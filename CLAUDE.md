# Project context (personal proxy fork)

This is a fork of upstream `vproxy` repurposed as a free, self-healing
personal proxy running inside a GitHub Codespace. The upstream project
(HTTP/HTTPS/SOCKS5 proxy server) is basically untouched; everything specific
to this fork lives in `.devcontainer/`. `README.md` (plus `docs/setup.md`
and `docs/self-healing.md`, which it links out to) is the user-facing
writeup — this file is the running internal context, kept up to date after
every change so a future session (including after a Codespace rebuild,
which wipes the container but not git or Codespaces secrets) doesn't have
to re-derive it from commit history.

**Update this file after every change made in this repo, and especially
after any big/structural change** (new component, changed architecture,
new secret, new failure mode) **— don't let it go stale.** Add to it, don't
just append — fold new facts into the relevant section, and remove
anything that's no longer true. If a change also affects what a user
forking this repo needs to know, update `README.md` and the relevant
`docs/*.md` page too, not just this file.

`AGENTS.md` is a symlink to this file, so any AI coding tool that looks for
the generic `AGENTS.md` convention (not just Claude Code) gets this same
context automatically if the repo is forked and opened in a Codespace.
Keep editing `CLAUDE.md` as the real file — don't break the symlink by
writing to `AGENTS.md` directly or making it a separate copy.

## What's running and why

- `vproxy` (plain HTTP) on container-local `0.0.0.0:8080` → tunneled by
  `bore` to `bore.pub:54584`. The original/simplest path, works everywhere.
