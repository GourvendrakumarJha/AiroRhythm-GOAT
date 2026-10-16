// =============================================================================
//  AIRO RHYTHM — Fan Display + Remote Control   (single-file Flutter prototype)
// =============================================================================
//  Drop-in `main.dart` for FlutLab.io / DartPad / Zapp / any Flutter project.
//  Zero third-party packages, zero assets — everything (including the logo and
//  the fan animation) is drawn in code.
//
//  Implements the AiroRhythm "AI Coding Manual":
//    • One responsive app with 4 views: My Devices / Fan Display / Remote /
//      Settings — the same app acts as the Fan Display or the Remote.
//    • Virtual fans now (SIMULATED DATA badge), ESP32 physical fans later
//      through the *same* service contract (esp32 adapter is a safe stub that
//      never fakes success and never fabricates telemetry).
//    • Layered architecture:
//        UI (pages/components)  ->  services (fan / pairing / auth)
//                               ->  device adapters (virtual | esp32)
//                               ->  repository + sync bus (realtime)
//      UI never touches storage or an adapter directly. Swapping the
//      repository for Supabase/Firebase/REST does not touch the UI layer.
//    • Desired-state commands with pending / confirmed / rejected / timeout /
//      offline / unsupported states, command ids and a state revision.
//    • Pairing codes: CSPRNG, SHA-256 hashed at rest, short expiry, single-use
//      atomic consumption, attempt limiting, role-based membership
//      (owner / controller / viewer), owner revocation.
//    • Automation with humidity hysteresis + dwell time (pure, testable fn).
//    • Stale/offline handling: never shows simulated values for a physical
//      device, never treats last-known values as fresh.
//
//  IMPORTANT (demo scope): there is no server here. Auth, the database and
//  realtime are simulated in-memory by `DemoBackend` + `SyncBus`, and a
//  "session switcher" in Settings lets you act as a second signed-in device in
//  the same browser to demo pairing + cross-device sync. Every simulated layer
//  sits behind the same interfaces a real backend would implement.
// =============================================================================

import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:math' as math;

import 'package:flutter/material.dart';

// =============================================================================
//  1. DESIGN TOKENS  (palette sampled from the AiroRhythm logo:
//     near-black base, sky blue #30A8F0 -> violet #6048F0 accents)
// =============================================================================

const Color kBase = Color(0xFF08090C);
const Color kSurface = Color(0xFF12151B);
const Color kSurfaceHigh = Color(0xFF171B23);
const Color kSurfaceTop = Color(0xFF1D222C);
const Color kOutline = Color(0xFF272D38);
const Color kText = Color(0xFFE9ECF3);
const Color kTextDim = Color(0xFF99A2B2);
const Color kBrandBlue = Color(0xFF30A8F0);
const Color kBrandViolet = Color(0xFF6048F0);
const Color kOk = Color(0xFF37D69B);
const Color kWarn = Color(0xFFFFB454);
const Color kDanger = Color(0xFFFF6B6B);
const Color kInfo = Color(0xFF63B3FF);

const List<Color> kBrandGradient = <Color>[kBrandBlue, kBrandViolet];
const double kRadius = 18.0;
const double kNarrowBreakpoint = 760.0;

Color fade(Color c, double a) => c.withOpacity(a.clamp(0.0, 1.0));

ThemeData buildAiroTheme() {
  final ThemeData base = ThemeData(useMaterial3: true, brightness: Brightness.dark);
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: kBrandBlue,
    brightness: Brightness.dark,
  ).copyWith(
    surface: kSurface,
    onSurface: kText,
    primary: kBrandBlue,
    onPrimary: Colors.black,
    secondary: kBrandViolet,
    outline: kOutline,
    error: kDanger,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: kBase,
    canvasColor: kBase,
    cardColor: kSurface,
    dividerColor: kOutline,
    hintColor: kTextDim,
    textTheme: base.textTheme.apply(bodyColor: kText, displayColor: kText),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: kText,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kSurfaceHigh,
      indicatorColor: fade(kBrandBlue, 0.18),
      labelTextStyle: MaterialStateProperty.resolveWith<TextStyle>(
        (Set<MaterialState> s) => TextStyle(
          fontSize: 11.5,
          fontWeight: s.contains(MaterialState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(MaterialState.selected) ? kText : kTextDim,
        ),
      ),
      iconTheme: MaterialStateProperty.resolveWith<IconThemeData>(
        (Set<MaterialState> s) => IconThemeData(
          color: s.contains(MaterialState.selected) ? kBrandBlue : kTextDim,
          size: 23,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: kSurfaceHigh,
      indicatorColor: fade(kBrandBlue, 0.16),
      selectedIconTheme: const IconThemeData(color: kBrandBlue, size: 24),
      unselectedIconTheme: const IconThemeData(color: kTextDim, size: 24),
      selectedLabelTextStyle: const TextStyle(color: kText, fontWeight: FontWeight.w700, fontSize: 12),
      unselectedLabelTextStyle: const TextStyle(color: kTextDim, fontWeight: FontWeight.w500, fontSize: 12),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kSurfaceTop,
      contentTextStyle: const TextStyle(color: kText),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurfaceHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kOutline)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kOutline)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBrandBlue, width: 1.6)),
      labelStyle: const TextStyle(color: kTextDim),
      hintStyle: TextStyle(color: fade(kTextDim, 0.75)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kBrandBlue,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kText,
        side: const BorderSide(color: kOutline),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kBrandBlue),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: kBrandBlue,
      inactiveTrackColor: kOutline,
      thumbColor: kBrandBlue,
      overlayColor: fade(kBrandBlue, 0.18),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.resolveWith<Color>(
        (Set<MaterialState> s) => s.contains(MaterialState.selected) ? Colors.black : kTextDim,
      ),
      trackColor: MaterialStateProperty.resolveWith<Color>(
        (Set<MaterialState> s) => s.contains(MaterialState.selected) ? kBrandBlue : kOutline,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: kSurfaceTop, borderRadius: BorderRadius.circular(8), border: Border.all(color: kOutline)),
      textStyle: const TextStyle(color: kText, fontSize: 12),
    ),
  );
}

// =============================================================================
//  2. SMALL UTILITIES  (ids, sha-256, formatting)
// =============================================================================

final math.Random _rnd = math.Random.secure();
final math.Random _driftRnd = math.Random();

String newId(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_rnd.nextInt(1 << 24).toRadixString(36)}';

/// Dependency-free SHA-256 (hex). Used so pairing codes are stored hashed.
/// In production: keep this server-side and use an HMAC with a server secret.
class Sha256 {
  Sha256._();

  static const List<int> _k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  static int _add(int a, int b) => (a + b) & 0xFFFFFFFF;

  static int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF;

  static String hash(String input) {
    final List<int> msg = utf8.encode(input);
    final List<int> h = <int>[
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ];
    final int bitLen = msg.length * 8;
    final List<int> data = List<int>.from(msg)..add(0x80);
    while (data.length % 64 != 56) {
      data.add(0);
    }
    final int hi = bitLen ~/ 0x100000000;
    final int lo = bitLen % 0x100000000;
    for (final int part in <int>[hi, lo]) {
      data.add((part >> 24) & 0xff);
      data.add((part >> 16) & 0xff);
      data.add((part >> 8) & 0xff);
      data.add(part & 0xff);
    }
    final List<int> w = List<int>.filled(64, 0);
    for (int off = 0; off < data.length; off += 64) {
      for (int i = 0; i < 16; i++) {
        w[i] = (data[off + i * 4] << 24) |
            (data[off + i * 4 + 1] << 16) |
            (data[off + i * 4 + 2] << 8) |
            data[off + i * 4 + 3];
      }
      for (int i = 16; i < 64; i++) {
        final int s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        final int s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = _add(_add(w[i - 16], s0), _add(w[i - 7], s1));
      }
      int a = h[0], b = h[1], c = h[2], d = h[3];
      int e = h[4], f = h[5], g = h[6], hh = h[7];
      for (int i = 0; i < 64; i++) {
        final int s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final int ch = ((e & f) ^ ((~e) & g)) & 0xFFFFFFFF;
        final int t1 = _add(_add(_add(hh, s1), _add(ch, _k[i])), w[i]);
        final int s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final int mj = ((a & b) ^ (a & c) ^ (b & c)) & 0xFFFFFFFF;
        final int t2 = _add(s0, mj);
        hh = g; g = f; f = e; e = _add(d, t1);
        d = c; c = b; b = a; a = _add(t1, t2);
      }
      h[0] = _add(h[0], a); h[1] = _add(h[1], b);
      h[2] = _add(h[2], c); h[3] = _add(h[3], d);
      h[4] = _add(h[4], e); h[5] = _add(h[5], f);
      h[6] = _add(h[6], g); h[7] = _add(h[7], hh);
    }
    return h.map((int v) => v.toRadixString(16).padLeft(8, '0')).join();
  }

  /// Salted hash for secrets at rest: hex(sha256(salt:secret)).
  static String salted(String salt, String secret) => hash('$salt:$secret');
}

String fmtTemp(double? v) => v == null ? '--' : '${v.toStringAsFixed(1)} °C';
String fmtHum(double? v) => v == null ? '--' : '${v.round()} %';
String fmtSpeed(int? v) => (v == null) ? '--' : '$v %';

String fmtClock(DateTime t) {
  final String h = t.hour.toString().padLeft(2, '0');
  final String m = t.minute.toString().padLeft(2, '0');
  final String s = t.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}

