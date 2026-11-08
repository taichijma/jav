# Install javcli

Script paths are relative to this skill directory. Progress is on stderr. The last stdout line is JSON.

The default is the latest GitHub Release. Build from source only when the user asks for this checkout or a release download is not possible.

```bash
bash scripts/install.sh
bash scripts/install.sh --prefix "$HOME/.local/bin"
bash scripts/install.sh --release v0.1.0
bash scripts/install.sh --source
bash scripts/install.sh --src /path/to/jav
bash scripts/install.sh --skills-dir "$AGENT_SKILLS_DIR"
```

| Flag | Effect |
| --- | --- |
| `--prefix DIR` | Binary directory. Default: `$HOME/.local/bin` |
| `--release [TAG]` | Download a GitHub Release. Omit TAG for the latest. Archives are named `javcli_<tag>_<os>_<arch>.tar.gz` (`.zip` on Windows) and checked against that Release's `SHA256SUMS` |
| `--source` | Compile a checkout. If none is found, shallow-clone `https://github.com/0xtaichim/jav.git` |
| `--src DIR` | Compile this checkout. Cannot be combined with `--release` |
| `--skills-dir DIR` | Copy this skill to `DIR/javcli`. `DIR` is the skill root this agent already loads. If omitted, `AGENT_SKILLS_DIR` is used. If neither is set, the skill is not copied |

`--release` cannot be combined with `--source` or `--src`.

A Release install needs `curl`, `python3`, and `sha256sum` or `shasum`. It does not need Go. A source build needs Go 1.24 or newer and `python3`. The script sets `CGO_ENABLED=0`.

Do not run either of these. The module path and the GitHub repository differ, so they do not install this program:

```bash
go install github.com/taichi/javcli@latest
go install github.com/0xtaichim/jav@latest
```

## Success JSON

```json
{
  "ok": true,
  "method": "release",
  "binary": "/home/user/.local/bin/javcli",
  "source": "https://github.com/taichijma/jav/releases/download/v0.1.0/javcli_v0.1.0_linux_amd64.tar.gz",
  "on_path": false,
  "path_hint": "export PATH=\"/home/user/.local/bin:$PATH\"",
  "version": "v0.1.0",
  "commit": "0123456789ab",
  "date": "2026-01-02T03:04:05Z",
  "skill_path": "/home/user/.agents/skills/javcli"
}
```

`method` is `release` or `source`. For a Release, `source` is the asset URL that was downloaded. `https://github.com/0xtaichim/jav` redirects, so the host in that URL may be the repository it redirects to. A source install reports `version` `dev`, `commit` `none`, and `date` `unknown` unless the binary was built with release ldflags. A Release binary's `version` is the git tag. `skill_path` is the copied skill directory, or `null` when the skill was not copied.

When `on_path` is false, tell the user `path_hint`. If another `javcli` is already on `PATH`, `path_hint` names it. Do not edit shell startup files unless the user asks.

On failure the exit code is non-zero and the last stdout line is `{"ok":false,"error":"..."}`. A checksum mismatch does not leave a new binary.

If the destination exists and its `--help` text is not javcli, the script refuses to overwrite it.

## When the download fails

Report the error and stop. Switch to `--source` only when the user asks for a source build. Do not invent a download mirror.

Install Go 1.24 or newer (https://go.dev/dl/) only when the user asks for a source build. Do not compile with an older distro Go.

## Manual install

Release archives and `SHA256SUMS` are at `https://github.com/taichijma/jav/releases`. Verify the checksum, then put `javcli` (`javcli.exe` on Windows) on `PATH`.

Source build of the current checkout:

```bash
go build -o "$HOME/.local/bin/javcli" .
```

On Windows: `go build -o javcli.exe .`, then add that directory to `PATH`.

## Upgrade

Run the same install again. The script replaces the binary at that path and leaves the config file alone.

## After install

```bash
command -v javcli
javcli version
javcli --help
```

`version` does not read the config file. Help text must contain `JavDB`. Stop there. Do not hit the search endpoint just to verify the install.

## Install this skill

This copy lives at `.agents/skills/javcli/`. An agent that loads project skills from `.agents/skills` can use it while this repository is open.

For other projects, copy the whole directory into the skill root this agent already loads. Keep the directory name `javcli`, including `references/` and `scripts/`. Use that agent's own directory.

```bash
bash scripts/install.sh --skills-dir "$AGENT_SKILLS_DIR"
```

`AGENT_SKILLS_DIR` is that root. The command also installs the latest Release binary. To copy only the skill:

```bash
mkdir -p "$AGENT_SKILLS_DIR"
rm -rf "$AGENT_SKILLS_DIR/javcli"
cp -a .agents/skills/javcli "$AGENT_SKILLS_DIR/javcli"
```

Copying `SKILL.md` alone drops the references and scripts. Do not delete `.agents/skills/javcli` inside this repository. That directory is the skill source.
