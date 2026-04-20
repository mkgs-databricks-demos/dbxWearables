import { useState } from 'react';
import {
  Clock,
  ChevronDown,
  ChevronRight,
  UserCheck,
  RefreshCw,
  AlertTriangle,
} from 'lucide-react';
import { BrandIcon } from '@/components/BrandIcon';

/* ═══════════════════════════════════════════════════════════════════
   SecurityPage — Authentication & Identity architecture
   Based on user-identity-todo.md planning document
   ═══════════════════════════════════════════════════════════════════ */

export function SecurityPage() {
  return (
    <div className="min-h-screen">
      <HeroSection />
      <AuthFlowDiagram />
      <TwoLayerModel />
      <SignInWithApple />
      <TokenLifecycle />
      <IdentityExtraction />
      <LakebaseRegistry />
      <AuthEndpoints />
      <BronzeIdentity />
      <ImplementationStatus />
    </div>
  );
}

/* ── Hero ──────────────────────────────────────────────────────────── */
function HeroSection() {
  return (
    <section className="gradient-hero text-white py-16 px-6 relative overflow-hidden">
      <div className="absolute inset-0 opacity-[0.03]">
        <img src="/images/databricks-symbol-light.svg" alt="" aria-hidden="true"
          className="absolute -bottom-20 -left-20 w-[400px] h-[400px] -rotate-12" />
      </div>
      <div className="max-w-5xl mx-auto relative z-10">
        <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-white/10 border border-white/20 text-sm mb-6">
          <BrandIcon name="data-security" className="h-4 w-4 text-[var(--dbx-lava-500)]" />
          App-Managed JWT Auth with Lakebase User Registry
        </div>
        <h1 className="text-4xl font-bold mb-3 tracking-tight">
          Security &amp; Authentication
        </h1>
        <p className="text-lg text-gray-300 max-w-2xl leading-relaxed">
          Two-layer authentication model: users authenticate to the app via Sign in with Apple,
          while the app authenticates to Databricks via M2M service principal credentials.
          Users never touch Databricks auth.
        </p>
      </div>
    </section>
  );
}

/* ── Auth Flow Diagram (image) ────────────────────────────────────── */
function AuthFlowDiagram() {
  return (
    <section className="py-16 px-6 bg-[var(--muted)]">
      <div className="max-w-6xl mx-auto">
        <SectionHeader
          label="Authentication Flow"
          title="JWT Authentication for Mobile Apps"
          subtitle="Sign in with Apple → App JWT → ZeroBus ingestion with authenticated user identity."
        />
        <div className="mt-8 bg-[var(--card)] rounded-2xl shadow-lg border border-[var(--border)] p-4 overflow-hidden">
          <img
            src="/images/dbxWearables-auth-flow.png"
            alt="dbxWearables JWT Authentication Flow Diagram"
            className="w-full rounded-xl"
          />
        </div>
      </div>
    </section>
  );
}

