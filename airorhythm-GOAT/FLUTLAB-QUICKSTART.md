# AiroRhythm → FlutLab.io, step by step

`main.dart` is the **entire app**. It imports only `package:flutter/material.dart`,
`package:flutter/services.dart`, `dart:async`, `dart:convert` and `dart:math` —
**no third-party packages, no assets, no fonts, no config**. FlutLab needs nothing
but the file itself.

---

## A. FlutLab.io (no local setup)

1. Log in at **https://flutlab.io** → **Create new project** → pick any code base
   ("Stateless Hello World" is fine).
2. In the file tree open **`lib/main.dart`**, select all, delete, then paste the
   **whole contents of `main.dart`** from this bundle → **Save**.
3. **Nothing to change in `pubspec.yaml`.** There are no dependencies to add.
   (If the template generated `import 'package:cupertino_icons/...'` anywhere, delete
   that import — this app doesn't use it. `main.dart` has no such import.)
4. Press **Build project** (web build) or run it in the built-in emulator.
5. Sign in with the seeded demo account:

   | Email | Password |
   |---|---|
   | `demo@airorhythm.app` | `demo1234` |

---

## B. Linking TWO REAL devices (laptop + phone) — do this first

Pairing works **only between devices that are in the same room**. Without a room,
each browser keeps its own private copy of the data, so a code generated on the
laptop simply does not exist on the phone and is always reported as
*invalid / expired / already used*. That is exactly the bug that was fixed.

**On the first device (e.g. the laptop, which will show the Fan Display):**

1. Sign in → **Settings → Connect devices → Create room code**.
2. You get an 8-character code like `K7M2-QX9P`. Leave this screen open, or copy
   the code (copy button next to it).

**On the second device (e.g. the phone, which will be the Remote):**

3. Open the same FlutLab project URL (or your own deployed web build) and sign in.
4. **Settings → Connect devices → "Or join an existing room code"** → type
   `K7M2-QX9P` (the dash is optional, case doesn't matter) → tap the arrow/enter.
5. The card flips to **LINKED** and shows `ops sent · received · last sync`.

**Now pair the two devices:**

6. On the laptop: **Fan Display → Pairing code → Generate pairing code** → a 6-character
   code appears with a countdown.
7. On the phone: **Remote → Connect to a fan → enter the 6-character code → Pair**.
8. The phone is granted the **Controller** role. Press **Turn ON**: it shows
   *Pending…* → *confirmed* by the device that owns the fan → the fan on the laptop
   starts spinning, and humidity / smoke / resistance readings replicate to the phone
   roughly every 2 seconds.

### Notes / troubleshooting

| Symptom | Cause & fix |
|---|---|
| Phone says "invalid, expired or already used" | The two devices are not in the same room, **or** the code expired (default 120 s) — generate a fresh code and retype it. The pairing card now shows an amber warning when the devices are not linked. |
| `LINKED` but nothing arrives | The devices need outbound HTTPS to `ntfy.sh`. Tap **Sync now**; the card shows any relay error underneath. |
| Both devices show a "Bedroom Ventilation" fan | Both installs seed the same demo device id. They auto-converge on one owner (deterministic tie-break) — you'll end up with a single shared fan. |
| Codes are rate-limited | 8 wrong redemption attempts per 10 minutes; each code also allows only 5 attempts and is single-use. |

### How the link actually works (one paragraph)

There is no server of your own. Each device publishes small JSON ops
(`device.upsert`, `state.reported`, `readings`, `code.issue`, `code.consume`,
`command`, …) to a **private topic on the public `ntfy.sh` relay** and polls that
topic every 2 s. The topic name is `airo-rhythm-<your room code>`, so anyone who
knows the room code can read it — treat the room code like a Wi-Fi password and see
`docs/SECURITY.md`. Pairing codes themselves are **never** published in the clear:
only the salted SHA-256 hash, expiry and single-use flag travel.

### Single-browser demo (no second device handy)

The old **session switcher** is still there: top-right session chip →
**Open another device session**. It signs you in as a second *session* inside the
same browser and shares the same in-memory backend — handy for a screen recording,
but it is **not** a substitute for the room link above.

---

## C. SDK requirement

Verified on **Flutter 3.35.7 / Dart 3.9.2**. The code needs **Dart 3+ (Flutter ≥ 3.10)**
because it uses switch expressions and records. FlutLab's current builder satisfies
this. If you see errors mentioning *"This requires the 'patterns' language feature"*
or *'records'*, your SDK predates Dart 3 — tell me and I'll hand you a
Dart-2-compatible variant of `main.dart`.

## D. If FlutLab complains

| Symptom | Fix |
|---|---|
| `Target of URI doesn't exist: 'package:flutter/material.dart'` | You pasted into the wrong file — it must be `lib/main.dart` |
| Errors about `cupertino_icons` | Delete that import from the template file |
| Blank screen after build | Hard-refresh the preview; the first web build can take ~40 s |
| `withOpacity` deprecation warnings | Harmless (info-level). Kept on purpose so the file also compiles on older SDKs |
| "Network unreachable" in the relay card | The sandbox/IDE blocked outbound HTTPS — the app still works fully as a local demo |

---

## E. What the app gives you

| Screen | What to look for |
|---|---|
| My Devices | device cards with type, connection, humidity + smoke chips, role, revision, last update |
| Fan Display | fan spins only on *reported* ON and is **coloured by resistance** (blue → amber → red); **humidity** and **smoke** tiles; smoke alarm + "Ventilate now"; **fan resistance** gauge with cleaning advice; mode + humidity hysteresis; pairing code with countdown; simulation controls (virtual only); access list; activity |
| Remote | pairing-code entry, ON/OFF + speed (only if the device supports it), humidity/smoke tiles, resistance gauge, pending/confirmed/rejected/timeout, last-seen, refresh, unpair |
| Settings | **Connect devices** (room link), account + sessions, service simulation knobs, **Self-tests**, docs, danger zone |

Monitored parameters are **humidity** and **smoke detection**; **fan resistance**
(dust/debris making the fan harder to turn) is measured and reported continuously
and drives the fan's colour. Demo account password is `demo1234`; newly created
accounts live in memory for the session.

---

## F. Build it locally (exactly what I ran)

```bash
# 1. project
flutter create airorhythm && cd airorhythm

# 2. replace lib/main.dart with the file from this bundle,
#    and drop test/airo_rhythm_test.dart into test/

# 3. dependencies (there are none beyond the SDK)
flutter pub get

# 4. verify
flutter analyze          # -> 0 errors, 15 deprecation *info* notices
flutter test             # -> All tests passed (15/15, incl. 44 in-app self-tests)

# 5. run / ship
flutter run -d chrome            # or: -d linux / -d windows / an emulator
flutter build web --release      # -> build/web  (this is what the preview serves)
flutter build apk --release      # Android, if you want it on a phone
```

The `pubspec.yaml` in this bundle is the minimal one those commands were run against:

```yaml
name: airorhythm
environment:
  sdk: ^3.6.0
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  flutter_test:
    sdk: flutter
flutter:
  uses-material-design: true
```

To preview the web build locally:
`python3 -m http.server 8100 --directory build/web` then open
`http://localhost:8100`.

---

## G. Files in this bundle

| File | Use |
|---|---|
| `main.dart` | the whole app — paste into FlutLab |
| `pubspec.yaml` | minimal manifest for local builds |
| `test/airo_rhythm_test.dart` | 15-test harness (`flutter test`), includes a two-client pairing test |
| `README.md` | overview, architecture, honest scope notes |
| `docs/API-CONTRACT.md` | ESP32 HTTP contract + service contract + sync ops |
| `docs/HARDWARE-INTEGRATION.md` | wiring, networking, firmware safety |
| `docs/SECURITY.md` | pairing, roles, relay threat model, RLS, secret handling |
| `supabase/schema.sql` | Postgres schema + RLS for the real backend |
| `.env.example` | config placeholders (no secrets) |
