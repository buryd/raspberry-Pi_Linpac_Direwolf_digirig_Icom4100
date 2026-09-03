# Linpac + DigiRig + Icom ID-4100 on a Raspberry Pi

Keyboard-to-keyboard packet radio (AX.25 connected chat) using a DigiRig as the soundcard TNC and an Icom ID-4100 as the analog FM radio.

This repository is **public**. Anyone can open the GitHub link below without logging in.

**Run the installer over SSH as a normal (non-root) user:** [SSH-INSTALL.md](./SSH-INSTALL.md)

**Word document:** [Linpac_DigiRig_ID-4100_Raspberry_Pi_Procedure.docx](./Linpac_DigiRig_ID-4100_Raspberry_Pi_Procedure.docx)

You need a valid amateur radio license and must identify as required in your country.

Do **not** run the whole install as root. Stay logged in as a normal Pi user and use `sudo` only for package install, `make install`, editing `/etc/ax25/axports`, and `kissattach`. Run `direwolf` and `linpac` as your normal user so configs land in your home directory.

## Install over SSH

On the Raspberry Pi (replace `YOURCALL` and the Pi address):

```bash
ssh -t USER@PI_ADDRESS
curl -fsSL https://raw.githubusercontent.com/buryd/raspberry-Pi_Linpac_Direwolf_digirig_Icom4100/main/install-linpac-packet.sh -o install-linpac-packet.sh
chmod +x install-linpac-packet.sh
./install-linpac-packet.sh --callsign YOURCALL
```

One-shot from your PC if the Pi user has passwordless `sudo`:

```bash
ssh -t USER@PI_ADDRESS 'curl -fsSL https://raw.githubusercontent.com/buryd/raspberry-Pi_Linpac_Direwolf_digirig_Icom4100/main/install-linpac-packet.sh | bash -s -- --callsign YOURCALL'
```

`ssh -t` allocates a terminal so `sudo` can ask for a password and so Linpac can use the full screen later.

The installer builds Direwolf and Linpac from source (several minutes), writes `~/direwolf.conf` and `/etc/ax25/axports`, and adds you to the `dialout` and `audio` groups. It does **not** start the radio stack. After it finishes, **disconnect SSH and log back in**, then:

```bash
./start-packet.sh          # or ~/start-packet.sh
# in a second SSH session:
ssh -t USER@PI_ADDRESS
linpac
```

Stop with `./stop-packet.sh`.

## How the pieces fit together

```
Keyboard  →  Linpac  →  Linux AX.25  →  Direwolf (software TNC)
                                              ↓
                                    DigiRig USB sound + RTS PTT
                                              ↓
                              Icom ID-4100 analog FM (not D-STAR)
                                              ↓
                                    RF to the other station
```

Linpac is only a terminal. It does not talk to the DigiRig by itself. Direwolf turns the DigiRig into a 1200-baud AFSK modem. Linux AX.25 is the packet protocol stack Linpac uses.

| Software | Role |
|---|---|
| Raspberry Pi OS | Host OS |
| `alsa-utils` | Identify and set DigiRig audio levels |
| Direwolf | Software TNC / 1200-baud AFSK modem |
| `libax25`, `ax25-tools`, `ax25-apps` | Kernel AX.25 stack, `kissattach`, `axcall`, `axlisten` |
| Linpac | Keyboard-to-keyboard packet terminal |
| `socat` (optional) | More reliable KISS pty than Direwolf `-p` |

Do **not** use D-STAR (DV), VARA, or Winlink for this procedure. Those are different modes. Linpac is analog 1200-baud AX.25 packet on FM.

---

## 1. Hardware

- Raspberry Pi 3B+, 4, or 5 with power supply, HDMI or SSH, and keyboard
- DigiRig **Mobile** (recommended: Silicon Labs CP210x serial port for RTS PTT)
- DigiRig **ICOM RJ-45 cable** (front mic + rear speaker)
- USB-C cable: DigiRig to Pi
- Icom **ID-4100A / ID-4100E**
- Antenna and radio power

If you have a **DigiRig Lite** (no COM port), PTT is VOX on the right audio channel. See the Lite note at the end of section 6.

