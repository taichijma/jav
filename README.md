# javcli

JavDB 非官方命令行客户端。搜索番号与关键词、拉取影片详情（含磁力）、查看排行榜与评论、管理想看 / 已看 / 演员收藏。所有命令的标准输出都是 JSON，适合人机直接调用，也适合作为 Agent 工具。

本项目不是 JavDB 官方产品，依赖页面结构解析，站点改版可能导致失败。内容面向成人，请自行确认当地法律与使用条款后再使用。

## 功能

- 按番号或关键词搜索
- 获取影片详情、演员、标签、磁力链接（高清 / 字幕标记）
- 日 / 周 / 月排行榜（有码、无码、欧美、FC2）
- 分页读取评论
- 列出、添加、删除「想看」「已看」；列出收藏演员（需登录 Cookie）
- 持久化配置：cookies、SOCKS5 代理、界面语言

## 安装

需要 [Go 1.24+](https://go.dev/dl/)。仓库地址与 Go module 路径目前不一致（仓库 `github.com/0xtaichim/jav`，module `github.com/taichi/javcli`），请从源码编译：

```bash
git clone https://github.com/0xtaichim/jav.git
cd jav
go build -o javcli .
```

将生成的 `javcli` 放到 `PATH` 中，或在当前目录使用 `./javcli`。验证：

```bash
./javcli --help
```

也可以从 [Releases](https://github.com/0xtaichim/jav/releases) 下载已编译的二进制（Linux、macOS、Windows，amd64 与 arm64）。同一 Release 里的 `SHA256SUMS` 是校验和。发布方式见下方「发布新版本」。

更多调用示例见 [`example.sh`](example.sh)。

## 配置

优先级从高到低：

1. 全局命令行参数：`--cookies`、`--proxy`、`--locale`
2. 环境变量
3. 配置文件（仅在前两者为空时生效）

配置文件路径为 `$XDG_CONFIG_HOME/jav/config.json`，未设置 `XDG_CONFIG_HOME` 时为 `~/.config/jav/config.json`。写入时权限为 `0600`。

| 用途 | 命令行 | 环境变量 | 配置键 |
| --- | --- | --- | --- |
| 登录 Cookie | `--cookies` | `JAVDB_COOKIES` | `cookies` |
| SOCKS5 代理 | `--proxy` | `SOCKS5_PROXY` | `proxy` |
| 界面语言（默认 `zh`） | `--locale` | `JAVDB_LOCALE` | `locale` |

另外两个仅环境变量生效的选项：

| 环境变量 | 说明 |
| --- | --- |
| `JAVDB_BASE_URL` | 覆盖站点根 URL，默认 `https://javdb.com` |
| `JAVDB_TLS_INSECURE` | 设为 `1` / `true` / `yes` / `on` 时跳过 TLS 校验 |

未提供 Cookie 时，客户端仍会带上 `over18=1` 与 `locale`。收藏的读写、以及部分无码 / FC2 内容需要浏览器登录后的会话 Cookie。SOCKS5 代理支持无认证与用户名/密码认证：

- `127.0.0.1:6153` 或 `socks5://127.0.0.1:6153`
- `socks5://user:pass@127.0.0.1:6153` 或 `user:pass@127.0.0.1:6153`

密码含 `@`、`:`、`/` 等字符时请做 URL 编码，例如 `socks5://user:p%40ss@127.0.0.1:6153`。

```bash
# 写入配置文件
javcli config set proxy "127.0.0.1:6153"
javcli config set proxy "socks5://user:pass@127.0.0.1:6153"
javcli config set cookies "<从浏览器复制的 Cookie 字符串>"
javcli config set locale zh

javcli config list
javcli config get proxy
javcli config path
javcli config unset cookies
```

不要把 Cookie 粘贴到聊天、日志或公开仓库。

## 命令

全局参数可加在子命令前或后，例如：

```bash
javcli --proxy 127.0.0.1:6153 search "SSNI-678"
javcli --proxy socks5://user:pass@127.0.0.1:6153 search "SSNI-678"
```

### search

按番号或关键词搜索。

```bash
javcli search "SSNI-678"
javcli search "秘书"
```

返回 `query`、`movies`、`total`。每条影片常见字段：`code`、`title`、`url`、`rating`、`rating_count`、`date`、`has_magnet`、`image_url`、`tags`。

### detail

按番号取详情与磁力。会先搜索再打开匹配条目（大小写不敏感；无精确匹配时用第一条结果）。

```bash
javcli detail SSNI-678
```

详情字段包括 `title`、`code`、`date`、`duration`、`director`、`publisher`、`series`、`actors`、`tags`、`magnets` 等。磁力条目含 `magnet`、`name`、`size`、`date`、`is_hd`、`has_subs`。

### rankings

```bash
javcli rankings                         # 有码日榜
javcli rankings -p weekly -t uncensored # 无码周榜
javcli rankings -p monthly -t fc2       # FC2 月榜
```

| 参数 | 取值 | 默认 |
| --- | --- | --- |
| `-p, --period` | `daily`、`weekly`、`monthly` | `daily` |
| `-t, --type` | `censored`、`uncensored`、`western`、`fc2` | `censored` |

非法取值会返回错误 JSON，而不是静默回退。

### reviews

分页读取某个番号的评论。

```bash
javcli reviews EBWH-156
javcli reviews EBWH-156 -p 2
```

返回 `reviews` 以及 `has_prev` / `has_next`、`prev_page` / `next_page`。评论字段：`id`、`author`、`rating`、`likes`、`content`、`date`。

### bookmarks

需要登录 Cookie。列出收藏：

```bash
javcli bookmarks                      # 想看，默认
javcli bookmarks -t watched -p 2
javcli bookmarks -t actors
```

`-t` 取值：`want_watch`、`watched`、`actors`。列表带 `has_next` / `next_page`。

添加 / 删除只支持影片（不支持演员）：

```bash
javcli bookmarks add -t want_watch SDJS-345
javcli bookmarks remove -t want_watch SDJS-345

javcli bookmarks add -t watched SDJS-345 -r 4 -c "节奏不错，推荐字幕版"
javcli bookmarks remove -t watched SDJS-345
```

`-t watched` 时：`-r/--rating` 为 1–5，缺省或越界按 3 分提交；`-c/--content` 为评论（站点要求约 10–1000 字）。成功返回 `{"ok": true, "type": "...", "code": "..."}`。删除时会在对应列表里查找该番号的 `review_id`，不在列表中会报错。

### config

见上方「配置」。子命令：`set`、`get`、`list`、`unset`、`path`。

### version

```bash
javcli version
```

输出构建信息：`version`、`commit`、`date`。从源码直接编译时 `version` 为 `dev`。Release 二进制中的 `version` 是对应的 Git 标签，例如 `v0.1.0`。

## 输出与错误

成功时 stdout 为带缩进的 JSON。失败时进程退出码非 0，stderr 有文本错误，stdout 仍是 JSON：

```json
{"code": 401, "message": "Unauthorized"}
```

```json
{"error": "code not found: XXX-000"}
```

`code: 401` 表示需要登录或 Cookie 失效，应提示用户设置 `JAVDB_COOKIES` 或 `javcli config set cookies ...`，不要编造结果。

## 作为 Go 库

```go
package main

import (
	"context"
	"fmt"
	"os"

	"github.com/taichi/javcli/pkg/javdb"
)

func main() {
	client := javdb.New(
		javdb.WithCookies(os.Getenv("JAVDB_COOKIES")),
		javdb.WithProxy(os.Getenv("SOCKS5_PROXY")),
		javdb.WithLocale("zh"),
	)
	result, err := client.Search(context.Background(), "SSNI-678")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("hits: %d\n", result.Total)
}
```

`javdb.New(...)` 可注入 HTTP 客户端、Base URL、超时、TLS 策略，便于测试。`javdb.NewClient()` 只从环境变量读取，适合简单脚本。

## Agent 技能

Agent 应阅读 [`SKILL.md`](SKILL.md)：何时调用哪条命令、如何解读 JSON、磁力排序规则、以及不要泄露 Cookie。在 Cursor 中安装为个人技能：

```bash
mkdir -p ~/.cursor/skills/javcli
cp SKILL.md ~/.cursor/skills/javcli/SKILL.md
```

## 发布新版本

推送语义化版本标签后，GitHub Actions 会自动测试、交叉编译，并创建 GitHub Release。说明来自上一版本标签以来合并的 Pull Request：每条包含标题、作者、链接和 PR 正文里的改进说明，并附上 GitHub 汇总的变更列表。

```bash
git tag v0.1.0
git push origin v0.1.0
```

标签形如 `v1.2.3`。带连字符的预发布标签（例如 `v1.2.3-rc.1`）会标成 Pre-release，并且不会覆盖当前的 Latest。Actions 里重跑失败的 workflow 时，会发布或更新这个标签对应的 Release。

给 Pull Request 打上 `enhancement`、`bug`、`documentation` 或 `breaking-change`，紧凑变更列表会按「新功能 / 修复 / 文档 / 破坏性变更」分组；未打标签的归入「其他改进」。不想出现在 Release 里的 PR 打上 `ignore-for-release`。

## 开发

```bash
go test ./...
python3 -m unittest discover -s .github/scripts -p 'test_*.py'
```

网络相关测试会访问外部站点，可能因网络或反爬而失败。HTTP 传输使用 uTLS 模拟 Chrome 指纹，并优先 HTTP/2、失败时回退 HTTP/1.1。

## 免责声明

仅供个人学习与研究。请遵守 JavDB 服务条款与所在地法律。作者不对滥用、封号、版权争议或数据准确性承担责任。
