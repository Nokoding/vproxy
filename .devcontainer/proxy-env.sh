# Shared port config, sourced (not executed) by every script that needs
# to know the proxy's actual ports/domain -- keeps the default/override
# precedence in one place instead of copy-pasted into restart-proxy.sh,
# quick-test.sh, port-check.sh, and configure-proxy.sh.
#
# Precedence: a real Codespaces secret (already in the environment when
# this is sourced) always wins > $HOME/.vproxy-config (written by
# `configure-proxy`, survives a stop/start but is wiped on a full rebuild,
# same as everything else in the container filesystem outside git +
# secrets) > the hardcoded defaults below.

CONFIG_FILE="$HOME/.vproxy-config"

if [ -z "$LOCAL_HTTP_PORT" ] && [ -z "$LOCAL_TLS_PORT" ] && [ -z "$BORE_HTTP_PORT" ] && [ -z "$BORE_TLS_PORT" ] && [ -z "$LOCAL_PAC_PORT" ] && [ -z "$BORE_PAC_PORT" ] && [ ! -f "$CONFIG_FILE" ]; then
  PROXY_CONFIG_IS_DEFAULT=1
else
  PROXY_CONFIG_IS_DEFAULT=0
fi

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

LOCAL_HTTP_PORT="${LOCAL_HTTP_PORT:-8080}"
LOCAL_TLS_PORT="${LOCAL_TLS_PORT:-8443}"
BORE_HTTP_PORT="${BORE_HTTP_PORT:-54584}"
BORE_TLS_PORT="${BORE_TLS_PORT:-54585}"
LOCAL_PAC_PORT="${LOCAL_PAC_PORT:-8090}"
BORE_PAC_PORT="${BORE_PAC_PORT:-54586}"

# Proxy authentication is presence-based, same idiom as MAILERSEND_*/
# DUCKDNS_* elsewhere in this repo gating optional features -- both
# PROXY_USERNAME and PROXY_PASSWORD set turns it on, either/both missing
# means off. No separate on/off flag: presence already IS the toggle, and
# it rules out an inconsistent "flag=on but no credentials" state. vproxy
# itself requires both together (see `requires = "password"` /
# `requires = "username"` on AuthMode in src/main.rs), so this mirrors
# that. NOT included in the PROXY_CONFIG_IS_DEFAULT check above -- that
# check exists to nag a first-time forker to run `configure-proxy`, and
# most forkers leaving auth off is the expected, unremarkable default,
# not something worth nagging about.
if [ -n "$PROXY_USERNAME" ] && [ -n "$PROXY_PASSWORD" ]; then
  PROXY_AUTH_ENABLED=1
else
  PROXY_AUTH_ENABLED=0
  # Exactly one set is almost always a typo (a misspelled secret name, or
  # one added and the other forgotten) rather than an intentional choice
  # -- and it fails all the way open, indistinguishable from auth never
  # having been configured at all (both `restart-proxy` and `port-check`
  # would otherwise just print the same generic "Auth: OFF" either way).
  # Flag it explicitly instead of staying silent about a public proxy
  # that's open when it looks like it shouldn't be.
  if [ -n "$PROXY_USERNAME" ] || [ -n "$PROXY_PASSWORD" ]; then
    echo "WARNING: only one of PROXY_USERNAME/PROXY_PASSWORD is set -- both are required to enable auth, so the proxy is running OPEN (unauthenticated) right now. Set both, or neither." >&2
  fi
fi

# "performance" skips the Ollama model entirely (restart-proxy.sh never
# starts `ollama serve`, freeing the RAM/CPU it'd otherwise hold resident)
# and quick-test-runner.sh skips its routine "all good" email -- core
# proxy functionality only. Self-healing (crash/hang auto-restart, and
# emailing when a real failure is detected) is NOT gated by this: it
# stays on in both modes, just using the fixed-throttle fallback instead
# of an AI-written diagnosis, the same fallback either mode already falls
# back to whenever Ollama is unavailable. Any value other than exactly
# "performance" is treated as normal -- a typo'd secret (e.g.
# "Performance") fails safe to normal rather than landing in some
# undefined third state. Both `restart-proxy` and `port-check` print the
# resolved mode, so a typo is still discoverable, just not rejected here.
case "$PROXY_MODE" in
  performance) : ;;
  *) PROXY_MODE="normal" ;;
esac

export LOCAL_HTTP_PORT LOCAL_TLS_PORT BORE_HTTP_PORT BORE_TLS_PORT LOCAL_PAC_PORT BORE_PAC_PORT PROXY_CONFIG_IS_DEFAULT PROXY_MODE PROXY_USERNAME PROXY_PASSWORD PROXY_AUTH_ENABLED