- `vproxy` (HTTPS) on container-local `0.0.0.0:8443` → tunneled by a second
  `bore` to `bore.pub:54585`, reachable at `cdspc.duckdns.org:54585`. Added
  2026-08-20 so the proxy can pass as ordinary HTTPS traffic (real
  Let's Encrypt cert, normal TLS handshake) on networks that block/inspect
  plain HTTP proxying. Purely additive — if TLS cert issuance fails, only
  this half is skipped; the plain HTTP proxy is unaffected. 8443 was picked
  arbitrarily as a second local port, not significant beyond that.
- Codespaces port visibility (`gh codespace ports visibility`) is flipped to
  public for both 8080 and 8443 on every restart. This is *not* actually
  required for bore to work (bore makes an outbound-only connection to
  bore.pub, unaffected by Codespaces' own port-forwarding visibility —
  confirmed by testing) but is kept for direct-access/debugging convenience.
- `bore` is required because Codespaces port forwarding is an
  HTTPS-terminating reverse proxy (`*.app.github.dev`), not raw TCP
  passthrough — a device dialing a forwarded port directly gets rejected.
  Same reason `cloudflared` quick tunnels don't work here either.
- Watchdog health-checks the (plain HTTP) proxy every 30s and kills+respawns
  vproxy/bore on crash or hang; a local Ollama model (`llama3.2:3b`)
  triages failures to decide alert-worthiness, falling back to a fixed
  throttle rule if Ollama's unavailable. Alerts go out via MailerSend to
  nokodash311@gmail.com.
- `port-check.sh` (symlinked to `/usr/local/bin/port-check`, same pattern
  as `restart-proxy`) is an on-demand troubleshooting command: for each
  proxy port, reports process-alive, actually-listening, a local curl
  test, bore tunnel connection status (from the log), and a real curl
  through the public tunnel. Added 2026-08-21 after confirming live that
  everything can check out fully healthy end-to-end while `gh codespace
  ports` lists neither 8080 nor 8443 at all — see the gotcha below. Always
  exits 0; it's a diagnostic report, not a health gate.
- On every startup, `restart-proxy.sh` backgrounds `quick-test-runner.sh`
  (after an 8s delay) to prove the proxy can actually reach the 4 sites the
  user tests with by hand — discord.com, tiktok.com, youtube.com,
  google.com — through both the plain (8080) and TLS (8443, if up) proxy
  variants (`quick-test.sh` does the actual checks). All pass → email
  "all good" with a one-line Ollama comment. Anything fails → kill+respawn
  vproxy/bore by PID (same recovery the 30s watchdog uses), email that a
  repair was attempted, retest, and email those results too. If the retest
  still fails, ask Ollama for one non-destructive next step, write full
  details to a new dated file under `.devcontainer/notes/`, and append a
  one-line pointer to this file (auto-read every session) so the next
  Claude Code session picks it up without hunting for a log. Added
  2026-08-21.
- `acme.sh` issues/renews the Let's Encrypt cert for the TLS proxy via a
  DuckDNS DNS-01 challenge (no inbound port needed). Cached in
  `~/.vproxy-tls/`, only reissued when <20 days from expiry, to stay well
  under Let's Encrypt's rate limits.
- The DuckDNS A record is repointed at bore.pub's current IP on every
  restart, both so `cdspc.duckdns.org` resolves to the tunnel and (as of
  the TLS work) so the domain is stable enough for cert issuance/renewal.

## Everything is ephemeral except git + Codespaces secrets

A Codespace *rebuild* wipes the whole container filesystem — installed
binaries, `/tmp` logs, everything — but NOT the git repo (pushed to origin)
or Codespaces secrets (injected fresh on every start). The entire
`.devcontainer/` setup is designed around this: `onCreateCommand` reinstalls
everything from scratch (`vproxy`, `bore`, `ollama` + model, `acme.sh`, and
now the `claude` CLI itself), and `postStartCommand` → `restart-proxy.sh`
relaunches all the processes. A rebuild should require zero manual
intervention. A plain Codespace *stop/start* (not rebuild) preserves the
container filesystem, so cached state like the TLS cert in `~/.vproxy-tls/`
survives that.

The `claude` CLI is installed via `postStart.sh` (`command -v claude ||
curl -fsSL claude.ai/install.sh | bash`) so a Claude Code session is always
available in the Codespace without a manual reinstall step after a rebuild.

## Gotchas learned the hard way

- **`gh codespace ports` (and the Codespaces "Ports" UI tab) will not list
  8080 or 8443, ever, and that's normal.** Confirmed 2026-08-21 while
  investigating a "the ports aren't online" report from the user: process
  alive, port listening, local curl, and a real curl through the public
  tunnel (`bore.pub:54584` / `cdspc.duckdns.org:54585`) were all healthy
  at the same moment `gh codespace ports` showed neither port at all. This
  is expected, not a bug — bore opens its own outbound connection to
  `bore.pub`, entirely separate from Codespaces' own port-forwarding, so
  those ports never get added to that list no matter how healthy they
  are. Don't diagnose from that list; use `port-check` (see above) or a
  direct curl instead.

- The base `mcr.microsoft.com/devcontainers/rust:1` image does **not**
  include `gh` (GitHub CLI) — confirmed 2026-08-21 that it was completely
  absent, meaning every `gh codespace ports visibility` call in
  `restart-proxy.sh` had been silently failing (output is redirected to
  `/dev/null`, and the whole block is best-effort so nothing else broke).
  `jq` happened to already be present (pulled in incidentally by something
  else in the image) but wasn't actually declared as a dependency either.
  Both are now explicit in `onCreateCommand`'s apt install line
  (`zstd git-lfs jq gh`) so a rebuild doesn't silently lose either one. `gh`
  needs no extra apt source on this image — it's in Debian trixie's default
  repos. It authenticates automatically via the Codespaces-injected
  `GITHUB_TOKEN`, no login step needed.

- **iOS's native Wi-Fi → Manual proxy settings cannot drive the TLS-cloaked
  proxy (port 54585 / `cdspc.duckdns.org`).** Confirmed 2026-08-20: iOS's
  manual proxy screen only has Server/Port/Auth fields, with no way to
  specify a TLS-secured connection to the proxy itself (unlike macOS's
  separate "Secure Web Proxy (HTTPS)" section in Network preferences). It
  sends a plain unencrypted CONNECT to the port, but vproxy there expects a
  TLS handshake first, so nothing loads — this looked like a broken setup
  but was actually just an iOS platform limitation; the server side worked
  fine (verified via curl before the user tested on-device). On iPad, use
  the plain proxy (`bore.pub:54584`) instead. Reaching the TLS variant from
  iOS would need a third-party proxy app exposing an explicit "https" proxy
  type (Shadowrocket, Quantumult X, Surge), not the native Settings app.

- The repo has a `pre-push` hook expecting `git-lfs`, but the base
  `mcr.microsoft.com/devcontainers/rust:1` image doesn't include it and
  there's no `.gitattributes` actually using LFS — so `git push` fails
  with an unhelpful error until `git-lfs` is installed. Added to
  `onCreateCommand`'s apt install line (2026-08-20) so this doesn't
  recur after a rebuild.

- `DUCKDNS_DOMAIN` is the **bare subdomain** (e.g. `cdspc`), matching what
  DuckDNS's own update API expects. Let's Encrypt needs the FQDN
  (`cdspc.duckdns.org`) — `tls-cert.sh` appends `.duckdns.org` itself if the
  value doesn't already contain a dot. Don't "fix" `DUCKDNS_DOMAIN` to be
  the FQDN; that'd break the existing DuckDNS A-record update call.
- acme.sh's DuckDNS DNS-01 hook expects the env var `DuckDNS_Token`
  (exact casing), not `DUCKDNS_TOKEN`.
- acme.sh's default CA is ZeroSSL (requires EAB registration) unless you
  pass `--server letsencrypt` explicitly — `tls-cert.sh` does this.

## Required Codespaces secrets

Set via Settings → Codespaces secrets, scoped to this repo:

- `MAILERSEND_API_TOKEN`, `MAILERSEND_FROM` — email alerts
- `DUCKDNS_TOKEN`, `DUCKDNS_DOMAIN` — DNS record + TLS cert DNS-01 challenge

## Loose ends / not yet wired up

- `serve-pac.sh` (repo root) references `RAILWAY_TCP_PROXY_DOMAIN` /
  `RAILWAY_TCP_PROXY_PORT`, which aren't set in the Codespace env — looks
  like a leftover from an earlier Railway-based approach before the switch
  to bore.pub. Not currently invoked by anything in `.devcontainer/`.
