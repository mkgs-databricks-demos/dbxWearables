import { createApp, lakebase, server } from '@databricks/appkit';
import { setupSampleLakebaseRoutes } from './routes/lakebase/todo-routes';
import { setupZeroBusRoutes } from './routes/zerobus/ingest-routes';
import { setupLoadTestRoutes } from './routes/testing/load-test-routes';
import { setLakebaseClient } from './services/load-test-history-service.js';

createApp({
  plugins: [
    server({ autoStart: false }),
    lakebase(),
  ],
})
  .then(async (appkit) => {
    // Wire Lakebase client into the load test history service
    setLakebaseClient(appkit.lakebase);

    // Lakebase CRUD routes (sample scaffold)
    await setupSampleLakebaseRoutes(appkit);

    // ZeroBus HealthKit ingestion routes
    await setupZeroBusRoutes(appkit);

    // Synthetic data load testing routes
    await setupLoadTestRoutes(appkit);

    await appkit.server.start();
  })
  .catch(console.error);
