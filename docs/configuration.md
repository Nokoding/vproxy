# Configuration

Everything here is optional — the proxy works out of the box on its
defaults. This page covers changing those defaults: ports, the TLS
domain, a username/password, the auto-config URL, and performance mode.

For the secrets you actually *need* to set once (email alerts and the TLS
domain), see [One-time setup](setup.md).

## The `configure-proxy` command

One command handles all of it:

```bash
configure-proxy
```

It prints the current effective values, then offers two ways to change
them:

1. **Codespaces secrets** — it tells you which secret names to add at
   [github.com/settings/codespaces](https://github.com/settings/codespaces).
   These survive a full Codespace rebuild, and take effect on the next
   Codespace start (a fresh terminal isn't enough — secrets are only
   injected when the container starts).
2. **Enter values right there in the terminal** — takes effect
   immediately (it offers to run `restart-proxy` for you), but is stored
   inside the container, so it survives a stop/start and is wiped by a
   rebuild.

Precedence, highest first:

**Codespaces secret** → **value entered via `configure-proxy`** →
**built-in default**

So a real secret always wins over a value typed into the terminal. If
you've never configured anything, `restart-proxy` prints a one-line
reminder to run `configure-proxy`.

## Ports

Six ports, all changeable. The "local" ones are inside the container and
you'll rarely care about them; the `bore.pub` ones are what your devices
actually connect to.

| Secret | What it's for | Default |
|---|---|---|
| `LOCAL_HTTP_PORT` | Container-local port for the regular proxy | `8080` |
| `LOCAL_TLS_PORT` | Container-local port for the secure (TLS) proxy | `8443` |
| `BORE_HTTP_PORT` | Public bore.pub port for the regular proxy | `54584` |
| `BORE_TLS_PORT` | Public bore.pub port for the secure (TLS) proxy | `54585` |
| `LOCAL_PAC_PORT` | Container-local port for the `.pac` auto-config file | `8090` |
| `BORE_PAC_PORT` | Public bore.pub port for the `.pac` auto-config file | `54586` |

Set them as secrets, or through `configure-proxy` — it validates as you
go (rejects anything above 65535, and rejects reusing the same number
twice among the three local ports or among the three public ones).

One caveat on the public ports: bore.pub hands them out first-come, so a
port you ask for may already be taken, in which case bore falls back to a
random one. `restart-proxy` prints the port it *asked* for, which is
normally also the one it got. If that ever isn't true,
[`port-check`](self-healing.md#port-check) reports the tunnel as NOT
connected on the configured port, and `/tmp/bore.log` has the port it
actually got.

## The TLS domain

The secure proxy's hostname comes from your `DUCKDNS_DOMAIN` /
`DUCKDNS_TOKEN` secrets, and its certificate is issued for that same
name. Changing the hostname means changing those two secrets — see
[One-time setup](setup.md), which also explains why `DUCKDNS_DOMAIN` is
the bare subdomain (`cdspc`) and not the full `cdspc.duckdns.org`.

The domain's A record is repointed at the tunnel's current IP on every
restart, so it keeps resolving even though bore.pub's address isn't
fixed.

## Authentication

By default this proxy has **no username or password**. Its address is a
port on a public relay — not secret, and findable by anyone scanning — so
anyone who has it can use your proxy. Turning auth on is the fix:

```bash
configure-proxy
```

Set **both** `PROXY_USERNAME` and `PROXY_PASSWORD`, either as Codespaces
secrets or through `configure-proxy`'s "enter values now" option (the
password prompt hides what you type). Setting only one of the two leaves
auth **off** — both are required together, and `restart-proxy` logs a
warning if it sees exactly one, since that's almost always a typo in a
secret name.

Once it's on, every device connecting through the proxy has to supply
that username and password; most browsers and OSes prompt for it the
first time. Both `restart-proxy` and
[`port-check`](self-healing.md#port-check) print whether auth is
currently on.

## Auto-config (`.pac`) URL

Instead of typing a proxy host and port into each device, point it at:

```
http://bore.pub:54586/proxy.pac
```

(or whatever `BORE_PAC_PORT` is set to — `restart-proxy` prints the exact
URL). The file is regenerated on every restart, so it always points at
the currently-configured regular proxy address.

The `.pac` format has no syntax for credentials, so it can't carry them:
with [authentication](#authentication) on, devices using this URL still
get prompted for the username/password by the proxy itself.

## Performance mode

| Secret | Values | Default |
|---|---|---|
| `PROXY_MODE` | `normal`, `performance` | `normal` |

By default the local AI model stays resident and every startup self-test
sends a status email. If you'd rather the Codespace's CPU and RAM went
entirely to the proxy itself, switch to `performance` — as a secret, or
through `configure-proxy`, same as everything else. In performance mode:

- The local AI model never starts, so no RAM or CPU is held for it.
- The startup self-test still runs, but a clean pass just logs a line to
  `/tmp/quick-test.log` instead of emailing you. Failure emails
  (repair-attempted, still-failing) are unchanged.

**Self-healing is not affected by the mode.** The watchdog still kills
and restarts things on a hang, and still emails you when it detects a
real failure, in both modes — it just uses the fixed fallback wording
instead of an AI-written diagnosis, exactly as it already does whenever
the AI model happens to be down or slow in normal mode. See
[How the self-healing works](self-healing.md).

`restart-proxy` and `port-check` both print the current mode.

Worth knowing before you reach for this: the throughput ceiling here is
the free bore.pub relay, not the Codespace (measured at roughly 14.5 MB/s
through the tunnel versus 122 MB/s direct, plus about 275 ms of added
latency). Performance mode trims background load competing for the
container's CPU and RAM; it can't move that ceiling.
