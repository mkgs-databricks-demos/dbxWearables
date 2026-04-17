/**
 * The WearableConnector contract — every provider plugin extends a
 * base class and is discovered at startup via the connectorRegistry.
 *
 * This file is the single source of truth for the TypeScript side of
 * the contract. The Python mirror lives at
 *   providers/common/connector_protocol.py
 * and keeps the pull path (Lakeflow fanout) in sync.
 */
import type { Request } from "express";

export interface DateRange {
  start: Date;
  end: Date;
}

export interface BronzeRow {
  record_id: string;
  ingested_at: string;
  body: string;
  headers: string;
  record_type: string;
}

export interface OAuthStartResult {
  redirectUrl: string;
  state: string;
}

export interface OAuthCallbackParams {
  code: string;
  state: string;
  userId: string;
  [key: string]: unknown;
}

export interface Credentials {
  providerUserId: string;
  accessToken: string;
  refreshToken?: string;
  tokenExpiresAt?: Date;
  scopes: string[];
}

/**
 * Root interface. Providers implement this via BaseOAuth2Connector or
 * BaseOAuth1aConnector and register into AppKit.wearableCore.connectorRegistry
 * from their plugin's setup().
 */
export interface WearableConnector {
  provider: string;
  displayName: string;
  iconUrl: string;
  supportsWebhook: boolean;
  supportsPoll: boolean;
  recordTypes(): string[];

  // Enrollment
  oauthStart(userId: string): Promise<OAuthStartResult>;
  oauthCallback(params: OAuthCallbackParams): Promise<Credentials>;
  revoke(userId: string): Promise<void>;

  // Push path (optional)
  verifyWebhook?(req: Request): Promise<boolean>;
  handleWebhook?(req: Request): Promise<BronzeRow[]>;

  // Pull path (optional — also typically mirrored in Python for fanout)
  pullBatch?(userId: string, range: DateRange): Promise<BronzeRow[]>;
}
