#!/bin/bash
# install-linpac-packet.sh
# Install Direwolf, Linux AX.25, and Linpac on Raspberry Pi OS over SSH.
# Do not run this as a root login. Use a normal user; the script calls sudo itself.
#
# From a PC (recommended: keep a TTY so sudo can ask for a password if needed):
#   ssh -t USER@PI_ADDRESS
#   curl -fsSL https://raw.githubusercontent.com/buryd/raspberry-Pi_Linpac_Direwolf_digirig_Icom4100/main/install-linpac-packet.sh -o install-linpac-packet.sh
#   chmod +x install-linpac-packet.sh
#   ./install-linpac-packet.sh --callsign YOURCALL
#
# One-shot from SSH (passwordless sudo):
#   ssh -t USER@PI_ADDRESS 'curl -fsSL https://raw.githubusercontent.com/buryd/raspberry-Pi_Linpac_Direwolf_digirig_Icom4100/main/install-linpac-packet.sh | bash -s -- --callsign YOURCALL'
#
# Environment alternatives:
#   CALLSIGN=YOURCALL ./install-linpac-packet.sh
#   CALLSIGN=YOURCALL SSID=1 AX25_PORT=radio ./install-linpac-packet.sh

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
REPO_RAW="https://raw.githubusercontent.com/buryd/raspberry-Pi_Linpac_Direwolf_digirig_Icom4100/main"
DIREWOLF_GIT="https://github.com/wb2osz/direwolf.git"
LINPAC_GIT_PRIMARY="https://git.code.sf.net/p/linpac/linpac"
LINPAC_GIT_FALLBACK="https://github.com/srl295/linpac.git"

CALLSIGN="${CALLSIGN:-}"
SSID="${SSID:-1}"
AX25_PORT="${AX25_PORT:-radio}"
SKIP_APT=0
SKIP_DIREWOLF=0
SKIP_LINPAC=0
FORCE_REBUILD=0

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Install packet-radio software for Linpac + Direwolf + DigiRig on Raspberry Pi OS.
Safe to run over SSH. Does not start Direwolf or Linpac (those need a live terminal).

Options:
  --callsign CALL   Amateur callsign without SSID (required unless CALLSIGN is set)
  --ssid N          SSID for packet identity (default: 1  ->  CALL-1)
  --port NAME       AX.25 port name in /etc/ax25/axports (default: radio)
  --skip-apt        Do not run apt (use if packages are already installed)
  --skip-direwolf   Do not clone/build Direwolf
  --skip-linpac     Do not clone/build Linpac
  --force-rebuild   Rebuild Direwolf and Linpac even if binaries exist
  -h, --help        Show this help

Examples:
  $SCRIPT_NAME --callsign KC4JIR
  CALLSIGN=KC4JIR $SCRIPT_NAME
EOF
}

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --callsign)
      CALLSIGN="${2:-}"
      shift 2
      ;;
    --ssid)
      SSID="${2:-}"
      shift 2
      ;;
    --port)
      AX25_PORT="${2:-}"
      shift 2
      ;;
    --skip-apt) SKIP_APT=1; shift ;;
    --skip-direwolf) SKIP_DIREWOLF=1; shift ;;
    --skip-linpac) SKIP_LINPAC=1; shift ;;
    --force-rebuild) FORCE_REBUILD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

if [[ -z "$CALLSIGN" ]]; then
  if [[ -t 0 ]]; then
    printf 'Enter amateur callsign (no SSID, e.g. KC4JIR): '
    read -r CALLSIGN
  else
    die "No callsign. Re-run with --callsign YOURCALL (needed for non-interactive SSH)."
  fi
fi