### Cable connections (ID-4100 + DigiRig ICOM RJ-45)

1. Unplug the hand mic from the front of the ID-4100.
2. Plug the cable **RJ-45** into the front **mic jack**.
3. Plug the cable **3.5 mm TRS** into the rear **speaker** jack (the larger jack). Leave the small 2.5 mm **DATA** jack empty. That DATA jack is for D-STAR cloning/GPS, not analog packet with this cable.
4. Plug the 4-pin (TRRS) end into the DigiRig socket labeled **AUDIO**. Nothing goes into the DigiRig serial socket when using this Icom cable.
5. USB-C from DigiRig to a Pi USB port.
6. Power on the radio, then the Pi.

---

## 2. ID-4100 radio settings

Packet via DigiRig is **analog FM**, not D-STAR.

| Setting | Value | How |
|---|---|---|
| Operating mode | **FM** (not DV, not FM-N) | Push `[MODE]` until FM |
| D-STAR / DR | Off | Do not use the DR screen |
| Duplex | OFF (simplex) | Quick menu / DUP |
| Tone / TSQL / DTCS | OFF unless your local packet channel uses CTCSS | `[QUICK]` → TONE |
| GPS TX Mode | **OFF** | `[MENU]` → GPS → GPS TX Mode → OFF |
| PTT Lock | **OFF** | `[MENU]` → Function → PTT Lock |
| MIC Gain | **2** (default; later 1–3 if overdriven) | `[MENU]` → Function → MIC Gain |
| PRIO / priority watch | **OFF** | `[QUICK]` → PRIO Watch OFF |
| TX power | **LOW** at first | Front panel power |
| Volume | About **50%** (10–12 o’clock) | `[VOL]` — this is the audio DigiRig hears |
| Squelch | Fully open (counterclockwise) | Direwolf has its own DCD; closed squelch can hide packet audio |
| Frequency | Local 2 m packet simplex | `[V/M]` to VFO, then set frequency |

Typical US 2 m packet simplex frequencies (confirm your local band plan): **145.010**, 145.030, 145.050, 145.070, 145.090 MHz. Many Winlink RMS stations use 145.670 — that is a different service; use a quiet simplex channel for keyboard chat.

Both stations must be on the **same frequency**, **FM**, **simplex**, and the same tone setting.

---

## 3. Raspberry Pi OS

Use current **Raspberry Pi OS** (Bookworm or later). 64-bit is fine if kernel and userland are both 64-bit. Do not mix a 64-bit kernel with 32-bit userland.

```bash
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

After reboot, install packages:

```bash
sudo apt install -y \
  git cmake build-essential \
  libasound2-dev libudev-dev \
  alsa-utils usbutils \
  libax25 ax25-apps ax25-tools \
  libncurses-dev automake autoconf libtool \
  socat
```

Add your user to the serial and audio groups (replace `pi` if your username differs):

```bash
sudo usermod -aG dialout,audio $USER
```

Log out and back in (or reboot) so group membership takes effect.

---

## 4. Confirm the DigiRig on the Pi

Plug the DigiRig in, then:

```bash
lsusb
aplay -l
arecord -l
ls -l /dev/serial/by-id
```

You should see something like:

- USB audio: `C-Media` / `USB PnP Sound Device` / `Device`
- Serial (Mobile only): `Silicon Labs CP210x` → `/dev/ttyUSB0`

Note the **card number** from `aplay -l`. Example:

```
card 2: Device [USB PnP Sound Device], device 0: USB Audio [USB Audio]
```

That card is `plughw:2,0` (or by name `plughw:Device,0`).

Also note the serial path. Prefer the stable by-id name:

```
/dev/serial/by-id/usb-Silicon_Labs_CP2102N_USB_to_UART_Bridge_Controller_........-if00-port0
```

If you only have `/dev/ttyUSB0`, that is fine as long as nothing else is plugged in.

Set levels (replace `2` with your card number):

```bash
alsamixer -c 2
```

- F6 to select the DigiRig card
- Playback (PCM / Speaker): start around **40–60%**
- Capture (Mic): around **70%**, not muted
- Disable Auto-Gain if it appears

Icom mic inputs are sensitive. If the radio overdrives or PTT is flaky, **lower** playback, not raise it.

---

## 5. Install Direwolf from source

The distro package is often older. Build current Direwolf:

```bash
cd ~
git clone https://github.com/wb2osz/direwolf.git
cd direwolf
mkdir build && cd build
cmake ..
make -j$(nproc)
sudo make install
make install-conf
```

`make install-conf` copies `direwolf.conf` into your home directory (`~/direwolf.conf`).

---

## 6. Configure Direwolf

Edit `~/direwolf.conf`. Replace `YOURCALL`, the sound card, and the serial path.

```text
ADEVICE  plughw:2,0
ACHANNELS 1

