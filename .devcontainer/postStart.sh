#!/bin/sh
vproxy run --bind 0.0.0.0:8080 http &
bore local 8080 --to bore.pub > /tmp/bore.log 2>&1 &
