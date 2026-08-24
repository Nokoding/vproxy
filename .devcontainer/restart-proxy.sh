#!/bin/sh
# bore.pub is a free public relay and drops under real browser load (a
# page's worth of parallel connections can kill it), so keep respawning
# it instead of letting the tunnel silently stay dead. cloudflared quick
# tunnels were tried as a replacement and don't work here: they only do
# HTTP(S) reverse-proxying at Cloudflare's edge, not raw TCP passthrough,
# so vproxy's CONNECT/absolute-URI proxy traffic gets rejected (403).

# Broad patterns (not tied to a specific port) so switching ports via
# configure-proxy and restarting always cleans up whatever was running
# before, even a stale process bound to a now-abandoned port.
pkill -f 'vproxy run' 2>/dev/null
pkill -f 'bore local' 2>/dev/null
pkill -f 'PROXY_WATCHDOG' 2>/dev/null
pkill -f 'keepalive.sh' 2>/dev/null
pkill -f 'ollama serve' 2>/dev/null
pkill -f 'pac-server.py' 2>/dev/null
# A quick-test-runner.sh from a PREVIOUS restart can still be mid-flight
# here (its failure path alone takes 2+ minutes: 8s delay, up to 8 curls,
# an 8s repair wait, a retest, a 45s Ollama call). Left alive, it holds
# the port values that were exported when IT started, so if ports changed
# in between (e.g. via configure-proxy) it silently tests/repairs against
# the now-abandoned old ports using the pidfiles this restart just wrote
# -- kill+respawning THIS restart's brand-new processes and emailing a
# bogus failure report. Found 2026-08-21 during a full-repo proofread.
pkill -f 'quick-test' 2>/dev/null
sleep 0.5

# Resolve the real script directory even when invoked through the
# /usr/local/bin/restart-proxy symlink (a plain dirname "$0" would
# resolve to /usr/local/bin instead of this repo's .devcontainer/).
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
ALERT_SCRIPT="$SCRIPT_DIR/alert-email.sh"
AI_TRIAGE_SCRIPT="$SCRIPT_DIR/ai-triage.sh"
. "$SCRIPT_DIR/proxy-env.sh"
export ALERT_SCRIPT AI_TRIAGE_SCRIPT
rm -f /tmp/proxy-alert-unhealthy /tmp/proxy-alert-count /tmp/proxy-alert-lastalert

# Keeps the Codespace from auto-stopping after 30 min idle -- unrelated
# to the proxy itself, just piggybacking on this script's startup.
nohup "$SCRIPT_DIR/keepalive.sh" >/dev/null 2>&1 &

# vproxy and bore both respawn immediately if they crash/exit. Each
# iteration records the real binary's PID (not the loop's own PID) to a
# file, so the watchdog below can kill exactly that process by PID
# instead of by pattern — a pattern match on the loop's own script text
# would kill the loop itself along with its child, leaving nothing to
# respawn it.
# Auth (--username/--password) is added only when PROXY_AUTH_ENABLED=1
# (both PROXY_USERNAME and PROXY_PASSWORD set -- see proxy-env.sh). Off
# by default: an open, unauthenticated proxy on a public bore.pub port is
# usable by anyone who finds it, not just you -- see CLAUDE.md.
nohup sh -c '
while true; do
  if [ "$PROXY_AUTH_ENABLED" = "1" ]; then
    vproxy run --bind "0.0.0.0:$LOCAL_HTTP_PORT" http --username "$PROXY_USERNAME" --password "$PROXY_PASSWORD" >> /tmp/vproxy.log 2>&1 &
  else
    vproxy run --bind "0.0.0.0:$LOCAL_HTTP_PORT" http >> /tmp/vproxy.log 2>&1 &
  fi
  echo $! > /tmp/vproxy.pid
  wait $!
  sleep 1
done' > /dev/null 2>&1 &

