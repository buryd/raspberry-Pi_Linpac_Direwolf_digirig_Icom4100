#!/bin/bash
# stop-packet.sh — tear down Direwolf / kissattach / linpac
set -euo pipefail

echo "Stopping packet stack..."
sudo killall kissattach 2>/dev/null || true
pkill -x linpac 2>/dev/null || true
pkill -x socat 2>/dev/null || true
if [[ -f /tmp/direwolf.pid ]]; then
  kill "$(cat /tmp/direwolf.pid)" 2>/dev/null || true
  rm -f /tmp/direwolf.pid
fi
pkill -x direwolf 2>/dev/null || true
sudo ip link set ax0 down 2>/dev/null || true
echo "Stopped."