String fmtAgo(DateTime? t, DateTime now) {
  if (t == null) return 'never';
  final Duration d = now.difference(t);
  if (d.inSeconds < 5) return 'just now';
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

String fmtCountdown(Duration d) {
  if (d.isNegative) return '0:00';
  final int m = d.inMinutes;
  final int s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

// =============================================================================
//  3. DOMAIN MODEL
//     Identity / state / telemetry / connectivity / capabilities / permissions
//     are modelled separately. Desired state is never confused with reported
//     state: `DeviceState.desired*` is what we asked for, `power/speed/mode`
//     is what the device actually reported back.
// =============================================================================

enum DeviceType { virtual, physical }

enum PowerState { on, off, unknown }

enum FanMode { manual, automatic }

enum ConnectivityStatus { connecting, online, offline, stale }

enum ReadingSource { simulated, physical }

enum MemberRole { owner, controller, viewer }

enum CommandStatus { pending, confirmed, rejected, timeout, offline, unsupported }

enum EventKind { command, state, pairing, membership, system }

extension DeviceTypeX on DeviceType {
  String get label => this == DeviceType.virtual ? 'Virtual' : 'Physical (ESP32)';
}

extension PowerStateX on PowerState {
  bool get isOn => this == PowerState.on;
  String get label => switch (this) {
        PowerState.on => 'ON',
        PowerState.off => 'OFF',
        PowerState.unknown => 'UNKNOWN',
      };
}

extension FanModeX on FanMode {
  String get label => this == FanMode.manual ? 'Manual' : 'Automatic';
}

extension ConnectivityX on ConnectivityStatus {
  String get label => switch (this) {
        ConnectivityStatus.connecting => 'Connecting',
        ConnectivityStatus.online => 'Online',
        ConnectivityStatus.offline => 'Offline',
        ConnectivityStatus.stale => 'Stale data',
      };
  Color get color => switch (this) {
        ConnectivityStatus.connecting => kInfo,
        ConnectivityStatus.online => kOk,
        ConnectivityStatus.offline => kDanger,
        ConnectivityStatus.stale => kWarn,
      };
  IconData get icon => switch (this) {
        ConnectivityStatus.connecting => Icons.hourglass_top_rounded,
        ConnectivityStatus.online => Icons.cloud_done_rounded,
        ConnectivityStatus.offline => Icons.cloud_off_rounded,
        ConnectivityStatus.stale => Icons.history_toggle_off_rounded,
      };
}

extension MemberRoleX on MemberRole {
  String get label => switch (this) {
        MemberRole.owner => 'Owner',
        MemberRole.controller => 'Controller',
        MemberRole.viewer => 'Viewer',
      };
  bool get canCommand => this != MemberRole.viewer;
  bool get canManage => this == MemberRole.owner;
}

/// Capabilities are per-device: the UI only shows speed when supported.
class Capabilities {
  const Capabilities({
    this.powerControl = true,
    this.speedControl = false,
    this.temperatureSensor = true,
    this.humiditySensor = true,
    this.automaticMode = true,
  });

  final bool powerControl;
  final bool speedControl;
  final bool temperatureSensor;
  final bool humiditySensor;
  final bool automaticMode;

  Capabilities copyWith({
    bool? powerControl,
    bool? speedControl,
    bool? temperatureSensor,
    bool? humiditySensor,
    bool? automaticMode,
  }) {
    return Capabilities(
      powerControl: powerControl ?? this.powerControl,
      speedControl: speedControl ?? this.speedControl,
      temperatureSensor: temperatureSensor ?? this.temperatureSensor,
      humiditySensor: humiditySensor ?? this.humiditySensor,
      automaticMode: automaticMode ?? this.automaticMode,
    );
  }
}

/// Humidity hysteresis settings. `offThreshold` must be < `onThreshold`.
class AutomationSettings {
  const AutomationSettings({
    this.onThreshold = 70,
    this.offThreshold = 60,
    this.minDwellSeconds = 20,
  });

  final double onThreshold;
  final double offThreshold;
  final int minDwellSeconds;

  AutomationSettings copyWith({double? onThreshold, double? offThreshold, int? minDwellSeconds}) {
    return AutomationSettings(
      onThreshold: onThreshold ?? this.onThreshold,
      offThreshold: offThreshold ?? this.offThreshold,
      minDwellSeconds: minDwellSeconds ?? this.minDwellSeconds,
    );
  }

  /// Returns a human-readable error, or null when valid.
  String? validate() {
    if (onThreshold.isNaN || offThreshold.isNaN) return 'Thresholds must be numbers.';
    if (onThreshold < 0 || onThreshold > 100 || offThreshold < 0 || offThreshold > 100) {
      return 'Thresholds must be between 0 and 100 %.';
    }
    if (offThreshold >= onThreshold) return 'OFF threshold must be lower than ON threshold.';
    if (minDwellSeconds < 0 || minDwellSeconds > 3600) return 'Dwell time must be 0–3600 s.';
    return null;
  }
}

class DeviceState {
  const DeviceState({
    required this.power,
    required this.mode,
    required this.automation,
    required this.revision,
    required this.updatedAt,
    this.speed,
    this.desiredPower,
    this.desiredSpeed,
    this.desiredMode,
    this.lastSwitchAt,
    this.automationReason,
  });

  /// Reported (confirmed) power state — this is what spins the animation.
  final PowerState power;
  final int? speed;
  final FanMode mode;

  final AutomationSettings automation;

  /// What the app asked for (may differ until the device acknowledges).
  final PowerState? desiredPower;
  final int? desiredSpeed;
  final FanMode? desiredMode;

  final DateTime? lastSwitchAt;
  final String? automationReason;

  /// Monotonic revision: consumers reject stale updates (rev < current).
  final int revision;
  final DateTime updatedAt;

  bool get hasPendingCommand =>
      (desiredPower != null && desiredPower != power) ||
      (desiredSpeed != null && desiredSpeed != speed) ||
      (desiredMode != null && desiredMode != mode);

  DeviceState copyWith({
    PowerState? power,
    Object? speed = _sentinel,
    FanMode? mode,
    AutomationSettings? automation,
    Object? desiredPower = _sentinel,
    Object? desiredSpeed = _sentinel,
    Object? desiredMode = _sentinel,
    Object? lastSwitchAt = _sentinel,
    Object? automationReason = _sentinel,
    int? revision,
    DateTime? updatedAt,
  }) {
    return DeviceState(
      power: power ?? this.power,
      speed: identical(speed, _sentinel) ? this.speed : speed as int?,
      mode: mode ?? this.mode,
      automation: automation ?? this.automation,
      desiredPower: identical(desiredPower, _sentinel) ? this.desiredPower : desiredPower as PowerState?,
      desiredSpeed: identical(desiredSpeed, _sentinel) ? this.desiredSpeed : desiredSpeed as int?,
      desiredMode: identical(desiredMode, _sentinel) ? this.desiredMode : desiredMode as FanMode?,
      lastSwitchAt: identical(lastSwitchAt, _sentinel) ? this.lastSwitchAt : lastSwitchAt as DateTime?,
      automationReason: identical(automationReason, _sentinel) ? this.automationReason : automationReason as String?,
      revision: revision ?? this.revision,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static const Object _sentinel = Object();

  factory DeviceState.initial() => DeviceState(
        power: PowerState.off,
        mode: FanMode.manual,
        automation: const AutomationSettings(),
        revision: 1,
        updatedAt: DateTime.now(),
      );
}

class DeviceReadings {
  const DeviceReadings({
    this.temperatureC,
    this.humidityPercent,
    this.source = ReadingSource.simulated,
    this.observedAt,
  });

  final double? temperatureC;
  final double? humidityPercent;
  final ReadingSource source;
  final DateTime? observedAt;

  static const DeviceReadings empty = DeviceReadings(source: ReadingSource.physical);

  bool get hasAny => temperatureC != null || humidityPercent != null;
}

class DeviceConnectivity {
  const DeviceConnectivity({this.status = ConnectivityStatus.offline, this.lastSeenAt, this.note});

  final ConnectivityStatus status;
  final DateTime? lastSeenAt;

  /// e.g. "ESP32 adapter not configured" — always visible, never hidden.
  final String? note;
}

class Device {
  const Device({
    required this.id,
    required this.ownerUserId,
    required this.name,
    required this.deviceType,
    required this.capabilities,
    required this.createdAt,
    this.room = '',
    this.firmware = '',
  });

  final String id;
  final String ownerUserId;
  final String name;
  final DeviceType deviceType;
  final Capabilities capabilities;
  final DateTime createdAt;
  final String room;
  final String firmware;

  String get shortId => id.length > 14 ? '${id.substring(0, 14)}…' : id;
}

/// Canonical view of a device — the single thing the UI renders.
class DeviceSnapshot {
  const DeviceSnapshot({
    required this.device,
    required this.state,
    required this.readings,
    required this.connectivity,
  });

  final Device device;
  final DeviceState state;
  final DeviceReadings readings;
  final DeviceConnectivity connectivity;

  bool get isSimulated => device.deviceType == DeviceType.virtual;
}

class Membership {
  const Membership({
    required this.id,
    required this.deviceId,
    required this.userId,
    required this.role,
    required this.createdAt,
    this.grantedVia = 'created',
  });

  final String id;
  final String deviceId;
  final String userId;
  final MemberRole role;
  final DateTime createdAt;
  final String grantedVia;
}

/// Stored pairing code. Only the hash is kept — the raw code is shown once.
class PairingCodeRecord {
  const PairingCodeRecord({
    required this.id,
    required this.deviceId,
    required this.codeHash,
    required this.salt,
    required this.createdAt,
    required this.expiresAt,
    required this.maxAttempts,
    required this.grantsRole,
    this.consumedAt,
    this.consumedByUserId,
    this.attempts = 0,
    this.createdByUserId = '',
  });

  final String id;
  final String deviceId;
  final String codeHash;
  final String salt;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int maxAttempts;
  final MemberRole grantsRole;
  final DateTime? consumedAt;
  final String? consumedByUserId;
  final int attempts;
  final String createdByUserId;

  bool get isConsumed => consumedAt != null;
  bool isExpired(DateTime now) => now.isAfter(expiresAt);
  bool isUsable(DateTime now) => !isConsumed && !isExpired(now) && attempts < maxAttempts;

  PairingCodeRecord copyWith({
    DateTime? consumedAt,
    String? consumedByUserId,
    int? attempts,
  }) {
    return PairingCodeRecord(
      id: id,
      deviceId: deviceId,
      codeHash: codeHash,
      salt: salt,
      createdAt: createdAt,
      expiresAt: expiresAt,
      maxAttempts: maxAttempts,
      grantsRole: grantsRole,
      createdByUserId: createdByUserId,
      consumedAt: consumedAt ?? this.consumedAt,
      consumedByUserId: consumedByUserId ?? this.consumedByUserId,
      attempts: attempts ?? this.attempts,
    );
  }
}

class DeviceEvent {
  const DeviceEvent({
    required this.id,
    required this.deviceId,
    required this.at,
    required this.kind,
    required this.message,
    this.actor = '',
    this.ok = true,
  });

  final String id;
  final String deviceId;
  final DateTime at;
  final EventKind kind;
  final String message;
  final String actor;
  final bool ok;
}

class CommandResult {
  const CommandResult({
    required this.commandId,
    required this.status,
    required this.message,
  });

  final String commandId;
  final CommandStatus status;
  final String message;

  bool get isSuccess => status == CommandStatus.confirmed;
}

/// Typed success/error result used across the service layer.
class ServiceResult<T> {
  const ServiceResult.ok(this.data, {this.message = ''}) : error = null;
  const ServiceResult.fail(this.error) : data = null, message = '';

  final T? data;
  final String? error;
  final String message;

  bool get ok => error == null;
}

/// Thrown when a caller is not allowed to perform an operation.
class PermissionException implements Exception {
  const PermissionException(this.message);
  final String message;

  @override
  String toString() => message;
}

// =============================================================================
//  4. AUTOMATION (pure) + SIMULATION ENGINE
//     No Flutter, no timers, no globals — deterministic and unit-testable.
// =============================================================================

class AutomationDecision {
  const AutomationDecision({this.desiredPower, required this.reason, required this.changed});

  /// null = keep the current power state (fail safe).
  final bool? desiredPower;
  final bool changed;
  final String reason;
}

/// Humidity-with-hysteresis decision function.
///
///  * ON  when humidity >= [onThreshold]
///  * OFF when humidity <= [offThreshold]
///  * between the thresholds -> hold previous state
///  * missing/stale readings or invalid thresholds -> hold (never guess)
///  * [minDwell] blocks a flip that would happen too soon after the last one
AutomationDecision evaluateAutomation({
  required double? humidityPercent,
  required bool currentPower,
  required double onThreshold,
  required double offThreshold,
  required Duration minDwell,
  required DateTime now,
  DateTime? observedAt,
  DateTime? lastSwitchAt,
  Duration staleAfter = const Duration(seconds: 45),
}) {
  // 1. Invalid thresholds -----------------------------------------------------
  final AutomationSettings candidate = AutomationSettings(
    onThreshold: onThreshold,
    offThreshold: offThreshold,
  );
  final String? invalid = candidate.validate();
  if (invalid != null) {
    return AutomationDecision(desiredPower: null, changed: false, reason: 'Hold — invalid thresholds ($invalid)');
  }

  // 2. Missing reading --------------------------------------------------------
  if (humidityPercent == null || humidityPercent.isNaN) {
    return AutomationDecision(desiredPower: null, changed: false, reason: 'Hold — no humidity reading');
  }

  // 3. Stale reading: never act on data we cannot trust -----------------------
  if (observedAt == null || now.difference(observedAt) > staleAfter) {
    return AutomationDecision(desiredPower: null, changed: false, reason: 'Hold — humidity reading is stale');
  }

  // 4. Hysteresis -------------------------------------------------------------
  bool? wanted;
  String why;
  if (humidityPercent >= onThreshold) {
    wanted = true;
    why = 'Humidity ${humidityPercent.toStringAsFixed(0)}% ≥ ON ${onThreshold.toStringAsFixed(0)}%';
  } else if (humidityPercent <= offThreshold) {
    wanted = false;
    why = 'Humidity ${humidityPercent.toStringAsFixed(0)}% ≤ OFF ${offThreshold.toStringAsFixed(0)}%';
  } else {
    return AutomationDecision(
      desiredPower: null,
      changed: false,
      reason: 'Hold — ${humidityPercent.toStringAsFixed(0)}% is between OFF ${offThreshold.toStringAsFixed(0)}% and ON ${onThreshold.toStringAsFixed(0)}%',
    );
  }

  if (wanted == currentPower) {
    return AutomationDecision(desiredPower: null, changed: false, reason: 'Hold — already ${wanted ? 'ON' : 'OFF'} ($why)');
  }

  // 5. Minimum dwell time (anti short-cycling) --------------------------------
  if (lastSwitchAt != null && minDwell > Duration.zero && now.difference(lastSwitchAt) < minDwell) {
    final int left = (minDwell - now.difference(lastSwitchAt)).inSeconds;
    return AutomationDecision(desiredPower: null, changed: false, reason: 'Hold — dwell time (${left}s left) before switching');
  }

  return AutomationDecision(desiredPower: wanted, changed: true, reason: '$why → turn ${wanted ? 'ON' : 'OFF'}');
}

/// Demo "room environment" the simulation drifts towards (virtual devices only).
class VirtualEnvironment {
  const VirtualEnvironment({this.targetTemperatureC = 26.5, this.targetHumidityPercent = 68});

  final double targetTemperatureC;
  final double targetHumidityPercent;

  VirtualEnvironment copyWith({double? targetTemperatureC, double? targetHumidityPercent}) => VirtualEnvironment(
        targetTemperatureC: targetTemperatureC ?? this.targetTemperatureC,
        targetHumidityPercent: targetHumidityPercent ?? this.targetHumidityPercent,
      );
}

class SimulationEngine {
  const SimulationEngine();

  /// One deterministic-ish step. `dt` is elapsed time, `rnd` keeps it lively
  /// but the physics stays trivial on purpose (no fake precision).
  DeviceReadings step({
    required DeviceReadings previous,
    required bool powerOn,
    required int speedPercent,
    required VirtualEnvironment env,
    required Duration dt,
    math.Random? rnd,
  }) {
    final math.Random r = rnd ?? _driftRnd;
    final double minutes = dt.inMilliseconds / 60000.0;

    // Baseline: a damp room that drifts towards the configured environment.
    double? humidity = previous.humidityPercent ?? env.targetHumidityPercent;
    double? temperature = previous.temperatureC ?? env.targetTemperatureC;

    // Ventilation removes moisture; the room slowly regains it when off.
    final double ventRate = powerOn ? (1.6 + speedPercent * 0.045) : 0.0;
    final double regain = (env.targetHumidityPercent - humidity) * 0.22;
    humidity = humidity + (regain - ventRate) * minutes + (r.nextDouble() - 0.5) * 0.08;
    humidity = humidity.clamp(5.0, 99.0);

    // Temperature eases towards target, a touch cooler while ventilating.
    final double target = env.targetTemperatureC - (powerOn ? 0.9 : 0.0);
    temperature = temperature + (target - temperature) * 0.18 * minutes + (r.nextDouble() - 0.5) * 0.03;
    temperature = temperature.clamp(-10.0, 60.0);

    return DeviceReadings(
      temperatureC: double.parse(temperature.toStringAsFixed(2)),
      humidityPercent: double.parse(humidity.toStringAsFixed(2)),
      source: ReadingSource.simulated,
      observedAt: DateTime.now(),
    );
  }
}

// =============================================================================
//  5. DEVICE ABSTRACTION LAYER
//     One contract, two implementations. The UI and services never know which
//     one they are talking to. The ESP32 adapter is an honest stub: it reports
//     "not configured" instead of pretending a motor turned.
// =============================================================================

class DeviceCommand {
  const DeviceCommand({
    required this.commandId,
    required this.device,
    required this.current,
    this.power,
    this.speed,
    this.mode,
  });

  final String commandId;
  final Device device;
  final DeviceState current;
  final PowerState? power;
  final int? speed;
  final FanMode? mode;
}

class AdapterAck {
  const AdapterAck({
    required this.status,
    required this.power,
    required this.mode,
    this.speed,
    this.message = '',
  });

  final CommandStatus status;
  final PowerState power;
  final int? speed;
  final FanMode mode;
  final String message;
}

class AdapterReadings {
  const AdapterReadings({this.readings, this.message = ''});

  final DeviceReadings? readings;
  final String message;
}

class AdapterHealth {
  const AdapterHealth({required this.status, required this.note, this.lastSeenAt, this.firmware = ''});

  final ConnectivityStatus status;
  final String note;
  final DateTime? lastSeenAt;
  final String firmware;
}

abstract class FanDeviceAdapter {
  DeviceType get type;
  String get label;

  Future<AdapterAck> applyCommand(DeviceCommand command);
  Future<AdapterReadings> readSensors(Device device);
  Future<AdapterHealth> health(Device device);
}

/// Simulated fan: echoes the desired state back as *reported* state.
/// Every reading it produces is tagged `ReadingSource.simulated`.
class VirtualFanAdapter implements FanDeviceAdapter {
  VirtualFanAdapter({required this.latency, required this.shouldFail});

  final Duration Function() latency;
  final bool Function() shouldFail;

  @override
  DeviceType get type => DeviceType.virtual;

  @override
  String get label => 'Virtual fan simulator';

  @override
  Future<AdapterAck> applyCommand(DeviceCommand command) async {
    await Future<void>.delayed(latency());
    if (shouldFail()) {
      return AdapterAck(
        status: CommandStatus.rejected,
        power: command.current.power,
        speed: command.current.speed,
        mode: command.current.mode,
        message: 'Virtual device rejected the command (failure injection is ON)',
      );
    }
    if (!command.device.capabilities.powerControl && command.power != null) {
      return AdapterAck(
        status: CommandStatus.unsupported,
        power: command.current.power,
        speed: command.current.speed,
        mode: command.current.mode,
        message: 'This device does not support power control',
      );
    }
    if (command.speed != null && !command.device.capabilities.speedControl) {
      return AdapterAck(
        status: CommandStatus.unsupported,
        power: command.current.power,
        speed: command.current.speed,
        mode: command.current.mode,
        message: 'This device does not support speed control',
      );
    }
    if (command.mode == FanMode.automatic && !command.device.capabilities.automaticMode) {
      return AdapterAck(
        status: CommandStatus.unsupported,
        power: command.current.power,
        speed: command.current.speed,
        mode: command.current.mode,
        message: 'This device does not support automatic mode',
      );
    }
    return AdapterAck(
      status: CommandStatus.confirmed,
      power: command.power ?? command.current.power,
      speed: command.speed ?? command.current.speed,
      mode: command.mode ?? command.current.mode,
      message: 'Simulated device acknowledged',
    );
  }

  @override
  Future<AdapterReadings> readSensors(Device device) async {
    // Readings are produced by the simulation engine in the backend tick loop;
    // this adapter only guarantees they are always labelled as simulated.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return const AdapterReadings(message: 'Simulated sensors');
  }

  @override
  Future<AdapterHealth> health(Device device) async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    return AdapterHealth(
      status: ConnectivityStatus.online,
      note: 'Simulated device — no hardware is involved',
      lastSeenAt: DateTime.now(),
      firmware: 'virtual-1.0.0',
    );
  }
}

/// ESP32 adapter stub (Phase 4 readiness).
/// Returns "not configured" for everything until a genuine, authenticated
/// device connection exists. It never invents readings and never confirms a
/// command it did not receive an acknowledgement for.
class Esp32FanAdapter implements FanDeviceAdapter {
  const Esp32FanAdapter({this.baseUrl = '', this.deviceSecretConfigured = false});

  /// e.g. https://gateway.local/device/airorhythm-01
  final String baseUrl;

  /// True only once a real provisioning flow has stored device credentials on
  /// a trusted server (never in app code).
  final bool deviceSecretConfigured;

  bool get isConfigured => baseUrl.isNotEmpty && deviceSecretConfigured;

  @override
  DeviceType get type => DeviceType.physical;

  @override
  String get label => 'ESP32 (not configured)';

  @override
  Future<AdapterAck> applyCommand(DeviceCommand command) async {
    if (!isConfigured) {
      return AdapterAck(
        status: CommandStatus.unsupported,
        power: PowerState.unknown,
        speed: null,
        mode: command.current.mode,
        message: 'ESP32 adapter not configured — no authenticated device connection',
      );
    }
    // Real implementation (see docs/API-CONTRACT.md):
    //   POST {baseUrl}/api/v1/commands  {commandId, desiredPower, desiredSpeed,
    //         desiredMode, expiresAt, hmac}
    //   → 202 {accepted:true} then wait for telemetry/ack with matching commandId.
    //   Timeout → CommandStatus.timeout ("Unconfirmed"), never "Success".
    return AdapterAck(
      status: CommandStatus.timeout,
      power: PowerState.unknown,
      speed: null,
      mode: command.current.mode,
      message: 'No acknowledgement from device (unconfirmed)',
    );
  }

  @override
  Future<AdapterReadings> readSensors(Device device) async {
    // Returning null here is deliberate: the UI must show "no data" rather
    // than fall back to simulated values for a physical device.
    return const AdapterReadings(readings: null, message: 'No authenticated telemetry');
  }

  @override
  Future<AdapterHealth> health(Device device) async {
    return AdapterHealth(
      status: isConfigured ? ConnectivityStatus.offline : ConnectivityStatus.offline,
      note: isConfigured
          ? 'Awaiting first authenticated telemetry from the ESP32'
          : 'ESP32 adapter not configured — provision the device first',
      lastSeenAt: null,
      firmware: device.firmware.isEmpty ? 'unknown' : device.firmware,
    );
  }
}

// =============================================================================
//  6. BACKEND / REPOSITORY + REALTIME ("sync bus")
//     Everything below this line is provider-agnostic: replace DemoBackend with
//     a Supabase/REST implementation of `DeviceRepository` and the UI, services
//     and adapters stay untouched.
// =============================================================================

abstract class DeviceRepository {
  Future<DeviceSnapshot?> snapshot(String deviceId);
  Stream<DeviceSnapshot> watch(String deviceId);
  Future<Device> createDevice({
    required String ownerUserId,
    required String name,
    required DeviceType type,
    required Capabilities capabilities,
    String room,
  });
  Future<void> deleteDevice(String deviceId);
  List<Device> devicesForUser(String userId);
  List<Membership> membershipsForDevice(String deviceId);
  List<Membership> membershipsForUser(String userId);
  Future<void> addMembership(Membership m);
  Future<void> revokeMembership(String membershipId);
  List<DeviceEvent> eventsFor(String deviceId);
  Future<void> addEvent(DeviceEvent e);
  Future<void> commitState(String deviceId, DeviceState state, {String? reason});
  List<PairingCodeRecord> codesFor(String deviceId);
}

/// Demo knobs, normally server-side configuration.
class DemoSettings {
  DemoSettings({
    this.roundTripMs = 420,
    this.commandTimeoutMs = 4000,
    this.tickSeconds = 2,
    this.pairingExpirySeconds = 180,
    this.maxCodeAttempts = 5,
    this.injectFailures = false,
    this.failureRate = 0.35,
  });

  int roundTripMs;
  int commandTimeoutMs;
  int tickSeconds;
  int pairingExpirySeconds;
  int maxCodeAttempts;
  bool injectFailures;
  double failureRate;

  Duration get staleAfter => Duration(seconds: (tickSeconds * 4).clamp(8, 60));
}

class DemoBackend implements DeviceRepository {
  DemoBackend({DemoSettings? settings}) : settings = settings ?? DemoSettings() {
    _seed();
  }

  final DemoSettings settings;

  final Map<String, Device> _devices = <String, Device>{};
  final Map<String, DeviceState> _states = <String, DeviceState>{};
  final Map<String, DeviceReadings> _readings = <String, DeviceReadings>{};
  final Map<String, DeviceConnectivity> _conn = <String, DeviceConnectivity>{};
  final Map<String, VirtualEnvironment> _env = <String, VirtualEnvironment>{};
  final Map<String, DateTime> _lastEmit = <String, DateTime>{};
  final List<Membership> _memberships = <Membership>[];
  final List<PairingCodeRecord> _codes = <PairingCodeRecord>[];
  final List<DeviceEvent> _events = <DeviceEvent>[];
  final Set<String> _pendingDevices = <String>{};

  final StreamController<DeviceSnapshot> _bus = StreamController<DeviceSnapshot>.broadcast();
  final SimulationEngine _engine = const SimulationEngine();
  final math.Random _noise = math.Random();
  Timer? _timer;
  DateTime _lastTick = DateTime.now();

  // -- adapters ---------------------------------------------------------------
  VirtualFanAdapter? _virtualAdapter;
  Esp32FanAdapter? _esp32Adapter;

  void attachAdapters({required VirtualFanAdapter virtual, required Esp32FanAdapter esp32}) {
    _virtualAdapter = virtual;
    _esp32Adapter = esp32;
  }

  FanDeviceAdapter adapterFor(DeviceType type) =>
      type == DeviceType.virtual ? _virtualAdapter! : _esp32Adapter!;

  // -- lifecycle --------------------------------------------------------------
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: settings.tickSeconds), (_) => tick());
  }

  void restartTicker() {
    start();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _bus.close();
  }

  // -- seeding (demo data, clearly labelled) ---------------------------------
  void _seed() {
    // Owner + one ready-made virtual fan so the app is usable immediately.
    final String owner = 'usr-demo';
    final String id = 'dev-bedroom';
    final Device device = Device(
      id: id,
      ownerUserId: owner,
      name: 'Bedroom Ventilation',
      deviceType: DeviceType.virtual,
      capabilities: const Capabilities(speedControl: true),
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
      room: 'Bedroom',
      firmware: 'virtual-1.0.0',
    );
    _devices[id] = device;
    _states[id] = DeviceState.initial().copyWith(
      automation: const AutomationSettings(onThreshold: 70, offThreshold: 60, minDwellSeconds: 20),
    );
    _readings[id] = DeviceReadings(
      temperatureC: 26.4,
      humidityPercent: 66,
      source: ReadingSource.simulated,
      observedAt: DateTime.now(),
    );
    _conn[id] = DeviceConnectivity(status: ConnectivityStatus.online, lastSeenAt: DateTime.now());
    _env[id] = const VirtualEnvironment(targetTemperatureC: 26.5, targetHumidityPercent: 68);
    _memberships.add(Membership(
      id: newId('mem'),
      deviceId: id,
      userId: owner,
      role: MemberRole.owner,
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
      grantedVia: 'created',
    ));
    _addEvent(DeviceEvent(
      id: newId('evt'),
      deviceId: id,
      at: DateTime.now().subtract(const Duration(days: 3)),
      kind: EventKind.system,
      message: 'Virtual device created (demo seed)',
      actor: 'demo@airorhythm.app',
    ));
  }

  // -- reads ------------------------------------------------------------------
  DeviceSnapshot? snapshotSync(String deviceId) {
    final Device? d = _devices[deviceId];
    if (d == null) return null;
    return DeviceSnapshot(
      device: d,
      state: _states[deviceId]!,
      readings: _readings[deviceId] ?? const DeviceReadings(),
      connectivity: effectiveConnectivity(deviceId),
    );
  }

  @override
  Future<DeviceSnapshot?> snapshot(String deviceId) async => snapshotSync(deviceId);

  DeviceConnectivity effectiveConnectivity(String deviceId) {
    final DeviceConnectivity c = _conn[deviceId] ?? const DeviceConnectivity();
    if (c.status == ConnectivityStatus.offline || c.status == ConnectivityStatus.connecting) {
      return c;
    }
    final DateTime? seen = c.lastSeenAt;
    if (seen == null) {
      return DeviceConnectivity(status: ConnectivityStatus.offline, note: c.note ?? 'No telemetry received yet');
    }
    if (DateTime.now().difference(seen) > settings.staleAfter) {
      return DeviceConnectivity(status: ConnectivityStatus.stale, lastSeenAt: seen, note: c.note);
    }
    return c;
  }

  @override
  Stream<DeviceSnapshot> watch(String deviceId) =>
      _bus.stream.where((DeviceSnapshot s) => s.device.id == deviceId);

  @override
  Future<Device> createDevice({
    required String ownerUserId,
    required String name,
    required DeviceType type,
    required Capabilities capabilities,
    String room = '',
  }) async {
    final String id = newId(type == DeviceType.virtual ? 'dev' : 'esp');
    final Device device = Device(
      id: id,
      ownerUserId: ownerUserId,
      name: name,
      deviceType: type,
      capabilities: capabilities,
      createdAt: DateTime.now(),
      room: room,
      firmware: type == DeviceType.virtual ? 'virtual-1.0.0' : '',
    );
    _devices[id] = device;
    _states[id] = DeviceState.initial().copyWith(speed: capabilities.speedControl ? 60 : null);
    _env[id] = const VirtualEnvironment();

    if (type == DeviceType.virtual) {
      _readings[id] = DeviceReadings(
        temperatureC: 26.0,
        humidityPercent: 65,
        source: ReadingSource.simulated,
        observedAt: DateTime.now(),
      );
      _conn[id] = DeviceConnectivity(status: ConnectivityStatus.online, lastSeenAt: DateTime.now());
    } else {
      // Physical device: no readings, not online. Ever. Until it reports.
      _readings[id] = const DeviceReadings();
      _conn[id] = const DeviceConnectivity(
        status: ConnectivityStatus.offline,
        note: 'Awaiting provisioning — ESP32 adapter not configured',
      );
    }
    _memberships.add(Membership(
      id: newId('mem'),
      deviceId: id,
      userId: ownerUserId,
      role: MemberRole.owner,
      createdAt: DateTime.now(),
      grantedVia: 'created',
    ));
    _addEvent(DeviceEvent(
      id: newId('evt'),
      deviceId: id,
      at: DateTime.now(),
      kind: EventKind.system,
      message: '${type == DeviceType.virtual ? 'Virtual' : 'Physical'} device created',
    ));
    emit(id);
    return device;
  }

  @override
  Future<void> deleteDevice(String deviceId) async {
    _devices.remove(deviceId);
    _states.remove(deviceId);
    _readings.remove(deviceId);
    _conn.remove(deviceId);
    _env.remove(deviceId);
    _memberships.removeWhere((Membership m) => m.deviceId == deviceId);
    _codes.removeWhere((PairingCodeRecord c) => c.deviceId == deviceId);
  }

  @override
  List<Device> devicesForUser(String userId) {
    final List<String> ids = _memberships
        .where((Membership m) => m.userId == userId)
        .map((Membership m) => m.deviceId)
        .toSet()
        .toList();
    final List<Device> out = <Device>[];
    for (final String id in ids) {
      final Device? d = _devices[id];
      if (d != null) out.add(d);
    }
    out.sort((Device a, Device b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  List<String> allDeviceIds() => _devices.keys.toList();

  @override
  List<Membership> membershipsForDevice(String deviceId) =>
      _memberships.where((Membership m) => m.deviceId == deviceId).toList();

  @override
  List<Membership> membershipsForUser(String userId) =>
      _memberships.where((Membership m) => m.userId == userId).toList();

  @override
  Future<void> addMembership(Membership m) async {
    _memberships.add(m);
  }

  @override
  Future<void> revokeMembership(String membershipId) async {
    _memberships.removeWhere((Membership m) => m.id == membershipId);
  }

  @override
  List<DeviceEvent> eventsFor(String deviceId) =>
      _events.where((DeviceEvent e) => e.deviceId == deviceId).toList().reversed.toList();

  @override
  Future<void> addEvent(DeviceEvent e) async => _addEvent(e);

  void _addEvent(DeviceEvent e) {
    _events.add(e);
    // Bounded history.
    while (_events.length > 300) {
      _events.removeAt(0);
    }
  }

  // -- state ------------------------------------------------------------------
  DeviceState stateOf(String deviceId) => _states[deviceId]!;

  Future<void> applyDesired(String deviceId, DeviceState desired) async {
    _states[deviceId] = desired;
    _pendingDevices.add(deviceId);
    emit(deviceId);
  }

  @override
  Future<void> commitState(String deviceId, DeviceState state, {String? reason}) async {
    _states[deviceId] = state;
    _pendingDevices.remove(deviceId);
    emit(deviceId);
  }

  bool isPending(String deviceId) => _pendingDevices.contains(deviceId);

  DeviceReadings readingsOf(String deviceId) => _readings[deviceId] ?? const DeviceReadings();

  VirtualEnvironment envOf(String deviceId) => _env[deviceId] ?? const VirtualEnvironment();

  Future<void> setEnvironment(String deviceId, VirtualEnvironment env) async {
    _env[deviceId] = env;
  }

  /// Demo control: move a simulated reading immediately (virtual devices only).
  Future<void> nudgeReading(String deviceId, {double humidityDelta = 0, double temperatureDelta = 0}) async {
    final Device? d = _devices[deviceId];
    if (d == null || d.deviceType != DeviceType.virtual) return; // never for hardware
    final DeviceReadings r = readingsOf(deviceId);
    _readings[deviceId] = DeviceReadings(
      temperatureC: (r.temperatureC ?? 26) + temperatureDelta,
      humidityPercent: (((r.humidityPercent ?? 65) + humidityDelta).clamp(0.0, 100.0)),
      source: ReadingSource.simulated,
      observedAt: DateTime.now(),
    );
    final VirtualEnvironment e = envOf(deviceId);
    _env[deviceId] = e.copyWith(
      targetHumidityPercent: (e.targetHumidityPercent + humidityDelta).clamp(5.0, 99.0),
      targetTemperatureC: (e.targetTemperatureC + temperatureDelta).clamp(-5.0, 55.0),
    );
    emit(deviceId);
  }

  // -- pairing codes ----------------------------------------------------------
  @override
  List<PairingCodeRecord> codesFor(String deviceId) =>
      _codes.where((PairingCodeRecord c) => c.deviceId == deviceId).toList();

  Future<PairingCodeRecord> storeCode(PairingCodeRecord c) async {
    _codes.add(c);
    return c;
  }

  Future<void> updateCode(PairingCodeRecord updated) async {
    final int i = _codes.indexWhere((PairingCodeRecord c) => c.id == updated.id);
    if (i >= 0) _codes[i] = updated;
  }

  Future<void> revokeCodesFor(String deviceId) async {
    final DateTime now = DateTime.now();
    for (int i = 0; i < _codes.length; i++) {
      if (_codes[i].deviceId == deviceId && _codes[i].consumedAt == null) {
        _codes[i] = _codes[i].copyWith(consumedAt: now);
      }
    }
  }

  // -- tick loop (simulation + automation live here, not in the UI) ----------
  void tick() {
    final DateTime now = DateTime.now();
    final Duration dt = now.difference(_lastTick);
    _lastTick = now;
    for (final Device d in _devices.values) {
      if (d.deviceType == DeviceType.virtual) {
        _tickVirtual(d, now, dt);
      } else {
        _tickPhysical(d, now);
      }
    }
  }

  void _tickVirtual(Device d, DateTime now, Duration dt) {
    final DeviceState s = _states[d.id]!;
    final DeviceReadings prev = _readings[d.id] ?? const DeviceReadings();
    final DeviceReadings next = _engine.step(
      previous: prev,
      powerOn: s.power == PowerState.on,
      speedPercent: s.speed ?? 60,
      env: _env[d.id] ?? const VirtualEnvironment(),
      dt: dt,
      rnd: _noise,
    );
    _readings[d.id] = next;

    DeviceState out = s;
    if (s.mode == FanMode.automatic && d.capabilities.automaticMode) {
      final AutomationDecision dec = evaluateAutomation(
        humidityPercent: next.humidityPercent,
        currentPower: s.power == PowerState.on,
        onThreshold: s.automation.onThreshold,
        offThreshold: s.automation.offThreshold,
        minDwell: Duration(seconds: s.automation.minDwellSeconds),
        observedAt: next.observedAt,
        lastSwitchAt: s.lastSwitchAt,
        now: now,
      );
      out = out.copyWith(automationReason: dec.reason);
      if (dec.desiredPower != null) {
        out = out.copyWith(
          power: dec.desiredPower! ? PowerState.on : PowerState.off,
          desiredPower: dec.desiredPower! ? PowerState.on : PowerState.off,
          lastSwitchAt: now,
          revision: s.revision + 1,
          updatedAt: now,
        );
        _addEvent(DeviceEvent(
          id: newId('evt'),
          deviceId: d.id,
          at: now,
          kind: EventKind.state,
          message: 'Automation (simulated): turned ${dec.desiredPower! ? 'ON' : 'OFF'} — ${dec.reason}',
          actor: 'automation',
        ));
      }
    }
    _states[d.id] = out;
    _conn[d.id] = DeviceConnectivity(status: ConnectivityStatus.online, lastSeenAt: now);
    _emitThrottled(d.id, now, changed: true);
  }

  /// Physical devices get NO invented data: their connectivity is derived
  /// purely from authenticated telemetry (which the stub never produces).
  void _tickPhysical(Device d, DateTime now) {
    final DeviceConnectivity c = _conn[d.id] ?? const DeviceConnectivity();
    final bool configured = _esp32Adapter?.isConfigured ?? false;
    _conn[d.id] = DeviceConnectivity(
      status: ConnectivityStatus.offline,
      lastSeenAt: c.lastSeenAt,
      note: configured
          ? 'Awaiting first authenticated telemetry from the ESP32'
          : 'ESP32 adapter not configured — provision the device first',
    );
  }

  void emit(String deviceId) => _emitThrottled(deviceId, DateTime.now(), changed: true);

  void _emitThrottled(String deviceId, DateTime now, {required bool changed}) {
    final Device? d = _devices[deviceId];
    if (d == null) return;
    final DateTime? last = _lastEmit[deviceId];
    if (!changed && last != null && now.difference(last) < const Duration(seconds: 4)) return;
    _lastEmit[deviceId] = now;
    if (_bus.isClosed) return;
    _bus.add(snapshotSync(deviceId)!);
  }
}

// =============================================================================
//  7. AUTH SERVICE (demo stand-in for Supabase Auth)
//     Sessions represent *signed-in devices*. Switching session in Settings is
//     the same as opening AiroRhythm on another phone/laptop.
// =============================================================================

class UserAccount {
  const UserAccount({
    required this.id,
    required this.email,
    required this.displayName,
    required this.salt,
    required this.passwordHash,
  });

  final String id;
  final String email;
  final String displayName;
  final String salt;
  final String passwordHash;
}

class Session {
  Session({
    required this.token,
    required this.userId,
    required this.deviceLabel,
    required this.createdAt,
  }) : lastSeenAt = createdAt;

  final String token;
  final String userId;
  final String deviceLabel;
  final DateTime createdAt;
  DateTime lastSeenAt;
}

class AuthService {
  AuthService() {
    _seedDemoUser();
  }

  final Map<String, UserAccount> _users = <String, UserAccount>{};
  final Map<String, Session> _sessions = <String, Session>{};
  final Map<String, List<DateTime>> _failedAttempts = <String, List<DateTime>>{};
  int _deviceLabelCursor = 0;

  static const List<String> _deviceLabels = <String>[
    'Laptop · Chrome',
    'Phone · Android',
    'Phone · iOS',
    'Tablet · iPadOS',
    'Desktop · Safari',
  ];

  void _seedDemoUser() {
    const String salt = 'demo-salt-airorhythm';
    _users['usr-demo'] = const UserAccount(
      id: 'usr-demo',
      email: 'demo@airorhythm.app',
      displayName: 'Demo User',
      salt: salt,
      passwordHash: '4c0d3a6ffd5fd9b7b6a0c9f24c4dbcb0e3b2a1d0e9f8c7b6a5d4e3f2c1b0a9f8', // replaced below
    );
    // Compute the real hash at runtime so the demo credentials stay correct.
    _users['usr-demo'] = UserAccount(
      id: 'usr-demo',
      email: 'demo@airorhythm.app',
      displayName: 'Demo User',
      salt: salt,
      passwordHash: Sha256.salted(salt, 'demo1234'),
    );
  }

  String nextDeviceLabel() {
    final String label = _deviceLabels[_deviceLabelCursor % _deviceLabels.length];
    _deviceLabelCursor++;
    return label;
  }

  List<UserAccount> get users => _users.values.toList();

  UserAccount? user(String id) => _users[id];

  UserAccount? byEmail(String email) {
    final String e = email.trim().toLowerCase();
    for (final UserAccount u in _users.values) {
      if (u.email == e) return u;
    }
    return null;
  }

  Session? session(String? token) {
    if (token == null) return null;
    final Session? s = _sessions[token];
    if (s != null) s.lastSeenAt = DateTime.now();
    return s;
  }

  List<Session> sessionsFor(String userId) =>
      _sessions.values.where((Session s) => s.userId == userId).toList();

  void signOut(String token) => _sessions.remove(token);

  bool _rateLimited(String email) {
    final List<DateTime>? attempts = _failedAttempts[email.trim().toLowerCase()];
    if (attempts == null) return false;
    final DateTime cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    attempts.removeWhere((DateTime t) => t.isBefore(cutoff));
    return attempts.length >= 5;
  }

  void _noteFailure(String email) {
    final String e = email.trim().toLowerCase();
    _failedAttempts.putIfAbsent(e, () => <DateTime>[]).add(DateTime.now());
  }

  Future<ServiceResult<Session>> signIn({required String email, required String password, String? deviceLabel}) async {
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (_rateLimited(email)) {
      return const ServiceResult<Session>.fail('Too many failed attempts. Try again in a few minutes.');
    }
    final UserAccount? u = byEmail(email);
    if (u == null || password.length < 6) {
      _noteFailure(email);
      return const ServiceResult<Session>.fail('Incorrect email or password.');
    }
    if (Sha256.salted(u.salt, password) != u.passwordHash) {
      _noteFailure(email);
      return const ServiceResult<Session>.fail('Incorrect email or password.');
    }
    _failedAttempts.remove(email.trim().toLowerCase());
    return ServiceResult<Session>.ok(_issue(u.id, deviceLabel));
  }

  Future<ServiceResult<Session>> signUp({
    required String email,
    required String password,
    required String displayName,
    String? deviceLabel,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final String e = email.trim().toLowerCase();
    if (!e.contains('@') || e.startsWith('@')) {
      return const ServiceResult<Session>.fail('Enter a valid email address.');
    }
    if (password.length < 8) {
      return const ServiceResult<Session>.fail('Password must be at least 8 characters.');
    }
    if (displayName.trim().isEmpty) {
      return const ServiceResult<Session>.fail('Enter your name.');
    }
    if (byEmail(e) != null) {
      return const ServiceResult<Session>.fail('An account with that email already exists.');
    }
    final String id = newId('usr');
    final String salt = newId('salt');
    _users[id] = UserAccount(
      id: id,
      email: e,
      displayName: displayName.trim(),
      salt: salt,
      passwordHash: Sha256.salted(salt, password),
    );
    return ServiceResult<Session>.ok(_issue(id, deviceLabel));
  }

  Session _issue(String userId, String? deviceLabel) {
    final Session s = Session(
      token: newId('ses'),
      userId: userId,
      deviceLabel: deviceLabel ?? nextDeviceLabel(),
      createdAt: DateTime.now(),
    );
    _sessions[s.token] = s;
    return s;
  }
}

// =============================================================================
//  8. APPLICATION / SERVICE LAYER
//     fanService: device selection, commands, permissions, state transitions.
//     pairingService: short-lived codes, memberships, revocation.
//     These are the ONLY things the UI is allowed to call.
// =============================================================================

class PairingCodeOffer {
  const PairingCodeOffer({required this.code, required this.record});

  /// "K7M2QX" -> "K7M 2QX" for readability.
  String get formatted =>
      code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;

  /// Raw code — shown once, never stored in plain text by the backend.
  final String code;
  final PairingCodeRecord record;
}

class FanService {
  FanService({required this.backend, required this.auth, this.onChanged});

  final DemoBackend backend;
  final AuthService auth;
  final VoidCallback? onChanged;

  final Map<String, DateTime> _lastCommandAt = <String, DateTime>{};

  bool isPending(String deviceId) => backend.isPending(deviceId);

  MemberRole? roleFor(String deviceId, String userId) {
    for (final Membership m in backend.membershipsForDevice(deviceId)) {
      if (m.userId == userId) return m.role;
    }
    return null;
  }

  List<Membership> members(String deviceId) => backend.membershipsForDevice(deviceId);

  void _changed() => onChanged?.call();

  // -- creation ---------------------------------------------------------------
  Future<ServiceResult<Device>> createVirtualFan({
    required String userId,
    required String name,
    String room = '',
    Capabilities capabilities = const Capabilities(speedControl: true),
  }) async {
    final String clean = name.trim();
    if (clean.length < 2) return const ServiceResult<Device>.fail('Give the fan a name (2+ characters).');
    final Device d = await backend.createDevice(
      ownerUserId: userId,
      name: clean,
      type: DeviceType.virtual,
      capabilities: capabilities,
      room: room.trim(),
    );
    await backend.addEvent(DeviceEvent(
      id: newId('evt'),
      deviceId: d.id,
      at: DateTime.now(),
      kind: EventKind.system,
      message: 'Virtual fan "$clean" created',
      actor: userId,
    ));
    _changed();
    return ServiceResult<Device>.ok(d);
  }

  /// Physical devices are *provisioned*, never converted from a virtual record.
  Future<ServiceResult<Device>> provisionPhysicalFan({
    required String userId,
    required String name,
    String room = '',
    Capabilities capabilities = const Capabilities(speedControl: false),
  }) async {
    final String clean = name.trim();
    if (clean.length < 2) return const ServiceResult<Device>.fail('Give the device a name (2+ characters).');
    final Device d = await backend.createDevice(
      ownerUserId: userId,
      name: clean,
      type: DeviceType.physical,
      capabilities: capabilities,
      room: room.trim(),
    );
    await backend.addEvent(DeviceEvent(
      id: newId('evt'),
      deviceId: d.id,
      at: DateTime.now(),
      kind: EventKind.system,
      message: 'Physical device provisioned — awaiting ESP32 connection (no data will be simulated)',
      actor: userId,
    ));
    _changed();
    return ServiceResult<Device>.ok(d);
  }

  Future<void> deleteDevice(String deviceId, String userId) async {
    if (roleFor(deviceId, userId) != MemberRole.owner) {
      throw const PermissionException('Only the owner can delete this device.');
    }
    await backend.deleteDevice(deviceId);
    _changed();
  }

  // -- commands ---------------------------------------------------------------
  Future<CommandResult> setPower(String deviceId, String userId, bool on) =>
      _dispatch(deviceId: deviceId, userId: userId, power: on ? PowerState.on : PowerState.off, verb: on ? 'Turn ON' : 'Turn OFF');

  Future<CommandResult> setSpeed(String deviceId, String userId, int percent) =>
      _dispatch(deviceId: deviceId, userId: userId, speed: percent.clamp(0, 100), verb: 'Set speed $percent%');

  Future<CommandResult> setMode(String deviceId, String userId, FanMode mode) =>
      _dispatch(deviceId: deviceId, userId: userId, mode: mode, verb: 'Set ${mode.label} mode');

  Future<CommandResult> refresh(String deviceId, String userId) async {
    final DeviceSnapshot? snap = backend.snapshotSync(deviceId);
    if (snap == null) return CommandResult(commandId: newId('cmd'), status: CommandStatus.rejected, message: 'Device not found.');
    if (roleFor(deviceId, userId) == null) {
      return CommandResult(commandId: newId('cmd'), status: CommandStatus.rejected, message: 'You do not have access to this device.');
    }
    final FanDeviceAdapter adapter = backend.adapterFor(snap.device.deviceType);
    final AdapterHealth health = await adapter.health(snap.device);
    if (snap.device.deviceType == DeviceType.virtual) {
      await backend.commitState(deviceId, backend.stateOf(deviceId).copyWith(updatedAt: DateTime.now()));
      await backend.addEvent(DeviceEvent(
        id: newId('evt'),
        deviceId: deviceId,
        at: DateTime.now(),
        kind: EventKind.system,
        message: 'Refreshed canonical state from service',
        actor: userId,
      ));
    } else {
      await backend.addEvent(DeviceEvent(
        id: newId('evt'),
        deviceId: deviceId,
        at: DateTime.now(),
        kind: EventKind.system,
        message: 'Refresh attempted — ${health.note}',
        actor: userId,
        ok: false,
      ));
    }
    _changed();
    return CommandResult(
      commandId: newId('cmd'),
      status: snap.device.deviceType == DeviceType.virtual ? CommandStatus.confirmed : CommandStatus.offline,
      message: snap.device.deviceType == DeviceType.virtual ? 'Canonical state reloaded' : health.note,
    );
  }

  Future<ServiceResult<DeviceSnapshot>> updateAutomation(
    String deviceId,
    String userId,
    AutomationSettings settings,
  ) async {
    final String? invalid = settings.validate();
    if (invalid != null) return ServiceResult<DeviceSnapshot>.fail(invalid);
    if (roleFor(deviceId, userId)?.canCommand != true) {
      return const ServiceResult<DeviceSnapshot>.fail('You are not allowed to change automation on this device.');
    }
    final DeviceSnapshot? snap = backend.snapshotSync(deviceId);
    if (snap == null) return const ServiceResult<DeviceSnapshot>.fail('Device not found.');
    final DeviceState s = snap.state;
    await backend.commitState(
      deviceId,
      s.copyWith(automation: settings, revision: s.revision + 1, updatedAt: DateTime.now()),
    );
    await backend.addEvent(DeviceEvent(
      id: newId('evt'),
      deviceId: deviceId,
      at: DateTime.now(),
      kind: EventKind.state,
      message: 'Automation: ON at ${settings.onThreshold.toStringAsFixed(0)}%, OFF at ${settings.offThreshold.toStringAsFixed(0)}%, dwell ${settings.minDwellSeconds}s',
      actor: userId,
    ));
    _changed();
    return ServiceResult<DeviceSnapshot>.ok(backend.snapshotSync(deviceId));
  }

  Future<ServiceResult<Membership>> revokeAccess(String deviceId, String userId, String membershipId) async {
    if (roleFor(deviceId, userId) != MemberRole.owner) {
      return const ServiceResult<Membership>.fail('Only the owner can revoke access.');
    }
    final Membership? m = backend.membershipsForDevice(deviceId).cast<Membership?>().firstWhere(
          (Membership? x) => x!.id == membershipId,
          orElse: () => null,
        );
    if (m == null) return const ServiceResult<Membership>.fail('Membership not found.');
    if (m.role == MemberRole.owner) return const ServiceResult<Membership>.fail('The owner cannot be removed.');
    await backend.revokeMembership(membershipId);
    await backend.addEvent(DeviceEvent(
      id: newId('evt'),
      deviceId: deviceId,
      at: DateTime.now(),
      kind: EventKind.membership,
      message: 'Access revoked for a ${m.role.label.toLowerCase()}',
      actor: userId,
    ));
    _changed();
    return ServiceResult<Membership>.ok(m);
  }

  Future<void> nudgeEnvironment(String deviceId, String userId,
      {double humidityDelta = 0, double temperatureDelta = 0}) async {
    final DeviceSnapshot? snap = backend.snapshotSync(deviceId);
    if (snap == null || snap.device.deviceType != DeviceType.virtual) return; // hardware: never
    if (roleFor(deviceId, userId)?.canCommand != true) return;
    await backend.nudgeReading(deviceId, humidityDelta: humidityDelta, temperatureDelta: temperatureDelta);
    _changed();
  }

  Future<void> setEnvironmentTarget(String deviceId, String userId, VirtualEnvironment env) async {
    final DeviceSnapshot? snap = backend.snapshotSync(deviceId);
    if (snap == null || snap.device.deviceType != DeviceType.virtual) return;
    if (roleFor(deviceId, userId)?.canCommand != true) return;
    await backend.setEnvironment(deviceId, env);
    _changed();
  }

  // -- command pipeline -------------------------------------------------------
  Future<CommandResult> _dispatch({
    required String deviceId,
    required String userId,
    required String verb,
    PowerState? power,
    int? speed,
    FanMode? mode,
  }) async {
    final DeviceSnapshot? snap = backend.snapshotSync(deviceId);
    if (snap == null) {
      return CommandResult(commandId: newId('cmd'), status: CommandStatus.rejected, message: 'Device not found.');
    }
    final Device d = snap.device;
    final MemberRole? role = roleFor(deviceId, userId);
    if (role == null) {
      return CommandResult(commandId: newId('cmd'), status: CommandStatus.rejected, message: 'You do not have access to this device.');
    }
    if (!role.canCommand) {
      return CommandResult(commandId: newId('cmd'), status: CommandStatus.rejected, message: 'Your role (${role.label}) is read-only.');
    }
    if (speed != null && !d.capabilities.speedControl) {
      return CommandResult(commandId: newId('cmd'), status: CommandStatus.unsupported, message: 'This device does not support speed control.');
    }
    if (mode == FanMode.automatic && !d.capabilities.automaticMode) {
      return CommandResult(commandId: newId('cmd'), status: CommandStatus.unsupported, message: 'This device does not support automatic mode.');
    }
    // Hardware honesty: we know there is no connection, so say so.
    if (d.deviceType == DeviceType.physical && snap.connectivity.status != ConnectivityStatus.online) {
      await backend.addEvent(DeviceEvent(
        id: newId('evt'),
        deviceId: deviceId,
        at: DateTime.now(),
        kind: EventKind.command,
        message: '$verb — not delivered, device is ${snap.connectivity.status.label.toLowerCase()}',
        actor: userId,
        ok: false,
      ));
      _changed();
      return CommandResult(
        commandId: newId('cmd'),
        status: CommandStatus.offline,
        message: 'Device is ${snap.connectivity.status.label.toLowerCase()} — command was not delivered.',
      );
    }

    final String commandId = newId('cmd');
    final DeviceState current = snap.state;
    final DeviceState desired = current.copyWith(
      desiredPower: power ?? current.desiredPower,
      desiredSpeed: speed ?? current.desiredSpeed,
      desiredMode: mode ?? current.desiredMode,
      revision: current.revision + 1,
      updatedAt: DateTime.now(),
    );
    await backend.applyDesired(deviceId, desired); // UI shows "pending"
    await backend.addEvent(DeviceEvent(
      id: newId('evt'),
      deviceId: deviceId,
      at: DateTime.now(),
      kind: EventKind.command,
      message: '$verb requested (cmd ${commandId.substring(0, 12)})',
      actor: userId,
    ));
    _changed();

    final FanDeviceAdapter adapter = backend.adapterFor(d.deviceType);
    final AdapterAck ack = await _withTimeout<AdapterAck>(
      adapter.applyCommand(DeviceCommand(commandId: commandId, device: d, current: current, power: power, speed: speed, mode: mode)),
      Duration(milliseconds: backend.settings.commandTimeoutMs),
      () => AdapterAck(
        status: CommandStatus.timeout,
        power: current.power,
        speed: current.speed,
        mode: current.mode,
        message: 'No acknowledgement within ${backend.settings.commandTimeoutMs} ms (unconfirmed)',
      ),
    );

    if (ack.status == CommandStatus.confirmed) {
      await backend.commitState(
        deviceId,
        current.copyWith(
          power: ack.power,
          speed: ack.speed,
          mode: ack.mode,
          desiredPower: ack.power,
          desiredSpeed: ack.speed,
          desiredMode: ack.mode,
          lastSwitchAt: ack.power != current.power ? DateTime.now() : current.lastSwitchAt,
          revision: current.revision + 2,
          updatedAt: DateTime.now(),
        ),
      );
      await backend.addEvent(DeviceEvent(
        id: newId('evt'),
        deviceId: deviceId,
        at: DateTime.now(),
        kind: EventKind.command,
        message: '$verb confirmed by device',
        actor: userId,
      ));
    } else {
      // Rejected/timeout/unsupported: keep reported state, drop the desire.
      await backend.commitState(
        deviceId,
        current.copyWith(
          desiredPower: current.power,
          desiredSpeed: current.speed,
          desiredMode: current.mode,
          updatedAt: DateTime.now(),
        ),
      );
      await backend.addEvent(DeviceEvent(
        id: newId('evt'),
        deviceId: deviceId,
        at: DateTime.now(),
        kind: EventKind.command,
        message: '$verb ${ack.status.name.toUpperCase()}: ${ack.message}',
        actor: userId,
        ok: false,
      ));
    }
    _lastCommandAt[deviceId] = DateTime.now();
    _changed();
    return CommandResult(commandId: commandId, status: ack.status, message: ack.message.isEmpty ? '$verb ${ack.status.name}' : ack.message);
  }
}

Future<T> _withTimeout<T>(Future<T> f, Duration d, T Function() onTimeout) async {
  try {
    return await f.timeout(d, onTimeout: () => onTimeout());
  } catch (_) {
    return onTimeout();
  }
}

class PairingService {
  PairingService({required this.backend, required this.auth, this.onChanged});

  final DemoBackend backend;
  final AuthService auth;
  final VoidCallback? onChanged;

  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no O/0/I/1
  final Map<String, List<DateTime>> _redeemAttempts = <String, List<DateTime>>{};

  void _changed() => onChanged?.call();

  PairingCodeRecord? activeCode(String deviceId) {
    final DateTime now = DateTime.now();
    for (final PairingCodeRecord c in backend.codesFor(deviceId)) {
      if (c.isUsable(now)) return c;
    }
    return null;
  }

  Future<ServiceResult<PairingCodeOffer>> createCode({
    required String deviceId,
    required String userId,
    MemberRole grantsRole = MemberRole.controller,
  }) async {
    final MemberRole? role = backend.membershipsForDevice(deviceId)
        .cast<Membership?>()
        .firstWhere((Membership? m) => m!.userId == userId, orElse: () => null)
        ?.role;
    if (role == null) return const ServiceResult<PairingCodeOffer>.fail('You do not have access to this device.');
    if (role == MemberRole.viewer) return const ServiceResult<PairingCodeOffer>.fail('Viewers cannot create pairing codes.');

    await backend.revokeCodesFor(deviceId); // one live code per device
    final String code = _generateCode();
    final String salt = newId('ps');
    final DateTime now = DateTime.now();
    final PairingCodeRecord record = PairingCodeRecord(
      id: newId('code'),
      deviceId: deviceId,
      codeHash: Sha256.salted(salt, _normalize(code)),
      salt: salt,
      createdAt: now,
      expiresAt: now.add(Duration(seconds: backend.settings.pairingExpirySeconds)),
      maxAttempts: backend.settings.maxCodeAttempts,
      grantsRole: grantsRole,
      createdByUserId: userId,
    );
    await backend.storeCode(record);
    await backend.addEvent(DeviceEvent(
      id: newId('evt'),
      deviceId: deviceId,
      at: now,
      kind: EventKind.pairing,
      message: 'Pairing code issued (expires in ${backend.settings.pairingExpirySeconds}s, single use)',
      actor: userId,
    ));
    _changed();
    return ServiceResult<PairingCodeOffer>.ok(PairingCodeOffer(code: code, record: record));
  }

  Future<ServiceResult<Membership>> redeem({
    required String code,
    required String userId,
    required String sessionToken,
    String deviceLabel = 'this device',
  }) async {
    if (auth.session(sessionToken) == null) {
      return const ServiceResult<Membership>.fail('Sign in before pairing.');
    }
    final String entered = _normalize(code);
    if (entered.length != 6) return const ServiceResult<Membership>.fail('Pairing codes are 6 characters.');

    // Rate limiting per user (brute-force protection).
    final List<DateTime> attempts = _redeemAttempts.putIfAbsent(userId, () => <DateTime>[]);
    final DateTime cutoff = DateTime.now().subtract(const Duration(minutes: 10));
    attempts.removeWhere((DateTime t) => t.isBefore(cutoff));
    if (attempts.length >= 8) return const ServiceResult<Membership>.fail('Too many pairing attempts. Wait 10 minutes.');
    attempts.add(DateTime.now());

    final DateTime now = DateTime.now();
    PairingCodeRecord? match;
    for (final PairingCodeRecord c in _allCodes()) {
      if (c.isConsumed || c.isExpired(now)) continue;
      if (c.attempts >= c.maxAttempts) continue;
      if (Sha256.salted(c.salt, entered) == c.codeHash) {
        match = c;
        break;
      }
      // wrong guess on a live code counts as an attempt
      if (!c.isConsumed) {
        await backend.updateCode(c.copyWith(attempts: c.attempts + 1));
      }
    }

    if (match == null) {
      await backend.addEvent(DeviceEvent(
        id: newId('evt'),
        deviceId: '',
        at: now,
        kind: EventKind.pairing,
        message: 'Failed pairing attempt (invalid, expired or used code)',
        actor: userId,
        ok: false,
      ));
      _changed();
      return const ServiceResult<Membership>.fail('That code is invalid, expired or already used.');
    }

    // Atomic single-use consumption (single-threaded by construction here;
    // on a server this must be a conditional UPDATE ... WHERE consumed_at IS NULL).
    await backend.updateCode(match.copyWith(consumedAt: now, consumedByUserId: userId));

    final List<Membership> existing = backend.membershipsForDevice(match.deviceId)
        .where((Membership m) => m.userId == userId)
        .toList();
    if (existing.isNotEmpty) {
      await backend.addEvent(DeviceEvent(
        id: newId('evt'),
        deviceId: match.deviceId,
        at: now,
        kind: EventKind.pairing,
        message: 'Pairing code accepted — access already granted (${existing.first.role.label})',
        actor: userId,
      ));
      _changed();
      return ServiceResult<Membership>.ok(existing.first);
    }

    final Membership m = Membership(
      id: newId('mem'),
      deviceId: match.deviceId,
      userId: userId,
      role: match.grantsRole,
      createdAt: now,
      grantedVia: 'pairing-code',
    );
    await backend.addMembership(m);
    await backend.addEvent(DeviceEvent(
      id: newId('evt'),
      deviceId: match.deviceId,
      at: now,
      kind: EventKind.pairing,
      message: 'Paired $deviceLabel as ${match.grantsRole.label} via code',
      actor: userId,
    ));
    _changed();
    return ServiceResult<Membership>.ok(m);
  }

  List<PairingCodeRecord> _allCodes() {
    final Map<String, PairingCodeRecord> unique = <String, PairingCodeRecord>{};
    for (final String deviceId in backend.allDeviceIds()) {
      for (final PairingCodeRecord c in backend.codesFor(deviceId)) {
        unique[c.id] = c;
      }
    }
    return unique.values.toList();
  }

  Future<void> revoke(String deviceId, String userId) async {
    await backend.revokeCodesFor(deviceId);
    await backend.addEvent(DeviceEvent(
      id: newId('evt'),
      deviceId: deviceId,
      at: DateTime.now(),
      kind: EventKind.pairing,
      message: 'Active pairing code revoked',
      actor: userId,
    ));
    _changed();
  }

  String _generateCode() {
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < 6; i++) {
      b.write(_alphabet[_rnd.nextInt(_alphabet.length)]);
    }
    return b.toString();
  }

  static String _normalize(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

// =============================================================================
//  9. APP STATE  (the only object the UI observes)
// =============================================================================

enum NavTab { devices, display, remote, settings }

extension NavTabX on NavTab {
  String get label => switch (this) {
        NavTab.devices => 'My Devices',
        NavTab.display => 'Fan Display',
        NavTab.remote => 'Remote',
        NavTab.settings => 'Settings',
      };
  IconData get icon => switch (this) {
        NavTab.devices => Icons.devices_rounded,
        NavTab.display => Icons.mode_fan_off_rounded,
        NavTab.remote => Icons.settings_remote_rounded,
        NavTab.settings => Icons.tune_rounded,
      };
}

class AppController extends ChangeNotifier {
  /// [startEngine] = false is only useful in tests: it skips the periodic
  /// simulation ticker (a repeating timer cannot drain inside fake async).
  AppController({bool startEngine = true}) {
    backend = DemoBackend();
    auth = AuthService();
    backend.attachAdapters(
      virtual: VirtualFanAdapter(
        latency: () => Duration(milliseconds: backend.settings.roundTripMs),
        shouldFail: () =>
            backend.settings.injectFailures && _driftRnd.nextDouble() < backend.settings.failureRate,
      ),
      esp32: const Esp32FanAdapter(),
    );
    fans = FanService(backend: backend, auth: auth, onChanged: notifyListeners);
    pairing = PairingService(backend: backend, auth: auth, onChanged: notifyListeners);
    if (startEngine) backend.start();
  }

  late final DemoBackend backend;
  late final AuthService auth;
  late final FanService fans;
  late final PairingService pairing;

  String? _sessionToken;
  NavTab _tab = NavTab.devices;
  String? _selectedDeviceId;
  String _message = '';
  bool _messageOk = true;
  int _messageSeq = 0;

  // -- accessors --------------------------------------------------------------
  Session? get session => auth.session(_sessionToken);
  UserAccount? get user => session == null ? null : auth.user(session!.userId);
  bool get isSignedIn => session != null;
  NavTab get tab => _tab;
  int get tabIndex => NavTab.values.indexOf(_tab);
  String get message => _message;
  bool get messageOk => _messageOk;
  int get messageSeq => _messageSeq;

  List<Session> get sessions => user == null ? const <Session>[] : auth.sessionsFor(user!.id);

  List<Device> get myDevices => isSignedIn ? backend.devicesForUser(session!.userId) : const <Device>[];

  Device? get selectedDevice {
    final List<Device> ds = myDevices;
    if (ds.isEmpty) return null;
    if (_selectedDeviceId != null) {
      for (final Device d in ds) {
        if (d.id == _selectedDeviceId) return d;
      }
    }
    return ds.first;
  }

  DeviceSnapshot? snapshotOf(String deviceId) => backend.snapshotSync(deviceId);

  Stream<DeviceSnapshot> watch(String deviceId) => backend.watch(deviceId);

  MemberRole? roleOn(String deviceId) =>
      isSignedIn ? fans.roleFor(deviceId, session!.userId) : null;

  bool isPending(String deviceId) => fans.isPending(deviceId);

  // -- mutations ---------------------------------------------------------------
  void setTab(NavTab tab) {
    _tab = tab;
    notifyListeners();
  }

  void selectDevice(String deviceId) {
    _selectedDeviceId = deviceId;
    notifyListeners();
  }

  /// Ask the UI to rebuild (used by the Settings page after changing config).
  void touch() => notifyListeners();

  void toast(String text, {bool ok = true}) {
    _message = text;
    _messageOk = ok;
    _messageSeq++;
    notifyListeners();
  }

  Future<ServiceResult<Session>> signIn(String email, String password) async {
    final ServiceResult<Session> r = await auth.signIn(email: email, password: password);
    if (r.ok) {
      _sessionToken = r.data!.token;
      _afterAuthChange();
    }
    return r;
  }

  Future<ServiceResult<Session>> signUp(String name, String email, String password) async {
    final ServiceResult<Session> r = await auth.signUp(email: email, password: password, displayName: name);
    if (r.ok) {
      _sessionToken = r.data!.token;
      _afterAuthChange();
    }
    return r;
  }

  /// Simulates opening AiroRhythm on another device (a second signed-in session).
  Future<ServiceResult<Session>> addSession({required String email, required String password, String? label}) async {
    final ServiceResult<Session> r = await auth.signIn(email: email, password: password, deviceLabel: label);
    if (r.ok) {
      _sessionToken = r.data!.token;
      _selectedDeviceId = null;
      notifyListeners();
    }
    return r;
  }

  void switchSession(String token) {
    if (auth.session(token) == null) return;
    _sessionToken = token;
    _selectedDeviceId = null;
    notifyListeners();
  }

  void signOutSession(String token) {
    auth.signOut(token);
    if (_sessionToken == token) {
      final List<Session> remaining = sessions;
      _sessionToken = remaining.isEmpty ? null : remaining.first.token;
      _selectedDeviceId = null;
      _tab = NavTab.devices;
    }
    notifyListeners();
  }

  void _afterAuthChange() {
    _selectedDeviceId = null;
    _tab = NavTab.devices;
    notifyListeners();
  }

  // -- convenience wrappers bound to the active session ------------------------
  String get actorId => session!.userId;

  Future<CommandResult> setPower(String deviceId, bool on) => fans.setPower(deviceId, actorId, on);
  Future<CommandResult> setSpeed(String deviceId, int percent) => fans.setSpeed(deviceId, actorId, percent);
  Future<CommandResult> setMode(String deviceId, FanMode mode) => fans.setMode(deviceId, actorId, mode);
  Future<CommandResult> refresh(String deviceId) => fans.refresh(deviceId, actorId);
  Future<ServiceResult<DeviceSnapshot>> updateAutomation(String deviceId, AutomationSettings s) =>
      fans.updateAutomation(deviceId, actorId, s);
  Future<ServiceResult<Membership>> revokeAccess(String deviceId, String membershipId) =>
      fans.revokeAccess(deviceId, actorId, membershipId);
  Future<void> deleteDevice(String deviceId) => fans.deleteDevice(deviceId, actorId);
  Future<void> nudgeEnvironment(String deviceId, {double humidityDelta = 0, double temperatureDelta = 0}) =>
      fans.nudgeEnvironment(deviceId, actorId, humidityDelta: humidityDelta, temperatureDelta: temperatureDelta);
  Future<ServiceResult<Device>> createVirtualFan(String name, String room, Capabilities caps) =>
      fans.createVirtualFan(userId: actorId, name: name, room: room, capabilities: caps);
  Future<ServiceResult<Device>> provisionPhysicalFan(String name, String room, Capabilities caps) =>
      fans.provisionPhysicalFan(userId: actorId, name: name, room: room, capabilities: caps);
  Future<ServiceResult<PairingCodeOffer>> createPairingCode(String deviceId) =>
      pairing.createCode(deviceId: deviceId, userId: actorId);
  Future<ServiceResult<Membership>> redeemCode(String code, String deviceLabel) =>
      pairing.redeem(code: code, userId: actorId, sessionToken: _sessionToken!, deviceLabel: deviceLabel);
  Future<void> revokePairingCode(String deviceId) => pairing.revoke(deviceId, actorId);

  @override
  void dispose() {
    backend.dispose();
    super.dispose();
  }
}

/// Inherited scope so any widget can reach the controller.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child}) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final AppScope? scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!.notifier!;
  }

  /// Same controller, but without registering a build dependency.
  /// Required inside [State.initState], where depending on an inherited widget
  /// is not allowed by the framework.
  static AppController read(BuildContext context) {
    final AppScope? scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!.notifier!;
  }
}

// =============================================================================
//  10. BRAND MARK  (drawn in code — no image assets needed)
// =============================================================================

class AiroRhythmLogo extends StatelessWidget {
  const AiroRhythmLogo({super.key, this.size = 34, this.showWordmark = true, this.wordmarkSize = 19});

  final double size;
  final bool showWordmark;
  final double wordmarkSize;

  @override
  Widget build(BuildContext context) {
    final Widget mark = Semantics(
      label: 'AiroRhythm logo',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _LogoPainter()),
      ),
    );
    if (!showWordmark) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        mark,
        SizedBox(width: size * 0.32),
        ShaderMask(
          shaderCallback: (Rect bounds) => const LinearGradient(
            colors: kBrandGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: Text(
            'AiroRhythm',
            style: TextStyle(
              color: Colors.white,
              fontSize: wordmarkSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final double r = size.width * 0.46;
    final Rect bounds = Rect.fromCircle(center: c, radius: r);
    final Paint gradientPaint = Paint()
      ..shader = const SweepGradient(
        colors: <Color>[kBrandBlue, Color(0xFF7A5CFF), kBrandViolet, Color(0xFF4FB4FF), kBrandBlue],
        startAngle: -0.4,
        endAngle: 5.88,
      ).createShader(bounds)
      ..style = PaintingStyle.fill;

    // Airflow arc (top-left sweep) — the "rhythm" of moving air.
    final Paint arcPaint = Paint()
      ..shader = const LinearGradient(colors: kBrandGradient).createShader(bounds)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.052;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.985),
      -2.55,
      1.5,
      false,
      arcPaint,
    );

    // Three sweeping blades.
    for (int i = 0; i < 3; i++) {
      final double a = (-1.5708) + i * 2.0944; // 120° apart
      canvas.drawPath(_blade(c, r * 0.74, a), gradientPaint);
    }

    // Hub: dark centre with a light ring (logo is drawn on a dark background).
    canvas.drawCircle(c, r * 0.235, Paint()..color = kBase);
    canvas.drawCircle(
      c,
      r * 0.235,
      Paint()
        ..color = fade(Colors.white, 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.045,
    );
    canvas.drawCircle(c, r * 0.075, gradientPaint);
  }

  Path _blade(Offset c, double len, double angle) {
    final Path p = Path();
    final Offset tip = Offset(c.dx + len * math.cos(angle), c.dy + len * math.sin(angle));
    final Offset ctrl1 = Offset(
      c.dx + len * 0.62 * math.cos(angle - 0.72),
      c.dy + len * 0.62 * math.sin(angle - 0.72),
    );
    final Offset ctrl2 = Offset(
      c.dx + len * 0.86 * math.cos(angle + 0.22),
      c.dy + len * 0.86 * math.sin(angle + 0.22),
    );
    p.moveTo(c.dx, c.dy);
    p.quadraticBezierTo(ctrl1.dx, ctrl1.dy, tip.dx, tip.dy);
    p.quadraticBezierTo(ctrl2.dx, ctrl2.dy, c.dx, c.dy);
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) => false;
}

// =============================================================================
//  11. SHARED UI COMPONENTS
// =============================================================================

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    this.accent,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: kSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius),
        side: const BorderSide(color: kOutline),
      ),
      child: Container(
        decoration: accent == null
            ? null
            : BoxDecoration(
                border: Border(left: BorderSide(color: accent!, width: 3)),
              ),
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(title!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            if (subtitle != null) ...<Widget>[
                              const SizedBox(height: 2),
                              Text(subtitle!, style: const TextStyle(fontSize: 12, color: kTextDim)),
                            ],
                          ],
                        ),
                      ),
                      if (trailing != null) trailing!,
                    ],
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class BadgeChip extends StatelessWidget {
  const BadgeChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dense = false,
    this.tooltip,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Widget chip = Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 11, vertical: dense ? 4 : 6),
      decoration: BoxDecoration(
        color: fade(color, 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fade(color, 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: dense ? 13 : 15, color: color),
            SizedBox(width: dense ? 5 : 7),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: dense ? 11 : 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
    if (tooltip == null) return chip;
    return Tooltip(message: tooltip!, child: chip);
  }
}

