# AiroRhythm — Fan Display + Remote Control

A **single-file Flutter implementation** of the AiroRhythm manual: one responsive app that
acts as the *Fan Display* or the *Remote*, with virtual fans first and ESP32 hardware ready
behind the same service contract.

`main.dart` is the whole app — no packages, no assets, no config. Paste it into
**FlutLab.io** (or DartPad / Zapp / `flutter run`) and press Run.

---

## Quick start (FlutLab.io)

1. Create a new Flutter project, open `lib/main.dart`, delete everything.
2. Paste the contents of [`main.dart`](main.dart) and save.
3. Run it. Sign in with the seeded demo account:

   | Email | Password |
   |---|---|
   | `demo@airorhythm.app` | `demo1234` |

   (or tap **Create account** — accounts live in memory for this prototype)

4. **Journey A** — My Devices → *Create device* → Virtual fan → name it → the Fan Display opens.
5. **Journey B (two real devices — laptop + phone)** — on the first device go to
   **Settings → Connect devices → Create room code**; on the second device open the same
   app, sign in and **join with that room code**. Then on device 1 (Fan Display) tap
   **Generate pairing code**, and on device 2 go to **Remote → Connect to a fan** and enter
   the 6-character code. *(A single browser can still fake this with the session chip →
   "Open another device session", but that shares one in-memory backend and is a demo aid,
   not cross-device pairing.)*
6. **Journey C** — press **Turn ON** on the Remote. It shows *Pending…*, then *confirmed by
   the owning device*; the fan on the other device starts spinning and its humidity / smoke /
   resistance readings replicate to the phone every ~2 s.
7. **Journey D (sensors)** — on the Fan Display use the simulation controls to push
   **humidity** up (watch hysteresis kick the fan on), trigger a **smoke burst** (red alarm +
   forced full-speed ventilation) and **add dust** (the fan's colour walks blue → amber →
   red as resistance climbs; *Mark fan as cleaned* resets it).

---

## What is implemented

| Manual section | Status |
|---|---|
| One app, four views (My Devices / Fan Display / Remote / Settings) | ✅ |
| Virtual device with simulated readings, labelled `SIMULATED DATA` | ✅ |
| Device abstraction: `virtualFanAdapter` + `esp32Adapter` stub behind one contract | ✅ |
| Desired-state commands: pending → confirmed / rejected / timeout / offline / unsupported | ✅ |
| Command ids, monotonic state revision, idempotent desired state | ✅ |
| Pairing codes: CSPRNG, salted SHA-256 at rest, expiry, single-use, attempt limits | ✅ |
| Roles (owner / controller / viewer) + owner revocation | ✅ |
| Automation with humidity hysteresis + dwell time (pure, unit-tested) | ✅ |
| Monitored parameters: **humidity sensor** + **smoke detection** | ✅ |
| **Fan resistance** monitoring (dust/debris), colour ramp blue → amber → red | ✅ |
| Cross-device sync (room link over a public relay) so pairing works laptop ↔ phone | ✅ |
| Stale / offline handling, "Last reported" labels, no fake hardware success | ✅ |
| Simulation controls (virtual only), clearly labelled | ✅ |
| Realtime sync bus + reconnect recovery ("Fetch canonical state") | ✅ |
| Activity history (bounded) | ✅ |
| Responsive phone / tablet / laptop layout, semantic labels, dark accessible palette | ✅ |
| In-app self-tests (Settings → Self-tests) | ✅ |
| Docs: API contract, hardware integration, security (also under `docs/`) | ✅ |

## Architecture

```
UI (pages + components)
   └─ AppController (ChangeNotifier)
        ├─ FanService ......... commands, permissions, automation, state transitions
        ├─ PairingService ..... codes, memberships, revocation
        └─ AuthService ........ sessions (one session = one signed-in device)
             └─ DemoBackend (DeviceRepository) ── the "server": devices, state,
                  readings, memberships, codes, events + SyncBus (realtime)
                     ├─ SyncEngine ─ NtfyTransport (public relay, GET only)
                     │               MemoryTransport (tests)
                     └─ FanDeviceAdapter  ┬─ VirtualFanAdapter  (now)
                                          └─ Esp32FanAdapter    (stub, later)
```

### Cross-device sync

Each client has an id (`ownerClientId` on every device) and joins a **room** (an 8-character
code). Inside a room it publishes small ops — `device.upsert`, `state.reported`, `readings`,
`env`, `code.issue`, `code.consume`, `membership.grant/revoke`, `command`, `event` — and polls
for new ones every 2 s. Ops are de-duplicated by id and state is merged by monotonically
increasing `revision`. Only the client that **owns** a device simulates it and executes its
commands; a command from any other device is relayed to the owner and confirmed only when the
owner reports a newer revision (otherwise: `timeout`, never a fake success).

* The UI never touches storage or an adapter; it only calls services.
* `DeviceRepository` is an abstract interface — swap `DemoBackend` for Supabase/REST and
  nothing above it changes.
* The simulation engine + ticker live in the **backend**, so state survives a screen being closed.

## Demo scope — read this before shipping

`main.dart` has **no server**. Auth, the database and realtime are simulated in memory by
`DemoBackend`; a *session switcher* (Settings → Account) stands in for a second physical
device, and an optional **room link** (`Settings → Connect devices`) replicates that state
between two real devices through the public `ntfy.sh` relay over plain GET requests — no API
key, no account, no third-party package. Pairing, permissions, hashing and command semantics
are real code; the relay is a demo-grade transport, not a security boundary (see
`docs/SECURITY.md`).

To go production: implement `DeviceRepository` against Supabase (see `supabase/schema.sql`),
replace `AuthService` with Supabase Auth, move pairing-code issuing/redemption into
Postgres functions or an edge function (codes must be generated and compared server-side),
and keep the UI and adapters unchanged.

## Verified

`flutter analyze` (Flutter 3.35.7 / Dart 3.9.2) → no errors (only deprecation *info* for
`withOpacity` / `MaterialState*`, kept deliberately for older Flutter compatibility), and
`flutter test` → **15/15 passing** (plus 44 in-app self-tests), covering:

* SHA-256 vectors, automation boundary cases (below / at / between / at / above thresholds,
  invalid thresholds, missing + stale readings, dwell time)
* Virtual adapter capability gating; ESP32 stub never confirms and never fabricates readings
* Command pipeline confirmation, injected-failure rejection, invalid automation rejection
* Pairing: wrong code rejected, correct code grants Controller, single use, expiry,
  controller can then command, Viewer cannot
* Physical device stays offline with no telemetry; tick never writes virtual data into it
* Smoke detection thresholds, stale-reading fail-safe, resistance bands and the colour ramp
* Relay stream parsing (ids retained so polling resumes), oversized payloads refused
* **Two clients, one room**: a device and a pairing code created on client A are visible on
  client B, the code redeems on B, the membership shows up on A, and a command from B is
  executed and confirmed by A
* Boot + My Devices / Fan Display / Remote / Settings rendering, device creation, session sheet

## Files

| File | Purpose |
|---|---|
| `main.dart` | The entire application (paste into FlutLab) |
| `docs/API-CONTRACT.md` | ESP32 HTTP contract + service contract |
| `docs/HARDWARE-INTEGRATION.md` | Wiring, networking, firmware safety |
| `docs/SECURITY.md` | Pairing, roles, RLS, secret handling |
| `supabase/schema.sql` | Postgres schema + RLS policies for the real backend |
| `.env.example` | Config placeholders (no secrets in the client) |
