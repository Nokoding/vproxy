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

export LOCAL_HTTP_PORT LOCAL_TLS_PORT BORE_HTTP_PORT BORE_TLS_PORT PROXY_CONFIG_IS_DEFAULT
