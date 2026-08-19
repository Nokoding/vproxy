#!/bin/sh
# bore.pub is a free public relay and drops under real browser load (a
# page's worth of parallel connections can kill it), so keep respawning
# it instead of letting the tunnel silently stay dead. cloudflared quick
# tunnels were tried as a replacement and don't work here: they only do
# HTTP(S) reverse-proxying at Cloudflare's edge, not raw TCP passthrough,
# so vproxy's CONNECT/absolute-URI proxy traffic gets rejected (403).

pkill -f 'vproxy run' 2>/dev/null
pkill -f 'bore local 8080' 2>/dev/null
sleep 0.5

nohup vproxy run --bind 0.0.0.0:8080 http > /tmp/vproxy.log 2>&1 &
nohup sh -c 'while true; do bore local 8080 --to bore.pub --port 54584 >> /tmp/bore.log 2>&1; sleep 1; done' > /dev/null 2>&1 &

sleep 1
echo "vproxy + bore restarted."
echo "proxy address: bore.pub:54584"
