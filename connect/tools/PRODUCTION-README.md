# AiroRhythm Connect 1.0.0

Puts your AiroRhythm ESP32 fan on your home Wi-Fi, then controls it — from a phone,
a laptop, anything with a browser. No account, no cloud, no companion app: the page
talks straight to the board on your own network.

```
Join the fan's hotspot  →  pick your home Wi-Fi  →  control the fan
       10 seconds            type once            done
```

---

## What is in this folder

| File | What it is | Needs to ship? |
|---|---|---|
| `index.html` | The whole app — HTML, CSS and JS in one file. No build step, no dependencies. | **yes** |
| `assets/logo_mark.png` | Favicon and logo used by the page. | **yes** |
| `firmware/airorhythm_wifi_setup.ino` | The ESP32 sketch the app talks to. Flash this to the board. | **yes** |
| `server.js` | Optional http server for your laptop: serves the app and proxies the fan at `/board/*`. No npm install needed. | optional |
| `simulator/esp32-sim.js` | The fake fan behind the in-app demo. Delete the folder and the demo card disappears. | optional |
| `package.json` | `npm start`, `npm run sim`. | optional |

Everything runs on Node 18+ (or not at all — `index.html` opens from any static
host or even a USB stick).

---

## 1. Flash the board

Arduino IDE → **Boards Manager** → install **esp32** by Espressif, then open
`firmware/airorhythm_wifi_setup.ino`.

