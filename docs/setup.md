# One-time setup

Everything except four secrets installs and configures itself the first
time the Codespace is created. Add these at
[github.com/settings/codespaces](https://github.com/settings/codespaces),
scoped to this repo — never put them in the code itself.

| Secret | What it's for | Where to get it |
|---|---|---|
| `MAILERSEND_API_TOKEN` | Sends the alert/status emails | Create a free account at [mailersend.com](https://www.mailersend.com), verify a sending domain, then create an API token under **Settings → API Tokens** |
| `MAILERSEND_FROM` | The address alerts come from | Any address on the domain you verified with MailerSend (e.g. `alerts@yourdomain.com`) |
| `DUCKDNS_TOKEN` | Keeps the domain pointed at the tunnel, and proves ownership for the secure certificate | Sign in at [duckdns.org](https://www.duckdns.org) with GitHub/Google — your token is shown on the main page |
| `DUCKDNS_DOMAIN` | Your domain's short name | The subdomain you create at duckdns.org, e.g. `cdspc` — **not** `cdspc.duckdns.org` (see below) |

`DUCKDNS_DOMAIN` is deliberately the bare subdomain, not the full
hostname — DuckDNS's own update API expects the short form, and the code
appends `.duckdns.org` itself wherever the full domain is actually needed
(like requesting the TLS certificate).

## After adding secrets

Stop and restart the Codespace. A new terminal in the same running
Codespace isn't enough — secrets are only injected when the container
starts.

That's it. On the next start the proxy comes up on its default ports,
open (no username/password), in normal mode. To change any of that, see
[Configuration](configuration.md).

## What happens if a secret is missing

None of this is required to get a *working* proxy — each secret unlocks
an optional piece, and everything else keeps running without it:

- **No `MAILERSEND_*`** — the proxy still runs and still self-heals; you
  just won't get status or alert emails. They're skipped silently and
  logged to `/tmp/proxy-watchdog.log`.
- **No `DUCKDNS_*`** — the secure (TLS) proxy has no stable hostname to
  issue a certificate for, so that variant doesn't start. The regular
  proxy is unaffected.
- **No optional settings at all** — ports fall back to their defaults,
  `PROXY_MODE` to `normal`, and the proxy runs with no
  username/password. All of those are covered in
  [Configuration](configuration.md).
