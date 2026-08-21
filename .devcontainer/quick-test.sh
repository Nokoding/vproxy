#!/bin/sh
# Hits the 4 sites the user actually tests this proxy with, through
# whichever proxy variants are currently up. Plain HTTP (8080) is always
# checked; the TLS variant (8443) is only checked if its PID file shows it's
# actually running, since cert issuance is best-effort and it may be down
# with the plain proxy otherwise fine.
#
# Prints one line per site/proxy to stdout and exits 0 only if every check
# that ran passed (2xx/3xx). Caller (quick-test-runner.sh) captures both.

SITES="discord.com tiktok.com youtube.com google.com"

# $1 = curl -x proxy arg, $2 = extra curl flags (may be empty), $3 = site,
# $4 = label for the output line.
check() {
  code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 -x "$1" $2 "https://$3" 2>/dev/null)
  case "$code" in
    2??|3??) echo "$4 $3: OK ($code)"; return 0 ;;
    *) echo "$4 $3: FAIL (${code:-no response})"; return 1 ;;
  esac
}

FAIL=0

for site in $SITES; do
  check "http://127.0.0.1:8080" "" "$site" "plain" || FAIL=1
done

if [ -f /tmp/vproxy-tls.pid ] && kill -0 "$(cat /tmp/vproxy-tls.pid)" 2>/dev/null; then
  for site in $SITES; do
    # --proxy-insecure: the cert is issued for cdspc.duckdns.org, not
    # 127.0.0.1, and this checks the proxy itself over the loopback
    # interface rather than through the bore tunnel -- cert validity was
    # already confirmed separately by tls-cert.sh at issuance time.
    check "https://127.0.0.1:8443" "--proxy-insecure" "$site" "tls  " || FAIL=1
  done
else
  echo "tls   proxy not running, skipped"
fi

exit $FAIL
