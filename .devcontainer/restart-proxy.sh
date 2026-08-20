#!/bin/sh
# bore.pub is a free public relay and drops under real browser load (a
# page's worth of parallel connections can kill it), so keep respawning
# it instead of letting the tunnel silently stay dead. cloudflared quick
# tunnels were tried as a replacement and don't work here: they only do
# HTTP(S) reverse-proxying at Cloudflare's edge, not raw TCP passthrough,
# so vproxy's CONNECT/absolute-URI proxy traffic gets rejected (403).

pkill -f 'vproxy run' 2>/dev/null
pkill -f 'bore local 8080' 2>/dev/null
pkill -f 'PROXY_WATCHDOG' 2>/dev/null
sleep 0.5

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

# Watchdog for the case where vproxy hangs instead of exiting (no crash,
# so the loop above wouldn't catch it): every 30s, send a real request
# through the local proxy with a 5s timeout. If that times out, kill
# both by PID — the respawn loops above bring them straight back.
nohup sh -c '
while true; do # PROXY_WATCHDOG
  sleep 30
  if ! curl -s -m 5 -x http://127.0.0.1:8080 http://example.com -o /dev/null; then
    echo "$(date): health check timed out, restarting" >> /tmp/proxy-watchdog.log
    [ -f /tmp/vproxy.pid ] && kill -9 "$(cat /tmp/vproxy.pid)" 2>/dev/null
    [ -f /tmp/bore.pid ] && kill -9 "$(cat /tmp/bore.pid)" 2>/dev/null
  fi
done' > /dev/null 2>&1 &

# Re-assert port 8080 as public every time (covers first boot and any
# time Codespaces resets it) so it never has to be done by hand.
if [ -n "$CODESPACE_NAME" ]; then
  gh codespace ports visibility 8080:public --codespace "$CODESPACE_NAME" >/dev/null 2>&1
fi

sleep 1
echo "vproxy + bore restarted (auto-restart on crash or timeout is active)."
echo "proxy address: bore.pub:54584"
