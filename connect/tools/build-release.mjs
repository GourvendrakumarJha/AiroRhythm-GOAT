#!/usr/bin/env node
/**
 * Assemble the shippable package.
 *
 *   node tools/build-release.mjs        (or: npm run release)
 *
 * Output (git-ignored, safe to delete):
 *   ../release/airorhythm-connect-<version>/
 *   ../release/airorhythm-connect-<version>.zip
 *   ../release/airorhythm-connect-<version>/SHA256SUMS.txt
 *
 * The app itself is a single file — this just copies the right pieces together and
 * gives them a version and a checksum, so nothing has to be hand-picked later.
 */

import { createHash } from 'node:crypto';
import { deflateRawSync } from 'node:zlib';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const CONNECT = path.resolve(HERE, '..');
const REPO = path.resolve(CONNECT, '..');
const OUT_ROOT = path.join(REPO, 'release');

const pkg = JSON.parse(fs.readFileSync(path.join(CONNECT, 'package.json'), 'utf8'));
const VERSION = pkg.version;
const NAME = `airorhythm-connect-${VERSION}`;
const OUT_DIR = path.join(OUT_ROOT, NAME);
const ZIP_PATH = path.join(OUT_ROOT, `${NAME}.zip`);

/* Everything that goes in, as [source relative to connect/, destination relative to the package]. */
const FILES = [
  ['index.html', 'index.html'],
  ['assets/logo_mark.png', 'assets/logo_mark.png'],
  ['firmware/airorhythm_wifi_setup.ino', 'firmware/airorhythm_wifi_setup.ino'],
  ['simulator/esp32-sim.js', 'simulator/esp32-sim.js'],
  ['tools/production-server.js', 'server.js'],
  ['tools/PRODUCTION-README.md', 'README.md'],
];

fs.rmSync(OUT_DIR, { recursive: true, force: true });
fs.mkdirSync(OUT_DIR, { recursive: true });

const written = [];
for (const [from, to] of FILES) {
  const src = path.join(CONNECT, from);
  const dest = path.join(OUT_DIR, to);
  if (!fs.existsSync(src)) throw new Error(`missing source file: ${from}`);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
  written.push(to);
}

/* package.json for the package itself (the dev one has test/sim-only scripts). */
const prodPkg = {
  name: 'airorhythm-connect',
  version: VERSION,
  private: true,
  description: pkg.description,
  homepage: 'https://github.com/GourvendrakumarJha/AiroRhythm-GOAT',
  scripts: {
    start: 'node server.js',
    sim: 'node simulator/esp32-sim.js',
  },
  engines: { node: '>=18' },
};
fs.writeFileSync(path.join(OUT_DIR, 'package.json'), JSON.stringify(prodPkg, null, 2) + '\n');
written.push('package.json');

/* Checksums, so a copy can be proven intact. */
const sum = (buf) => createHash('sha256').update(buf).digest('hex');
const sums = written
  .slice()
  .sort()
  .map((rel) => `${sum(fs.readFileSync(path.join(OUT_DIR, rel)))}  ${rel}`);
fs.writeFileSync(path.join(OUT_DIR, 'SHA256SUMS.txt'), sums.join('\n') + '\n');

/* ---------------------------------------------------------------- zip ---- */
/* Minimal ZIP writer: deflate + UTF-8 names, no dependencies, works on Windows too. */

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function dosTime(d) {
  const time = ((d.getHours() & 31) << 11) | ((d.getMinutes() & 63) << 5) | ((d.getSeconds() / 2) & 31);
  const date = (((d.getFullYear() - 1980) & 127) << 9) | (((d.getMonth() + 1) & 15) << 5) | (d.getDate() & 31);
  return { time, date };
}

function listFiles(dir, base = dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) listFiles(full, base, out);
    else out.push(path.relative(base, full).split(path.sep).join('/'));
  }
  return out;
}

function makeZip(srcDir, zipPath) {
  const entries = listFiles(srcDir).sort();
  const now = new Date();
  const { time, date } = dosTime(now);
  const local = [];
  const central = [];
  let offset = 0;

  for (const rel of entries) {
    const data = fs.readFileSync(path.join(srcDir, rel));
    const deflated = deflateRawSync(data, { level: 9 });
    const useDeflate = deflated.length < data.length;
    const body = useDeflate ? deflated : data;
    const method = useDeflate ? 8 : 0;
    const nameBuf = Buffer.from(rel, 'utf8');
    const crc = crc32(data);

    const header = Buffer.alloc(30);
    header.writeUInt32LE(0x04034b50, 0);
    header.writeUInt16LE(20, 4);
    header.writeUInt16LE(0x0800, 6); // UTF-8 names
    header.writeUInt16LE(method, 8);
    header.writeUInt16LE(time, 10);
    header.writeUInt16LE(date, 12);
    header.writeUInt32LE(crc, 14);
    header.writeUInt32LE(body.length, 18);
    header.writeUInt32LE(data.length, 22);
    header.writeUInt16LE(nameBuf.length, 26);
    header.writeUInt16LE(0, 28);

    local.push(header, nameBuf, body);

    const cd = Buffer.alloc(46);
    cd.writeUInt32LE(0x02014b50, 0);
    cd.writeUInt16LE(20, 4); // version made by
    cd.writeUInt16LE(20, 6); // version needed
    cd.writeUInt16LE(0x0800, 8);
    cd.writeUInt16LE(method, 10);
    cd.writeUInt16LE(time, 12);
    cd.writeUInt16LE(date, 14);
    cd.writeUInt32LE(crc, 16);
    cd.writeUInt32LE(body.length, 20);
    cd.writeUInt32LE(data.length, 24);
    cd.writeUInt16LE(nameBuf.length, 28);
    cd.writeUInt16LE(0, 30); // extra
    cd.writeUInt16LE(0, 32); // comment
    cd.writeUInt16LE(0, 34); // disk
    cd.writeUInt16LE(0, 36); // internal attrs
    cd.writeUInt32LE((0o100644 << 16) >>> 0, 38); // external attrs: regular file 0644
    cd.writeUInt32LE(offset, 42);

    central.push(cd, nameBuf);
    offset += header.length + nameBuf.length + body.length;
  }

  const centralBuf = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(0, 4);
  end.writeUInt16LE(0, 6);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(centralBuf.length, 12);
  end.writeUInt32LE(offset, 16);
  end.writeUInt16LE(0, 20);

  fs.writeFileSync(zipPath, Buffer.concat([...local, centralBuf, end]));
  return entries;
}

fs.mkdirSync(OUT_ROOT, { recursive: true });
const zipped = makeZip(OUT_DIR, ZIP_PATH);

/* ------------------------------------------------------------- report ---- */
const kb = (n) => `${(n / 1024).toFixed(1)} kB`;
console.log(`\n${NAME}\n${'─'.repeat(52)}`);
for (const rel of written.slice().sort()) {
  const size = fs.statSync(path.join(OUT_DIR, rel)).size;
  console.log(`  ${rel.padEnd(40)} ${kb(size).padStart(9)}`);
}
console.log('─'.repeat(52));
console.log(`  folder   ${path.relative(REPO, OUT_DIR)}  (${written.length} files)`);
console.log(`  zip      ${path.relative(REPO, ZIP_PATH)}  (${kb(fs.statSync(ZIP_PATH).size)}, ${zipped.length} entries)`);
console.log('\nDeploy: copy index.html + assets/ to any static host, or run `node server.js`.');
console.log('Flash:  open firmware/airorhythm_wifi_setup.ino in the Arduino IDE.\n');
