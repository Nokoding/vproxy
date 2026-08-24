# How the self-healing works

This page is about the reliability machinery: what watches what, what
restarts what, and where to look when something seems off. For changing
ports, the TLS domain, auth, the `.pac` URL, or performance mode, see
[Configuration](configuration.md).

## The stack

A small set of processes, watching itself:

- **vproxy** — the proxy itself, running twice: a regular instance (plain
  HTTP, local port 8080 → `bore.pub:54584`) and a secure one (TLS, local
  port 8443 → `cdspc.duckdns.org:54585`). If the TLS certificate can't be
  issued, only the secure half is skipped; the regular proxy is
  unaffected.
- **bore** — the outbound tunnel that makes each of those reachable from
  the internet, running three times: once per vproxy instance, plus once
  for the `.pac` auto-config file.
- **A watchdog** — every 30 seconds, sends a real request through the
  regular proxy. If it hangs or times out, it kills and restarts vproxy +
  bore — so it's checking that things actually *work*, not just that the
  processes are still alive.
- **A local AI model** (Ollama's `llama3.2:3b`, running entirely inside
  the Codespace — nothing leaves it) — when the watchdog catches a
  failure, it reads the recent logs and decides whether this is worth
  emailing you about right now, or a repeat of something already
  reported. If the model is down or slow, a fixed throttle rule takes
  over instead, so alerting never silently depends on it.
- **A startup self-test** — see [below](#the-startup-self-test).
- **Email alerts** — sent via MailerSend, only when the AI (or the
  fallback rule) decides you should know.
- **A keepalive** — quietly pokes the Codespace's terminal every 20
  minutes so GitHub's 30-minute idle auto-stop never kicks in. It has
  nothing to do with the proxy's health; it just rides along on the same
  startup lifecycle.

Every one of these respawns automatically if it crashes, and all of them
come back if the Codespace restarts. A full Codespace *rebuild* wipes the
container entirely — every binary, every log — and it all reinstalls and
relaunches itself with no manual steps; your git repo and your Codespaces
secrets are what survive.

Nothing here needs manual intervention, but if you ever want to force a
full restart:

```bash
restart-proxy
```

That restarts vproxy, all three tunnels, the watchdog, the keepalive, and
the local AI, then prints the current addresses, mode, and whether auth is
on.

## The startup self-test

Every time the proxy (re)starts — after a crash-recovery, a manual
`restart-proxy`, or a fresh Codespace — it runs a real test against four
sites (Discord, TikTok, YouTube, and Google), through both the regular and
the secure proxy, before declaring itself ready:

1. **Everything passes** → you get an email confirming it's good, with a
   one-line comment from the local AI. (In
   [performance mode](configuration.md#performance-mode) this is a log
   line instead of an email.)
2. **Anything fails** → it restarts vproxy + bore (the same recovery the
   watchdog uses), emails you that it's attempting a repair, and re-tests.
3. **Still failing after the repair** → you get an email with the retest
   results and the AI's best guess at a next diagnostic step. It also
   leaves a dated note in the repo for the next time this project is
   opened with an AI coding assistant, so troubleshooting doesn't start
   from scratch.

So in normal mode there's a status email after every restart either way —
you never have to go check for yourself whether it's actually working.
Performance mode drops only the "everything's fine" one.

## port-check

If something seems down, this gives a direct, always-finishes read on
every variant (regular, secure, and the `.pac` server): process alive,
port actually listening, a local test request, whether the bore tunnel is
currently connected, and a real request through the public tunnel. It also
prints the current mode and whether auth is on:

```bash
port-check
```

It's a diagnostic report, not a health gate — it never "fails", it just
tells you what it found.

**Important:** the Codespaces "Ports" tab (and `gh codespace ports`) does
**not** need to list these ports for the proxy to be working — in fact it
never will. bore opens its own outbound connection to `bore.pub`,
completely separate from Codespaces' own port-forwarding, so those ports
being absent there is normal and not a sign of a problem. `port-check` is
the accurate signal; the Ports tab isn't.

## Logs

```bash
tail -f /tmp/vproxy.log            # the regular proxy
tail -f /tmp/vproxy-tls.log        # the secure proxy
tail -f /tmp/bore.log              # the tunnel (regular)
tail -f /tmp/bore-tls.log          # the tunnel (secure)
tail -f /tmp/pac-server.log        # the .pac auto-config server
tail -f /tmp/bore-pac.log          # the tunnel (.pac)
tail -f /tmp/proxy-watchdog.log    # health checks and restarts
tail -f /tmp/quick-test.log        # the startup self-test
tail -f /tmp/ollama.log            # the local AI
tail -f /tmp/acme.log              # the secure certificate
```

These live in `/tmp`, so they're wiped by a Codespace rebuild along with
everything else in the container.
