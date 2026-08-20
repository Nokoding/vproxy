#!/bin/sh
# Sends a watchdog alert email via the MailerSend API. Credentials come
# from MAILERSEND_API_TOKEN / MAILERSEND_FROM, injected as Codespaces
# secrets (never committed to the repo). Usage:
#   alert-email.sh "<subject>" "<body>"

SUBJECT="$1"
BODY="$2"
TO="${ALERT_EMAIL:-nokodash311@gmail.com}"

if [ -z "$MAILERSEND_API_TOKEN" ] || [ -z "$MAILERSEND_FROM" ]; then
  echo "$(date): alert email skipped, MAILERSEND_API_TOKEN/MAILERSEND_FROM not set" >> /tmp/proxy-watchdog.log
  exit 0
fi

PAYLOAD=$(jq -n \
  --arg from "$MAILERSEND_FROM" \
  --arg to "$TO" \
  --arg subject "$SUBJECT" \
  --arg text "$BODY" \
  '{from: {email: $from}, to: [{email: $to}], subject: $subject, text: $text}')

curl -s -m 10 -X POST https://api.mailersend.com/v1/email \
  -H "Authorization: Bearer $MAILERSEND_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" >> /tmp/proxy-watchdog.log 2>&1
