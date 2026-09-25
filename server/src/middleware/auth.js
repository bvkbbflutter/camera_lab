'use strict';

const config = require('../config');

/** Optional bearer-token check. No-op unless API_TOKEN is set in the environment. */
function authMiddleware(req, res, next) {
  if (!config.apiToken) return next();
  const header = req.get('Authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (token !== config.apiToken) {
    return res.status(401).json({
      success: false,
      error: { code: 'UNAUTHORIZED', message: 'Missing or invalid bearer token' },
    });
  }
  next();
}

module.exports = { authMiddleware };
