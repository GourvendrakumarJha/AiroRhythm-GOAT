#!/usr/bin/env node
/**
 * AiroRhythm Connect — ESP32 simulator
 * ------------------------------------
 * A software copy of the Wi-Fi setup firmware (`firmware/airorhythm_wifi_setup.ino`).
 * Same JSON, same endpoints, same failure reasons — so the app can be tried,
 * demoed and tested with no hardware on the desk.
 *
 * Run it on its own:
 *     node simulator/esp32-sim.js            # http://127.0.0.1:8099
 *     PORT=9000 node simulator/esp32-sim.js
 *
 * It is also mounted by ../server.js at /sim so the app can reach it
 * same-origin (that is how the online preview demo works).
 *
 * Endpoints
 *   Setup network (board's own hotspot, real board: 192.168.4.1)
 *     GET  /ap/status        -> { state, device, fw, ip, ... }
 *     GET  /ap/scan          -> { networks: [ { ssid, rssi, enc, ch }, ... ] }
 *     POST /ap/wifi          -> { ok: true, ip } | { ok:false, reason }
 *     POST /ap/reset         -> factory-fresh state again
 *
 *   Home network (real board: its LAN address)
 *     GET  /lan/status       -> { state:"connected", ip, ssid, rssi }
 *     GET  /lan/state        -> telemetry
 *     POST /lan/cmd          -> fan command
 *     POST /lan/wifi         -> switch network
 *     POST /lan/forget       -> clear Wi-Fi, back to setup network
 *     GET  /lan/scan
 */

'use strict';

const http = require('http');
const { URL } = require('url');

const FW = '1.0.0';
const DEVICE = 'AiroRhythm Fan';
const AP_SSID = 'AiroRhythm-Setup';
const LAN_IP = '192.168.1.23';

const NETWORKS = [
  { ssid: 'Home_WiFi', rssi: -46, enc: true, ch: 6, band: '2.4' },
  { ssid: 'JioFiber_5G', rssi: -58, enc: true, ch: 149, band: '5' },
  { ssid: 'ChaiShop_Guest', rssi: -71, enc: false, ch: 1, band: '2.4' },
  { ssid: 'TP-Link_2.4G', rssi: -79, enc: true, ch: 11, band: '2.4' },
];

function freshState() {
  return {
    phase: 'idle',            // idle | joining | connected | failed
    reason: null,             // not-found | bad-password | 5ghz | timeout
    apActive: true,
    lan: { ssid: null, ip: null, rssi: 0 },
    attemptSsid: null,
    fan: { on: false, speed: 0, rpm: 0, mode: 'manual', timerEnds: null },
    sensors: { temp: 29.4, rh: 54, smoke: 60, amps: 0.012 },
    bootedAt: Date.now(),
    lastCmd: null,
  };
}

class Sim {
  constructor() {
    this.reset();
    this.ticker = setInterval(() => this.tick(), 1000);
    this.ticker.unref?.();
  }

  reset() {
    this.s = freshState();
    this.joiningSince = 0;
    this.pending = null; // promise resolvers waiting for the attempt
    this.attempt = null;
    this.log = [];
  }

  note(msg) {
    this.log.push({ t: new Date().toISOString(), msg });
    if (this.log.length > 60) this.log.shift();
  }

  /* ---- the one piece of behaviour that makes the demo feel real ---- */
  startAttempt(ssid, password) {
    const net = NETWORKS.find((n) => n.ssid.toLowerCase() === String(ssid || '').toLowerCase());
    this.s.phase = 'joining';
    this.s.reason = null;
    this.s.attemptSsid = ssid;
    this.joiningSince = Date.now();
    this.note(`join "${ssid}"`);

    let outcome;
    if (!ssid) outcome = { ok: false, reason: 'not-found' };
    else if (!net) outcome = { ok: false, reason: 'not-found' };
    else if (net.band === '5') outcome = { ok: false, reason: '5ghz' };
    else if (net.enc && String(password || '').length < 8) outcome = { ok: false, reason: 'bad-password' };
    else outcome = { ok: true, reason: null };

    // A real board takes 3–8 s to associate, get an address and settle.
    this.attempt = { resolveAt: Date.now() + (outcome.ok ? 5200 : 3400), outcome, ssid, password };
  }

  finishAttempt() {
    const { outcome, ssid } = this.attempt;
    const net = NETWORKS.find((n) => n.ssid === ssid);
    this.attempt = null;
    if (outcome.ok) {
      this.s.phase = 'connected';
      this.s.apActive = false;
      this.s.lan = { ssid, ip: LAN_IP, rssi: net ? net.rssi : -60 };
      this.note(`connected to ${ssid} as ${LAN_IP}`);
    } else {
      this.s.phase = 'failed';
      this.s.reason = outcome.reason;
      this.s.attemptSsid = ssid;
      this.s.apActive = true;
      this.note(`join failed (${outcome.reason})`);
    }
    const waiting = this.pending || [];
    this.pending = [];
    waiting.forEach((fn) => fn(this.attemptResult()));
  }

