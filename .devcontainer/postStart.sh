#!/bin/sh
nohup vproxy run --bind 0.0.0.0:8080 http > /tmp/vproxy.log 2>&1 &
nohup bore local 8080 --to bore.pub > /tmp/bore.log 2>&1 &
