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

if [ -z "$LOCAL_HTTP_PORT" ] && [ -z "$LOCAL_TLS_PORT" ] && [ -z "$BORE_HTTP_PORT" ] && [ -z "$BORE_TLS_PORT" ] && [ ! -f "$CONFIG_FILE" ]; then
  PROXY_CONFIG_IS_DEFAULT=1
else
  PROXY_CONFIG_IS_DEFAULT=0
fi

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

LOCAL_HTTP_PORT="${LOCAL_HTTP_PORT:-8080}"
LOCAL_TLS_PORT="${LOCAL_TLS_PORT:-8443}"
BORE_HTTP_PORT="${BORE_HTTP_PORT:-54584}"
BORE_TLS_PORT="${BORE_TLS_PORT:-54585}"

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

export LOCAL_HTTP_PORT LOCAL_TLS_PORT BORE_HTTP_PORT BORE_TLS_PORT PROXY_CONFIG_IS_DEFAULT PROXY_MODE