/* ── Two-Layer Auth Model ─────────────────────────────────────────── */
function TwoLayerModel() {
  const layers = [
    {
      brandKey: 'smartphone',
      direction: 'User → App',
      title: 'User Authentication',
      mechanism: 'App-issued JWT via Sign in with Apple',
      status: 'Planned',
      statusColor: 'text-amber-500 bg-amber-50',
      desc: 'Mobile users authenticate to the Databricks App using Sign in with Apple. The app validates the Apple identity token, registers the user in Lakebase, and issues its own short-lived JWT. This JWT is sent as a Bearer token on every API call.',
      details: [
        'Sign in with Apple provides a privacy-preserving user ID (sub claim)',
        'App issues its own JWT (15 min) signed with a secret from the Databricks secret scope',
        'Refresh tokens (30 days) stored as SHA-256 hashes in Lakebase',
        'Users never interact with Databricks workspace auth',
      ],
    },
    {
      brandKey: 'webhook',
      direction: 'App → Workspace',
      title: 'Service Principal Auth',
      mechanism: 'M2M OAuth client credentials',
      status: 'Active',
      statusColor: 'text-[var(--dbx-green-600)] bg-emerald-50',
      desc: 'The Databricks App authenticates to the workspace using an auto-provisioned service principal. This SPN has access to ZeroBus, Unity Catalog, and the secret scope. It is the single identity writing to ZeroBus on behalf of all users.',
      details: [
        'M2M OAuth client credentials flow (DATABRICKS_CLIENT_ID / CLIENT_SECRET)',
        'ZeroBus SPN credentials stored in Databricks secret scope',
        'Single identity writes to bronze table — user_id comes from validated JWT claims',
        'AppKit proxy injects x-forwarded-email for workspace traffic',
      ],
    },
  ];

  return (
    <section className="py-20 px-6 bg-[var(--background)]">
      <div className="max-w-5xl mx-auto">
        <SectionHeader
          label="Architecture"
          title="Two-Layer Authentication Model"
          subtitle="Users authenticate to the app. The app authenticates to Databricks. These are independent layers."
        />

        <div className="grid md:grid-cols-2 gap-6 mt-12">
          {layers.map((layer, i) => (
            <div key={i} className="bg-[var(--card)] border border-[var(--border)] rounded-xl overflow-hidden">
              <div className="bg-[var(--dbx-navy-800)] p-5 text-white">
                <div className="flex items-center gap-3 mb-2">
                  {'brandKey' in layer ? <BrandIcon name={layer.brandKey} className="h-6 w-6" /> : null}
                  <span className="text-xs font-mono text-gray-400">{layer.direction}</span>
                  <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${layer.statusColor}`}>
                    {layer.status}
                  </span>
                </div>
                <h3 className="text-xl font-bold">{layer.title}</h3>
                <p className="text-sm text-gray-300 font-mono mt-1">{layer.mechanism}</p>
              </div>
              <div className="p-5">
                <p className="text-sm text-[var(--muted-foreground)] leading-relaxed mb-4">{layer.desc}</p>
                <ul className="space-y-2">
                  {layer.details.map((d, j) => (
                    <li key={j} className="flex items-start gap-2 text-xs text-[var(--foreground)]">
                      <div className="mt-1 w-4 h-4 rounded-full bg-[var(--dbx-green-600)] flex items-center justify-center flex-shrink-0">
                        <svg className="h-2.5 w-2.5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}>
                          <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                        </svg>
                      </div>
                      {d}
                    </li>
                  ))}
                </ul>
              </div>
            </div>
          ))}
        </div>

        {/* Why this approach */}
        <div className="mt-8 bg-[var(--dbx-navy-800)] rounded-xl p-6 text-white">
          <h4 className="font-bold mb-3 flex items-center gap-2">
            <AlertTriangle className="h-5 w-5 text-[var(--dbx-lava-500)]" />
            Why Not Databricks-Native User Auth?
          </h4>
          <p className="text-gray-300 text-sm leading-relaxed">
            Onboarding each mobile app user as a Databricks workspace identity is not possible.
            This rules out Databricks OIDC, per-user service principals, and OAuth2 public client (PKCE) flows.
            Instead, the app manages its own user registry in Lakebase and issues JWTs that carry the user identity
            into the data layer via the validated <code className="text-[var(--dbx-lava-500)] bg-white/10 px-1.5 py-0.5 rounded text-xs">sub</code> claim.
          </p>
        </div>
      </div>
    </section>
  );
}

/* ── Sign in with Apple ───────────────────────────────────────────── */
function SignInWithApple() {
  const steps = [
    { num: '1', title: 'User taps Sign in with Apple', desc: 'ASAuthorizationAppleIDProvider presents the native system sheet. User authenticates with Face ID / Touch ID / password.' },
    { num: '2', title: 'Apple returns identity token', desc: 'ASAuthorizationAppleIDCredential provides an identity JWT with a stable, privacy-preserving sub claim. Full name is only available on first auth.' },
    { num: '3', title: 'App sends token to server', desc: 'POST /api/v1/auth/apple with the Apple identity JWT, device ID (Keychain UUID), platform, and app version.' },
    { num: '4', title: 'Server validates with Apple JWKS', desc: 'Fetch Apple\'s public keys from https://appleid.apple.com/auth/keys, verify the JWT signature, extract the sub claim.' },
    { num: '5', title: 'Upsert user in Lakebase', desc: 'Create or update the user record (keyed on apple_sub), register the device, generate a refresh token hash.' },
    { num: '6', title: 'Issue app JWT + refresh token', desc: 'Return a 15-min access JWT (signed with app secret) and a 30-day refresh token. Both stored in iOS Keychain.' },
  ];

  return (
    <section className="py-20 px-6 bg-[var(--muted)]">
      <div className="max-w-5xl mx-auto">
        <SectionHeader
          label="Identity Provider"
          title="Sign in with Apple"
          subtitle="Apple's privacy-preserving identity for iOS users — no email or name required."
        />

        <div className="mt-12 space-y-4">
          {steps.map((step) => (
            <div key={step.num} className="bg-[var(--card)] border border-[var(--border)] rounded-xl p-5 flex gap-5 items-start hover:shadow-md transition-shadow">
              <div className="w-10 h-10 rounded-full gradient-red flex items-center justify-center text-white font-bold text-sm flex-shrink-0">
                {step.num}
              </div>
              <div>
                <h3 className="font-bold text-[var(--foreground)] mb-1">{step.title}</h3>
                <p className="text-sm text-[var(--muted-foreground)] leading-relaxed">{step.desc}</p>
              </div>
            </div>
          ))}
        </div>

        {/* Why not HealthKit for identity */}
        <div className="mt-8 bg-[var(--card)] border border-[var(--border)] rounded-xl p-6">
          <h4 className="font-bold text-[var(--foreground)] mb-2 flex items-center gap-2">
            <BrandIcon name="authentication" className="h-5 w-5 text-[var(--dbx-lava-600)]" />
            Why HealthKit Can&apos;t Identify Users
          </h4>
          <p className="text-sm text-[var(--muted-foreground)] leading-relaxed">
            Apple HealthKit is local-only and privacy-first — it exposes no user identifier.
            <code className="mx-1 text-xs bg-[var(--muted)] px-1.5 py-0.5 rounded">HKSource</code> identifies the
            app/device that wrote the data, not the person. The iOS app&apos;s per-installation UUID
            (Keychain) persists across updates but is lost on reinstall, and a single user with
            iPhone + iPad would appear as two different device IDs.
          </p>
        </div>
      </div>
    </section>
  );
}

/* ── Token Lifecycle ──────────────────────────────────────────────── */
function TokenLifecycle() {
  const tokens = [
    {
      name: 'Apple Identity Token',
      lifetime: '~10 min',
      iosStorage: 'Transient (not stored)',
      serverStorage: 'Not stored',
      purpose: 'Exchanged once during Sign in with Apple → validates user identity',
      brandKey: 'authentication',
    },
    {
      name: 'App Access JWT',
      lifetime: '15 min',
      iosStorage: 'Keychain (KeychainHelper)',
      serverStorage: 'Not stored (stateless)',
      purpose: 'Bearer token for all API calls — carries user_id in sub claim',
      brandKey: 'encryption',
    },
    {
      name: 'App Refresh Token',
      lifetime: '30 days',
      iosStorage: 'Keychain (KeychainHelper)',
      serverStorage: 'Lakebase refresh_tokens (hashed)',
      purpose: 'Silent token renewal without re-authentication',
      icon: RefreshCw,
    },
  ];

  return (
    <section className="py-20 px-6 bg-[var(--background)]">
      <div className="max-w-5xl mx-auto">
        <SectionHeader
          label="Token Management"
          title="Token Lifecycle"
          subtitle="Three tokens with distinct lifetimes, storage locations, and security properties."
        />

        <div className="grid md:grid-cols-3 gap-6 mt-12">
          {tokens.map((t, i) => (
            <div key={i} className="bg-[var(--card)] border border-[var(--border)] rounded-xl p-5 hover:shadow-md transition-shadow">
              <div className="flex items-center gap-3 mb-4">
                <div className="w-10 h-10 rounded-lg bg-[var(--dbx-navy-800)] flex items-center justify-center">
                  {'brandKey' in t ? <BrandIcon name={t.brandKey} className="h-5 w-5" /> : <t.icon className="h-5 w-5 text-white" />}
                </div>
                <div>
                  <h3 className="font-bold text-sm text-[var(--foreground)]">{t.name}</h3>
                  <span className="text-xs font-mono text-[var(--dbx-lava-600)]">{t.lifetime}</span>
                </div>
              </div>
              <p className="text-xs text-[var(--muted-foreground)] leading-relaxed mb-3">{t.purpose}</p>
              <div className="space-y-2 text-xs">
                <div className="flex justify-between bg-[var(--muted)] rounded-lg px-3 py-2">
                  <span className="text-[var(--muted-foreground)]">iOS</span>
                  <span className="font-medium text-[var(--foreground)]">{t.iosStorage}</span>
                </div>
                <div className="flex justify-between bg-[var(--muted)] rounded-lg px-3 py-2">
                  <span className="text-[var(--muted-foreground)]">Server</span>
                  <span className="font-medium text-[var(--foreground)]">{t.serverStorage}</span>
                </div>
              </div>
            </div>
          ))}
        </div>

        {/* JWT Claims */}
        <div className="mt-8">
          <h4 className="font-bold text-[var(--foreground)] mb-3 flex items-center gap-2">
            <BrandIcon name="encryption" className="h-5 w-5 text-[var(--dbx-lava-600)]" />
            JWT Access Token Claims
          </h4>
          <div className="code-block text-sm">
            <pre>{`{
  `}<span className="header-name">"sub"</span>{`:       `}<span className="string">"&lt;user_id UUID from Lakebase users table&gt;"</span>{`,
  `}<span className="header-name">"device_id"</span>{`: `}<span className="string">"&lt;X-Device-Id from Keychain&gt;"</span>{`,
  `}<span className="header-name">"platform"</span>{`:  `}<span className="string">"apple_healthkit"</span>{`,
  `}<span className="header-name">"iat"</span>{`:       `}<span className="keyword">1776500000</span>{`,
  `}<span className="header-name">"exp"</span>{`:       `}<span className="keyword">1776500900</span>{`    `}<span className="comment">// iat + 900s (15 min)</span>{`
}`}</pre>
          </div>
          <p className="text-xs text-[var(--muted-foreground)] mt-2">
            Signed with HS256 using a secret from the Databricks secret scope
            (<code className="bg-[var(--muted)] px-1 py-0.5 rounded">dbxw_zerobus_secrets/jwt_signing_secret</code>).
            The <code className="bg-[var(--muted)] px-1 py-0.5 rounded">sub</code> claim is the value written to the bronze
            table&apos;s <code className="bg-[var(--muted)] px-1 py-0.5 rounded">user_id</code> column.
          </p>
        </div>
      </div>
    </section>
  );
}

/* ── Identity Extraction (3-way) ──────────────────────────────────── */
function IdentityExtraction() {
  const methods = [
    {
      priority: '1',
      title: 'Authorization: Bearer <JWT>',
      source: 'Direct mobile client',
      desc: 'iOS/Android app sends the app-issued JWT. Server validates the signature, checks expiry, and extracts the sub claim (Lakebase user UUID) as user_id. AppKit\'s proxy strips this header, so its presence confirms a direct client call.',
      status: 'Planned',
      statusColor: 'text-amber-500 bg-amber-50',
    },
    {
      priority: '2',
      title: 'x-forwarded-email',
      source: 'Workspace traffic',
      desc: 'Injected by AppKit\'s reverse proxy after OAuth validation. Used for requests from Databricks notebooks, jobs, or services. Cannot be spoofed — the proxy strips client-supplied forwarded headers before injecting its own.',
      status: 'Active',
      statusColor: 'text-[var(--dbx-green-600)] bg-emerald-50',
    },
    {
      priority: '3',
      title: 'Anonymous (fallback)',
      source: 'No auth context',
      desc: 'When no authentication context is available — pre-auth clients, health checks, or development/testing. Records are still ingested but tagged with user_id = "anonymous".',
      status: 'Active',
      statusColor: 'text-[var(--dbx-green-600)] bg-emerald-50',
    },
  ];

  return (
    <section className="py-20 px-6 bg-[var(--muted)]">
      <div className="max-w-5xl mx-auto">
        <SectionHeader
          label="Request Processing"
          title="Three-Way Identity Extraction"
          subtitle="Priority-ordered determination of user identity on each ingest request."
        />
        <div className="space-y-4 mt-12">
          {methods.map((m) => (
            <div key={m.priority} className="bg-[var(--card)] border border-[var(--border)] rounded-xl p-5 flex gap-5 items-start hover:shadow-md transition-shadow">
              <div className="w-10 h-10 rounded-full bg-[var(--dbx-navy-800)] flex items-center justify-center text-white font-bold text-sm flex-shrink-0">
                {m.priority}
              </div>
              <div className="flex-1">
                <div className="flex items-center gap-3 mb-1 flex-wrap">
                  <h3 className="font-bold text-[var(--foreground)] font-mono text-sm">{m.title}</h3>
                  <span className="text-xs text-[var(--muted-foreground)]">{m.source}</span>
                  <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${m.statusColor}`}>{m.status}</span>
                </div>
                <p className="text-sm text-[var(--muted-foreground)] leading-relaxed">{m.desc}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

/* ── Lakebase User Registry ───────────────────────────────────────── */
function LakebaseRegistry() {
  return (
    <section className="py-20 px-6 bg-[var(--background)]">
      <div className="max-w-5xl mx-auto">
        <SectionHeader
          label="Data Store"
          title="Lakebase User Registry"
          subtitle="Three Postgres tables manage user identity, device tracking, and token lifecycle."
        />

        <div className="grid md:grid-cols-3 gap-6 mt-12">
          <TableCard
            name="users"
            icon={UserCheck}
            desc="One row per authenticated person. Keyed on Apple's privacy-preserving sub claim."
            columns={[
              { name: 'user_id', type: 'UUID', note: 'PRIMARY KEY' },
              { name: 'apple_sub', type: 'TEXT', note: 'UNIQUE NOT NULL' },
              { name: 'display_name', type: 'TEXT', note: 'optional' },
              { name: 'created_at', type: 'TIMESTAMPTZ', note: '' },
              { name: 'last_seen_at', type: 'TIMESTAMPTZ', note: '' },
            ]}
          />
          <TableCard
            name="devices"
            brandKey="smartphone"
            desc="Links device installs to users. A single user with iPhone + iPad = two device rows."
            columns={[
              { name: 'device_id', type: 'TEXT', note: 'PRIMARY KEY' },
              { name: 'user_id', type: 'UUID', note: 'FK → users' },
              { name: 'platform', type: 'TEXT', note: '' },
              { name: 'app_version', type: 'TEXT', note: '' },
              { name: 'first_seen_at', type: 'TIMESTAMPTZ', note: '' },
            ]}
          />
          <TableCard
            name="refresh_tokens"
            brandKey="encryption"
            desc="SHA-256 hashes of active refresh tokens. Raw tokens are never stored server-side."
            columns={[
              { name: 'token_hash', type: 'TEXT', note: 'PRIMARY KEY' },
              { name: 'user_id', type: 'UUID', note: 'FK → users' },
              { name: 'device_id', type: 'TEXT', note: 'FK → devices' },
              { name: 'expires_at', type: 'TIMESTAMPTZ', note: '' },
              { name: 'revoked_at', type: 'TIMESTAMPTZ', note: 'NULL if active' },
            ]}
          />
        </div>
      </div>
    </section>
  );
}

function TableCard({
  name, icon: Icon, brandKey, desc, columns,
}: {
  name: string;
  icon?: React.ComponentType<{ className?: string }>;
  brandKey?: import('@/icons').IconKey;
  desc: string;
  columns: { name: string; type: string; note: string }[];
}) {
  return (
    <div className="bg-[var(--card)] border border-[var(--border)] rounded-xl overflow-hidden">
      <div className="bg-[var(--dbx-navy-800)] p-4 text-white flex items-center gap-3">
        {brandKey ? <BrandIcon name={brandKey} className="h-5 w-5" /> : Icon ? <Icon className="h-5 w-5" /> : null}
        <code className="font-bold">{name}</code>
      </div>
      <div className="p-4">
        <p className="text-xs text-[var(--muted-foreground)] mb-3 leading-relaxed">{desc}</p>
        <div className="space-y-1">
          {columns.map((col) => (
            <div key={col.name} className="flex items-center justify-between text-xs bg-[var(--muted)] rounded px-2.5 py-1.5">
              <code className="font-medium text-[var(--foreground)]">{col.name}</code>
              <div className="flex items-center gap-2">
                <span className="text-[var(--dbx-lava-500)] font-mono">{col.type}</span>
                {col.note && <span className="text-[var(--muted-foreground)]">{col.note}</span>}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

/* ── Auth API Endpoints ───────────────────────────────────────────── */
function AuthEndpoints() {
  const [expandedIdx, setExpandedIdx] = useState<number | null>(null);

  const endpoints = [
    {
      method: 'POST',
      path: '/api/v1/auth/apple',
      badge: 'bg-[var(--dbx-green-600)]',
      summary: 'Exchange Apple identity token for app JWT',
      auth: 'Public (no JWT required)',
      request: `{
  "identity_token": "<Apple identity JWT>",
  "device_id": "<DeviceIdentifier.current>",
  "platform": "apple_healthkit",
  "app_version": "1.0.0"
}`,
      response: `{
  "access_token": "<app JWT>",
  "refresh_token": "<opaque token>",
  "expires_in": 900,
  "token_type": "Bearer",
  "user_id": "<UUID>"
}`,
      flow: 'Validate Apple JWT (JWKS) → extract sub → upsert user in Lakebase → register device → issue app JWT + refresh token',
    },
    {
      method: 'POST',
      path: '/api/v1/auth/refresh',
      badge: 'bg-blue-500',
      summary: 'Exchange refresh token for new access JWT',
      auth: 'Refresh token only',
      request: `{
  "refresh_token": "<opaque token>"
}`,
      response: `{
  "access_token": "<new app JWT>",
  "refresh_token": "<new opaque token>",
  "expires_in": 900,
  "token_type": "Bearer",
  "user_id": "<UUID>"
}`,
      flow: 'Hash refresh token → lookup in Lakebase → verify not expired/revoked → issue new JWT → rotate refresh token',
    },
    {
      method: 'POST',
      path: '/api/v1/auth/revoke',
      badge: 'bg-red-500',
      summary: 'Revoke refresh token (logout)',
      auth: 'Access JWT required',
      request: `{
  "refresh_token": "<opaque token>"
}`,
      response: `{
  "status": "success",
  "message": "Token revoked"
}`,
      flow: 'Validate access JWT → hash refresh token → set revoked_at in Lakebase → return success',
    },
  ];

  return (
    <section className="py-20 px-6 bg-[var(--muted)]">
      <div className="max-w-5xl mx-auto">
        <SectionHeader
          label="API Reference"
          title="Auth Endpoints"
          subtitle="Three new endpoints for the Sign in with Apple authentication flow."
        />

        <div className="space-y-4 mt-12">
          {endpoints.map((ep, i) => (
            <div key={i} className="bg-[var(--card)] border border-[var(--border)] rounded-xl overflow-hidden">
              <button
                onClick={() => setExpandedIdx(expandedIdx === i ? null : i)}
                className="w-full flex items-center gap-4 p-5 hover:bg-[var(--muted)]/50 transition-colors"
              >
                <span className={`px-3 py-1 rounded-md text-xs font-bold uppercase tracking-wider ${ep.badge} text-white`}>
                  {ep.method}
                </span>
                <code className="text-sm font-mono font-bold text-[var(--foreground)] flex-1 text-left">{ep.path}</code>
                <span className="text-xs text-[var(--muted-foreground)]">{ep.summary}</span>
                {expandedIdx === i ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
              </button>
              {expandedIdx === i && (
                <div className="border-t border-[var(--border)] p-5 space-y-4">
                  <div className="flex items-center gap-2 text-xs">
                    <BrandIcon name="encryption" className="h-3.5 w-3.5 text-[var(--muted-foreground)]" />
                    <span className="text-[var(--muted-foreground)]">Auth:</span>
                    <span className="font-medium text-[var(--foreground)]">{ep.auth}</span>
                  </div>
                  <div className="text-xs text-[var(--muted-foreground)] bg-[var(--muted)] rounded-lg p-3">
                    <span className="font-medium text-[var(--foreground)] block mb-1">Server flow:</span>
                    {ep.flow}
                  </div>
                  <div className="grid md:grid-cols-2 gap-4">
                    <div>
                      <span className="text-xs font-medium text-[var(--muted-foreground)] mb-2 block">Request</span>
                      <div className="code-block text-xs"><pre>{ep.request}</pre></div>
                    </div>
                    <div>
                      <span className="text-xs font-medium text-[var(--muted-foreground)] mb-2 block">Response</span>
                      <div className="code-block text-xs"><pre>{ep.response}</pre></div>
                    </div>
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

/* ── Bronze Table Identity ────────────────────────────────────────── */
function BronzeIdentity() {
  const before = [
    { trace: 'Device install', location: 'headers::"x-device-id"', identifies: 'App installation (Keychain UUID)' },
    { trace: 'Platform', location: 'source_platform', identifies: 'Data source (apple_healthkit)' },
    { trace: 'Source app', location: 'body:source_name', identifies: 'HK data contributor' },
    { trace: 'HealthKit sample', location: 'body:uuid', identifies: 'Individual HK record' },
    { trace: 'User (person)', location: '—', identifies: '❌ Not identifiable' },
  ];
  const after = [
    ...before.slice(0, 4),
    { trace: 'User (person)', location: 'user_id column', identifies: '✅ Authenticated person' },
  ];

  return (
    <section className="py-20 px-6 bg-[var(--background)]">
      <div className="max-w-5xl mx-auto">
        <SectionHeader
          label="Data Layer"
          title="Identity in the Bronze Table"
          subtitle="How user_id flows from the validated JWT into the Unity Catalog bronze table."
        />

        <div className="grid md:grid-cols-2 gap-8 mt-12">
          <div>
            <h4 className="font-bold text-[var(--foreground)] mb-3 flex items-center gap-2">
              <Clock className="h-5 w-5 text-[var(--muted-foreground)]" />
              Before (Current)
            </h4>
            <TraceTable rows={before} />
          </div>
          <div>
            <h4 className="font-bold text-[var(--foreground)] mb-3 flex items-center gap-2">
              <UserCheck className="h-5 w-5 text-[var(--dbx-green-600)]" />
              After (With JWT Auth)
            </h4>
            <TraceTable rows={after} highlight />
          </div>
        </div>

        {/* New column */}
        <div className="mt-8 code-block text-sm">
          <pre>{`ALTER `}<span className="keyword">TABLE</span>{` hls_fde_dev.dev_matthew_giglia_wearables.wearables_zerobus
ADD COLUMNS (
  user_id `}<span className="keyword">STRING</span>{` `}<span className="comment">COMMENT 'App-authenticated user ID from validated JWT sub claim'</span>{`
);`}</pre>
        </div>
      </div>
    </section>
  );
}

function TraceTable({ rows, highlight }: { rows: { trace: string; location: string; identifies: string }[]; highlight?: boolean }) {
  return (
    <div className="border border-[var(--border)] rounded-xl overflow-hidden">
      <table className="w-full text-xs">
        <thead className="bg-[var(--muted)]">
          <tr>
            <th className="text-left py-2 px-3 font-medium text-[var(--muted-foreground)]">Trace</th>
            <th className="text-left py-2 px-3 font-medium text-[var(--muted-foreground)]">Location</th>
            <th className="text-left py-2 px-3 font-medium text-[var(--muted-foreground)]">Identifies</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-[var(--border)]">
          {rows.map((r, i) => {
            const isLast = i === rows.length - 1;
            return (
              <tr key={i} className={isLast && highlight ? 'bg-emerald-50' : ''}>
                <td className={`py-2 px-3 font-medium ${isLast ? 'text-[var(--foreground)] font-bold' : 'text-[var(--foreground)]'}`}>{r.trace}</td>
                <td className="py-2 px-3 font-mono text-[var(--dbx-lava-500)]">{r.location}</td>
                <td className="py-2 px-3 text-[var(--muted-foreground)]">{r.identifies}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

/* ── Implementation Status ────────────────────────────────────────── */
function ImplementationStatus() {
  const phases = [
    {
      phase: 'Phase 1',
      title: 'Server-Side Auth Infrastructure',
      status: 'Planned',
      items: [
        'Add jsonwebtoken + jwks-rsa to package.json',
        'Create auth-service.ts (Apple JWKS, JWT signing, Lakebase CRUD)',
        'Create jwt-auth.ts middleware',
        'Create auth-routes.ts (3 endpoints)',
        'Lakebase migration (users, devices, refresh_tokens)',
        'JWT_SIGNING_SECRET in secret scope + app.yaml',
      ],
    },
    {
      phase: 'Phase 2',
      title: 'Ingest Route Integration',
      items: [
        'Add JWT middleware to POST /api/v1/healthkit/ingest',
        'Add user_id to WearablesRecord and buildRecord()',
        'Add user_id STRING column to bronze table DDL',
        'Update validation notebook',
      ],
    },
    {
      phase: 'Phase 3',
      title: 'iOS App Auth',
      items: [
        'Create AuthService.swift (Sign in with Apple)',
        'Create SignInView.swift + AuthViewModel.swift',
        'Update KeychainHelper (store JWT + refresh token)',
        'Update APIService (Bearer token, 401 → refresh)',
        'Gate app on auth state',
      ],
    },
    {
      phase: 'Phase 4',
      title: 'Multi-Device Support',
      items: [
        'Verify same user from multiple devices → single user_id',
        'Test device registration/deregistration',
        'Per-user data aggregation in dashboards',
      ],
    },
  ];

  return (
    <section className="py-20 px-6 bg-[var(--muted)]">
      <div className="max-w-5xl mx-auto">
        <SectionHeader
          label="Roadmap"
          title="Implementation Status"
          subtitle="Phased rollout — each phase is independently deployable."
        />

        <div className="grid sm:grid-cols-2 gap-6 mt-12">
          {phases.map((p, i) => (
            <div key={i} className="bg-[var(--card)] border border-[var(--border)] rounded-xl p-5">
              <div className="flex items-center gap-3 mb-3">
                <span className="text-xs font-bold uppercase tracking-wider text-[var(--dbx-lava-600)]">{p.phase}</span>
                {i === 0 && p.status && (
                  <span className="text-xs font-medium px-2 py-0.5 rounded-full text-amber-500 bg-amber-50">
                    {p.status}
                  </span>
                )}
              </div>
              <h3 className="font-bold text-[var(--foreground)] mb-3">{p.title}</h3>
              <ul className="space-y-1.5">
                {p.items.map((item, j) => (
                  <li key={j} className="flex items-start gap-2 text-xs text-[var(--muted-foreground)]">
                    <div className="mt-0.5 w-4 h-4 rounded border border-[var(--border)] flex-shrink-0" />
                    {item}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

/* ── Shared Section Header ────────────────────────────────────────── */
function SectionHeader({ label, title, subtitle }: { label: string; title: string; subtitle: string }) {
  return (
    <div className="text-center mb-4">
      <span className="inline-block text-xs font-bold uppercase tracking-widest text-[var(--dbx-lava-600)] mb-2">{label}</span>
      <h2 className="text-3xl font-bold text-[var(--foreground)] mb-3">{title}</h2>
      <p className="text-[var(--muted-foreground)] max-w-2xl mx-auto">{subtitle}</p>
    </div>
  );
}
