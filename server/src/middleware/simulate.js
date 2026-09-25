'use strict';

/**
 * Dev-only middleware for the app's "Network Tests" screen.
 * Enabled with SIMULATE=true. The client sends a header like:
 *
 *   X-Simulate: 400 | 401 | 413 | 500 | timeout | slow:2000
 *
 * "timeout" never responds (the client's own timeout must fire).
 * "slow:<ms>" delays the response by <ms> before continuing normally.
 */

const config = require('../config');

function simulateMiddleware(req, res, next) {
  if (!config.simulate) return next();
  const header = req.get('X-Simulate');
  if (!header) return next();

  const [kind, arg] = header.split(':');

  switch (kind) {
    case '400':
      return res.status(400).json({ success: false, error: { code: 'SIMULATED_BAD_REQUEST', message: 'Simulated 400 Bad Request' } });
    case '401':
      return res.status(401).json({ success: false, error: { code: 'SIMULATED_UNAUTHORIZED', message: 'Simulated 401 Unauthorized' } });
    case '413':
      return res.status(413).json({ success: false, error: { code: 'SIMULATED_PAYLOAD_TOO_LARGE', message: 'Simulated 413 Payload Too Large' } });
    case '500':
      return res.status(500).json({ success: false, error: { code: 'SIMULATED_SERVER_ERROR', message: 'Simulated 500 Internal Server Error' } });
    case 'timeout':
      return; // deliberately never respond
    case 'slow':
      return setTimeout(next, Number.parseInt(arg, 10) || 3000);
    default:
      return next();
  }
}

module.exports = { simulateMiddleware };
