# AiroRhythm Connect

A phone-friendly web app that **puts your AiroRhythm ESP32 fan on your home Wi-Fi**, then
controls it. No app store, no account, nothing in the cloud — the page talks straight to the
board on your own network.

```
Join the fan's hotspot  →  pick your Wi-Fi  →  control the fan
       10 seconds            type once            done
```

It is plain HTML/CSS/JS in a single file (`index.html`) with no dependencies, plus:

- `firmware/airorhythm_wifi_setup.ino` — the ESP32 sketch it talks to (captive portal included)
- `simulator/esp32-sim.js` — a software copy of that firmware, so the whole app can be used and
  demonstrated with no hardware
- `server.js` — serves the app and the simulator on one `http://` origin

---

## Try it in 30 seconds (no hardware)

```bash
cd connect
npm start                 # same as: node server.js
```

Open **http://localhost:8080** and tap **Open the demo**. You get a simulated fan that scans
fake networks, fails on purpose when you pick the 5 GHz one or type a short password, joins
your chosen network, and then shows live-ish telemetry.

> Demo tip: any password of **8+ characters** works. `JioFiber_5G` always fails (the ESP32 has
> no 5 GHz radio) and a password under 8 characters always fails — both on purpose.

The demo is mounted at `/sim`, so it also works when the page is viewed over **https** (preview
iframes, tunnels) where a real `http://192.168.x.x` board would be blocked by the browser.

---

## Real hardware, three steps

### 1. Flash the firmware

`firmware/airorhythm_wifi_setup.ino`

- Arduino IDE → **Boards Manager**: install **esp32** by Espressif.
- Board: **ESP32 Dev Module**. Upload speed 921600 is fine.
- **No extra libraries needed.** (Only if you switch on `HAS_DHT` do you need Adafruit's
  *DHT sensor library* + *Adafruit Unified Sensor*.)
- Leave `HAS_FAN`, `HAS_DHT`, `HAS_SMOKE`, `HAS_CURRENT` at `0` for a bare board — Wi-Fi setup
  still works and telemetry reports `null` for sensors it does not have.

Open the Serial Monitor at **115200**. First boot looks like:

```
=== AiroRhythm ESP32 1.0.0 ===
[boot] saved network: (none)
[setup] network 'AiroRhythm-Setup' at http://192.168.4.1
[boot] ready · waiting for setup
```

### 2. Join the fan's hotspot

On your phone: **Settings → Wi-Fi → AiroRhythm-Setup**.

- It is an **open** network by default (set `AP_PASSWORD` in the sketch to lock it).
- Your phone will warn **“No internet connection.”** That is expected — keep the connection.
- A setup page usually opens by itself (captive portal). If not, open **http://192.168.4.1**.

That page is served by the board itself, so it works with only a phone and no laptop.
The board's LED blinks slowly while it waits.

### 3. Pick your Wi-Fi

Choose your **2.4 GHz** network, type the password, tap **Connect my fan**. The LED blinks fast
while it joins, then stays **solid** when it is online. The page shows the address it was given,
for example:

```
Your fan is online · 192.168.1.23
```

Reconnect your phone to your home Wi-Fi, then:

- **Control it with no extra software:** open `http://192.168.1.23/` on your phone — the board
  serves a small control page (on/off, speeds, RPM, power, sensors).
- **Or use the full app** (below) for the nicer controls, setup wizard and troubleshooting.

`http://airorhythm.local/` also works on Android and laptops (mDNS). iPhone cannot resolve
`.local` names — use the IP address there.

### LED quick reference

| LED | Meaning |
|---|---|
| Slow blink (~0.7 s) | Setup mode — waiting for you |
| Fast blink | Trying to join your Wi-Fi |
| Solid | Connected and online |
| Off / unexpected | Power or firmware problem — check the Serial Monitor |

**Forgot the network / changing router?** Hold the **BOOT** button (GPIO 0) while plugging the
board in, then release after ~2 seconds. Saved Wi-Fi is wiped and setup mode returns. You can
also use **Fan → Network → Start over** in the app.

---

## Using the full app at home

The app must be opened over **http://** for it to reach a fan at `http://192.168.x.x` — a browser
blocks an https page from talking to a plain-http device. Three ways that work:

