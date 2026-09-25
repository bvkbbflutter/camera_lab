'use strict';

/**
 * Tiny JSON-file database for the POC (db.json).
 *
 * - Whole file is loaded into memory on start.
 * - Writes are serialised through a promise chain and made atomic with
 *   write-to-temp + rename, so a crash never leaves a half-written db.json.
 *
 * Records here are an INDEX of metadata extracted from the stored images.
 * The image file in assets/ remains the authoritative source of its metadata.
 *
 * For production swap this for PostgreSQL / MongoDB with the same interface.
 */

const fs = require('fs');
const fsp = fs.promises;
const path = require('path');

class JsonDb {
  constructor(filePath) {
    this.filePath = filePath;
    this.data = { images: [] };
    this._chain = Promise.resolve();
  }

  async init() {
    await fsp.mkdir(path.dirname(this.filePath), { recursive: true });
    try {
      const raw = await fsp.readFile(this.filePath, 'utf8');
      const parsed = raw.trim() ? JSON.parse(raw) : {};
      this.data = { images: Array.isArray(parsed.images) ? parsed.images : [] };
    } catch (err) {
      if (err.code !== 'ENOENT') throw new Error(`db.json is not valid JSON: ${err.message}`);
      await this._persist();
    }
    return this;
  }

  _persist() {
    const tmp = `${this.filePath}.${process.pid}.tmp`;
    const body = JSON.stringify(this.data, null, 2) + '\n';
    return fsp.writeFile(tmp, body, 'utf8').then(() => fsp.rename(tmp, this.filePath));
  }

  _enqueue(mutator) {
    const run = this._chain.then(async () => {
      const result = mutator(this.data);
      await this._persist();
      return result;
    });
    // keep the chain alive even if one write fails
    this._chain = run.catch(() => {});
    return run;
  }

  // ---- images -------------------------------------------------------------

  listImages({ limit = 100, offset = 0 } = {}) {
    const sorted = [...this.data.images].sort((a, b) => (a.uploadedAt < b.uploadedAt ? 1 : -1));
    return { total: sorted.length, items: sorted.slice(offset, offset + limit) };
  }

  getImage(id) {
    return this.data.images.find((r) => r.id === id) || null;
  }

  findByUploadId(uploadId) {
    if (!uploadId) return null;
    return this.data.images.find((r) => r.uploadId === uploadId) || null;
  }

  insertImage(record) {
    return this._enqueue((data) => {
      data.images.push(record);
      return record;
    });
  }

  deleteImage(id) {
    return this._enqueue((data) => {
      const idx = data.images.findIndex((r) => r.id === id);
      if (idx === -1) return null;
      const [removed] = data.images.splice(idx, 1);
      return removed;
    });
  }
}

module.exports = { JsonDb };
