#!/usr/bin/env python3
# Serves a single static file (the generated proxy.pac) with the PAC MIME
# type on every GET, on the given port. Not `python3 -m http.server`
# directly: that infers Content-Type from the file extension via the
# `mimetypes` module, which has no ".pac" entry, so it'd serve
# application/octet-stream instead of application/x-ns-proxy-autoconfig --
# most browsers tolerate that, but no reason to rely on tolerance. Content
# is re-read from disk on every request so a restart-proxy.sh
# regeneration (new bore.pub port, etc.) takes effect without needing to
# restart this server too.
#
# Usage: pac-server.py <port> <path-to-pac-file>

import http.server
import sys

PORT = int(sys.argv[1])
PAC_FILE = sys.argv[2]


class Handler(http.server.BaseHTTPRequestHandler):
    # This port is publicly reachable (bore.pub:$BORE_PAC_PORT). Without a
    # timeout, a client that connects and never sends a request (a port
    # scanner, a dropped mobile connection, bore holding a half-open
    # socket) blocks the request-read forever -- and since HTTPServer is
    # single-threaded by default, that one stalled connection wedges the
    # PAC endpoint for everyone until TCP keepalive eventually gives up
    # (~2h) or never. socketserver applies this via socket.settimeout().
    timeout = 10

    def do_GET(self):
        self._respond(write_body=True)

    def do_HEAD(self):
        self._respond(write_body=False)

    def _respond(self, write_body):
        try:
            with open(PAC_FILE, "rb") as f:
                body = f.read()
        except OSError:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ns-proxy-autoconfig")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if write_body:
            self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass  # nothing sensitive here; keep /tmp/pac-server.log to real errors only


if __name__ == "__main__":
    # Threading, not plain HTTPServer, so one slow/stalled client (see
    # Handler.timeout above) can't block everyone else even during its
    # own 10s timeout window.
    http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
