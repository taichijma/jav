---
name: javcli
description: >-
  Install, uninstall, configure, and operate javcli, the unofficial JavDB CLI.
  Use when the user mentions javcli, JavDB, a DVD code (番号), magnet links
  (磁力), rankings (排行榜), reviews, want-watch or watched (想看/已看), actor
  bookmarks, cookies, or a SOCKS5 proxy, or asks to install, upgrade, remove,
  or configure the command. Prefer a GitHub Release install. Covers config
  precedence and search, detail, rankings, reviews, bookmarks, config, and
  version.
---

# javcli

`javcli` queries JavDB. Every command prints one JSON document on stdout. Answer in the user's language and keep only the fields they asked for.

Repository: `https://github.com/taichijma/jav` (`https://github.com/0xtaichim/jav` redirects there). Go module: `github.com/taichi/javcli`. Those paths differ. Human docs are in the repository `README.md`. This skill does not cover the Go library.

## Open one reference

Paths are relative to this skill directory. Read only the file for the current request, then act.

| Request | Read |
| --- | --- |
| Install, upgrade, PATH, or copy this skill into the agent's skill directory | [references/install.md](references/install.md) |
| Remove the binary, config, or an installed skill copy | [references/uninstall.md](references/uninstall.md) |
| Cookie, SOCKS5, locale, environment variables | [references/configure.md](references/configure.md) |
| Search, detail, magnets, rankings, reviews, bookmarks, version | [references/commands.md](references/commands.md) |

Prefer `scripts/install.sh` and `scripts/uninstall.sh` in this directory. Progress goes to stderr. The last stdout line is JSON on success and on failure.

## Rules

1. Confirm the binary first. `javcli version` is JSON (`version`, `commit`, `date`). `javcli --help` is text and contains `JavDB`. Help text is not JSON. If the command is missing, follow the install reference. Do not browse the site instead, and do not invent results.
2. Report only fields the command returned. Do not fill in codes, titles, ratings, actors, magnets, or reviews. `description` on `detail` is always an empty string.
3. A non-zero exit still prints JSON on stdout, and stderr repeats the error. `{"code":401,"message":"Unauthorized"}` means a login cookie is required; follow the configure reference. For any other error, read `error`, tell the user, and stop. Do not rerun the same command.
4. Cookies and proxy URLs that contain a password stay in the request configuration. Do not repeat them in replies, commits, or log excerpts. `config set`, `config get`, and `config list` print them on stdout. Use the filter in the configure reference and report only whether each key is set.
5. Before deleting the config directory or an installed skill copy, run `--dry-run`, get an explicit yes, then add `--yes`.
6. When a failure looks like a network problem, check whether a SOCKS5 proxy is already configured. If not, suggest one. If it is, report the error. Do not retry the same command.
7. This is adult video metadata. Answer only what the user asked.

## Choose a command

| Intent | Command |
| --- | --- |
| Installed build | `javcli version` |
| Code or keyword | `javcli search "<query>"` |
| Metadata, actors, magnets | `javcli detail <code>` |
| Rankings | `javcli rankings [-p daily\|weekly\|monthly] [-t censored\|uncensored\|western\|fc2]` |
| Reviews | `javcli reviews <code> [-p page]` |
| Want-watch, watched, or actor bookmarks | `javcli bookmarks [-t want_watch\|watched\|actors] [-p page]` |
| Add or remove a want-watch or watched entry | `javcli bookmarks add\|remove -t want_watch\|watched <code>` |
| Read or change config | `javcli config set\|get\|list\|unset\|path` |

Global flags `--cookies`, `--proxy`, and `--locale` may appear before or after the subcommand. They apply to that invocation only and are not saved. Precedence is command line, then environment, then the config file. An empty string does not override a non-empty value from a lower source.

`detail`, `reviews`, and bookmark add/remove search first. If the returned `code` differs from the code the user gave, say which title was opened.

When showing magnets, list `is_hd` and `has_subs` both true first, then either one, then the rest. Always include `size`. An empty `magnets` array means there are no magnets.

Summarize the first few ranking, review, and bookmark rows. Expand only when the user asks for the full list. Follow `has_next` / `next_page`. Do not guess the next page number.
