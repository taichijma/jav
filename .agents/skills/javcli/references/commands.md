# Use javcli

Successful query commands print indented JSON. On failure the exit code is 1, stdout is still one JSON document (compact), and stderr has the same error text. `version` and `config` also print JSON on success. `--help` is text, not JSON.

When arguments are wrong, read `error`, then run `javcli <subcommand> --help`. Do not guess a flag and rerun the same command.

Login required:

```json
{"code": 401, "message": "Unauthorized"}
```

Other failures:

```json
{"error": "code not found: XXX-000"}
```

When `code` is 401, or `error` says `JAVDB_COOKIES` is required, follow [configure.md](configure.md). Do not invent rows.

The HTTP timeout is 30 seconds and is not a CLI flag. Ctrl-C / SIGTERM cancels the request.

## version

```bash
javcli version
```

```json
{"version": "dev", "commit": "none", "date": "unknown"}
```

It does not read config and does not use the network. A plain `go build` keeps the three defaults above. A Release binary sets `version` to a tag such as `vX.Y.Z`, `commit` to a 12-character hash, and `date` to a UTC timestamp.

## search

```bash
javcli search "SSNI-678"
javcli search "秘书"
```

Exactly one argument. An empty string fails with `query is required`.

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

`total` is the number of rows parsed on this page, not the site-wide hit count. `review_id` is 0 on search rows. Tags may include `磁鏈` or `磁链` while `has_magnet` is true. An empty `movies` array means nothing matched.

Prefer `code`, `title`, `date`, `rating`, and `has_magnet`. Omit `image_url` and `url` unless the user asked for artwork or links.

## detail

```bash
javcli detail SSNI-678
```

The command searches, then opens the matching page. The code match is case-insensitive. With no exact match it opens the first result. If the returned `code` differs from the user's code, say which title was opened. Not found: `code not found: <input>`.

Fields: `code`, `title`, `url`, `rating`, `rating_count`, `date`, `duration`, `director`, `publisher`, `series`, `image_url`, `tags`, `actors`, `magnets`, `description`.

Each actor has `name`, `url`, and `image_url`. `description` is not parsed and is always an empty string. Do not treat that as "no synopsis", and do not write one.

Magnet fields:

| Field | Meaning |
| --- | --- |
| `magnet` | Magnet URI |
| `name` | Name |
| `size` | Size. Always include it when listing a magnet |
| `date` | Date |
| `is_hd` | The tag text contains `高清` or `HD` |
| `has_subs` | The tag text contains `字幕` or `中字` |

Duplicate magnet URIs are dropped. Present `is_hd` and `has_subs` both true first, then either one, then the rest. That order is for the answer, not the command output. If there are no magnets, say so. Do not invent one.

When the user asked only for metadata, do not paste a full `magnet` URI. Include the URI when they ask for the link.

## rankings

```bash
javcli rankings
javcli rankings -p weekly -t uncensored
javcli rankings -p monthly -t fc2
```

| Flag | Values | Default |
| --- | --- | --- |
| `-p`, `--period` | `daily`, `weekly`, `monthly` | `daily` |
| `-t`, `--type` | `censored`, `uncensored`, `western`, `fc2` | `censored` |

An illegal value fails, for example `unknown ranking period "yearly"; supported: daily, weekly, monthly`. Tell the user. Do not silently substitute a nearby legal value and rerun.

The result has `period`, `type`, and `movies`. Movie fields match search. By default, summarize the first few rows with code, title, and rating.

## reviews

```bash
javcli reviews EBWH-156
javcli reviews EBWH-156 -p 2
```

The command resolves the code, then loads that review page. A page below 1 is treated as page 1.

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

`rating` is the number of filled stars. When `has_next` is true, request `next_page`. Do not add one to the current page. Summarize a few reviews (author, rating, content) unless the user asks for more.

## bookmarks

A login cookie is required. List:

```bash
javcli bookmarks
javcli bookmarks -t watched -p 2
javcli bookmarks -t actors
```

`-t` / `--type`: `want_watch` (default), `watched`, `actors`. `-p` / `--page` defaults to 1, and a value below 1 is treated as 1.

Movie lists include `review_id` on each movie. The `actors` list uses `actors` (`name`, `url`, `image_url`) and leaves `movies` empty. `total` is the count on this page. Page with `has_next` and `next_page`.

Unknown type: `unknown bookmark type "..."; supported: want_watch, watched, actors`.

Add and remove accept movies only, not actors:

```bash
javcli bookmarks add -t want_watch SDJS-345
javcli bookmarks remove -t want_watch SDJS-345
javcli bookmarks add -t watched SDJS-345 -r 4 -c "节奏不错，推荐字幕版"
javcli bookmarks remove -t watched SDJS-345
```

Omitting `-t` means `want_watch`. `actors` or any other type fails with `add only supports -t want_watch or -t watched` (remove says `remove only supports ...`).

For watched, `-r` / `--rating` is sent as given when it is 1 through 5. A missing value, 0, or any other value is submitted as 3. `-c` / `--content` is sent as given. The site expects roughly 10 to 1000 characters. If the site rejects the length, tell the user. Do not rewrite the comment and retry unless they ask for a length change.

Success:

```json
{"ok": true, "type": "want_watch", "code": "SDJS-345"}
```

`code` here is the argument text. Remove searches the matching list for that code, up to 100 pages. Missing: `code <code> not found in want-watch list` or `watched list`. A row without `review_id`: `review_id not found for this <type> item; try again later`. Do not list the collection first unless the user wants to confirm. On failure, explain `error`.

## Sequence

1. The user gives a code or a loose description: `search`. For metadata, actors, or magnets, run `detail` on a returned code.
2. Rankings: confirm period and type, then `rankings`. If they did not specify, use the default censored daily chart and say so.
3. Reviews: `reviews`. Follow `next_page` when they want more.
4. Want-watch, watched, or "my bookmarks": `bookmarks`. On 401, follow the configure reference.
5. For a one-off query, pass global flags or environment variables. Use `config` when the user wants the setting saved.
