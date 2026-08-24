# vproxy

Your own private proxy. It lives in a free GitHub Codespace, runs itself,
and works from any device — no server to rent, no domain to buy.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/Nokoding/vproxy)

Click that and GitHub forks this repo to your own account and opens a
Codespace on it — no manual forking step. Add four secrets
([one-time setup](docs/setup.md)), restart the Codespace, and you have
your own proxy under your own account.

## What you get

- A regular and a TLS-cloaked proxy, both reachable from any device.
- Restarts itself on a crash, a hang, or a Codespace reboot, and rebuilds
  itself from scratch after a full container wipe.
- Tests itself against four real sites on every start and emails you the
  result, so you're never guessing whether it's up. (Failures always;
  clean passes too, unless you switch to
  [performance mode](docs/configuration.md#performance-mode).)
- Free: a Codespace, a free tunnel relay, a free subdomain, a free
  certificate.

## How it works

A Codespace can't accept incoming connections, so vproxy reaches *out*
instead, using [bore](https://github.com/ekzhang/bore) to open a tunnel
to a public relay. Your device connects to the relay, and the relay hands
the traffic straight through to vproxy inside the Codespace.

```
your device  →  bore.pub  →  the Codespace  →  vproxy
```

Because that relay is free and shared, expect the proxy to slow down —
not fail — under heavy load, like a page pulling down a lot of images at
once.

## Connect a device

Point your device's proxy settings at one of these:

| Type | Address | Port |
|---|---|---|
| Regular | `bore.pub` | `54584` |
| Secure (TLS) | `cdspc.duckdns.org` | `54585` |

Or skip typing host and port by hand and point the device at the
auto-config URL instead: `http://bore.pub:54586/proxy.pac`.

Prefer the secure one where your device supports it — it looks like
ordinary encrypted web traffic to anything watching the network. One
catch: iPhone/iPad's built-in Wi-Fi proxy settings can't use it (there's
nowhere to say the proxy itself speaks TLS), so use the regular address
there.

Those are this fork's current values, and every one of them is yours to
change. Two things worth knowing before you hand the address around:

- There's **no username or password by default**, so anyone who finds the
  address can use your proxy.
- `restart-proxy` prints the live addresses any time you forget them.

→ **[Ports, the TLS domain, authentication, performance mode](docs/configuration.md)**

## Get started

1. Click the Codespaces badge above.
2. Add the four secrets — see **[One-time setup](docs/setup.md)**.
3. Stop and restart the Codespace, then connect a device using the table
   above.

Everything else — installing vproxy, the tunnels, the certificate, the
watchdog — happens on its own the first time the Codespace is created.

## Day to day

Three commands, none of them required in normal use:

| Command | What it does |
|---|---|
| `restart-proxy` | Forces a full restart; prints the current addresses, mode, and auth state |
| `configure-proxy` | Changes ports, auth, or performance mode, interactively |
| `port-check` | Tells you what's actually alive, listening, and reachable |

It also keeps the Codespace from auto-stopping after 30 minutes idle, so
you don't need to leave a tab open.

→ **[How the self-healing works — the watchdog, the AI triage, the logs](docs/self-healing.md)**

## If something seems broken

Run `port-check` first. In particular, the Codespace's own "Ports" tab
will never list these ports as active, even when everything is perfectly
healthy — that's expected, not a symptom (bore's tunnel is a separate
outbound connection, unrelated to Codespaces' port forwarding).

→ **[port-check and the logs](docs/self-healing.md#port-check)**

## Docs

- **[One-time setup](docs/setup.md)** — the four secrets, where to get
  them, and what breaks if one's missing.
- **[Configuration](docs/configuration.md)** — ports, the TLS domain,
  authentication, the `.pac` URL, performance mode.
- **[How the self-healing works](docs/self-healing.md)** — the watchdog,
  the local AI triage, the startup self-test, `port-check`, and the logs.

## Built on

This is a personal setup built on top of
[vproxy](https://github.com/0x676e67/vproxy), a proxy server by
[0x676e67](https://github.com/0x676e67). Released under
[GPL-3.0](./LICENSE).
