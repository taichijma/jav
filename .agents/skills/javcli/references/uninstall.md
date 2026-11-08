# Uninstall javcli

Show the plan first. The script never prints config file contents.

```bash
bash scripts/uninstall.sh --help
bash scripts/uninstall.sh --dry-run
bash scripts/uninstall.sh --prefix "$HOME/.local/bin"
bash scripts/uninstall.sh --skill "$AGENT_SKILLS_DIR" --dry-run
bash scripts/uninstall.sh --config --yes
bash scripts/uninstall.sh --skill "$AGENT_SKILLS_DIR" --yes
```

| Flag | Effect |
| --- | --- |
| `--dry-run` | Report only. `--yes` is not required |
| `--prefix DIR` | Also check `DIR/javcli` and `DIR/javcli.exe`. Repeatable. The standard locations are always checked |
| `--config` | Remove `${XDG_CONFIG_HOME:-$HOME/.config}/jav`. Requires `--yes` unless this is a dry run |
| `--skill DIR` | Remove `DIR/javcli`. `DIR` is the same skill root used at install time. Requires `--yes` unless this is a dry run |
| `--yes` | Allow `--config` and `--skill` to delete |

## Binary

A file is removed only when its `--help` text contains `JavDB`. Candidates:

- `javcli` and `javcli.exe` under each `--prefix`
- `command -v javcli` and `command -v javcli.exe`
- `$HOME/.local/bin/javcli`
- `/usr/local/bin/javcli`
- `/usr/bin/javcli`
- `$(go env GOBIN)/javcli`, or `$(go env GOPATH)/bin/javcli` when `GOBIN` is empty

A same-named file that cannot be confirmed as javcli (not executable, or help text without `JavDB`) is listed in `skipped_binaries` and kept. If removal is denied, the path is listed in `remove_errors`. Files already removed are not restored. Do not add `sudo` unless the user asks.

## Config

`--config` deletes the whole config directory, which holds the cookie. If the directory contains anything other than `config.json` and `config.json.tmp.*`, this run deletes nothing and explains why in `remove_errors`.

To clear one key and keep the binary, do not delete the directory:

```bash
javcli config unset cookies
javcli config unset proxy
javcli config unset locale
```

`unset` does not print the removed value.

## Skill copy

The argument to `--skill` is the skill root used at install time. The script removes only `javcli` inside it, and only when `SKILL.md` frontmatter says `name: javcli`. A missing directory is treated as already removed. If that path is not this skill, this run deletes nothing and the reason is in `remove_errors`.

`.agents/skills/javcli` inside this repository is the skill source. `--skill` aimed at it is refused and the source stays in place.

## Environment variables

The script lists the names of variables that are still non-empty: `JAVDB_COOKIES`, `SOCKS5_PROXY`, `JAVDB_LOCALE`, `JAVDB_BASE_URL`, `JAVDB_TLS_INSECURE`. It does not print their values. When the user asks to drop them from shell config, delete the assignment lines without reading the values aloud. The script does not edit shell config and does not delete a git clone.

Delete a source checkout only after the user names the directory and confirms. `./javcli` in the repository is a gitignored build product. Remove it only when the user asks to clean the workspace.

## Output

The last stdout line:

```json
{
  "ok": true,
  "dry_run": true,
  "binaries": ["/home/user/.local/bin/javcli"],
  "removed_binaries": [],
  "skipped_binaries": [],
  "remove_errors": [],
  "config_dir": "/home/user/.config/jav",
  "config_exists": true,
  "config_requested": false,
  "removed_config": false,
  "skill_copies": [],
  "skill_requested": false,
  "removed_skills": [],
  "env_still_set": ["SOCKS5_PROXY"]
}
```

During `--dry-run`, every `removed_*` array is empty. `binaries` lists confirmed javcli files, which a real run would delete. Exit code 2 means `--yes` is missing or the arguments are wrong.
