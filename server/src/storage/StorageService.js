'use strict';

/**
 * Storage abstraction. The POC uses LocalStorageService (assets/ folder).
 * Production implementations can target S3, Azure Blob, GCS, Firebase Storage
 * or Cloudinary by implementing the same four methods.
 *
 * Keys look like "jpeg/3f2c...e1.jpg" — format folder + id + extension.
 */
class StorageService {
  /** @returns {Promise<{key:string, sizeBytes:number}>} */
  async put(_key, _buffer, _mimeType) { throw new Error('not implemented'); }

  /** @returns {Promise<import('stream').Readable>} */
  async getStream(_key) { throw new Error('not implemented'); }

  /** @returns {Promise<Buffer>} */
  async getBuffer(_key) { throw new Error('not implemented'); }

  async delete(_key) { throw new Error('not implemented'); }

  async exists(_key) { throw new Error('not implemented'); }
}

module.exports = { StorageService };