  attemptResult() {
    if (this.s.phase === 'connected') {
      return { ok: true, ip: this.s.lan.ip, ssid: this.s.lan.ssid, rssi: this.s.lan.rssi };
    }
    return { ok: false, reason: this.s.reason || 'timeout', ssid: this.s.attemptSsid };
  }

  waitForAttempt() {
    return new Promise((resolve) => {
      if (this.s.phase === 'connected' || this.s.phase === 'failed') return resolve(this.attemptResult());
      this.pending = this.pending || [];
      this.pending.push(resolve);
    });
  }

  tick() {
    if (this.attempt && Date.now() >= this.attempt.resolveAt) this.finishAttempt();

    // Fan physics-lite: rpm walks toward the target, amps follow the load.
    const f = this.s.fan;
    const target = f.on ? f.targetRpm || 0 : 0;
    f.rpm += (target - f.rpm) * 0.18;
    if (Math.abs(f.rpm - target) < 5) f.rpm = target;
    const base = f.on ? 0.035 + (f.rpm / 2400) * 0.28 : 0.008;
    this.s.sensors.amps = +(base + Math.random() * 0.006).toFixed(3);

    // Gentle sensor drift so the live screen breathes.
    this.s.sensors.temp = +clamp(this.s.sensors.temp + (Math.random() - 0.5) * 0.12, 26, 34).toFixed(1);
    this.s.sensors.rh = Math.round(clamp(this.s.sensors.rh + (Math.random() - 0.5) * 0.7, 30, 80));
    this.s.sensors.smoke = Math.round(clamp(this.s.sensors.smoke + (Math.random() - 0.5) * 4, 20, 120));

    if (f.timerEnds && Date.now() > f.timerEnds) {
      f.on = false;
      f.targetRpm = 0;
      f.timerEnds = null;
      f.mode = 'manual';
    }
  }

  statusPayload(kind) {
    const base = { device: DEVICE, fw: FW, model: 'ESP32-DevKitC', kind };
    if (this.s.phase === 'connected') {
      return {
        ...base,
        state: 'connected',
        ip: this.s.lan.ip,
        ssid: this.s.lan.ssid,
        rssi: this.s.lan.rssi,
        ap: AP_SSID,
      };
    }
    return {
      ...base,
      state: this.s.phase === 'joining' ? 'connecting' : this.s.phase === 'failed' ? 'failed' : 'ap',
      ip: kind === 'ap' ? '192.168.4.1' : null,
      ap: AP_SSID,
      ssid: this.s.phase === 'failed' ? this.s.attemptSsid : null,
      reason: this.s.reason,
      rssi: 0,
    };
  }

  telemetry() {
    const f = this.s.fan;
    return {
      t: 'tel',
      ts: Date.now(),
      on: f.on,
      speed: f.speed,
      rpm: Math.round(f.rpm),
      targetRpm: f.targetRpm || 0,
      mode: f.timerEnds ? 'timer' : f.mode,
      timerLeft: f.timerEnds ? Math.max(0, Math.round((f.timerEnds - Date.now()) / 1000)) : 0,
      temp: this.s.sensors.temp,
      rh: this.s.sensors.rh,
      smoke: this.s.sensors.smoke,
      amps: this.s.sensors.amps,
      watts: +(this.s.sensors.amps * 230).toFixed(1),
      ssid: this.s.lan.ssid,
      rssi: this.s.lan.rssi,
      ip: this.s.lan.ip,
      uptime: Math.round((Date.now() - this.s.bootedAt) / 1000),
      fw: FW,
    };
  }

  command(body) {
    const f = this.s.fan;
    const a = body && body.a;
    if (a === 'fan') {
      if (typeof body.on === 'boolean') f.on = body.on;
      if (typeof body.speed === 'number') {
        f.speed = clamp(body.speed, 0, 4);
        f.targetRpm = [0, 600, 1000, 1500, 1900][f.speed] || 0;
        if (f.speed > 0) f.on = true;
        if (f.speed === 0) f.on = false;
      }
      if (!f.on) f.targetRpm = 0;
      f.mode = 'manual';
      f.timerEnds = body.timer ? Date.now() + body.timer * 1000 : null;
      this.s.lastCmd = body;
      this.note(`cmd fan on=${f.on} speed=${f.speed}`);
      return { ok: true, on: f.on, speed: f.speed, targetRpm: f.targetRpm };
    }
    if (a === 'reset') {
      this.reset();
      return { ok: true, rebooted: true };
    }
    return { ok: false, reason: 'unknown-command' };
  }

  forget() {
    const old = this.s.lan.ssid;
    // Keep the fan running state, wipe the network — like a real reboot into setup mode.
    const keep = this.s.fan;
    this.reset();
    this.s.fan = keep;
    this.note(`forgot ${old || 'network'}`);
    return { ok: true, ap: AP_SSID };
  }

  scan() {
    return {
      networks: NETWORKS.map((n) => ({ ssid: n.ssid, rssi: n.rssi, enc: n.enc, ch: n.ch })),
    };
  }
}

function clamp(v, a, b) {
  return Math.min(b, Math.max(a, v));
}

