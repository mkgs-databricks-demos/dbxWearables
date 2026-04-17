/**
 * Garmin Connect + Garmin Health API connector.
 *
 * OAuth 1.0a (Garmin has not moved to OAuth 2.0 for the Health API as of
 * early 2026). Subclass BaseOAuth1aConnector; override userinfo lookup
 * and webhook handling.
 */
import { createHmac, timingSafeEqual } from "node:crypto";
import type { Request } from "express";
import type {
  BronzeRow,
  DateRange,
} from "../../wearable-core/src/connector";
import type { BronzeWriter } from "../../wearable-core/src/bronzeWriter";
import type { CredentialStore } from "../../wearable-core/src/credentialStore";
import {
  BaseOAuth1aConnector,
  type OAuth1aConfig,
  type OAuth1aRequestTokenCache,
} from "../../wearable-core/src/baseOAuth1aConnector";

export interface GarminConnectorOptions {
  clientId: string;
  clientSecret: string;
  webhookSecret: string;
  redirectUri: string;
}

/** Record types this connector produces via any path. */
export const GARMIN_RECORD_TYPES = [
  "daily_stats",
  "heart_rates",
  "sleep",
  "stress",
  "hrv",
  "spo2",
  "body_battery",
  "steps",
  "respiration",
  "activities",
  // Connect IQ watch widget — ingested via /api/wearable-core/ingest/garmin_connect_iq
  "samples",
] as const;

const GARMIN_OAUTH_CONFIG = (opts: GarminConnectorOptions): OAuth1aConfig => ({
  provider: "garmin",
  displayName: "Garmin",
  iconUrl: "/icons/garmin.svg",
  requestTokenUrl: "https://connectapi.garmin.com/oauth-service/oauth/request_token",
  authorizeUrl: "https://connect.garmin.com/oauthConfirm",
  accessTokenUrl: "https://connectapi.garmin.com/oauth-service/oauth/access_token",
  consumerKey: opts.clientId,
  consumerSecret: opts.clientSecret,
  redirectUri: opts.redirectUri,
});

export class GarminConnector extends BaseOAuth1aConnector {
  private readonly webhookSecret: string;

  constructor(
    options: GarminConnectorOptions,
    credentialStore: CredentialStore,
    bronzeWriter: BronzeWriter,
    requestTokenCache: OAuth1aRequestTokenCache,
  ) {
    super(
      GARMIN_OAUTH_CONFIG(options),
      credentialStore,
      bronzeWriter,
      requestTokenCache,
    );
    this.webhookSecret = options.webhookSecret;
  }

  recordTypes(): string[] {
    return [...GARMIN_RECORD_TYPES];
  }

  protected async resolveProviderUserId(
    oauthToken: string,
    oauthTokenSecret: string,
  ): Promise<string> {
    const body = await this.signedFetch(
      "GET",
      "https://apis.garmin.com/wellness-api/rest/user/id",
      oauthTokenSecret,
      { oauth_token: oauthToken },
    );
    const parsed = JSON.parse(body) as { userId?: string; userID?: string };
    const id = parsed.userId ?? parsed.userID;
    if (!id) {
      throw new Error(`Garmin user/id response missing userId: ${body}`);
    }
    return id;
  }

  // -----------------------------------------------------------------
  // Webhook: Garmin Health API PING → PULL
  // -----------------------------------------------------------------

  async verifyWebhook(req: Request): Promise<boolean> {
    const signatureHeader = req.header("x-garmin-signature") ?? "";
    if (!signatureHeader || !this.webhookSecret) return false;
    const raw =
      typeof req.body === "string"
        ? req.body
        : Buffer.isBuffer(req.body)
          ? req.body.toString("utf8")
          : JSON.stringify(req.body ?? {});
    const expected = createHmac("sha256", this.webhookSecret)
      .update(raw)
      .digest("hex");
    const a = Buffer.from(signatureHeader);
    const b = Buffer.from(expected);
    return a.length === b.length && timingSafeEqual(a, b);
  }

  async handleWebhook(req: Request): Promise<BronzeRow[]> {
    const recordType = req.params.recordType;
    const payload = normalizeWebhookBody(req.body);

    // Garmin's webhook shape: an object containing an array of "summary"
    // objects keyed by record type (e.g. { dailies: [...] }, { sleeps: [...] }).
    // Each summary carries a userId (provider_user_id) we resolve to app_users.
    const summaries = pickSummaries(payload);
    const rows: BronzeRow[] = [];

    for (const summary of summaries) {
      const providerUserId = (summary.userId ?? summary.userID) as
        | string
        | undefined;
      if (!providerUserId) continue;

      // Resolve app user_id via credential store. `listEnrolled` returns
      // everyone enrolled for this provider; look up by provider_user_id.
      const enrolled = await this.credentialStore.listEnrolled(this.provider);
      const match = enrolled.find((e) => e.providerUserId === providerUserId);
      if (!match) {
        // Unknown provider_user_id — log and skip rather than 500.
        continue;
      }

      const row = await this.bronzeWriter.write({
        provider: "garmin",
        userId: match.userId,
        providerUserId,
        deviceId: (summary.deviceId as string) ?? "garmin_unknown",
        recordType,
        body: summary,
        extraHeaders: { "X-Source-Path": "health_api_webhook" },
      });
      rows.push(row);
    }

    return rows;
  }

  /**
   * Pull path lives in Python (providers/garmin/pull/) because it uses
   * the python-garminconnect library and runs in a Lakeflow notebook.
   * The TS side deliberately does NOT implement pullBatch to avoid
   * duplicating the Garmin API surface.
   */
  async pullBatch(_userId: string, _range: DateRange): Promise<BronzeRow[]> {
    throw new Error(
      "Garmin pullBatch runs in Python via providers/garmin/pull/. " +
        "The TS connector only handles OAuth + webhooks.",
    );
  }
}

function normalizeWebhookBody(body: unknown): Record<string, unknown> {
  if (typeof body === "string") return JSON.parse(body) as Record<string, unknown>;
  if (Buffer.isBuffer(body))
    return JSON.parse(body.toString("utf8")) as Record<string, unknown>;
  return (body ?? {}) as Record<string, unknown>;
}

function pickSummaries(payload: Record<string, unknown>): Array<Record<string, unknown>> {
  // Garmin uses plural keys per record type: dailies, sleeps, stressDetails, ...
  // Take the first array-valued key; the route param already tells us the type.
  for (const value of Object.values(payload)) {
    if (Array.isArray(value)) {
      return value as Array<Record<string, unknown>>;
    }
  }
  // Singleton payload (no wrapping array)
  return [payload];
}