/// SIMULATED DATA / REAL DEVICE DATA — always visible, never ambiguous.
class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.source, required this.deviceType});

  final ReadingSource source;
  final DeviceType deviceType;

  @override
  Widget build(BuildContext context) {
    if (deviceType == DeviceType.physical) {
      final bool real = source == ReadingSource.physical;
      return BadgeChip(
        label: real ? 'REAL DEVICE DATA' : 'NO DEVICE DATA',
        color: real ? kOk : kDanger,
        icon: real ? Icons.verified_rounded : Icons.sensors_off_rounded,
        tooltip: real
            ? 'Values come from authenticated device telemetry.'
            : 'This physical device has not reported any telemetry. Nothing is simulated for it.',
      );
    }
    return const BadgeChip(
      label: 'SIMULATED DATA',
      color: kBrandViolet,
      icon: Icons.science_rounded,
      tooltip: 'Values are produced by the AiroRhythm simulator. No hardware is involved.',
    );
  }
}

class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({super.key, required this.connectivity, this.dense = false});

  final DeviceConnectivity connectivity;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return BadgeChip(
      label: connectivity.status.label,
      color: connectivity.status.color,
      icon: connectivity.status.icon,
      dense: dense,
      tooltip: connectivity.note,
    );
  }
}

class SensorTile extends StatelessWidget {
  const SensorTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.unit = '',
    this.color = kBrandBlue,
    this.footer,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kSurfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kOutline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 11.5, color: kTextDim, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, height: 1.05),
              ),
            ),
            if (footer != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(footer!, style: const TextStyle(fontSize: 11, color: kTextDim)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Command button with pending / success / failure states.
class CommandButton extends StatelessWidget {
  const CommandButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.pending = false,
    this.enabled = true,
    this.filled = false,
    this.expand = true,
    this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool pending;
  final bool enabled;
  final bool filled;
  final bool expand;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bool active = enabled && !pending;
    final Widget child = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 50,
      width: expand ? double.infinity : null,
      padding: EdgeInsets.symmetric(horizontal: expand ? 12 : 20, vertical: 8),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (pending)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: kText),
            )
          else
            Icon(icon, size: 19, color: active ? (color ?? Colors.white) : kTextDim),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              pending ? 'Pending…' : label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: active ? (color ?? Colors.white) : kTextDim,
              ),
            ),
          ),
        ],
      ),
    );
    final ButtonStyle style = filled
        ? FilledButton.styleFrom(
            backgroundColor: active ? (color ?? kBrandBlue) : kSurfaceTop,
            foregroundColor: active ? Colors.black : kTextDim,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
            padding: EdgeInsets.zero,
          )
        : OutlinedButton.styleFrom(
            side: BorderSide(color: active ? fade(color ?? kBrandBlue, 0.75) : kOutline),
            backgroundColor: active ? fade(color ?? kBrandBlue, 0.10) : kSurfaceHigh,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
            padding: EdgeInsets.zero,
          );
    final VoidCallback? cb = active ? onPressed : null;
    return Semantics(
      button: true,
      enabled: active,
      label: label,
      child: filled
          ? FilledButton(style: style, onPressed: cb, child: child)
          : OutlinedButton(style: style, onPressed: cb, child: child),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fade(kBrandBlue, 0.12),
                  border: Border.all(color: fade(kBrandBlue, 0.35)),
                ),
                child: Icon(icon, size: 34, color: kBrandBlue),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: kTextDim, height: 1.45),
              ),
              if (actionLabel != null && onAction != null) ...<Widget>[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  12. FAN ANIMATION
//      Spins ONLY while the reported/confirmed state is ON. Speed changes the
//      rotation period. Unknown (hardware) state renders a stopped, dimmed fan.
// =============================================================================

class FanAnimation extends StatefulWidget {
  const FanAnimation({
    super.key,
    required this.running,
    this.speedPercent = 60,
    this.size = 230,
    this.unknown = false,
  });

  final bool running;
  final int speedPercent;
  final double size;
  final bool unknown;

  @override
  State<FanAnimation> createState() => _FanAnimationState();
}

class _FanAnimationState extends State<FanAnimation> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this);

  Duration _durationFor(int speed) {
    final double seconds = 2.4 - (speed.clamp(0, 100) / 100.0) * 1.85; // 2.4s .. 0.55s
    return Duration(milliseconds: (seconds * 1000).round());
  }

  @override
  void initState() {
    super.initState();
    _spin.duration = _durationFor(widget.speedPercent);
    if (widget.running) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant FanAnimation old) {
    super.didUpdateWidget(old);
    _spin.duration = _durationFor(widget.speedPercent);
    if (widget.running && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.running && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool dim = !widget.running || widget.unknown;
    return Semantics(
      label: widget.unknown
          ? 'Fan state unknown — no device report'
          : (widget.running ? 'Fan running' : 'Fan stopped'),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // Housing / glow
            AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    fade(widget.running ? kBrandBlue : kSurfaceTop, widget.running ? 0.20 : 0.35),
                    fade(kSurfaceHigh, 0.15),
                  ],
                ),
                border: Border.all(
                  color: widget.running ? fade(kBrandBlue, 0.55) : kOutline,
                  width: 1.4,
                ),
              ),
            ),
            // Blades
            RotationTransition(
              turns: _spin,
              child: CustomPaint(
                size: Size(widget.size * 0.78, widget.size * 0.78),
                painter: _FanBladesPainter(dim: dim),
              ),
            ),
            // Hub
            Container(
              width: widget.size * 0.17,
              height: widget.size * 0.17,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kSurfaceTop,
                border: Border.all(color: fade(kBrandBlue, widget.running ? 0.9 : 0.35), width: 2),
              ),
              child: Icon(
                widget.unknown ? Icons.help_outline_rounded : Icons.circle,
                size: widget.size * 0.07,
                color: widget.running ? kBrandBlue : kTextDim,
              ),
            ),
            if (widget.unknown)
              Positioned(
                bottom: widget.size * 0.13,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: fade(kSurfaceTop, 0.95),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kOutline),
                  ),
                  child: const Text(
                    'no device report',
                    style: TextStyle(fontSize: 10.5, color: kTextDim, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FanBladesPainter extends CustomPainter {
  const _FanBladesPainter({required this.dim});

  final bool dim;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final double r = size.width * 0.47;
    final Paint paint = Paint()
      ..shader = SweepGradient(
        colors: <Color>[
          dim ? fade(kTextDim, 0.55) : kBrandBlue,
          dim ? fade(kTextDim, 0.35) : kBrandViolet,
          dim ? fade(kTextDim, 0.55) : const Color(0xFF54C7FF),
          dim ? fade(kTextDim, 0.35) : kBrandBlue,
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r))
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 4; i++) {
      final double a = i * (math.pi / 2) + 0.35;
      canvas.drawPath(_blade(c, r, a, 0.62), paint);
    }
    // Rim
    canvas.drawCircle(
      c,
      r * 1.02,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.018
        ..color = dim ? fade(kTextDim, 0.35) : fade(kBrandBlue, 0.45),
    );
  }

  Path _blade(Offset c, double len, double angle, double width) {
    final Path p = Path();
    final double spread = width;
    p.moveTo(c.dx, c.dy);
    p.quadraticBezierTo(
      c.dx + len * 0.55 * math.cos(angle - spread),
      c.dy + len * 0.55 * math.sin(angle - spread),
      c.dx + len * math.cos(angle),
      c.dy + len * math.sin(angle),
    );
    p.quadraticBezierTo(
      c.dx + len * 0.55 * math.cos(angle + spread),
      c.dy + len * 0.55 * math.sin(angle + spread),
      c.dx,
      c.dy,
    );
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(covariant _FanBladesPainter old) => old.dim != dim;
}

// =============================================================================
//  13. APP ROOT + AUTH
// =============================================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AiroRhythmApp(controller: AppController()));
}

