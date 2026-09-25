'use strict';

const fs = require('fs');
const fsp = fs.promises;
const path = require('path');
const { StorageService } = require('./StorageService');

/**
 * Stores image binaries on local disk under assets/:
 *
 *   assets/
 *   ├── jpeg/
 *   ├── png/
 *   └── webp/
 *
 * Bytes are written exactly as received — never re-encoded — so the
 * EXIF metadata embedded by the app stays intact inside the file.
 */
class LocalStorageService extends StorageService {
  constructor(baseDir) {
    super();
    this.baseDir = path.resolve(baseDir);
  }

  async init() {
    for (const dir of ['jpeg', 'png', 'webp']) {
      await fsp.mkdir(path.join(this.baseDir, dir), { recursive: true });
    }
    return this;
  }

  _resolve(key) {
    const full = path.resolve(this.baseDir, key);
    // path traversal guard
    if (!full.startsWith(this.baseDir + path.sep)) throw new Error('Invalid storage key');
    return full;
  }

  async put(key, buffer) {
    const full = this._resolve(key);
    await fsp.mkdir(path.dirname(full), { recursive: true });
    const tmp = `${full}.part`;
    await fsp.writeFile(tmp, buffer, { flag: 'wx' });
    await fsp.rename(tmp, full);
    return { key, sizeBytes: buffer.length };
  }

  async getStream(key) {
    return fs.createReadStream(this._resolve(key));
  }

  async getBuffer(key) {
    return fsp.readFile(this._resolve(key));
  }

  async delete(key) {
    await fsp.rm(this._resolve(key), { force: true });
  }

  async exists(key) {
    try {
      await fsp.access(this._resolve(key));
      return true;
    } catch {
      return false;
    }
  }

  /** Relative path shown in db.json, e.g. "assets/jpeg/abc.jpg" */
  publicPath(key) {
    return path.posix.join('assets', key.split(path.sep).join('/'));
  }
}

module.exports = { LocalStorageService };
