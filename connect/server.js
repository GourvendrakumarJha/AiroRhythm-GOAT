#!/usr/bin/env node
/**
 * AiroRhythm Connect — local server
 * ---------------------------------
 * Serves the app and, at the same origin, either:
 *   /sim/*    the ESP32 simulator (default), or
 *   /board/*  a real board on your home Wi-Fi
 *
 * Why bother with a server when index.html is standalone?
 *   • `http://` — a browser will not let an `https://` page (or a hosted copy)
 *     talk to `http://192.168.x.x`. This server is plain HTTP, so it can.
 *   • Same-origin `/sim` means the demo works even in an https preview iframe.
 *   • It can find/remember the board address, so you do not retype it.
 *
 * Usage:
 *   node server.js                       # http://localhost:8080  (simulator as demo)
 *   PORT=3000 node server.js
 *   BOARD_HOST=192.168.1.23 node server.js   # proxy a real fan at /board
 */

'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const { createSimHandler } = require('./simulator/esp32-sim.js');

const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '0.0.0.0';
const BOARD_HOST = (process.env.BOARD_HOST || '').trim();
const ROOT = __dirname;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.webmanifest': 'application/manifest+json',
  '.woff2': 'font/woff2',
};

const sim = createSimHandler({ prefix: '/sim' });

function cors(res) {
  res.setHeader('access-control-allow-origin', '*');
  res.setHeader('access-control-allow-methods', 'GET,POST,OPTIONS');
  res.setHeader('access-control-allow-headers', 'content-type');
  res.setHeader('access-control-allow-private-network', 'true');
}

async function proxyBoard(req, res, url) {
  if (!BOARD_HOST) {
    res.writeHead(502, { 'content-type': 'application/json', 'access-control-allow-origin': '*' });
    res.end(
      JSON.stringify({
        error: 'no-board-configured',
        hint: 'Start with BOARD_HOST=192.168.1.23 node server.js, or use the simulator at /sim.',
      })
    );
    return;
  }
  const target = `http://${BOARD_HOST}${url.pathname.replace(/^\/board/, '') || '/'}${url.search}`;
  const chunks = [];
  for await (const c of req) chunks.push(c);
  try {
    const upstream = await fetch(target, {
      method: req.method,
      headers: { 'content-type': req.headers['content-type'] || 'application/json' },
      body: ['GET', 'HEAD'].includes(req.method) ? undefined : Buffer.concat(chunks),
      signal: AbortSignal.timeout(9000),
    });
    const body = Buffer.from(await upstream.arrayBuffer());
    res.writeHead(upstream.status, {
      'content-type': upstream.headers.get('content-type') || 'application/json',
      'cache-control': 'no-store',
      'access-control-allow-origin': '*',
      'access-control-allow-methods': 'GET,POST,OPTIONS',
      'access-control-allow-headers': 'content-type',
      'access-control-allow-private-network': 'true',
    });
    res.end(body);
  } catch (err) {
    res.writeHead(504, { 'content-type': 'application/json', 'access-control-allow-origin': '*' });
    res.end(JSON.stringify({ error: 'unreachable', target, detail: String(err.message || err) }));
  }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  if (req.method === 'OPTIONS') {
    cors(res);
    res.writeHead(204).end();
    return;
  }

  if (url.pathname === '/health') {
    cors(res);
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: true, sim: sim.sim.s.phase, board: BOARD_HOST || null }));
    return;
  }

  if (url.pathname.startsWith('/sim/')) {
    cors(res);
    const handled = await sim(req, res);
    if (!handled) {
      res.writeHead(404, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: 'not-found' }));
    }
    return;
  }

  if (url.pathname.startsWith('/board/')) {
    await proxyBoard(req, res, url);
    return;
  }

  // static app
  let rel = decodeURIComponent(url.pathname);
  if (rel === '/' || rel === '') rel = '/index.html';
  const filePath = path.normalize(path.join(ROOT, rel));
  if (!filePath.startsWith(ROOT)) {
    res.writeHead(403).end('Forbidden');
    return;
  }
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      res.end('Not found: ' + rel + '\nTry / for the app.');
      return;
    }
    res.writeHead(200, {
      'content-type': MIME[path.extname(filePath).toLowerCase()] || 'application/octet-stream',
      'cache-control': 'no-cache',
      'x-content-type-options': 'nosniff',
    });
    res.end(data);
  });
});

server.listen(PORT, HOST, () => {
  console.log('');
  console.log('  AiroRhythm Connect');
  console.log(`  app        http://localhost:${PORT}/`);
  console.log(`  demo       http://localhost:${PORT}/?demo=1   (simulated ESP32 at /sim)`);
  console.log(`  simulator  ${BOARD_HOST ? 'off (real board proxied at /board)' : 'on  → /sim'}`);
  if (BOARD_HOST) console.log(`  real board http://${BOARD_HOST} proxied at /board/*`);
  console.log('');
});
