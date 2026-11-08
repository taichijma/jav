# 使用 javcli

查询命令的 stdout 是缩进 JSON。失败时退出码为 1，stdout 仍是一份 JSON（紧凑格式），stderr 是同一条错误文本。`version` 和 `config` 成功时也是 JSON。`--help` 是文本，不是 JSON。

参数不对时读 `error`，再运行 `javcli <子命令> --help` 核对。不要猜 flag 后原样重试。

登录不足：

```json
{"code": 401, "message": "Unauthorized"}
```

其它失败：

```json
{"error": "code not found: XXX-000"}
```

`code` 为 401，或 `error` 里说明需要 `JAVDB_COOKIES` 时，按 [configure.md](configure.md) 处理，不要编造条目。

HTTP 超时默认 30 秒，命令行不能改。Ctrl-C / SIGTERM 会取消请求。

## version

```bash
javcli version
```

```json
{"version": "dev", "commit": "none", "date": "unknown"}
```

不读取配置文件，也不访问网络。源码直接 `go build` 时三个字段就是上面的默认值。Release 二进制的 `version` 是 `vX.Y.Z` 这样的标签，`commit` 是 12 位哈希，`date` 是 UTC 时间。

## search

```bash
javcli search "SSNI-678"
javcli search "秘书"
```

正好一个参数。空字符串失败：`query is required`。

```json
{
  "query": "SSNI-678",
  "movies": [
    {
      "code": "SSNI-678",
      "title": "",
      "url": "https://javdb.com/v/...",
      "rating": 0,
      "rating_count": 0,
      "date": "",
      "has_magnet": false,
      "image_url": "",
      "tags": [],
      "review_id": 0
    }
  ],
  "total": 1
}
```

`total` 是这一页解析到的条数，不是站点上的全部命中数。搜索结果里的 `review_id` 为 0。标签里可能有「磁鏈」或「磁链」，同时 `has_magnet` 为 true。`movies` 为空就说没找到。

回答时优先用 `code`、`title`、`date`、`rating`、`has_magnet`。用户没要封面和链接时省略 `image_url` 和 `url`。

## detail

```bash
javcli detail SSNI-678
```

先搜索，再打开匹配页面。番号大小写不敏感；没有精确匹配时用第一条结果。返回的 `code` 和用户给的番号不一致时，先说明实际打开的是哪一条。找不到：`code not found: <输入>`。

字段：`code`、`title`、`url`、`rating`、`rating_count`、`date`、`duration`、`director`、`publisher`、`series`、`image_url`、`tags`、`actors`、`magnets`、`description`。

`actors` 的元素是 `name`、`url`、`image_url`。`description` 目前没有解析，始终是空字符串，不要据此说「没有简介」，也不要自己写情节。

`magnets` 的元素：

| 字段 | 含义 |
| --- | --- |
| `magnet` | 磁力 URI |
| `name` | 名称 |
| `size` | 大小，展示时始终带上 |
| `date` | 日期 |
| `is_hd` | 标签里有「高清」或 `HD` |
| `has_subs` | 标签里有「字幕」或「中字」 |

相同磁力只保留一条。展示顺序：`is_hd` 与 `has_subs` 都为真，然后只满足一项，然后其余。这是回答时的排序，不是命令输出的顺序。没有磁力就说明没有，不要编造。

用户只要元数据时，不要主动贴出完整 `magnet`。用户要链接时再给对应的那条。

## rankings

```bash
javcli rankings
javcli rankings -p weekly -t uncensored
javcli rankings -p monthly -t fc2
```

| 参数 | 取值 | 默认 |
| --- | --- | --- |
| `-p` / `--period` | `daily`、`weekly`、`monthly` | `daily` |
| `-t` / `--type` | `censored`、`uncensored`、`western`、`fc2` | `censored` |

非法取值直接失败，例如 `unknown ranking period "yearly"; supported: daily, weekly, monthly`。不要改成接近的合法值再偷偷重跑，先告诉用户。

返回 `period`、`type`、`movies`。`movies` 的字段与搜索相同。默认摘要前几条的番号、标题、评分。

## reviews

```bash
javcli reviews EBWH-156
javcli reviews EBWH-156 -p 2
```

先按番号解析影片，再取评论页。页码小于 1 时按第 1 页。

```json
{
  "code": "EBWH-156",
  "page": 1,
  "has_prev": false,
  "has_next": true,
  "prev_page": 0,
  "next_page": 2,
  "reviews": [
    {
      "id": 1,
      "author": "",
      "rating": 5,
      "likes": 0,
      "content": "",
      "date": ""
    }
  ]
}
```

`rating` 是实心星的个数。`has_next` 为 true 时，下一页用 `next_page`，不要把当前页加一再猜。默认摘要少量评论的作者、评分和内容；用户要更多再翻页。

## bookmarks

需要登录 Cookie。列出：

```bash
javcli bookmarks
javcli bookmarks -t watched -p 2
javcli bookmarks -t actors
```

`-t` / `--type`：`want_watch`（默认）、`watched`、`actors`。`-p` / `--page` 默认 1，小于 1 时按 1。

影片列表的 `movies` 里会带 `review_id`。`actors` 列表使用 `actors`（`name`、`url`、`image_url`），`movies` 为空。`total` 是这一页的条数。用 `has_next` 和 `next_page` 翻页。

未知类型：`unknown bookmark type "..."; supported: want_watch, watched, actors`。

增删只支持影片，不支持演员：

```bash
javcli bookmarks add -t want_watch SDJS-345
javcli bookmarks remove -t want_watch SDJS-345
javcli bookmarks add -t watched SDJS-345 -r 4 -c "节奏不错，推荐字幕版"
javcli bookmarks remove -t watched SDJS-345
```

`-t` 省略时按 `want_watch`。`actors` 或其它类型失败：`add only supports -t want_watch or -t watched`（删除是 `remove only supports ...`）。

已看的 `-r` / `--rating` 只在 1 到 5 之间原样提交；缺省、0 或越界都改成 3 分再提交。`-c` / `--content` 原样提交。站点大约要求 10 到 1000 字。过短或过长会由站点报错；把错误告诉用户，不要擅自改写后重试，除非用户要求调整字数。

成功：

```json
{"ok": true, "type": "want_watch", "code": "SDJS-345"}
```

这里的 `code` 是参数原文。删除时会在对应列表里按番号查找，最多 100 页。不在列表中：`code <番号> not found in want-watch list` 或 `watched list`。找到条目但没有 `review_id`：`review_id not found for this <type> item; try again later`。删除前不必先列给用户看，除非用户要确认；失败时把 `error` 说明白。

## 怎么串起来

1. 用户给了番号或模糊说法：`search`。要元数据、演员或磁力时，对命中的番号再 `detail`。
2. 热门或榜单：先确认周期和类型，再 `rankings`。用户没指定时用默认的有码日榜，并在回答里说明这个默认。
3. 评价或短评：`reviews`。需要更多时按 `next_page` 翻页。
4. 想看、已看、我的收藏：`bookmarks`。401 就按配置参考处理。
5. 同一请求里要改配置时用 `config`，不要为了一次查询去改配置文件；一次查询用全局参数或环境变量。
