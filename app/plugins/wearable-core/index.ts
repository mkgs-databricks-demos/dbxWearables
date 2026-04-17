import * as path from "node:path";
import type { IAppRouter } from "@databricks/appkit";
import { Plugin, toPlugin, type PluginManifest } from "@databricks/appkit";

import { BronzeWriter } from "./src/bronzeWriter";
import { ConnectorRegistry } from "./src/connectorRegistry";
import {
  LakebaseCredentialStore,
  type CredentialStore,
} from "./src/credentialStore";
import { runMigrations } from "./src/runMigrations";
import { mountIngestRoute } from "./src/routes/ingest";
import { mountConnectionsRoutes } from "./src/routes/connections";

export { BaseOAuth2Connector } from "./src/baseOAuth2Connector";
export { BaseOAuth1aConnector } from "./src/baseOAuth1aConnector";
export type {
  WearableConnector,
  BronzeRow,
  Credentials,
  OAuthCallbackParams,
  OAuthStartResult,
} from "./src/connector";
export type { CredentialStore, EnrolledUser } from "./src/credentialStore";

export interface WearableCoreConfig {
  /** Optional override for the bronze table FQN. Defaults to WEARABLES_BRONZE_TABLE env var. */
  bronzeTable?: string;
  /** Optional override for the migrations namespace. Defaults to "wearable-core". */
  migrationsNamespace?: string;
}

export class WearableCorePlugin extends Plugin<WearableCoreConfig> {
  static manifest = {
    name: "wearableCore",
    displayName: "Wearable Core",
    description:
      "Platform plugin: Lakebase schema, credential store, bronze row shape, OAuth base classes, connector registry",
    resources: {
      required: [
        {
          type: "secret",
          alias: "signingKey",
          resourceKey: "signingKey",
          permission: "READ",
          description:
            "32-byte AES-256 signing key for envelope-encrypting OAuth tokens",
          fields: {
            scope: { env: "WEARABLE_CORE_SECRET_SCOPE" },
            key: { env: "WEARABLE_CORE_SIGNING_KEY" },
          },
        },
        {
          type: "secret",
          alias: "bronzeTable",
          resourceKey: "bronzeTable",
          permission: "READ",
          description: "Fully-qualified name of the wearables_zerobus bronze table",
          fields: {
            scope: { env: "WEARABLES_BRONZE_TABLE_SCOPE" },
            key: { env: "WEARABLES_BRONZE_TABLE_KEY" },
          },
        },
      ],
      optional: [],
    },
  } satisfies PluginManifest<"wearableCore">;

  credentialStore!: CredentialStore;
  bronzeWriter!: BronzeWriter;
  connectorRegistry = new ConnectorRegistry();

  async setup() {
    const lakebase = this.appkit.lakebase;
    const zerobus = this.appkit.zerobus;

    if (!lakebase) {
      throw new Error(
        "wearable-core requires the lakebase plugin. Add lakebase() before wearableCore() in createApp().",
      );
    }
    if (!zerobus) {
      throw new Error(
        "wearable-core requires the zerobus plugin. Add zerobus() before wearableCore() in createApp().",
      );
    }

    // 1. Apply platform migrations.
    const namespace = this.config.migrationsNamespace ?? "wearable-core";
    const { applied, skipped } = await runMigrations(
      lakebase,
      namespace,
      path.join(__dirname, "migrations"),
      this.logger,
    );
    this.logger.info("wearable-core migrations complete", {
      applied,
      skipped: skipped.length,
    });

    // 2. Credential store (envelope-encrypted via signingKey).
    const signingKeyHex = (this.resources.signingKey.value ?? "").trim();
    const signingKey = Buffer.from(signingKeyHex, "hex");
    this.credentialStore = new LakebaseCredentialStore(lakebase, signingKey);

    // 3. Bronze writer — shapes rows, delegates to zerobus.writeRow.
    const bronzeTableFqn =
      this.config.bronzeTable ??
      this.resources.bronzeTable.value ??
      process.env.WEARABLES_BRONZE_TABLE ??
      "";
    if (!bronzeTableFqn) {
      throw new Error(
        "wearable-core: bronze table FQN not configured. Set WEARABLES_BRONZE_TABLE.",
      );
    }
    this.bronzeWriter = new BronzeWriter(zerobus, bronzeTableFqn);

    this.logger.info("wearable-core ready", { bronzeTableFqn });
  }

  injectRoutes(router: IAppRouter) {
    mountIngestRoute(router, this.bronzeWriter);
    mountConnectionsRoutes(router, this.connectorRegistry, this.credentialStore);
  }

  /**
   * Public migrations helper so other plugins can own their own tables
   * without editing wearable-core.
   */
  async runMigrations(namespace: string, migrationsDir: string) {
    return runMigrations(
      this.appkit.lakebase,
      namespace,
      migrationsDir,
      this.logger,
    );
  }

  exports() {
    return {
      credentialStore: this.credentialStore,
      bronzeWriter: this.bronzeWriter,
      connectorRegistry: this.connectorRegistry,
      runMigrations: this.runMigrations.bind(this),
    };
  }
}

export const wearableCore = toPlugin(WearableCorePlugin);
