import { createApp, lakebase, server } from '@databricks/appkit';
import { setupSampleLakebaseRoutes } from './routes/lakebase/todo-routes';
import { setupZeroBusRoutes } from './routes/zerobus/ingest-routes';
import { setupLoadTestRoutes } from './routes/testing/load-test-routes';
import { setLakebaseClient } from './services/load-test-history-service.js';
import { authService } from './services/auth-service.js';
import { setupRouteGuard } from './middleware/spn-route-guard.js';
import { setupAuthRoutes } from './routes/auth/auth-routes.js';

createApp({
  plugins: [
    server({ autoStart: false }),
    lakebase(),
  ],
})
  .then(async (appkit) => {
    // Wire Lakebase client into the load test history service
    setLakebaseClient(appkit.lakebase);

    // Initialize auth service — runs Lakebase migration (auth schema + tables).
    // Graceful degradation: if JWT_SIGNING_SECRET is not set, auth endpoints
    // return 503 but the rest of the app works normally.
    await authService.setup(appkit.lakebase);

    // ── Global middleware (runs before all route handlers) ─────────
    //
    // Route guard: identifies caller type (workspace-user / app-jwt-user /
    // ios-spn / proxy-unverified / anonymous) and enforces the access matrix.
    // Must be registered BEFORE route handlers so it gates all /api/* traffic.
    setupRouteGuard(appkit);

    // ── Route registrations ───────────────────────────────────────

    // Lakebase CRUD routes (sample scaffold)
    await setupSampleLakebaseRoutes(appkit);

    // Auth routes (Sign in with Apple, token refresh, revoke)
    // Includes per-endpoint rate limiters.
    await setupAuthRoutes(appkit);

    // ZeroBus HealthKit ingestion routes
    await setupZeroBusRoutes(appkit);

    // Synthetic data load testing routes
    await setupLoadTestRoutes(appkit);

    await appkit.server.start();
  })
  .catch(console.error);
