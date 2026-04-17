/**
 * BronzeWriter — shapes the canonical wearables bronze row and delegates
 * the actual ZeroBus write to AppKit.zerobus (Tier-1 plugin).
 *
 * Every connector calls this, so the entire platform has a single
 * consistent landing format in wearables_zerobus. Silver pipelines
 * dispatch on headers:"X-Platform".
 */
import { randomUUID } from "node:crypto";

export interface WriteRequest {
  provider: string;           // e.g. 'garmin', 'apple_healthkit'
  userId: string;             // app_users.user_id UUID
  providerUserId?: string;    // vendor's user id (for webhook paths)
  deviceId: string;           // device identifier reported by the source
  recordType: string;         // e.g. 'daily_stats', 'sleep', 'samples'
  body: unknown;              // JSON-serializable payload (the vendor's raw response)
  extraHeaders?: Record<string, string>;
}

export interface BronzeRow {
  record_id: string;
  ingested_at: string;
  body: string;
  headers: string;
  record_type: string;
}

export interface ZerobusLike {
  writeRow: (tableFqn: string, row: BronzeRow) => Promise<void>;
  writeRows: (tableFqn: string, rows: BronzeRow[]) => Promise<void>;
}

export class BronzeWriter {
  constructor(
    private readonly zerobus: ZerobusLike,
    private readonly tableFqn: string,
  ) {}

  async write(req: WriteRequest): Promise<BronzeRow> {
    const row = this.shape(req);
    await this.zerobus.writeRow(this.tableFqn, row);
    return row;
  }

  async writeMany(reqs: WriteRequest[]): Promise<BronzeRow[]> {
    const rows = reqs.map((r) => this.shape(r));
    await this.zerobus.writeRows(this.tableFqn, rows);
    return rows;
  }

  private shape(req: WriteRequest): BronzeRow {
    const nowIso = new Date().toISOString();
    const wrappedBody = {
      source: req.provider,
      device_id: req.deviceId,
      user_id: req.userId,
      provider_user_id: req.providerUserId ?? null,
      data: req.body,
    };
    const headers = {
      "Content-Type": "application/json",
      "X-Platform": req.provider,
      "X-Record-Type": req.recordType,
      "X-Device-Id": req.deviceId,
      "X-User-Id": req.userId,
      "X-Upload-Timestamp": nowIso,
      ...(req.providerUserId
        ? { "X-Provider-User-Id": req.providerUserId }
        : {}),
      ...(req.extraHeaders ?? {}),
    };
    return {
      record_id: randomUUID(),
      ingested_at: nowIso,
      body: JSON.stringify(wrappedBody),
      headers: JSON.stringify(headers),
      record_type: req.recordType,
    };
  }
}
