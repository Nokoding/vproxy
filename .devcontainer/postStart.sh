#!/bin/sh
command -v claude >/dev/null 2>&1 || curl -fsSL claude.ai/install.sh | bash

sh "$(dirname "$0")/restart-proxy.sh"
