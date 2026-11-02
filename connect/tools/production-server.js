#!/usr/bin/env node
/**
 * AiroRhythm Connect — production server
 * --------------------------------------
 * Serves the app over plain http:// on your own network and (optionally) forwards
 * requests to the fan, so an https:// page or a phone on another origin can still
 * reach a board at http://192.168.x.x.
 *
 *   node server.js                            # http://localhost:8080
 *   PORT=3000 node server.js                  # another port
 *   BOARD_HOST=192.168.1.23 node server.js    # also accept /board/*
 *   BOARD_HOST=airorhythm.local:80 node server.js
 *
 * Endpoints
 *   GET  /                 the app (index.html)
 *   GET  /assets/*         static files
 *   GET  /health           {"ok":true,"board":"192.168.1.23"|null,"version":"1.0.0"}
 *   ANY  /board/<path>     proxied to http://<BOARD_HOST>/<path>, 9 s timeout
 *   ANY  /sim/<path>       only if ./simulator/esp32-sim.js is present (demo)
 *
 * No dependencies. Node 18 or newer.
 */

'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');

const VERSION = '1.0.0';
const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '0.0.0.0';
const BOARD_HOST = (process.env.BOARD_HOST || '').trim().replace(/^https?:\/\//, '').replace(/\/+$/, '');
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

/* The demo is optional: it is mounted only when the simulator file was shipped. */
let sim = null;
try {
  const { createSimHandler } = require('./simulator/esp32-sim.js');
  sim = createSimHandler({ prefix: '/sim' });
} catch (_) {
  sim = null;
}

function cors(res) {
  res.setHeader('access-control-allow-origin', '*');
  res.setHeader('access-control-allow-methods', 'GET,POST,OPTIONS');
  res.setHeader('access-control-allow-headers', 'content-type');
  res.setHeader('access-control-allow-private-network', 'true');
}

function json(res, code, body, extra) {
  cors(res);
  res.writeHead(code, Object.assign({ 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' }, extra));
  res.end(JSON.stringify(body));
}

async function proxyBoard(req, res, url) {
  if (!BOARD_HOST) {
    json(res, 502, {
      error: 'no-board-configured',
      hint: 'Start with BOARD_HOST=192.168.1.23 node server.js',
    });
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
    cors(res);
    res.writeHead(upstream.status, {
      'content-type': upstream.headers.get('content-type') || 'application/json',
      'cache-control': 'no-store',
    });
    res.end(body);
  } catch (err) {
    json(res, 504, { error: 'unreachable', target, detail: String(err.message || err) });
  }
}

function serveStatic(req, res, url) {
  let rel = decodeURIComponent(url.pathname);
  if (rel === '/' || rel === '') rel = '/index.html';
  if (rel.includes('\0')) {
    res.writeHead(400).end('Bad request');
    return;
  }
  const filePath = path.normalize(path.join(ROOT, rel));
  const inside = filePath === ROOT || filePath.startsWith(ROOT + path.sep);
  const hidden = rel.split('/').some((part) => part.startsWith('.'));
  if (!inside || hidden) {
    res.writeHead(403).end('Forbidden');
    return;
  }
  fs.readFile(filePath, (err, data) => {
    if (err) {
      // SPA-ish fallback: unknown paths that are not files get the app.
      const isApi = rel.startsWith('/board') || rel.startsWith('/sim');
      if (!isApi && !path.extname(rel) && req.method === 'GET') {
        fs.readFile(path.join(ROOT, 'index.html'), (e2, page) => {
          if (e2) {
            res.writeHead(500).end('index.html is missing');
            return;
          }
          res.writeHead(200, { 'content-type': MIME['.html'], 'cache-control': 'no-cache' });
          res.end(page);
        });
        return;
      }
      res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      res.end(`Not found: ${rel}\nOpen / for the app.\n`);
      return;
    }
    const ext = path.extname(filePath).toLowerCase();
    const longCache = ext !== '.html';
    res.writeHead(200, {
      'content-type': MIME[ext] || 'application/octet-stream',
      'cache-control': longCache ? 'public, max-age=86400' : 'no-cache',
      'content-length': data.length,
    });
    res.end(req.method === 'HEAD' ? undefined : data);
  });
}

const server = http.createServer(async (req, res) => {
  let url;
  try {
    url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  } catch (_) {
    res.writeHead(400).end('Bad request');
    return;
  }

  if (req.method === 'OPTIONS') {
    cors(res);
    res.writeHead(204).end();
    return;
  }

  if (url.pathname === '/health') {
    json(res, 200, { ok: true, board: BOARD_HOST || null, demo: Boolean(sim), version: VERSION });
    return;
  }

  if (url.pathname.startsWith('/board/')) {
    await proxyBoard(req, res, url);
    return;
  }

  if (url.pathname.startsWith('/sim/')) {
    if (!sim) {
      json(res, 404, {
        error: 'demo-not-installed',
        hint: 'Add the simulator/ folder next to server.js to enable the in-app demo.',
      });
      return;
    }
    cors(res);
    const handled = await sim(req, res);
    if (!handled) json(res, 404, { error: 'not-found' });
    return;
  }

  serveStatic(req, res, url);
});

server.on('error', (err) => {
  if (err && err.code === 'EADDRINUSE') {
    console.error(`Port ${PORT} is already in use. Try: PORT=8081 node server.js`);
    process.exit(1);
  }
  console.error(err);
  process.exit(1);
});

server.listen(PORT, HOST, () => {
  console.log(`AiroRhythm Connect ${VERSION}`);
  console.log(`  app      http://localhost:${PORT}/`);
  console.log(`  phone    http://<this-computer-ip>:${PORT}/  (same Wi-Fi)`);
  console.log(`  board    ${BOARD_HOST ? 'http://' + BOARD_HOST + '/  via /board/*' : 'not configured — set BOARD_HOST to proxy a fan'}`);
  console.log(`  demo     ${sim ? 'yes (/sim)' : 'no'}`);
});

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 1500).unref();
  });
}
