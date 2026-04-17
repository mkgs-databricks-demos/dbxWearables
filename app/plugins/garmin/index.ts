import type { IAppRouter } from "@databricks/appkit";
import { Plugin, toPlugin, type PluginManifest } from "@databricks/appkit";

import { GarminConnector, GARMIN_RECORD_TYPES } from "./src/garminConnector";
import { mountOAuthRoutes } from "./src/routes/oauth";
import { mountWebhookRoute } from "./src/routes/webhook";

export interface GarminConfig {
  /**
   * When false (default), the plugin's manifest keeps its OAuth secrets
   * optional so deployments that don't use Garmin don't have to provision
   * them. Set true in `server/server.ts` only when Garmin is live.
   */
  enabled?: boolean;
  /**
   * Absolute URL Garmin will redirect the user back to after consent.
   * Typically `${APP_PUBLIC_URL}/api/garmin/oauth/callback`.
   */
  redirectUri?: string;
}

export class GarminPlugin extends Plugin<GarminConfig> {
  static manifest = {
    name: "garmin",
    displayName: "Garmin",
    description: "Garmin Connect + Garmin Health API wearable connector",
    resources: {
      required: [],
      optional: [
        {
          type: "secret",
          alias: "clientId",
          resourceKey: "clientId",
          permission: "READ",
          description: "Garmin OAuth 1.0a consumer key",
          fields: {
            scope: { env: "GARMIN_SECRET_SCOPE" },
            key: { env: "GARMIN_CLIENT_ID_KEY" },
          },
        },
        {
          type: "secret",
          alias: "clientSecret",
          resourceKey: "clientSecret",
          permission: "READ",
          description: "Garmin OAuth 1.0a consumer secret",
          fields: {
            scope: { env: "GARMIN_SECRET_SCOPE" },
            key: { env: "GARMIN_CLIENT_SECRET_KEY" },
          },
        },
        {
          type: "secret",
          alias: "webhookSecret",
          resourceKey: "webhookSecret",
          permission: "READ",
          description: "HMAC-SHA256 key for Garmin Health API webhook verification",
          fields: {
            scope: { env: "GARMIN_SECRET_SCOPE" },
            key: { env: "GARMIN_WEBHOOK_SECRET_KEY" },
          },
        },
      ],
    },
  } satisfies PluginManifest<"garmin">;

  /**
   * Promote the optional OAuth secrets to required when Garmin is enabled.
   */
  static getResourceRequirements(config: GarminConfig) {
    if (!config.enabled) return [];
    return [
      { alias: "clientId", required: true },
      { alias: "clientSecret", required: true },
      { alias: "webhookSecret", required: true },
    ];
  }

  private connector!: GarminConnector;

  async setup() {
    if (!this.config.enabled) {
      this.logger.info("garmin plugin disabled — skipping connector init");
      return;
    }

    const core = this.appkit.wearableCore;
    if (!core) {
      throw new Error(
        "garmin plugin requires wearable-core. Add wearableCore() before garmin() in createApp().",
      );
    }

    // Short-lived OAuth 1.0a request-token cache via the AppKit caching plugin.
    // Falls back to an in-memory Map when the caching plugin is absent.
    const cache = this.appkit.caching ?? new InMemoryTokenCache();

    const redirectUri =
      this.config.redirectUri ??
      `${process.env.APP_PUBLIC_URL ?? ""}/api/garmin/oauth/callback`;

    this.connector = new GarminConnector(
      {
        clientId: this.resources.clientId.value,
        clientSecret: this.resources.clientSecret.value,
        webhookSecret: this.resources.webhookSecret.value,
        redirectUri,
      },
      core.credentialStore,
      core.bronzeWriter,
      {
        put: async (token, payload, ttlSeconds) => {
          await cache.set(`garmin:oauth1a:${token}`, payload, ttlSeconds);
        },
        take: async (token) => {
          const key = `garmin:oauth1a:${token}`;
          const value = (await cache.get(key)) as
            | { tokenSecret: string; userId: string }
            | null;
          if (value) await cache.delete(key);
          return value;
        },
      },
    );

    core.connectorRegistry.register(this.connector);
    this.logger.info("garmin connector registered", {
      recordTypes: GARMIN_RECORD_TYPES.length,
    });
  }

  injectRoutes(router: IAppRouter) {
    if (!this.config.enabled || !this.connector) return;
    mountOAuthRoutes(router, this.connector);
    mountWebhookRoute(router, this.connector);
  }

  exports() {
    return { connector: this.connector };
  }
}

/** Minimal fallback used when AppKit's caching plugin isn't loaded. */
class InMemoryTokenCache {
  private readonly map = new Map<string, { value: unknown; expiresAt: number }>();
  async set(key: string, value: unknown, ttlSeconds: number): Promise<void> {
    this.map.set(key, { value, expiresAt: Date.now() + ttlSeconds * 1000 });
  }
  async get(key: string): Promise<unknown> {
    const entry = this.map.get(key);
    if (!entry) return null;
    if (entry.expiresAt < Date.now()) {
      this.map.delete(key);
      return null;
    }
    return entry.value;
  }
  async delete(key: string): Promise<void> {
    this.map.delete(key);
  }
}

export const garmin = toPlugin(GarminPlugin);
