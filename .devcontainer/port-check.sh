#!/bin/sh
# On-demand deep check of the local proxy ports (plain + TLS, whatever
# they're currently configured to), for troubleshooting -- separate from
# quick-test.sh's "can it reach real sites" check, this looks one layer
# lower: is the process actually alive, is the port actually listening,
# and is the bore tunnel actually connected. Written because Codespaces'
# own port-forwarding list (the "Ports" tab in the UI, or `gh codespace
# ports`) does NOT need to include either local port for the proxy to
# work -- bore's tunnel is a separate outbound connection, unrelated to
# Codespaces port visibility (see CLAUDE.md) -- but that makes those ports
# look "offline" from that view, which is a recurring source of
# confusion. This makes the real state explicit.
#
# Usage: port-check.sh  (no args, prints a report, always exits 0 --
# this is a diagnostic tool, not a health gate)

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
. "$SCRIPT_DIR/proxy-env.sh"

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
  label="$1" pidfile="$2" port="$3" scheme="$4" borepidfile="$5" borelog="$6" pubhost="$7" pubport="$8"

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

  if [ "$PROXY_AUTH_ENABLED" = "1" ]; then
    local_code=$(curl -s -o /dev/null -w '%{http_code}' -m 5 -x "$scheme://127.0.0.1:$port" -U "$PROXY_USERNAME:$PROXY_PASSWORD" --proxy-insecure http://example.com 2>/dev/null)
  else
    local_code=$(curl -s -o /dev/null -w '%{http_code}' -m 5 -x "$scheme://127.0.0.1:$port" --proxy-insecure http://example.com 2>/dev/null)
  fi
  case "$local_code" in
    2??|3??) echo "  local curl:     OK ($local_code)" ;;
    *) echo "  local curl:     FAIL (${local_code:-no response})" ;;
  esac

  # bore.log is append-only across every restart-proxy run this session,
  # so an old "listening at bore.pub:<port>" line never goes away on its
  # own -- matching anywhere in the file would still claim "connected"
  # for a tunnel that died an hour ago, or report a port nothing is using
  # after a port change where bore failed to grab the new one. Require
  # BOTH a live bore process (its own pidfile, not just vproxy's) AND a
  # "listening" line for the port we're actually configured for right now.
  if [ -f "$borepidfile" ] && kill -0 "$(cat "$borepidfile")" 2>/dev/null && grep -q "listening at bore.pub:$pubport" "$borelog" 2>/dev/null; then
    echo "  bore tunnel:    connected (bore.pub:$pubport)"
  else
    if [ -f "$borepidfile" ] && kill -0 "$(cat "$borepidfile")" 2>/dev/null; then
      bore_proc_state="process alive"
    else
      bore_proc_state="no live process"
    fi
    echo "  bore tunnel:    NOT connected ($bore_proc_state; no 'listening at bore.pub:$pubport' line in $borelog)"
  fi

  if [ "$PROXY_AUTH_ENABLED" = "1" ]; then
    pub_code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 -x "$scheme://$pubhost:$pubport" -U "$PROXY_USERNAME:$PROXY_PASSWORD" --proxy-insecure http://example.com 2>/dev/null)
  else
    pub_code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 -x "$scheme://$pubhost:$pubport" --proxy-insecure http://example.com 2>/dev/null)
  fi
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

# Report Ollama's actual live state, not just the configured mode --
# they can diverge (mode changed via `configure-proxy` without a restart
# yet, or a secret added before the Codespace stop/start that injects
# it), and this tool exists specifically to show real state over
# configuration/assumption (see the port-visibility gotcha below).
if [ -f /tmp/ollama.pid ] && kill -0 "$(cat /tmp/ollama.pid)" 2>/dev/null; then
  ollama_state="running (AI triage + routine test emails active)"
else
  ollama_state="not running (fixed fallback throttle rule, no routine test emails; self-healing still active)"
fi
echo "Mode: $PROXY_MODE (configured) -- Ollama: $ollama_state"
if [ "$PROXY_AUTH_ENABLED" = "1" ]; then
  echo "Auth: ON (username: $PROXY_USERNAME)"
else
  echo "Auth: OFF -- this proxy is open to anyone who finds the address"
fi
echo

check_stack "plain proxy" /tmp/vproxy.pid "$LOCAL_HTTP_PORT" http /tmp/bore.pid /tmp/bore.log bore.pub "$BORE_HTTP_PORT"

