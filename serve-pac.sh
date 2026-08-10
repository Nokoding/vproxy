#!/bin/sh
BODY=$(printf 'function FindProxyForURL(url, host) {\n  return "PROXY %s:%s";\n}\n' "$RAILWAY_TCP_PROXY_DOMAIN" "$RAILWAY_TCP_PROXY_PORT")
LEN=$(printf '%s' "$BODY" | wc -c)
while true; do
  { printf 'HTTP/1.1 200 OK\r\nContent-Type: application/x-ns-proxy-autoconfig\r\nContent-Length: %s\r\nConnection: close\r\n\r\n' "$LEN"; printf '%s' "$BODY"; } | nc -l -p 8090
done
