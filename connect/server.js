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
// `npm run release` writes here; served at /downloads/ so the files can be grabbed
// straight from the preview (nothing is copied, it is the release folder itself).
const RELEASES = path.resolve(ROOT, '..', 'release');

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
  '.apk': 'application/vnd.android.package-archive',
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

/* ------------------------- /downloads (release files) ----------------- */

function walk(dir, base = dir, out = []) {
  let entries = [];
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch (_) {
    return out;
  }
  for (const e of entries) {
    if (e.name.startsWith('.')) continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) walk(full, base, out);
    else out.push(path.relative(base, full).split(path.sep).join('/'));
  }
  return out.sort();
}

function sizeLabel(n) {
  if (n < 1024) return n + ' B';
  if (n < 1024 * 1024) return (n / 1024).toFixed(1) + ' kB';
  return (n / 1024 / 1024).toFixed(2) + ' MB';
}

function downloadPage() {
  let dirs = [];
  let zips = [];
  let apks = [];
  let entries = [];
  try {
    entries = fs.readdirSync(RELEASES, { withFileTypes: true });
    dirs = entries.filter((e) => e.isDirectory()).map((e) => e.name).sort().reverse();
    zips = entries.filter((e) => e.isFile() && e.name.endsWith('.zip')).map((e) => e.name).sort().reverse();
    apks = entries.filter((e) => e.isFile() && e.name.endsWith('.apk')).map((e) => e.name).sort().reverse();
  } catch (_) {
    return '<!doctype html><meta charset="utf-8"><body style="font:16px system-ui;padding:40px;color:#334">'
      + '<h1>No release yet</h1><p>Run <code>cd connect &amp;&amp; npm run release</code> and reload this page.</p></body>';
  }

  const zipCards = zips
    .map((zip) => `<section><h2>${zip}</h2>
      <p class="zip"><a href="/downloads/${zip}" download>Download ${zip}</a>
      <span class="s">${sizeLabel(fs.statSync(path.join(RELEASES, zip)).size)} · everything in one file</span></p>
      <p class="h">Unzip it and open <code>README.md</code>, or run <code>node server.js</code> inside it.</p>
    </section>`)
    .join('');

  const apkCards = apks
    .map((apk) => `<section><h2>Android app</h2>
      <p class="zip"><a href="/downloads/${apk}" download>Download ${apk}</a>
      <span class="s">${sizeLabel(fs.statSync(path.join(RELEASES, apk)).size)} · install on the phone</span></p>
      <p class="h">Open it on the phone, allow "install unknown apps" once, then
      launch <b>AiroRhythm Connect</b>. Same app as the web page — it just talks to the fan without a browser.</p>
    </section>`)
    .join('');

  const blocks = dirs.map((dir) => {
    const root = path.join(RELEASES, dir);
    const files = walk(root);
    const zip = dir + '.zip';
    const hasZip = fs.existsSync(path.join(RELEASES, zip)) && !zips.includes(zip);
    const rows = files
      .filter((f) => f !== 'SHA256SUMS.txt')
      .map((f) => {
        let size = '';
        try {
          size = sizeLabel(fs.statSync(path.join(root, f)).size);
        } catch (_) {}
        const label = f === 'index.html' ? 'index.html <i>— the whole app</i>'
          : f === 'server.js' ? 'server.js <i>— optional local server</i>'
          : f === 'firmware/airorhythm_wifi_setup.ino' ? 'airorhythm_wifi_setup.ino <i>— flash this</i>'
          : f;
        return `<tr><td><a href="/downloads/${dir}/${f}" download>${label}</a></td><td class="s">${size}</td></tr>`;
      })
      .join('');
    return `<section>
      <h2>${dir}</h2>
      ${hasZip ? `<p class="zip"><a href="/downloads/${zip}" download>Download ${zip}</a> <span class="s">${sizeLabel(fs.statSync(path.join(RELEASES, zip)).size)} · everything in one file</span></p>` : ''}
      <table>${rows}</table>
    </section>`;
  }).join('');

  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>AiroRhythm Connect — download the files</title>
<style>
  :root{--ink:#101828;--ink2:#516074;--ink3:#8794a2;--line:#e7e2d6;--bg:#f7f4ed;--blue:#2f6bff}
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--ink);
       font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
       padding:32px 18px 64px}
  main{max-width:720px;margin:0 auto}
  h1{font-size:26px;letter-spacing:-.03em;margin:0 0 4px}
  p.lead{color:var(--ink2);margin:0 0 26px}
  section{background:#fff;border:1px solid var(--line);border-radius:16px;padding:16px 18px;margin-bottom:16px}
  h2{font-size:15px;letter-spacing:-.01em;margin:0 0 10px;color:var(--ink)}
  a{color:var(--blue);text-decoration:none;font-weight:650}
  a:hover{text-decoration:underline}
  table{width:100%;border-collapse:collapse}
  td{padding:7px 0;border-top:1px solid #f0ece2;vertical-align:top}
  tr:first-child td{border-top:0}
  td i{color:var(--ink3);font-style:normal;font-weight:500}
  td.s,.s{color:var(--ink3);font-size:12.5px;text-align:right;white-space:nowrap;font-weight:500}
  .h{color:var(--ink3);font-size:12.5px;line-height:1.5;margin:8px 0 0}
  .h b{color:var(--ink2)}
  .zip{margin:0 0 12px;padding:12px 14px;border-radius:12px;background:#eef3ff;border:1px solid #d8e4ff}
  .zip a{font-size:15.5px}
  .zip .s{display:block;text-align:left;margin-top:2px}
  code{background:#f1ede2;border-radius:5px;padding:1px 5px;font-size:13px}
  footer{color:var(--ink3);font-size:12.5px;text-align:center;margin-top:24px}
</style></head>
<body><main>
  <h1>AiroRhythm Connect — files</h1>
  <p class="lead">Grab the zip, or the individual files. <code>index.html</code> plus
     <code>assets/</code> is the whole app; <code>firmware/</code> goes to the board.</p>
  ${apkCards || ''}
  ${zipCards || ''}
  ${blocks || (zips.length ? '' : '<section><p>No release found. Run <code>npm run release</code>.</p></section>')}
  <footer>Served from <code>release/</code> by the local development server.</footer>
</main></body></html>`;
}

function serveDownloads(req, res, url) {
  const rel = decodeURIComponent(url.pathname.replace(/^\/downloads\/?/, ''));

  if (!rel) {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
    res.end(downloadPage());
    return;
  }

  const filePath = path.normalize(path.join(RELEASES, rel));
  if (!filePath.startsWith(RELEASES + path.sep) || rel.split('/').some((p) => p.startsWith('.'))) {
    res.writeHead(403).end('Forbidden');
    return;
  }
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      res.end('Not found in the release folder: ' + rel + '\nSee /downloads/ for the list.');
      return;
    }
    const ext = path.extname(filePath).toLowerCase();
    const headers = {
      'content-type': MIME[ext] || 'application/octet-stream',
      'content-length': data.length,
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
    };
    if (ext === '.zip' || ext === '.ino' || ext === '.apk') {
      headers['content-disposition'] = `attachment; filename="${path.basename(filePath)}"`;
    }
    res.writeHead(200, headers);
    res.end(req.method === 'HEAD' ? undefined : data);
  });
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

  if (url.pathname === '/downloads') {
    res.writeHead(302, { location: '/downloads/' }).end();
    return;
  }

  if (url.pathname.startsWith('/downloads/')) {
    serveDownloads(req, res, url);
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
