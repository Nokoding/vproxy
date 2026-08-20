#!/bin/sh
# bore.pub is a free public relay and drops under real browser load (a
# page's worth of parallel connections can kill it), so keep respawning
# it instead of letting the tunnel silently stay dead. cloudflared quick
# tunnels were tried as a replacement and don't work here: they only do
# HTTP(S) reverse-proxying at Cloudflare's edge, not raw TCP passthrough,
# so vproxy's CONNECT/absolute-URI proxy traffic gets rejected (403).

pkill -f 'vproxy run' 2>/dev/null
pkill -f 'bore local 8080' 2>/dev/null
pkill -f 'bore local 8443' 2>/dev/null
pkill -f 'PROXY_WATCHDOG' 2>/dev/null
pkill -f 'ollama serve' 2>/dev/null
sleep 0.5

# Resolve the real script directory even when invoked through the
# /usr/local/bin/restart-proxy symlink (a plain dirname "$0" would
# resolve to /usr/local/bin instead of this repo's .devcontainer/).
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
ALERT_SCRIPT="$SCRIPT_DIR/alert-email.sh"
AI_TRIAGE_SCRIPT="$SCRIPT_DIR/ai-triage.sh"
export ALERT_SCRIPT AI_TRIAGE_SCRIPT
rm -f /tmp/proxy-alert-unhealthy /tmp/proxy-alert-count /tmp/proxy-alert-lastalert

# vproxy and bore both respawn immediately if they crash/exit. Each
# iteration records the real binary's PID (not the loop's own PID) to a
# file, so the watchdog below can kill exactly that process by PID
# instead of by pattern — a pattern match on the loop's own script text
# would kill the loop itself along with its child, leaving nothing to
# respawn it.
nohup sh -c '
while true; do
  vproxy run --bind 0.0.0.0:8080 http >> /tmp/vproxy.log 2>&1 &
  echo $! > /tmp/vproxy.pid
  wait $!
  sleep 1
done' > /dev/null 2>&1 &

nohup sh -c '
while true; do
  bore local 8080 --to bore.pub --port 54584 >> /tmp/bore.log 2>&1 &
  echo $! > /tmp/bore.pid
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
TLS_CERT_DIR="$HOME/.vproxy-tls"
if "$SCRIPT_DIR/tls-cert.sh"; then
  nohup sh -c "
  while true; do
    vproxy run --bind 0.0.0.0:8443 https --tls-cert '$TLS_CERT_DIR/fullchain.pem' --tls-key '$TLS_CERT_DIR/key.pem' >> /tmp/vproxy-tls.log 2>&1 &
    echo \$! > /tmp/vproxy-tls.pid
    wait \$!
    sleep 1
  done" > /dev/null 2>&1 &

  nohup sh -c '
  while true; do
    bore local 8443 --to bore.pub --port 54585 >> /tmp/bore-tls.log 2>&1 &
    echo $! > /tmp/bore-tls.pid
    wait $!
    sleep 1
  done' > /dev/null 2>&1 &
else
  echo "$(date): TLS cert unavailable, HTTPS proxy variant not started (plain HTTP still up)" >> /tmp/proxy-watchdog.log
fi

# Local model server for ai-triage.sh (see below). OLLAMA_KEEP_ALIVE=-1
# keeps the model resident in RAM indefinitely instead of the 5-minute
# default, so a failure after a quiet stretch doesn't pay the ~30s
# reload cost. Pre-warm with a throwaway request so it's already loaded
# before the first real failure ever needs it.
nohup env OLLAMA_KEEP_ALIVE=-1 sh -c '
while true; do
  ollama serve >> /tmp/ollama.log 2>&1 &
  echo $! > /tmp/ollama.pid
  wait $!
  sleep 1
done' > /dev/null 2>&1 &
(sleep 3; curl -s -m 60 http://127.0.0.1:11434/api/chat -d '{"model":"llama3.2:3b","stream":false,"messages":[{"role":"user","content":"hi"}]}' > /dev/null 2>&1) &

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
# always alerts, then throttled to 15 min unless escalating), so
# alerting never silently depends on the model being up. Recovery kill
# +respawn above already happened unconditionally before any of this,
# so the ~10-15s the model takes never delays actual recovery.
nohup sh -c '
while true; do # PROXY_WATCHDOG
  sleep 30
  if ! curl -s -m 5 -x http://127.0.0.1:8080 http://example.com -o /dev/null; then
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
      if [ "$was_unhealthy" = 0 ] || [ $(( now - last )) -ge 900 ] || [ $(( count % 3 )) -eq 0 ]; then
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

# Re-assert ports 8080/8443 as public every time (covers first boot and
# any time Codespaces resets it) so it never has to be done by hand. Not
# actually required for bore itself (it's an outbound tunnel, unaffected
# by Codespaces port visibility) but kept for direct access/debugging.
if [ -n "$CODESPACE_NAME" ]; then
  gh codespace ports visibility 8080:public --codespace "$CODESPACE_NAME" >/dev/null 2>&1
  gh codespace ports visibility 8443:public --codespace "$CODESPACE_NAME" >/dev/null 2>&1
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

sleep 1
echo "vproxy + bore restarted (auto-restart on crash or timeout is active)."
echo "proxy address (http):  bore.pub:54584"
case "$DUCKDNS_DOMAIN" in
  *.*) DUCKDNS_FQDN="$DUCKDNS_DOMAIN" ;;
  ?*) DUCKDNS_FQDN="${DUCKDNS_DOMAIN}.duckdns.org" ;;
  *) DUCKDNS_FQDN="<DUCKDNS_DOMAIN unset>" ;;
esac
echo "proxy address (https): ${DUCKDNS_FQDN}:54585 (only if TLS cert issuance succeeded, see /tmp/acme.log)"
