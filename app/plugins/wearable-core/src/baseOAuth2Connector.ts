/**
 * Scaffolding for OAuth 2.0 (Authorization Code + PKCE) connectors.
 *
 * Fitbit, Whoop, Oura, Withings, Strava all use this flow. Subclass and
 * override the provider-specific bits (authorize URL, token URL, scopes,
 * user_id resolution). The base class handles PKCE code_verifier/challenge,
 * state minting, token exchange, and refresh.
 */
import { createHash, randomBytes } from "node:crypto";
import type {
  BronzeRow,
  Credentials,
  DateRange,
  OAuthCallbackParams,
  OAuthStartResult,
  WearableConnector,
} from "./connector";
import type { CredentialStore } from "./credentialStore";
import type { BronzeWriter } from "./bronzeWriter";

export interface OAuth2Config {
  provider: string;
  displayName: string;
  iconUrl: string;
  authorizeUrl: string;
  tokenUrl: string;
  clientId: string;
  clientSecret: string;
  redirectUri: string;
  scopes: string[];
}

export interface PkceState {
  codeVerifier: string;
  userId: string;
  createdAt: number;
}

/**
 * Minimal cache contract compatible with AppKit's caching plugin.
 * Stores the PKCE verifier + userId keyed by the state string for the
 * short window between oauthStart and oauthCallback.
 */
export interface PkceStateCache {
  put(state: string, payload: PkceState, ttlSeconds: number): Promise<void>;
  take(state: string): Promise<PkceState | null>;
}

export abstract class BaseOAuth2Connector implements WearableConnector {
  constructor(
    protected readonly oauthConfig: OAuth2Config,
    protected readonly credentialStore: CredentialStore,
    protected readonly bronzeWriter: BronzeWriter,
    protected readonly stateCache: PkceStateCache,
  ) {}

  get provider(): string {
    return this.oauthConfig.provider;
  }
  get displayName(): string {
    return this.oauthConfig.displayName;
  }
  get iconUrl(): string {
    return this.oauthConfig.iconUrl;
  }

  supportsWebhook = true;
  supportsPoll = true;

  abstract recordTypes(): string[];

  // -----------------------------------------------------------------
  // OAuth 2.0 + PKCE
  // -----------------------------------------------------------------

  async oauthStart(userId: string): Promise<OAuthStartResult> {
    const codeVerifier = base64UrlEncode(randomBytes(32));
    const codeChallenge = base64UrlEncode(
      createHash("sha256").update(codeVerifier).digest(),
    );
    const state = base64UrlEncode(randomBytes(16));

    await this.stateCache.put(
      state,
      { codeVerifier, userId, createdAt: Date.now() },
      600, // 10 minutes
    );

    const url = new URL(this.oauthConfig.authorizeUrl);
    url.searchParams.set("response_type", "code");
    url.searchParams.set("client_id", this.oauthConfig.clientId);
    url.searchParams.set("redirect_uri", this.oauthConfig.redirectUri);
    url.searchParams.set("scope", this.oauthConfig.scopes.join(" "));
    url.searchParams.set("code_challenge", codeChallenge);
    url.searchParams.set("code_challenge_method", "S256");
    url.searchParams.set("state", state);

    return { redirectUrl: url.toString(), state };
  }

  async oauthCallback(params: OAuthCallbackParams): Promise<Credentials> {
    const cached = await this.stateCache.take(params.state);
    if (!cached || cached.userId !== params.userId) {
      throw new Error("Invalid OAuth state — possible CSRF or expired flow");
    }

    const tokenResp = await this.exchangeCodeForToken(
      params.code,
      cached.codeVerifier,
    );

    const providerUserId = await this.resolveProviderUserId(
      tokenResp.access_token,
    );

    const creds: Credentials = {
      providerUserId,
      accessToken: tokenResp.access_token,
      refreshToken: tokenResp.refresh_token,
      tokenExpiresAt: tokenResp.expires_in
        ? new Date(Date.now() + tokenResp.expires_in * 1000)
        : undefined,
      scopes: (tokenResp.scope ?? this.oauthConfig.scopes.join(" "))
        .split(/[, ]+/)
        .filter(Boolean),
    };

    await this.credentialStore.put({
      userId: params.userId,
      provider: this.provider,
      ...creds,
    });

    return creds;
  }

  async revoke(userId: string): Promise<void> {
    await this.credentialStore.revoke(userId, this.provider);
    // Providers that expose a revoke endpoint should override to call it.
  }

  // -----------------------------------------------------------------
  // Hooks providers override
  // -----------------------------------------------------------------

  protected async exchangeCodeForToken(
    code: string,
    codeVerifier: string,
  ): Promise<{
    access_token: string;
    refresh_token?: string;
    expires_in?: number;
    scope?: string;
    [key: string]: unknown;
  }> {
    const body = new URLSearchParams({
      grant_type: "authorization_code",
      code,
      redirect_uri: this.oauthConfig.redirectUri,
      client_id: this.oauthConfig.clientId,
      code_verifier: codeVerifier,
    });
    const resp = await fetch(this.oauthConfig.tokenUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Authorization:
          "Basic " +
          Buffer.from(
            `${this.oauthConfig.clientId}:${this.oauthConfig.clientSecret}`,
          ).toString("base64"),
      },
      body,
    });
    if (!resp.ok) {
      throw new Error(
        `OAuth token exchange failed (${resp.status}): ${await resp.text()}`,
      );
    }
    return resp.json() as Promise<{
      access_token: string;
      refresh_token?: string;
      expires_in?: number;
      scope?: string;
    }>;
  }

  /**
   * Every provider exposes a "who am I" endpoint with the bearer token.
   * Override to call the provider's userinfo URL and return its ID.
   */
  protected abstract resolveProviderUserId(accessToken: string): Promise<string>;

  // Pull and webhook are provider-specific — not implemented here.
  async pullBatch?(_userId: string, _range: DateRange): Promise<BronzeRow[]>;
  async handleWebhook?(_req: unknown): Promise<BronzeRow[]>;
  async verifyWebhook?(_req: unknown): Promise<boolean>;
}

function base64UrlEncode(buf: Buffer): string {
  return buf
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}
