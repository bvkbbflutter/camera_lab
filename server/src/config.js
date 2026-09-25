'use strict';

const path = require('path');

const ROOT = path.resolve(__dirname, '..');

function intEnv(name, fallback) {
  const v = process.env[name];
  if (v === undefined || v === '') return fallback;
  const n = Number.parseInt(v, 10);
  return Number.isFinite(n) ? n : fallback;
}

const maxFileMb = intEnv('MAX_FILE_MB', 25);

module.exports = Object.freeze({
  // 0.0.0.0 so a phone / emulator on the same network can reach "localhost" of this machine.
  host: process.env.HOST || '0.0.0.0',
  port: intEnv('PORT', 3000),

  rootDir: ROOT,
  // Image binaries live here: assets/jpeg, assets/png, assets/webp
  assetsDir: process.env.ASSETS_DIR || path.join(ROOT, 'assets'),
  // Metadata index (derived from the images, NOT the source of truth)
  dbFile: process.env.DB_FILE || path.join(ROOT, 'db.json'),

  maxFileBytes: maxFileMb * 1024 * 1024,
  // Base64 inflates by 4/3, plus JSON overhead.
  maxJsonBytes: Math.ceil(maxFileMb * 1024 * 1024 * 4 / 3) + 64 * 1024,
  maxPixels: intEnv('MAX_PIXELS', 100_000_000), // 100 MP
  maxDimension: intEnv('MAX_DIMENSION', 16_384),

  // Optional. When set, every /api/images request needs "Authorization: Bearer <token>".
  apiToken: process.env.API_TOKEN || '',

  // Dev only: lets the app send "X-Simulate: 400|401|413|500|timeout|slow:<ms>" for network tests.
  simulate: process.env.SIMULATE === 'true',
});
