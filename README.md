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
reboots — including a self-test against four real sites (Discord, TikTok,
YouTube, Google) every time it starts, with an email either way so you
never have to go check yourself. Nothing here needs a manual restart, but
`restart-proxy` forces one if you ever want to.

→ **[How the self-healing works, the AI triage, and the logs](docs/self-healing.md)**

## One-time setup

Add four secrets at
[github.com/settings/codespaces](https://github.com/settings/codespaces),
scoped to this repo, then stop and restart the Codespace. Everything else
installs itself the first time the Codespace is created.

→ **[What each secret is for and where to get it](docs/setup.md)**

## Built on

This is a personal setup built on top of
[vproxy](https://github.com/0x676e67/vproxy), a proxy server by
[0x676e67](https://github.com/0x676e67). Released under
[GPL-3.0](./LICENSE).
