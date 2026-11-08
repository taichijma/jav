# 配置 javcli

配置只影响以后的请求。`javcli version` 不读配置。

## 优先级

命令行全局参数，然后是环境变量，然后是配置文件。某一级是空字符串时跳过，使用下一级。因此 `--proxy ""` 或空的 `SOCKS5_PROXY` **不会**关掉已经写在配置文件里的代理。要直连，先 `javcli config unset proxy`，并去掉环境里的 `SOCKS5_PROXY`。

全局参数可以写在子命令前或后，只对这一次生效：

```bash
javcli --proxy 127.0.0.1:6153 search "SSNI-678"
javcli search "SSNI-678" --locale zh
```

`javcli --proxy 127.0.0.1:6153 config set locale zh` 不会把代理存进配置文件。要持久化就用 `config set`。

## 配置文件

路径是 `$XDG_CONFIG_HOME/jav/config.json`，未设置 `XDG_CONFIG_HOME` 时是 `~/.config/jav/config.json`。目录权限 `0700`，文件权限 `0600`，写入是原子替换。

| 用途 | 命令行 | 环境变量 | 配置键 |
| --- | --- | --- | --- |
| 登录 Cookie | `--cookies` | `JAVDB_COOKIES` | `cookies` |
| SOCKS5 代理 | `--proxy` | `SOCKS5_PROXY` | `proxy` |
| 界面语言 | `--locale` | `JAVDB_LOCALE` | `locale` |

只认这三个键。`config set` 其它键会失败，错误形如 `unknown config key: nope (supported: cookies, proxy, locale)`。

下面两项只能放在环境变量里，不能 `config set`：

| 环境变量 | 作用 |
| --- | --- |
| `JAVDB_BASE_URL` | 站点根 URL，默认 `https://javdb.com`。末尾的 `/` 会被去掉 |
| `JAVDB_TLS_INSECURE` | `1`、`true`、`yes`、`on`（大小写不敏感）时跳过 TLS 校验。只在用户明确要求时设置 |

未提供 Cookie 时，客户端仍发送 `over18=1; theme=auto; locale=<语言>`。提供了 Cookie 时，把其中的 `locale` 换成当前语言；原来没有 `locale` 就追加。`over18` 和 `theme` 不会自动补进用户提供的 Cookie。

语言省略时是 `zh`。配置值是任意字符串，原样写入 `locale` cookie。

收藏的读写，以及部分无码 / FC2 页面，需要浏览器登录后的会话 Cookie。

## 代理写法

接受这些形式：

- `127.0.0.1:6153`
- `socks5://127.0.0.1:6153`
- `user:pass@127.0.0.1:6153`
- `socks5://user:pass@127.0.0.1:6153`
- `socks://...` 与 `socks5h://...`（按 SOCKS5 使用）
- IPv6：`[::1]:1080`

不接受 `http://` 或 `https://`。用户名、密码最长 255 字节。密码里的 `@`、`:`、`/` 要做 URL 编码，例如 `socks5://user:p%40ss@127.0.0.1:6153`。回复里如果代理带密码，只说「已设置带认证的代理」，不要写出 URL。

## 命令

```bash
javcli config path
javcli config set proxy "127.0.0.1:6153"
javcli config set locale zh
javcli config unset cookies
javcli config get locale
```

`path` 只返回路径：

```json
{"path": "/home/user/.config/jav/config.json"}
```

`set` 成功：

```json
{"message": "Successfully set locale", "key": "locale", "value": "zh"}
```

`get` 返回 `{"key","value"}`。`list` 只包含非空键，空配置是 `{}`。`unset` 返回 `message` 和 `key`，不含旧值。

用户没有明确要求手改文件时，用这些子命令。手改时保持 `0600`，不要把文件内容贴进对话。

## Cookie 和代理密码

`config set`、`config get`、`config list` 会把 Cookie 和代理 URL 写进 stdout。判断是否已设置时用下面的过滤，让工具输出里只有状态：

```bash
javcli config list | python3 -c 'import json,sys; d=json.load(sys.stdin); print("cookies" if d.get("cookies") else "no-cookies"); print("proxy" if d.get("proxy") else "no-proxy"); print("locale=" + d.get("locale",""))'
```

设置 Cookie 时优先请用户在自己的终端执行 `javcli config set cookies '...'`。用户已经把 Cookie 发在对话里、并要求保存时，可以代为写入；回复里只说「已写入」，不要重复这个值，也不要再 `config get cookies`。不要把 Cookie 写进仓库、技能文件或提交。

带密码的代理同样处理。`config get proxy` 只在代理没有用户信息时，才可以把主机和端口告诉用户。
