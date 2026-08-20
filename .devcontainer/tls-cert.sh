#!/bin/sh
# Issues/renews a real Let's Encrypt cert for $DUCKDNS_DOMAIN via acme.sh's
# DNS-01 duckdns hook, so vproxy's https mode can present a trusted
# certificate instead of a self-signed one (a self-signed cert gets
# rejected or flagged by most OSes/browsers, defeating the point of
# looking like ordinary HTTPS traffic).
#
# Cached in $CERT_DIR, which survives a Codespace stop/start but is wiped
# (and silently re-fetched here) on a rebuild -- same lifecycle as the
# vproxy/bore/ollama binaries themselves. Skips reissuance if a cached
# cert still has >20 days left, to stay well under Let's Encrypt's rate
# limit (5 duplicate certs/week for the same domain).
#
# On any failure (no acme.sh, DuckDNS down, Let's Encrypt down) this exits
# 1 -- caller must treat https as unavailable and fall back to the plain
# HTTP proxy, which never depends on this succeeding.

ACME="$HOME/.acme.sh/acme.sh"
CERT_DIR="$HOME/.vproxy-tls"
FULLCHAIN="$CERT_DIR/fullchain.pem"
KEY_FILE="$CERT_DIR/key.pem"

[ -n "$DUCKDNS_TOKEN" ] && [ -n "$DUCKDNS_DOMAIN" ] || exit 1
[ -x "$ACME" ] || exit 1

# DUCKDNS_DOMAIN is the bare subdomain (e.g. "cdspc"), matching what
# DuckDNS's own update API expects elsewhere in restart-proxy.sh --
# Let's Encrypt needs the FQDN.
case "$DUCKDNS_DOMAIN" in
  *.*) FQDN="$DUCKDNS_DOMAIN" ;;
  *) FQDN="${DUCKDNS_DOMAIN}.duckdns.org" ;;
esac

mkdir -p "$CERT_DIR"

if [ -f "$FULLCHAIN" ] && openssl x509 -in "$FULLCHAIN" -checkend $((20 * 86400)) -noout >/dev/null 2>&1; then
  exit 0
fi

export DuckDNS_Token="$DUCKDNS_TOKEN"

"$ACME" --issue --dns dns_duckdns -d "$FQDN" \
  --server letsencrypt \
  --key-file "$KEY_FILE" \
  --fullchain-file "$FULLCHAIN" \
  >/tmp/acme.log 2>&1
