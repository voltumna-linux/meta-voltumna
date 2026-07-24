#!/bin/sh
#
# Simple test service for verifying container autostart
# Writes timestamps to stdout (captured by container logs)
#

INTERVAL=${INTERVAL:-5}
MESSAGE=${MESSAGE:-"autostart-test is running"}

echo "=== Autostart Test Service ==="
echo "Started at: $(date)"
echo "PID: $$"
echo "Interval: ${INTERVAL}s"
echo "=============================="

count=0
while true; do
    count=$((count + 1))
    echo "[${count}] $(date): ${MESSAGE}"
    sleep ${INTERVAL}
done
