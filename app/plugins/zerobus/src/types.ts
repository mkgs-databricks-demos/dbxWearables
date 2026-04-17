/**
 * Minimal shape the ZeroBus plugin writes.
 *
 * The plugin is row-shape-agnostic — any JSON-serializable record is
 * accepted. Callers are responsible for matching the target table's
 * column contract; the plugin only manages streams, retries, and OTel.
 */
export interface ZerobusRow {
  [key: string]: unknown;
}

export interface RetryPolicy {
  maxAttempts: number;
  baseDelayMs: number;
}

export interface StreamPoolOptions {
  clientId: string;
  clientSecret: string;
  workspaceUrl: string;
  endpoint: string;
  maxInflightRequests: number;
  maxStreams: number;
  retry: RetryPolicy;
  telemetry?: unknown;
  logger?: { info: (msg: string, meta?: object) => void; warn: (msg: string, meta?: object) => void; error: (msg: string, meta?: object) => void };
}
