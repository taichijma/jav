import subprocess
import tempfile
import unittest

import release_notes


class CleanBodyTest(unittest.TestCase):
    def test_extracts_cursor_pr_body_and_drops_footer(self):
        raw = """<!-- CURSOR_AGENT_PR_BODY_BEGIN -->
## 变更

- 解析带密码的 SOCKS5 地址

<!-- CURSOR_AGENT_PR_BODY_END -->

<div><a href="https://cursor.com/agents/abc">View agent</a></div>
"""
        self.assertEqual(release_notes.clean_body(raw), "## 变更\n\n- 解析带密码的 SOCKS5 地址")

    def test_strips_html_comments_and_blank_html_lines(self):
        raw = "说明\n<!-- hidden -->\n<div>footer</div>\n\n\n保留"
        self.assertEqual(release_notes.clean_body(raw), "说明\n\n保留")

    def test_keeps_autolink(self):
        self.assertEqual(release_notes.clean_body("见 <https://example.com>"), "见 <https://example.com>")


class PullRequestNumbersTest(unittest.TestCase):
    def test_generated_notes_keep_order_and_drop_duplicates(self):
        text = """## What's Changed
* First by @a in https://github.com/acme/jav/pull/4
* Second by @b in https://github.com/acme/jav/pull/4
* Third by @c in https://github.com/acme/jav/pull/2
"""
        self.assertEqual(release_notes.pr_numbers_from_text(text), [4, 2])

    def test_commit_subjects(self):
        messages = [
            "Merge pull request #5 from acme/topic\n\nbody mentions (#9)",
            "Support SOCKS5 username/password authentication. (#3)",
            "Mention #8 in the subject but not as a squash suffix",
            "Merge branch 'main'",
        ]
        self.assertEqual(release_notes.pr_numbers_from_commits(messages), [5, 3])


class NestHeadingsTest(unittest.TestCase):
    def test_shifts_headings_and_keeps_code_fences(self):
        text = "## 变更\n\n```bash\n# not a heading\n```\n\n### 细节\n"
        nested = release_notes.nest_headings(text)
        self.assertIn("#### 变更", nested)
        self.assertIn("##### 细节", nested)
        self.assertIn("# not a heading", nested)
        self.assertNotIn("\n## 变更", "\n" + nested)


class VisiblePullRequestsTest(unittest.TestCase):
    def test_skips_ignored_label_and_reports_missing(self):
        found = {
            1: release_notes.PullRequest(1, "Keep", "", "octocat", "https://example.com/1"),
            2: release_notes.PullRequest(
                2, "Skip", "", "octocat", "https://example.com/2", ("ignore-for-release",)
            ),
        }
        pull_requests, missing = release_notes.visible_pull_requests([1, 2, 3], found)
        self.assertEqual([item.number for item in pull_requests], [1])
        self.assertEqual(missing, [3])


class RenderNotesTest(unittest.TestCase):
    def test_includes_pr_explanation_and_generated_list(self):
        notes = release_notes.render_notes(
            tag="v1.2.0",
            previous="v1.1.0",
            pull_requests=[
                release_notes.PullRequest(
                    number=5,
                    title="Fix ratings",
                    body="<!-- CURSOR_AGENT_PR_BODY_BEGIN -->\n## 说明\n\n评分字段已改正\n<!-- CURSOR_AGENT_PR_BODY_END -->",
                    author="octocat",
                    url="https://github.com/acme/jav/pull/5",
                )
            ],
            missing_numbers=[8],
            generated="## What's Changed\n* Fix ratings by @octocat in https://github.com/acme/jav/pull/5\n",
            repo="acme/jav",
        )
        self.assertIn("## 改进说明", notes)
        self.assertIn("自 `v1.1.0` 至 `v1.2.0`", notes)
        self.assertIn("### #5 Fix ratings", notes)
        self.assertIn("- 作者：@octocat", notes)
        self.assertIn("#### 说明", notes)
        self.assertIn("评分字段已改正", notes)
        self.assertNotIn("CURSOR_AGENT_PR_BODY", notes)
        self.assertNotRegex(notes, r"(?m)^## 说明")
        self.assertIn("### #8", notes)
        self.assertIn("## 变更列表", notes)
        self.assertIn("## What's Changed", notes)

    def test_truncates_long_body_and_links_compare_when_ungenerated(self):
        notes = release_notes.render_notes(
            tag="v1.2.3+build",
            previous="v1.2.2",
            pull_requests=[
                release_notes.PullRequest(1, "Title", "x" * 50, "octocat", "https://example.com/1")
            ],
            missing_numbers=[],
            generated="",
            repo="acme/jav",
            body_limit=10,
        )
        self.assertIn("xxxxxxxxxx", notes)
        self.assertIn("（说明已截断）", notes)
        self.assertIn("https://github.com/acme/jav/compare/v1.2.2...v1.2.3%2Bbuild", notes)

    def test_empty_range(self):
        notes = release_notes.render_notes(
            tag="v0.1.0",
            previous=None,
            pull_requests=[],
            missing_numbers=[],
            generated="",
            repo="acme/jav",
        )
        self.assertIn("还没有更早的版本标签", notes)
        self.assertIn("没有关联的 Pull Request", notes)


class PreviousTagTest(unittest.TestCase):
    def test_picks_newest_ancestor_semver_tag(self):
        with tempfile.TemporaryDirectory() as cwd:
            git = lambda *args, identity=False: _git(cwd, *args, identity=identity)
            git("init", "-b", "main")
            git("commit", "--allow-empty", "-m", "a", identity=True)
            git("tag", "v1.0.0")
            git("commit", "--allow-empty", "-m", "b", identity=True)
            git("tag", "v1.2")
            git("tag", "nightly")
            git("commit", "--allow-empty", "-m", "c", identity=True)
            git("tag", "v1.1.0")
            git("commit", "--allow-empty", "-m", "d", identity=True)
            git("tag", "v1.2.0-rc.1")
            sha = _rev(cwd, "HEAD")
            self.assertEqual(release_notes.previous_release_tag("v1.2.0-rc.1", sha, cwd=cwd), "v1.1.0")
            git("commit", "--allow-empty", "-m", "e", identity=True)
            git("tag", "v1.2.0")
            sha = _rev(cwd, "HEAD")
            self.assertEqual(release_notes.previous_release_tag("v1.2.0", sha, cwd=cwd), "v1.2.0-rc.1")

            git("checkout", "--orphan", "side")
            git("commit", "--allow-empty", "-m", "side", identity=True)
            git("tag", "v9.0.0")
            git("checkout", "main")
            sha = _rev(cwd, "HEAD")
            self.assertEqual(release_notes.previous_release_tag("v1.2.0", sha, cwd=cwd), "v1.2.0-rc.1")
            self.assertIsNone(release_notes.previous_release_tag("v1.0.0", _rev(cwd, "v1.0.0"), cwd=cwd))


def _git(cwd: str, *args: str, identity: bool = False) -> None:
    cmd = ["git", "-C", cwd]
    if identity:
        cmd.extend(["-c", "user.email=test@example.com", "-c", "user.name=Test"])
    cmd.extend(args)
    subprocess.run(cmd, check=True, capture_output=True, text=True)


def _rev(cwd: str, ref: str) -> str:
    return subprocess.check_output(["git", "-C", cwd, "rev-parse", ref], text=True).strip()


if __name__ == "__main__":
    unittest.main()