/* ------------------------------ HTTP layer ------------------------------ */

function send(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET,POST,OPTIONS',
    'access-control-allow-headers': 'content-type',
    'access-control-allow-private-network': 'true',
  });
  res.end(body);
}

function readJson(req) {
  return new Promise((resolve) => {
    let raw = '';
    req.on('data', (c) => {
      raw += c;
      if (raw.length > 4000) req.destroy();
    });
    req.on('end', () => {
      try {
        resolve(raw ? JSON.parse(raw) : {});
      } catch {
        resolve({});
      }
    });
    req.on('error', () => resolve({}));
  });
}

/**
 * Creates a handler for the simulator.
 * @param {{prefix?: string}} opts prefix is stripped before routing (`/sim`)
 */
function createSimHandler(opts = {}) {
  const prefix = opts.prefix || '';
  const sim = new Sim();

  const handler = async (req, res) => {
    const url = new URL(req.url, 'http://sim.local');
    let path = url.pathname;
    if (prefix && path.startsWith(prefix)) path = path.slice(prefix.length) || '/';

    // Root aliases mirror the real board, which serves /status, /state,
    // /cmd ... at the address root in whichever mode it is in.
    const online = sim.s.phase === 'connected';
    if (path === '/status') path = online ? '/lan/status' : '/ap/status';
    else if (path === '/state') path = '/lan/state';
    else if (path === '/cmd') path = '/lan/cmd';
    else if (path === '/forget') path = '/lan/forget';
    else if (path === '/scan') path = online ? '/lan/scan' : '/ap/scan';
    else if (path === '/wifi') path = online ? '/lan/wifi' : '/ap/wifi';
    else if (path === '/reset') path = '/ap/reset';

    if (!path.startsWith('/ap') && !path.startsWith('/lan')) return false;

    if (req.method === 'OPTIONS') {
      res.writeHead(204, {
        'access-control-allow-origin': '*',
        'access-control-allow-methods': 'GET,POST,OPTIONS',
        'access-control-allow-headers': 'content-type',
        'access-control-allow-private-network': 'true',
        'access-control-max-age': '86400',
      });
      return res.end(), true;
    }

    // A tiny pause so the UI's "talking to the board" states are visible.
    await new Promise((r) => setTimeout(r, 120));

    if (path === '/ap/status' && req.method === 'GET') {
      return send(res, 200, sim.statusPayload('ap')), true;
    }
    if (path === '/ap/scan' && req.method === 'GET') {
      return send(res, 200, sim.scan()), true;
    }
    if ((path === '/ap/wifi' || path === '/lan/wifi') && req.method === 'POST') {
      const body = await readJson(req);
      if (sim.s.phase === 'joining') return send(res, 409, { ok: false, reason: 'busy' }), true;
      // Return straight away; the app polls /status for the staged progress.
      sim.startAttempt(body.ssid, body.password);
      const result = await sim.waitForAttempt();
      return send(res, 200, result), true;
    }
    if (path === '/ap/reset' && req.method === 'POST') {
      sim.reset();
      return send(res, 200, { ok: true }), true;
    }
    if (path === '/lan/status' && req.method === 'GET') {
      const connected = sim.s.phase === 'connected';
      return send(res, connected ? 200 : 503, sim.statusPayload('lan')), true;
    }
    if (path === '/lan/state' && req.method === 'GET') {
      if (sim.s.phase !== 'connected') return send(res, 503, { error: 'offline' }), true;
      return send(res, 200, sim.telemetry()), true;
    }
    if (path === '/lan/cmd' && req.method === 'POST') {
      if (sim.s.phase !== 'connected') return send(res, 503, { error: 'offline' }), true;
      const body = await readJson(req);
      return send(res, 200, sim.command(body)), true;
    }
    if (path === '/lan/forget' && req.method === 'POST') {
      return send(res, 200, sim.forget()), true;
    }
    if (path === '/lan/scan' && req.method === 'GET') {
      return send(res, 200, sim.scan()), true;
    }

    return send(res, 404, { error: 'not-found', path }), true;
  };

  handler.sim = sim;
  return handler;
}

module.exports = { createSimHandler, Sim, NETWORKS, DEVICE, FW };

/* ------------------------------ standalone ------------------------------ */

if (require.main === module) {
  const port = Number(process.env.PORT || 8099);
  const handler = createSimHandler();
  const server = http.createServer(async (req, res) => {
    const handled = await handler(req, res);
    if (!handled) {
      res.writeHead(404, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: 'not-found', hint: 'try /status, /scan, /state, /cmd or /ap/* /lan/*' }));
    }
  });
  server.listen(port, '0.0.0.0', () => {
    console.log(`AiroRhythm ESP32 simulator on http://0.0.0.0:${port}`);
    console.log('  GET  /ap/status   /ap/scan   POST /ap/wifi   POST /ap/reset');
    console.log('  GET  /lan/state   POST /lan/cmd   POST /lan/forget');
    console.log('  Demo networks: ' + NETWORKS.map((n) => n.ssid).join(', '));
  });
}
