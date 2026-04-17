/**
 * POST /api/wearable-core/ingest/:platform
 *
 * Generic phone-SDK ingest endpoint. HealthKit (iOS), Health Connect
 * (Android), Samsung Health (Samsung), and the Garmin Connect IQ watch
 * widget all POST here.
 *
 * Body is NDJSON — one record per line. Request headers carry the
 * X-Record-Type, X-Platform, X-Device-Id, X-User-Id, X-Upload-Timestamp
 * contract defined in the bronzeWriter shape.
 */
import type { Request, Response, Router } from "express";
import type { BronzeWriter } from "../bronzeWriter";

export function mountIngestRoute(
  router: Router,
  bronzeWriter: BronzeWriter,
): void {
  router.post("/ingest/:platform", async (req: Request, res: Response) => {
    const platform = req.params.platform;
    const recordType = getRequiredHeader(req, "x-record-type");
    const deviceId = getRequiredHeader(req, "x-device-id");
    const userId = req.header("x-user-id") ?? "";
    const providerUserId = req.header("x-provider-user-id") ?? undefined;

    if (!recordType || !deviceId) {
      res.status(400).json({
        error: "missing_required_headers",
        required: ["X-Record-Type", "X-Device-Id"],
      });
      return;
    }

    const raw =
      typeof req.body === "string"
        ? req.body
        : Buffer.isBuffer(req.body)
          ? req.body.toString("utf8")
          : JSON.stringify(req.body ?? {});

    const lines = raw
      .split(/\r?\n/)
      .map((s) => s.trim())
      .filter(Boolean);

    if (lines.length === 0) {
      res.status(400).json({ error: "empty_body" });
      return;
    }

    try {
      const records = lines.map((line) => JSON.parse(line) as unknown);
      const rows = await bronzeWriter.writeMany(
        records.map((body) => ({
          provider: platform,
          userId,
          providerUserId,
          deviceId,
          recordType,
          body,
        })),
      );
      res.status(202).json({
        accepted: rows.length,
        record_ids: rows.map((r) => r.record_id),
      });
    } catch (err) {
      res.status(500).json({
        error: "ingest_failed",
        message: (err as Error).message,
      });
    }
  });
}

function getRequiredHeader(req: Request, name: string): string | null {
  const v = req.header(name);
  return typeof v === "string" && v.length > 0 ? v : null;
}
