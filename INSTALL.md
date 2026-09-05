# Linpac + DigiRig + Kenwood TM-D700 on a Raspberry Pi

Keyboard-to-keyboard packet radio (AX.25 connected chat) using a DigiRig as the soundcard TNC and a Kenwood **TM-D700** (D700A/E) as the analog FM radio.

You need a valid amateur radio license and must identify as required in your country.

## How the pieces fit together

```
Keyboard  →  Linpac  →  Linux AX.25  →  Direwolf (software TNC)
                                              ↓
                                    DigiRig USB sound + RTS PTT
                                              ↓
                              Kenwood TM-D700 analog FM (built-in TNC OFF)
                                              ↓
                                    RF to the other station
```

Linpac is only a terminal. It does not talk to the DigiRig by itself. Direwolf turns the DigiRig into a 1200-baud AFSK modem. Linux AX.25 is the packet protocol stack Linpac uses.

The TM-D700 also has a **built-in TNC** and a **DB-9 COM** port on the control head. This procedure does **not** use those. Leave the built-in TNC **off** and plug the DigiRig into the **6-pin DATA** jack on the radio body (external TNC / soundcard audio).

| Software | Role |
|---|---|
| Raspberry Pi OS | Host OS |
| `alsa-utils` | Identify and set DigiRig audio levels |
| Direwolf | Software TNC / 1200-baud AFSK modem |
| `libax25`, `ax25-tools`, `ax25-apps` | Kernel AX.25 stack, `kissattach`, `axcall`, `axlisten` |
| Linpac | Keyboard-to-keyboard packet terminal |
| `socat` (optional) | More reliable KISS pty than Direwolf `-p` |

Do **not** use the D700’s TNC PKT / TNC APRS modes, VARA, or Winlink for this procedure. Linpac here is analog 1200-baud AX.25 packet on FM via Direwolf.

---

## 1. Hardware

- Raspberry Pi 3B+, 4, or 5 with power supply, HDMI or SSH, and keyboard
- DigiRig **Mobile** (recommended: Silicon Labs CP210x serial port for RTS PTT)
- DigiRig **MiniDin6 audio/PTT cable** (Kenwood 6-pin DATA jack; DigiRig lists this for TM-D700)
- USB-C cable: DigiRig to Pi
- Kenwood **TM-D700A / TM-D700E** (TH-D700 handheld uses different connectors)
- Antenna and radio power

If you have a **DigiRig Lite** (no COM port), PTT is VOX on the right audio channel. See the Lite note at the end of section 6.

Fallback if you do not have a MiniDin6 cable: DigiRig **Kenwood RJ-45** mic cable plus a speaker pigtail. DATA jack is preferred (fixed RX level, mic stays unused).

### Cable connections (TM-D700 + DigiRig MiniDin6)

1. Do **not** use the **DB-9 COM** connector on the control head. That port is for the built-in TNC / GPS / PC, not the DigiRig.
2. Plug the DigiRig MiniDin6 into the **DATA** jack on the **main unit** (radio body), Kenwood PG-5A style 6-pin mini-DIN.
3. Plug the 4-pin (TRRS) end into the DigiRig socket labeled **AUDIO**. Nothing goes into the DigiRig serial socket for this cable.
4. USB-C from DigiRig to a Pi USB port.
5. Power on the radio, then the Pi.

---

## 2. TM-D700 radio settings

Packet via DigiRig is **analog FM** with an **external** soundcard TNC. The radio’s own TNC must be off so it does not fight Direwolf.

| Setting | Value | How |
|---|---|---|
| Built-in TNC | **OFF** (no `TNC APRS`, no `TNC PKT` on the display) | Hold `[F]` until TNC appears, press `[TNC]`. Repeat until those labels are **blank** |
| External data speed | **1200 bps** | Menu **1–9–6** (DATA SPEED). This applies to an external TNC / DATA jack |
| Operating mode | **FM** (not narrow on the data band, especially TM-D700E) | Band mode FM |
| Duplex / offset | OFF (simplex) | No +/- shift |
| Tone / CTCSS | OFF unless your local packet channel uses CTCSS | |
| Cross-band repeat | **OFF** | Menu **1–7–6** |
| Dual watch / both bands busy | Off for packet | Operate on **one** band |
| TX power | **LOW** at first | Front panel power |
| Volume | About **50%** if you use a speaker cable; DATA-jack RX is a fixed level | `[VOL]` |
| Squelch | Fully open (counterclockwise) | Direwolf has its own DCD |
| Frequency | Local 2 m packet simplex on the **TX band** | For an external TNC, Menu 1–6–1 (DATA BAND) does not apply; use the band you are transmitting on |

Typical US 2 m packet simplex frequencies (confirm your local band plan): **145.010**, 145.030, 145.050, 145.070, 145.090 MHz. Many Winlink RMS stations use 145.670 — that is a different service; use a quiet simplex channel for keyboard chat.

Both stations must be on the **same frequency**, **FM**, **simplex**, and the same tone setting.

---

## 3. Raspberry Pi OS

The fastest path over SSH is the installer script (builds Direwolf and Linpac, writes configs). From the Pi:

```bash
curl -fsSL https://raw.githubusercontent.com/buryd/raspberry-Pi_Linpac_Direwolf_digirig_Icom4100/main/install-linpac-packet.sh -o install-linpac-packet.sh
chmod +x install-linpac-packet.sh
./install-linpac-packet.sh --callsign YOURCALL
```

