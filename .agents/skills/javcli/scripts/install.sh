#!/usr/bin/env bash
# Install javcli from a GitHub Release or from source.
# stdout: one JSON object. Progress and command logs go to stderr.
set -euo pipefail

REPO_SLUG="0xtaichim/jav"
REPO_WEB="https://github.com/${REPO_SLUG}"
REPO_GIT="${REPO_WEB}.git"
API_ROOT="https://api.github.com/repos/${REPO_SLUG}"

prefix="${HOME}/.local/bin"
src=""
mode="auto"
release_tag=""
skills_dir="${AGENT_SKILLS_DIR:-}"
skill_src=""
skill_dest=""
stage=""
clone_root=""
work=""

cleanup() {
  if [[ -n "${stage}" && -f "${stage}" ]]; then
    rm -f "${stage}"
  fi
  if [[ -n "${clone_root}" && -d "${clone_root}" ]]; then
    rm -rf "${clone_root}"
  fi
  if [[ -n "${work}" && -d "${work}" ]]; then
    rm -rf "${work}"
  fi
}
trap cleanup EXIT

fail() {
  local msg="$1"
  local code="${2:-1}"
  printf '%s\n' "${msg}" >&2
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.dumps({"ok": False, "error": sys.argv[1]}, ensure_ascii=False))' "${msg}"
  else
    printf '{"ok":false,"error":"python3 is required"}\n'
  fi
  exit "${code}"
}

usage() {
  cat <<'EOF'
Usage: install.sh [--prefix DIR] [--release [TAG]] [--source] [--src DIR]

  --prefix DIR       Binary directory. Default: $HOME/.local/bin
  --release [TAG]    Download a GitHub Release. Omit TAG for the latest.
  --source           Build from source. Clone if no checkout is found.
  --src DIR          Build this checkout. Not valid with --release.
  --skills-dir DIR   Copy this skill to DIR/javcli. DIR is the skills root
                     the current agent already loads. Defaults to
                     AGENT_SKILLS_DIR when that variable is set.

With no mode flag, the latest GitHub Release is installed.
Pass --source to build a checkout, or --src DIR to build that checkout.

stdout is one JSON object. Progress is on stderr.
EOF
}

require_python() {
  command -v python3 >/dev/null 2>&1 || fail "python3 is required"
}

require_go() {
  command -v go >/dev/null 2>&1 || fail "Go 1.24 or newer is required (https://go.dev/dl/)"
  local raw major minor
  raw="$(go env GOVERSION 2>/dev/null || true)"
  if [[ ! "${raw}" =~ go([0-9]+)\.([0-9]+) ]]; then
    raw="$(go version 2>/dev/null || true)"
  fi
  if [[ ! "${raw}" =~ go([0-9]+)\.([0-9]+) ]]; then
    fail "cannot parse Go version: ${raw}"
  fi
  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  if (( major < 1 || (major == 1 && minor < 24) )); then
    fail "Go 1.24 or newer is required, found ${raw}"
  fi
}

find_module() {
  local start="$1"
  local dir
  [[ -d "${start}" ]] || return 1
  dir="$(cd "${start}" && pwd)"
  while true; do
    if [[ -f "${dir}/go.mod" ]] && grep -q -E '^module[[:space:]]+github.com/taichi/javcli[[:space:]]*$' "${dir}/go.mod"; then
      printf '%s\n' "${dir}"
      return 0
    fi
    [[ "${dir}" == "/" ]] && return 1
    dir="$(dirname "${dir}")"
  done
}

is_javcli() {
  local bin="$1"
  local help
  [[ -f "${bin}" && -x "${bin}" ]] || return 1
  if command -v timeout >/dev/null 2>&1; then
    help="$(timeout 5 "${bin}" --help 2>&1)" || return 1
  else
    help="$("${bin}" --help 2>&1)" || return 1
  fi
  [[ "${help}" == *"JavDB"* ]]
}

host_goos() {
  case "$(uname -s)" in
    Linux) printf 'linux\n' ;;
    Darwin) printf 'darwin\n' ;;
    MINGW*|MSYS*|CYGWIN*) printf 'windows\n' ;;
    *) return 1 ;;
  esac
}

