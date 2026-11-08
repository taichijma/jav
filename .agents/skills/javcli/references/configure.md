# Configure javcli

Saved settings affect later requests. `javcli version` does not read them.

## Precedence

Command-line global flags, then environment variables, then the config file. An empty string is skipped, and the next source is used. `--proxy ""` or an empty `SOCKS5_PROXY` does not turn off a proxy already stored in the config file. For a direct connection, run `javcli config unset proxy` and unset `SOCKS5_PROXY`.

Global flags may be placed before or after the subcommand. They apply once:

```bash
javcli --proxy 127.0.0.1:6153 search "SSNI-678"
javcli search "SSNI-678" --locale zh
```

`javcli --proxy 127.0.0.1:6153 config set locale zh` does not save the proxy. Persist values with `config set`.

## Config file

The path is `$XDG_CONFIG_HOME/jav/config.json`, or `~/.config/jav/config.json` when `XDG_CONFIG_HOME` is unset. The directory is mode `0700`, the file is mode `0600`, and writes are atomic.

| Use | Flag | Environment | Key |
| --- | --- | --- | --- |
| Login cookie | `--cookies` | `JAVDB_COOKIES` | `cookies` |
| SOCKS5 proxy | `--proxy` | `SOCKS5_PROXY` | `proxy` |
| UI locale | `--locale` | `JAVDB_LOCALE` | `locale` |

Only these three keys are accepted. Any other `config set` key fails with `unknown config key: nope (supported: cookies, proxy, locale)`.

These two settings are environment-only. `config set` cannot store them:

| Variable | Effect |
| --- | --- |
| `JAVDB_BASE_URL` | Site origin. Default `https://javdb.com`. A trailing `/` is stripped |
| `JAVDB_TLS_INSECURE` | `1`, `true`, `yes`, or `on` (any case) skips TLS verification. Set this only when the user explicitly asks |

With no cookie, the client sends `over18=1; theme=auto; locale=<locale>`. With a cookie, it replaces an existing `locale` value, or appends `locale` when it is absent. `over18` and `theme` are not added to a cookie the user supplied.

The locale defaults to `zh`. Any non-empty string is stored and sent as the `locale` cookie.

Bookmark reads and writes, and some uncensored or FC2 pages, need a browser session cookie.

## Proxy forms

Accepted forms:

- `127.0.0.1:6153`
- `socks5://127.0.0.1:6153`
- `user:pass@127.0.0.1:6153`
- `socks5://user:pass@127.0.0.1:6153`
- `socks://...` and `socks5h://...` (used as SOCKS5)
- IPv6: `[::1]:1080`

`http://` and `https://` are rejected. Username and password are at most 255 bytes. Percent-encode `@`, `:`, and `/` in the password, for example `socks5://user:p%40ss@127.0.0.1:6153`. If the proxy has a password, tell the user that an authenticated proxy is set. Do not repeat the URL.

## Commands

```bash
javcli config path
javcli config set proxy "127.0.0.1:6153"
javcli config set locale zh
javcli config unset cookies
javcli config get locale
```

`path` returns only the path:

```json
{"path": "/home/user/.config/jav/config.json"}
```

A successful `set`:

```json
{"message": "Successfully set locale", "key": "locale", "value": "zh"}
```

`get` returns `{"key","value"}`. `list` includes only non-empty keys. An empty config is `{}`. `unset` returns `message` and `key`, not the old value.

Use these subcommands unless the user explicitly asks to edit the file. A hand edit keeps mode `0600`. Do not paste the file into the chat.

## Cookies and proxy passwords

`config set`, `config get`, and `config list` print the cookie and proxy URL on stdout. Check what is set with this filter so the tool output contains only status:

```bash
javcli config list | python3 -c 'import json,sys; d=json.load(sys.stdin); print("cookies" if d.get("cookies") else "no-cookies"); print("proxy" if d.get("proxy") else "no-proxy"); print("locale=" + d.get("locale",""))'
```

Prefer that the user run `javcli config set cookies '...'` in their own terminal. If they already pasted a cookie into the chat and asked to save it, write it, then say only that it was saved. Do not repeat the value, and do not run `config get cookies`. Do not write the cookie into the repository, the skill, or a commit.

Treat a proxy password the same way. Repeat the host and port from `config get proxy` only when the proxy URL has no user info.
