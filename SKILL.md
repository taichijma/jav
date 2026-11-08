---
name: javcli
description: >-
  Use javcli to query JavDB: search by 番号/keyword, fetch movie details and magnet
  links, rankings, reviews, and want-watch/watched/actor bookmarks; also configure
  cookies, SOCKS5 proxy, and locale. Trigger when the user mentions javcli, JavDB,
  番号, 磁力, 排行榜, 想看/已看, or adult-video metadata lookup.
---

# javcli

JavDB 非官方 CLI。每条命令的 **stdout 都是 JSON**。解析后用自然语言回答；不要把整段 JSON 或 Cookie 贴进对话。

仓库：`https://github.com/0xtaichim/jav`（Go module：`github.com/taichi/javcli`）。人类向说明见 [README.md](README.md)。

## 安装

先跑 `javcli --help`。若 `command not found`，需要 Go 1.24+，从源码编译（不要用错误的 `go install github.com/taichi/javcli@latest`，module 路径与 GitHub 仓库不一致）：

```bash
git clone https://github.com/0xtaichim/jav.git
cd jav
go build -o javcli .
```

把二进制放入 `PATH`，或后续使用 `./javcli`。已发布的版本也可以从仓库 [Releases](https://github.com/0xtaichim/jav/releases) 下载对应平台的压缩包。`javcli version` 输出 JSON（`version`、`commit`、`date`）；Release 二进制的 `version` 是 Git 标签。

## 配置（优先级）

**命令行全局 flag > 环境变量 > 配置文件**

| 用途 | Flag | 环境变量 | `javcli config` 键 |
| --- | --- | --- | --- |
| 登录 Cookie | `--cookies` | `JAVDB_COOKIES` | `cookies` |
| SOCKS5 代理 | `--proxy` | `SOCKS5_PROXY` | `proxy` |
| 语言（默认 `zh`） | `--locale` | `JAVDB_LOCALE` | `locale` |

配置文件：`$XDG_CONFIG_HOME/jav/config.json` 或 `~/.config/jav/config.json`。

仅环境变量：`JAVDB_BASE_URL`（默认 `https://javdb.com`）；`JAVDB_TLS_INSECURE=1` 跳过 TLS 校验。

未设 Cookie 时仍带 `over18=1`。**收藏读写、部分无码/FC2 内容需要有效登录 Cookie。** SOCKS5 代理写成 `host:port`、`socks5://host:port`，或带认证的 `socks5://user:pass@host:port`（密码中的 `@`、`:` 等请 URL 编码）。设置配置：

```bash
javcli config set proxy "127.0.0.1:6153"
javcli config set proxy "socks5://user:pass@127.0.0.1:6153"
javcli config set cookies "<cookie>"
javcli config list
javcli config path
```

绝对不要把 Cookie 值回显给用户（可用 `config path` / 是否已设置来确认）。

## 按意图选命令

所有查询类命令失败时：stdout 仍是 JSON，exit code ≠ 0。

- 登录不足：`{"code": 401, "message": "Unauthorized"}` → 请用户配置 Cookie，不要编造数据。
- 其它：`{"error": "<message>"}` → 原样说明原因。

### 搜索 — `javcli search "<番号或关键词>"`

```bash
javcli search "SSNI-678"
javcli search "秘书"
```

读 `movies[]`：`code`、`title`、`date`、`rating`、`has_magnet`。空列表就说没找到。

### 详情与磁力 — `javcli detail <番号>`

```bash
javcli detail SSNI-678
```

先搜索再打开匹配项。关注 `title`、`code`、`date`、`duration`、`director`、`publisher`、`series`、`actors`、`tags`、`magnets`。

列出磁力时：

1. 优先 `is_hd == true` 且 `has_subs == true`
2. 其次高清或有字幕
3. **始终展示 `size`**，需要时附上 `magnet` 字符串
4. 没有磁力就明确说没有，不要编造

### 排行榜 — `javcli rankings`

```bash
javcli rankings                         # 有码日榜
javcli rankings -p weekly -t uncensored
javcli rankings -p monthly -t fc2
```

- `-p/--period`：`daily`（默认）、`weekly`、`monthly`
- `-t/--type`：`censored`（默认）、`uncensored`、`western`、`fc2`

非法取值会报错。默认只摘要前几条（番号、标题、评分），用户要完整榜再展开。

### 评论 — `javcli reviews <番号> [-p 页码]`

```bash
javcli reviews EBWH-156
javcli reviews EBWH-156 -p 2
```

用 `has_next` / `next_page` 翻页。字段：`author`、`rating`、`likes`、`content`、`date`。

### 收藏 — `javcli bookmarks`（需登录）

列出：

```bash
javcli bookmarks                 # want_watch
javcli bookmarks -t watched -p 2
javcli bookmarks -t actors
```

增删（仅影片，不是演员）：

```bash
javcli bookmarks add -t want_watch <番号>
javcli bookmarks remove -t want_watch <番号>
javcli bookmarks add -t watched <番号> [-r 1-5] [-c "评论"]
javcli bookmarks remove -t watched <番号>
```

`watched` 的评分缺省或越界按 3 分提交；评论长度约 10–1000。成功：`{"ok": true, "type": "...", "code": "..."}`。删除前番号必须已在对应列表中。

## 工作流

1. 用户给番号或模糊描述 → `search`；要元数据/磁力/演员 → 对命中番号再 `detail`。
2. 「热门 / 榜单」→ `rankings`，确认周期与类型。
3. 「评价 / 短评」→ `reviews`，需要更多再翻页。
4. 「我想看 / 看过 / 我的收藏」→ `bookmarks`；401 则引导配置 Cookie。
5. 访问失败且环境可能需要代理 → 提示 `--proxy` 或 `SOCKS5_PROXY`，不要反复盲试同一命令。
6. 不要编造番号、磁力、评分或演员。命令失败就报告错误。
7. 用户要改配置时用 `config` 子命令，不要手改 JSON（除非用户明确要求）。
