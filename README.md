# 🌬️ AiroRhythm — Smart Fan Control & Monitoring

### Rethinking the way we interact with fans.

**AiroRhythm** is a smart-fan control and monitoring prototype developed by Team AiroRhythm for **AtomQuest 2026 by Atomberg**. It explores how conventional fans can evolve into connected, intelligent devices through remote control, environmental monitoring, automation, and cross-device communication.

The project starts with virtual fans and is designed with a service architecture that can later integrate physical fan hardware through an ESP32-based implementation.

---

## 🚀 What is AiroRhythm?

Imagine controlling a fan from your phone while viewing its status on another device. Now imagine that fan responding automatically to changing humidity, detecting smoke, and monitoring dust-related resistance.

AiroRhythm explores this concept through a unified interface that supports both **Fan Display** and **Remote Control** modes.

The prototype simulates fan behaviour and sensor readings, allowing its control logic and device-to-device workflows to be explored before physical hardware is integrated.

## ✨ Key Features

- **🎛️ Smart Fan Control:** Turn virtual fans on or off remotely and manage their operating state.
- **📱 Cross-Device Communication:** Connect a laptop and phone through a room-based pairing workflow.
- **🌡️ Environmental Monitoring:** Simulate humidity readings and trigger automatic fan responses.
- **🚨 Smoke Detection:** Demonstrate smoke alerts and forced full-speed ventilation in the simulation.
- **🧹 Dust & Resistance Monitoring:** Simulate increasing fan resistance and display a blue-to-amber-to-red condition indicator.
- **⚙️ Intelligent Automation:** Use humidity thresholds, hysteresis, and dwell time to demonstrate automated fan operation.
- **🔐 Device Pairing & Permissions:** Support pairing codes, expiry, single-use redemption, owner/controller/viewer roles, and access revocation.
- **🔄 State Synchronization:** Relay commands and state updates between connected clients, with confirmation from the device owner.
- **📜 Activity History:** Keep a bounded history of relevant device events.
- **🧪 Built-in Testing:** Includes in-app self-tests and automated tests for important control, pairing, and synchronization behaviours.
- **📐 Responsive Interface:** Designed for phone, tablet, and laptop screens.

> **Important:** Sensor readings and virtual fan behaviour are simulated. Physical fan control and ESP32 integration are not yet implemented in this prototype.

## 🖥️ Application Views

| View | Purpose |
|---|---|
| **My Devices** | Create and manage fan devices. |
| **Fan Display** | View the fan's state, readings, alerts, and simulation controls. |
| **Remote** | Control a paired fan from another device. |
| **Settings** | Manage sessions, device connections, pairing, and self-tests. |

## 🛠️ Technology & Architecture

AiroRhythm is implemented as a Flutter application using Dart.

- **Frontend:** Flutter and Dart
- **Application state:** `ChangeNotifier` through an `AppController`
- **Services:** FanService, PairingService, and AuthService
- **Device abstraction:** A shared interface for virtual and future physical fan adapters
- **Demo backend:** In-memory `DemoBackend` and `DeviceRepository`
- **Cross-device relay:** Optional room-based synchronization using the public `ntfy.sh` relay
- **Planned production backend:** Supabase, PostgreSQL, and Supabase Auth
- **Planned hardware integration:** ESP32 with an HTTP-based device contract

### Architecture at a glance

```text
Flutter User Interface
          |
          v
     AppController
          |
    +-----+------+
    |            |
 FanService  PairingService
    |            |
    +-----+------+
          |
     DemoBackend
          |
     DeviceRepository
          |
    +-----+------+
    |            |
Virtual Fan   ESP32 Adapter
 (Implemented)  (Stub)
          |
       Sync Engine
          |
      ntfy.sh Relay
          |
    Connected Client
```

The interface communicates with application services instead of accessing device adapters or storage directly. This separation is intended to make future backend and hardware integration easier without rewriting the entire UI.

## ⚡ Getting Started

### Option 1: Run using FlutLab