Use current **Raspberry Pi OS** (Bookworm or later). 64-bit is fine if kernel and userland are both 64-bit. Do not mix a 64-bit kernel with 32-bit userland.

If you prefer to install by hand:

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

If the radio overdrives or PTT is flaky, **lower** playback, not raise it. DATA-jack TX audio is sensitive; start low.

---

## 5. Install Direwolf from source

The distro package is often older. Build current Direwolf. Clone into `~/src` so a failed attempt is easy to delete:

```bash
mkdir -p ~/src
cd ~/src
git clone --depth 1 https://github.com/wb2osz/direwolf.git
cd direwolf
mkdir build && cd build
cmake ..
make -j$(nproc)
sudo make install
make install-conf
```

`make install-conf` copies `direwolf.conf` into your home directory (`~/direwolf.conf`).

### If `git clone` fails

A failed clone often leaves a half-written `direwolf` folder. Remove it, then retry. `cd ~` is your home directory (`/home/YOURUSER`).

```bash
ping -c 2 github.com
mkdir -p ~/src
cd ~/src
rm -rf direwolf
git clone --depth 1 https://github.com/wb2osz/direwolf.git
```

If that folder was created in home instead of `~/src`:

```bash
cd ~
rm -rf direwolf
```

If clone still fails, skip git and download the source tarball:

```bash
cd ~/src
rm -rf direwolf
curl -fL --retry 3 -o direwolf.tar.gz https://github.com/wb2osz/direwolf/archive/refs/heads/master.tar.gz
tar xzf direwolf.tar.gz
mv direwolf-master direwolf
cd direwolf
mkdir build && cd build
cmake ..
make -j$(nproc)
sudo make install
```

Last resort (older packaged build):

```bash
sudo apt install -y direwolf
```

If `ping github.com` fails, the Pi cannot reach GitHub (DNS or firewall). Fix networking before cloning again.

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
radio   YOURCALL-1   19200  255     2       2m 1200 packet TM-D700
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

If `axcall` connects, Direwolf, DigiRig, TM-D700, and AX.25 are good; remaining issues are Linpac config.

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

1. Open squelch on the TM-D700. Direwolf’s underrun/level line should move (DATA-jack RX is a fixed level; if it stays at zero, check the MiniDin6 seating and Menu 1–9–6 = 1200).
2. Brief decode test on 144.390 APRS (US) or a known local packet channel. You should see decoded frames.
3. Return to your simplex chat frequency.
4. From Linpac F10 send an unproto. The DigiRig **PTT LED** should light and the TM-D700 should transmit.
5. A second receiver (HT) on the same frequency should hear the classic 1200-baud packet burst, not voice.
6. Adjust:

   | Symptom | Fix |
   |---|---|
   | Radio does not key; DigiRig LED off | Wrong `PTT` device, not in `dialout`, or Lite with no VOX |
   | DigiRig LED on, radio does not key | MiniDin6 not fully in **DATA** jack (not the DB-9 COM); built-in TNC still on |
   | Keys but nobody decodes you | Lower `alsamixer` playback; Menu 1–9–6 = 1200; TXDELAY 40 |
   | You never decode them | Confirm FM; squelch open; TNC OFF; 1200 bps DATA SPEED |
   | Retries / corrupted text | Too much TX audio (ALC/clipping); lower playback |
   | Constant transmit | Wrong PTT polarity or serial device; unplug USB and check `PTT ... RTS` |
   | Radio beacons APRS by itself | Built-in TNC is still in TNC APRS — turn TNC **off** |

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

### git clone of Direwolf failed

Remove the broken folder, then retry or use the tarball. Full steps are in [section 5](#5-install-direwolf-from-source).

```bash
cd ~/src
rm -rf direwolf
git clone --depth 1 https://github.com/wb2osz/direwolf.git
```

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

### Built-in TNC still on (`TNC PKT` or `TNC APRS` on the display)

Hold `[F]` then `[TNC]` until those labels are **blank**. Direwolf and the radio TNC cannot share the same audio path.

Do not plug the DigiRig into the control-head **DB-9 COM** port.

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

On the TM-D700:

- [ ] Built-in TNC **off** (no TNC PKT / TNC APRS)
- [ ] Menu 1–9–6 DATA SPEED **1200**
- [ ] MiniDin6 in the **DATA** jack on the radio body (not DB-9 COM)
- [ ] FM simplex, cross-band off, power LOW, squelch open

On the air:

- [ ] Second packet station (another Linpac/Direwolf, or Windows UZ7HO Soundmodem + EasyTerm) on the same frequency
- [ ] `:c OTHERCALL-1` then type without a colon

---

## References

- Direwolf: https://github.com/wb2osz/direwolf
- Linpac: https://sourceforge.net/projects/linpac/ and https://linpac.sourceforge.net/doc/manual.html
- DigiRig MiniDin6 audio/PTT cable: https://digirig.net/product/9600-baud-audio-cable/
- Kenwood TM-D700 instruction manual (external TNC / DATA jack, Menu 1–9–6)
- Raspberry Pi AX.25 + Direwolf overview: https://www.kevinhooke.com/2022/03/03/revisiting-packet-radio-on-a-raspberry-pi-with-direwolf-part-2-minimal-installation/
