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