1. Open [FlutLab](https://flutlab.io/) and create a new Flutter project.
2. Open `lib/main.dart`.
3. Replace its contents with the code from the repository's `main.dart`.
4. Save the file and run the project.
5. Sign in with the demo credentials below.

| Field | Demo value |
|---|---|
| Email | `demo@airorhythm.app` |
| Password | `demo1234` |

You can also select **Create account** to create a prototype account. These demo accounts are stored in memory and are not production authentication accounts.

### Option 2: Run locally

Install the [Flutter SDK](https://docs.flutter.dev/get-started/install) and verify your setup:

```bash
flutter doctor
```

Clone the repository:

```bash
git clone https://github.com/GourvendrakumarJha/AiroRhythm-GOAT.git
cd AiroRhythm-GOAT
```

Open the project file containing the Flutter application and place the app source in `lib/main.dart`. Then run:

```bash
flutter run
```

**Note:** The repository's current application is designed as a single-file Flutter implementation. Check the repository structure and any accompanying documentation before assuming it is a conventional, fully configured Flutter project.

## 🔗 Try the Main Workflows

### 1. Create a virtual fan

Go to **My Devices → Create device → Virtual fan**, assign a name, and open its Fan Display.

### 2. Connect two devices

On the first device, open **Settings → Connect devices** and create a room code. On the second device, sign in and join the same room.

On the first device, generate a fan pairing code. On the second device, open **Remote → Connect to a fan** and enter the six-character code.

### 3. Test remote control

Use the Remote to switch the fan on or off. Commands are confirmed by the device that owns the fan; a missing confirmation should not be treated as a successful operation.

### 4. Explore the sensor simulations

From Fan Display, experiment with the humidity, smoke, and dust simulation controls. Observe the corresponding automation, alerts, and condition indicators.

## 🧪 Testing & Verification

The project includes automated Flutter tests and in-app self-tests for core prototype behaviours.

The repository documents verification using Flutter 3.35.7 and Dart 3.9.2, with **15 automated tests passing** at the time of that verification, alongside 44 in-app self-tests.

Coverage includes:

- Humidity automation thresholds and hysteresis
- Command confirmation, rejection, and timeout handling
- Pairing-code validation, expiry, and single-use behaviour
- Controller and viewer permissions
- Virtual versus physical device behaviour
- Smoke alerts and resistance monitoring
- Relay message handling and cross-device synchronization

Test results describe the documented verification run and may differ with subsequent code or environment changes.

## 🔒 Security & Limitations

AiroRhythm is a prototype, not a production-ready smart-home control system.

- Authentication and device data are currently simulated in memory.
- The optional public relay is intended for demonstration and is **not a production security boundary**.
- Pairing logic and role-based permissions require a secure server-side implementation before deployment.
- Physical fan actuation and real sensor telemetry require hardware, firmware, and appropriate electrical safety measures.
- Production deployment should use authenticated APIs, server-side pairing-code validation, secure database policies, and appropriate access controls.

Refer to the project's `docs/SECURITY.md`, `docs/API-CONTRACT.md`, `docs/HARDWARE-INTEGRATION.md`, and `supabase/schema.sql` for the documented implementation direction.

## 🛣️ Future Scope

The next stage of AiroRhythm is to bridge the gap between virtual simulation and real-world smart-fan operation.

- Integrate an ESP32-based hardware controller.
- Connect real humidity and smoke sensors.
- Collect real device telemetry instead of simulated readings.
- Replace the in-memory demo backend with Supabase or another suitable production backend.
- Implement secure authentication, authorization, and pairing on the server.
- Expand automated control and monitoring capabilities.
- Validate real-world performance, fault handling, and hardware safety.

## 🎯 Project Vision

**AiroRhythm aims to make fan control more intelligent, connected, and responsive.**

By developing the software architecture and testing the interaction workflows before integrating physical hardware, the project explores a practical path from a virtual prototype to a connected smart-fan ecosystem.

## 👥 Team

**Team AiroRhythm**

Developed as a prototype for **AtomQuest 2026 by Atomberg**.

## 📄 Documentation

Explore the repository for implementation details:

- `main.dart` — Application source
- `docs/API-CONTRACT.md` — Service and hardware API contract
- `docs/HARDWARE-INTEGRATION.md` — Hardware integration guidance
- `docs/SECURITY.md` — Security considerations
- `supabase/schema.sql` — Proposed PostgreSQL schema and row-level security policies
- `.env.example` — Example configuration placeholders

## 📜 License

No license has been specified in this README. Add a suitable open-source license to the repository if you intend to permit others to reuse, modify, or distribute the project.

---

*Built with curiosity, engineering, and a vision for smarter airflow.* 🌬️
