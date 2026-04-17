/**
 * Scaffolding for OAuth 1.0a connectors (the legacy flow Garmin Health
 * API still uses as of early 2026).
 *
 * Subclass for Garmin. Adopt BaseOAuth2Connector when Garmin migrates
 * to OAuth 2.0.
 *
 * OAuth 1.0a flow:
 *   1. POST to request_token_url → receive oauth_token + oauth_token_secret
 *   2. Redirect user to authorize_url?oauth_token=…
 *   3. User consents, Garmin redirects back with oauth_verifier
 *   4. POST to access_token_url with verifier → receive long-lived tokens
 *
 * Signature: HMAC-SHA1 per RFC 5849.
 */
import { createHmac, randomBytes } from "node:crypto";
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

export interface OAuth1aConfig {
  provider: string;
  displayName: string;
  iconUrl: string;
  requestTokenUrl: string;
  authorizeUrl: string;
  accessTokenUrl: string;
  consumerKey: string;
  consumerSecret: string;
  redirectUri: string;
}

export interface OAuth1aRequestTokenCache {
  put(
    oauthToken: string,
    payload: { tokenSecret: string; userId: string },
    ttlSeconds: number,
  ): Promise<void>;
  take(
    oauthToken: string,
  ): Promise<{ tokenSecret: string; userId: string } | null>;
}

export abstract class BaseOAuth1aConnector implements WearableConnector {
  constructor(
    protected readonly oauthConfig: OAuth1aConfig,
    protected readonly credentialStore: CredentialStore,
    protected readonly bronzeWriter: BronzeWriter,
    protected readonly requestTokenCache: OAuth1aRequestTokenCache,
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

  async oauthStart(userId: string): Promise<OAuthStartResult> {
    const { oauth_token, oauth_token_secret } = await this.fetchRequestToken();
    await this.requestTokenCache.put(
      oauth_token,
      { tokenSecret: oauth_token_secret, userId },
      600,
    );
    const url = new URL(this.oauthConfig.authorizeUrl);
    url.searchParams.set("oauth_token", oauth_token);
    url.searchParams.set("oauth_callback", this.oauthConfig.redirectUri);
    return { redirectUrl: url.toString(), state: oauth_token };
  }

  async oauthCallback(params: OAuthCallbackParams): Promise<Credentials> {
    const cached = await this.requestTokenCache.take(params.state);
    if (!cached || cached.userId !== params.userId) {
      throw new Error("Invalid OAuth1a state — possible CSRF or expired flow");
    }
    const oauthVerifier = params["oauth_verifier"] as string | undefined;
    if (!oauthVerifier) {
      throw new Error("Missing oauth_verifier in callback");
    }
    const { oauth_token, oauth_token_secret } = await this.fetchAccessToken(
      params.state,
      cached.tokenSecret,
      oauthVerifier,
    );
    const providerUserId = await this.resolveProviderUserId(
      oauth_token,
      oauth_token_secret,
    );
    const creds: Credentials = {
      providerUserId,
      accessToken: `${oauth_token}:${oauth_token_secret}`, // store as one blob
      scopes: [],
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
  }

  // -----------------------------------------------------------------
  // OAuth 1.0a helpers — subclass may override per provider quirks
  // -----------------------------------------------------------------

  protected async fetchRequestToken(): Promise<{
    oauth_token: string;
    oauth_token_secret: string;
  }> {
    const resp = await this.signedFetch("POST", this.oauthConfig.requestTokenUrl, "", {
      oauth_callback: this.oauthConfig.redirectUri,
    });
    return parseFormTokenResponse(resp);
  }

  protected async fetchAccessToken(
    oauthToken: string,
    tokenSecret: string,
    oauthVerifier: string,
  ): Promise<{ oauth_token: string; oauth_token_secret: string }> {
    const resp = await this.signedFetch(
      "POST",
      this.oauthConfig.accessTokenUrl,
      tokenSecret,
      { oauth_token: oauthToken, oauth_verifier: oauthVerifier },
    );
    return parseFormTokenResponse(resp);
  }

  protected abstract resolveProviderUserId(
    oauthToken: string,
    oauthTokenSecret: string,
  ): Promise<string>;

  protected async signedFetch(
    method: "GET" | "POST",
    url: string,
    tokenSecret: string,
    extraOAuthParams: Record<string, string> = {},
  ): Promise<string> {
    const oauthParams: Record<string, string> = {
      oauth_consumer_key: this.oauthConfig.consumerKey,
      oauth_nonce: randomBytes(16).toString("hex"),
      oauth_signature_method: "HMAC-SHA1",
      oauth_timestamp: Math.floor(Date.now() / 1000).toString(),
      oauth_version: "1.0",
      ...extraOAuthParams,
    };
    const signature = signHmacSha1(
      method,
      url,
      oauthParams,
      this.oauthConfig.consumerSecret,
      tokenSecret,
    );
    oauthParams.oauth_signature = signature;
    const authHeader =
      "OAuth " +
      Object.entries(oauthParams)
        .map(([k, v]) => `${k}="${encodeURIComponent(v)}"`)
        .join(", ");
    const resp = await fetch(url, {
      method,
      headers: { Authorization: authHeader },
    });
    if (!resp.ok) {
      throw new Error(
        `OAuth1a ${method} ${url} failed (${resp.status}): ${await resp.text()}`,
      );
    }
    return resp.text();
  }

  async pullBatch?(_userId: string, _range: DateRange): Promise<BronzeRow[]>;
  async handleWebhook?(_req: unknown): Promise<BronzeRow[]>;
  async verifyWebhook?(_req: unknown): Promise<boolean>;
}

function signHmacSha1(
  method: string,
  url: string,
  params: Record<string, string>,
  consumerSecret: string,
  tokenSecret: string,
): string {
  const paramString = Object.entries(params)
    .map(([k, v]) => [encodeURIComponent(k), encodeURIComponent(v)] as const)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([k, v]) => `${k}=${v}`)
    .join("&");
  const base = [method, encodeURIComponent(url), encodeURIComponent(paramString)].join(
    "&",
  );
  const key = `${encodeURIComponent(consumerSecret)}&${encodeURIComponent(tokenSecret)}`;
  return createHmac("sha1", key).update(base).digest("base64");
}

function parseFormTokenResponse(body: string): {
  oauth_token: string;
  oauth_token_secret: string;
} {
  const params = new URLSearchParams(body);
  const oauth_token = params.get("oauth_token");
  const oauth_token_secret = params.get("oauth_token_secret");
  if (!oauth_token || !oauth_token_secret) {
    throw new Error(`Malformed OAuth1a token response: ${body}`);
  }
  return { oauth_token, oauth_token_secret };
}
