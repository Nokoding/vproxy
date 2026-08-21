#!/bin/sh
# On-demand deep check of the local proxy ports (8080 plain, 8443 TLS),
# for troubleshooting -- separate from quick-test.sh's "can it reach real
# sites" check, this looks one layer lower: is the process actually alive,
# is the port actually listening, and is the bore tunnel actually
# connected. Written because Codespaces' own port-forwarding list (the
# "Ports" tab in the UI, or `gh codespace ports`) does NOT need to include
# 8080/8443 for the proxy to work -- bore's tunnel is a separate outbound
# connection, unrelated to Codespaces port visibility (see CLAUDE.md) --
# but that makes those ports look "offline" from that view, which is a
# recurring source of confusion. This makes the real state explicit.
#
# Usage: port-check.sh  (no args, prints a report, always exits 0 --
# this is a diagnostic tool, not a health gate)

is_listening() {
  # $1 = port
  if command -v ss >/dev/null 2>&1; then
    ss -tln 2>/dev/null | grep -q ":$1[[:space:]]" && return 0 || return 1
  fi
  # ss may not exist in a minimal image; fall back to a raw connection
  # attempt -- curl exit code 7 means connection refused (nothing
  # listening), anything else means something accepted the TCP connection.
  curl -s -o /dev/null -m 2 "http://127.0.0.1:$1/" >/dev/null 2>&1
  [ $? -ne 7 ]
}

check_stack() {
  label="$1" pidfile="$2" port="$3" scheme="$4" borelog="$5" pubhost="$6" pubport="$7"

  echo "$label (local port $port):"

  if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    echo "  process:        running (pid $(cat "$pidfile"))"
  else
    echo "  process:        NOT RUNNING (no live pid in $pidfile)"
  fi

  if is_listening "$port"; then
    echo "  listening:      yes (0.0.0.0:$port)"
  else
    echo "  listening:      NO -- nothing is bound to this port"
  fi

  local_code=$(curl -s -o /dev/null -w '%{http_code}' -m 5 -x "$scheme://127.0.0.1:$port" --proxy-insecure http://example.com 2>/dev/null)
  case "$local_code" in
    2??|3??) echo "  local curl:     OK ($local_code)" ;;
    *) echo "  local curl:     FAIL (${local_code:-no response})" ;;
  esac

  if [ -f "$borelog" ] && grep -q "listening at bore.pub" "$borelog" 2>/dev/null; then
    echo "  bore tunnel:    connected ($(grep "listening at bore.pub" "$borelog" | tail -1 | grep -oE 'bore\.pub:[0-9]+'))"
  else
    echo "  bore tunnel:    no 'listening' line found in $borelog"
  fi

  pub_code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 -x "$scheme://$pubhost:$pubport" --proxy-insecure http://example.com 2>/dev/null)
  case "$pub_code" in
    2??|3??) echo "  public curl:    OK ($pub_code) via $pubhost:$pubport" ;;
    *) echo "  public curl:    FAIL (${pub_code:-no response}) via $pubhost:$pubport" ;;
  esac
  echo
}

case "$DUCKDNS_DOMAIN" in
  *.*) DUCKDNS_FQDN="$DUCKDNS_DOMAIN" ;;
  ?*) DUCKDNS_FQDN="${DUCKDNS_DOMAIN}.duckdns.org" ;;
  *) DUCKDNS_FQDN="" ;;
esac

check_stack "plain proxy" /tmp/vproxy.pid 8080 http /tmp/bore.log bore.pub 54584

if [ -f /tmp/vproxy-tls.pid ]; then
  check_stack "TLS proxy" /tmp/vproxy-tls.pid 8443 https /tmp/bore-tls.log "${DUCKDNS_FQDN:-bore.pub}" 54585
else
  echo "TLS proxy (local port 8443): not running (no pid file -- cert issuance likely failed, see /tmp/acme.log)"
  echo
fi

echo "Note: Codespaces' own port-forwarding list (Ports tab / \`gh codespace"
echo "ports\`) does NOT need to show 8080 or 8443 -- bore's tunnel is a"
echo "separate outbound connection and doesn't depend on Codespaces port"
echo "visibility. Use the checks above, not that list, to judge health."
