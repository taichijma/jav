#!/usr/bin/env bash
# Remove javcli binaries. Config and installed skill copies require --yes.
# stdout: one JSON object. Progress goes to stderr.
set -euo pipefail

dry_run="false"
do_config="false"
do_skill="false"
skill_root=""
confirmed="false"
prefixes=()

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
Usage: uninstall.sh [--dry-run] [--prefix DIR] [--config] [--skill DIR] [--yes]

  --dry-run     Report what would be removed. Does not delete.
  --prefix DIR  Also check DIR/javcli and DIR/javcli.exe. Repeatable.
  --config      Remove $XDG_CONFIG_HOME/jav or ~/.config/jav. Requires --yes.
  --skill DIR   Remove DIR/javcli. DIR is the skills root this agent loads.
                Requires --yes. Does not remove the copy shipped in the repo.
  --yes         Allow --config and --skill to delete.

Standard binary locations are always checked. A file is removed only when
its --help text contains JavDB. stdout is one JSON object.
EOF
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

canon_existing() {
  local p="$1"
  if [[ -e "${p}" ]]; then
    printf '%s/%s\n' "$(cd "$(dirname "${p}")" && pwd)" "$(basename "${p}")"
  else
    printf '%s\n' "${p}"
  fi
}

add_candidate() {
  local p="$1"
  local existing key
  [[ -n "${p}" ]] || return 0
  key="$(canon_existing "${p}")"
  if [[ ${#candidates[@]} -gt 0 ]]; then
    for existing in "${candidates[@]}"; do
      [[ "${existing}" == "${key}" ]] && return 0
    done
  fi
  candidates+=("${key}")
}

config_dir() {
  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
    printf '%s/jav\n' "${XDG_CONFIG_HOME}"
  else
    printf '%s/.config/jav\n' "${HOME}"
  fi
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run="true"
      shift
      ;;
    --prefix)
      [[ $# -ge 2 ]] || fail "--prefix requires a directory" 2
      prefixes+=("$2")
      shift 2
      ;;
    --config)
      do_config="true"
      shift
      ;;
    --skill)
      [[ $# -ge 2 && "$2" != --* ]] || fail "--skill requires the skills directory this agent uses" 2
      skill_root="$2"
      do_skill="true"
      shift 2
      ;;
    --yes)
      confirmed="true"
      shift
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

command -v python3 >/dev/null 2>&1 || fail "python3 is required"

if [[ "${dry_run}" == "false" && "${confirmed}" == "false" && ( "${do_config}" == "true" || "${do_skill}" == "true" ) ]]; then
  fail "--config and --skill require --yes (or use --dry-run first)" 2
fi

cfg="$(config_dir)"
case "${cfg}" in
  /*/jav) ;;
  *) fail "refusing suspicious config directory: ${cfg}" ;;
esac

candidates=()
if [[ ${#prefixes[@]} -gt 0 ]]; then
  for prefix in "${prefixes[@]}"; do
    add_candidate "${prefix}/javcli"
    add_candidate "${prefix}/javcli.exe"
  done
fi
if command -v javcli >/dev/null 2>&1; then
  add_candidate "$(command -v javcli)"
fi
if command -v javcli.exe >/dev/null 2>&1; then
  add_candidate "$(command -v javcli.exe)"
fi
add_candidate "${HOME}/.local/bin/javcli"
add_candidate "/usr/local/bin/javcli"
add_candidate "/usr/bin/javcli"
if command -v go >/dev/null 2>&1; then
  gobin="$(go env GOBIN 2>/dev/null || true)"
  gopath="$(go env GOPATH 2>/dev/null || true)"
  if [[ -n "${gobin}" ]]; then
    add_candidate "${gobin}/javcli"
  elif [[ -n "${gopath}" ]]; then
    add_candidate "${gopath}/bin/javcli"
  fi
fi

verified=()
skipped=()
if [[ ${#candidates[@]} -gt 0 ]]; then
  for candidate in "${candidates[@]}"; do
    if [[ ! -e "${candidate}" ]]; then
      continue
    fi
    if is_javcli "${candidate}"; then
      verified+=("${candidate}")
    else
      skipped+=("${candidate}")
    fi
  done
fi

config_exists="false"
removed_config="false"
errors=()
if [[ -d "${cfg}" ]]; then
  config_exists="true"
fi

if [[ "${do_config}" == "true" && "${config_exists}" == "true" ]]; then
  unexpected=()
  while IFS= read -r entry; do
    base="$(basename "${entry}")"
    case "${base}" in
      config.json|config.json.tmp.*) ;;
      *) unexpected+=("${base}") ;;
    esac
  done < <(find "${cfg}" -mindepth 1 -maxdepth 1)
  if [[ ${#unexpected[@]} -gt 0 ]]; then
    errors+=("config directory has unexpected files; not deleting ${cfg}")
  fi
fi

copies=()
if [[ "${do_skill}" == "true" ]]; then
  if [[ -d "${skill_root}" ]]; then
    skill_root="$(cd "${skill_root}" && pwd)"
    skill_copy="${skill_root}/javcli"
    source_skill="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if [[ -d "${skill_copy}" ]]; then
      skill_copy="$(cd "${skill_copy}" && pwd)"
      if [[ "${skill_copy}" == "${source_skill}" ]]; then
        errors+=("refusing to remove the skill shipped in the repository: ${skill_copy}")
      elif is_javcli_skill "${skill_copy}"; then
        copies+=("${skill_copy}")
      else
        errors+=("${skill_copy} is not the javcli skill")
      fi
    fi
  fi
fi

removed=()
if [[ ${#errors[@]} -eq 0 && "${dry_run}" == "false" && ${#verified[@]} -gt 0 ]]; then
  errfile="$(mktemp)"
  for bin in "${verified[@]}"; do
    if rm -f "${bin}" 2>"${errfile}"; then
      removed+=("${bin}")
    else
      errors+=("failed to remove ${bin}: $(tr '\n' ' ' <"${errfile}")")
    fi
  done
  rm -f "${errfile}"
fi

if [[ ${#errors[@]} -eq 0 && "${do_config}" == "true" && "${config_exists}" == "true" && "${dry_run}" == "false" ]]; then
  if rm -rf "${cfg}"; then
    removed_config="true"
    config_exists="false"
  else
    errors+=("failed to remove ${cfg}")
  fi
fi

removed_skills=()
if [[ ${#errors[@]} -eq 0 && "${do_skill}" == "true" && "${dry_run}" == "false" && ${#copies[@]} -gt 0 ]]; then
  for skill_dir in "${copies[@]}"; do
    if rm -rf "${skill_dir}"; then
      removed_skills+=("${skill_dir}")
    else
      errors+=("failed to remove ${skill_dir}")
    fi
  done
fi

env_names=()
for name in JAVDB_COOKIES SOCKS5_PROXY JAVDB_LOCALE JAVDB_BASE_URL JAVDB_TLS_INSECURE; do
  if [[ -n "${!name:-}" ]]; then
    env_names+=("${name}")
  fi
done

report="$(mktemp -d)"
write_lines() {
  local file="$1"
  shift
  : >"${file}"
  local item
  for item in "$@"; do
    printf '%s\n' "${item}" >>"${file}"
  done
}
write_lines "${report}/binaries"
write_lines "${report}/removed"
write_lines "${report}/skipped"
write_lines "${report}/errors"
write_lines "${report}/skills"
write_lines "${report}/removed_skills"
write_lines "${report}/env"
if [[ ${#verified[@]} -gt 0 ]]; then
  write_lines "${report}/binaries" "${verified[@]}"
fi
if [[ ${#removed[@]} -gt 0 ]]; then
  write_lines "${report}/removed" "${removed[@]}"
fi
if [[ ${#skipped[@]} -gt 0 ]]; then
  write_lines "${report}/skipped" "${skipped[@]}"
fi
if [[ ${#errors[@]} -gt 0 ]]; then
  write_lines "${report}/errors" "${errors[@]}"
fi
if [[ ${#copies[@]} -gt 0 ]]; then
  write_lines "${report}/skills" "${copies[@]}"
fi
if [[ ${#removed_skills[@]} -gt 0 ]]; then
  write_lines "${report}/removed_skills" "${removed_skills[@]}"
fi
if [[ ${#env_names[@]} -gt 0 ]]; then
  write_lines "${report}/env" "${env_names[@]}"
fi

set +e
python3 - "${report}" "${dry_run}" "${cfg}" "${config_exists}" "${do_config}" "${removed_config}" "${do_skill}" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
dry_run, cfg, config_exists, do_config, removed_config, do_skill = sys.argv[2:]

def lines(name):
    text = (root / name).read_text(encoding="utf-8")
    return [line for line in text.splitlines() if line]

errors = lines("errors")
payload = {
    "ok": not errors,
    "dry_run": dry_run == "true",
    "binaries": lines("binaries"),
    "removed_binaries": lines("removed"),
    "skipped_binaries": lines("skipped"),
    "remove_errors": errors,
    "config_dir": cfg,
    "config_exists": config_exists == "true",
    "config_requested": do_config == "true",
    "removed_config": removed_config == "true",
    "skill_copies": lines("skills"),
    "skill_requested": do_skill == "true",
    "removed_skills": lines("removed_skills"),
    "env_still_set": lines("env"),
}
print(json.dumps(payload, ensure_ascii=False))
sys.exit(0 if payload["ok"] else 1)
PY
status=$?
set -e
rm -rf "${report}"
exit "${status}"
