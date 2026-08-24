# Project context (personal proxy fork)

This is a fork of upstream `vproxy` repurposed as a free, self-healing
personal proxy running inside a GitHub Codespace. The upstream project
(HTTP/HTTPS/SOCKS5 proxy server) is basically untouched; everything specific
to this fork lives in `.devcontainer/`. `README.md` (plus the `docs/`
pages it links out to) is the user-facing writeup — this file is the
running internal context, kept up to date after
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

The user-facing docs are split one-topic-per-file, and each fact should
have exactly one home (cross-link from elsewhere rather than explaining
it twice):

- `README.md` — entry point only: what this is, how it works at a
  glance, the connect table, get-started steps, the three commands, and
  links out. Keep the Codespaces badge near the top and the upstream
  "Built on" attribution at the bottom; both are load-bearing.
- `docs/setup.md` — the four required Codespaces secrets
  (`MAILERSEND_*`, `DUCKDNS_*`): what each is for, where to get it, the
  restart-required note, and what degrades if one is missing.
- `docs/configuration.md` — everything optional/tunable: the
  `configure-proxy` command and its secret > config-file > default
  precedence, the six ports, the TLS domain, auth, the `.pac` URL, and
  `PROXY_MODE`.
- `docs/self-healing.md` — the reliability machinery only: the process
  stack, the 30s watchdog, the Ollama triage + fixed fallback rule, the
  startup self-test, `port-check` (anchor `#port-check`), and the logs.
  Configuration topics do not belong here — that was the structural
  problem the 2026-08-24 docs rewrite fixed.

`AGENTS.md` is a symlink to this file, so any AI coding tool that looks for
the generic `AGENTS.md` convention (not just Claude Code) gets this same
context automatically if the repo is forked and opened in a Codespace.
Keep editing `CLAUDE.md` as the real file — don't break the symlink by
writing to `AGENTS.md` directly or making it a separate copy.

