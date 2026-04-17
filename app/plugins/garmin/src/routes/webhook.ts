import type { Request, Response, Router } from "express";
import type { GarminConnector } from "../garminConnector";

export function mountWebhookRoute(router: Router, connector: GarminConnector): void {
  router.post("/webhook/:recordType", async (req: Request, res: Response) => {
    const verified = await connector.verifyWebhook?.(req);
    if (!verified) {
      res.status(401).json({ error: "invalid_signature" });
      return;
    }
    try {
      const rows = (await connector.handleWebhook?.(req)) ?? [];
      res.status(202).json({
        accepted: rows.length,
        record_ids: rows.map((r) => r.record_id),
      });
    } catch (err) {
      res.status(500).json({
        error: "webhook_failed",
        message: (err as Error).message,
      });
    }
  });
}
