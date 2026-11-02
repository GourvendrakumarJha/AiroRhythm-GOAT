/*
  AiroRhythm Connect — ESP32 Wi-Fi setup firmware
  ===============================================

  What this does
  --------------
  1. First boot (or after a reset) it becomes its own Wi-Fi network:
       SSID:     AiroRhythm-Setup
       Password: (none — see AP_PASSWORD below)
       Address:  http://192.168.4.1
     A captive-portal page opens by itself on your phone; the AiroRhythm
     Connect app can also talk to the same endpoints.

  2. It scans the room, takes the SSID + password you type, joins your
     home Wi-Fi, then serves the fan API on that network (http + mDNS).

  3. It remembers the network in flash, so a power cut does not mean
     setting it up again.

  Board: "ESP32 Dev Module" in Arduino IDE.
  Libraries: none beyond the ESP32 core (Wi-Fi, WebServer, DNS, mDNS,
  Preferences). Optional DHT sensor needs "DHT sensor library" by Adafruit.

  Wiring is optional — with HAS_* left at 0 the board still does Wi-Fi
  setup and serves /state with null sensors, so you can test with a bare
  board on USB.

  Default pins (match docs/HARDWARE-INTEGRATION.md):
    DHT22 data      GPIO 4
    MQ smoke A-out  GPIO 34
    ACS712 A-out    GPIO 35
    Fan PWM (L298N) GPIO 25
    Status LED      GPIO 2  (on-board LED on most DevKits)
*/

#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>
#include <Preferences.h>
#include <ESPmDNS.h>

/* ------------------------------ settings ------------------------------ */

#define FW_VERSION      "1.0.0"
#define DEVICE_NAME     "AiroRhythm Fan"
#define AP_SSID         "AiroRhythm-Setup"
#define AP_PASSWORD     ""            // 8+ characters to lock the setup network
#define MDNS_HOSTNAME   "airorhythm"  // http://airorhythm.local on your LAN
#define CONNECT_TIMEOUT 20000         // ms spent trying to join your Wi-Fi
#define RESET_PIN       0             // BOOT button: hold at power-up to wipe Wi-Fi

/* Optional hardware. Leave 0 for a bare board. */
#define HAS_FAN         0
#define FAN_PWM_PIN     25
#define HAS_DHT         0
#define DHT_PIN         4
#define HAS_SMOKE       0
#define SMOKE_PIN       34
#define HAS_CURRENT     0
#define CURRENT_PIN     35
#define LED_PIN         2

#if HAS_DHT
  #include <DHT.h>
  DHT dht(DHT_PIN, DHT22);
#endif

/* ------------------------------- state ------------------------------- */

enum Mode { MODE_AP, MODE_STA };
Mode mode = MODE_AP;

WebServer server(80);
DNSServer dnsServer;
Preferences prefs;

String savedSsid = "";
String savedPass = "";
String lastReason = "";        // not-found | bad-password | timeout
String lastResultSsid = "";
bool apTeardownPending = false;
unsigned long apTeardownAt = 0;
unsigned long bootMillis = 0;

bool fanOn = false;
int fanSpeed = 0;              // 0..4
int fanPwm = 0;               // 0..255
unsigned long timerEndsAt = 0; // 0 = no timer

float lastTemp = NAN;
float lastRh = NAN;
int lastSmoke = -1;
float lastAmps = -1;
unsigned long lastSensorRead = 0;

/* --------------------------- small helpers --------------------------- */

void ledSet(bool on) {
#ifdef LED_PIN
  digitalWrite(LED_PIN, on ? HIGH : LOW);
#endif
}

/* Slow blink = setup mode, fast blink = joining, solid = online. */
void ledService() {
#ifdef LED_PIN
  unsigned long t = millis();
  if (mode == MODE_AP) {
    ledSet((t / 700) % 2 == 0);
  } else {
    bool joining = (WiFi.status() != WL_CONNECTED);
    ledSet(joining ? ((t / 120) % 2 == 0) : true);
  }
#endif
}

void addCors() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
  server.sendHeader("Access-Control-Allow-Private-Network", "true");
  server.sendHeader("Access-Control-Max-Age", "86400");
}

void sendJson(int code, const String &body) {
  addCors();
  server.sendHeader("Cache-Control", "no-store");
  server.send(code, "application/json; charset=utf-8", body);
}

String jsonEscape(const String &in) {
  String out;
  out.reserve(in.length() + 8);
  for (size_t i = 0; i < in.length(); i++) {
    char c = in[i];
    switch (c) {
      case '"':  out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n";  break;
      case '\r': out += "\\r";  break;
      case '\t': out += "\\t";  break;
      default:
        if ((uint8_t)c < 0x20) {
          char buf[7];
          snprintf(buf, sizeof(buf), "\\u%04x", (uint8_t)c);
          out += buf;
        } else {
          out += c;
        }
    }
  }
  return out;
}

/* Minimal JSON string reader: finds "key":"value" and unescapes it.
   Good enough for {"ssid":"...","password":"..."} and avoids pulling in
   a JSON library. Also accepts application/x-www-form-urlencoded. */