class AiroRhythmApp extends StatelessWidget {
  const AiroRhythmApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: MaterialApp(
        title: 'AiroRhythm',
        debugShowCheckedModeBanner: false,
        theme: buildAiroTheme(),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final AppController c = AppScope.of(context);
    return AnimatedBuilder(
      animation: c,
      builder: (BuildContext context, _) => c.isSignedIn ? const AppShell() : const AuthPage(),
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _name = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final AppController c = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final ServiceResult<Session> r = _signUp
        ? await c.signUp(_name.text, _email.text, _password.text)
        : await c.signIn(_email.text, _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok && mounted) {
      setState(() => _error = r.error);
    }
  }

  Future<void> _useDemo() async {
    final AppController c = AppScope.of(context);
    setState(() => _busy = true);
    _email.text = 'demo@airorhythm.app';
    _password.text = 'demo1234';
    final ServiceResult<Session> r = await c.signIn('demo@airorhythm.app', 'demo1234');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = r.ok ? null : r.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.of(context).size.width >= 780;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF0B0E14), kBase, Color(0xFF0E0A16)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 880 : 420),
                child: wide
                    ? Row(
                        children: <Widget>[
                          Expanded(child: _brandPanel()),
                          const SizedBox(width: 36),
                          Expanded(child: _formCard()),
                        ],
                      )
                    : Column(
                        children: <Widget>[
                          _brandPanel(),
                          const SizedBox(height: 26),
                          _formCard(),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _brandPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const AiroRhythmLogo(size: 54, wordmarkSize: 28),
        const SizedBox(height: 18),
        const Text(
          'One app. Fan Display and Remote,\nvirtual now, hardware ready.',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.35),
        ),
        const SizedBox(height: 14),
        const Text(
          'Create a virtual fan, show its pairing code, and control it from another '
          'signed-in device. Simulated values are always labelled. Physical ESP32 '
          'devices plug into the same service contract later — the app never '
          'pretends hardware is connected.',
          style: TextStyle(fontSize: 13.5, color: kTextDim, height: 1.5),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const <Widget>[
            BadgeChip(label: 'Virtual first', color: kBrandViolet, icon: Icons.science_rounded),
            BadgeChip(label: 'ESP32 ready', color: kBrandBlue, icon: Icons.memory_rounded),
            BadgeChip(label: 'Hashed pairing codes', color: kOk, icon: Icons.key_rounded),
          ],
        ),
      ],
    );
  }

  Widget _formCard() {
    return SectionCard(
      title: _signUp ? 'Create account' : 'Sign in',
      subtitle: 'Authentication is required before pairing or control.',
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_signUp) ...<Widget>[
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.person_outline_rounded)),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              helperText: _signUp ? 'At least 8 characters' : null,
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: fade(kDanger, 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: fade(kDanger, 0.5)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.error_outline_rounded, size: 17, color: kDanger),
                  const SizedBox(width: 9),
                  Expanded(child: Text(_error!, style: const TextStyle(color: kDanger, fontSize: 12.5))),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.black))
                  : Text(_signUp ? 'Create account' : 'Sign in'),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _busy ? null : _useDemo,
            child: const Text('Use demo account'),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _signUp = !_signUp),
            child: Text(_signUp ? 'I already have an account' : 'Create an account'),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
