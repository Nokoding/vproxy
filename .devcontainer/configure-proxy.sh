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
_secret_local_pac="${LOCAL_PAC_PORT:+1}"
_secret_bore_pac="${BORE_PAC_PORT:+1}"
_secret_username="${PROXY_USERNAME:+1}"
_secret_password="${PROXY_PASSWORD:+1}"

. "$SCRIPT_DIR/proxy-env.sh"

echo "vproxy port/domain configuration"
echo "================================="
echo "Current effective values (Codespaces secret > saved config > default):"
echo "  Local HTTP port (container):  $LOCAL_HTTP_PORT"
echo "  Local TLS port (container):   $LOCAL_TLS_PORT"
echo "  Bore HTTP port (public):      $BORE_HTTP_PORT  -> bore.pub:$BORE_HTTP_PORT"
echo "  Bore TLS port (public):       $BORE_TLS_PORT  -> bore.pub:$BORE_TLS_PORT"
echo "  Local PAC port (container):   $LOCAL_PAC_PORT"
echo "  Bore PAC port (public):       $BORE_PAC_PORT  -> http://bore.pub:$BORE_PAC_PORT/proxy.pac"
echo "  TLS domain (DuckDNS):         ${DUCKDNS_DOMAIN:-<not set>}"
echo "  Mode:                         $PROXY_MODE  (performance = core proxy only, no Ollama/routine emails; self-healing stays on either way)"
if [ "$PROXY_AUTH_ENABLED" = "1" ]; then
  echo "  Auth:                         ON  (username: $PROXY_USERNAME)"
else
  echo "  Auth:                         OFF -- this proxy is open to anyone who finds the address"
fi
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
  LOCAL_PAC_PORT    container-local port for the .pac file      (default 8090)
  BORE_PAC_PORT     public bore.pub port for the .pac file      (default 54586)
  DUCKDNS_DOMAIN    TLS hostname's bare subdomain (see docs/setup.md)
  PROXY_MODE        "normal" or "performance" (default normal)
  PROXY_USERNAME    proxy auth username (unset = no auth)
  PROXY_PASSWORD    proxy auth password (unset = no auth)

Any left unset keep using their current/default value shown above. If a
BORE_HTTP_PORT/BORE_TLS_PORT/BORE_PAC_PORT you pick is already taken by
someone else on bore.pub, bore falls back to a random port instead --
check /tmp/bore.log, /tmp/bore-tls.log, or /tmp/bore-pac.log (the
"listening at bore.pub:<port>" line) to see what it actually got.