| Option | How | Demo available? |
|---|---|---|
| **Local server (easiest)** | `node connect/server.js` on a laptop, then open `http://<laptop-ip>:8080` on the phone | yes (`/sim`) |
| **From disk** | copy `connect/` to the phone and open `index.html` | no |
| **Any static host over http** | `python3 -m http.server 8080` in `connect/` and open `http://<laptop-ip>:8080` | no |
| **Vercel** | this repo is connected; `connect/vercel.json` sets caching, root directory is `connect` | no |

On a `file://` or plain-static copy everything still works except the demo, because the demo
needs the little simulator behind `/sim`.

> **Hosted on Vercel it is `https://`.** That means it is great for walking through the flow,
> but the browser will block it from reaching a real fan at `http://192.168.x.x` — the page
> says so itself on the home screen. For a real setup use the APK, the local server, or the
> board's own page.

Then in the app: **Fan tab → Enter address** → `192.168.1.23` (or `airorhythm.local`) →
**Connect**. Controls are live: power, speed 1–4, RPM, watts, temperature, humidity, smoke, and
the fan's Wi-Fi details.

---

## Android app (APK)

The same app ships as an installable APK: a ~60 KB WebView wrapper that loads
`index.html` **from inside the APK**, so it works with no server, no browser and no
internet — just the phone and the fan.

- Source: [`android/`](android/) — one `MainActivity`, no libraries, no AndroidX.
- The build copies `index.html` + `assets/logo_mark.png` into the APK (`syncWebApp`), so the
  APK can never drift from the web app.
- Cleartext HTTP is allowed and the WebView is told to accept it, which a browser page on
  `https://` would refuse — that is the whole reason to have an APK.
- Extra, only inside the app: **Open Wi-Fi settings** in step 1 jumps straight to the
  system Wi-Fi panel. The page reveals it only when the bridge exists, so the browser
  build is unchanged.

### Get the APK

Three ways, pick whichever suits you:

| Where | How |
|---|---|
| **This repository** | `release/airorhythm-connect-1.0.0.apk` — committed by CI, so a clone has it |
| **The running server** | open `/downloads/` and tap **Download airorhythm-connect-1.0.0.apk** |
| **Actions** | **Android APK** → a run → download the `airorhythm-connect-apk` artifact |

Then on the phone: open the file, allow "install unknown apps" once, install, and launch
**AiroRhythm Connect**.

The workflow builds on every change to the web app and commits a fresh APK whenever the
commit message contains `[apk]` (or on a manual run), so the file in `release/` never goes
stale.

The debug APK is signed with the standard debug key, which is fine for sideloading. Replace
the `signingConfig` in `app/build.gradle` before publishing anywhere.

### Build it yourself

```bash
# Android Studio: open connect/android and press Run
# or, with a local JDK 17 + Android SDK:
cd connect/android && gradle assembleDebug
# → app/build/outputs/apk/debug/app-debug.apk
```

The in-app **demo** needs the little simulator behind `/sim`, which only the Node server
provides, so the demo card stays hidden in the APK. Everything else — setup, scan, joining,
controls, Change Wi-Fi, Help — is the same code.

---

## Shipping it (production files)

```bash
npm run release          # → ../release/airorhythm-connect-1.0.0/ + .zip
```

That assembles exactly what you deploy, straight from this folder, so nothing has to be
hand-picked later:

| File in the package | Why |
|---|---|
| `index.html` | the whole app (one file, no build step, no dependencies) |
| `assets/logo_mark.png` | favicon + logo the page references |
| `firmware/airorhythm_wifi_setup.ino` | flash this to the board |
| `server.js` | lean production server: static + `/board/*` proxy, no simulator assumptions |
| `README.md` | deployment, wiring, HTTP contract, troubleshooting |
| `simulator/` | **optional** demo backend — delete it and the demo card disappears |
| `SHA256SUMS.txt`, `package.json` | integrity + `npm start` |

The packaged `server.js` differs from the dev one on purpose: it has no dependency on the
simulator (mounted only if the folder is present), refuses dotted paths and path traversal,
caches assets but never the HTML, answers `GET /health` with `{ok, board, demo, version}`,
and exits with a readable message if the port is taken.

Verify a package:

```bash
cd release/airorhythm-connect-1.0.0 && node server.js     # http://localhost:8080
curl -s localhost:8080/health
BOARD_HOST=192.168.1.23 node server.js                    # + /board/* proxy
```

---

## What's in the app