//  14. APP SHELL + NAVIGATION  (responsive: rail on laptop, bar on phone)
// =============================================================================

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _seenMessage = 0;
  late AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppScope.read(context);
    _seenMessage = _controller.messageSeq;
    _controller.addListener(_onControllerChange);
  }

  void _onControllerChange() {
    final AppController c = _controller;
    if (c.messageSeq == _seenMessage) return;
    _seenMessage = c.messageSeq;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: <Widget>[
              Icon(
                c.messageOk ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 18,
                color: c.messageOk ? kOk : kDanger,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(c.message)),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppController c = AppScope.of(context);
    return AnimatedBuilder(
      animation: c,
      builder: (BuildContext context, _) {
        final bool wide = MediaQuery.of(context).size.width >= kNarrowBreakpoint;
        final Device? selected = c.selectedDevice;
        final bool pending = selected != null && c.isPending(selected.id);

        final Widget body = switch (c.tab) {
          NavTab.devices => const MyDevicesPage(),
          NavTab.display => const FanDisplayPage(),
          NavTab.remote => const RemoteControlPage(),
          NavTab.settings => const SettingsPage(),
        };

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 68,
            title: AiroRhythmLogo(size: 28, wordmarkSize: wide ? 19 : 16.5),
            actions: <Widget>[
              if (pending)
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: BadgeChip(label: 'Syncing…', color: kInfo, icon: Icons.sync_rounded, dense: true),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _SessionMenu(),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: wide
                  ? Row(
                      children: <Widget>[
                        NavigationRail(
                          extended: MediaQuery.of(context).size.width >= 1080,
                          minExtendedWidth: 190,
                          selectedIndex: c.tabIndex,
                          onDestinationSelected: (int i) => c.setTab(NavTab.values[i]),
                          labelType: MediaQuery.of(context).size.width >= 1080
                              ? NavigationRailLabelType.none
                              : NavigationRailLabelType.all,
                          destinations: NavTab.values
                              .map(
                                (NavTab t) => NavigationRailDestination(
                                  icon: Icon(t.icon),
                                  selectedIcon: Icon(t.icon),
                                  label: Text(t.label),
                                ),
                              )
                              .toList(),
                        ),
                        const VerticalDivider(width: 1, color: kOutline),
                        Expanded(child: body),
                      ],
                    )
                  : body,
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: c.tabIndex,
                  onDestinationSelected: (int i) => c.setTab(NavTab.values[i]),
                  destinations: NavTab.values
                      .map((NavTab t) => NavigationDestination(icon: Icon(t.icon), label: t.label))
                      .toList(),
                ),
        );
      },
    );
  }
}

