'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const fsp = fs.promises;
const os = require('os');
const path = require('path');
const http = require('http');

const { createApp } = require('../src/app');
const { JsonDb } = require('../src/db/jsonDb');
const { LocalStorageService } = require('../src/storage/LocalStorageService');

const FIX = path.join(__dirname, 'fixtures');
const load = (name) => fs.readFileSync(path.join(FIX, name));

let server, baseUrl, tmpDir;

test.before(async () => {
  tmpDir = await fsp.mkdtemp(path.join(os.tmpdir(), 'camera-lab-test-'));
  const storage = await new LocalStorageService(path.join(tmpDir, 'assets')).init();
  const db = await new JsonDb(path.join(tmpDir, 'db.json')).init();
  const app = createApp({ storage, db });
  server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

test.after(async () => {
  await new Promise((resolve) => server.close(resolve));
  await fsp.rm(tmpDir, { recursive: true, force: true });
});

async function json(method, urlPath, body) {
  const res = await fetch(baseUrl + urlPath, {
    method,
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  let payload = null;
  try { payload = await res.json(); } catch { /* non-JSON response */ }
  return { status: res.status, body: payload, res };
}

// ---------------------------------------------------------------------------

test('GET /api/health returns ok', async () => {
  const { status, body } = await json('GET', '/api/health');
  assert.equal(status, 200);
  assert.equal(body.success, true);
  assert.equal(body.status, 'ok');
});

test('POST /api/images/base64 stores the image, embedded EXIF is extracted', async () => {
  const buf = load('with_gps.jpg');
  const { status, body } = await json('POST', '/api/images/base64', {
    fileName: 'test.jpg',
    mimeType: 'image/jpeg',
    imageBase64: buf.toString('base64'),
    uploadId: 'up-1',
  });

  assert.equal(status, 201);
  assert.equal(body.success, true);
  assert.ok(body.fileId);
  assert.equal(body.image.format, 'jpeg');
  assert.equal(body.image.width, 1920);
  assert.equal(body.image.hasGps, true);
  assert.equal(body.image.exifPresent, true);

  // File actually landed on disk under assets/jpeg/
  const stored = fs.readdirSync(path.join(tmpDir, 'assets', 'jpeg'));
  assert.ok(stored.some((f) => f.endsWith('.jpg')));

  // Bytes on disk are byte-identical to what was sent (never re-encoded).
  const onDisk = fs.readFileSync(path.join(tmpDir, 'assets', 'jpeg', stored.find((f) => f.endsWith('.jpg'))));
  assert.ok(onDisk.equals(buf));

  // db.json actually has the record
  const dbContent = JSON.parse(fs.readFileSync(path.join(tmpDir, 'db.json'), 'utf8'));
  const rec = dbContent.images.find((r) => r.id === body.fileId);
  assert.ok(rec);
  assert.equal(rec.uploadMethod, 'base64');
  assert.equal(rec.cameraMake, 'Samsung');
  assert.ok(Math.abs(rec.latitude - 17.385044) < 1e-4);
});

test('POST /api/images/base64 rejects missing imageBase64', async () => {
  const { status, body } = await json('POST', '/api/images/base64', { fileName: 'x.jpg' });
  assert.equal(status, 400);
  assert.equal(body.success, false);
  assert.equal(body.error.code, 'MISSING_IMAGE_BASE64');
});

test('POST /api/images/base64 rejects invalid base64', async () => {
  const { status, body } = await json('POST', '/api/images/base64', { imageBase64: '!!!not-base64!!!' });
  assert.equal(status, 400);
  assert.equal(body.error.code, 'INVALID_BASE64');
});

test('POST /api/images/base64 rejects a non-image payload despite a claimed image mimeType (server never trusts client MIME)', async () => {
  const fakeImageBytes = Buffer.from('this is definitely not an image');
  const { status, body } = await json('POST', '/api/images/base64', {
    fileName: 'fake.jpg',
    mimeType: 'image/jpeg', // lies
    imageBase64: fakeImageBytes.toString('base64'),
  });
  assert.equal(status, 415);
  assert.equal(body.error.code, 'UNSUPPORTED_FORMAT');
});

test('POST /api/images/multipart stores the image via real multipart/form-data', async () => {
  const buf = load('with_gps.png');
  const form = new FormData();
  form.append('file', new Blob([buf], { type: 'image/png' }), 'photo.png');
  form.append('uploadId', 'up-multipart-1');

  const res = await fetch(baseUrl + '/api/images/multipart', { method: 'POST', body: form });
  const body = await res.json();

  assert.equal(res.status, 201);
  assert.equal(body.image.format, 'png');
  assert.equal(body.image.hasGps, true);

  const stored = fs.readdirSync(path.join(tmpDir, 'assets', 'png'));
  assert.ok(stored.some((f) => f.endsWith('.png')));
});

test('POST /api/images/multipart with no file field returns 400 MISSING_FILE', async () => {
  const form = new FormData();
  form.append('userId', 'u1');
  const res = await fetch(baseUrl + '/api/images/multipart', { method: 'POST', body: form });
  const body = await res.json();
  assert.equal(res.status, 400);
  assert.equal(body.error.code, 'MISSING_FILE');
});

test('GET /api/images/:id returns the exact stored binary', async () => {
  const buf = load('with_gps.webp');
  const form = new FormData();
  form.append('file', new Blob([buf], { type: 'image/webp' }), 'photo.webp');
  const uploadRes = await fetch(baseUrl + '/api/images/multipart', { method: 'POST', body: form });
  const uploadBody = await uploadRes.json();

  const getRes = await fetch(baseUrl + `/api/images/${uploadBody.fileId}`);
  assert.equal(getRes.status, 200);
  assert.equal(getRes.headers.get('content-type'), 'image/webp');
  const gotBuf = Buffer.from(await getRes.arrayBuffer());
  assert.ok(gotBuf.equals(buf));
});

test('GET /api/images/:id/metadata extracts metadata from the image itself, matches embedded EXIF', async () => {
  const buf = load('with_gps.jpg');
  const { body: uploadBody } = await json('POST', '/api/images/base64', {
    fileName: 'meta-test.jpg',
    imageBase64: buf.toString('base64'),
  });

  const { status, body } = await json('GET', `/api/images/${uploadBody.fileId}/metadata`);
  assert.equal(status, 200);
  assert.equal(body.source, 'embedded-in-image');
  assert.equal(body.metadata.exif.present, true);
  assert.equal(body.metadata.camera.make, 'Samsung');
  assert.equal(body.metadata.camera.model, 'SM-S928B');
  assert.ok(Math.abs(body.metadata.gps.latitude - 17.385044) < 1e-4);
  assert.equal(body.metadata.dpi.x, 300);
  assert.equal(body.metadata.orientation.value, 1);
});

test('GET /api/images/:id/metadata for unknown id returns 404', async () => {
  const { status, body } = await json('GET', '/api/images/does-not-exist/metadata');
  assert.equal(status, 404);
  assert.equal(body.error.code, 'NOT_FOUND');
});

test('GET /api/images lists uploaded images newest first, paginated', async () => {
  const { status, body } = await json('GET', '/api/images?limit=5&offset=0');
  assert.equal(status, 200);
  assert.equal(body.success, true);
  assert.ok(Array.isArray(body.images));
  assert.ok(body.images.length <= 5);
  assert.ok(body.total >= body.images.length);
});

test('DELETE /api/images/:id removes both the db record and the file', async () => {
  const buf = load('no_exif.jpg');
  const { body: uploadBody } = await json('POST', '/api/images/base64', {
    fileName: 'to-delete.jpg',
    imageBase64: buf.toString('base64'),
  });

  const delRes = await fetch(baseUrl + `/api/images/${uploadBody.fileId}`, { method: 'DELETE' });
  const delBody = await delRes.json();
  assert.equal(delRes.status, 200);
  assert.equal(delBody.success, true);

  const getRes = await fetch(baseUrl + `/api/images/${uploadBody.fileId}`);
  assert.equal(getRes.status, 404);
});

test('unknown route returns a JSON 404, not an HTML error page', async () => {
  const { status, body } = await json('GET', '/api/does-not-exist');
  assert.equal(status, 404);
  assert.equal(body.error.code, 'NOT_FOUND');
});
