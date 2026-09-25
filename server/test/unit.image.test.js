'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const { inspectImage } = require('../src/image/inspect');
const { sniffFormat } = require('../src/image/sniff');

const FIX = path.join(__dirname, 'fixtures');
const load = (name) => fs.readFileSync(path.join(FIX, name));

test('sniffFormat identifies real formats from magic bytes, ignoring extension', () => {
  assert.equal(sniffFormat(load('with_gps.jpg')), 'jpeg');
  assert.equal(sniffFormat(load('with_gps.png')), 'png');
  assert.equal(sniffFormat(load('with_gps.webp')), 'webp');
  assert.equal(sniffFormat(load('not_an_image.txt')), null);
});

test('JPEG: dimensions, GPS, capture time, camera, orientation and DPI all round-trip', () => {
  const info = inspectImage(load('with_gps.jpg'));
  assert.equal(info.format, 'jpeg');
  assert.equal(info.width, 1920);
  assert.equal(info.height, 1440);
  assert.equal(info.exifPresent, true);

  assert.ok(info.gps);
  assert.ok(Math.abs(info.gps.latitude - 17.385044) < 1e-4);
  assert.ok(Math.abs(info.gps.longitude - 78.486671) < 1e-4);
  assert.equal(info.gps.latitudeRef, 'N');
  assert.ok(Math.abs(info.gps.altitude - 530) < 1);

  assert.equal(info.capture.dateTimeOriginal, '2026:09:24 10:42:31');
  assert.equal(info.capture.capturedAt, '2026-09-24T10:42:31.123+05:30');

  assert.equal(info.camera.make, 'Samsung');
  assert.equal(info.camera.model, 'SM-S928B');
  assert.equal(info.camera.facing, 'back');
  assert.equal(info.camera.iso, 100);

  assert.equal(info.orientation.value, 1);

  assert.ok(info.dpi);
  assert.equal(info.dpi.x, 300);
  assert.equal(info.dpi.y, 300);
  assert.equal(info.dpi.source, 'exif');
});

test('JPEG without GPS reports gps:null but keeps other EXIF', () => {
  const info = inspectImage(load('no_gps.jpg'));
  assert.equal(info.gps, null);
  assert.equal(info.camera.make, 'Samsung');
  assert.equal(info.exifPresent, true);
});

test('JPEG with no EXIF at all reports exifPresent:false and nulls, not fake values', () => {
  const info = inspectImage(load('no_exif.jpg'));
  assert.equal(info.exifPresent, false);
  assert.equal(info.gps, null);
  assert.equal(info.capture, null);
  assert.equal(info.camera, null);
  assert.equal(info.orientation, null);
  assert.equal(info.width, 1920);
  assert.equal(info.height, 1440);
});

test('PNG: eXIf chunk parses to the same GPS/camera/date values as the JPEG', () => {
  const info = inspectImage(load('with_gps.png'));
  assert.equal(info.format, 'png');
  assert.equal(info.exifPresent, true);
  assert.ok(Math.abs(info.gps.latitude - 17.385044) < 1e-4);
  assert.equal(info.camera.model, 'SM-S928B');
});

test('WebP lossless: EXIF chunk parses correctly', () => {
  const info = inspectImage(load('with_gps.webp'));
  assert.equal(info.format, 'webp');
  assert.equal(info.formatDetails.encoding, 'lossless');
  assert.equal(info.exifPresent, true);
  assert.ok(Math.abs(info.gps.longitude - 78.486671) < 1e-4);
});

test('WebP lossy: EXIF metadata survives lossy compression (verification, not assumption)', () => {
  const info = inspectImage(load('with_gps_lossy.webp'));
  assert.equal(info.format, 'webp');
  assert.equal(info.formatDetails.encoding, 'lossy');
  assert.equal(info.exifPresent, true);
  assert.equal(info.camera.make, 'Samsung');
});

test('corrupt JPEG throws a 400 CORRUPT_IMAGE error, not a crash', () => {
  assert.throws(() => inspectImage(load('corrupt.jpg')), (err) => {
    assert.equal(err.status, 400);
    assert.equal(err.code, 'CORRUPT_IMAGE');
    return true;
  });
});

test('non-image file throws a 415 UNSUPPORTED_FORMAT error', () => {
  assert.throws(() => inspectImage(load('not_an_image.txt')), (err) => {
    assert.equal(err.status, 415);
    assert.equal(err.code, 'UNSUPPORTED_FORMAT');
    return true;
  });
});