/// Top-right chip: which signed-in *device* you are acting as.
class _SessionMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppController c = AppScope.of(context);
    final Session? s = c.session;
    if (s == null) return const SizedBox.shrink();
    final UserAccount? u = c.user;
    return PopupMenuButton<String>(
      tooltip: 'Signed-in device',
      offset: const Offset(0, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: kSurfaceTop,
      onSelected: (String value) async {
        if (value.startsWith('switch:')) {
          c.switchSession(value.substring(7));
          return;
        }
        if (value == 'add') {
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: kSurface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            builder: (BuildContext ctx) => const _AddSessionSheet(),
          );
          return;
        }
        if (value.startsWith('out:')) {
          c.signOutSession(value.substring(4));
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          child: Text('Signed in as ${u?.email ?? ''}', style: const TextStyle(fontSize: 11.5, color: kTextDim)),
        ),
        const PopupMenuDivider(),
        for (final Session other in c.sessions)
          PopupMenuItem<String>(
            value: 'switch:${other.token}',
            child: Row(
              children: <Widget>[
                Icon(
                  other.token == s.token ? Icons.check_rounded : Icons.devices_rounded,
                  size: 17,
                  color: other.token == s.token ? kBrandBlue : kTextDim,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(other.deviceLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(
                        'since ${fmtClock(other.createdAt)}',
                        style: const TextStyle(fontSize: 11, color: kTextDim),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'add',
          child: Row(
            children: <Widget>[
              Icon(Icons.add_rounded, size: 17, color: kBrandBlue),
              SizedBox(width: 10),
              Text('Add another device session…'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'out:${s.token}',
          child: const Row(
            children: <Widget>[
              Icon(Icons.logout_rounded, size: 17, color: kDanger),
              SizedBox(width: 10),
              Text('Sign out this device'),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: kSurfaceHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: kOutline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.devices_rounded, size: 15, color: kBrandBlue),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                s.deviceLabel,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded, size: 16, color: kTextDim),
          ],
        ),
      ),
    );
  }
}

class _AddSessionSheet extends StatefulWidget {
  const _AddSessionSheet();

  @override
  State<_AddSessionSheet> createState() => _AddSessionSheetState();
}

class _AddSessionSheetState extends State<_AddSessionSheet> {
  late final TextEditingController _email;
  late final TextEditingController _password;
  String _label = 'Phone · Android';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final AppController c = AppScope.read(context);
    _email = TextEditingController(text: c.user?.email ?? '');
    _password = TextEditingController();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppController c = AppScope.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.devices_rounded, color: kBrandBlue, size: 20),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text('Open a second signed-in device',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Simulates opening AiroRhythm on another phone or laptop. The new '
              'session starts with no paired fans — use a pairing code from the '
              'Fan Display to grant it control. Same-account multi-device pairing '
              'is supported for the demo.',
              style: TextStyle(fontSize: 12.5, color: kTextDim, height: 1.45),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline_rounded)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: <String>['Phone · Android', 'Phone · iOS', 'Tablet · iPadOS', 'Desktop · Safari']
                  .map(
                    (String l) => ChoiceChip(
                      label: Text(l),
                      selected: _label == l,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _label = l),
                    ),
                  )
                  .toList(),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: kDanger, fontSize: 12.5)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        final ServiceResult<Session> r = await c.addSession(
                          email: _email.text,
                          password: _password.text,
                          label: _label,
                        );
                        if (!mounted) return;
                        setState(() {
                          _busy = false;
                          _error = r.ok ? null : r.error;
                        });
                        if (r.ok && mounted) {
                          Navigator.of(context).pop();
                          c.toast('Signed in on $_label');
                        }
                      },
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.black),
                      )
                    : const Text('Open session'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
//  15. MY DEVICES
// =============================================================================

class MyDevicesPage extends StatelessWidget {
  const MyDevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppController c = AppScope.of(context);
    final List<Device> devices = c.myDevices;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: devices.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openCreate(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create device'),
            ),
      body: devices.isEmpty
          ? EmptyState(
              icon: Icons.devices_rounded,
              title: 'No devices yet',
              message: 'Create a virtual fan to get a Fan Display, simulated readings and '
                  'a pairing code — or provision an ESP32 device for later.',
              actionLabel: 'Create virtual fan',
              onAction: () => _openCreate(context),
            )
          : LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                final int columns = box.maxWidth >= 1000 ? 3 : (box.maxWidth >= 640 ? 2 : 1);
                return ListView(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, devices.length > columns ? 96 : 24),
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text('My Devices', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 3),
                              Text(
                                '${devices.length} device${devices.length == 1 ? '' : 's'} you own or can access',
                                style: const TextStyle(fontSize: 12.5, color: kTextDim),
                              ),
                            ],
                          ),
                        ),
                        if (box.maxWidth >= 640)
                          OutlinedButton.icon(
                            onPressed: () => _openCreate(context),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Create device'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: <Widget>[
                        for (final Device d in devices)
                          SizedBox(
                            width: (box.maxWidth - 32 - (columns - 1) * 14) / columns,
                            child: _DeviceCard(device: d),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
    );
  }

  static Future<void> _openCreate(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (BuildContext ctx) => const _CreateDeviceSheet(),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    final AppController c = AppScope.of(context);
    final bool isSelected = c.selectedDevice?.id == device.id;
    final MemberRole? role = c.roleOn(device.id);
    return StreamBuilder<DeviceSnapshot>(
      stream: c.watch(device.id),
      initialData: c.snapshotOf(device.id),
      builder: (BuildContext context, AsyncSnapshot<DeviceSnapshot> snap) {
        final DeviceSnapshot s = snap.data!;
        final bool stale = s.connectivity.status == ConnectivityStatus.stale;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(color: isSelected ? fade(kBrandBlue, 0.85) : kOutline, width: isSelected ? 1.8 : 1),
            boxShadow: isSelected
                ? <BoxShadow>[BoxShadow(color: fade(kBrandBlue, 0.16), blurRadius: 20, spreadRadius: 1)]
                : null,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(kRadius),
            onTap: () {
              c.selectDevice(device.id);
              c.setTab(NavTab.display);
            },
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: fade(s.state.power.isOn ? kBrandBlue : kSurfaceTop, 0.22),
                          border: Border.all(color: s.state.power.isOn ? fade(kBrandBlue, 0.6) : kOutline),
                        ),
                        child: Icon(
                          device.deviceType == DeviceType.virtual ? Icons.science_rounded : Icons.memory_rounded,
                          size: 20,
                          color: s.state.power.isOn ? kBrandBlue : kTextDim,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              device.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              device.room.isEmpty ? device.shortId : '${device.room} · ${device.shortId}',
                              style: const TextStyle(fontSize: 11, color: kTextDim),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      BadgeChip(
                        label: s.state.power.label,
                        color: s.state.power.isOn ? kOk : kTextDim,
                        dense: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: <Widget>[
                      BadgeChip(label: device.deviceType.label, color: kInfo, dense: true),
                      ConnectionBadge(connectivity: s.connectivity, dense: true),
                      SourceBadge(source: s.readings.source, deviceType: device.deviceType),
                      if (role != null) BadgeChip(label: role.label, color: kTextDim, dense: true),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Row(
                    children: <Widget>[
                      _MetaChip(
                        icon: Icons.thermostat_rounded,
                        text: device.capabilities.temperatureSensor ? fmtTemp(s.readings.temperatureC) : 'no sensor',
                      ),
                      const SizedBox(width: 8),
                      _MetaChip(
                        icon: Icons.water_drop_rounded,
                        text: device.capabilities.humiditySensor ? fmtHum(s.readings.humidityPercent) : 'no sensor',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Icon(
                        stale ? Icons.history_toggle_off_rounded : Icons.schedule_rounded,
                        size: 13,
                        color: stale ? kWarn : kTextDim,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${stale ? 'Last reported' : 'Updated'} ${fmtAgo(s.state.updatedAt, DateTime.now())} · rev ${s.state.revision}',
                          style: TextStyle(fontSize: 11, color: stale ? kWarn : kTextDim),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 11)),
                          onPressed: () {
                            c.selectDevice(device.id);
                            c.setTab(NavTab.display);
                          },
                          icon: const Icon(Icons.monitor_rounded, size: 16),
                          label: const Text('Display'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 11)),
                          onPressed: () {
                            c.selectDevice(device.id);
                            c.setTab(NavTab.remote);
                          },
                          icon: const Icon(Icons.settings_remote_rounded, size: 16),
                          label: const Text('Remote'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: kSurfaceHigh,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: kOutline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: kTextDim),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _CreateDeviceSheet extends StatefulWidget {
  const _CreateDeviceSheet();

  @override
  State<_CreateDeviceSheet> createState() => _CreateDeviceSheetState();
}

class _CreateDeviceSheetState extends State<_CreateDeviceSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _room = TextEditingController();
  DeviceType _type = DeviceType.virtual;
  bool _speed = true;
  bool _auto = true;
  bool _temp = true;
  bool _hum = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppController c = AppScope.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.add_circle_outline_rounded, color: kBrandBlue),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text('Create device', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<DeviceType>(
                segments: const <ButtonSegment<DeviceType>>[
                  ButtonSegment<DeviceType>(value: DeviceType.virtual, label: Text('Virtual fan'), icon: Icon(Icons.science_rounded)),
                  ButtonSegment<DeviceType>(value: DeviceType.physical, label: Text('ESP32'), icon: Icon(Icons.memory_rounded)),
                ],
                selected: <DeviceType>{_type},
                onSelectionChanged: (Set<DeviceType> s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: _type == DeviceType.virtual ? fade(kBrandViolet, 0.10) : fade(kWarn, 0.10),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: _type == DeviceType.virtual ? fade(kBrandViolet, 0.4) : fade(kWarn, 0.4)),
                ),
                child: Text(
                  _type == DeviceType.virtual
                      ? 'A virtual fan is simulated by the AiroRhythm service and labelled SIMULATED DATA everywhere.'
                      : 'A physical device is provisioned but stays offline until the ESP32 reports '
                          'authenticated telemetry. Nothing will be simulated for it.',
                  style: TextStyle(
                    fontSize: 12,
                    color: _type == DeviceType.virtual ? kBrandViolet : kWarn,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Device name', hintText: 'Bedroom Ventilation'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _room,
                decoration: const InputDecoration(labelText: 'Room (optional)', hintText: 'Bedroom'),
              ),
              const SizedBox(height: 14),
              const Text('Capabilities', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              _capSwitch('Speed control', _speed, (bool v) => setState(() => _speed = v)),
              _capSwitch('Automatic mode', _auto, (bool v) => setState(() => _auto = v)),
              _capSwitch('Temperature sensor', _temp, (bool v) => setState(() => _temp = v)),
              _capSwitch('Humidity sensor', _hum, (bool v) => setState(() => _hum = v)),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: kDanger, fontSize: 12.5)),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          final Capabilities caps = Capabilities(
                            speedControl: _speed,
                            automaticMode: _auto,
                            temperatureSensor: _temp,
                            humiditySensor: _hum,
                          );
                          final ServiceResult<Device> r = _type == DeviceType.virtual
                              ? await c.createVirtualFan(_name.text, _room.text, caps)
                              : await c.provisionPhysicalFan(_name.text, _room.text, caps);
                          if (!mounted) return;
                          setState(() {
                            _busy = false;
                            _error = r.ok ? null : r.error;
                          });
                          if (r.ok && mounted) {
                            c.selectDevice(r.data!.id);
                            Navigator.of(context).pop();
                            c.setTab(NavTab.display);
                            c.toast('${r.data!.name} created');
                          }
                        },
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.black),
                        )
                      : const Text('Create device'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _capSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      value: value,
      onChanged: onChanged,
    );
  }
}

// =============================================================================
//  16. SHARED DEVICE PIECES
// =============================================================================

/// Resolves the selected device and streams its canonical snapshot.
class DeviceGuard extends StatelessWidget {
  const DeviceGuard({
    super.key,
    required this.builder,
    required this.emptyTitle,
    required this.emptyMessage,
    this.emptyAction = 'Create virtual fan',
  });

  final Widget Function(BuildContext context, DeviceSnapshot snap, MemberRole? role) builder;
  final String emptyTitle;
  final String emptyMessage;
  final String emptyAction;

  @override
  Widget build(BuildContext context) {
    final AppController c = AppScope.of(context);
    final Device? device = c.selectedDevice;
    if (device == null) {
      return EmptyState(
        icon: Icons.mode_fan_off_rounded,
        title: emptyTitle,
        message: emptyMessage,
        actionLabel: emptyAction,
        onAction: () {
          if (c.myDevices.isEmpty) {
            MyDevicesPage._openCreate(context);
          } else {
            c.setTab(NavTab.devices);
          }
        },
      );
    }
    return StreamBuilder<DeviceSnapshot>(
      stream: c.watch(device.id),
      initialData: c.snapshotOf(device.id),
      builder: (BuildContext context, AsyncSnapshot<DeviceSnapshot> snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return builder(context, snap.data!, c.roleOn(device.id));
      },
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.snap, required this.onRefresh, this.pending = false});

  final DeviceSnapshot snap;
  final VoidCallback onRefresh;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final Device d = snap.device;
    final DateTime now = DateTime.now();
    final bool stale = snap.connectivity.status == ConnectivityStatus.stale;
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      d.name,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${d.deviceType.label} · id ${d.shortId}',
                      style: const TextStyle(fontSize: 11.5, color: kTextDim),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Fetch canonical state',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: <Widget>[
              BadgeChip(
                label: snap.state.power.label,
                color: snap.state.power.isOn ? kOk : kTextDim,
                icon: snap.state.power.isOn ? Icons.power_rounded : Icons.power_off_rounded,
              ),
              ConnectionBadge(connectivity: snap.connectivity),
              SourceBadge(source: snap.readings.source, deviceType: d.deviceType),
              if (pending) const BadgeChip(label: 'COMMAND PENDING', color: kInfo, icon: Icons.sync_rounded),
              if (snap.state.mode == FanMode.automatic)
                const BadgeChip(label: 'AUTO', color: kBrandViolet, icon: Icons.auto_mode_rounded, dense: true),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Icon(stale ? Icons.history_toggle_off_rounded : Icons.schedule_rounded,
                  size: 13, color: stale ? kWarn : kTextDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${stale ? 'Last reported' : 'State updated'} ${fmtAgo(snap.state.updatedAt, now)} · '
                  'rev ${snap.state.revision} · device seen ${fmtAgo(snap.connectivity.lastSeenAt, now)}',
                  style: TextStyle(fontSize: 11.5, color: stale ? kWarn : kTextDim),
                ),
              ),
            ],
          ),
          if (snap.connectivity.note != null) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: fade(kSurfaceHigh, 1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kOutline),
              ),
              child: Text(
                snap.connectivity.note!,
                style: const TextStyle(fontSize: 11.5, color: kTextDim, height: 1.35),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Manual / Automatic + humidity hysteresis thresholds.
class AutomationPanel extends StatefulWidget {
  const AutomationPanel({
    super.key,
    required this.snap,
    required this.canEdit,
    required this.onModeChanged,
    required this.onSave,
  });

  final DeviceSnapshot snap;
  final bool canEdit;
  final void Function(FanMode mode) onModeChanged;
  final void Function(AutomationSettings settings) onSave;

  @override
  State<AutomationPanel> createState() => _AutomationPanelState();
}

class _AutomationPanelState extends State<AutomationPanel> {
  late double _on;
  late double _off;
  late int _dwell;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _syncFromWidget();
  }

  @override
  void didUpdateWidget(covariant AutomationPanel old) {
    super.didUpdateWidget(old);
    if (old.snap.state.automation != widget.snap.state.automation) {
      _syncFromWidget();
    }
  }

  void _syncFromWidget() {
    final AutomationSettings a = widget.snap.state.automation;
    _on = a.onThreshold;
    _off = a.offThreshold;
    _dwell = a.minDwellSeconds;
  }

  @override
  Widget build(BuildContext context) {
    final AutomationSettings a = widget.snap.state.automation;
    final String? invalid = AutomationSettings(
      onThreshold: _on,
      offThreshold: _off,
      minDwellSeconds: _dwell,
    ).validate();
    final bool dirty = _on != a.onThreshold || _off != a.offThreshold || _dwell != a.minDwellSeconds;
    final Device d = widget.snap.device;

    return SectionCard(
      title: 'Mode & automation',
      subtitle: d.capabilities.automaticMode
          ? 'Humidity hysteresis — ON at or above the ON threshold, OFF at or below the OFF threshold'
          : 'This device does not support automatic mode',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (d.capabilities.automaticMode) ...<Widget>[
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<FanMode>(
                segments: const <ButtonSegment<FanMode>>[
                  ButtonSegment<FanMode>(value: FanMode.manual, label: Text('Manual'), icon: Icon(Icons.pan_tool_alt_rounded)),
                  ButtonSegment<FanMode>(value: FanMode.automatic, label: Text('Automatic'), icon: Icon(Icons.auto_mode_rounded)),
                ],
                selected: <FanMode>{widget.snap.state.mode},
                onSelectionChanged: widget.canEdit
                    ? (Set<FanMode> s) => widget.onModeChanged(s.first)
                    : null,
              ),
            ),
            const SizedBox(height: 16),
          ],
          _ThresholdSlider(
            label: 'Turn ON at humidity',
            value: _on,
            suffix: '%',
            color: kBrandBlue,
            enabled: widget.canEdit,
            onChanged: (double v) => setState(() => _on = v.roundToDouble()),
          ),
          const SizedBox(height: 6),
          _ThresholdSlider(
            label: 'Turn OFF at humidity',
            value: _off,
            suffix: '%',
            color: kBrandViolet,
            enabled: widget.canEdit,
            onChanged: (double v) => setState(() => _off = v.roundToDouble()),
          ),
          const SizedBox(height: 6),
          _ThresholdSlider(
            label: 'Minimum dwell time',
            value: _dwell.toDouble(),
            suffix: 's',
            color: kInfo,
            max: 120,
            divisions: 24,
            enabled: widget.canEdit,
            onChanged: (double v) => setState(() => _dwell = v.round()),
          ),
          const SizedBox(height: 10),
          if (invalid != null)
            Row(
              children: <Widget>[
                const Icon(Icons.error_outline_rounded, size: 15, color: kDanger),
                const SizedBox(width: 7),
                Expanded(child: Text(invalid, style: const TextStyle(fontSize: 12, color: kDanger))),
              ],
            ),
          if (widget.snap.state.mode == FanMode.automatic &&
              widget.snap.state.automationReason != null) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: fade(kBrandViolet, 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: fade(kBrandViolet, 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Last automation decision (simulated)',
                      style: TextStyle(fontSize: 11, color: kBrandViolet, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(widget.snap.state.automationReason!,
                      style: const TextStyle(fontSize: 12, color: kTextDim, height: 1.35)),
                ],
              ),
            ),
          ],
          if (d.deviceType == DeviceType.physical) ...<Widget>[
            const SizedBox(height: 10),
            const Text(
              'On real hardware these thresholds are synced to the ESP32 and executed locally, '
              'so automation keeps working without the app or internet. The device validates '
              'every value; the UI is not a safety boundary.',
              style: TextStyle(fontSize: 11.5, color: kTextDim, height: 1.4),
            ),
          ],
          if (dirty && invalid == null) ...<Widget>[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: _saving
                    ? null
                    : () async {
                        setState(() => _saving = true);
                        widget.onSave(AutomationSettings(
                          onThreshold: _on,
                          offThreshold: _off,
                          minDwellSeconds: _dwell,
                        ));
                        if (mounted) setState(() => _saving = false);
                      },
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('Save thresholds'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThresholdSlider extends StatelessWidget {
  const _ThresholdSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.color,
    this.suffix = '',
    this.max = 100,
    this.divisions = 20,
    this.enabled = true,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final Color color;
  final String suffix;
  final double max;
  final int divisions;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 12.5, color: kTextDim)),
            ),
            Text(
              '${value.round()}$suffix',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: enabled ? color : kTextDim),
            ),
          ],
        ),
        Slider(
          value: value.clamp(0, max),
          min: 0,
          max: max,
          divisions: divisions,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}

/// Who can see/control this fan + revocation (owner only).
class MembersCard extends StatelessWidget {
  const MembersCard({super.key, required this.snap, required this.role});

  final DeviceSnapshot snap;
  final MemberRole? role;