# kill -0, not just [ -f ] -- a stale pidfile from a previous run whose
# TLS cert issuance failed survives a stop/start (restart-proxy now
# cleans this up going forward, but an old one may already be sitting
# there) and would otherwise fall through to check_stack and print four
# confusing FAILs instead of this "not running" message.
if [ -f /tmp/vproxy-tls.pid ] && kill -0 "$(cat /tmp/vproxy-tls.pid)" 2>/dev/null; then
  check_stack "TLS proxy" /tmp/vproxy-tls.pid "$LOCAL_TLS_PORT" https /tmp/bore-tls.pid /tmp/bore-tls.log "${DUCKDNS_FQDN:-bore.pub}" "$BORE_TLS_PORT"
else
  echo "TLS proxy (local port $LOCAL_TLS_PORT): not running (no live pid -- cert issuance likely failed, see /tmp/acme.log)"
  echo
fi

# PAC server isn't a proxy (nothing to hand -x to), so it gets its own
# simpler check rather than reusing check_stack -- but the public-fetch
# check still needs the same bore-tunnel-staleness guard check_stack uses
# above (kill -0 on bore-pac's own pidfile AND a "listening" line for the
# port we're actually configured for right now, not just any port ever
# seen in the append-only log -- see the comment on check_stack). It also
# needs to check the *content*, not just that something PAC-shaped came
# back: a bore.pub fallback to a different public port (e.g. because
# $BORE_HTTP_PORT was already taken) would still serve a syntactically
# valid PAC file that sends every client to the wrong port -- matching
# the same "requested, not confirmed-granted" caveat noted in
# restart-proxy.sh where this file gets generated.
expected_pac_line="PROXY bore.pub:$BORE_HTTP_PORT"
echo "PAC server (local port $LOCAL_PAC_PORT):"
if [ -f /tmp/pac-server.pid ] && kill -0 "$(cat /tmp/pac-server.pid)" 2>/dev/null; then
  echo "  process:        running (pid $(cat /tmp/pac-server.pid))"
else
  echo "  process:        NOT RUNNING (no live pid in /tmp/pac-server.pid)"
fi
if is_listening "$LOCAL_PAC_PORT"; then
  echo "  listening:      yes (0.0.0.0:$LOCAL_PAC_PORT)"
else
  echo "  listening:      NO -- nothing is bound to this port"
fi
local_pac=$(curl -s -m 5 "http://127.0.0.1:$LOCAL_PAC_PORT/proxy.pac" 2>/dev/null)
case "$local_pac" in
  *"$expected_pac_line"*) echo "  local fetch:    OK (advertises $expected_pac_line)" ;;
  *FindProxyForURL*) echo "  local fetch:    STALE (served a PAC, but not advertising $expected_pac_line -- check /tmp/vproxy-pac/proxy.pac)" ;;
  *) echo "  local fetch:    FAIL (empty or unexpected response)" ;;
esac
if [ -f /tmp/bore-pac.pid ] && kill -0 "$(cat /tmp/bore-pac.pid)" 2>/dev/null && grep -q "listening at bore.pub:$BORE_PAC_PORT" /tmp/bore-pac.log 2>/dev/null; then
  pub_pac=$(curl -s -m 10 "http://bore.pub:$BORE_PAC_PORT/proxy.pac" 2>/dev/null)
  case "$pub_pac" in
    *"$expected_pac_line"*) echo "  bore tunnel:    connected (bore.pub:$BORE_PAC_PORT)" ;;
    *FindProxyForURL*) echo "  bore tunnel:    connected (bore.pub:$BORE_PAC_PORT), but STALE content -- not advertising $expected_pac_line" ;;
    *) echo "  bore tunnel:    connected (bore.pub:$BORE_PAC_PORT), but public fetch FAIL (empty or unexpected response)" ;;
  esac
else
  if [ -f /tmp/bore-pac.pid ] && kill -0 "$(cat /tmp/bore-pac.pid)" 2>/dev/null; then
    bore_pac_state="process alive"
  else
    bore_pac_state="no live process"
  fi
  echo "  bore tunnel:    NOT connected ($bore_pac_state; no 'listening at bore.pub:$BORE_PAC_PORT' line in /tmp/bore-pac.log)"
fi
echo

echo "Note: Codespaces' own port-forwarding list (Ports tab / \`gh codespace"
echo "ports\`) does NOT need to show either local port -- bore's tunnel is a"
echo "separate outbound connection and doesn't depend on Codespaces port"
echo "visibility. Use the checks above, not that list, to judge health."
