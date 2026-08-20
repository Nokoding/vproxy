#!/bin/sh
# Asks a local Ollama model (llama3.2:3b) whether a detected proxy failure
# is worth emailing about right now, and to write a short diagnosis from
# the recent log context. Runs entirely on-machine, no external API/cost.
#
# Usage: ai-triage.sh "<failure_number>" "<seconds_since_last_alert_or_never>"
# On success: prints {"should_alert":bool,"subject":str,"diagnosis":str} to
# stdout, exit 0. On any failure (Ollama down, bad/slow response, invalid
# JSON): prints nothing, exit 1 -- caller must fall back to the fixed
# throttle heuristic so alerting never silently depends on the model.
#
# Uses printf '%s' instead of echo throughout when piping JSON into jq --
# dash's echo builtin (unlike bash's) interprets backslash escapes like \n
# by default, which corrupts any JSON string containing an escaped newline
# (e.g. whenever the model pretty-prints its own JSON output) before jq
# ever sees it.

FAILURE_NUM="$1"
SINCE_LAST="$2"

VPROXY_TAIL=$(tail -15 /tmp/vproxy.log 2>/dev/null)
BORE_TAIL=$(tail -15 /tmp/bore.log 2>/dev/null)

USER_MSG=$(jq -n \
  --arg n "$FAILURE_NUM" \
  --arg since "$SINCE_LAST" \
  --arg vp "$VPROXY_TAIL" \
  --arg bo "$BORE_TAIL" \
  '"Failure #\($n) in this bad stretch. Seconds since last alert email: \($since) (\"never\" if this is the first).\n\nvproxy.log tail (last activity before the timeout):\n\($vp)\n\nbore.log tail:\n\($bo)"')

PAYLOAD=$(jq -n \
  --arg sys "You are a monitoring assistant for a proxy server (vproxy) tunneled through bore.pub. A health check against the proxy has ALREADY FAILED (confirmed timeout) -- that is a given fact, not something to verify. You will be given recent log excerpts (showing the last activity BEFORE the failure) and failure history. Your job: (1) decide should_alert -- true if the operator should be emailed now given the failure history/pattern, false only if this looks like a repeat that should stay suppressed, and (2) write a one-sentence plain-English diagnosis of what likely caused the timeout based on the log context. Respond with ONLY valid JSON, no other text." \
  --argjson user "$USER_MSG" \
  '{
    model: "llama3.2:3b",
    stream: false,
    messages: [
      {role: "system", content: $sys},
      {role: "user", content: $user}
    ],
    format: {
      type: "object",
      properties: {
        should_alert: {type: "boolean"},
        subject: {type: "string"},
        diagnosis: {type: "string"}
      },
      required: ["should_alert", "subject", "diagnosis"]
    }
  }')

RESPONSE=$(curl -s -m 45 http://127.0.0.1:11434/api/chat -d "$PAYLOAD")
CONTENT=$(printf '%s' "$RESPONSE" | jq -r '.message.content // empty' 2>/dev/null)

if [ -z "$CONTENT" ]; then
  exit 1
fi

if ! printf '%s' "$CONTENT" | jq -e '.should_alert != null and .subject != null and .diagnosis != null' > /dev/null 2>&1; then
  exit 1
fi

printf '%s\n' "$CONTENT"
exit 0