| Screen | What it does |
|---|---|
| **Home** | Start setup, reopen a saved fan, or open the demo. Warns when the page is https. |
| **Step 1 — Join** | The hotspot name with a copy button and a one-line checklist (“No internet” is explained before you hit it). A live detection strip shows *searching → found → still nothing*, and only reveals the troubleshooting link when it actually needs to. **Continue** turns on the moment the board answers. |
| **Step 2 — Network** | The board scans, and you get three big rows with signal strength and lock state (scroll for more, or **Type the name instead** for a hidden network). Names that look 5 GHz are flagged before you commit, the password is length-checked, and the **Connect my fan** button sticks to the bottom so it is never off-screen. |
| **Step 3 — Connect** | A ring draws the join, then three stages tick over with elapsed time. On success: the address, a copy button, and **Open fan controls**. On failure: a plain-language reason (“That's a 5 GHz network”), the retry buttons first, then three things to check. |
| **Fan** | Live telemetry (power, temperature, humidity, air quality), power and speed 0–4, network details, **Change Wi-Fi** in a sheet that keeps the old network until the new one works, and **Start over**. |
| **Help** | Nine answers: hotspot missing, “no internet”, wrong password, 5 GHz, can't reach the fan, https/mixed content, LED meanings, factory reset, safety. |

The layout is checked in a real browser from **320 px to 1440 px** — nothing overflows sideways, and
every primary button stays on screen without scrolling (the step-2 button is sticky, the rest fit).

Details that make it feel less like a config page: it remembers the last fan, copies addresses
for you, never says “success” before the board confirms, disables buttons while a command is in
flight, keeps working when the screen was in the background, and has a real empty state instead
of a spinner forever.

---

## How the two halves talk

Everything is JSON over HTTP with `Access-Control-Allow-Origin: *`, so the app can live on a
different origin. `OPTIONS` preflights are answered too.

**Setup mode** (`http://192.168.4.1`)

| Method | Path | Returns |
|---|---|---|
| GET | `/status` | `{"state":"ap"｜"connecting"｜"connected"｜"failed","ip":…,"reason":…,"fw":…}` |
| GET | `/scan` | `{"networks":[{"ssid":"Home_WiFi","rssi":-46,"enc":true,"ch":6}]}` |
| POST | `/wifi` | `{"ssid":…,"password":…}` → `{"ok":true,"ip":"192.168.1.23"}` or `{"ok":false,"reason":"bad-password"｜"not-found"｜"5ghz"｜"timeout"}` |
| POST | `/reset` | wipes the saved network and reboots |
| GET | `/` | the board's own setup page |

> **Both spellings work.** The app calls `/ap/status`, `/ap/scan`, `/ap/wifi`, `/ap/reset` while it is
> on the fan's hotspot and `/lan/status`, `/lan/state`, `/lan/cmd`, `/lan/wifi`, `/lan/forget`,
> `/lan/scan` once the fan is on your home network. The sketch registers those prefixes next to the
> bare paths in the tables, so curl, the built-in pages and the app all agree.

**Home network** (the fan's IP)

| Method | Path | Returns |
|---|---|---|
| GET | `/status` | `{"state":"connected","ip":…,"ssid":…,"rssi":…}` |
| GET | `/state` | telemetry (see below) |
| POST | `/cmd` | `{"a":"fan","on":true,"speed":3}` → `{"ok":true,…}` |
| POST | `/wifi` | switch networks; on failure the **old network is restored** |
| POST | `/forget` | clear the network, reboot into setup mode |
| GET | `/scan` | nearby networks |
| GET | `/` | the board's small control page |

Telemetry shape (`GET /state`):

```json
{"t":"tel","on":true,"speed":3,"rpm":1280,"mode":"manual","temp":29.4,"rh":54,
 "smoke":60,"amps":0.095,"watts":21.9,"ssid":"Home_WiFi","rssi":-46,
 "ip":"192.168.1.23","uptime":184,"fw":"1.0.0"}
```

Sensors you have not wired are `null`, and the app shows “—”, never a fake number.

`rpm` is **estimated** from the speed setting unless you add a tachometer to the firmware; the
field `rpmEst` says so.

Quick check from a laptop on the same Wi-Fi:

```bash
curl http://192.168.1.23/state
curl -X POST http://192.168.1.23/cmd -H 'content-type: application/json' \
     -d '{"a":"fan","on":true,"speed":3}'
```

---

## Firmware settings

At the top of `firmware/airorhythm_wifi_setup.ino`:

| Setting | Default | Notes |
|---|---|---|
| `AP_SSID` | `AiroRhythm-Setup` | Name of the hotspot |
| `AP_PASSWORD` | `""` (open) | 8+ characters to require a password |
| `CONNECT_TIMEOUT` | `20000` ms | How long to try before reporting a failure |
| `MDNS_HOSTNAME` | `airorhythm` | Gives `http://airorhythm.local` |
| `HAS_FAN` / `FAN_PWM_PIN` | `0` / `25` | PWM out for an L298N / driver |
| `HAS_DHT` / `DHT_PIN` | `0` / `4` | DHT22 temperature + humidity |
| `HAS_SMOKE` / `SMOKE_PIN` | `0` / `34` | MQ analogue out |
| `HAS_CURRENT` / `CURRENT_PIN` | `0` / `35` | ACS712-30A analogue out |
| `LED_PIN` | `2` | On-board LED on most DevKits |
| `RESET_PIN` | `0` | BOOT button, held at power-up clears Wi-Fi |

Bench-test the motor driver with a lamp **before** putting mains anywhere near it. Keep the wall
switch in the circuit.

---

## Demo simulator

```bash
node simulator/esp32-sim.js            # http://127.0.0.1:8099
PORT=9000 node simulator/esp32-sim.js
```

Same endpoints as the firmware, at `/ap/*` and `/lan/*`, with four fake networks. It models the
parts that matter for the UI: association time, wrong-password and 5 GHz failures, telemetry
drift, fan spin-up, watts, timers, and a reset back to setup mode.

---

## Tests

```bash
cd connect
npm test
```

Ten contract tests against the simulator cover: setup-mode status, CORS preflight, scanning,
short-password and 5 GHz failures, unknown network, successful join and address, telemetry,
commands, unknown command rejection, and forgetting the network.

The app itself was walked end to end in a DOM harness (demo start → detection → scan → validation
→ join → controls → change Wi-Fi → help → failure path → retry) with no console errors.
The sketch has not been run on hardware in this repository's checks — flash it and watch the
Serial Monitor for `[boot] ready`.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `AiroRhythm-Setup` never appears | Power-cycle the fan and wait ~10 s; check the Serial Monitor says `[setup] network …`. Hold BOOT while powering on to force setup mode. |
| Phone drops the hotspot | Keep the phone on `AiroRhythm-Setup` while setup runs. Answer “Stay connected” if Android asks. |
| “Password didn't work” | Passwords are case-sensitive; confirm the network is 2.4 GHz, not the 5 GHz twin. |
| Only 5 GHz at home | Switch on the 2.4 GHz band in the router app, or test with a 2.4 GHz phone hotspot. |
| Fan is online, app can't reach it | Phone and fan must be on the same network (guest Wi-Fi and AP isolation break this). Use the IP, not `.local`, on iPhone. Allow Chrome's local-network prompt. |
| Everything fails over https | Browsers block `https` pages reaching `http` devices. Run `node connect/server.js` and use its `http://` address. |

More in the app's **Help** tab.

---

## Security & limits

- The setup hotspot is **open** by default for convenience. Set `AP_PASSWORD` if you would rather
  have it locked.
- The fan's API has **no authentication**. Keep it on your home network; never expose it to the
  internet or put it on public Wi-Fi.
- Your Wi-Fi password is stored in the ESP32's NVS flash in plain text. That is normal for
  microcontroller provisioning but worth knowing: anyone with physical access to the board can
  read it.
- Traffic is plain HTTP (an ESP32 has no practical TLS server). The app refuses to pretend
  otherwise and explains the mixed-content rule instead of failing silently.
- `rpm`, `smoke` and current readings are only as good as the sensors you wire — everything else
  is reported honestly as `null` or marked as an estimate.

---

## Files

```
connect/
├── index.html                     the whole app (no build step, no dependencies)
├── server.js                      static hosting + /sim + optional /board proxy
├── package.json                   npm start / npm test
├── assets/                        logo artwork
├── firmware/
│   └── airorhythm_wifi_setup.ino  ESP32 sketch: setup portal + fan API + control page
├── simulator/
│   └── esp32-sim.js               software copy of that firmware
└── tests/
    └── sim.test.js                contract tests
```

Optional: proxy a real board through the local server (handy when the page is on https or you
want same-origin calls):

```bash
BOARD_HOST=192.168.1.23 node server.js     # board reachable at /board/*
```
