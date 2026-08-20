#!/bin/sh
# Sends a watchdog alert email via Gmail SMTP. Credentials come from
# GMAIL_USER / GMAIL_APP_PASSWORD, injected as Codespaces secrets (never
# committed to the repo). Usage: alert-email.sh "<subject>" "<body>"

SUBJECT="$1"
BODY="$2"
TO="${ALERT_EMAIL:-nokodash311@gmail.com}"

if [ -z "$GMAIL_USER" ] || [ -z "$GMAIL_APP_PASSWORD" ]; then
  echo "$(date): alert email skipped, GMAIL_USER/GMAIL_APP_PASSWORD not set" >> /tmp/proxy-watchdog.log
  exit 0
fi

curl -s -m 10 --ssl-reqd \
  --url "smtps://smtp.gmail.com:465" \
  --mail-from "$GMAIL_USER" \
  --mail-rcpt "$TO" \
  --user "$GMAIL_USER:$GMAIL_APP_PASSWORD" \
  --upload-file - >> /tmp/proxy-watchdog.log 2>&1 <<EOF
From: vproxy watchdog <$GMAIL_USER>
To: $TO
Subject: $SUBJECT

$BODY
EOF