CHANNEL 0
MYCALL YOURCALL-1
MODEM 1200
PTT /dev/ttyUSB0 RTS

# Timing for a mobile FM radio (values are 10 ms units)
DWAIT 0
TXDELAY 30
TXTAIL 10

AGWPORT 8000
KISSPORT 8001
```

Notes:

- `ADEVICE` must match the DigiRig card from `aplay -l`. Using the name is more stable: `ADEVICE plughw:Device,0`
- DigiRig Mobile PTT is **RTS**, not DTR
- `YOURCALL-1` is the on-air packet identity. Use a unique SSID on each radio if both ends share one callsign (example: `N0CALL-1` and `N0CALL-2`)

### DigiRig Lite (no serial port)

Omit the `PTT` line and let the Lite’s VOX circuit key the radio from the right audio channel, **or** keep levels conservative so VOX is reliable. Confirm the Lite LED keys when Direwolf transmits. If it never keys, the Lite may need the right-channel PTT path; in that case use DigiRig Mobile instead.

Test Direwolf by itself (leave this terminal running):

```bash
direwolf -t 0
```

`-t 0` turns off color (cleaner over SSH). You should see the sound card open and, when the radio hears packet or noise, an audio level meter. Tune a busy APRS channel (US: 144.390 FM) briefly to confirm **decode**. Then go back to your packet simplex frequency.

PTT test: in another terminal, while Direwolf is running with default APRS beacon disabled, you can send a keyboard test later from Linpac. You can also watch the DigiRig PTT LED when a packet goes out.

Comment out or leave `PBEACON` unused so you do not beacon APRS on a packet chat frequency.

---

## 7. Configure Linux AX.25

Edit `/etc/ax25/axports` (create the file if missing). **No blank lines** in the file.

```bash
sudo nano /etc/ax25/axports
```

```text
# name  callsign     speed  paclen  window  description
radio   YOURCALL-1   19200  255     2       2m 1200 packet ID-4100
```

- `radio` is the **port name** Linpac will use
- `callsign` should match Direwolf `MYCALL`
- `speed` is the KISS serial rate to Direwolf, not the on-air baud. 19200 is fine
- `paclen 255` and `window 2` are reasonable for VHF simplex

Make `axlisten` usable from a normal user (Debian names it `axlisten`; Linpac often looks for `listen`):

```bash
sudo chmod u+s /usr/bin/axlisten
sudo ln -sf /usr/bin/axlisten /usr/local/bin/listen
sudo mkdir -p /var/ax25/mail /var/ax25/mheard
sudo chown "$USER" /var/ax25/mail
```

---

## 8. Install Linpac from source

Do not use the old Raspbian `linpac` package if it is offered. Build the `develop` branch.

```bash
cd ~
git clone https://git.code.sf.net/p/linpac/linpac linpac
cd linpac
git checkout develop
sudo apt install -y automake autoconf libtool libncurses-dev
autoreconf --install
./configure --prefix=/usr
make -j$(nproc)
sudo make install
```

If `autoreconf` fails with an undefined `LIBTOOL` error:

```bash
libtoolize
autoreconf --install
```

Then configure/make/install again.

Confirm:

```bash
which linpac
linpac --help || true
```

---

## 9. Start the stack (order matters)

Open **three** terminals (or use `tmux` / `screen`).

### Terminal 1 — Direwolf as a KISS TNC

```bash
direwolf -t 0 -p
```

Wait until you see:

```text
Ready to accept KISS client application on port 8001 ...
Virtual KISS TNC is available on /dev/pts/N
Created symlink /tmp/kisstnc -> /dev/pts/N
```

Leave this running.

If `-p` later causes `kissattach` “error setting line discipline”, use the socat method in the troubleshooting section instead.

### Terminal 2 — Attach AX.25

```bash
sudo kissattach /tmp/kisstnc radio
sudo kissparms -p radio -t 300 -l 10 -s 100 -r 64
```

Success looks like:

```text
AX.25 port radio bound to device ax0
```

Optional monitor in this or another terminal:

```bash
sudo axlisten -a -c -t
```

### Terminal 3 — Linpac

```bash
linpac
```

First run creates `~/LinPac/` and asks:

| Prompt | What to enter |
|---|---|
| Callsign without SSID | `YOURCALL` |
| Home BBS | `YOURCALL-1` (your own packet SSID is fine if you have no BBS) |
| Port name | `radio` (must match `/etc/ax25/axports`) |
| Digipeaters | Enter (none) |
| Hierarchical address | Your region, e.g. `#NM.USA.NOAM` — or a placeholder if unsure |

