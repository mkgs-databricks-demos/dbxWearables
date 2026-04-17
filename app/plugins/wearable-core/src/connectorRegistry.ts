import type { WearableConnector } from "./connector";

/**
 * Thin in-memory registry populated by each provider plugin during setup().
 *
 * The Connections UI reads from here (via /api/wearable-core/connections)
 * to render the list of available providers. Order is insertion order.
 */
export class ConnectorRegistry {
  private readonly byProvider = new Map<string, WearableConnector>();

  register(connector: WearableConnector): void {
    if (this.byProvider.has(connector.provider)) {
      throw new Error(
        `Connector for provider '${connector.provider}' already registered. ` +
          `Check your plugin list in server/server.ts for duplicates.`,
      );
    }
    this.byProvider.set(connector.provider, connector);
  }

  get(provider: string): WearableConnector | undefined {
    return this.byProvider.get(provider);
  }

  has(provider: string): boolean {
    return this.byProvider.has(provider);
  }

  all(): WearableConnector[] {
    return [...this.byProvider.values()];
  }
}