String jsonField(const String &src, const char *key) {
  String needle = String("\"") + key + "\"";
  int k = src.indexOf(needle);
  if (k < 0) return String();
  int colon = src.indexOf(':', k + needle.length());
  if (colon < 0) return String();
  int q1 = src.indexOf('"', colon + 1);
  if (q1 < 0) return String();
  String out;
  for (int i = q1 + 1; i < (int)src.length(); i++) {
    char c = src[i];
    if (c == '\\' && i + 1 < (int)src.length()) {
      char n = src[++i];
      switch (n) {
        case 'n': out += '\n'; break;
        case 'r': out += '\r'; break;
        case 't': out += '\t'; break;
        case 'u': {
          // keep basic latin only; Wi-Fi names with emoji are rare
          if (i + 4 < (int)src.length()) {
            char hex[5] = {src[i + 1], src[i + 2], src[i + 3], src[i + 4], 0};
            long cp = strtol(hex, nullptr, 16);
            if (cp > 31 && cp < 127) out += (char)cp;
            i += 4;
          }
          break;
        }
        default: out += n;
      }
    } else if (c == '"') {
      break;
    } else {
      out += c;
    }
  }
  return out;
}

String formField(const String &body, const char *key) {
  String needle = String(key) + "=";
  int k = body.indexOf(needle);
  if (k < 0) return String();
  int start = k + needle.length();
  int end = body.indexOf('&', start);
  if (end < 0) end = body.length();
  String raw = body.substring(start, end);
  String out;
  for (int i = 0; i < (int)raw.length(); i++) {
    char c = raw[i];
    if (c == '+') {
      out += ' ';
    } else if (c == '%' && i + 2 < (int)raw.length()) {
      char hex[3] = {raw[i + 1], raw[i + 2], 0};
      out += (char)strtol(hex, nullptr, 16);
      i += 2;
    } else {
      out += c;
    }
  }
  return out;
}

String deviceField(const String &body, const char *key, bool isJson) {
  if (isJson) return jsonField(body, key);
  return formField(body, key);
}

/* ------------------------- credentials in flash ---------------------- */

void loadCreds() {
  prefs.begin("airorhythm", true);
  savedSsid = prefs.getString("ssid", "");
  savedPass = prefs.getString("pass", "");
  prefs.end();
}

void saveCreds(const String &ssid, const String &pass) {
  prefs.begin("airorhythm", false);
  prefs.putString("ssid", ssid);
  prefs.putString("pass", pass);
  prefs.end();
  savedSsid = ssid;
  savedPass = pass;
}

void clearCreds() {
  prefs.begin("airorhythm", false);
  prefs.clear();
  prefs.end();
  savedSsid = "";
  savedPass = "";
}

/* ----------------------------- setup mode ---------------------------- */

void startSetupMode() {
  mode = MODE_AP;
  WiFi.persistent(false);
  WiFi.disconnect(true, false);
  WiFi.mode(WIFI_AP);
  bool ok = AP_PASSWORD[0] ? WiFi.softAP(AP_SSID, AP_PASSWORD) : WiFi.softAP(AP_SSID);
  dnsServer.start(53, "*", WiFi.softAPIP());
  MDNS.end();
  Serial.printf("[setup] network '%s' at http://%s\n", AP_SSID, WiFi.softAPIP().toString().c_str());
  if (!ok) Serial.println("[setup] AP failed to start");
}

void startStationMode() {
  mode = MODE_STA;
  dnsServer.stop();
  WiFi.setHostname(MDNS_HOSTNAME);
  if (MDNS.begin(MDNS_HOSTNAME)) {
    MDNS.addService("http", "tcp", 80);
    Serial.printf("[mdns] http://%s.local/\n", MDNS_HOSTNAME);
  }
  Serial.printf("[wifi] %s  http://%s/\n", WiFi.localIP().toString().c_str(),
                WiFi.localIP().toString().c_str());
}

/* Join a network. Blocks, and keeps the setup AP alive meanwhile so the
   browser request that asked for this can still be answered. */
bool tryConnect(const String &ssid, const String &pass, uint8_t &statusOut) {
  WiFi.persistent(false);
  WiFi.mode(WIFI_AP_STA);
  WiFi.disconnect(false, false);
  delay(200);
  WiFi.begin(ssid.c_str(), pass.c_str());

  unsigned long start = millis();
  while (millis() - start < CONNECT_TIMEOUT) {
    if (WiFi.status() == WL_CONNECTED) {
      statusOut = WL_CONNECTED;
      return true;
    }
    // Wrong password / unreachable SSID usually reports within a few seconds.
    if (millis() - start > 3500) {
      uint8_t st = WiFi.status();
      if (st == WL_CONNECT_FAILED || st == WL_NO_SSID_AVAIL) break;
    }
    delay(150);
    ledService();
  }
  statusOut = WiFi.status();
  WiFi.disconnect(true, false);
  WiFi.mode(WIFI_AP);
  return false;
}

bool ssidInScan(const String &ssid) {
  int n = WiFi.scanNetworks(false, true);
  bool found = false;
  for (int i = 0; i < n; i++) {
    if (WiFi.SSID(i) == ssid) {
      found = true;
      break;
    }
  }
  WiFi.scanDelete();
  return found;
}

/* --------------------------- HTTP: common ---------------------------- */

void handleStatus() {
  String state = "ap";
  String ip = "";
  if (mode == MODE_STA && WiFi.status() == WL_CONNECTED) {
    state = "connected";
    ip = WiFi.localIP().toString();
  } else if (lastReason.length()) {
    state = "failed";
  }
  String body = "{";
  body += "\"device\":\"" + String(DEVICE_NAME) + "\",";
  body += "\"fw\":\"" + String(FW_VERSION) + "\",";
  body += "\"model\":\"ESP32\",";
  body += "\"kind\":\"" + String(mode == MODE_AP ? "ap" : "lan") + "\",";
  body += "\"state\":\"" + state + "\",";
  body += "\"ip\":\"" + (ip.length() ? ip : (mode == MODE_AP ? WiFi.softAPIP().toString() : String(""))) + "\",";
  body += "\"ap\":\"" + String(AP_SSID) + "\",";
  body += "\"ssid\":\"" + jsonEscape(lastResultSsid.length() ? lastResultSsid : savedSsid) + "\",";
  body += "\"reason\":";
  body += lastReason.length() ? ("\"" + lastReason + "\"") : String("null");
  body += ",\"rssi\":" + String(mode == MODE_STA && WiFi.status() == WL_CONNECTED ? WiFi.RSSI() : 0);
  body += "}";
  sendJson(200, body);
}