PROXY_USERNAME/PROXY_PASSWORD turn auth on only when BOTH are set --
either alone leaves the proxy unauthenticated (open to anyone who finds
the address). Secrets are the safer place for these specifically: unlike
the ports, this is credentials, and option 2 below stores them in plain
text in $HOME/.vproxy-config.
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
    new_local_pac=$(ask "Local PAC port" "$LOCAL_PAC_PORT")
    new_bore_pac=$(ask "Bore PAC (public) port" "$BORE_PAC_PORT")
    new_proxy_mode=$(ask "Mode: normal or performance" "$PROXY_MODE")

    for p in "$new_local_http" "$new_local_tls" "$new_bore_http" "$new_bore_tls" "$new_local_pac" "$new_bore_pac"; do
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

    # All three container-local ports bind on this same container, and
    # bore.pub can't hand out the same public port to two tunnels -- so
    # each group of three needs to be pairwise distinct, not just each
    # pair checked in isolation (a loop scales to a third port; three
    # separate pairwise if-checks would need to grow to three x2 = six).
    seen=""
    for p in "$new_local_http" "$new_local_tls" "$new_local_pac"; do
      case " $seen " in
        *" $p "*)
          echo "Local ports (HTTP/TLS/PAC) must all be different -- got '$p' twice. Aborting, nothing changed." >&2
          exit 1
          ;;
      esac
      seen="$seen $p"
    done
    seen=""
    for p in "$new_bore_http" "$new_bore_tls" "$new_bore_pac"; do
      case " $seen " in
        *" $p "*)
          echo "Bore (public) ports (HTTP/TLS/PAC) must all be different -- got '$p' twice. Aborting, nothing changed." >&2
          exit 1
          ;;
      esac
      seen="$seen $p"
    done

    case "$new_proxy_mode" in
      normal|performance) ;;
      *)
        echo "Invalid mode: '$new_proxy_mode' -- must be 'normal' or 'performance'. Aborting, nothing changed." >&2
        exit 1
        ;;
    esac

    echo
    if [ "$PROXY_AUTH_ENABLED" = "1" ]; then
      auth_current="y"
    else
      auth_current="n"
    fi
    printf "Require a username/password to use this proxy? [y/N, currently %s -- Enter keeps it as-is]: " "$auth_current"
    read auth_choice
    case "$auth_choice" in
      y|Y|yes|Yes|YES)
        printf "Username: "
        IFS= read -r new_username
        printf "Password (hidden): "
        # Restore terminal echo on Ctrl-C too -- otherwise an interrupt
        # between the two stty calls below leaves the terminal typing
        # invisibly with no on-screen hint why.
        trap 'stty echo 2>/dev/null; echo; exit 130' INT
        stty -echo 2>/dev/null
        IFS= read -r new_password
        stty echo 2>/dev/null
        trap - INT
        echo
        # Both get written into a double-quoted string inside
        # $CONFIG_FILE (see below), which is later `.`-sourced as shell --
        # unlike the ports, nothing upstream constrains these to a safe
        # character set. ", `, $, \ would break that file's quoting or get
        # interpreted (command substitution, var expansion) the next time
        # it's sourced; } would prematurely close the surrounding
        # ${VAR:-word} expansion, truncating/relocating the stored value
        # without any syntax error to notice by. Reject rather than
        # attempt to escape -- simpler to get right for a personal proxy.
        # (`read -r` above already keeps a literal \ intact so this can
        # actually catch it, and IFS= keeps leading/trailing whitespace
        # from being silently trimmed out of the value.)
        for v in "$new_username" "$new_password"; do
          if [ -z "$v" ]; then
            echo "Username and password can't be empty. Aborting, nothing changed." >&2
            exit 1
          fi
          case "$v" in
            *'"'*|*'`'*|*'$'*|*'\'*|*'{'*|*'}'*)
              echo 'Username/password can'"'"'t contain " ` $ \ { } -- these would break the saved config file. Aborting, nothing changed.' >&2
              exit 1
              ;;
          esac
        done
        ;;
      n|N|no|No|NO)
        new_username=""
        new_password=""
        ;;
      "")
        # Enter alone means "leave it as-is" everywhere else in this
        # menu (see the instructions printed above) -- treating it as an
        # implicit "no" here would silently strip auth off a proxy that
        # was relying on it, the first time someone runs this just to
        # change an unrelated port.
        new_username="$PROXY_USERNAME"
        new_password="$PROXY_PASSWORD"
        ;;
      *)
        echo "Invalid answer: '$auth_choice' -- must be y or n. Aborting, nothing changed." >&2
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
      echo "LOCAL_PAC_PORT=\"\${LOCAL_PAC_PORT:-$new_local_pac}\""
      echo "BORE_PAC_PORT=\"\${BORE_PAC_PORT:-$new_bore_pac}\""
      echo "PROXY_MODE=\"\${PROXY_MODE:-$new_proxy_mode}\""
      echo "PROXY_USERNAME=\"\${PROXY_USERNAME:-$new_username}\""
      echo "PROXY_PASSWORD=\"\${PROXY_PASSWORD:-$new_password}\""
    } > "$CONFIG_FILE"
    # Now holds a plaintext password (ports were never sensitive enough
    # to bother with this) -- restrict to owner-only.
    chmod 600 "$CONFIG_FILE" 2>/dev/null

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
        [ -z "$_secret_local_pac" ] && unset LOCAL_PAC_PORT
        [ -z "$_secret_bore_pac" ] && unset BORE_PAC_PORT
        [ -z "$_secret_username" ] && unset PROXY_USERNAME
        [ -z "$_secret_password" ] && unset PROXY_PASSWORD
        restart-proxy
        ;;
    esac
    ;;
  *)
    echo "Cancelled, nothing changed."
    ;;
esac
