#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
# SPDX-License-Identifier: MIT
#
# k3s-get-token — Display the k3s server join token
#
# Waits for the token file to be created (k3s server generates it
# on first start) and prints it. Useful for setting up agent nodes.

TOKEN_FILE="/var/lib/rancher/k3s/server/node-token"
TIMEOUT=60

if [ ! -f "$TOKEN_FILE" ]; then
    echo "Waiting for k3s server to generate token..."
    i=0
    while [ ! -f "$TOKEN_FILE" ] && [ $i -lt $TIMEOUT ]; do
        sleep 2
        i=$((i + 2))
    done
fi

if [ -f "$TOKEN_FILE" ]; then
    echo ""
    echo "=== K3s Join Token ==="
    cat "$TOKEN_FILE"
    echo ""
    echo "To join an agent node:"
    echo "  run-k3s-multinode.sh agent --token \$(k3s-get-token)"
    echo ""
else
    echo "Token not found. Is k3s server running?"
    echo "  systemctl status k3s"
fi