host_goarch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'amd64\n' ;;
    aarch64|arm64) printf 'arm64\n' ;;
    *) return 1 ;;
  esac
}

emit_ok() {
  local binary="$1"
  local method="$2"
  local source="$3"
  local on_path="$4"
  local path_hint="$5"
  local version_json="$6"
  local skill_path="$7"
  python3 - "${binary}" "${method}" "${source}" "${on_path}" "${path_hint}" "${version_json}" "${skill_path}" <<'PY'
import json
import sys

binary, method, source, on_path, hint, version_raw, skill_path = sys.argv[1:]
try:
    version = json.loads(version_raw)
except json.JSONDecodeError as exc:
    print(json.dumps({"ok": False, "error": "version command did not return JSON: %s" % exc}, ensure_ascii=False))
    sys.exit(1)
if not isinstance(version, dict):
    print(json.dumps({"ok": False, "error": "version command did not return an object"}, ensure_ascii=False))
    sys.exit(1)
print(json.dumps({
    "ok": True,
    "method": method,
    "binary": binary,
    "source": source,
    "on_path": on_path == "true",
    "path_hint": hint,
    "version": version.get("version", ""),
    "commit": version.get("commit", ""),
    "date": version.get("date", ""),
    "skill_path": skill_path or None,
}, ensure_ascii=False))
PY
}

is_javcli_skill() {
  local dir="$1"
  [[ -f "${dir}/SKILL.md" ]] || return 1
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit found ? 0 : 1 }
    fm && $0 ~ /^name:[[:space:]]*javcli[[:space:]]*$/ { found = 1 }
    END { exit found ? 0 : 1 }
  ' "${dir}/SKILL.md"
}

prepare_skill_dest() {
  [[ -n "${skills_dir}" ]] || return 0
  skill_src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  mkdir -p "${skills_dir}" || fail "cannot create ${skills_dir}"
  skills_dir="$(cd "${skills_dir}" && pwd)" || fail "cannot open ${skills_dir}"
  skill_dest="${skills_dir}/javcli"
  if [[ "${skill_dest}" == "${skill_src}" ]]; then
    fail "refusing to copy the skill onto its source at ${skill_src}"
  fi
  if [[ -e "${skill_dest}" ]] && ! is_javcli_skill "${skill_dest}"; then
    fail "refusing to overwrite ${skill_dest} because it is not the javcli skill"
  fi
}

prepare_dest() {
  local goos="$1"
  mkdir -p "${prefix}" || fail "cannot create ${prefix}"
  prefix="$(cd "${prefix}" && pwd)" || fail "cannot open ${prefix}"
  if [[ "${goos}" == "windows" ]]; then
    dest="${prefix}/javcli.exe"
  else
    dest="${prefix}/javcli"
  fi
  if [[ -e "${dest}" ]] && ! is_javcli "${dest}"; then
    fail "refusing to overwrite ${dest} because it is not javcli"
  fi
  stage="$(mktemp "${prefix}/.javcli.XXXXXX")" || fail "cannot create a temporary file in ${prefix}"
}

finish_install() {
  local method="$1"
  local source="$2"
  local version_json on_path path_hint found found_canon
  local skill_path=""
  chmod 755 "${stage}"
  if ! is_javcli "${stage}"; then
    fail "binary failed the javcli --help check"
  fi
  if [[ -n "${skill_dest}" ]]; then
    rm -rf "${skill_dest}"
    cp -a "${skill_src}" "${skill_dest}" || fail "failed to copy the skill to ${skill_dest}"
    skill_path="${skill_dest}"
  fi
  mv -f "${stage}" "${dest}"
  stage=""
  version_json="$("${dest}" version 2>/dev/null)" || fail "javcli version failed"
  on_path="false"
  path_hint=""
  if command -v javcli >/dev/null 2>&1; then
    found="$(command -v javcli)"
    found_canon="$(cd "$(dirname "${found}")" && pwd)/$(basename "${found}")"
    if [[ "${found_canon}" == "${dest}" ]]; then
      on_path="true"
    else
      path_hint="PATH already contains another javcli at ${found_canon}. Installed ${dest}."
    fi
  fi
  if [[ "${on_path}" == "false" && -z "${path_hint}" ]]; then
    path_hint="export PATH=\"${prefix}:\$PATH\""
  fi
  emit_ok "${dest}" "${method}" "${source}" "${on_path}" "${path_hint}" "${version_json}" "${skill_path}"
}

