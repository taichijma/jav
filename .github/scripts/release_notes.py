#!/usr/bin/env python3
"""Build GitHub Release notes from pull requests merged since the previous tag."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from urllib.parse import quote

SEMVER_RE = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$")
PR_URL_RE = re.compile(r"https://github\.com/[^/\s)]+/[^/\s)]+/pull/(\d+)")
MERGE_RE = re.compile(r"^Merge pull request #(\d+)\b")
SQUASH_RE = re.compile(r"\(#(\d+)\)\s*$")
COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)
BEGIN = "<!-- CURSOR_AGENT_PR_BODY_BEGIN -->"
END = "<!-- CURSOR_AGENT_PR_BODY_END -->"
BODY_LIMIT = 12000
IGNORE_LABEL = "ignore-for-release"


class CommandError(RuntimeError):
    pass


@dataclass(frozen=True)
class PullRequest:
    number: int
    title: str
    body: str
    author: str
    url: str
    labels: tuple[str, ...] = ()


def run(cmd: list[str], cwd: str | None = None) -> str:
    proc = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, check=False)
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        program = " ".join(cmd[:3])
        raise CommandError(f"{program} failed ({proc.returncode}): {detail}")
    return proc.stdout


def clean_body(body: str) -> str:
    text = (body or "").replace("\r\n", "\n")
    if BEGIN in text:
        text = text.split(BEGIN, 1)[1]
        if END in text:
            text = text.split(END, 1)[0]
    text = COMMENT_RE.sub("", text)
    kept: list[str] = []
    for line in text.split("\n"):
        stripped = line.strip()
        if stripped.startswith("<") and stripped.endswith(">") and not re.fullmatch(r"<https?://[^>]+>", stripped):
            continue
        kept.append(line.rstrip())
    text = "\n".join(kept).strip()
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text


def bound_text(text: str, limit: int = BODY_LIMIT) -> str:
    if len(text) <= limit:
        return text
    return text[:limit].rstrip() + "\n\n（说明已截断）"


def nest_headings(text: str, base: int = 4) -> str:
    """Shift Markdown headings so they sit under the pull-request heading.

    Lines inside fenced code blocks are left unchanged.
    """
    lines = text.split("\n")
    in_fence = False
    heading_indexes: list[int] = []
    for index, line in enumerate(lines):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if re.match(r"^(#{1,6})\s+\S", line):
            heading_indexes.append(index)
    if not heading_indexes:
        return text
    min_level = min(len(re.match(r"^(#+)", lines[index]).group(1)) for index in heading_indexes)
    shift = max(0, base - min_level)
    if shift == 0:
        return text
    for index in heading_indexes:
        match = re.match(r"^(#{1,6})(\s+\S.*)$", lines[index])
        if match is None:
            continue
        level = min(6, len(match.group(1)) + shift)
        lines[index] = ("#" * level) + match.group(2)
    return "\n".join(lines)


def pr_numbers_from_text(text: str) -> list[int]:
    seen: list[int] = []
    for match in PR_URL_RE.finditer(text or ""):
        number = int(match.group(1))
        if number not in seen:
            seen.append(number)
    return seen


def pr_numbers_from_commits(messages: list[str]) -> list[int]:
    seen: list[int] = []
    for message in messages:
        subject = (message or "").splitlines()[0] if message else ""
        match = MERGE_RE.search(subject) or SQUASH_RE.search(subject)
        if match is None:
            continue
        number = int(match.group(1))
        if number not in seen:
            seen.append(number)
    return seen


def previous_release_tag(tag: str, sha: str, cwd: str | None = None) -> str | None:
    out = run(["git", "tag", "-l", "v*.*.*", "--merged", sha, "--sort=-v:refname"], cwd=cwd)
    for line in out.splitlines():
        name = line.strip()
        if name and name != tag and SEMVER_RE.fullmatch(name):
            return name
    return None


def commit_messages(previous: str | None, sha: str, cwd: str | None = None) -> list[str]:
    spec = f"{previous}..{sha}" if previous else sha
    out = run(["git", "log", "--format=%B%x1e", spec], cwd=cwd)
    return [part.strip("\n") for part in out.split("\x1e") if part.strip()]


def fetch_generated_notes(repo: str, tag: str, sha: str, previous: str | None) -> str:
    cmd = [
        "gh",
        "api",
        "--method",
        "POST",
        f"/repos/{repo}/releases/generate-notes",
        "-f",
        f"tag_name={tag}",
        "-f",
        f"target_commitish={sha}",
    ]
    if previous:
        cmd.extend(["-f", f"previous_tag_name={previous}"])
    payload = json.loads(run(cmd))
    return str(payload.get("body") or "")


def fetch_pull_requests(repo: str, numbers: list[int]) -> dict[int, PullRequest]:
    if not numbers:
        return {}
    owner, name = repo.split("/", 1)
    found: dict[int, PullRequest] = {}
    for start in range(0, len(numbers), 40):
        chunk = numbers[start : start + 40]
        fields = "\n".join(
            f"pr{number}: pullRequest(number: {number}) "
            "{ number title body url author { login } labels(first: 30) { nodes { name } } }"
            for number in chunk
        )
        query = (
            "query($owner: String!, $name: String!) { "
            f"repository(owner: $owner, name: $name) {{ {fields} }} }}"
        )
        raw = run(
            [
                "gh",
                "api",
                "graphql",
                "-f",
                f"query={query}",
                "-f",
                f"owner={owner}",
                "-f",
                f"name={name}",
            ]
        )
        repository = json.loads(raw)["data"]["repository"]
        for number in chunk:
            node = repository.get(f"pr{number}")
            if not node:
                continue
            author = ((node.get("author") or {}).get("login")) or ""
            labels = tuple(
                str(item.get("name") or "")
                for item in ((node.get("labels") or {}).get("nodes") or [])
                if item.get("name")
            )
            found[number] = PullRequest(
                number=int(node["number"]),
                title=" ".join(str(node.get("title") or "").split()),
                body=str(node.get("body") or ""),
                author=author,
                url=str(node.get("url") or ""),
                labels=labels,
            )
    return found


def visible_pull_requests(
    numbers: list[int], found: dict[int, PullRequest]
) -> tuple[list[PullRequest], list[int]]:
    pull_requests: list[PullRequest] = []
    missing: list[int] = []
    for number in numbers:
        pull_request = found.get(number)
        if pull_request is None:
            missing.append(number)
            continue
        if IGNORE_LABEL in pull_request.labels:
            continue
        pull_requests.append(pull_request)
    return pull_requests, missing


def compare_url(repo: str, previous: str, tag: str) -> str:
    return (
        f"https://github.com/{repo}/compare/"
        f"{quote(previous, safe='')}...{quote(tag, safe='')}"
    )


def render_notes(
    *,
    tag: str,
    previous: str | None,
    pull_requests: list[PullRequest],
    missing_numbers: list[int],
    generated: str,
    repo: str,
    body_limit: int = BODY_LIMIT,
) -> str:
    lines: list[str] = ["## 改进说明", ""]
    if previous:
        lines.append(f"自 `{previous}` 至 `{tag}` 合并的 Pull Request：")
    else:
        lines.append(f"`{tag}` 包含的已合并 Pull Request（还没有更早的版本标签）：")
    lines.append("")
    if not pull_requests and not missing_numbers:
        lines.append("此范围内没有关联的 Pull Request。")
        lines.append("")
    for pr in pull_requests:
        lines.append(f"### #{pr.number} {pr.title}")
        lines.append("")
        author = f"@{pr.author}" if pr.author else "未知作者"
        lines.append(f"- 作者：{author}")
        if pr.url:
            lines.append(f"- 链接：{pr.url}")
        lines.append("")
        body = bound_text(nest_headings(clean_body(pr.body)), body_limit)
        lines.append(body or "（此 PR 未填写说明。）")
        lines.append("")
    for number in missing_numbers:
        lines.append(f"### #{number}")
        lines.append("")
        lines.append("未能读取该 Pull Request 的说明。标题见下方变更列表。")
        lines.append("")
    generated = (generated or "").strip()
    if generated:
        lines.extend(
            [
                "## 变更列表",
                "",
                "以下为 GitHub 按标签范围汇总的 Pull Request、贡献者与完整对比。",
                "",
                generated,
                "",
            ]
        )
    elif previous and repo:
        lines.append(f"**完整变更对比：** {compare_url(repo, previous, tag)}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def build_notes(tag: str, repo: str, sha: str, cwd: str | None = None) -> str:
    if not repo or "/" not in repo:
        raise CommandError("repo must look like owner/name")
    previous = previous_release_tag(tag, sha, cwd=cwd)
    generated = ""
    numbers: list[int] = []
    try:
        generated = fetch_generated_notes(repo, tag, sha, previous)
        numbers = pr_numbers_from_text(generated)
    except CommandError as exc:
        print(f"warning: generate-notes unavailable, using git history ({exc})", file=sys.stderr)
    if not numbers:
        numbers = pr_numbers_from_commits(commit_messages(previous, sha, cwd=cwd))
    found = fetch_pull_requests(repo, numbers) if numbers else {}
    pull_requests, missing = visible_pull_requests(numbers, found)
    return render_notes(
        tag=tag,
        previous=previous,
        pull_requests=pull_requests,
        missing_numbers=missing,
        generated=generated,
        repo=repo,
    )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Write release notes for a version tag to stdout.")
    parser.add_argument("--tag", required=True, help="Version tag, for example v1.2.3")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""), help="owner/name")
    parser.add_argument("--sha", default=os.environ.get("GITHUB_SHA", "HEAD"), help="Commit the tag points at")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    repo = args.repo.strip()
    if not repo:
        repo = run(["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"]).strip()
    sha = args.sha
    if sha == "HEAD":
        sha = run(["git", "rev-parse", "HEAD"]).strip()
    sys.stdout.write(build_notes(args.tag, repo, sha))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CommandError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
