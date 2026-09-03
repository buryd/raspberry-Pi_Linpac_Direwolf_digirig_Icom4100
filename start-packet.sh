#!/bin/bash
# start-packet.sh — start Direwolf + AX.25 over SSH, then run linpac in another session.
# Installer also writes a copy to $HOME/start-packet.sh with your callsign noted.
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Do not start packet as root. Run this as your normal Pi user."
  exit 1
fi

CONF="${HOME}/direwolf.conf"
LOG="/tmp/direwolf.log"
PORT="$(awk '/^[^#]/ && NF { print $1; exit }' /etc/ax25/axports 2>/dev/null || true)"
PORT="${PORT:-radio}"

if [[ ! -f "$CONF" ]]; then
  echo "Missing $CONF — run install-linpac-packet.sh first."
  exit 1
fi

if ! id -nG | grep -qw dialout; then
  echo "WARNING: $USER is not in group dialout yet. Log out of SSH and back in, then retry."
fi

if pgrep -x direwolf >/dev/null; then
  echo "Direwolf is already running."
else
  echo "Starting Direwolf..."
  nohup direwolf -t 0 -c "$CONF" -p >>"$LOG" 2>&1 &
  echo $! >/tmp/direwolf.pid
  sleep 3
fi

if [[ ! -e /tmp/kisstnc ]]; then
  echo "Direwolf did not create /tmp/kisstnc. Last log lines:"
  tail -n 40 "$LOG" || true
  echo "Trying socat KISS TCP 8001..."
  pkill -x socat 2>/dev/null || true
  socat pty,raw,echo=0,link=/tmp/kisstnc tcp:127.0.0.1:8001 &
  sleep 1
fi

if [[ ! -e /tmp/kisstnc ]]; then
  echo "Still no /tmp/kisstnc. See $LOG"
  exit 1
fi

KISS_DEV="/tmp/kisstnc"
if [[ -L /tmp/kisstnc ]]; then
  KISS_DEV="$(readlink -f /tmp/kisstnc)"
fi

if ip link show ax0 >/dev/null 2>&1; then
  echo "AX.25 interface ax0 already exists."
else
  echo "Attaching AX.25 port $PORT to $KISS_DEV"
  sudo kissattach "$KISS_DEV" "$PORT" || sudo kissattach -l "$KISS_DEV" "$PORT"
  sudo kissparms -p "$PORT" -t 300 -l 10 -s 100 -r 64 || true
fi

echo "Ready. AX.25 port $PORT"
echo "In another SSH session (use ssh -t) run:  linpac"
echo "Direwolf log: $LOG"
echo "Stop with:  $HOME/stop-packet.sh   or   ./stop-packet.sh"