nohup sh -c '
while true; do
  bore local "$LOCAL_HTTP_PORT" --to bore.pub --port "$BORE_HTTP_PORT" >> /tmp/bore.log 2>&1 &
  echo $! > /tmp/bore.pid
  wait $!
  sleep 1
done' > /dev/null 2>&1 &

# .pac (Proxy Auto-Config) file so a device can be pointed at one URL
# instead of entering host/port by hand. Always served regardless of
# PROXY_MODE -- this is core proxy usability, not the AI/email extras
# performance mode trims. Content is regenerated every restart from the
# *requested* BORE_HTTP_PORT; same caveat as the "proxy address" line
# printed at the bottom of this script -- if bore.pub fell back to a
# random port because that one was already taken by someone else, this
# will be wrong until the next restart (check bore.log's "listening at"
# line, same as always). Auth (if enabled) still applies to the proxy
# itself regardless of how a device learned its address -- vproxy
# challenges for it independently; this file can't and doesn't carry
# credentials, PAC has no syntax for that.
#
# Deliberately started here, BEFORE the TLS cert block below -- acme.sh's
# DNS-01 flow sleeps ~120s for propagation on every issuance (every
# rebuild, since ~/.vproxy-tls is wiped then) and has no timeout of its
# own, so if this were started after that block the PAC endpoint would be
# down for minutes on every rebuild/renewal, or indefinitely if acme.sh
# ever stalls -- same reason the plain HTTP proxy above is started before
# the TLS block too.
mkdir -p /tmp/vproxy-pac
printf 'function FindProxyForURL(url, host) {\n  return "PROXY bore.pub:%s";\n}\n' "$BORE_HTTP_PORT" > /tmp/vproxy-pac/proxy.pac

nohup sh -c '
while true; do
  python3 "'"$SCRIPT_DIR"'/pac-server.py" "$LOCAL_PAC_PORT" /tmp/vproxy-pac/proxy.pac >> /tmp/pac-server.log 2>&1 &
  echo $! > /tmp/pac-server.pid
  wait $!
  sleep 1
done' > /dev/null 2>&1 &

nohup sh -c '
while true; do
  bore local "$LOCAL_PAC_PORT" --to bore.pub --port "$BORE_PAC_PORT" >> /tmp/bore-pac.log 2>&1 &
  echo $! > /tmp/bore-pac.pid
  wait $!
  sleep 1
done' > /dev/null 2>&1 &

# HTTPS proxy variant: presents a real Let's Encrypt cert for
# $DUCKDNS_DOMAIN (see tls-cert.sh) so a device connecting via TLS to
# cdspc.duckdns.org sees an ordinary HTTPS handshake instead of
# unencrypted proxy CONNECT traffic on a bare port -- lets the proxy work
# on networks that inspect/block plain HTTP proxying but allow generic
# HTTPS. Purely additive: if cert issuance fails for any reason, this
# block just doesn't start and the plain HTTP proxy above is unaffected.
export TLS_CERT_DIR="$HOME/.vproxy-tls"
if "$SCRIPT_DIR/tls-cert.sh"; then
  nohup sh -c '
  while true; do
    if [ "$PROXY_AUTH_ENABLED" = "1" ]; then
      vproxy run --bind "0.0.0.0:$LOCAL_TLS_PORT" https --tls-cert "$TLS_CERT_DIR/fullchain.pem" --tls-key "$TLS_CERT_DIR/key.pem" --username "$PROXY_USERNAME" --password "$PROXY_PASSWORD" >> /tmp/vproxy-tls.log 2>&1 &
    else
      vproxy run --bind "0.0.0.0:$LOCAL_TLS_PORT" https --tls-cert "$TLS_CERT_DIR/fullchain.pem" --tls-key "$TLS_CERT_DIR/key.pem" >> /tmp/vproxy-tls.log 2>&1 &
    fi
    echo $! > /tmp/vproxy-tls.pid
    wait $!
    sleep 1
  done' > /dev/null 2>&1 &

  nohup sh -c '
  while true; do
    bore local "$LOCAL_TLS_PORT" --to bore.pub --port "$BORE_TLS_PORT" >> /tmp/bore-tls.log 2>&1 &
    echo $! > /tmp/bore-tls.pid
    wait $!
    sleep 1
  done' > /dev/null 2>&1 &
