# vproxy

Your own private proxy. It lives in a free GitHub Codespace, runs itself,
and works from any device — no server to rent, no domain to buy.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/Nokoding/vproxy)

Click that, and GitHub forks this repo to your own account and opens a
Codespace on it — no manual forking step needed. Then add your own secrets
(see **One-time setup** below) and you have your own copy of this proxy,
under your own account.

## How it works

A Codespace can't take incoming connections, so vproxy reaches *out*
instead, using [bore](https://github.com/ekzhang/bore) to open a tunnel to
a public relay. Your device connects to that relay. The relay hands the
traffic straight through to vproxy, running quietly inside the Codespace.

```
your device  →  bore.pub  →  the Codespace  →  vproxy
```

## Connect

Point your device's proxy settings here:

| Type | Address | Port |
|---|---|---|
| Regular | `bore.pub` | `54584` |
| Secure (TLS) | `cdspc.duckdns.org` | `54585` |

No username or password needed.

Use the secure one if your device supports it — it looks like ordinary
encrypted web traffic to anything watching the network. One catch:
iPhone/iPad's built-in Wi-Fi proxy settings can't use the secure address —
use the regular one there instead.

Because it runs through a free, shared relay, expect it to slow down (not
fail) under heavy load, like a page loading a lot of images at once.

## It fixes itself

Everything restarts on its own if it crashes, hangs, or the Codespace
reboots. Nothing here needs a manual restart — but if you ever want to
force one:

```bash
restart-proxy
```

That one command restarts vproxy, the tunnel, the health checks, and the
small AI that watches for trouble, then prints the current addresses.

Logs, if you want them:

```bash
tail -f /tmp/vproxy.log            # the regular proxy
tail -f /tmp/vproxy-tls.log        # the secure proxy
tail -f /tmp/bore.log              # the tunnel (regular)
tail -f /tmp/bore-tls.log          # the tunnel (secure)
tail -f /tmp/proxy-watchdog.log    # health checks and restarts
tail -f /tmp/ollama.log            # the local AI
tail -f /tmp/acme.log              # the secure certificate
```

## What's running

A small stack, watching itself:

- **vproxy** — the proxy, running twice (regular and secure)
- **bore** — the tunnel out to the internet, also running twice
- **A watchdog** — checks every 30 seconds that things actually work, not
  just that they're still alive
- **A local AI model** — reads the logs when something fails and decides
  whether it's worth an email
- **Email alerts** — sent only when the AI (or a simple backup rule, if
  the AI is ever unavailable) thinks you should know

## One-time setup

Add four secrets at
[github.com/settings/codespaces](https://github.com/settings/codespaces),
scoped to this repo. Never put these in the code itself.

| Secret | What it's for |
|---|---|
| `MAILERSEND_API_TOKEN` | Sends the alert emails |
| `MAILERSEND_FROM` | The address alerts come from |
| `DUCKDNS_TOKEN` | Keeps the domain pointed at the tunnel, and proves ownership for the secure certificate |
| `DUCKDNS_DOMAIN` | Your domain's short name (e.g. `cdspc`, not `cdspc.duckdns.org`) |

After adding or changing a secret, stop and restart the Codespace — a new
terminal isn't enough.

Everything else installs itself the first time the Codespace is created.

## Built on

This is a personal setup built on top of
[vproxy](https://github.com/0x676e67/vproxy), a proxy server by
[0x676e67](https://github.com/0x676e67). Released under
[GPL-3.0](./LICENSE).