void handleScan() {
  WiFi.mode(mode == MODE_AP ? WIFI_AP_STA : WIFI_STA);
  int n = WiFi.scanNetworks(false, true);
  String body = "{\"networks\":[";
  bool first = true;
  for (int i = 0; i < n && i < 24; i++) {
    String ssid = WiFi.SSID(i);
    if (!ssid.length()) continue;
    bool dup = false;
    for (int j = 0; j < i; j++) {
      if (WiFi.SSID(j) == ssid) { dup = true; break; }
    }
    if (dup) continue;
    if (!first) body += ",";
    first = false;
    body += "{\"ssid\":\"" + jsonEscape(ssid) + "\",";
    body += "\"rssi\":" + String(WiFi.RSSI(i)) + ",";
    body += "\"enc\":" + String(WiFi.encryptionType(i) == WIFI_AUTH_OPEN ? "false" : "true") + ",";
    body += "\"ch\":" + String(WiFi.channel(i)) + "}";
  }
  body += "]}";
  WiFi.scanDelete();
  sendJson(200, body);
}

/* ------------------- HTTP: join / switch / forget -------------------- */

void handleWifi() {
  if (server.method() != HTTP_POST) {
    sendJson(405, "{\"ok\":false,\"reason\":\"method\"}");
    return;
  }
  String body = server.arg("plain");
  bool isJson = body.length() && body[0] == '{';
  String ssid = deviceField(body, "ssid", isJson);
  String pass = deviceField(body, "password", isJson);
  ssid.trim();

  Serial.printf("[wifi] request to join '%s'\n", ssid.c_str());

  if (!ssid.length()) {
    sendJson(400, "{\"ok\":false,\"reason\":\"not-found\"}");
    return;
  }

  lastReason = "";
  lastResultSsid = ssid;

  bool wasSta = (mode == MODE_STA);
  uint8_t status = 0;
  bool connected = tryConnect(ssid, pass, status);
  lastResultSsid = ssid;

  if (!connected) {
    if (!ssidInScan(ssid)) lastReason = "not-found";
    else lastReason = "bad-password";

    // If we were already online, put the old network back so a wrong
    // password does not strand the fan.
    bool restored = false;
    if (wasSta) {
      if (savedSsid.length() && savedSsid != ssid) {
        uint8_t st2 = 0;
        restored = tryConnect(savedSsid, savedPass, st2);
      }
      if (restored) {
        startStationMode();
      } else {
        startSetupMode();
      }
    }

    String out = "{\"ok\":false,\"reason\":\"" + lastReason + "\",\"ssid\":\"" +
                 jsonEscape(ssid) + "\",\"restored\":" + (restored ? "true" : "false") +
                 ",\"wifiStatus\":" + String(status) + "}";
    sendJson(200, out);
    Serial.printf("[wifi] failed (%s, status %d, restored %d)\n",
                  lastReason.c_str(), status, restored);
    return;
  }

  saveCreds(ssid, pass);
  String ip = WiFi.localIP().toString();
  String out = "{\"ok\":true,\"ip\":\"" + ip + "\",\"ssid\":\"" + jsonEscape(ssid) +
               "\",\"rssi\":" + String(WiFi.RSSI()) + ",\"device\":\"" + String(DEVICE_NAME) + "\"}";
  sendJson(200, out);
  Serial.printf("[wifi] joined '%s' as %s\n", ssid.c_str(), ip.c_str());

  startStationMode();

  // Give the phone a moment to receive the answer before the setup
  // network disappears (it was connected to it).
  apTeardownPending = true;
  apTeardownAt = millis() + 2500;
}

void handleForget() {
  clearCreds();
  lastReason = "";
  lastResultSsid = "";
  sendJson(200, "{\"ok\":true,\"ap\":\"" + String(AP_SSID) + "\"}");
  delay(400);
  ESP.restart();
}

void handleReset() {
  clearCreds();
  sendJson(200, "{\"ok\":true}");
  delay(300);
  ESP.restart();
}

/* ----------------------------- fan control --------------------------- */

void applyFanOutput() {
#if HAS_FAN
  #if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
    ledcWrite(FAN_PWM_PIN, fanPwm);
  #else
    ledcWrite(0, fanPwm);
  #endif
#endif
}

int speedToPwm(int speed) {
  switch (speed) {
    case 1: return 64;    // ~25 %
    case 2: return 115;   // ~45 %
    case 3: return 179;   // ~70 %
    case 4: return 255;   // 100 %
    default: return 0;
  }
}

int estimateRpm() {
  if (!fanOn || fanSpeed == 0) return 0;
  return 260 + fanSpeed * 340;
}

