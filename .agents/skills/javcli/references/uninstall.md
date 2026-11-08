# 卸载 javcli

先看会删什么，再删。脚本不打印配置文件内容。

```bash
bash scripts/uninstall.sh --help
bash scripts/uninstall.sh --dry-run
bash scripts/uninstall.sh --prefix "$HOME/.local/bin"
bash scripts/uninstall.sh --skill "$AGENT_SKILLS_DIR" --dry-run
bash scripts/uninstall.sh --config --yes
bash scripts/uninstall.sh --skill "$AGENT_SKILLS_DIR" --yes
```

| 参数 | 作用 |
| --- | --- |
| `--dry-run` | 只报告，不删除。可以不带 `--yes` |
| `--prefix DIR` | 额外检查这个目录里的 `javcli` / `javcli.exe`。可重复。标准位置始终会检查 |
| `--config` | 删除 `${XDG_CONFIG_HOME:-$HOME/.config}/jav`。必须同时有 `--yes`，除非是 `--dry-run` |
| `--skill DIR` | 删除 `DIR/javcli`。`DIR` 是当前 Agent 的技能根目录，与安装时同一个。必须同时有 `--yes`，除非是 `--dry-run` |
| `--yes` | 允许 `--config` 和 `--skill` 真正删除 |

## 二进制

脚本只删除 `--help` 文本里含有 JavDB 的文件。候选位置：

- 每个 `--prefix` 下的 `javcli` 和 `javcli.exe`
- `command -v javcli` 和 `command -v javcli.exe`
- `$HOME/.local/bin/javcli`
- `/usr/local/bin/javcli`
- `/usr/bin/javcli`
- `$(go env GOBIN)/javcli`，没有 GOBIN 时用 `$(go env GOPATH)/bin/javcli`

存在但无法确认是 javcli 的同名文件（不能执行，或帮助文本里没有 JavDB）放进 `skipped_binaries`，保留不删。没有删除权限时，路径留在 `remove_errors`，已经删掉的其它文件不会回滚。不要自行加 `sudo`，除非用户要求。

## 配置

`--config` 删除的是整个配置目录，里面有 Cookie。目录里除了 `config.json` 和 `config.json.tmp.*` 以外还有别的文件时，脚本这一次什么都不删，并在 `remove_errors` 里说明原因。

只想清掉某一项、留下二进制时，不要删目录：

```bash
javcli config unset cookies
javcli config unset proxy
javcli config unset locale
```

`unset` 的输出不含被删掉的值。

## 技能副本

`--skill` 后面是安装时用的那个技能根目录。脚本只删除其中的 `javcli`，且 `SKILL.md` 的 frontmatter 必须是 `name: javcli`。目录不存在就当作已经卸掉。那个位置不是本技能时，这次什么都不删，原因在 `remove_errors`。

仓库里的 `.agents/skills/javcli` 是技能源。对它执行 `--skill` 会被拒绝，源目录保持不动。

## 环境变量

脚本只列出仍然非空的变量名：`JAVDB_COOKIES`、`SOCKS5_PROXY`、`JAVDB_LOCALE`、`JAVDB_BASE_URL`、`JAVDB_TLS_INSECURE`。用户要求从 shell 配置里去掉时，只删对应的赋值行，不要读出或复述值。脚本不会改 shell 配置，也不会删除 git 克隆。

用户指出源码目录并确认后，再删除那个目录。仓库里的 `./javcli` 是被 gitignore 的构建产物，只有用户要求清理工作区时才删。

## 输出

stdout 最后一行：

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

`--dry-run` 时 `removed_*` 为空，`binaries` 是确认过的 javcli，也就是真正执行时会删除的文件。退出码 2 表示缺 `--yes` 或参数错误。