else
  # Clear any pidfiles from a previous run's TLS variant -- left stale,
  # they survive a stop/start and get trusted at face value by
  # quick-test.sh (kill -0, correctly) and by port-check.sh (existence
  # only, no kill -0 -- see port-check.sh), producing a confusing report
  # instead of the "not running" message it's supposed to show.
  rm -f /tmp/vproxy-tls.pid /tmp/bore-tls.pid
  echo "$(date): TLS cert unavailable, HTTPS proxy variant not started (plain HTTP still up)" >> /tmp/proxy-watchdog.log
fi

# Local model server for ai-triage.sh (see below). OLLAMA_KEEP_ALIVE=-1
# keeps the model resident in RAM indefinitely instead of the 5-minute
# default, so a failure after a quiet stretch doesn't pay the ~30s
# reload cost. Pre-warm with a throwaway request so it's already loaded
# before the first real failure ever needs it.
#
# Skipped entirely in performance mode ($PROXY_MODE, see proxy-env.sh) --
# frees the RAM/CPU the resident model would otherwise hold for core
# proxy throughput. Nothing else needs to know: every ai-triage.sh /
# ask_ollama call already treats a down Ollama as a normal, handled case
# (connection refused, fails fast, falls back) since that's also what
# happens whenever Ollama is merely slow to (re)start in normal mode.
if [ "$PROXY_MODE" != "performance" ]; then
  nohup env OLLAMA_KEEP_ALIVE=-1 sh -c '
  while true; do
    ollama serve >> /tmp/ollama.log 2>&1 &
    echo $! > /tmp/ollama.pid
    wait $!
    sleep 1
  done' > /dev/null 2>&1 &
  (sleep 3; curl -s -m 60 http://127.0.0.1:11434/api/chat -d '{"model":"llama3.2:3b","stream":false,"messages":[{"role":"user","content":"hi"}]}' > /dev/null 2>&1) &
else
  # Stale pidfile from a previous normal-mode run would otherwise survive
  # a mode switch -- same class of bug as the vproxy-tls/bore-tls stale
  # pidfiles fixed elsewhere in this file; port-check.sh's mode line
  # trusts this file's kill -0 result, so a leftover PID (however
  # unlikely to get reused) shouldn't be left around to read.
  rm -f /tmp/ollama.pid
fi

# Watchdog for the case where vproxy hangs instead of exiting (no crash,
# so the loop above wouldn't catch it): every 30s, send a real request
# through the local proxy with a 5s timeout. If that times out, kill
# both by PID — the respawn loops above bring them straight back.
#
# Alert-worthiness and diagnosis come from a local Ollama model
# (ai-triage.sh) fed the recent log tails and failure history -- it
# decides whether this specific failure is worth emailing about and
# writes a plain-English guess at the cause, instead of a fixed timer.
# If Ollama is down/slow/returns something unusable, ai-triage.sh exits
# 1 and we fall back to the old fixed-throttle rule (first failure
# always alerts, then throttled to 15 min), so alerting never silently
# depends on the model being up. Recovery kill+respawn above already
# happened unconditionally before any of this, so the ~10-15s the model
# takes never delays actual recovery.
#
# In performance mode (PROXY_MODE, see proxy-env.sh) Ollama never starts,
# so this fallback is the ONLY alerting path for the whole outage, not
# just an occasional gap-filler -- an earlier version of this fallback
# also had a "count % 3 == 0" escalation clause on top of the 15-min
# throttle, meant to alert more often on a worsening run. At this loop's
# 30s cadence that fired every ~90s, i.e. it wasn't really throttling at
# all. Mostly latent in normal mode (Ollama's own judgment call usually
# wins instead), but always active in performance mode, so a mode meant
# to cut email volume was instead emailing ~34x/hour during any real
# outage. Found 2026-08-24 by an Opus review of the performance-mode
# change itself (see CLAUDE.md's post-change bug check rule) -- removed
# the escalation clause; first-failure + 15-min throttle is the only rule
# now, matching what this comment already claimed it did.
nohup sh -c '
while true; do # PROXY_WATCHDOG
  sleep 30
  # Must authenticate when auth is on, same as quick-test.sh/port-check.sh
  # -- an un-authenticated request here gets a fast 407 straight from
  # vproxy'\''s listener (curl still exits 0 on a 407, so `! curl ...`
  # never trips), meaning this check would always look "healthy" without
  # ever actually routing anything upstream -- exactly the hang/outbound-
  # break scenario this watchdog exists to catch.
  if [ "$PROXY_AUTH_ENABLED" = "1" ]; then
    watchdog_ok=$(curl -s -m 5 -x "http://127.0.0.1:$LOCAL_HTTP_PORT" -U "$PROXY_USERNAME:$PROXY_PASSWORD" http://example.com -o /dev/null; echo $?)
  else
    watchdog_ok=$(curl -s -m 5 -x "http://127.0.0.1:$LOCAL_HTTP_PORT" http://example.com -o /dev/null; echo $?)
  fi
  if [ "$watchdog_ok" != "0" ]; then
    echo "$(date): health check timed out, restarting" >> /tmp/proxy-watchdog.log
    [ -f /tmp/vproxy.pid ] && kill -9 "$(cat /tmp/vproxy.pid)" 2>/dev/null
    [ -f /tmp/bore.pid ] && kill -9 "$(cat /tmp/bore.pid)" 2>/dev/null

    was_unhealthy=$(cat /tmp/proxy-alert-unhealthy 2>/dev/null || echo 0)
    count=$(( $(cat /tmp/proxy-alert-count 2>/dev/null || echo 0) + 1 ))
    now=$(date +%s)
    last=$(cat /tmp/proxy-alert-lastalert 2>/dev/null || echo 0)
    echo 1 > /tmp/proxy-alert-unhealthy
    echo "$count" > /tmp/proxy-alert-count

    if [ "$last" = 0 ]; then since_last="never"; else since_last=$(( now - last )); fi
    ai_result=$("$AI_TRIAGE_SCRIPT" "$count" "$since_last" 2>/dev/null)

    if [ -n "$ai_result" ]; then
      should_alert=$(printf "%s" "$ai_result" | jq -r ".should_alert")
      subject=$(printf "%s" "$ai_result" | jq -r ".subject")
      diagnosis=$(printf "%s" "$ai_result" | jq -r ".diagnosis")
    else
      echo "$(date): ai-triage unavailable, using fallback throttle rule" >> /tmp/proxy-watchdog.log
      if [ "$was_unhealthy" = 0 ] || [ $(( now - last )) -ge 900 ]; then
        should_alert=true
      else
        should_alert=false
      fi
      subject="vproxy proxy issue detected"
      diagnosis="Health check timed out at $(date). Restarting vproxy + bore. Failure #$count in this bad stretch. (AI triage unavailable, used fallback rule.)"
    fi

    if [ "$should_alert" = "true" ]; then
      "$ALERT_SCRIPT" "$subject" "$diagnosis"
      echo "$now" > /tmp/proxy-alert-lastalert
    fi
  else
    if [ "$(cat /tmp/proxy-alert-unhealthy 2>/dev/null || echo 0)" = 1 ]; then
      "$ALERT_SCRIPT" "vproxy proxy recovered" "Health check passed again at $(date). Back to normal."
      echo 0 > /tmp/proxy-alert-unhealthy
      echo 0 > /tmp/proxy-alert-count
    fi
  fi
done' > /dev/null 2>&1 &

# Re-assert both local ports as public every time (covers first boot and
# any time Codespaces resets it) so it never has to be done by hand. Not
# actually required for bore itself (it's an outbound tunnel, unaffected
# by Codespaces port visibility) but kept for direct access/debugging.
if [ -n "$CODESPACE_NAME" ]; then
  gh codespace ports visibility "$LOCAL_HTTP_PORT:public" --codespace "$CODESPACE_NAME" >/dev/null 2>&1
  gh codespace ports visibility "$LOCAL_TLS_PORT:public" --codespace "$CODESPACE_NAME" >/dev/null 2>&1
fi

# Keep the DuckDNS record (used for the URL-cloaking reverse proxy)
# pointed at bore.pub's current IP -- resolved fresh each run rather
# than hardcoded, in case bore.pub ever moves servers.
if [ -n "$DUCKDNS_TOKEN" ] && [ -n "$DUCKDNS_DOMAIN" ]; then
  BORE_IP=$(getent ahostsv4 bore.pub 2>/dev/null | head -1 | awk '{print $1}')
  if [ -n "$BORE_IP" ]; then
    curl -s -m 10 "https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=${BORE_IP}" >> /tmp/duckdns.log 2>&1
  fi
fi

# Startup smoke test against the 4 sites the user actually uses this proxy
# for (discord/tiktok/youtube/google): self-repairs via kill+respawn on
# failure and always emails the result (see quick-test-runner.sh). Delayed
# and backgrounded so it runs once vproxy/bore/ollama have had a moment to
# come up, without blocking this script's own exit. Needs nohup like every
# other background job above -- a plain "&" here was found (2026-08-21) to
# get killed before the 8s sleep even finished whenever the invoking shell
# exited first, silently skipping the self-test every time.
nohup sh -c "sleep 8; '$SCRIPT_DIR/quick-test-runner.sh' >> /tmp/quick-test.log 2>&1" > /dev/null 2>&1 &

sleep 1
echo "vproxy + bore restarted (auto-restart on crash or timeout is active)."
echo "proxy address (http):  bore.pub:$BORE_HTTP_PORT"
case "$DUCKDNS_DOMAIN" in
  *.*) DUCKDNS_FQDN="$DUCKDNS_DOMAIN" ;;
  ?*) DUCKDNS_FQDN="${DUCKDNS_DOMAIN}.duckdns.org" ;;
  *) DUCKDNS_FQDN="<DUCKDNS_DOMAIN unset>" ;;
esac
echo "proxy address (https): ${DUCKDNS_FQDN}:$BORE_TLS_PORT (only if TLS cert issuance succeeded, see /tmp/acme.log)"
echo "auto-config (.pac):    http://bore.pub:$BORE_PAC_PORT/proxy.pac"
if [ "$PROXY_CONFIG_IS_DEFAULT" = 1 ]; then
  echo "Using default ports (local $LOCAL_HTTP_PORT/$LOCAL_TLS_PORT, public $BORE_HTTP_PORT/$BORE_TLS_PORT). Run 'configure-proxy' to customize."
fi
if [ "$PROXY_MODE" = "performance" ]; then
  echo "Mode: performance -- Ollama not started, routine 'all good' test emails skipped. Self-healing (auto-restart + failure emails) still active."
else
  echo "Mode: normal. Run 'configure-proxy' to switch to performance mode (core proxy only, no AI/routine emails)."
fi
if [ "$PROXY_AUTH_ENABLED" = "1" ]; then
  echo "Auth: ON -- devices must supply the configured username/password to use this proxy."
else
  echo "Auth: OFF -- this proxy is open to anyone who finds the address. Run 'configure-proxy' to require a username/password."
fi
