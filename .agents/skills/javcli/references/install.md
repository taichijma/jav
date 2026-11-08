# 安装 javcli

脚本路径相对于本技能目录。进度在 stderr，stdout 最后一行是 JSON。

```bash
bash scripts/install.sh --help
bash scripts/install.sh --release
bash scripts/install.sh --release v0.1.0 --prefix "$HOME/.local/bin"
bash scripts/install.sh --source
bash scripts/install.sh --src /path/to/jav
bash scripts/install.sh --release --skills-dir "$AGENT_SKILLS_DIR"
```

| 参数 | 作用 |
| --- | --- |
| `--prefix DIR` | 二进制目录，默认 `$HOME/.local/bin` |
| `--release [TAG]` | 下载 GitHub Release。省略 TAG 时用最新版。资产名是 `javcli_<tag>_<os>_<arch>.tar.gz`（Windows 为 `.zip`），并用同一 Release 的 `SHA256SUMS` 校验 |
| `--source` | 从源码编译。找不到检出时浅克隆 `https://github.com/0xtaichim/jav.git` |
| `--src DIR` | 编译这个检出。不能和 `--release` 一起用 |
| `--skills-dir DIR` | 把本技能复制到 `DIR/javcli`。`DIR` 是当前 Agent 已经在加载的技能根目录。省略时使用 `AGENT_SKILLS_DIR`；两者都没有则不复制技能 |

## 选哪一种

- 用户要能用的正式版本：`--release`。不在本仓库里、也不传 `--source` / `--src` 时，脚本默认就是 Release。
- 技能脚本位于本仓库内时，不带参数会编译**当前检出**，不会下载 Release。用户要正式版本时必须加上 `--release`。
- 用户正在改这个仓库，或明确要当前源码：`--source` 或 `--src`。
- `--release` 与 `--source`、`--src` 互斥。

源码编译需要 Go 1.24 或更新，以及 `python3`。脚本使用 `CGO_ENABLED=0`。Release 安装需要 `curl`、`python3`，以及 `sha256sum` 或 `shasum`。

不要执行下面两条。module 路径和 GitHub 仓库不一致，装不到这份程序：

```bash
go install github.com/taichi/javcli@latest
go install github.com/0xtaichim/jav@latest
```

## 成功时的 JSON

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

`method` 是 `release` 或 `source`。`source` 在源码安装时是检出目录，在 Release 安装时是实际下载的资产 URL。文档里的 `0xtaichim/jav` 会跳转到实际仓库，所以 URL 的主机名可能是跳转之后的地址。源码安装的 `version` 一般是 `dev`，`commit` 是 `none`，`date` 是 `unknown`。Release 二进制的 `version` 是 Git 标签。`skill_path` 是复制后的技能目录；这次没有复制技能时为 `null`。

`on_path` 为 false 时，把 `path_hint` 告诉用户。PATH 里若已有另一个 `javcli`，`path_hint` 会写出那个路径。不要改 `.bashrc`、`.zshrc` 或其它 shell 配置，除非用户要求。

失败时退出码非 0，stdout 最后一行是 `{"ok":false,"error":"..."}`。校验和不符时脚本不会留下新二进制。

目标路径上若已有文件，且 `--help` 不像 javcli，脚本拒绝覆盖。

## 没有 Go 或下载失败

Release 路线不需要 Go。用户明确要求安装 Go 时再安装 1.24 或更新的版本（https://go.dev/dl/），不要用更旧的发行版包硬编。

GitHub 下载失败时，说明错误并停。用户要求改走源码时再加 `--source`。不要换镜像地址，除非用户给了镜像。

## 手动安装

Release 压缩包和 `SHA256SUMS` 在 `https://github.com/0xtaichim/jav/releases`。核对校验和后再解压，把 `javcli`（Windows 是 `javcli.exe`）放到 PATH。

当前检出：

```bash
go build -o "$HOME/.local/bin/javcli" .
```

Windows 源码构建：`go build -o javcli.exe .`，再把所在目录加入 PATH。

## 升级

再跑一次与上次相同的安装方式。脚本覆盖同一路径上的旧 javcli，不修改配置文件。

## 安装后检查

```bash
command -v javcli
javcli version
javcli --help
```

`version` 不读取配置文件。帮助文本里要有 JavDB。到此为止，不要为了验证去请求搜索接口。

## 把技能装进当前 Agent

本仓库的技能在 `.agents/skills/javcli/`。打开这个仓库时，从 `.agents/skills` 读取项目技能的 Agent 会直接用到它。

其它项目也要使用时，复制到**你正在加载技能的那个根目录**。用你自己的目录，不要改放到另一个工具的目录。目录名保持 `javcli`，并带上 `references/` 和 `scripts/`。

```bash
bash scripts/install.sh --release --skills-dir "$AGENT_SKILLS_DIR"
```

`AGENT_SKILLS_DIR` 就是这个根目录。只想复制技能、不安装二进制时：

```bash
mkdir -p "$AGENT_SKILLS_DIR"
rm -rf "$AGENT_SKILLS_DIR/javcli"
cp -a .agents/skills/javcli "$AGENT_SKILLS_DIR/javcli"
```

只复制一个 `SKILL.md` 会缺参考和脚本。仓库里的 `.agents/skills/javcli` 是技能源，不要删。