**After a major/structural change** (the same bar as the CLAUDE.md-update
rule above — new component, changed architecture, new failure mode), run a
bug-focused review of the diff on the Opus model at high effort before
calling the change done: `Agent` tool, `subagent_type: general-purpose`,
`model: opus`, briefed on what changed and why (a fresh agent has no
context — don't just hand it a bare `git diff`). The `/code-review` skill
itself has no way to pin the model, so invoke the review this way rather
than through the skill. Have it report via `ReportFindings`, correctness
bugs only (not style/simplification). Fix anything CONFIRMED before
considering the change complete; use judgment on PLAUSIBLE findings.

## What's running and why

- `vproxy` (plain HTTP) on container-local `0.0.0.0:$LOCAL_HTTP_PORT`
  (default `8080`) → tunneled by `bore` to `bore.pub:$BORE_HTTP_PORT`
  (default `54584`). The original/simplest path, works everywhere.
- `vproxy` (HTTPS) on container-local `0.0.0.0:$LOCAL_TLS_PORT` (default
  `8443`) → tunneled by a second `bore` to `bore.pub:$BORE_TLS_PORT`
  (default `54585`), reachable at `cdspc.duckdns.org:$BORE_TLS_PORT`. Added
  2026-08-20 so the proxy can pass as ordinary HTTPS traffic (real
  Let's Encrypt cert, normal TLS handshake) on networks that block/inspect
  plain HTTP proxying. Purely additive — if TLS cert issuance fails, only
  this half is skipped; the plain HTTP proxy is unaffected.
- A `.pac` (Proxy Auto-Config) file, added 2026-08-24, so a device can be
  pointed at one URL instead of entering host/port by hand:
  `http://bore.pub:$BORE_PAC_PORT/proxy.pac` (default `54586`), served by
  `.devcontainer/pac-server.py` (stdlib-only `http.server`, no deps) on
  container-local `0.0.0.0:$LOCAL_PAC_PORT` (default `8090`) → a third
  `bore` tunnel, same respawn-loop-with-pidfile pattern as vproxy/bore
  above. `restart-proxy.sh` regenerates `/tmp/vproxy-pac/proxy.pac`
  (`FindProxyForURL` returning `PROXY bore.pub:$BORE_HTTP_PORT`) on every
  restart from the *requested* `BORE_HTTP_PORT` — same "not
  confirmed-granted" caveat as the printed proxy addresses below, if
  bore.pub fell back to a random port this is stale until the next
  restart. `pac-server.py` re-reads the file from disk per-request rather
  than needing its own restart to pick up a regeneration. Not a Rust
  proxy protocol port and can't carry credentials (PAC has no syntax for
  that) — the repo-root `serve-pac.sh` is a separate, older, unrelated
  Railway-era leftover (see "Loose ends" below), not this. Started
  *before* the TLS cert block, not after (acme.sh's DNS-01 flow sleeps
  ~120s per issuance with no timeout, which would otherwise leave the PAC
  endpoint down for minutes on every rebuild). `Handler.timeout = 10` +
  `ThreadingHTTPServer` (not plain `HTTPServer`) so one client that
  connects on this public port and never sends anything can't wedge the
  whole endpoint. `python3` is an explicit `onCreateCommand` apt dep, not
  just assumed present — see the `gh`/`jq` gotcha this repo already hit
  once for why that assumption is worth avoiding.
- Proxy authentication, added 2026-08-24 in response to discovering the
  proxy was a de-facto open proxy (see the gotcha below on how that was
  found). Presence-based, same idiom as `MAILERSEND_*`/`DUCKDNS_*`
  elsewhere in this file gating an optional feature: setting **both**
  `PROXY_USERNAME` and `PROXY_PASSWORD` turns auth on (`vproxy` itself
  already supported `--username`/`--password`, just wasn't being passed
  them); either missing means off, matching `vproxy`'s own
  `requires` relationship between the two flags. `proxy-env.sh` computes
  `PROXY_AUTH_ENABLED=1/0` from their presence; `restart-proxy.sh`'s two
  `vproxy run` invocations add the flags conditionally. `quick-test.sh`,
  `port-check.sh`, AND the `PROXY_WATCHDOG` health-check loop all
  self-authenticate too (`-U user:pass`) when enabled — the watchdog case
  was a real bug an Opus review caught: vproxy answers an
  unauthenticated request with a `407`, and `curl` exits `0` on a `407`
  (it's not a connection failure), so the un-authenticated watchdog would
  have silently stopped ever detecting a real hang/outage the moment auth
  was turned on, without erroring or logging anything. Off by default —
  an existing fork keeps working exactly as before until someone opts in.
  Exactly one of the two set (not both) logs a warning and runs open
  rather than failing closed or staying silent — almost always a typo
  (misspelled secret name), and silently open is the worst version of
  that mistake to not hear about. `configure-proxy`'s interactive flow
  prompts for both (password entry has terminal echo disabled, restored
  on Ctrl-C too) via `IFS= read -r` (plain `read` would silently eat a
  literal `\` and trim whitespace, both caught live by the same Opus
  review), rejects any value containing `"`, `` ` ``, `$`, `\`, `{`, or
  `}` (the `{`/`}` were a review-caught gap — spliced unescaped into a
  `${VAR:-word}` config-file line, either one would truncate the stored
  value with no syntax error to notice by), defaults an empty/Enter
  answer to the *current* auth state rather than "off" (another
  review-caught bug — silently stripped auth from an already-configured
  proxy the first time someone ran `configure-proxy` just to change an
  unrelated port), and `chmod 600`s `~/.vproxy-config` once it's
  answering "yes" (it now holds a plaintext password, unlike when it only
  held port numbers).
- All six ports (four proxy + two PAC) and `PROXY_MODE`/auth are
  configurable, either via the matching Codespaces secret
  (`LOCAL_HTTP_PORT`/`LOCAL_TLS_PORT`/`BORE_HTTP_PORT`/`BORE_TLS_PORT`/`LOCAL_PAC_PORT`/`BORE_PAC_PORT`/`PROXY_MODE`/`PROXY_USERNAME`/`PROXY_PASSWORD`)
  or interactively via `configure-proxy` (symlinked like `restart-proxy`).
  Added 2026-08-21, extended 2026-08-24 for PAC ports + auth.
  `.devcontainer/proxy-env.sh` is the single source of truth for
  resolving them — sourced by every script that needs one
  (`restart-proxy.sh`, `quick-test.sh`, `port-check.sh`,
  `configure-proxy.sh`, `quick-test-runner.sh`) — precedence: real
  Codespaces secret > entry saved to `~/.vproxy-config` by
  `configure-proxy` (survives stop/start, wiped on rebuild) > hardcoded
  default (auth has no default — presence-based, see above).
  `restart-proxy` prints a one-line reminder to run `configure-proxy` for
  as long as nothing's ever been configured (`PROXY_CONFIG_IS_DEFAULT`,
  set by `proxy-env.sh` from the 6 ports only — auth being unset is the
  normal, unremarkable default, not worth nagging about). See the gotcha
  below about a shadowing bug this design had to work around, now
  extended to 9 vars total.
- Codespaces port visibility (`gh codespace ports visibility`) is flipped to
  public for both local ports on every restart. This is *not* actually
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
- `PROXY_MODE` (`normal` default, or `performance`) — added 2026-08-24 in
  response to the user asking to boost proxy throughput/latency. Investigated
  first: `vproxy` itself was already well-tuned (`TCP_NODELAY` on both
  client and outbound sockets, tokio worker threads = CPU cores). Measured
  live that the actual ceiling is the bore.pub free relay itself (~14.5MB/s
  vs ~122MB/s direct, +~275ms latency vs direct) — not something a mode
  can move. So `PROXY_MODE` instead trims background load competing with
  the proxy for the Codespace's CPU/RAM: in `performance`, `restart-proxy.sh`
  never starts `ollama serve` at all (the resident 3B model otherwise held
  RAM/CPU continuously via `OLLAMA_KEEP_ALIVE=-1`), and
  `quick-test-runner.sh` skips its routine "all good" startup-test email
  (logged to `/tmp/quick-test.log` instead). Self-healing is explicitly
  NOT gated by mode: crash/hang auto-restart and the emails for an actual
  detected failure fire the same in both modes — every Ollama call site
  (`ai-triage.sh`, `quick-test-runner.sh`'s `ask_ollama`) already treats a
  down Ollama as a normal case (connection refused, fails fast, falls back
  to the fixed-throttle rule / generic text), the same path either mode
  already takes whenever Ollama is merely slow to (re)start in normal mode
  — so no separate fallback logic was needed for performance mode itself.
  Resolved via the same secret > `~/.vproxy-config` > default precedence as
  the ports (`proxy-env.sh`), settable via `configure-proxy` (option 2's
  prompts) or the `PROXY_MODE` Codespaces secret. `restart-proxy` and
  `port-check` both print the current mode. Verified live: performance
  mode restart left `ollama serve` un-started, proxy still fully healthy
  end-to-end, quick-test logged its "all good" line without emailing;
  restarting again with no `PROXY_MODE` set brought Ollama back.
- `port-check.sh` (symlinked to `/usr/local/bin/port-check`, same pattern
  as `restart-proxy`) is an on-demand troubleshooting command: for each
  proxy port, reports process-alive, actually-listening, a local curl
  test, bore tunnel connection status (from the log), and a real curl
  through the public tunnel. Added 2026-08-21 after confirming live that
  everything can check out fully healthy end-to-end while `gh codespace
  ports` lists neither local port at all — see the gotcha below. Always
  exits 0; it's a diagnostic report, not a health gate.
- On every startup, `restart-proxy.sh` backgrounds `quick-test-runner.sh`
  (after an 8s delay) to prove the proxy can actually reach the 4 sites the
  user tests with by hand — discord.com, tiktok.com, youtube.com,
  google.com — through both the plain and TLS (if up) proxy variants,
  whatever ports they're actually configured for (`quick-test.sh` does the
  actual checks). All pass → email
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
- `keepalive.sh` stops the Codespace from auto-stopping after 30 min idle.
  Added 2026-08-23. Confirmed by testing that GitHub's idle timer only
  resets on real terminal I/O (input or output on the connected
  terminal), not on a silent background process, and that
  `idle_timeout_minutes` can't be changed after creation — a `PATCH
  /user/codespaces/{name}` with the auto-injected `GITHUB_TOKEN` silently
  no-ops, and `gh codespace edit` has no `--idle-timeout` flag (only
  `codespace create` takes one). So instead, every 20 min it writes a
  cursor save/restore escape sequence (`\0337\0338`, no visible effect,
  no beep) to every attached pty under `/dev/pts/` — cheap enough to
  register as terminal output without ever appearing on screen. No-ops
  outside a Codespace (`$CODESPACES` unset). Started by `restart-proxy.sh`
  alongside the proxy processes, killed/respawned the same way
  (`pkill -f 'keepalive.sh'` on startup) — otherwise unrelated to the
  proxy itself, just piggybacking on the same lifecycle hook.

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
  either local proxy port, ever, and that's normal.** Confirmed 2026-08-21
  while investigating a "the ports aren't online" report from the user:
  process alive, port listening, local curl, and a real curl through the
  public tunnel were all healthy at the same moment `gh codespace ports`
  showed neither port at all. This is expected, not a bug — bore opens its
  own outbound connection to `bore.pub`, entirely separate from
  Codespaces' own port-forwarding, so those ports never get added to that
  list no matter how healthy they are. Don't diagnose from that list; use
  `port-check` (see above) or a direct curl instead.

- **A child process inheriting an already-`export`ed port variable will
  shadow a config file it should have re-read.** Found 2026-08-21 while
  testing `configure-proxy`: it sources `proxy-env.sh` at the top just to
  *display* current values, which exports e.g. `LOCAL_HTTP_PORT` into its
  own process env with the *old* value already resolved. If the user then
  picks option 2 (enter values now) and it calls `restart-proxy` as a
  child process, that child inherits the stale exported value — and since
  `proxy-env.sh`'s `${VAR:-default}` precedence can't tell "real
  Codespaces secret" apart from "already resolved by an earlier sourcing
  in this same process," the freshly-written `~/.vproxy-config` gets
  silently ignored and the proxy restarts on the *old* port. Confirmed
  live: set local ports to 9090/9443, restart bound to 8080/8443 anyway.
  Fixed in `configure-proxy.sh` by capturing which of the four vars came
  from a real secret *before* sourcing `proxy-env.sh` at all
  (`${VAR:+1}` on the raw incoming env, before defaults are ever applied),
  then `unset`-ing exactly the non-secret ones right before calling
  `restart-proxy` so the child re-resolves cleanly from the new config
  file. `PROXY_MODE` (added 2026-08-24) follows the exact same
  capture/unset pattern as a fifth var, and the PAC ports + auth vars
  (also 2026-08-24) extend it to nine (`LOCAL_PAC_PORT`, `BORE_PAC_PORT`,
  `PROXY_USERNAME`, `PROXY_PASSWORD`). Verified live after the fix:
  9090/9443 came up correctly. Worth remembering for any other script
  that both sources `proxy-env.sh` for its own display/logic AND shells
  out to another script that also sources it.

- **A full-repo proofread (2026-08-21, right after the above) found three
  more bugs in the same new port-config code, all now fixed:**
  1. `restart-proxy.sh`'s startup pkill list didn't match a still-running
     `quick-test-runner.sh` from a *previous* restart (its failure path
     alone runs 2+ minutes). Left alive across a port change, it inherits
     the stale exported ports, tests the abandoned old ones, and
     kill+respawns THIS restart's brand-new pidfiles while emailing a
     bogus failure report. Fixed: `pkill -f 'quick-test'` added to the
     startup cleanup.
  2. `port-check.sh` judged "bore tunnel: connected" by grepping the
     *whole* (append-only, never-truncated) `bore.log` for any
     `"listening at bore.pub"` line ever, with no check that the bore
     process was actually still alive — so a tunnel dead for the whole
     session, or reassigned to a different port after a collision, still
     read as healthy. Fixed: now also checks `bore.pid` via `kill -0`,
     and requires the listening-line's port to match the *current*
     `$BORE_HTTP_PORT`/`$BORE_TLS_PORT`, not just any port ever seen.
  3. A stale `/tmp/vproxy-tls.pid`/`/tmp/bore-tls.pid` (left behind
     whenever TLS cert issuance fails, since nothing cleared them —
     they survive a stop/start) made `port-check.sh`'s "TLS proxy: not
     running" branch unreachable, since it only checked file-existence,
     not `kill -0` like `quick-test.sh` does. Fixed both: `restart-proxy.sh`
     now `rm -f`s them on cert failure, and `port-check.sh`'s gate now
     matches `quick-test.sh`'s (`kill -0`, not just `[ -f ]`).

  Also hardened `configure-proxy.sh`'s port entry, which previously
  accepted any positive number (e.g. 70000, or the same port twice) with
  no upper-bound or duplicate check — now rejects >65535 and rejects any
  duplicate among the (now three, since the 2026-08-24 PAC addition)
  local ports or among the three public ports, pairwise via a loop
  rather than a single equality check per pair.

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
  the plain proxy instead. Reaching the TLS variant from
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

- **This proxy was a de-facto open proxy until 2026-08-24, and it was
  found by accident.** While diagnosing an unrelated "some sites work,
  others don't" report, `vproxy.log` showed live traffic to
  `sch-28554.school.mosyle.io` and `gateway.icloud.com` — Apple/school-MDM
  domains the user confirmed weren't from their device. `vproxy run` was
  never being passed `--username`/`--password` (it supports both, see
  `AuthMode` in `src/main.rs`), and `bore.pub:$BORE_HTTP_PORT` is a public
  port on a public relay — trivially found by anyone scanning or
  stumbling on it. A stranger's concurrent, uncontrolled usage competing
  for bore.pub's own limited connection capacity (already documented
  above as fragile under load) is a very plausible explanation for
  "some sites work, others don't" independent of anything actually being
  broken. Fixed by adding optional auth (see above) — off by default, so
  check `port-check`'s "Auth:" line if this symptom ever recurs.
- A blanket `*.py` rule already existed in `.gitignore` (predates this
  fork, presumably for some unrelated Python tooling) and was silently
  excluding the new `.devcontainer/pac-server.py` from every commit —
  caught only because `git status` after writing it showed nothing.
  Fixed with a `!.devcontainer/pac-server.py` negation line. Worth
  `git status`-checking any new file this repo adds, not just editing it
  and assuming `git add` will pick it up.

## Required Codespaces secrets

Set via Settings → Codespaces secrets, scoped to this repo:

- `MAILERSEND_API_TOKEN`, `MAILERSEND_FROM` — email alerts
- `DUCKDNS_TOKEN`, `DUCKDNS_DOMAIN` — DNS record + TLS cert DNS-01 challenge

Optional, all have working defaults if unset (see "What's running and
why" above) — `LOCAL_HTTP_PORT`, `LOCAL_TLS_PORT`, `BORE_HTTP_PORT`,
`BORE_TLS_PORT`, `LOCAL_PAC_PORT`, `BORE_PAC_PORT`, `PROXY_MODE`. Easiest
set via `configure-proxy` rather than by hand.

`PROXY_USERNAME`/`PROXY_PASSWORD` — optional, no default (unset = proxy
auth off, the same as before 2026-08-24). Set **both** to require a
username/password to use this proxy. Easiest set via `configure-proxy`.

## Loose ends / not yet wired up

- `serve-pac.sh` (repo root) references `RAILWAY_TCP_PROXY_DOMAIN` /
  `RAILWAY_TCP_PROXY_PORT`, which aren't set in the Codespace env — looks
  like a leftover from an earlier Railway-based approach before the switch
  to bore.pub. Not invoked by anything in `.devcontainer/` (the Codespace
  path this fork actually uses), but it IS still invoked by `Dockerfile`
  (`COPY serve-pac.sh` + run in `ENTRYPOINT`, alongside vproxy on 8090) —
  `Dockerfile` was hand-edited by this fork (commit `ace43f3`) and is the
  one non-`.devcontainer` file outside the Rust source that was. With both
  Railway vars unset it just serves a valid-but-useless PAC (`return
  "PROXY :";`). Only reachable if something actually builds/runs this
  Dockerfile, which nothing in the Codespace flow does. Unrelated to (and
  not touched by) the real `.pac` file added 2026-08-24 — see
  `.devcontainer/pac-server.py` in "What's running and why" above. Pure
  coincidence that both happen to default to port 8090; they never run in
  the same context so it isn't a real collision.
