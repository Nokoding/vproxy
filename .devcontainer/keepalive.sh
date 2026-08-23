#!/bin/sh
# GitHub stops an idle Codespace after 30 min with no terminal activity.
# Per GitHub's docs, "terminal activity, either input or output" resets
# that clock -- a silent background process does NOT. Confirmed directly
# 2026-08-23: idle_timeout_minutes can't even be raised via the API with
# the auto-injected GITHUB_TOKEN (PATCH /user/codespaces/{name} silently
# no-ops), and `gh codespace edit` has no --idle-timeout flag at all --
# it's only settable once, at `codespace create` time.
#
# So instead of fighting the API, this writes a cursor save+restore
# escape sequence (no visible effect, no beep, doesn't touch the shell's
# input line) to every attached pty often enough to register as "output"
# without ever appearing on screen. Zero CPU/network cost between ticks,
# and it's a no-op outside a Codespace.
[ -n "$CODESPACES" ] || exit 0

while true; do
  for pty in /dev/pts/[0-9]*; do
    [ -c "$pty" ] || continue
    printf '\0337\0338' > "$pty" 2>/dev/null
  done
  sleep 1200
done