CALLSIGN="$(printf '%s' "$CALLSIGN" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')"
[[ -n "$CALLSIGN" ]] || die "Callsign is empty."
[[ "$CALLSIGN" =~ ^[A-Z0-9]{3,7}$ ]] || die "Callsign '$CALLSIGN' does not look valid (3-7 A-Z/0-9)."
[[ "$SSID" =~ ^[0-9]{1,2}$ ]] && (( SSID >= 0 && SSID <= 15 )) || die "SSID must be 0-15."
[[ "$AX25_PORT" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || die "Invalid AX.25 port name: $AX25_PORT"

MYCALL="${CALLSIGN}-${SSID}"

if [[ "$(id -u)" -eq 0 ]]; then
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    REAL_USER="$SUDO_USER"
  else
    die "Do not run this as a root login. SSH in as a normal user, then: ./$SCRIPT_NAME --callsign YOURCALL"
  fi
else
  REAL_USER="$(id -un)"
fi

REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
[[ -n "$REAL_HOME" && -d "$REAL_HOME" ]] || die "Cannot find home directory for $REAL_USER"
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

SRC_DIR="$REAL_HOME/src"
LOG_FILE="$REAL_HOME/linpac-install.log"
DIREWOLF_CONF="$REAL_HOME/direwolf.conf"
START_SCRIPT="$REAL_HOME/start-packet.sh"
STOP_SCRIPT="$REAL_HOME/stop-packet.sh"

run_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo -n "$@" 2>/dev/null || sudo "$@"
  fi
}

run_user() {
  if [[ "$(id -u)" -eq 0 ]]; then
    sudo -u "$REAL_USER" -H "$@"
  else
    "$@"
  fi
}

as_user_bash() {
  if [[ "$(id -u)" -eq 0 ]]; then
    sudo -u "$REAL_USER" -H bash -lc "$*"
  else
    bash -lc "$*"
  fi
}

exec > >(tee -a "$LOG_FILE") 2>&1

log "============================================================"
log "Linpac / Direwolf / DigiRig installer"
log "Time:      $(date -Is)"
log "User:      $REAL_USER"
log "Home:      $REAL_HOME"
log "Callsign:  $MYCALL"
log "AX.25 port:$AX25_PORT"
log "Log:       $LOG_FILE"
log "============================================================"

command -v apt-get >/dev/null || die "This script requires Raspberry Pi OS / Debian (apt-get not found)."

if [[ "$SKIP_APT" -eq 0 ]]; then
  log "==> Installing packages (non-interactive apt)"
  run_root env DEBIAN_FRONTEND=noninteractive apt-get update -y
  run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git cmake build-essential \
    libasound2-dev libudev-dev \
    alsa-utils usbutils \
    libax25 ax25-apps ax25-tools \
    libncurses-dev automake autoconf libtool \
    socat ca-certificates curl
else
  log "==> Skipping apt (--skip-apt)"
fi

log "==> Adding $REAL_USER to dialout and audio groups"
run_root usermod -aG dialout,audio "$REAL_USER"

run_root mkdir -p /etc/ax25 /var/ax25/mail /var/ax25/mheard
run_root chown "$REAL_USER" /var/ax25/mail

AXLISTEN_BIN=""
if [[ -x /usr/bin/axlisten ]]; then
  AXLISTEN_BIN=/usr/bin/axlisten
elif [[ -x /usr/bin/listen ]]; then
  AXLISTEN_BIN=/usr/bin/listen
fi
if [[ -n "$AXLISTEN_BIN" ]]; then
  log "==> Setting setuid on $AXLISTEN_BIN so Linpac can monitor as $REAL_USER"
  run_root chmod u+s "$AXLISTEN_BIN"
  if [[ "$AXLISTEN_BIN" == "/usr/bin/axlisten" ]]; then
    run_root ln -sfn /usr/bin/axlisten /usr/local/bin/listen
  fi
fi

AXPORTS=/etc/ax25/axports
log "==> Writing $AXPORTS"
AXPORTS_BODY=$(cat <<EOF
# name  callsign     speed  paclen  window  description
$AX25_PORT   $MYCALL   19200  255     2       2m 1200 packet TM-D700
EOF
)
TMP_AX="$(mktemp)"
if [[ -f "$AXPORTS" ]]; then
  grep -v "^$AX25_PORT[[:space:]]" "$AXPORTS" | grep -v '^[[:space:]]*$' >"$TMP_AX" || true
fi
printf '%s\n' "$AXPORTS_BODY" >>"$TMP_AX"
run_root cp "$TMP_AX" "$AXPORTS"
rm -f "$TMP_AX"
run_root chmod 644 "$AXPORTS"

run_user mkdir -p "$SRC_DIR"

detect_audio_device() {
  local line card
  if command -v aplay >/dev/null; then
    line="$(aplay -l 2>/dev/null | grep -iE 'USB|Digirig|Device|C-Media|PnP' | head -n1 || true)"
    if [[ -n "$line" && "$line" =~ card[[:space:]]+([0-9]+): ]]; then
      card="${BASH_REMATCH[1]}"
      printf 'plughw:%s,0' "$card"
      return 0
    fi
    # Prefer any non-HDMI / non-vc4 card
    line="$(aplay -l 2>/dev/null | grep -i '^card' | grep -viE 'HDMI|vc4|bcm2835|Headphones' | head -n1 || true)"
    if [[ -n "$line" && "$line" =~ card[[:space:]]+([0-9]+): ]]; then
      printf 'plughw:%s,0' "${BASH_REMATCH[1]}"
      return 0
    fi
  fi
  printf 'plughw:1,0'
}

detect_ptt_device() {
  local id
  if [[ -d /dev/serial/by-id ]]; then
    id="$(ls /dev/serial/by-id 2>/dev/null | grep -iE 'Silicon_Labs|CP210|Digirig' | head -n1 || true)"
    if [[ -n "$id" ]]; then
      printf '/dev/serial/by-id/%s' "$id"
      return 0
    fi
  fi
  if [[ -e /dev/ttyUSB0 ]]; then
    printf '/dev/ttyUSB0'
    return 0
  fi
  printf '/dev/ttyUSB0'
}

ADEVICE="$(detect_audio_device)"
PTT_DEV="$(detect_ptt_device)"
log "==> Detected ADEVICE=$ADEVICE  PTT=$PTT_DEV"
log "    Plug in the DigiRig before the first start if these look wrong, then edit $DIREWOLF_CONF"

write_direwolf_conf() {
  local dest="$1"
  cat >"$dest" <<EOF
# Generated by $SCRIPT_NAME on $(date -Is)
# Edit ADEVICE / PTT if the DigiRig was not plugged in during install.
# Confirm with: aplay -l    and    ls -l /dev/serial/by-id

ADEVICE  $ADEVICE
ACHANNELS 1

CHANNEL 0
MYCALL $MYCALL
MODEM 1200
PTT $PTT_DEV RTS

# Timing for a mobile FM radio (values are 10 ms units)
DWAIT 0
TXDELAY 30
TXTAIL 10

AGWPORT 8000
KISSPORT 8001
EOF
}

if [[ -f "$DIREWOLF_CONF" ]]; then
  log "==> Backing up existing $DIREWOLF_CONF"
  run_user cp "$DIREWOLF_CONF" "$DIREWOLF_CONF.bak.$(date +%Y%m%d%H%M%S)"
fi
TMPCONF="$(mktemp)"
write_direwolf_conf "$TMPCONF"
if [[ "$(id -u)" -eq 0 ]]; then
  cp "$TMPCONF" "$DIREWOLF_CONF"
  chown "$REAL_USER":"$REAL_USER" "$DIREWOLF_CONF"
else
  cp "$TMPCONF" "$DIREWOLF_CONF"
fi
rm -f "$TMPCONF"
log "==> Wrote $DIREWOLF_CONF"

need_build_direwolf() {
  if [[ "$FORCE_REBUILD" -eq 1 ]]; then return 0; fi
  if command -v direwolf >/dev/null 2>&1; then return 1; fi
  return 0
}

fetch_direwolf_source() {
  local dest="$SRC_DIR/direwolf"
  local tar="$SRC_DIR/direwolf-src.tar.gz"
  local attempt
  run_user mkdir -p "$SRC_DIR"
  export GIT_TERMINAL_PROMPT=0

  if [[ -d "$dest/.git" ]]; then
    log "Updating existing Direwolf git clone"
    run_user git -C "$dest" pull --ff-only || true
    return 0
  fi

  # A failed clone often leaves a half-written directory that blocks retry.
  if [[ -e "$dest" ]]; then
    log "Removing incomplete $dest from a previous failed clone"
    run_user rm -rf "$dest"
  fi

  for attempt in 1 2 3; do
    log "Direwolf git clone attempt $attempt/3: $DIREWOLF_GIT"
    if run_user env GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$DIREWOLF_GIT" "$dest"; then
      return 0
    fi
    run_user rm -rf "$dest"
    sleep $((attempt * 3))
  done

  log "Git clone failed. Downloading Direwolf source tarball instead."
  run_user rm -f "$tar"
  local tarball_ok=0
  local url
  for url in \
    "https://github.com/wb2osz/direwolf/archive/refs/heads/master.tar.gz" \
    "https://github.com/wb2osz/direwolf/archive/refs/heads/dev.tar.gz" \
    "https://github.com/wb2osz/direwolf/archive/refs/heads/main.tar.gz"
  do
    log "Trying $url"
    if run_user curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$tar" "$url"; then
      tarball_ok=1
      break
    fi
  done
  if [[ "$tarball_ok" -eq 1 ]]; then
    run_user bash -c "
      set -e
      cd '$SRC_DIR'
      tar xzf '$tar'
      rm -rf direwolf
      dir=\$(printf '%s\n' direwolf-* | head -n1)
      mv \"\$dir\" direwolf
    "
    return 0
  fi

  log "Tarball download failed. Installing packaged direwolf from apt (older, but usable)."
  run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y direwolf
  return 2
}

if [[ "$SKIP_DIREWOLF" -eq 0 ]] && need_build_direwolf; then
  log "==> Building Direwolf from source (this can take several minutes)"
  dw_fetch=0
  fetch_direwolf_source && dw_fetch=0 || dw_fetch=$?
  if [[ "$dw_fetch" -eq 0 ]]; then
    as_user_bash "cd '$SRC_DIR/direwolf' && rm -rf build && mkdir build && cd build && cmake .. && make -j\$(nproc)"
    run_root make -C "$SRC_DIR/direwolf/build" install
  elif [[ "$dw_fetch" -eq 2 ]]; then
    log "Using apt direwolf; skip source build"
  else
    die "Could not get Direwolf source. On the Pi run: ping -c 2 github.com   and   curl -I https://github.com"
  fi
  log "==> Direwolf installed: $(command -v direwolf || echo /usr/local/bin/direwolf)"
elif [[ "$SKIP_DIREWOLF" -eq 1 ]]; then
  log "==> Skipping Direwolf build"
else
  log "==> Direwolf already present: $(command -v direwolf)"
fi

need_build_linpac() {
  if [[ "$FORCE_REBUILD" -eq 1 ]]; then return 0; fi
  if command -v linpac >/dev/null 2>&1; then return 1; fi
  return 0
}

if [[ "$SKIP_LINPAC" -eq 0 ]] && need_build_linpac; then
  log "==> Building Linpac from source (this can take several minutes)"
  as_user_bash "
    set -e
    mkdir -p '$SRC_DIR'
    cd '$SRC_DIR'
    if [[ ! -d linpac/.git ]]; then
      git clone '$LINPAC_GIT_PRIMARY' linpac || git clone '$LINPAC_GIT_FALLBACK' linpac
    else
      git -C linpac pull --ff-only || true
    fi
    cd linpac
    git checkout develop 2>/dev/null || git checkout master 2>/dev/null || true
    if [[ ! -f configure ]]; then
      if ! autoreconf --install; then
        libtoolize || true
        autoreconf --install
      fi
    fi
    ./configure --prefix=/usr
    make -j\$(nproc)
  "
  run_root make -C "$SRC_DIR/linpac" install
  log "==> Linpac installed: $(command -v linpac || echo /usr/bin/linpac)"
elif [[ "$SKIP_LINPAC" -eq 1 ]]; then
  log "==> Skipping Linpac build"
else
  log "==> Linpac already present: $(command -v linpac)"
fi

write_start_script() {
  cat <<EOF
#!/bin/bash
# Start Direwolf + AX.25 for Linpac. Run as $REAL_USER, keep this SSH session open
# or use tmux/screen. Then in another SSH session run: linpac
set -euo pipefail
CALL="$MYCALL"
PORT="$AX25_PORT"
CONF="\$HOME/direwolf.conf"
LOG="/tmp/direwolf.log"

if [[ "\$(id -u)" -eq 0 ]]; then
  echo "Do not start packet as root. Run: \$HOME/start-packet.sh"
  exit 1
fi

if [[ ! -f "\$CONF" ]]; then
  echo "Missing \$CONF"
  exit 1
fi

if pgrep -x direwolf >/dev/null; then
  echo "Direwolf is already running."
else
  echo "Starting Direwolf..."
  nohup direwolf -t 0 -c "\$CONF" -p >>"\$LOG" 2>&1 &
  echo \$! >/tmp/direwolf.pid
  sleep 3
fi

if [[ ! -e /tmp/kisstnc ]]; then
  echo "Direwolf did not create /tmp/kisstnc. Last log lines:"
  tail -n 40 "\$LOG" || true
  echo "Trying socat KISS TCP 8001 instead..."
  pkill -x socat 2>/dev/null || true
  socat pty,raw,echo=0,link=/tmp/kisstnc tcp:127.0.0.1:8001 &
  sleep 1
fi

if [[ ! -e /tmp/kisstnc ]]; then
  echo "Still no /tmp/kisstnc. See \$LOG"
  exit 1
fi

KISS_DEV="/tmp/kisstnc"
if [[ -L /tmp/kisstnc ]]; then
  KISS_DEV="\$(readlink -f /tmp/kisstnc)"
fi

if ip link show ax0 >/dev/null 2>&1; then
  echo "AX.25 interface ax0 already exists."
else
  echo "Attaching AX.25 port \$PORT to \$KISS_DEV"
  sudo kissattach "\$KISS_DEV" "\$PORT" || sudo kissattach -l "\$KISS_DEV" "\$PORT"
  sudo kissparms -p "\$PORT" -t 300 -l 10 -s 100 -r 64 || true
fi

echo "Ready. Callsign \$CALL  port \$PORT"
echo "In this or another SSH session run:  linpac"
echo "Direwolf log: \$LOG"
echo "Stop with: \$HOME/stop-packet.sh"
EOF
}

write_stop_script() {
  cat <<EOF
#!/bin/bash
set -euo pipefail
echo "Stopping packet stack..."
sudo killall kissattach 2>/dev/null || true
pkill -x linpac 2>/dev/null || true
pkill -x socat 2>/dev/null || true
if [[ -f /tmp/direwolf.pid ]]; then
  kill "\$(cat /tmp/direwolf.pid)" 2>/dev/null || true
  rm -f /tmp/direwolf.pid
fi
pkill -x direwolf 2>/dev/null || true
sudo ip link set ax0 down 2>/dev/null || true
echo "Stopped."
EOF
}

TMPSTART="$(mktemp)"
TMPSTOP="$(mktemp)"
write_start_script >"$TMPSTART"
write_stop_script >"$TMPSTOP"
if [[ "$(id -u)" -eq 0 ]]; then
  cp "$TMPSTART" "$START_SCRIPT"
  cp "$TMPSTOP" "$STOP_SCRIPT"
  chown "$REAL_USER":"$REAL_USER" "$START_SCRIPT" "$STOP_SCRIPT"
else
  cp "$TMPSTART" "$START_SCRIPT"
  cp "$TMPSTOP" "$STOP_SCRIPT"
fi
chmod 755 "$START_SCRIPT" "$STOP_SCRIPT"
rm -f "$TMPSTART" "$TMPSTOP"
# The generated start/stop scripts are written on the Pi; keep copies in $HOME.

log ""
log "============================================================"
log "Install finished."
log "============================================================"
log "Installed / configured:"
log "  Direwolf:     $(command -v direwolf 2>/dev/null || echo 'not in PATH yet')"
log "  Linpac:       $(command -v linpac 2>/dev/null || echo 'not in PATH yet')"
log "  axports:      $AXPORTS  ($AX25_PORT $MYCALL)"
log "  direwolf.conf:$DIREWOLF_CONF"
log "  start:        $START_SCRIPT"
log "  stop:         $STOP_SCRIPT"
log ""
log "IMPORTANT — groups: $REAL_USER was added to dialout and audio."
log "  Disconnect SSH and log back in before the first start so group membership applies."
log ""
log "Next (after reconnecting SSH):"
log "  1. Plug in DigiRig. Confirm devices:"
log "       aplay -l"
log "       ls -l /dev/serial/by-id"
log "     Edit $DIREWOLF_CONF if ADEVICE or PTT is wrong."
log "  2. Set analog FM simplex on the TM-D700 (built-in TNC OFF, Menu 1-9-6 = 1200)."
log "  3. Start the TNC/AX.25 stack:"
log "       $START_SCRIPT"
log "  4. In another SSH session:"
log "       linpac"
log "     First-run port name must be: $AX25_PORT"
log "     Connect with:  :c OTHERCALL-1"
log ""
log "Use ssh -t so linpac's full-screen terminal works:"
log "  ssh -t $REAL_USER@PI_ADDRESS"
log "============================================================"

if [[ "$(id -u)" -eq 0 ]]; then
  chown "$REAL_USER":"$REAL_USER" "$LOG_FILE" "$DIREWOLF_CONF" "$START_SCRIPT" "$STOP_SCRIPT" 2>/dev/null || true
fi
