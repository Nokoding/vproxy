#!/bin/sh
vproxy run --bind 0.0.0.0:8080 http > /tmp/vproxy.log 2>&1 &
bore local 8080 --to bore.pub --port 54584 > /tmp/bore.log 2>&1 &
