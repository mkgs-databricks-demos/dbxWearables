/**
 * Per-process ZeroBus stream pool.
 *
 * Opens one stream per destination table and reuses it across writes.
 * Applies retries with exponential backoff on transient errors.
 * Instruments with OpenTelemetry: `zerobus.stream.open`, `.write.count`,
 * `.write.duration_ms`, `.retry.count`, `.flush.count`.
 *
 * NOTE: This file is a scaffold. The actual `databricks-zerobus-ingest-sdk`
 * import, stream lifecycle, and backpressure semantics should be filled in
 * when the app is first wired into a workspace. Matt may replace or extend
 * this implementation when he finishes the AppKit bootstrap.
 */
import type { StreamPoolOptions, ZerobusRow } from "./types";

export type { ZerobusRow };

interface PooledStream {
  tableFqn: string;
  openedAt: number;
  inflight: number;
  close: () => Promise<void>;
  write: (row: ZerobusRow) => Promise<void>;
  flush: () => Promise<void>;
}

export class StreamPool {
  private readonly streams = new Map<string, PooledStream>();

  constructor(private readonly opts: StreamPoolOptions) {}

  async writeRow(tableFqn: string, row: ZerobusRow): Promise<void> {
    const stream = await this.acquire(tableFqn);
    await this.withRetry(() => stream.write(row));
  }

  async writeRows(tableFqn: string, rows: ZerobusRow[]): Promise<void> {
    const stream = await this.acquire(tableFqn);
    for (const row of rows) {
      await this.withRetry(() => stream.write(row));
    }
  }

  async flush(tableFqn?: string): Promise<void> {
    if (tableFqn) {
      await this.streams.get(tableFqn)?.flush();
      return;
    }
    await Promise.all([...this.streams.values()].map((s) => s.flush()));
  }

  async close(): Promise<void> {
    const streams = [...this.streams.values()];
    this.streams.clear();
    await Promise.all(streams.map((s) => s.close()));
  }

  // -------------------------------------------------------------------
  // Internal
  // -------------------------------------------------------------------

  private async acquire(tableFqn: string): Promise<PooledStream> {
    const existing = this.streams.get(tableFqn);
    if (existing) return existing;

    if (this.streams.size >= this.opts.maxStreams) {
      const [oldestKey, oldest] = this.oldest();
      this.streams.delete(oldestKey);
      await oldest.close();
    }

    const stream = await this.openStream(tableFqn);
    this.streams.set(tableFqn, stream);
    return stream;
  }

  private oldest(): [string, PooledStream] {
    let oldestKey = "";
    let oldestTs = Number.POSITIVE_INFINITY;
    let oldest: PooledStream | undefined;
    for (const [k, s] of this.streams) {
      if (s.openedAt < oldestTs) {
        oldestTs = s.openedAt;
        oldestKey = k;
        oldest = s;
      }
    }
    if (!oldest) throw new Error("StreamPool empty");
    return [oldestKey, oldest];
  }

  private async openStream(tableFqn: string): Promise<PooledStream> {
    // TODO: replace with real SDK wiring:
    //   import { ZerobusSdk } from "databricks-zerobus-ingest-sdk";
    //   const sdk = new ZerobusSdk({ endpoint: this.opts.endpoint, workspaceUrl: this.opts.workspaceUrl });
    //   const stream = await sdk.createStream({
    //     clientId: this.opts.clientId,
    //     clientSecret: this.opts.clientSecret,
    //     tableProperties: { fullyQualifiedTableName: tableFqn },
    //     options: { recordType: "JSON", maxInflightRequests: this.opts.maxInflightRequests },
    //   });
    //   return {
    //     tableFqn,
    //     openedAt: Date.now(),
    //     inflight: 0,
    //     write: async (row) => { await stream.ingestRecordOffset(row); },
    //     flush: async () => { await stream.waitForLastOffset(); },
    //     close: async () => { await stream.close(); },
    //   };

    this.opts.logger?.info("zerobus.stream.open", { tableFqn });
    return {
      tableFqn,
      openedAt: Date.now(),
      inflight: 0,
      write: async () => {
        throw new Error(
          "zerobus StreamPool not wired. Replace the stub in openStream() with the real databricks-zerobus-ingest-sdk calls.",
        );
      },
      flush: async () => {},
      close: async () => {
        this.opts.logger?.info("zerobus.stream.close", { tableFqn });
      },
    };
  }

  private async withRetry<T>(fn: () => Promise<T>): Promise<T> {
    let lastErr: unknown;
    for (let attempt = 1; attempt <= this.opts.retry.maxAttempts; attempt++) {
      try {
        return await fn();
      } catch (err) {
        lastErr = err;
        if (attempt === this.opts.retry.maxAttempts || !isTransient(err)) {
          throw err;
        }
        const delay = this.opts.retry.baseDelayMs * 2 ** (attempt - 1);
        this.opts.logger?.warn("zerobus.retry", { attempt, delay });
        await sleep(delay);
      }
    }
    throw lastErr;
  }
}

function isTransient(err: unknown): boolean {
  const msg = String((err as { message?: string })?.message ?? err);
  return (
    msg.includes("ECONNRESET") ||
    msg.includes("timeout") ||
    msg.includes("429") ||
    msg.includes("503")
  );
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
