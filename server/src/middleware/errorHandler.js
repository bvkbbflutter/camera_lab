'use strict';

const multer = require('multer');

/** Central error handler. Never echoes stack traces or raw bytes to the client. */
function errorHandler(err, req, res, _next) {
  if (res.headersSent) return;

  if (err instanceof multer.MulterError) {
    const status = err.code === 'LIMIT_FILE_SIZE' ? 413 : 400;
    return res.status(status).json({
      success: false,
      error: { code: `MULTER_${err.code}`, message: err.message },
    });
  }

  if (err && err.type === 'entity.too.large') {
    return res.status(413).json({
      success: false,
      error: { code: 'PAYLOAD_TOO_LARGE', message: 'Request body exceeds the configured size limit' },
    });
  }

  if (err && err.type === 'entity.parse.failed') {
    return res.status(400).json({
      success: false,
      error: { code: 'INVALID_JSON', message: 'Request body is not valid JSON' },
    });
  }

  const status = err && err.status ? err.status : 500;
  const code = err && err.code ? err.code : 'INTERNAL_ERROR';
  // eslint-disable-next-line no-console
  console.error(`[error] ${req.method} ${req.originalUrl} ->`, status, code, err && err.message);

  res.status(status).json({
    success: false,
    error: { code, message: status >= 500 ? 'Internal server error' : (err.message || 'Request failed') },
  });
}

module.exports = { errorHandler };
