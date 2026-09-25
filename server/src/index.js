'use strict';

const config = require('./config');
const { createApp } = require('./app');
const { JsonDb } = require('./db/jsonDb');
const { LocalStorageService } = require('./storage/LocalStorageService');

async function main() {
  const storage = await new LocalStorageService(config.assetsDir).init();
  const db = await new JsonDb(config.dbFile).init();

  const app = createApp({ storage, db });

  app.listen(config.port, config.host, () => {
    const shown = config.host === '0.0.0.0' ? 'localhost' : config.host;
    console.log('');
    console.log('  Camera Lab API server');
    console.log('  ----------------------------------------');
    console.log(`  Local:     http://${shown}:${config.port}/api/health`);
    console.log(`  Network:   http://<your-machine-ip>:${config.port}/api/health   (for phones/emulators)`);
    console.log(`  Assets:    ${config.assetsDir}`);
    console.log(`  Database:  ${config.dbFile}`);
    if (config.apiToken) console.log('  Auth:      Bearer token required');
    if (config.simulate) console.log('  Simulate:  ON (X-Simulate header enabled)');
    console.log('');
  });
}

main().catch((err) => {
  console.error('Fatal startup error:', err);
  process.exit(1);
});