If the wizard already ran and you need to redo it:

```bash
rm -rf ~/LinPac
linpac
```

---

## 10. Keyboard-to-keyboard operation

Linpac commands start with `:`. Anything else is sent to the connected station.

### Direct connected chat (true keyboard-to-keyboard)

Both stations on the same simplex FM frequency, both stacks running.

On station A:

```text
:c OTHERCALL-1
```

Wait for `CONNECTED to OTHERCALL-1`. Then type normally (no colon) and press Enter. Each line is a packet.

Disconnect:

```text
:d
```

### Incoming connect

Leave Linpac running on a channel (F1–F8). When the other station connects to `YOURCALL-1`, the channel shows connected and you type the same way.

Edit `~/LinPac/macro/ctext.mac` if you want an automatic greeting, for example:

```text
Hello from YOURCALL-1, type away.
```

### Unproto / CQ (no connection)

F10 is the unproto channel. Or:

```text
:unsrc YOURCALL-1
:undest CQ
:unproto Anyone on frequency? de YOURCALL-1
```

The other station will see UI frames in the monitor. Unproto is broadcast; connected `:c` is the reliable keyboard-to-keyboard QSO.

### Useful keys

| Key | Action |
|---|---|
| F1–F8 | QSO channels |
| F10 | Unproto / monitor send |
| Alt+X | Quit Linpac |
| `:c CALL` | Connect |
| `:d` | Disconnect |
| `:port radio` | Select AX.25 port |
| `:help` | Help |

### Quick test without Linpac

```bash
axcall radio OTHERCALL-1
```

If `axcall` connects, Direwolf, DigiRig, radio, and AX.25 are good; remaining issues are Linpac config.

---

## 11. Optional start script

Save as `~/start-packet.sh` and `chmod +x ~/start-packet.sh`.

```bash
#!/bin/bash
set -e
cd "$HOME"

# Start Direwolf in the background with KISS pty
direwolf -t 0 -p > /tmp/direwolf.log 2>&1 &
echo $! > /tmp/direwolf.pid
sleep 3

if [ ! -e /tmp/kisstnc ]; then
  echo "Direwolf did not create /tmp/kisstnc — see /tmp/direwolf.log"
  exit 1
fi

sudo kissattach /tmp/kisstnc radio
sudo kissparms -p radio -t 300 -l 10 -s 100 -r 64

echo "AX.25 up. Run: linpac"
echo "Direwolf log: /tmp/direwolf.log"
```

Stop:

```bash
sudo killall kissattach linpac 2>/dev/null || true
kill "$(cat /tmp/direwolf.pid)" 2>/dev/null || true
```

---

## 12. Audio and PTT checkout

