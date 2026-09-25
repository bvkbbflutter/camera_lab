'use strict';

const express = require('express');
const { requestLogger } = require('./middleware/requestLogger');
const { simulateMiddleware } = require('./middleware/simulate');
const { authMiddleware } = require('./middleware/auth');
const { errorHandler } = require('./middleware/errorHandler');
const { healthRouter } = require('./routes/health');
const { imagesRouter } = require('./routes/images');

/** @param {{ storage, db }} deps */
function createApp(deps) {
  const app = express();
  app.disable('x-powered-by');

  app.use(requestLogger);
  app.use(simulateMiddleware);

  app.use('/api', healthRouter());
  app.use('/api', authMiddleware, imagesRouter(deps));

  app.use((req, res) => {
    res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: `No route for ${req.method} ${req.path}` } });
  });

  app.use(errorHandler);
  return app;
}

module.exports = { createApp };
