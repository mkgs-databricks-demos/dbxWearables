import { createApp, lakebase, server } from '@databricks/appkit';
import { setupSampleLakebaseRoutes } from './routes/lakebase/todo-routes';
import { setupZeroBusRoutes } from './routes/zerobus/ingest-routes';

createApp({
  plugins: [
    server({ autoStart: false }),
    lakebase(),
  ],
})
  .then(async (appkit) => {
    // Lakebase CRUD routes (sample scaffold)
    await setupSampleLakebaseRoutes(appkit);

    // ZeroBus HealthKit ingestion routes
    await setupZeroBusRoutes(appkit);

    await appkit.server.start();
  })
  .catch(console.error);