void readSensors() {
  if (millis() - lastSensorRead < 2000) return;
  lastSensorRead = millis();

#if HAS_DHT
  float t = dht.readTemperature();
  float h = dht.readHumidity();
  if (!isnan(t)) lastTemp = t;
  if (!isnan(h)) lastRh = h;
#endif
#if HAS_SMOKE
  // MQ sensors need a warm-up; report a smoothed raw value.
  static float smooth = 0;
  int raw = analogRead(SMOKE_PIN);
  smooth = smooth * 0.8 + raw * 0.2;
  lastSmoke = (int)smooth;
#endif
#if HAS_CURRENT
  static float smoothA = 0;
  int raw = analogRead(CURRENT_PIN);
  float volts = (raw / 4095.0) * 3.3;
  float amps = (volts - 1.65) / 0.066;   // ACS712-30A sensitivity
  smoothA = smoothA * 0.8 + amps * 0.2;
  lastAmps = smoothA < 0 ? 0 : smoothA;
#endif
}

String telemetryJson() {
  if (timerEndsAt && millis() > timerEndsAt) {
    fanOn = false;
    fanSpeed = 0;
    fanPwm = 0;
    timerEndsAt = 0;
    applyFanOutput();
  }

  String body = "{";
  body += "\"t\":\"tel\",";
  body += "\"ts\":" + String(millis() + 1) + ",";
  body += "\"on\":" + String(fanOn ? "true" : "false") + ",";
  body += "\"speed\":" + String(fanSpeed) + ",";
  body += "\"rpm\":" + String(estimateRpm()) + ",";
  body += "\"rpmEst\":true,";
  body += "\"targetRpm\":" + String(estimateRpm()) + ",";
  body += "\"mode\":\"" + String(timerEndsAt ? "timer" : "manual") + "\",";
  body += "\"timerLeft\":" + String(timerEndsAt ? (long)((timerEndsAt - millis()) / 1000) : 0) + ",";

  body += "\"temp\":";
  body += isnan(lastTemp) ? String("null") : String(lastTemp, 1);
  body += ",\"rh\":";
  body += isnan(lastRh) ? String("null") : String((int)lastRh);
  body += ",\"smoke\":";
  body += lastSmoke < 0 ? String("null") : String(lastSmoke);
  body += ",\"amps\":";
  body += lastAmps < 0 ? String("null") : String(lastAmps, 3);
  body += ",\"watts\":";
  body += lastAmps < 0 ? String("null") : String(lastAmps * 230.0, 1);

  body += ",\"ssid\":\"" + jsonEscape(savedSsid) + "\",";
  body += "\"rssi\":" + String(WiFi.RSSI()) + ",";
  body += "\"ip\":\"" + WiFi.localIP().toString() + "\",";
  body += "\"uptime\":" + String((millis() - bootMillis) / 1000) + ",";
  body += "\"fw\":\"" + String(FW_VERSION) + "\"}";
  return body;
}

void handleState() {
  if (mode != MODE_STA || WiFi.status() != WL_CONNECTED) {
    sendJson(503, "{\"error\":\"offline\"}");
    return;
  }
  sendJson(200, telemetryJson());
}

void handleCmd() {
  if (server.method() != HTTP_POST) {
    sendJson(405, "{\"ok\":false,\"reason\":\"method\"}");
    return;
  }
  String body = server.arg("plain");
  String action = body.indexOf("\"a\"") >= 0 ? jsonField(body, "a") : formField(body, "a");

  if (action == "reset") {
    clearCreds();
    sendJson(200, "{\"ok\":true,\"rebooted\":true}");
    delay(300);
    ESP.restart();
    return;
  }
  if (action != "fan") {
    sendJson(400, "{\"ok\":false,\"reason\":\"unknown-command\"}");
    return;
  }

  bool hasOn = body.indexOf("\"on\"") >= 0;
  bool hasSpeed = body.indexOf("\"speed\"") >= 0;
  bool hasTimer = body.indexOf("\"timer\"") >= 0;

  if (hasSpeed) {
    int speed = jsonField(body, "speed").toInt();
    if (speed < 0) speed = 0;
    if (speed > 4) speed = 4;
    fanSpeed = speed;
    fanOn = speed > 0;
  }
  if (hasOn) {
    String onStr = jsonField(body, "on");
    bool on = (onStr == "true" || onStr == "1");
    fanOn = on;
    if (!on) fanSpeed = 0;
    if (on && fanSpeed == 0) fanSpeed = 2;
  }
  if (hasTimer) {
    long seconds = jsonField(body, "timer").toInt();
    timerEndsAt = seconds > 0 ? millis() + seconds * 1000UL : 0;
  }

  fanPwm = speedToPwm(fanSpeed);
  applyFanOutput();

  String out = "{\"ok\":true,\"on\":" + String(fanOn ? "true" : "false") +
               ",\"speed\":" + String(fanSpeed) + ",\"targetRpm\":" + String(estimateRpm()) + "}";
  sendJson(200, out);
}

/* ---------------------------- setup page ----------------------------- */

