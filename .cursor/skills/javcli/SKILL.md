---
name: javcli
description: >-
  安装、卸载、配置并完整使用 javcli（JavDB 非官方 CLI）。用户提到 javcli、JavDB、
  番号、磁力、排行榜、评论、想看、已看、收藏演员、Cookie、SOCKS5，或要求安装、升级、
  卸载、配置这个命令时使用。包含 Release 与源码安装、配置优先级，以及 search、detail、
  rankings、reviews、bookmarks、config、version。
---

# javcli

`javcli` 查询 JavDB。每条命令的 stdout 都是一份 JSON。用自然语言回答用户，只保留他要的字段。

仓库文档里的地址是 `https://github.com/0xtaichim/jav`（Go module 是 `github.com/taichi/javcli`，两者不一致）。人类向说明在仓库 `README.md`。本技能不覆盖作为 Go 库调用。

## 先打开对应参考

路径相对于本技能目录（本文件所在目录）。只读当前请求需要的那一份，再执行。

| 用户要做的事 | 先读 |
| --- | --- |
| 安装、升级、放入 PATH、把技能复制到用户目录 | [references/install.md](references/install.md) |
| 卸载二进制、删除配置、卸下技能副本 | [references/uninstall.md](references/uninstall.md) |
| Cookie、SOCKS5、语言、环境变量 | [references/configure.md](references/configure.md) |
| 搜索、详情、磁力、排行、评论、收藏、版本 | [references/commands.md](references/commands.md) |

安装和卸载优先跑同目录下的 `scripts/install.sh`、`scripts/uninstall.sh`。脚本把进度写到 stderr，成功或失败时 stdout 的最后一行都是 JSON。

## 每次都遵守

1. 先确认要调用的那个二进制：`javcli version` 是 JSON（`version`、`commit`、`date`），`javcli --help` 的文本里有 JavDB。帮助文本不是 JSON。找不到命令就按安装参考处理，不要改用浏览器，也不要编造结果。
2. 只报告命令实际返回的字段。番号、标题、评分、演员、磁力、评论都不得补全。`detail` 里的 `description` 目前始终是空字符串。
3. 退出码不是 0 时，stdout 仍是 JSON，stderr 有同一条错误。`{"code":401,"message":"Unauthorized"}` 表示需要登录 Cookie，按配置参考处理。其它错误读 `error`，向用户说明后停止。不要用相同参数再跑一遍。
4. Cookie 和带密码的代理 URL 只存在于请求配置里。回复、提交、日志摘录里都不要出现这些值。`config set`、`config get`、`config list` 会把它们打进 stdout；用配置参考里的方式判断「已设置 / 未设置」，不要引用原始输出。
5. 删除配置目录或用户目录里的技能副本之前，先 `--dry-run`，得到明确同意后再加 `--yes`。
6. 请求失败且像网络问题时，先看是否已经有 SOCKS5。没有就建议配置代理；已经有就报告错误。不要连续盲试。
7. 这是成人影片元数据。回答用户问的那一项。

## 命令怎么选

| 意图 | 命令 |
| --- | --- |
| 是否装好、哪个构建 | `javcli version` |
| 番号或关键词 | `javcli search "<查询>"` |
| 详情、演员、磁力 | `javcli detail <番号>` |
| 热门、榜单 | `javcli rankings [-p daily\|weekly\|monthly] [-t censored\|uncensored\|western\|fc2]` |
| 短评 | `javcli reviews <番号> [-p 页码]` |
| 想看 / 已看 / 演员收藏 | `javcli bookmarks [-t want_watch\|watched\|actors] [-p 页码]` |
| 加入或移出想看、已看 | `javcli bookmarks add\|remove -t want_watch\|watched <番号>` |
| 查看或修改配置 | `javcli config set\|get\|list\|unset\|path` |

全局参数 `--cookies`、`--proxy`、`--locale` 可以写在子命令前面或后面，只对这一次调用生效，不会写入配置文件。优先级是命令行、环境变量、配置文件。空字符串不会盖掉较低优先级里已经有的值。

`detail`、`reviews` 和收藏的增删会先搜索。返回的 `code` 与用户给的番号不一致时，先说明实际用了哪一条。

向用户展示磁力时：先列 `is_hd` 和 `has_subs` 都为真的，其次只满足其中一项的，其余放后。每条都带上 `size`。`magnets` 为空就说明没有磁力。

榜单、评论、收藏默认只摘要前几条。用户要完整列表再展开。有 `has_next` 时用 `next_page` 翻页，不要自己猜页码。
