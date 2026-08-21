#!/bin/sh
# Startup smoke test + self-repair + email report, run once at the end of
# restart-proxy.sh. Proves the proxy can actually reach the 4 sites the
# user manually tests with (discord/tiktok/youtube/google) -- not just that
# the vproxy/bore processes exist -- every time the Codespace (re)starts.
#
# Flow:
#   1. quick-test.sh. All good -> ask Ollama for a one-line comment and
#      email "it's good" with that comment.
#   2. Anything failed -> kill+respawn vproxy/bore/vproxy-tls/bore-tls by
#      PID (same recovery the PROXY_WATCHDOG in restart-proxy.sh uses on a
#      hung health check -- the while-loops already running from
#      restart-proxy.sh relaunch them), email that a repair was attempted,
#      then re-run quick-test.sh and email THOSE results.
#   3. If the retest still fails, ask Ollama for one non-destructive next
#      diagnostic/fix step, write full details to a new dated file under
#      .devcontainer/notes/, and add a one-line pointer to CLAUDE.md (which
#      Claude Code reads automatically at the start of every session) so
#      the next session picks it up without anyone going to look for a log.
#
# Never blocks proxy startup itself -- restart-proxy.sh backgrounds this
# with a startup delay.

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
QUICK_TEST="$SCRIPT_DIR/quick-test.sh"
ALERT_SCRIPT="$SCRIPT_DIR/alert-email.sh"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
NOTES_DIR="$REPO_ROOT/.devcontainer/notes"

# $1 = system prompt, $2 = user content. Prints Ollama's plain-text reply on
# success. On any failure (Ollama down/slow/empty response) prints nothing
# and returns 1 -- callers must handle that, alerting never silently depends
# on the model being up (same contract as ai-triage.sh).
ask_ollama() {
  payload=$(jq -n --arg sys "$1" --arg user "$2" \
    '{model:"llama3.2:3b",stream:false,messages:[{role:"system",content:$sys},{role:"user",content:$user}]}')
  resp=$(curl -s -m 45 http://127.0.0.1:11434/api/chat -d "$payload")
  content=$(printf '%s' "$resp" | jq -r '.message.content // empty' 2>/dev/null)
  [ -z "$content" ] && return 1
  printf '%s\n' "$content"
  return 0
}

run_quick_test() {
  QT_OUTPUT=$("$QUICK_TEST")
  QT_RESULT=$?
}

run_quick_test
FIRST_OUTPUT="$QT_OUTPUT"
FIRST_RESULT=$QT_RESULT

if [ "$FIRST_RESULT" -eq 0 ]; then
  comment=$(ask_ollama \
    "You are a monitoring assistant for a personal proxy server. A startup quick test just ran and every site passed. Write one short, plain-English sentence confirming the proxy is ready to use." \
    "$FIRST_OUTPUT")
  [ -z "$comment" ] && comment="(Ollama unavailable for commentary -- but every site passed.)"
  "$ALERT_SCRIPT" "vproxy quick test: all good" "$FIRST_OUTPUT

$comment"
  exit 0
fi

# Self-repair: kill by PID, same as PROXY_WATCHDOG's recovery in
# restart-proxy.sh -- the respawn while-loops already running relaunch each
# process immediately.
[ -f /tmp/vproxy.pid ] && kill -9 "$(cat /tmp/vproxy.pid)" 2>/dev/null
[ -f /tmp/bore.pid ] && kill -9 "$(cat /tmp/bore.pid)" 2>/dev/null
[ -f /tmp/vproxy-tls.pid ] && kill -9 "$(cat /tmp/vproxy-tls.pid)" 2>/dev/null
[ -f /tmp/bore-tls.pid ] && kill -9 "$(cat /tmp/bore-tls.pid)" 2>/dev/null

"$ALERT_SCRIPT" "vproxy quick test: repairing" "Startup quick test failed, attempting self-repair (restart vproxy+bore):

$FIRST_OUTPUT"

sleep 8 # let the respawn loops relaunch vproxy/bore and bore reconnect its tunnel(s)

run_quick_test
SECOND_OUTPUT="$QT_OUTPUT"
SECOND_RESULT=$QT_RESULT

if [ "$SECOND_RESULT" -eq 0 ]; then
  "$ALERT_SCRIPT" "vproxy quick test: repaired, now good" "$SECOND_OUTPUT"
  exit 0
fi

patch_note=$(ask_ollama \
  "You are a monitoring assistant for a personal proxy server (vproxy+bore+acme.sh running in a devcontainer). A kill+respawn self-repair did NOT fix a startup quick-test failure. You will be given the quick-test output from after the repair attempt. Suggest ONE concrete, NON-DESTRUCTIVE next diagnostic or fix step for a future session to try -- nothing that deletes data, force-resets config, or could break anything currently working. 2-3 sentences." \
  "$SECOND_OUTPUT")
[ -z "$patch_note" ] && patch_note="(Ollama unavailable -- no automated suggestion. Check /tmp/vproxy.log, /tmp/bore.log, /tmp/vproxy-tls.log, /tmp/bore-tls.log by hand.)"

mkdir -p "$NOTES_DIR"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
NOTE_FILE="$NOTES_DIR/quick-test-failure-$TIMESTAMP.md"

{
  echo "# Quick-test failure, $(date -u '+%Y-%m-%d %H:%M:%SZ')"
  echo
  echo "Startup quick test failed twice in a row: once before, once after a"
  echo "kill+respawn self-repair attempt. Left here by quick-test-runner.sh"
  echo "for the next Claude Code session to investigate."
  echo
  echo "## Quick-test output before repair"
  echo '```'
  printf '%s\n' "$FIRST_OUTPUT"
  echo '```'
  echo
  echo "## Quick-test output after repair"
  echo '```'
  printf '%s\n' "$SECOND_OUTPUT"
  echo '```'
  echo
  echo "## Ollama's suggested next step"
  printf '%s\n' "$patch_note"
} > "$NOTE_FILE"

NOTE_REL_PATH=".devcontainer/notes/quick-test-failure-$TIMESTAMP.md"
{
  echo
  echo "## Unresolved: quick-test failure ($(date -u '+%Y-%m-%d'))"
  echo
  echo "Startup quick test failed twice in a row (before and after a"
  echo "self-repair restart). See \`$NOTE_REL_PATH\` for the quick-test"
  echo "output and Ollama's suggested next step. Investigate and delete"
  echo "this section + the notes file once resolved."
} >> "$CLAUDE_MD"

"$ALERT_SCRIPT" "vproxy quick test: still failing after repair" "$SECOND_OUTPUT

Ollama's suggested next step:
$patch_note

(Also written to $NOTE_REL_PATH and noted in CLAUDE.md for the next Claude Code session.)"
