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

`DUCKDNS_DOMAIN` is deliberately the bare subdomain, not the full hostname
— DuckDNS's own update API expects the short form, and the code appends
`.duckdns.org` itself wherever the full domain is actually needed (like
requesting the TLS certificate).

## Ports (optional)

Every port is also changeable — the four secrets below, or the
`configure-proxy` command, whichever you prefer:

| Secret | What it's for | Default |
|---|---|---|
| `LOCAL_HTTP_PORT` | Container-local port for the plain proxy | `8080` |
| `LOCAL_TLS_PORT` | Container-local port for the TLS proxy | `8443` |
| `BORE_HTTP_PORT` | Public bore.pub port for the plain proxy | `54584` |
| `BORE_TLS_PORT` | Public bore.pub port for the TLS proxy | `54585` |

→ **[Changing ports or the TLS domain](self-healing.md#changing-ports-or-the-tls-domain)**

## Performance mode (optional)

Set the `PROXY_MODE` secret to `performance` (or use `configure-proxy`) to
run core proxy functionality only: the local AI model never starts, and
the routine "all good" startup-test email is skipped. Self-healing —
auto-restart on crash/hang, and emailing when a real failure is detected
— stays on either way. Default is `normal` (AI triage + routine emails
on). See [self-healing.md](self-healing.md#performance-mode) for details.

## After adding secrets

Stop and restart the Codespace — a new terminal in the same running
Codespace isn't enough, since secrets are only injected at container start.

## What each secret enables if missing

Nothing here is required to get a working proxy — secrets unlock optional
pieces, and everything else keeps working if one is missing:

- No `MAILERSEND_*`: the proxy still runs and self-heals, you just won't
  get status/alert emails (skipped silently, logged to
  `/tmp/proxy-watchdog.log`).
- No `DUCKDNS_*`: the secure (TLS) proxy variant won't have a stable
  hostname to issue a certificate for, so it won't start — the regular
  proxy is unaffected either way.
- No `LOCAL_HTTP_PORT`/`LOCAL_TLS_PORT`/`BORE_HTTP_PORT`/`BORE_TLS_PORT`:
  every port just uses its default above — nothing else is affected.
- No `PROXY_MODE`: runs in `normal` mode (AI triage + routine emails on).