const char SETUP_PAGE[] PROGMEM = R"HTML(<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#F7F4ED">
<title>AiroRhythm — Wi-Fi setup</title>
<style>
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#F7F4ED;
color:#141C28;min-height:100dvh;padding:20px 16px 40px;font-size:16px;
background-image:radial-gradient(600px 380px at 6% -8%,rgba(47,128,237,.14),transparent 62%),
radial-gradient(520px 360px at 104% 104%,rgba(124,77,255,.14),transparent 60%)}
.wrap{max-width:430px;margin:0 auto}
.brand{display:flex;align-items:center;gap:9px;margin-bottom:22px}
.brand .m{width:30px;height:30px;border-radius:9px;background:linear-gradient(135deg,#2F80ED,#7C4DFF);
display:grid;place-items:center;color:#fff;font-weight:800;font-size:15px}
.brand b{font-size:15px;letter-spacing:-.02em}
.brand span{font-size:10px;font-weight:800;letter-spacing:.09em;text-transform:uppercase;
color:#2F80ED;background:#E9F1FE;padding:3px 6px;border-radius:6px}
h1{font-size:29px;line-height:1.08;letter-spacing:-.035em;margin-bottom:9px}
h1 em{font-style:normal;background:linear-gradient(135deg,#2F80ED,#7C4DFF);
-webkit-background-clip:text;background-clip:text;color:transparent}
p.sub{font-size:14px;color:#586675;line-height:1.5;margin-bottom:20px}
.card{background:#fff;border:1px solid #E7E2D6;border-radius:20px;padding:16px;
box-shadow:0 10px 30px rgba(20,28,40,.07);margin-bottom:14px}
label{display:block;font-size:12px;font-weight:750;color:#586675;margin-bottom:6px}
select,input{width:100%;height:50px;border-radius:14px;border:1.5px solid #E7E2D6;background:#fff;
padding:0 13px;font-size:15px;font-family:inherit;color:#141C28;outline:none}
select:focus,input:focus{border-color:#2F80ED;box-shadow:0 0 0 4px rgba(47,128,237,.11)}
.field{margin-bottom:13px}
.pw{position:relative}
.pw button{position:absolute;right:6px;top:6px;height:38px;width:38px;border:0;background:none;
color:#8D9AA8;font-size:12px;font-weight:700;cursor:pointer}
button.go{width:100%;height:54px;border:0;border-radius:16px;background:linear-gradient(135deg,#2F80ED,#7C4DFF);
color:#fff;font-size:16px;font-weight:750;font-family:inherit;cursor:pointer;
box-shadow:0 12px 26px rgba(64,101,240,.3)}
button.go:disabled{opacity:.5;box-shadow:none}
.note{font-size:12.5px;color:#8D9AA8;line-height:1.5;margin-top:10px;text-align:center}
.msg{border-radius:14px;padding:12px 13px;font-size:13px;line-height:1.5;margin-top:12px;display:none}
.msg.show{display:block}
.msg.err{background:#FCECEC;color:#8F3030}
.msg.ok{background:#E3F6EE;color:#0C6B48}
.spin{display:inline-block;width:14px;height:14px;border:2px solid rgba(255,255,255,.4);
border-right-color:#fff;border-radius:50%;animation:s .7s linear infinite;vertical-align:-2px;margin-right:6px}
@keyframes s{to{transform:rotate(360deg)}}
.done{text-align:center;padding:8px 4px}
.tick{width:58px;height:58px;border-radius:50%;background:#12A66E;color:#fff;display:grid;
place-items:center;margin:0 auto 14px;font-size:28px;box-shadow:0 0 0 8px rgba(18,166,110,.1)}
.ip{display:inline-block;font-family:ui-monospace,Menlo,monospace;font-size:16px;background:#F4F8FF;
border:1px dashed #CFE0FA;border-radius:12px;padding:9px 14px;margin:12px 0}
.steps{list-style:none;margin:16px 0 0}
.steps li{display:flex;gap:10px;font-size:13px;color:#586675;line-height:1.5;margin-bottom:9px}
.steps b{color:#141C28}
.steps i{flex:0 0 auto;width:20px;height:20px;border-radius:50%;background:#E9F1FE;color:#2F80ED;
font-style:normal;font-size:11px;font-weight:800;display:grid;place-items:center;margin-top:1px}
</style></head><body><div class="wrap">
<div class="brand"><span class="m">A</span><b>AiroRhythm</b><span>Setup</span></div>

<div id="form">
  <h1>Put your fan<br><em>on Wi-Fi</em></h1>
  <p class="sub">Pick your home network and type its password. The fan remembers it, so this is a one-time job.</p>
  <div class="card">
    <div class="field">
      <label for="ssid">Home Wi-Fi (2.4 GHz)</label>
      <select id="ssid"><option value="">Scanning…</option></select>
    </div>
    <div class="field">
      <label for="pass">Wi-Fi password</label>
      <div class="pw">
        <input id="pass" type="password" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="Your Wi-Fi password">
        <button type="button" id="eye">Show</button>
      </div>
    </div>
    <button class="go" id="go" disabled>Connect my fan</button>
    <div class="msg err" id="err"></div>
    <p class="note">The fan can only join 2.4 GHz networks. Your password goes straight to the fan and stays on it.</p>
  </div>
</div>

<div id="waiting" style="display:none">
  <h1>Connecting…</h1>
  <p class="sub">The fan is joining your Wi-Fi. This takes 10–20 seconds — keep this page open.</p>
  <div class="card" style="text-align:center;padding:26px">
    <div class="tick" style="background:#E9F1FE;color:#2F80ED;box-shadow:0 0 0 8px rgba(47,128,237,.08)">⋯</div>
    <div style="font-size:14px;color:#586675" id="waitMsg">Talking to the fan…</div>
  </div>
</div>

<div id="done" style="display:none">
  <div class="card done">
    <div class="tick">✓</div>
    <h2 style="font-size:21px;letter-spacing:-.02em;margin-bottom:6px">Your fan is online</h2>
    <p style="font-size:13.5px;color:#586675;line-height:1.5">It joined <b id="doneSsid">your Wi-Fi</b>.</p>
    <div class="ip" id="doneIp">—</div>
    <ol class="steps" style="text-align:left">
      <li><i>1</i><span>Your phone is still on the fan’s setup network — open <b>Wi-Fi settings</b> and reconnect it to <b id="doneSsid2">your Wi-Fi</b>.</span></li>
      <li><i>2</i><span>Open the AiroRhythm Connect app and use <b id="doneIp2">that address</b> to control the fan.</span></li>
    </ol>
  </div>
</div>

<script>
var $=function(s){return document.querySelector(s)};
var sel=$('#ssid'),pass=$('#pass'),go=$('#go'),err=$('#err');
var open=false;
function msg(t,bad){err.textContent=t;err.className='msg show '+(bad?'err':'ok');}
function scan(){
  fetch('/scan').then(function(r){return r.json()}).then(function(d){
    var nets=(d.networks||[]).filter(function(n){return n.ssid});
    if(!nets.length){sel.innerHTML='<option value="">No networks found — move closer to the router</option>';return}
    sel.innerHTML='<option value="">Choose your network…</option>'+nets.map(function(n){
      return '<option value="'+n.ssid.replace(/"/g,'&quot;')+'">'+n.ssid+' ('+n.rssi+' dBm)'+(n.enc?' · secured':' · open')+'</option>';
    }).join('');
  }).catch(function(){sel.innerHTML='<option value="">Could not scan — reload the page</option>'});
}
function upd(){
  var s=sel.value, p=pass.value;
  var net=(s&&/5g/i.test(s));
  if(net){msg('That name looks like a 5 GHz network. The fan can only join 2.4 GHz.',true)}else{err.className='msg'}
  go.disabled=!s||p.length<8;
}
sel.addEventListener('change',upd);
pass.addEventListener('input',upd);
$('#eye').addEventListener('click',function(){
  open=!open;pass.type=open?'text':'password';this.textContent=open?'Hide':'Show';
});
go.addEventListener('click',function(){
  go.disabled=true;go.innerHTML='<span class="spin"></span>Connecting…';
  $('#form').style.display='none';$('#waiting').style.display='block';
  var t=Date.now();
  var timer=setInterval(function(){
    $('#waitMsg').textContent='Trying '+sel.value+'… '+Math.round((Date.now()-t)/1000)+' s';
  },500);
  fetch('/wifi',{method:'POST',headers:{'content-type':'application/json'},
    body:JSON.stringify({ssid:sel.value,password:pass.value})})
  .then(function(r){return r.json()}).then(function(d){
    clearInterval(timer);
    if(d.ok){
      $('#waiting').style.display='none';$('#done').style.display='block';
      $('#doneIp').textContent=d.ip;$('#doneIp2').textContent=d.ip;
      $('#doneSsid').textContent=d.ssid;$('#doneSsid2').textContent=d.ssid;
    } else {
      $('#waiting').style.display='none';$('#form').style.display='block';
      go.disabled=false;go.textContent='Connect my fan';
      var reasons={
        'bad-password':'That password did not work. Wi-Fi passwords are case-sensitive — check it, and make sure this is the 2.4 GHz network.',
        'not-found':'The fan cannot see that network. Move it closer to the router, then try again.',
        '5ghz':'That network is 5 GHz. The fan needs the 2.4 GHz one.'
      };
      msg(reasons[d.reason]||'The fan could not join. Try again.',true);
      scan();
    }
  }).catch(function(){
    clearInterval(timer);
    $('#waiting').style.display='none';$('#form').style.display='block';
    go.disabled=false;go.textContent='Connect my fan';
    msg('Lost contact with the fan. Reconnect to AiroRhythm-Setup and try again.',true);
  });
});
scan();
</script></div></body></html>)HTML";

/* ---------------------------- control page --------------------------- */

const char CONTROL_PAGE[] PROGMEM = R"HTML(<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#141C28">
<title>AiroRhythm — your fan</title>
<style>
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#F7F4ED;
color:#141C28;min-height:100dvh;padding:20px 16px 40px;
background-image:radial-gradient(600px 380px at 6% -8%,rgba(47,128,237,.13),transparent 62%),
radial-gradient(520px 360px at 104% 104%,rgba(124,77,255,.13),transparent 60%)}
.wrap{max-width:430px;margin:0 auto}
.brand{display:flex;align-items:center;gap:9px;margin-bottom:18px}
.brand .m{width:28px;height:28px;border-radius:8px;background:linear-gradient(135deg,#2F80ED,#7C4DFF);
display:grid;place-items:center;color:#fff;font-weight:800;font-size:14px}
.brand b{font-size:14px;letter-spacing:-.02em}
.brand span{font-size:9.5px;font-weight:800;letter-spacing:.09em;text-transform:uppercase;color:#12A66E;
background:#E3F6EE;padding:3px 6px;border-radius:6px}
.hero{background:linear-gradient(160deg,#151D2A,#243349 60%,#2B2350);border-radius:24px;padding:20px 16px 18px;
color:#fff;text-align:center;box-shadow:0 18px 40px rgba(20,28,40,.25);margin-bottom:12px}
.state{font-size:11px;font-weight:800;letter-spacing:.12em;text-transform:uppercase;color:rgba(255,255,255,.55)}
.rpm{font-size:44px;font-weight:850;letter-spacing:-.04em;line-height:1.05;margin:3px 0 2px;font-variant-numeric:tabular-nums}
.rpm small{font-size:13px;font-weight:700;opacity:.55;letter-spacing:0;margin-left:4px}
.speeds{display:grid;grid-template-columns:repeat(5,1fr);gap:6px;margin-top:15px}
.speeds button{border:1px solid rgba(255,255,255,.16);background:rgba(255,255,255,.07);color:rgba(255,255,255,.72);
border-radius:11px;padding:9px 2px;font-family:inherit;font-size:12px;font-weight:800;cursor:pointer}
.speeds button.sel{background:#fff;color:#152033;border-color:#fff}
.power{margin-top:12px;width:100%;border:0;border-radius:999px;padding:15px;font-family:inherit;font-size:15.5px;
font-weight:800;background:#fff;color:#152033;cursor:pointer;box-shadow:0 10px 22px rgba(0,0,0,.2)}
.power.on{background:rgba(255,255,255,.1);color:#fff;border:1px solid rgba(255,255,255,.24);box-shadow:none}
.tiles{display:grid;grid-template-columns:1fr 1fr;gap:9px;margin-bottom:12px}
.tile{background:#fff;border:1px solid #E7E2D6;border-radius:16px;padding:11px 13px}
.tile .l{font-size:10.5px;font-weight:800;letter-spacing:.05em;text-transform:uppercase;color:#8D9AA8}
.tile .v{font-size:20px;font-weight:850;letter-spacing:-.03em;margin-top:4px}
.tile .v small{font-size:11px;font-weight:750;color:#8D9AA8;margin-left:2px}
.card{background:#fff;border:1px solid #E7E2D6;border-radius:18px;padding:14px;box-shadow:0 8px 24px rgba(20,28,40,.06)}
.card .row{display:flex;justify-content:space-between;align-items:center;font-size:13px;padding:6px 0}
.card .row .k{color:#8D9AA8;font-weight:700;font-size:12px}
.card .row .v{font-weight:800}
code{font-family:ui-monospace,Menlo,monospace;font-size:12px;color:#586675}
.off{text-align:center;font-size:13px;color:#D95050;font-weight:700;padding:8px}
</style></head><body><div class="wrap">
<div class="brand"><span class="m">A</span><b>AiroRhythm</b><span>Online</span></div>

<div class="hero">
  <div class="state" id="state">Fan off</div>
  <div class="rpm" id="rpm">0<small>rpm</small></div>
  <div class="speeds" id="speeds">
    <button data-s="0">Off</button><button data-s="1">1</button><button data-s="2">2</button>
    <button data-s="3">3</button><button data-s="4">4</button>
  </div>
  <button class="power" id="power">Turn on</button>
</div>

<div class="tiles">
  <div class="tile"><div class="l">Power</div><div class="v" id="w">—</div></div>
  <div class="tile"><div class="l">Humidity</div><div class="v" id="rh">—</div></div>
  <div class="tile"><div class="l">Temperature</div><div class="v" id="t">—</div></div>
  <div class="tile"><div class="l">Signal</div><div class="v" id="rssi">—</div></div>
</div>

<div class="card">
  <div class="row"><span class="k">Network</span><span class="v" id="ssid">—</span></div>
  <div class="row"><span class="k">Address</span><span class="v"><code id="ip">—</code></span></div>
  <div class="row"><span class="k">Firmware</span><span class="v" id="fw">—</span></div>
</div>
<div class="off" id="offline" style="display:none">Lost contact with the fan — retrying…</div>

<script>
var $=function(s){return document.querySelector(s)},last=null;
function send(b){
  fetch('/cmd',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(b)})
  .then(function(){setTimeout(poll,300)}).catch(function(){offline(true)});
}
function offline(v){$('#offline').style.display=v?'block':'none'}
function paint(d){
  last=d;
  var on=!!d.on;
  $('#state').textContent=on?'Fan on':'Fan off';
  $('#rpm').innerHTML=Math.round(d.rpm)+'<small>rpm</small>';
  $('#power').textContent=on?'Turn off':'Turn on';
  $('#power').className='power'+(on?' on':'');
  [].forEach.call(document.querySelectorAll('#speeds button'),function(b){
    b.className=(Number(b.dataset.s)===Number(d.speed||0)&&on)?'sel':'';
  });
  $('#w').innerHTML=(d.watts==null?'—':d.watts)+'<small>W</small>';
  $('#rh').innerHTML=(d.rh==null?'—':d.rh)+'<small>%</small>';
  $('#t').innerHTML=(d.temp==null?'—':d.temp)+'<small>°C</small>';
  $('#rssi').innerHTML=d.rssi+'<small>dBm</small>';
  $('#ssid').textContent=d.ssid||'—';
  $('#ip').textContent=d.ip||'—';
  $('#fw').textContent='v'+d.fw;
  offline(false);
}
function poll(){
  fetch('/state',{cache:'no-store'}).then(function(r){if(!r.ok)throw 0;return r.json()})
  .then(paint).catch(function(){offline(true)});
}
$('#power').addEventListener('click',function(){
  var on=last&&last.on;
  send({a:'fan',on:!on,speed:!on?Math.max(1,(last&&last.speed)||2):0});
});
document.querySelectorAll('#speeds button').forEach(function(b){
  b.addEventListener('click',function(){
    var s=Number(b.dataset.s);send({a:'fan',on:s>0,speed:s});
  });
});
poll();setInterval(poll,2000);
</script></div></body></html>)HTML";

void handleRoot() {
  if (mode == MODE_STA) {
    addCors();
    server.sendHeader("Cache-Control", "no-store");
    server.send_P(200, "text/html; charset=utf-8", CONTROL_PAGE);
    return;
  }
  addCors();
  server.sendHeader("Cache-Control", "no-store");
  server.send_P(200, "text/html; charset=utf-8", SETUP_PAGE);
}

/* ------------------------------- routing ----------------------------- */

void handleOptions() {
  addCors();
  server.send(204);
}

void setupRoutes() {
  server.on("/", HTTP_GET, handleRoot);
  server.on("/status", HTTP_GET, handleStatus);
  server.on("/scan", HTTP_GET, handleScan);
  server.on("/wifi", HTTP_POST, handleWifi);
  server.on("/wifi", HTTP_OPTIONS, handleOptions);
  server.on("/forget", HTTP_POST, handleForget);
  server.on("/forget", HTTP_OPTIONS, handleOptions);
  server.on("/reset", HTTP_POST, handleReset);
  server.on("/reset", HTTP_OPTIONS, handleOptions);
  server.on("/api/state", HTTP_GET, handleState);
  server.on("/state", HTTP_GET, handleState);
  server.on("/cmd", HTTP_POST, handleCmd);
  server.on("/cmd", HTTP_OPTIONS, handleOptions);
  server.on("/api/cmd", HTTP_POST, handleCmd);

  // The web app speaks two prefixes: /ap/* while your phone sits on the fan's hotspot and
  // /lan/* once the fan is on your home network. Same handlers, so both spellings work and
  // the bare paths above keep the built-in pages (and curl) happy.
  server.on("/ap/status", HTTP_GET, handleStatus);
  server.on("/ap/scan", HTTP_GET, handleScan);
  server.on("/ap/wifi", HTTP_POST, handleWifi);
  server.on("/ap/wifi", HTTP_OPTIONS, handleOptions);
  server.on("/ap/reset", HTTP_POST, handleReset);
  server.on("/ap/reset", HTTP_OPTIONS, handleOptions);
  server.on("/lan/status", HTTP_GET, handleStatus);
  server.on("/lan/scan", HTTP_GET, handleScan);
  server.on("/lan/state", HTTP_GET, handleState);
  server.on("/lan/cmd", HTTP_POST, handleCmd);
  server.on("/lan/cmd", HTTP_OPTIONS, handleOptions);
  server.on("/lan/wifi", HTTP_POST, handleWifi);
  server.on("/lan/wifi", HTTP_OPTIONS, handleOptions);
  server.on("/lan/forget", HTTP_POST, handleForget);
  server.on("/lan/forget", HTTP_OPTIONS, handleOptions);

  // Any other GET while in setup mode: show the page (captive portal friendly).
  server.onNotFound([]() {
    if (server.method() == HTTP_OPTIONS) {
      handleOptions();
      return;
    }
    if (mode == MODE_AP && server.method() == HTTP_GET) {
      handleRoot();
      return;
    }
    sendJson(404, "{\"error\":\"not-found\"}");
  });
}

/* -------------------------------- setup ------------------------------ */

void setup() {
  Serial.begin(115200);
  bootMillis = millis();
  delay(300);

  Serial.println();
  Serial.println("=== AiroRhythm ESP32 " FW_VERSION " ===");

#ifdef LED_PIN
  pinMode(LED_PIN, OUTPUT);
#endif

#if HAS_FAN
  #if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
    ledcAttach(FAN_PWM_PIN, 25000, 8);
  #else
    ledcSetup(0, 25000, 8);
    ledcAttachPin(FAN_PWM_PIN, 0);
  #endif
  pinMode(FAN_PWM_PIN, OUTPUT);
#endif

#if HAS_DHT
  dht.begin();
#endif

  // Hold BOOT while powering up to wipe the saved network.
  pinMode(RESET_PIN, INPUT_PULLUP);
  bool factoryReset = digitalRead(RESET_PIN) == LOW;

  loadCreds();
  if (factoryReset) {
    clearCreds();
    Serial.println("[boot] BOOT held — saved Wi-Fi cleared");
  }

  Serial.printf("[boot] saved network: %s\n", savedSsid.length() ? savedSsid.c_str() : "(none)");

  if (savedSsid.length() && !factoryReset) {
    Serial.printf("[wifi] trying '%s'\n", savedSsid.c_str());
    // Station-only attempt first, so a failed join does not leave an AP behind.
    WiFi.persistent(false);
    WiFi.mode(WIFI_STA);
    WiFi.setHostname(MDNS_HOSTNAME);
    WiFi.begin(savedSsid.c_str(), savedPass.c_str());

    unsigned long start = millis();
    while (millis() - start < CONNECT_TIMEOUT && WiFi.status() != WL_CONNECTED) {
      delay(150);
      ledService();
    }

    if (WiFi.status() == WL_CONNECTED) {
      Serial.printf("[wifi] %s  http://%s/\n", WiFi.localIP().toString().c_str(),
                    WiFi.localIP().toString().c_str());
      startStationMode();
    } else {
      Serial.println("[wifi] could not rejoin — starting setup mode");
      lastReason = "timeout";
      lastResultSsid = savedSsid;
      startSetupMode();
    }
  } else {
    startSetupMode();
  }

  setupRoutes();
  server.begin();
  Serial.printf("[boot] ready · %s\n", mode == MODE_AP ? "waiting for setup" : "online");
}

/* -------------------------------- loop ------------------------------- */

void loop() {
  server.handleClient();
  if (mode == MODE_AP) dnsServer.processNextRequest();
  ledService();
  readSensors();

  if (apTeardownPending && millis() > apTeardownAt) {
    apTeardownPending = false;
    WiFi.softAPdisconnect(true);
    Serial.println("[setup] setup network closed");
  }

  if (mode == MODE_STA && WiFi.status() != WL_CONNECTED) {
    // Connection dropped: try to bring it back, fall back to setup mode.
    static unsigned long lastRetry = 0;
    if (millis() - lastRetry > 8000) {
      lastRetry = millis();
      Serial.println("[wifi] connection lost — retrying");
      WiFi.reconnect();
    }
  }

  delay(2);
}