- Board: **ESP32 Dev Module** · Upload speed 921600
- **No extra libraries** with `HAS_FAN`, `HAS_DHT`, `HAS_SMOKE`, `HAS_CURRENT` left at `0`.
  (Switching `HAS_DHT` on needs Adafruit's *DHT sensor library* + *Adafruit Unified Sensor*.)
- Serial Monitor at **115200**. First boot:

```
=== AiroRhythm ESP32 1.0.0 ===
[boot] saved network: (none)
[setup] network 'AiroRhythm-Setup' at http://192.168.4.1
[boot] ready · waiting for setup
```

Sensors you have not wired report `null`; the app shows “—” rather than inventing a number.

---

## 2. Put the app somewhere the phone can reach

**Option A — laptop on the same Wi-Fi (recommended):**

```bash
node server.js
# AiroRhythm Connect 1.0.0
#   app      http://localhost:8080/
#   phone    http://<this-computer-ip>:8080/  (same Wi-Fi)
```

Add `PORT=3000` for a different port. Binding is `0.0.0.0`, so the phone can open it.

**Option B — any static host:** upload `index.html` + `assets/`. The app works, but
**the browser will block it from reaching `http://192.168.x.x` when the page is served
over `https://`** (mixed content). That is a browser rule, not a bug — use `http://` or
Option A.

**Option C — the board itself:** once the fan is online it serves its own small control
page at `http://<fan-ip>/`. The full app is nicer, but this needs nothing else.

---

## 3. Run the setup flow

1. **Start setup** → the page shows `AiroRhythm-Setup` and watches `192.168.4.1`.
2. On the phone: **Settings → Wi-Fi → AiroRhythm-Setup**. It is open by default;
   the “No internet” warning is expected — stay connected. A caption/captive portal may
   open by itself.
3. Back in the app, the strip turns green (**Fan found**) and **Continue** lights up.
4. Pick your **2.4 GHz** network, type the password, tap **Connect my fan**.
   A 5 GHz name is flagged before you try.
5. On success you get the fan's address (e.g. `192.168.1.23`) and **Open fan controls**.

The fan remembers the network — this is a one-time job. Move the phone back to your
home Wi-Fi afterwards.

### After setup

- `http://192.168.1.23/` — the fan's address (copy it from the success screen)
- `http://airorhythm.local/` — works on Android and laptops (mDNS), **not iPhone**
- **Change Wi-Fi** keeps the old network until the new one actually works
- **Start over** wipes the saved network (same as holding **BOOT** at power-up)

---

## Optional: proxy a real fan through the server

Useful when the app is served from a machine on the same network, or when you want one
URL for both the page and the board:

```bash
BOARD_HOST=192.168.1.23 node server.js
curl http://localhost:8080/board/status
```

`/board/<path>` is forwarded to `http://<BOARD_HOST>/<path>` with CORS and the
Private-Network-Access header set, a 9 s timeout, and JSON errors (`502 no-board-configured`,
`504 unreachable`). `GET /health` reports what is configured.

---

## Optional: the demo

`simulator/esp32-sim.js` is a software copy of the firmware. With it present, the home
screen offers **“No fan handy?”** and `/sim/*` answers like a board would:

- any password of **8+ characters** works
- `JioFiber_5G` always fails (no 5 GHz radio)
- a password under 8 characters always fails

```bash
npm run sim     # http://127.0.0.1:8099 on its own
```

Delete the `simulator/` folder for a clean production install; `server.js` only mounts
`/sim` when the file is there.

---

## HTTP contract (what the board answers)

Both spellings work on the firmware: the app calls `/ap/*` while the phone is on the
fan's hotspot and `/lan/*` once the fan is on your network; the bare paths (below) keep
the built-in pages and `curl` happy.

**Setup mode — `http://192.168.4.1`**

| Method | Path | Returns |
|---|---|---|
| GET | `/status` | `{"state":"ap"｜"connecting"｜"connected"｜"failed","ip":…,"reason":…,"fw":…}` |
| GET | `/scan` | `{"networks":[{"ssid":"Home_WiFi","rssi":-46,"enc":true,"ch":6}]}` |
| POST | `/wifi` | `{"ssid":…,"password":…}` → `{"ok":true,"ip":"192.168.1.23"}` or `{"ok":false,"reason":"bad-password"｜"not-found"｜"5ghz"｜"timeout"}` |
| POST | `/reset` | wipe the saved network and reboot |

**Home network — the fan's IP**

| Method | Path | Returns |
|---|---|---|
| GET | `/status` | `{"state":"connected","ip":…,"ssid":…,"rssi":…}` |
| GET | `/state` | telemetry (below) |
| POST | `/cmd` | `{"a":"fan","on":true,"speed":3}` |
| POST | `/wifi` | switch networks; on failure the **old one is restored** |
| POST | `/forget` | clear the network, reboot into setup mode |
| GET | `/scan` | nearby networks |

```json
{"t":"tel","on":true,"speed":3,"rpm":1280,"mode":"manual","temp":29.4,"rh":54,
 "smoke":60,"amps":0.095,"watts":21.9,"ssid":"Home_WiFi","rssi":-46,
 "ip":"192.168.1.23","uptime":184,"fw":"1.0.0"}
```

`rpm` is estimated from the speed setting unless you add a tachometer (`rpmEst` says so).

---

## Firmware settings (top of the .ino)

| Setting | Default | Notes |
|---|---|---|
| `AP_SSID` | `AiroRhythm-Setup` | hotspot name |
| `AP_PASSWORD` | `""` (open) | 8+ characters to lock it |
| `CONNECT_TIMEOUT` | `20000` ms | how long to try before reporting failure |
| `MDNS_HOSTNAME` | `airorhythm` | gives `http://airorhythm.local` |
| `HAS_FAN` / `FAN_PWM_PIN` | `0` / `25` | PWM out to an L298N or similar |
| `HAS_DHT` / `DHT_PIN` | `0` / `4` | DHT22 temperature + humidity |
| `HAS_SMOKE` / `SMOKE_PIN` | `0` / `34` | MQ analogue out |
| `HAS_CURRENT` / `CURRENT_PIN` | `0` / `35` | ACS712-30A analogue out |
| `LED_PIN` | `2` | on-board LED |
| `RESET_PIN` | `0` | BOOT, held at power-up, clears Wi-Fi |

LED: slow blink = waiting for setup · fast blink = joining · solid = online.

---

## Troubleshooting

| Symptom | What to do |
|---|---|
| `AiroRhythm-Setup` never appears | Power-cycle the fan, wait 10 s, and check for the slow blink. A solid LED means it is already on a network — hold **BOOT** at power-up to wipe it. |
| “No internet connection” warning | Expected. Stay on the network; the setup page is local. |
| Password rejected | 2.4 GHz networks only, and check the password. The fan restores its previous network if the new one fails. |
| Fan joined but the app can't reach it | Same Wi-Fi, right address, and the page must be `http://` — an `https://` page cannot talk to a plain-http device. |
| Nothing happens at all | Open the browser console (F12): messages start with `[AiroRhythm]` and name the exact address that failed. |

---

## Safety

Keep the wall switch in the circuit, fuse the mains side, and bench-test the motor
driver with a lamp before the fan blades go back on. The ESP32 is 3.3 V logic — never
wire mains anywhere near it.
