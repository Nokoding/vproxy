# How the self-healing works

## The stack

A small set of processes, watching itself:

- **vproxy** — the proxy itself, running twice: a regular (plain HTTP,
  default port 8080 → `bore.pub:54584`) and a secure (TLS, default port
  8443 → `cdspc.duckdns.org:54585`) instance. Every one of those ports is
  changeable — see **Changing ports or the TLS domain** below.
- **bore** — the outbound tunnel that makes each vproxy instance reachable
  from the internet, also running twice (one per vproxy instance).
- **A watchdog** — every 30 seconds, sends a real request through the
  regular proxy. If it hangs or times out, kills and restarts vproxy +
  bore — checking that things actually *work*, not just that the
  processes are still alive.
- **A local AI model** (Ollama, running entirely inside the Codespace) —
  when the watchdog catches a failure, reads the recent logs and decides
  whether it's worth emailing you about right now, versus a repeat of
  something already reported. If the model is ever down or slow, a fixed
  fallback rule takes over instead, so alerting never silently depends on
  it.
- **A startup self-test** — see below.
- **Email alerts** — sent via MailerSend, only when the AI (or the
  fallback rule) decides you should know.

Every one of the above respawns automatically if it crashes or the
Codespace itself restarts. Nothing here needs manual intervention — but if
you ever want to force a full restart of everything:

```bash
restart-proxy
```

That restarts vproxy, both tunnels, the watchdog, and the local AI, then
prints the current addresses.

## The startup self-test

Every time the proxy (re)starts — including after a crash-recovery, a
manual `restart-proxy`, or a fresh Codespace — it runs a real test against
four sites (Discord, TikTok, YouTube, and Google), through both the
regular and secure proxy, before declaring itself ready:

1. **All four pass** → you get an email confirming it's good, along with a
   one-line comment from the local AI.
2. **Anything fails** → it restarts vproxy + bore (the same recovery the
   watchdog uses), emails you that it's attempting a repair, and re-tests.
3. **Still failing after the repair** → you get an email with the retest
   results and the AI's best guess at a next diagnostic step. It also
   leaves a note for the next time this repo is opened with an AI coding
   assistant, so troubleshooting doesn't start from scratch.

This means a status email after every restart, either way — you never
have to go check for yourself whether it's actually working.

## Logs

```bash
tail -f /tmp/vproxy.log            # the regular proxy
tail -f /tmp/vproxy-tls.log        # the secure proxy
tail -f /tmp/bore.log              # the tunnel (regular)
tail -f /tmp/bore-tls.log          # the tunnel (secure)
tail -f /tmp/proxy-watchdog.log    # health checks and restarts
tail -f /tmp/quick-test.log        # the startup self-test
tail -f /tmp/ollama.log            # the local AI
tail -f /tmp/acme.log              # the secure certificate
```

## Changing ports or the TLS domain

Every port here is configurable — the local container ports, and the
public bore.pub ports your device actually connects to:

```bash
configure-proxy
```

It shows the current effective values and offers two ways to change them:

1. **Codespaces secrets** (`LOCAL_HTTP_PORT`, `LOCAL_TLS_PORT`,
   `BORE_HTTP_PORT`, `BORE_TLS_PORT`) — survives a full Codespace rebuild,
   not just a stop/start. Requires a Codespace restart to take effect,
   same as the other secrets (see `docs/setup.md`).
2. **Enter values right there in the terminal** — takes effect
   immediately (it offers to run `restart-proxy` for you), but is wiped
   on a rebuild unless you also add secrets for it.

A real Codespaces secret always wins over a value entered through option
2. `restart-proxy` prints a reminder to run `configure-proxy` any time
you're still on the defaults.

## Checking port health directly

If something seems down, `port-check` gives a direct read on both proxy
ports — process alive, port actually listening, a local test request, and
a real request through the public tunnel:

```bash
port-check
```

**Important:** the Codespaces "Ports" tab (and `gh codespace ports`) does
**not** need to list either local port for the proxy to be working. bore
opens its own outbound connection to `bore.pub`, completely separate from
Codespaces' own port-forwarding — so those ports showing as absent/offline
there is normal, not a sign of a problem. `port-check` is the accurate
signal; the Ports tab isn't.