install_from_source() {
  local module_dir="$1"
  local goos
  require_go
  goos="$(host_goos)" || fail "unsupported operating system: $(uname -s)"
  prepare_dest "${goos}"
  printf 'building %s\n' "${module_dir}" >&2
  (
    cd "${module_dir}"
    CGO_ENABLED=0 go build -trimpath -o "${stage}" .
  ) >&2 || fail "go build failed"
  finish_install "source" "${module_dir}"
}

install_from_release() {
  local tag="$1"
  local goos goarch asset_name asset_url sums_url archive digest
  command -v curl >/dev/null 2>&1 || fail "curl is required to download a release"
  goos="$(host_goos)" || fail "unsupported operating system: $(uname -s)"
  goarch="$(host_goarch)" || fail "unsupported architecture: $(uname -m)"
  prepare_dest "${goos}"
  work="$(mktemp -d)"
  if [[ -n "${tag}" ]]; then
    printf 'fetching release %s\n' "${tag}" >&2
    curl -fsSL --retry 3 --retry-delay 1 -A javcli-install \
      -H "Accept: application/vnd.github+json" \
      -o "${work}/release.json" \
      "${API_ROOT}/releases/tags/${tag}" >&2 || fail "release ${tag} was not found at ${REPO_WEB}/releases"
  else
    printf 'fetching latest release\n' >&2
    curl -fsSL --retry 3 --retry-delay 1 -A javcli-install \
      -H "Accept: application/vnd.github+json" \
      -o "${work}/release.json" \
      "${API_ROOT}/releases/latest" >&2 || fail "no GitHub Release found at ${REPO_WEB}/releases; rerun with --source"
  fi
  python3 - "${work}/release.json" "${goos}" "${goarch}" >"${work}/selection" <<'PY' || fail "failed to read release metadata"
import json
import sys

path, goos, goarch = sys.argv[1:]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
if not isinstance(data, dict) or "tag_name" not in data:
    message = data.get("message") if isinstance(data, dict) else "invalid release metadata"
    print(message or "invalid release metadata", file=sys.stderr)
    sys.exit(1)
tag = data["tag_name"]
suffix = ".zip" if goos == "windows" else ".tar.gz"
asset = "javcli_%s_%s_%s%s" % (tag, goos, goarch, suffix)
urls = {item.get("name"): item.get("browser_download_url") for item in data.get("assets") or []}
if not urls.get(asset) or not urls.get("SHA256SUMS"):
    print("release %s has no %s or SHA256SUMS" % (tag, asset), file=sys.stderr)
    sys.exit(1)
print(tag)
print(asset)
print(urls[asset])
print(urls["SHA256SUMS"])
PY
  tag="$(sed -n '1p' "${work}/selection")"
  asset_name="$(sed -n '2p' "${work}/selection")"
  asset_url="$(sed -n '3p' "${work}/selection")"
  sums_url="$(sed -n '4p' "${work}/selection")"
  [[ -n "${tag}" && -n "${asset_name}" && -n "${asset_url}" && -n "${sums_url}" ]] || fail "failed to read release metadata"
  printf 'downloading %s\n' "${asset_name}" >&2
  curl -fsSL --retry 3 --retry-delay 1 -A javcli-install -o "${work}/${asset_name}" "${asset_url}" >&2 \
    || fail "failed to download ${asset_url}"
  curl -fsSL --retry 3 --retry-delay 1 -A javcli-install -o "${work}/SHA256SUMS" "${sums_url}" >&2 \
    || fail "failed to download ${sums_url}"
  archive="${work}/${asset_name}"
  if command -v sha256sum >/dev/null 2>&1; then
    digest="$(sha256sum "${archive}" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    digest="$(shasum -a 256 "${archive}" | awk '{print $1}')"
  else
    fail "sha256sum or shasum is required to verify the release"
  fi
  python3 - "${work}/SHA256SUMS" "${asset_name}" "${digest}" <<'PY' || fail "SHA256 mismatch for ${asset_name}"
import sys

sums, name, got = sys.argv[1:]
with open(sums, encoding="utf-8") as fh:
    for raw in fh:
        parts = raw.split()
        if len(parts) < 2:
            continue
        filename = parts[-1][2:] if parts[-1].startswith("./") else parts[-1]
        if filename == name and parts[0].lower() == got.lower():
            sys.exit(0)
sys.exit(1)
PY
  python3 - "${archive}" "${work}" "${goos}" <<'PY' || fail "release archive did not contain the expected binary"
import sys
import tarfile
import zipfile

archive, dest, goos = sys.argv[1:]
if goos == "windows":
    with zipfile.ZipFile(archive) as zf:
        names = [name for name in zf.namelist() if name not in ("", "/", "./")]
        if names != ["javcli.exe"]:
            sys.exit(1)
        info = zf.getinfo("javcli.exe")
        if info.is_dir():
            sys.exit(1)
        zf.extract("javcli.exe", dest)
else:
    with tarfile.open(archive, "r:gz") as tf:
        members = [member for member in tf.getmembers() if member.name not in (".", "./")]
        if len(members) != 1 or members[0].name not in ("javcli", "./javcli") or not members[0].isfile():
            sys.exit(1)
        members[0].name = "javcli"
        kwargs = {}
        if sys.version_info >= (3, 12):
            kwargs["filter"] = "data"
        tf.extract(members[0], dest, **kwargs)
PY
  if [[ "${goos}" == "windows" ]]; then
    cp "${work}/javcli.exe" "${stage}"
  else
    cp "${work}/javcli" "${stage}"
  fi
  finish_install "release" "${asset_url}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || fail "--prefix requires a directory" 2
      prefix="$2"
      shift 2
      ;;
    --src)
      [[ $# -ge 2 ]] || fail "--src requires a directory" 2
      src="$2"
      shift 2
      ;;
    --skills-dir)
      [[ $# -ge 2 ]] || fail "--skills-dir requires the skills directory this agent uses" 2
      skills_dir="$2"
      shift 2
      ;;
    --source)
      [[ "${mode}" == "auto" ]] || fail "--source cannot be combined with --release" 2
      mode="source"
      shift
      ;;
    --release)
      [[ "${mode}" == "auto" ]] || fail "--release cannot be combined with --source" 2
      mode="release"
      if [[ $# -ge 2 && "$2" != --* ]]; then
        release_tag="$2"
        if [[ ! "${release_tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
          fail "release tag must look like v1.2.3 or v1.2.3-rc.1" 2
        fi
        shift 2
      else
        shift
      fi
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1" 2
      ;;
  esac
done

if [[ -n "${src}" && "${mode}" == "release" ]]; then
  fail "--src cannot be combined with --release" 2
fi

require_python
prepare_skill_dest

if [[ "${mode}" == "source" || -n "${src}" ]]; then
  source_dir=""
  if [[ -n "${src}" ]]; then
    source_dir="$(find_module "${src}")" || fail "--src is not a javcli checkout (module github.com/taichi/javcli)"
  elif source_dir="$(find_module "${PWD}")"; then
    :
  else
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if ! source_dir="$(find_module "${script_dir}")"; then
      command -v git >/dev/null 2>&1 || fail "git is required to clone ${REPO_GIT}"
      clone_root="$(mktemp -d)"
      printf 'cloning %s\n' "${REPO_GIT}" >&2
      GIT_TERMINAL_PROMPT=0 git clone --depth 1 "${REPO_GIT}" "${clone_root}/jav" >&2 || fail "git clone failed"
      source_dir="${clone_root}/jav"
    fi
  fi
  install_from_source "${source_dir}"
else
  install_from_release "${release_tag}"
fi
