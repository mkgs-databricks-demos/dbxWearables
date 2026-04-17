import { Plugin, toPlugin, type PluginManifest } from "@databricks/appkit";
import { StreamPool, type ZerobusRow } from "./src/streamPool";

export interface ZerobusConfig {
  maxInflightRequests?: number;
  maxStreams?: number;
  retry?: { maxAttempts?: number; baseDelayMs?: number };
}

/**
 * Generic AppKit plugin wrapping databricks-zerobus-ingest-sdk.
 *
 * Row-shape-agnostic. Callers supply arbitrary JSON-compatible rows; the
 * bronze row shape is layered on top by the `wearable-core` plugin.
 */
export class ZerobusPlugin extends Plugin<ZerobusConfig> {
  static manifest = {
    name: "zerobus",
    displayName: "ZeroBus",
    description: "Databricks ZeroBus SDK writer with stream reuse and OTel metrics",
    resources: {
      required: [
        {
          type: "secret",
          alias: "clientId",
          resourceKey: "clientId",
          permission: "READ",
          description: "ZeroBus OAuth M2M client_id",
          fields: {
            scope: { env: "ZEROBUS_SECRET_SCOPE", description: "Secret scope (default: dbxw_zerobus_credentials)" },
            key: { env: "ZEROBUS_CLIENT_ID_KEY", description: "Secret key (default: client_id)" },
          },
        },
        {
          type: "secret",
          alias: "clientSecret",
          resourceKey: "clientSecret",
          permission: "READ",
          description: "ZeroBus OAuth M2M client_secret",
          fields: {
            scope: { env: "ZEROBUS_SECRET_SCOPE" },
            key: { env: "ZEROBUS_CLIENT_SECRET_KEY", description: "Default: client_secret" },
          },
        },
        {
          type: "secret",
          alias: "workspaceUrl",
          resourceKey: "workspaceUrl",
          permission: "READ",
          description: "Databricks workspace URL",
          fields: {
            scope: { env: "ZEROBUS_SECRET_SCOPE" },
            key: { env: "ZEROBUS_WORKSPACE_URL_KEY", description: "Default: workspace_url" },
          },
        },
        {
          type: "secret",
          alias: "endpoint",
          resourceKey: "endpoint",
          permission: "READ",
          description: "Region-specific ZeroBus ingest endpoint",
          fields: {
            scope: { env: "ZEROBUS_SECRET_SCOPE" },
            key: { env: "ZEROBUS_ENDPOINT_KEY", description: "Default: zerobus_endpoint" },
          },
        },
      ],
      optional: [],
    },
  } satisfies PluginManifest<"zerobus">;

  private pool!: StreamPool;

  async setup() {
    const { clientId, clientSecret, workspaceUrl, endpoint } = this.resources;
    this.pool = new StreamPool({
      clientId: clientId.value,
      clientSecret: clientSecret.value,
      workspaceUrl: workspaceUrl.value,
      endpoint: endpoint.value,
      maxInflightRequests: this.config.maxInflightRequests ?? 50,
      maxStreams: this.config.maxStreams ?? 8,
      retry: {
        maxAttempts: this.config.retry?.maxAttempts ?? 3,
        baseDelayMs: this.config.retry?.baseDelayMs ?? 400,
      },
      telemetry: this.telemetry,
      logger: this.logger,
    });
    this.logger.info("zerobus plugin ready");
  }

  async writeRow(tableFqn: string, row: ZerobusRow): Promise<void> {
    await this.pool.writeRow(tableFqn, row);
  }

  async writeRows(tableFqn: string, rows: ZerobusRow[]): Promise<void> {
    await this.pool.writeRows(tableFqn, rows);
  }

  async flush(tableFqn?: string): Promise<void> {
    await this.pool.flush(tableFqn);
  }

  async shutdown() {
    await this.pool?.close();
  }

  exports() {
    return {
      writeRow: this.writeRow.bind(this),
      writeRows: this.writeRows.bind(this),
      flush: this.flush.bind(this),
    };
  }
}

export const zerobus = toPlugin(ZerobusPlugin);
