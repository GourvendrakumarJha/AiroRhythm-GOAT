/**
 * Simulator contract tests — the same JSON the firmware speaks.
 *   node --test tests/
 */
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { createSimHandler } = require('../simulator/esp32-sim.js');

const handler = createSimHandler();
let server;
let origin;

test.before(async () => {
  server = http.createServer(async (req, res) => {
    const handled = await handler(req, res);
    if (!handled) {
      res.writeHead(404).end();
    }
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  origin = 'http://127.0.0.1:' + server.address().port;
});

test.after(() => server && server.close());

const get = async (path) => {
  const res = await fetch(origin + path);
  return { status: res.status, headers: res.headers, body: await res.json() };
};

const post = async (path, body) => {
  const res = await fetch(origin + path, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { status: res.status, headers: res.headers, body: await res.json() };
};

test('setup mode answers /ap/status and offers CORS', async () => {
  const { status, body, headers } = await get('/ap/status');
  assert.equal(status, 200);
  assert.equal(body.state, 'ap');
  assert.equal(body.device, 'AiroRhythm Fan');
  assert.equal(body.fw, '1.0.0');
  assert.equal(headers.get('access-control-allow-origin'), '*');
});

test('preflight requests are allowed (the app lives on another origin)', async () => {
  const res = await fetch(origin + '/ap/wifi', { method: 'OPTIONS' });
  assert.equal(res.status, 204);
  assert.equal(res.headers.get('access-control-allow-methods'), 'GET,POST,OPTIONS');
});

test('scan lists 2.4 GHz and 5 GHz networks', async () => {
  const { body } = await get('/ap/scan');
  const names = body.networks.map((n) => n.ssid);
  assert.ok(names.includes('Home_WiFi'));
  assert.ok(names.includes('JioFiber_5G'));
  assert.ok(body.networks.every((n) => typeof n.rssi === 'number' && typeof n.enc === 'boolean'));
});

test('short password fails with bad-password and keeps setup mode alive', async () => {
  const { body } = await post('/ap/wifi', { ssid: 'Home_WiFi', password: '1234' });
  assert.equal(body.ok, false);
  assert.equal(body.reason, 'bad-password');
  const status = await get('/ap/status');
  assert.equal(status.body.state, 'failed');
});

test('a 5 GHz network is refused with a specific reason', async () => {
  const { body } = await post('/ap/wifi', { ssid: 'JioFiber_5G', password: 'password123' });
  assert.equal(body.ok, false);
  assert.equal(body.reason, '5ghz');
});

test('an unknown network reports not-found', async () => {
  const { body } = await post('/ap/wifi', { ssid: 'NoSuchNetwork', password: 'password123' });
  assert.equal(body.ok, false);
  assert.equal(body.reason, 'not-found');
});

test('correct details bring the fan online with an address', async () => {
  const { body } = await post('/ap/wifi', { ssid: 'Home_WiFi', password: 'password123' });
  assert.equal(body.ok, true);
  assert.equal(body.ip, '192.168.1.23');
  assert.equal(body.ssid, 'Home_WiFi');

  const lan = await get('/lan/status');
  assert.equal(lan.status, 200);
  assert.equal(lan.body.state, 'connected');
});

test('telemetry and commands work on the home network', async () => {
  const before = await get('/lan/state');
  assert.equal(before.body.on, false);
  assert.equal(typeof before.body.temp, 'number');
  assert.equal(typeof before.body.ip, 'string');

  const cmd = await post('/lan/cmd', { a: 'fan', on: true, speed: 3 });
  assert.equal(cmd.body.ok, true);
  assert.equal(cmd.body.speed, 3);
  assert.equal(cmd.body.targetRpm, 1500);

  await new Promise((r) => setTimeout(r, 1200));
  const after = await get('/lan/state');
  assert.equal(after.body.on, true);
  assert.ok(after.body.rpm > 0, 'fan spins up');
  assert.ok(after.body.watts >= 0);
});

test('an unknown command is rejected, not guessed', async () => {
  const { body } = await post('/lan/cmd', { a: 'self-destruct' });
  assert.equal(body.ok, false);
  assert.equal(body.reason, 'unknown-command');
});

test('forget puts the board back into setup mode', async () => {
  const forget = await post('/lan/forget', {});
  assert.equal(forget.body.ok, true);
  const ap = await get('/ap/status');
  assert.equal(ap.body.state, 'ap');
  const lan = await get('/lan/state');
  assert.equal(lan.status, 503);
});
