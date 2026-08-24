#!/bin/sh
# Interactive port/domain configuration menu, so anyone who forks this
# repo can customize ports without editing code. Run manually, any time
# you want -- NOT wired into postStartCommand, since blocking Codespaces'
# own startup command on interactive input risks the Codespace looking
# stuck on "setting up" if the terminal isn't opened right away. Instead,
# restart-proxy.sh prints a one-line pointer to this command on first
# boot, before any config has ever been set (see PROXY_CONFIG_IS_DEFAULT
# in proxy-env.sh).
#
# Usage: configure-proxy  (no args, interactive)

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Capture which of these came from a REAL Codespaces secret before
# proxy-env.sh (sourced next, just to display current values) exports its
# own resolved/defaulted versions into THIS process's environment. If
# option 2 below calls `restart-proxy` afterward, that child process
# would otherwise inherit those already-resolved values and mistake them
# for a real secret -- shadowing the config file this script just wrote,
# so the "new" ports would silently keep using the old ones.
_secret_local_http="${LOCAL_HTTP_PORT:+1}"
_secret_local_tls="${LOCAL_TLS_PORT:+1}"
_secret_bore_http="${BORE_HTTP_PORT:+1}"
_secret_bore_tls="${BORE_TLS_PORT:+1}"
_secret_proxy_mode="${PROXY_MODE:+1}"

. "$SCRIPT_DIR/proxy-env.sh"

echo "vproxy port/domain configuration"
echo "================================="
echo "Current effective values (Codespaces secret > saved config > default):"
echo "  Local HTTP port (container):  $LOCAL_HTTP_PORT"
echo "  Local TLS port (container):   $LOCAL_TLS_PORT"
echo "  Bore HTTP port (public):      $BORE_HTTP_PORT  -> bore.pub:$BORE_HTTP_PORT"
echo "  Bore TLS port (public):       $BORE_TLS_PORT  -> bore.pub:$BORE_TLS_PORT"
echo "  TLS domain (DuckDNS):         ${DUCKDNS_DOMAIN:-<not set>}"
echo "  Mode:                         $PROXY_MODE  (performance = core proxy only, no Ollama/routine emails; self-healing stays on either way)"
echo
echo "How do you want to set custom values?"
echo "  1) Codespaces secrets (recommended) -- survives a full Codespace rebuild, not just a stop/start"
echo "  2) Enter values now, right here -- takes effect after a restart, but is wiped on a rebuild unless you also add secrets"
echo "  3) Cancel, leave everything as-is"
printf "Choice [1/2/3]: "
read choice

case "$choice" in
  1)
    cat <<EOF

Add/update these at https://github.com/settings/codespaces, scoped to
this repo, then stop and restart the Codespace -- a new terminal in the
same running Codespace isn't enough, secrets are only injected at
container start:

  LOCAL_HTTP_PORT   container-local port for the plain proxy    (default 8080)
  LOCAL_TLS_PORT    container-local port for the TLS proxy      (default 8443)
  BORE_HTTP_PORT    public bore.pub port for the plain proxy    (default 54584)
  BORE_TLS_PORT     public bore.pub port for the TLS proxy      (default 54585)
  DUCKDNS_DOMAIN    TLS hostname's bare subdomain (see docs/setup.md)
  PROXY_MODE        "normal" or "performance" (default normal)

Any left unset keep using their current/default value shown above. If a
BORE_HTTP_PORT/BORE_TLS_PORT you pick is already taken by someone else on
bore.pub, bore falls back to a random port instead -- check /tmp/bore.log
or /tmp/bore-tls.log (the "listening at bore.pub:<port>" line) to see
what it actually got.
EOF
    ;;
  2)
    echo
    echo "Press enter on any prompt to keep the current/default value shown."
    ask() {
      # $1 = prompt label, $2 = current value
      printf "%s [%s]: " "$1" "$2" >&2
      read val
      if [ -n "$val" ]; then printf '%s' "$val"; else printf '%s' "$2"; fi
    }
    new_local_http=$(ask "Local HTTP port" "$LOCAL_HTTP_PORT")
    new_local_tls=$(ask "Local TLS port" "$LOCAL_TLS_PORT")
    new_bore_http=$(ask "Bore HTTP (public) port" "$BORE_HTTP_PORT")
    new_bore_tls=$(ask "Bore TLS (public) port" "$BORE_TLS_PORT")
    new_proxy_mode=$(ask "Mode: normal or performance" "$PROXY_MODE")

    for p in "$new_local_http" "$new_local_tls" "$new_bore_http" "$new_bore_tls"; do
      case "$p" in
        ''|*[!0-9]*|0)
          echo "Invalid port: '$p' -- must be a positive whole number. Aborting, nothing changed." >&2
          exit 1
          ;;
      esac
      if [ "$p" -gt 65535 ]; then
        echo "Invalid port: '$p' -- must be 65535 or lower. Aborting, nothing changed." >&2
        exit 1
      fi
    done

    if [ "$new_local_http" = "$new_local_tls" ]; then
      echo "Local HTTP and TLS ports must be different -- both bind on this same container. Aborting, nothing changed." >&2
      exit 1
    fi
    if [ "$new_bore_http" = "$new_bore_tls" ]; then
      echo "Bore HTTP and TLS (public) ports must be different -- bore.pub can't hand out the same port to both. Aborting, nothing changed." >&2
      exit 1
    fi

    case "$new_proxy_mode" in
      normal|performance) ;;
      *)
        echo "Invalid mode: '$new_proxy_mode' -- must be 'normal' or 'performance'. Aborting, nothing changed." >&2
        exit 1
        ;;
    esac

    {
      echo "# Written by configure-proxy on $(date -u '+%Y-%m-%d %H:%M:%SZ')."
      echo "# Only takes effect for whichever of these DON'T already have a"
      echo "# real Codespaces secret set -- see proxy-env.sh for precedence."
      echo "# Wiped on a Codespace rebuild -- add Codespaces secrets instead"
      echo "# for a value that needs to survive that."
      echo "LOCAL_HTTP_PORT=\"\${LOCAL_HTTP_PORT:-$new_local_http}\""
      echo "LOCAL_TLS_PORT=\"\${LOCAL_TLS_PORT:-$new_local_tls}\""
      echo "BORE_HTTP_PORT=\"\${BORE_HTTP_PORT:-$new_bore_http}\""
      echo "BORE_TLS_PORT=\"\${BORE_TLS_PORT:-$new_bore_tls}\""
      echo "PROXY_MODE=\"\${PROXY_MODE:-$new_proxy_mode}\""
    } > "$CONFIG_FILE"

    echo
    echo "Saved to $CONFIG_FILE."
    printf "Restart the proxy now with these values? [Y/n]: "
    read go
    case "$go" in
      n|N|no|No|NO) echo "Not restarting -- run 'restart-proxy' whenever you're ready." ;;
      *)
        [ -z "$_secret_local_http" ] && unset LOCAL_HTTP_PORT
        [ -z "$_secret_local_tls" ] && unset LOCAL_TLS_PORT
        [ -z "$_secret_bore_http" ] && unset BORE_HTTP_PORT
        [ -z "$_secret_bore_tls" ] && unset BORE_TLS_PORT
        [ -z "$_secret_proxy_mode" ] && unset PROXY_MODE
        restart-proxy
        ;;
    esac
    ;;
  *)
    echo "Cancelled, nothing changed."
    ;;
esac