  @override
  Widget build(BuildContext context) {
    final AppController c = AppScope.of(context);
    final List<Membership> members = c.fans.members(snap.device.id);
    return SectionCard(
      title: 'Access',
      subtitle: 'Pairing grants an association and a role — never a permanent credential.',
      trailing: const Icon(Icons.group_rounded, size: 18, color: kTextDim),
      child: Column(
        children: <Widget>[
          for (final Membership m in members)
            Builder(builder: (BuildContext ctx) {
              final UserAccount? u = c.auth.user(m.userId);
              final bool isOwner = m.role == MemberRole.owner;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: fade(kBrandBlue, 0.16),
                      child: Text(
                        (u?.displayName.isNotEmpty == true ? u!.displayName[0] : '?').toUpperCase(),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kBrandBlue),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(u?.displayName ?? 'unknown user',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          Text('${u?.email ?? ''} · via ${m.grantedVia}',
                              style: const TextStyle(fontSize: 11, color: kTextDim),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    BadgeChip(label: m.role.label, color: isOwner ? kOk : kInfo, dense: true),
                    if (role?.canManage == true && !isOwner) ...<Widget>[
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Revoke access',
                        icon: const Icon(Icons.link_off_rounded, size: 18, color: kDanger),
                        onPressed: () async {
                          final ServiceResult<Membership> r = await c.revokeAccess(snap.device.id, m.id);
                          if (!ctx.mounted) return;
                          c.toast(r.ok ? 'Access revoked' : r.error!, ok: r.ok);
                        },
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.deviceId, this.limit = 8});

  final String deviceId;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final AppController c = AppScope.of(context);
    final List<DeviceEvent> events = c.backend.eventsFor(deviceId).take(limit).toList();
    return SectionCard(
      title: 'Activity',
      subtitle: 'Bounded history of commands, state changes and pairing events.',
      trailing: const Icon(Icons.history_rounded, size: 18, color: kTextDim),
      child: events.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No activity yet.', style: TextStyle(fontSize: 12.5, color: kTextDim)),
            )
          : Column(
              children: <Widget>[
                for (final DeviceEvent e in events)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          e.ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                          size: 15,
                          color: e.ok ? kOk : kDanger,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(e.message, style: const TextStyle(fontSize: 12.5, height: 1.35)),
                              const SizedBox(height: 2),
                              Text('${fmtClock(e.at)} · ${e.kind.name}${e.actor.isEmpty ? '' : ' · ${e.actor}'}',
                                  style: const TextStyle(fontSize: 10.5, color: kTextDim)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// =============================================================================
//  17. PAIRING CODE CARD  (Fan Display side)
// =============================================================================

class PairingCodeCard extends StatefulWidget {
  const PairingCodeCard({super.key, required this.snap, required this.role});

  final DeviceSnapshot snap;
  final MemberRole? role;

  @override
  State<PairingCodeCard> createState() => _PairingCodeCardState();
}

class _PairingCodeCardState extends State<PairingCodeCard> {
  PairingCodeOffer? _offer;
  Timer? _ticker;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Only tick while a code is actually live (keeps idle screens quiet).
    if (AppScope.read(context).pairing.activeCode(widget.snap.device.id) != null) {
      _startTicker();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final PairingCodeRecord? live =
          AppScope.of(context).pairing.activeCode(widget.snap.device.id);
      if (live == null) {
        _stopTicker();
        if (mounted) setState(() => _offer = null);
        return;
      }
      setState(() {});
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }

  Future<void> _generate() async {
    final AppController c = AppScope.of(context);
    setState(() => _busy = true);
    final ServiceResult<PairingCodeOffer> r = await c.createPairingCode(widget.snap.device.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _offer = r.data;
    });
    if (r.ok) {
      _startTicker();
    } else {
      c.toast(r.error!, ok: false);
    }
  }

  Future<void> _revoke() async {
    final AppController c = AppScope.of(context);
    await c.revokePairingCode(widget.snap.device.id);
    if (!mounted) return;
    _stopTicker();
    setState(() => _offer = null);
    c.toast('Pairing code revoked');
  }

  @override
  Widget build(BuildContext context) {
    final AppController c = AppScope.of(context);
    final PairingCodeRecord? stored = c.pairing.activeCode(widget.snap.device.id);
    final DateTime now = DateTime.now();
    final bool mineLive = _offer != null && stored != null && _offer!.record.id == stored.id;
    final Duration remaining = stored == null ? Duration.zero : stored.expiresAt.difference(now);

    return SectionCard(
      title: 'Pairing code',
      subtitle: 'Short-lived, single-use, hashed at rest. Grants the Controller role.',
      trailing: IconButton(
        tooltip: 'Generate a new code',
        onPressed: widget.role == MemberRole.viewer || _busy ? null : _generate,
        icon: const Icon(Icons.refresh_rounded, size: 19),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (mineLive && _offer != null) ...<Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: <Color>[fade(kBrandBlue, 0.16), fade(kBrandViolet, 0.16)],
                ),
                border: Border.all(color: fade(kBrandBlue, 0.45)),
              ),
              child: Column(
                children: <Widget>[
                  SelectableText(
                    _offer!.formatted,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 7,
                      color: kText,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Icon(Icons.timer_outlined, size: 15, color: kWarn),
                      const SizedBox(width: 6),
                      Text(
                        'expires in ${fmtCountdown(remaining)}',
                        style: const TextStyle(fontSize: 12.5, color: kWarn, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _revoke,
                    icon: const Icon(Icons.link_off_rounded, size: 17),
                    label: const Text('Revoke'),
                  ),
                ),
              ],
            ),
          ] else if (stored != null) ...<Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: fade(kInfo, 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: fade(kInfo, 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Row(
                    children: <Widget>[
                      Icon(Icons.key_rounded, size: 16, color: kInfo),
                      SizedBox(width: 8),
                      Text('A code is active', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'For security the raw code is only shown on the screen that generated it '
                    '(only its hash is stored). Generate a new code here to invalidate it.',
                    style: TextStyle(fontSize: 11.5, color: kTextDim, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  Text('Expires in ${fmtCountdown(remaining)}',
                      style: const TextStyle(fontSize: 12, color: kWarn, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.role == MemberRole.viewer ? null : _generate,
                icon: const Icon(Icons.autorenew_rounded, size: 17),
                label: const Text('Generate a new code'),
              ),
            ),
          ] else ...<Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kSurfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kOutline),
              ),
              child: const Text(
                'No active pairing code. Generate one, then enter it on the other device '
                'under Remote → Enter pairing code. It expires automatically and can only '
                'be used once.',
                style: TextStyle(fontSize: 12, color: kTextDim, height: 1.45),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: widget.role == MemberRole.viewer || _busy ? null : _generate,
                icon: _busy
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.black),
                      )
                    : const Icon(Icons.qr_code_2_rounded, size: 18),
                label: Text(_busy ? 'Generating…' : 'Generate pairing code'),
              ),
            ),
          ],
          if (widget.role == MemberRole.viewer) ...<Widget>[
            const SizedBox(height: 10),
            const Text(
              'Your role (Viewer) cannot issue pairing codes.',
              style: TextStyle(fontSize: 11.5, color: kTextDim),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
//  18. SIMULATION PANEL  (virtual devices only — never shown for hardware)
// =============================================================================

class SimulationPanel extends StatelessWidget {
  const SimulationPanel({super.key, required this.snap, required this.canEdit});

  final DeviceSnapshot snap;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final AppController c = AppScope.of(context);
    final VirtualEnvironment env = c.backend.envOf(snap.device.id);
    return SectionCard(
      accent: kWarn,
      title: 'Simulation controls',
      trailing: const BadgeChip(label: 'SIMULATION CONTROLS', color: kWarn, icon: Icons.science_rounded, dense: true),
      subtitle: 'Demo levers for the virtual environment. Values stay labelled SIMULATED DATA.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'These controls only exist because this is a virtual device. A physical '
            'ESP32 never shows them and never receives simulated readings.',
            style: TextStyle(fontSize: 11.5, color: kTextDim, height: 1.4),
          ),
          const SizedBox(height: 14),
          const Text('Humidity', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <(String, double)>[
              ('−10%', -10),
              ('−5%', -5),
              ('−1%', -1),
              ('+1%', 1),
              ('+5%', 5),
              ('+10%', 10),
            ]
                .map(
                  ((String, double) e) => OutlinedButton(
                    onPressed: canEdit
                        ? () => c.nudgeEnvironment(snap.device.id, humidityDelta: e.$2)
                        : null,
                    child: Text(e.$1),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          const Text('Temperature', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <(String, double)>[
              ('−2 °C', -2),
              ('−0.5 °C', -0.5),
              ('+0.5 °C', 0.5),
              ('+2 °C', 2),
            ]
                .map(
                  ((String, double) e) => OutlinedButton(
                    onPressed: canEdit
                        ? () => c.nudgeEnvironment(snap.device.id, temperatureDelta: e.$2)
                        : null,
                    child: Text(e.$1),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Room target: ${fmtHum(env.targetHumidityPercent)} RH · ${fmtTemp(env.targetTemperatureC)}',
                  style: const TextStyle(fontSize: 11.5, color: kTextDim),
                ),
              ),
            ],
          ),
          if (!canEdit) ...<Widget>[
            const SizedBox(height: 10),
            const Text('Your role cannot change simulated values.',
                style: TextStyle(fontSize: 11.5, color: kTextDim)),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
//  19. FAN DISPLAY PAGE
// =============================================================================

class FanDisplayPage extends StatelessWidget {
  const FanDisplayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DeviceGuard(
      emptyTitle: 'No fan selected',
      emptyMessage: 'Pick a device in My Devices, or create a virtual fan to open its Fan Display.',
      builder: (BuildContext context, DeviceSnapshot snap, MemberRole? role) {
        final AppController c = AppScope.of(context);
        final Device d = snap.device;
        final bool pending = c.isPending(d.id);
        final bool canEdit = role?.canCommand ?? false;
        final bool wide = MediaQuery.of(context).size.width >= 1000;

        final Widget stage = SectionCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: <Widget>[
              FanAnimation(
                running: snap.state.power.isOn && !pending,
                speedPercent: snap.state.speed ?? 60,
                unknown: snap.state.power == PowerState.unknown,
                size: wide ? 260 : 230,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    snap.state.power.isOn ? Icons.power_rounded : Icons.power_off_rounded,
                    color: snap.state.power.isOn ? kOk : kTextDim,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    snap.state.power.label,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: snap.state.power.isOn ? kOk : kTextDim,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Animation reflects the last reported state${pending ? ' (command pending)' : ''}'
                '${d.deviceType == DeviceType.physical ? ' — it is not proof the motor is turning' : ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, color: kTextDim, height: 1.35),
              ),
              if (d.capabilities.speedControl) ...<Widget>[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(Icons.speed_rounded, size: 16, color: kTextDim),
                    const SizedBox(width: 7),
                    Text(
                      'Speed ${fmtSpeed(snap.state.speed)}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );

        final Widget sensors = SectionCard(
          title: 'Sensors',
          subtitle: d.deviceType == DeviceType.virtual
              ? 'Simulated readings'
              : 'Reported by authenticated device telemetry',
          child: Row(
            children: <Widget>[
              if (d.capabilities.temperatureSensor)
                SensorTile(
                  icon: Icons.thermostat_rounded,
                  label: 'Temperature',
                  value: fmtTemp(snap.readings.temperatureC),
                  color: kBrandBlue,
                  footer: 'observed ${fmtAgo(snap.readings.observedAt, DateTime.now())}',
                )
              else
                const Expanded(child: _UnsupportedSensor(label: 'Temperature')),
              const SizedBox(width: 12),
              if (d.capabilities.humiditySensor)
                SensorTile(
                  icon: Icons.water_drop_rounded,
                  label: 'Relative humidity',
                  value: fmtHum(snap.readings.humidityPercent),
                  color: kBrandViolet,
                  footer: 'observed ${fmtAgo(snap.readings.observedAt, DateTime.now())}',
                )
              else
                const Expanded(child: _UnsupportedSensor(label: 'Humidity')),
            ],
          ),
        );

        final Widget automation = AutomationPanel(
          snap: snap,
          canEdit: canEdit,
          onModeChanged: (FanMode m) async {
            final CommandResult r = await c.setMode(d.id, m);
            c.toast(r.message, ok: r.isSuccess);
          },
          onSave: (AutomationSettings s) async {
            final ServiceResult<DeviceSnapshot> r = await c.updateAutomation(d.id, s);
            c.toast(r.ok ? 'Automation updated' : r.error!, ok: r.ok);
          },
        );

        final Widget right = Column(
          children: <Widget>[
            automation,
            const SizedBox(height: 14),
            PairingCodeCard(snap: snap, role: role),
          ],
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.monitor_rounded, size: 16, color: kBrandBlue),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Fan Display',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kTextDim)),
                  ),
                  Text('rev ${snap.state.revision}', style: const TextStyle(fontSize: 11, color: kTextDim)),
                ],
              ),
              const SizedBox(height: 12),
              _StatusHeader(
                snap: snap,
                pending: pending,
                onRefresh: () async {
                  final CommandResult r = await c.refresh(d.id);
                  c.toast(r.message, ok: r.isSuccess);
                },
              ),
              const SizedBox(height: 14),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: Column(children: <Widget>[stage, const SizedBox(height: 14), sensors])),
                    const SizedBox(width: 14),
                    Expanded(child: right),
                  ],
                )
              else ...<Widget>[
                stage,
                const SizedBox(height: 14),
                sensors,
                const SizedBox(height: 14),
                automation,
                const SizedBox(height: 14),
                PairingCodeCard(snap: snap, role: role),
              ],
              if (d.deviceType == DeviceType.virtual) ...<Widget>[
                const SizedBox(height: 14),
                SimulationPanel(snap: snap, canEdit: canEdit),
              ],
              const SizedBox(height: 14),
              MembersCard(snap: snap, role: role),
              const SizedBox(height: 14),
              ActivityCard(deviceId: d.id),
            ],
          ),
        );
      },
    );
  }
}

class _UnsupportedSensor extends StatelessWidget {
  const _UnsupportedSensor({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.sensors_off_rounded, size: 16, color: kTextDim),
              const SizedBox(width: 7),
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 11.5, color: kTextDim, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text('not supported', style: TextStyle(fontSize: 13, color: kTextDim)),
        ],
      ),
    );
  }
}

// =============================================================================
//  20. REMOTE CONTROL PAGE
// =============================================================================

class RemoteControlPage extends StatelessWidget {
  const RemoteControlPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DeviceGuard(
      emptyTitle: 'No fan to control',
      emptyMessage: 'Create a virtual fan, or enter a pairing code from a Fan Display to get access '
          'to someone else\'s fan.',
      builder: (BuildContext context, DeviceSnapshot snap, MemberRole? role) =>
          _RemoteBody(snap: snap, role: role),
    );
  }
}

class _RemoteBody extends StatefulWidget {
  const _RemoteBody({required this.snap, required this.role});

  final DeviceSnapshot snap;
  final MemberRole? role;

  @override
  State<_RemoteBody> createState() => _RemoteBodyState();
}

class _RemoteBodyState extends State<_RemoteBody> {
  String? _busyAction;
  String? _commandNote;
  bool _commandOk = true;

  Future<void> _run(String action, Future<CommandResult> work) async {
    setState(() {
      _busyAction = action;
      _commandNote = null;
    });
    final CommandResult r = await work;
    if (!mounted) return;
    setState(() {
      _busyAction = null;
      _commandNote = r.message;
      _commandOk = r.isSuccess;
    });
    AppScope.of(context).toast(r.message, ok: r.isSuccess);
  }

  @override
  Widget build(BuildContext context) {
    final AppController c = AppScope.of(context);
    final DeviceSnapshot snap = widget.snap;
    final Device d = snap.device;
    final MemberRole? role = widget.role;
    final bool canControl = role?.canCommand ?? false;
    final ConnectivityStatus conn = snap.connectivity.status;
    final bool unusable = conn == ConnectivityStatus.offline && d.deviceType == DeviceType.physical;
    final bool controlsEnabled = canControl && !unusable && _busyAction == null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.settings_remote_rounded, size: 16, color: kBrandBlue),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Remote Control',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kTextDim)),
              ),
              Text('rev ${snap.state.revision}', style: const TextStyle(fontSize: 11, color: kTextDim)),
            ],
          ),
          const SizedBox(height: 12),
          _FanPicker(current: d),
          const SizedBox(height: 14),
          const _PairingInput(),
          const SizedBox(height: 14),
          _StatusHeader(
            snap: snap,
            pending: c.isPending(d.id),
            onRefresh: () async {
              final CommandResult r = await c.refresh(d.id);
              c.toast(r.message, ok: r.isSuccess);
            },
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Controls',
            subtitle: canControl
                ? 'Desired-state commands. Success is shown only after confirmation.'
                : 'Your role is read-only (${role?.label ?? 'no access'})',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (unusable) ...<Widget>[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: fade(kDanger, 0.10),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: fade(kDanger, 0.45)),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.cloud_off_rounded, size: 17, color: kDanger),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            '${snap.connectivity.note ?? 'Device is offline'}. Controls stay disabled — '
                            'the app will not fake a hardware response.',
                            style: const TextStyle(fontSize: 12, color: kDanger, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Row(
                  children: <Widget>[
                    Expanded(
                      child: CommandButton(
                        label: 'Turn ON',
                        icon: Icons.power_rounded,
                        color: kOk,
                        filled: snap.state.power.isOn,
                        enabled: controlsEnabled,
                        pending: _busyAction == 'on' || (c.isPending(d.id) && snap.state.desiredPower == PowerState.on),
                        onPressed: () => _run('on', c.setPower(d.id, true)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CommandButton(
                        label: 'Turn OFF',
                        icon: Icons.power_off_rounded,
                        color: kText,
                        filled: !snap.state.power.isOn && snap.state.power != PowerState.unknown,
                        enabled: controlsEnabled,
                        pending: _busyAction == 'off' || (c.isPending(d.id) && snap.state.desiredPower == PowerState.off),
                        onPressed: () => _run('off', c.setPower(d.id, false)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Reported: ${snap.state.power.label}'
                        '${snap.state.desiredPower != null && snap.state.desiredPower != snap.state.power ? ' · requested ${snap.state.desiredPower!.label}' : ''}',
                        style: const TextStyle(fontSize: 12, color: kTextDim),
                      ),
                    ),
                  ],
                ),
                if (_commandNote != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Icon(
                        _commandOk ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                        size: 15,
                        color: _commandOk ? kOk : kDanger,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _commandNote!,
                          style: TextStyle(fontSize: 12, color: _commandOk ? kOk : kDanger),
                        ),
                      ),
                    ],
                  ),
                ],
                if (d.capabilities.speedControl) ...<Widget>[
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.speed_rounded, size: 16, color: kTextDim),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Speed ${fmtSpeed(snap.state.speed)}',
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (_busyAction == 'speed')
                        const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2, color: kBrandBlue),
                        ),
                    ],
                  ),
                  Slider(
                    value: (snap.state.speed ?? 0).clamp(0, 100).toDouble(),
                    max: 100,
                    divisions: 10,
                    onChanged: controlsEnabled
                        ? (double v) {
                            // debounce-ish: send on release
                          }
                        : null,
                    onChangeEnd: controlsEnabled
                        ? (double v) => _run('speed', c.setSpeed(d.id, v.round()))
                        : null,
                  ),
                  Wrap(
                    spacing: 8,
                    children: <int>[0, 25, 50, 75, 100]
                        .map(
                          (int p) => ChoiceChip(
                            label: Text(p == 0 ? 'Auto-off' : '$p%'),
                            selected: snap.state.speed == p,
                            showCheckmark: false,
                            onSelected: controlsEnabled ? (bool _) => _run('speed', c.setSpeed(d.id, p)) : null,
                          ),
                        )
                        .toList(),
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: 14),
                  const Text(
                    'This device does not support speed control, so no speed control is shown.',
                    style: TextStyle(fontSize: 11.5, color: kTextDim),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          AutomationPanel(
            snap: snap,
            canEdit: canControl,
            onModeChanged: (FanMode m) async {
              final CommandResult r = await c.setMode(d.id, m);
              c.toast(r.message, ok: r.isSuccess);
            },
            onSave: (AutomationSettings s) async {
              final ServiceResult<DeviceSnapshot> r = await c.updateAutomation(d.id, s);
              c.toast(r.ok ? 'Automation updated' : r.error!, ok: r.ok);
            },
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Connection',
            subtitle: 'Last seen and freshness of the canonical state.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _InfoRow(
                  label: 'Device seen',
                  value: fmtAgo(snap.connectivity.lastSeenAt, DateTime.now()),
                ),
                _InfoRow(label: 'State updated', value: fmtAgo(snap.state.updatedAt, DateTime.now())),
                _InfoRow(label: 'Readings observed', value: fmtAgo(snap.readings.observedAt, DateTime.now())),
                _InfoRow(label: 'State revision', value: '${snap.state.revision}'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final CommandResult r = await c.refresh(d.id);
                      c.toast(r.message, ok: r.isSuccess);
                    },
                    icon: const Icon(Icons.sync_rounded, size: 17),
                    label: const Text('Fetch canonical state (reconnect recovery)'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (role != MemberRole.owner && role != null)
            SectionCard(
              title: 'Unpair',
              subtitle: 'Removes this device\'s access to the fan. The owner can also revoke you at any time.',
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: kDanger, side: BorderSide(color: fade(kDanger, 0.6))),
                  onPressed: () async {
                    final List<Membership> mine = c.fans
                        .members(d.id)
                        .where((Membership m) => m.userId == c.actorId)
                        .toList();
                    if (mine.isEmpty) return;
                    final ServiceResult<Membership> r = await c.revokeAccess(d.id, mine.first.id);
                    c.toast(r.ok ? 'Unpaired — you no longer have access' : r.error!, ok: r.ok);
                    if (r.ok) c.selectDevice('');
                  },
                  icon: const Icon(Icons.link_off_rounded, size: 17),
                  label: const Text('Disconnect this device'),
                ),
              ),
            ),
          const SizedBox(height: 14),
          ActivityCard(deviceId: d.id, limit: 6),
        ],
      ),
    );
  }
}

class _FanPicker extends StatelessWidget {
  const _FanPicker({required this.current});

  final Device current;

  @override
  Widget build(BuildContext context) {
    final AppController c = AppScope.of(context);
    final List<Device> devices = c.myDevices;
    if (devices.length < 2) return const SizedBox.shrink();
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: <Widget>[
          const Icon(Icons.list_alt_rounded, size: 17, color: kTextDim),
          const SizedBox(width: 10),
          const Text('Authorised fan', style: TextStyle(fontSize: 12.5, color: kTextDim)),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<String>(
              value: current.id,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: devices
                  .map(
                    (Device d) => DropdownMenuItem<String>(
                      value: d.id,
                      child: Text('${d.name} · ${d.deviceType.label}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  )
                  .toList(),
              onChanged: (String? id) {
                if (id != null) c.selectDevice(id);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PairingInput extends StatefulWidget {
  const _PairingInput();

  @override
  State<_PairingInput> createState() => _PairingInputState();
}

class _PairingInputState extends State<_PairingInput> {
  final TextEditingController _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final AppController c = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    final ServiceResult<Membership> r = await c.redeemCode(_code.text, c.session?.deviceLabel ?? 'this device');
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _success = 'Paired as ${r.data!.role.label}. The fan now appears in your list.';
        _code.clear();
        c.selectDevice(r.data!.deviceId);
        c.toast('Paired as ${r.data!.role.label}');
      } else {
        _error = r.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Connect to a fan',
      subtitle: 'Enter the 6-character code shown on the Fan Display. Codes are single-use and expire quickly.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 7,
                  onSubmitted: (_) => _pair(),
                  decoration: const InputDecoration(
                    labelText: 'Pairing code',
                    hintText: 'ABC123',
                    counterText: '',
                    prefixIcon: Icon(Icons.key_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _busy ? null : _pair,
                  child: _busy
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.black),
                        )
                      : const Text('Pair'),
                ),
              ),
            ],
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                const Icon(Icons.error_outline_rounded, size: 15, color: kDanger),
                const SizedBox(width: 7),
                Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12, color: kDanger))),
              ],
            ),
          ],
          if (_success != null) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                const Icon(Icons.check_circle_rounded, size: 15, color: kOk),
                const SizedBox(width: 7),
                Expanded(child: Text(_success!, style: const TextStyle(fontSize: 12, color: kOk))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5, color: kTextDim))),
          Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// =============================================================================