1. Open squelch on the ID-4100. Direwolf’s underrun/level line should move.
2. Brief decode test on 144.390 APRS (US) or a known local packet channel. You should see decoded frames.
3. Return to your simplex chat frequency.
4. From Linpac F10 send an unproto. The DigiRig **PTT LED** should light and the ID-4100 should transmit.
5. A second receiver (HT) on the same frequency should hear the classic 1200-baud packet burst, not voice, not D-STAR.
6. Adjust:

   | Symptom | Fix |
   |---|---|
   | Radio does not key; DigiRig LED off | Wrong `PTT` device, not in `dialout`, or Lite with no VOX |
   | DigiRig LED on, radio does not key | Cable not fully in mic jack; PTT Lock ON; wrong Icom cable |
   | Keys but nobody decodes you | Lower `alsamixer` playback; MIC Gain 1–2; TXDELAY 40 |
   | You never decode them | Raise radio volume; raise capture; squelch open; confirm FM not DV |
   | Retries / corrupted text | Too much TX audio (ALC/clipping); lower playback |
   | Constant transmit | Wrong PTT polarity or serial device; unplug USB and check `PTT ... RTS` |

Direwolf prints `Audio level for PLUGHW:...` — for received packets, mid-scale (around 50) is healthy. Pegged 100 is too loud.

---

## 13. Troubleshooting

### kissattach: error setting line discipline

Use TCP KISS + socat instead of `direwolf -p`.

In `~/direwolf.conf` you already have `KISSPORT 8001`. Start Direwolf **without** `-p`:

```bash
direwolf -t 0
```

Then:

```bash
socat pty,raw,echo=0,link=/tmp/kisstnc tcp:127.0.0.1:8001 &
sleep 1
sudo kissattach /tmp/kisstnc radio
```

If `kissattach` needs the real pty:

```bash
sudo kissattach -l "$(readlink -f /tmp/kisstnc)" radio
```

### No sound card / card number changes after reboot

Use the ALSA name in Direwolf:

```text
ADEVICE plughw:Device,0
```

List names with `aplay -l`.

### Permission denied on `/dev/ttyUSB0`

```bash
groups   # must include dialout
sudo usermod -aG dialout $USER
```

Then log out and back in.

### Linpac monitor empty / crashes on listen

```bash
sudo chmod u+s /usr/bin/axlisten
ls -l /usr/local/bin/listen
```

### Connected but no text, or immediate disconnect

- Same frequency and FM on both ends
- Different SSIDs (`-1` vs `-2`) if same callsign
- `axports` callsign matches Direwolf `MYCALL`
- Linpac port name is `radio`

### ID-4100 stays in D-STAR

Push `[MODE]` to **FM**. GPS TX Mode OFF. Do not use DR.

---

## 14. What you should have installed (checklist)

On the Pi:

- [ ] Raspberry Pi OS updated
- [ ] `alsa-utils`, `usbutils`
- [ ] Direwolf (built from source)
- [ ] `libax25`, `ax25-apps`, `ax25-tools`
- [ ] `socat` (backup KISS path)
- [ ] Linpac (built from `develop`)
- [ ] User in `dialout` and `audio`
- [ ] `~/direwolf.conf` pointing at DigiRig audio + RTS PTT
- [ ] `/etc/ax25/axports` port named `radio`

On the ID-4100:

- [ ] FM simplex, GPS TX off, PTT Lock off
- [ ] Mic + speaker cable, DATA jack unused
- [ ] Volume ~50%, squelch open, power LOW

On the air:

- [ ] Second packet station (another Linpac/Direwolf, or Windows UZ7HO Soundmodem + EasyTerm) on the same frequency
- [ ] `:c OTHERCALL-1` then type without a colon

---

## References

- Direwolf: https://github.com/wb2osz/direwolf
- Linpac: https://sourceforge.net/projects/linpac/ and https://linpac.sourceforge.net/doc/manual.html
- DigiRig Icom RJ-45 cable: https://digirig.net/product/icom-rj45-cable/
- ID-4100 + DigiRig cabling (mic + speaker): Delaware County ARES Winlink/VARA write-up uses the same physical hookup
- Raspberry Pi AX.25 + Direwolf overview: https://www.kevinhooke.com/2022/03/03/revisiting-packet-radio-on-a-raspberry-pi-with-direwolf-part-2-minimal-installation/
