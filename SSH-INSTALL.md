# Run the installer on the Pi over SSH (non-root)

Use a **normal Raspberry Pi user** (for example `pi` or the account you created).  
Do **not** SSH as `root` and do **not** run `sudo su` or `sudo -i` first.

Replace:

- `YOURUSER` — Pi login name  
- `PI_ADDRESS` — hostname or IP (example: `192.168.1.50`)  
- `YOURCALL` — amateur callsign with **no SSID** (example: `KC4JIR`)

The script uses SSID `-1` unless you add `--ssid N`. Packet identity becomes `YOURCALL-1`.

---

## 1. Connect with a terminal

`-t` is required if `sudo` asks for a password, and later for Linpac’s full-screen display.

```bash
ssh -t YOURUSER@PI_ADDRESS
```

If this logs you in as `root`, stop. Use your normal username instead.

---

## 2. Download the installer (still as YOURUSER)

```bash
curl -fsSL https://raw.githubusercontent.com/buryd/raspberry-Pi_Linpac_Direwolf_digirig_Icom4100/main/install-linpac-packet.sh -o install-linpac-packet.sh
chmod +x install-linpac-packet.sh
```

---

## 3. Run the installer (not as root)

The script calls `sudo` only for `apt`, `make install`, group membership, and files under `/etc` and `/usr`.

```bash
./install-linpac-packet.sh --callsign YOURCALL
```

Enter your sudo password if prompted. Building Direwolf and Linpac from source takes several minutes.

If you see *Do not run this as a root login*, you are `root`. Log out and SSH in as `YOURUSER`.

---

## 4. Disconnect SSH and log back in

This is required so `dialout` and `audio` group membership take effect.

```bash
exit
ssh -t YOURUSER@PI_ADDRESS
```

---

## 5. Start the packet stack

Plug in the DigiRig first (if it was not already connected).

```bash
~/start-packet.sh
```

Leave this session running, or confirm it printed that AX.25 is ready.

---

## 6. Start Linpac in a second SSH window

```bash
ssh -t YOURUSER@PI_ADDRESS
linpac
```

First-run **port name** must be `radio`.  
Connect to the other station with:

```text
:c OTHERCALL-1
```

Then type without a colon. Disconnect with `:d`. Quit Linpac with **Alt+X**.

---

## 7. Stop

```bash
~/stop-packet.sh
```

---

## Optional: one line from your PC

Only if the Pi user can run `sudo` **without** a password:

```bash
ssh -t YOURUSER@PI_ADDRESS 'curl -fsSL https://raw.githubusercontent.com/buryd/raspberry-Pi_Linpac_Direwolf_digirig_Icom4100/main/install-linpac-packet.sh | bash -s -- --callsign YOURCALL'
```

Then still log out and back in before `~/start-packet.sh`.

---

## Checks if something fails

| Message / symptom | What to do |
|---|---|
| Permission denied (publickey,password) | Wrong user/host, or SSH not enabled on the Pi |
| `sudo: a terminal is required` | Use `ssh -t` |
| Installer refuses to run as root | SSH as `YOURUSER`, not `root` |
| `direwolf` cannot open `/dev/ttyUSB0` | You skipped the log-out / log-back-in step |
| `linpac` screen is garbled | Use `ssh -t` |
| `git clone https://github.com/wb2osz/direwolf.git` failed | Incomplete clone or the Pi cannot reach GitHub. See below. |

### Direwolf git clone failed

A failed clone often leaves a broken `~/src/direwolf` folder. On the Pi, as your normal user:

```bash
ping -c 2 github.com
mkdir -p ~/src
cd ~/src
rm -rf direwolf
git clone --depth 1 https://github.com/wb2osz/direwolf.git
```

If clone still fails, skip git and use the source tarball:

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

Then re-run the installer (it will skip Direwolf if `direwolf` is already on PATH):

```bash
./install-linpac-packet.sh --callsign YOURCALL
```

Last resort (older packaged build):

```bash
sudo apt install -y direwolf
```