//  21. SELF-TESTS  (pure + service-level checks, runnable inside the app)
// =============================================================================

class TestResult {
  const TestResult(this.name, this.passed, this.detail);

  final String name;
  final bool passed;
  final String detail;
}

Future<List<TestResult>> runSelfTests() async {
  final List<TestResult> results = <TestResult>[];
  void check(String name, bool ok, String detail) => results.add(TestResult(name, ok, detail));

  // --- crypto ----------------------------------------------------------------
  check(
    'SHA-256 known vector ("abc")',
    Sha256.hash('abc') == 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    Sha256.hash('abc'),
  );
  check(
    'Salted hashing is salt-sensitive',
    Sha256.salted('s1', 'code') != Sha256.salted('s2', 'code'),
    'different salts → different digests',
  );

  // --- automation (pure) ------------------------------------------------------
  final DateTime now = DateTime(2026, 1, 1, 12);
  AutomationDecision dec(
    double? h, {
    bool power = false,
    double on = 70,
    double off = 60,
    int dwell = 0,
    Duration age = Duration.zero,
    DateTime? lastSwitch,
  }) {
    return evaluateAutomation(
      humidityPercent: h,
      currentPower: power,
      onThreshold: on,
      offThreshold: off,
      minDwell: Duration(seconds: dwell),
      now: now,
      observedAt: now.subtract(age),
      lastSwitchAt: lastSwitch,
    );
  }

  check('Just below ON threshold (69.9) holds OFF',
      dec(69.9).desiredPower == null && !dec(69.9).changed, dec(69.9).reason);
  check('Exactly at ON threshold (70) turns ON', dec(70).desiredPower == true, dec(70).reason);
  check('Between thresholds (65) holds previous state', dec(65, power: true).desiredPower == null,
      dec(65, power: true).reason);
  check('Exactly at OFF threshold (60) turns OFF', dec(60, power: true).desiredPower == false,
      dec(60, power: true).reason);
  check('Just above OFF threshold (60.1) holds previous state', dec(60.1, power: true).desiredPower == null,
      dec(60.1, power: true).reason);
  check('Invalid thresholds (off >= on) fail safe',
      dec(80, on: 50, off: 60).desiredPower == null && dec(80, on: 50, off: 60).reason.contains('invalid'),
      dec(80, on: 50, off: 60).reason);
  check('Missing humidity reading fails safe', dec(null).desiredPower == null, dec(null).reason);
  check('Stale humidity reading fails safe', dec(95, age: const Duration(minutes: 5)).desiredPower == null,
      dec(95, age: const Duration(minutes: 5)).reason);
  check(
    'Dwell time blocks a fast flip',
    dec(95, dwell: 30, lastSwitch: now.subtract(const Duration(seconds: 5))).desiredPower == null,
    dec(95, dwell: 30, lastSwitch: now.subtract(const Duration(seconds: 5))).reason,
  );
  check(
    'Dwell time expires and allows the flip',
    dec(95, dwell: 10, lastSwitch: now.subtract(const Duration(seconds: 30))).desiredPower == true,
    dec(95, dwell: 10, lastSwitch: now.subtract(const Duration(seconds: 30))).reason,
  );

  // --- device adapters --------------------------------------------------------
  final Device virtualNoSpeed = Device(
    id: 'test-dev',
    ownerUserId: 'u',
    name: 'Test',
    deviceType: DeviceType.virtual,
    capabilities: const Capabilities(speedControl: false),
    createdAt: now,
  );
  final DeviceState baseState = DeviceState.initial();
  final VirtualFanAdapter fastVirtual = VirtualFanAdapter(
    latency: () => Duration.zero,
    shouldFail: () => false,
  );
  final AdapterAck ackSpeed = await fastVirtual.applyCommand(
    DeviceCommand(commandId: 'c1', device: virtualNoSpeed, current: baseState, speed: 50),
  );
  check('Virtual adapter refuses speed when unsupported', ackSpeed.status == CommandStatus.unsupported,
      ackSpeed.message);

  final AdapterAck ackPower = await fastVirtual.applyCommand(
    DeviceCommand(commandId: 'c2', device: virtualNoSpeed, current: baseState, power: PowerState.on),
  );
  check('Virtual adapter confirms power when supported',
      ackPower.status == CommandStatus.confirmed && ackPower.power == PowerState.on, ackPower.message);

  final Esp32FanAdapter esp32 = const Esp32FanAdapter();
  final AdapterAck ackEsp = await esp32.applyCommand(
    DeviceCommand(
      commandId: 'c3',
      device: virtualNoSpeed.copyWithDeviceType(DeviceType.physical),
      current: baseState,
      power: PowerState.on,
    ),
  );
  check('ESP32 stub never confirms a command', ackEsp.status != CommandStatus.confirmed, ackEsp.message);

  final AdapterReadings espReadings = await esp32.readSensors(virtualNoSpeed);
  check('ESP32 stub never fabricates readings', espReadings.readings == null, espReadings.message);

  // --- service level: pairing, permissions, physical honesty ------------------
  final DemoBackend backend = DemoBackend();
  backend.attachAdapters(virtual: fastVirtual, esp32: esp32);
  final AuthService auth = AuthService();
  final FanService fans = FanService(backend: backend, auth: auth);
  final PairingService pair = PairingService(backend: backend, auth: auth);

  final ServiceResult<Session> su = await auth.signUp(
    email: 'tester@airorhythm.test',
    password: 'password123',
    displayName: 'Tester',
  );
  final String uid = su.data!.userId;
  final Device testFan = (await fans.createVirtualFan(userId: uid, name: 'Test fan')).data!;

  final ServiceResult<PairingCodeOffer> offer = await pair.createCode(deviceId: testFan.id, userId: uid);
  check('Pairing code is issued with 6 characters',
      offer.ok && offer.data!.code.length == 6, offer.ok ? offer.data!.formatted : offer.error!);

  final ServiceResult<Session> pairer = await auth.signUp(
    email: 'pairer@airorhythm.test',
    password: 'password123',
    displayName: 'Pairer',
  );
  final String pairerId = pairer.data!.userId;

  final ServiceResult<Membership> wrong = await pair.redeem(
    code: 'ZZZZZZ',
    userId: pairerId,
    sessionToken: pairer.data!.token,
  );
  check('Wrong pairing code is rejected', !wrong.ok, wrong.error ?? '');

  final ServiceResult<Membership> right = await pair.redeem(
    code: offer.data!.code,
    userId: pairerId,
    sessionToken: pairer.data!.token,
  );
  check('Correct pairing code grants Controller role',
      right.ok && right.data!.role == MemberRole.controller,
      right.ok ? right.data!.role.label : right.error!);

  final ServiceResult<Membership> reuse = await pair.redeem(
    code: offer.data!.code,
    userId: pairerId,
    sessionToken: pairer.data!.token,
  );
  check('Pairing code cannot be reused (single use)', !reuse.ok, reuse.error ?? '');

  final CommandResult controllerCanCommand =
      await fans.setPower(testFan.id, pairerId, true);
  check('Paired controller can command the fan', controllerCanCommand.isSuccess,
      controllerCanCommand.message);

  backend.settings.pairingExpirySeconds = 1;
  final ServiceResult<PairingCodeOffer> shortLived = await pair.createCode(deviceId: testFan.id, userId: uid);
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  final ServiceResult<Membership> expired = await pair.redeem(
    code: shortLived.data!.code,
    userId: uid,
    sessionToken: su.data!.token,
  );
  check('Expired pairing code is rejected', !expired.ok, expired.error ?? '');

  final ServiceResult<Session> other = await auth.signUp(
    email: 'viewer@airorhythm.test',
    password: 'password123',
    displayName: 'Viewer',
  );
  await backend.addMembership(Membership(
    id: newId('mem'),
    deviceId: testFan.id,
    userId: other.data!.userId,
    role: MemberRole.viewer,
    createdAt: DateTime.now(),
    grantedVia: 'test',
  ));
  final CommandResult viewerCommand = await fans.setPower(testFan.id, other.data!.userId, true);
  check('Viewer role cannot send commands', viewerCommand.status == CommandStatus.rejected, viewerCommand.message);

  final ServiceResult<Device> phys = await fans.provisionPhysicalFan(userId: uid, name: 'ESP32 prototype');
  final DeviceSnapshot? physSnap = backend.snapshotSync(phys.data!.id);
  check('Physical device starts offline with no telemetry',
      physSnap != null &&
          physSnap.connectivity.status == ConnectivityStatus.offline &&
          !physSnap.readings.hasAny,
      physSnap == null ? 'missing' : '${physSnap.connectivity.status.label}, readings=${physSnap.readings.hasAny}');

  backend.tick(); // simulation tick must not invent hardware data
  final DeviceSnapshot? physAfter = backend.snapshotSync(phys.data!.id);
  check('Simulation tick never writes virtual data into a physical device',
      physAfter != null && !physAfter.readings.hasAny, 'readings empty: ${physAfter?.readings.hasAny == false}');

  final CommandResult physCommand = await fans.setPower(phys.data!.id, uid, true);
  check('Command to offline hardware is reported as not delivered',
      physCommand.status == CommandStatus.offline, physCommand.message);

  final ServiceResult<DeviceSnapshot> badAuto = await fans.updateAutomation(
    testFan.id,
    uid,
    const AutomationSettings(onThreshold: 40, offThreshold: 80),
  );
  check('Invalid automation thresholds are rejected by the service', !badAuto.ok, badAuto.error ?? '');

  backend.dispose();
  return results;
}

extension _DeviceTypeSwap on Device {
  Device copyWithDeviceType(DeviceType t) => Device(
        id: id,
        ownerUserId: ownerUserId,
        name: name,
        deviceType: t,
        capabilities: capabilities,
        createdAt: createdAt,
        room: room,
        firmware: firmware,
      );
}

// =============================================================================
//  22. SETTINGS PAGE
// =============================================================================

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppController c = AppScope.of(context);
    return AnimatedBuilder(
      animation: c,
      builder: (BuildContext context, _) {
        final UserAccount? u = c.user;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: <Widget>[
            const Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Account',
              subtitle: 'Authentication is required before pairing or control.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: fade(kBrandBlue, 0.16),
                        child: Text(
                          (u?.displayName.isNotEmpty == true ? u!.displayName[0] : '?').toUpperCase(),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kBrandBlue),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(u?.displayName ?? '—', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            Text(u?.email ?? '—', style: const TextStyle(fontSize: 12, color: kTextDim)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Signed-in devices',
                      style: TextStyle(fontSize: 12.5, color: kTextDim, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  for (final Session s in c.sessions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.devices_rounded, size: 16, color: kTextDim),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(s.deviceLabel,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                          Text('${fmtAgo(s.lastSeenAt, DateTime.now())}',
                              style: const TextStyle(fontSize: 11, color: kTextDim)),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => c.signOutSession(s.token),
                            child: const Text('Sign out'),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: kSurface,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                        ),
                        builder: (BuildContext ctx) => const _AddSessionSheet(),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('Open another device session'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sessions share the same simulated backend, so this is how the two-device '
                    'journey is demonstrated in a single browser: Fan Display in one session, '
                    'Remote (with a pairing code) in the other.',
                    style: TextStyle(fontSize: 11.5, color: kTextDim, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _ServiceConfiguration(),
            const SizedBox(height: 14),
            const _SelfTestCard(),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Danger zone',
              subtitle: 'Destructive actions for this demo workspace.',
              accent: kDanger,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kDanger,
                      side: BorderSide(color: fade(kDanger, 0.6)),
                    ),
                    onPressed: c.selectedDevice == null || c.roleOn(c.selectedDevice!.id) != MemberRole.owner
                        ? null
                        : () async {
                            final Device d = c.selectedDevice!;
                            final bool? confirm = await showDialog<bool>(
                              context: context,
                              builder: (BuildContext ctx) => AlertDialog(
                                backgroundColor: kSurface,
                                title: const Text('Delete device?'),
                                content: Text('"${d.name}" and its pairings will be removed from this demo workspace.'),
                                actions: <Widget>[
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: kDanger),
                                    onPressed: () => Navigator.of(ctx).pop(true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await c.deleteDevice(d.id);
                              c.selectDevice('');
                              c.toast('${d.name} deleted');
                            }
                          },
                    icon: const Icon(Icons.delete_outline_rounded, size: 17),
                    label: const Text('Delete selected device (owner only)'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kDanger,
                      side: BorderSide(color: fade(kDanger, 0.6)),
                    ),
                    onPressed: () {
                      for (final Session s in List<Session>.from(c.sessions)) {
                        c.signOutSession(s.token);
                      }
                    },
                    icon: const Icon(Icons.logout_rounded, size: 17),
                    label: const Text('Sign out every device session'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const _DocsCard(),
            const SizedBox(height: 14),
            SectionCard(
              title: 'About this build',
              subtitle: 'Single-file Flutter prototype for FlutLab.io / DartPad.',
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Everything lives in main.dart: domain model, simulation engine, device '
                    'adapters, service layer, repository and UI. No packages, no assets — the '
                    'logo and fan animation are painted in code.',
                    style: TextStyle(fontSize: 12, color: kTextDim, height: 1.45),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Auth, database and realtime are simulated in memory behind the same '
                    'interfaces a Supabase/REST backend would implement, so the UI and device '
                    'contract survive the swap unchanged.',
                    style: TextStyle(fontSize: 12, color: kTextDim, height: 1.45),
                  ),
                  SizedBox(height: 12),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: <Widget>[
                      BadgeChip(label: 'Flutter · single file', color: kBrandBlue, dense: true),
                      BadgeChip(label: 'No third-party packages', color: kOk, dense: true),
                      BadgeChip(label: 'Virtual now · ESP32 ready', color: kBrandViolet, dense: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ServiceConfiguration extends StatelessWidget {
  const _ServiceConfiguration();

  @override
  Widget build(BuildContext context) {
    final AppController c = AppScope.of(context);
    final DemoSettings s = c.backend.settings;
    return SectionCard(
      title: 'Service simulation',
      subtitle: 'Normally these live in server-side configuration.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SettingSlider(
            label: 'Round-trip latency',
            value: s.roundTripMs.toDouble(),
            min: 0,
            max: 3000,
            divisions: 30,
            display: '${s.roundTripMs} ms',
            onChanged: (double v) {
              s.roundTripMs = v.round();
              c.touch();
            },
          ),
          _SettingSlider(
            label: 'Command timeout',
            value: s.commandTimeoutMs.toDouble(),
            min: 500,
            max: 10000,
            divisions: 19,
            display: '${(s.commandTimeoutMs / 1000).toStringAsFixed(1)} s',
            onChanged: (double v) {
              s.commandTimeoutMs = v.round();
              c.touch();
            },
          ),
          _SettingSlider(
            label: 'Telemetry tick (simulation engine)',
            value: s.tickSeconds.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            display: '${s.tickSeconds} s',
            onChanged: (double v) {
              s.tickSeconds = v.round();
              c.backend.restartTicker();
              c.touch();
            },
          ),
          _SettingSlider(
            label: 'Pairing code lifetime',
            value: s.pairingExpirySeconds.toDouble(),
            min: 30,
            max: 600,
            divisions: 19,
            display: '${s.pairingExpirySeconds} s',
            onChanged: (double v) {
              s.pairingExpirySeconds = v.round();
              c.touch();
            },
          ),
          _SettingSlider(
            label: 'Max attempts per code',
            value: s.maxCodeAttempts.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            display: '${s.maxCodeAttempts}',
            onChanged: (double v) {
              s.maxCodeAttempts = v.round();
              c.touch();
            },
          ),
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Inject command failures', style: TextStyle(fontSize: 13.5)),
            subtitle: const Text(
              'Demo only: makes virtual commands randomly fail so you can see the '
              'rejected / unconfirmed UI states.',
              style: TextStyle(fontSize: 11.5, color: kTextDim),
            ),
            value: s.injectFailures,
            onChanged: (bool v) {
              s.injectFailures = v;
              c.touch();
            },
          ),
          if (s.injectFailures)
            _SettingSlider(
              label: 'Failure rate',
              value: s.failureRate,
              min: 0.05,
              max: 1,
              divisions: 19,
              display: '${(s.failureRate * 100).round()}%',
              onChanged: (double v) {
                s.failureRate = v;
                c.touch();
              },
            ),
        ],
      ),
    );
  }
}

class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5, color: kTextDim))),
            Text(display, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SelfTestCard extends StatefulWidget {
  const _SelfTestCard();

  @override
  State<_SelfTestCard> createState() => _SelfTestCardState();
}

class _SelfTestCardState extends State<_SelfTestCard> {
  List<TestResult>? _results;
  bool _running = false;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _results = null;
    });
    final List<TestResult> r = await runSelfTests();
    if (!mounted) return;
    setState(() {
      _running = false;
      _results = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    final int passed = _results?.where((TestResult t) => t.passed).length ?? 0;
    return SectionCard(
      title: 'Self-tests',
      subtitle: 'Automation boundaries, adapter honesty, pairing and permission checks.',
      trailing: _results == null
          ? null
          : BadgeChip(
              label: '$passed/${_results!.length} passed',
              color: passed == _results!.length ? kOk : kDanger,
              dense: true,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _running ? null : _run,
              icon: _running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kBrandBlue),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(_running ? 'Running…' : 'Run tests'),
            ),
          ),
          if (_results != null) ...<Widget>[
            const SizedBox(height: 12),
            for (final TestResult t in _results!)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      t.passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 16,
                      color: t.passed ? kOk : kDanger,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(t.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          if (t.detail.isNotEmpty)
                            Text(t.detail,
                                style: const TextStyle(fontSize: 11, color: kTextDim, height: 1.35)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _DocsCard extends StatelessWidget {
  const _DocsCard();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Documentation',
      subtitle: 'Contracts and safety notes that back this prototype.',
      child: Column(
        children: <Widget>[
          _DocTile(
            title: 'Device service contract',
            body: 'fanService: getDevice, getStatus, getReadings, setPower(deviceId, desired), '
                'setSpeed, setMode, updateAutomation, subscribeToDevice, createPairingCode, '
                'pairWithCode. Every call returns a typed result with pending / confirmed / '
                'rejected / timeout / offline / unsupported. setPower(true) requests a desired '
                'state — it is never a blind toggle. The UI never calls an adapter or a database '
                'directly.',
          ),
          _DocTile(
            title: 'ESP32 API contract',
            body: 'GET /api/v1/health — firmware version, device id, uptime, connectivity.\n'
                'GET /api/v1/status — reported power, speed (if supported), mode, revision, timestamp.\n'
                'GET /api/v1/readings — temperature, humidity, sensor health, observedAt.\n'
                'POST /api/v1/commands — {commandId, desiredPower, desiredSpeed, desiredMode, expiresAt, hmac}.\n'
                'GET/PUT /api/v1/automation — thresholds validated and applied by the device.\n'
                'Auth: per-device HMAC secret held server-side, never in app code. 202 Accepted '
                'means "routed", not "applied"; confirmed only on matching acknowledgement or '
                'fresh telemetry with the same commandId.',
          ),
          _DocTile(
            title: 'Hardware integration + safety',
            body: 'Prefer an authenticated outbound connection from the ESP32 to the backend, or a '
                'trusted local gateway; never expose an unauthenticated control endpoint to the '
                'internet. Automation runs on the ESP32 so ventilation continues without the app '
                'or internet. Prototype with a low-voltage DC fan and a suitable motor driver — '
                'never power a motor from a GPIO pin, and leave any mains wiring to a qualified '
                'person. Firmware must define a safe state for boot, sensor fault, watchdog reset '
                'and lost connection.',
          ),
          _DocTile(
            title: 'Security model',
            body: 'Pairing codes are generated with a CSPRNG, stored only as salted SHA-256 hashes, '
                'short-lived, single-use (atomically consumed) and attempt-limited. Pairing grants '
                'a membership role (owner / controller / viewer), not a permanent credential; owners '
                'can revoke at any time. Row Level Security must restrict reads and writes to '
                'memberships, and users must never be able to grant themselves access or read '
                'another user\'s codes. No service-role keys or device secrets in client code.',
          ),
          _DocTile(
            title: 'Source-of-truth rules',
            body: 'deviceType separates virtual from physical; readings.source separates simulated '
                'from physical. A physical device is never "online" just because the app is. '
                'Stale data is labelled "Last reported" with a timestamp, animation follows '
                'reported state only, pending commands look different from confirmed ones, and '
                'virtual values are never written into a physical device record. Converting a '
                'virtual device to physical requires a deliberate provisioning flow.',
          ),
        ],
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 10),
        title: Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Text(body, style: const TextStyle(fontSize: 12, color: kTextDim, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
