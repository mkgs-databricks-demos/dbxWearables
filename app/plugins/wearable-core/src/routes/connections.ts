/**
 * GET /api/wearable-core/connections
 *
 * Returns every registered WearableConnector (provider + displayName +
 * iconUrl + capabilities) plus the current user's enrollment state from
 * wearable_credentials. The React Connections UI consumes this.
 *
 * POST /api/wearable-core/connections/:provider/revoke
 *
 * Revokes a user's credential for a given provider. The corresponding
 * provider plugin may additionally call the vendor's revoke endpoint.
 */
import type { Request, Response, Router } from "express";
import type { ConnectorRegistry } from "../connectorRegistry";
import type { CredentialStore } from "../credentialStore";

export function mountConnectionsRoutes(
  router: Router,
  registry: ConnectorRegistry,
  credentialStore: CredentialStore,
): void {
  router.get("/connections", async (req: Request, res: Response) => {
    const userId = extractUserId(req);
    const enrolled = userId
      ? new Map(
          (await credentialStore.listEnrolled())
            .filter((e) => e.userId === userId)
            .map((e) => [e.provider, e]),
        )
      : new Map();

    const connectors = registry.all().map((c) => ({
      provider: c.provider,
      displayName: c.displayName,
      iconUrl: c.iconUrl,
      supportsWebhook: c.supportsWebhook,
      supportsPoll: c.supportsPoll,
      recordTypes: c.recordTypes(),
      enrolled: enrolled.has(c.provider),
      providerUserId: enrolled.get(c.provider)?.providerUserId ?? null,
    }));

    res.json({ userId, connectors });
  });

  router.post(
    "/connections/:provider/revoke",
    async (req: Request, res: Response) => {
      const userId = extractUserId(req);
      if (!userId) {
        res.status(401).json({ error: "unauthorized" });
        return;
      }
      const connector = registry.get(req.params.provider);
      if (!connector) {
        res.status(404).json({ error: "provider_not_registered" });
        return;
      }
      try {
        await connector.revoke(userId);
        res.status(204).end();
      } catch (err) {
        res.status(500).json({
          error: "revoke_failed",
          message: (err as Error).message,
        });
      }
    },
  );
}

/**
 * Extract the app user ID from the request. In Databricks Apps the SPN
 * auth headers can be used; for demo, an X-User-Id header is sufficient.
 * Override this in production with whatever session / SSO middleware
 * the deployer configures.
 */
function extractUserId(req: Request): string | null {
  return req.header("x-user-id") ?? null;
}
