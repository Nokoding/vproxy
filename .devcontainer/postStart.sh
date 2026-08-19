#!/bin/sh
vproxy run --bind 0.0.0.0:8080 http > /tmp/vproxy.log 2>&1 &

# bore.pub is a free public relay and drops under real browser load (a
# page's worth of parallel connections can kill it), so keep respawning
# it instead of letting the tunnel silently stay dead. cloudflared quick
# tunnels were tried as a replacement and don't work here: they only do
# HTTP(S) reverse-proxying at Cloudflare's edge, not raw TCP passthrough,
# so vproxy's CONNECT/absolute-URI proxy traffic gets rejected (403).
(while true; do
  bore local 8080 --to bore.pub --port 54584 >> /tmp/bore.log 2>&1
  sleep 1
done) &
