import type { Request, Response, Router } from "express";
import type { GarminConnector } from "../garminConnector";

export function mountOAuthRoutes(router: Router, connector: GarminConnector): void {
  router.get("/oauth/start", async (req: Request, res: Response) => {
    const userId = req.query.user_id as string | undefined;
    if (!userId) {
      res.status(400).json({ error: "missing_user_id" });
      return;
    }
    try {
      const { redirectUrl } = await connector.oauthStart(userId);
      res.redirect(302, redirectUrl);
    } catch (err) {
      res.status(500).json({
        error: "oauth_start_failed",
        message: (err as Error).message,
      });
    }
  });

  router.get("/oauth/callback", async (req: Request, res: Response) => {
    const { oauth_token, oauth_verifier, user_id } = req.query as {
      oauth_token?: string;
      oauth_verifier?: string;
      user_id?: string;
    };
    if (!oauth_token || !oauth_verifier || !user_id) {
      res.status(400).json({
        error: "missing_callback_params",
        required: ["oauth_token", "oauth_verifier", "user_id"],
      });
      return;
    }
    try {
      await connector.oauthCallback({
        code: "",
        state: oauth_token,
        userId: user_id,
        oauth_verifier,
      });
      res.redirect(302, "/connections?linked=garmin");
    } catch (err) {
      res.status(500).json({
        error: "oauth_callback_failed",
        message: (err as Error).message,
      });
    }
  });

  router.post("/revoke", async (req: Request, res: Response) => {
    const userId = (req.body?.user_id ?? req.query.user_id) as string | undefined;
    if (!userId) {
      res.status(400).json({ error: "missing_user_id" });
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
  });
}
