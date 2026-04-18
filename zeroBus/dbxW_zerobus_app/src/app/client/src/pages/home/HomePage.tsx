import {
  Watch,
  Smartphone,
  Server,
  Layers,
  ArrowRight,
  Zap,
  Lock,
  Shield,
  Radio,
  BarChart3,
  Heart,
  Footprints,
  Moon,
  Flame,
  Trash2,
  Database,
} from 'lucide-react';
import { Link } from 'react-router';

/* ═══════════════════════════════════════════════════════════════════════
   HomePage — Landing page for the dbxWearables ZeroBus Gateway
   Uses official Databricks brand assets from /images/
   ═══════════════════════════════════════════════════════════════════════ */

export function HomePage() {
  return (
    <div className="min-h-screen">
      <HeroSection />
      <ArchitectureDiagramSection />
      <ArchitectureSection />
      <ZeroBusSection />
      <AuthSection />
      <RecordTypesSection />
      <MedallionSection />
    </div>
  );
}

/* ── Hero ──────────────────────────────────────────────────────────── */
function HeroSection() {
  return (
    <section className="gradient-hero text-white py-20 px-6 relative overflow-hidden">
      {/* Background decoration */}
      <div className="absolute inset-0 opacity-[0.03]">
        <img
          src="/images/databricks-symbol-light.svg"
          alt=""
          aria-hidden="true"
          className="absolute -top-20 -right-20 w-[500px] h-[500px] rotate-12"
        />
      </div>

      <div className="max-w-5xl mx-auto relative z-10">
        <div className="flex flex-col lg:flex-row items-center gap-12">
          {/* Text */}
          <div className="flex-1 text-center lg:text-left">
            <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-white/10 border border-white/20 text-sm mb-6">
              <Zap className="h-4 w-4 text-[var(--dbx-orange)]" />
              Powered by Databricks AppKit &amp; ZeroBus
            </div>

            <h1 className="text-5xl font-bold mb-4 tracking-tight">
              dbxWearables
              <span className="block text-3xl font-normal text-gray-300 mt-2">
                ZeroBus Health Data Gateway
              </span>
            </h1>

            <p className="text-lg text-gray-300 max-w-xl leading-relaxed">
              Stream wearable health data from Apple HealthKit into the
              Databricks Lakehouse in real time. Built with AppKit, ZeroBus,
              Lakebase, and Spark Declarative Pipelines.
            </p>

            <div className="flex justify-center lg:justify-start gap-4 mt-10">
              <Link
                to="/docs"
                className="gradient-red text-white px-6 py-3 rounded-lg font-semibold text-sm shadow-lg shadow-[var(--dbx-red)]/30 hover:shadow-[var(--dbx-red)]/50 transition-all"
              >
                View API Docs
              </Link>
              <Link
                to="/status"
                className="bg-white/10 border border-white/20 text-white px-6 py-3 rounded-lg font-semibold text-sm hover:bg-white/20 transition-all"
              >
                System Health
              </Link>
            </div>

            {/* Powered by logo */}
            <div className="mt-10 pt-6 border-t border-white/10">
              <span className="text-xs text-gray-500 uppercase tracking-widest block mb-3">Powered by</span>
              <img
                src="/images/primary-lockup-one-color-white-rgb.svg"
                alt="Databricks"
                className="h-6 opacity-60"
              />
            </div>
          </div>

          {/* Hero image — project banner */}
          <div className="flex-shrink-0">
            <img
              src="/images/dbxWearables-square.png"
              alt="dbxWearables"
              className="w-72 h-72 rounded-2xl shadow-2xl shadow-black/40 border border-white/10 object-cover"
            />
          </div>
        </div>
      </div>
    </section>
  );
}

/* ── Architecture Diagram (actual image) ──────────────────────────── */
function ArchitectureDiagramSection() {
  return (
    <section className="py-16 px-6 bg-[var(--muted)]">
      <div className="max-w-6xl mx-auto">
        <SectionHeader
          label="System Overview"
          title="HealthKit Architecture"
          subtitle="The end-to-end data flow from Apple Watch to Lakehouse analytics."
        />
        <div className="mt-8 bg-[var(--card)] rounded-2xl shadow-lg border border-[var(--border)] p-4 overflow-hidden">
          <img
            src="/images/dbxWearables-architecture.png"
            alt="dbxWearables HealthKit Architecture Diagram"
            className="w-full rounded-xl"
          />
        </div>
      </div>
    </section>
  );
}

/* ── Architecture Flow (cards) ────────────────────────────────────── */
function ArchitectureSection() {
  const steps = [
    {
      icon: Watch,
      title: 'Apple HealthKit',
      subtitle: 'Data Source',
      desc: 'Apple Watch and Health app collect activity, workouts, sleep, and vitals. The iOS app reads data via anchored HealthKit queries.',
      color: 'bg-gray-800',
      image: null,
    },
    {
      icon: Smartphone,
      title: 'iOS App',
      subtitle: 'NDJSON Serializer',
      desc: 'SwiftUI app maps HKSamples to Codable structs, serializes as NDJSON, and POSTs batches with X-Record-Type headers.',
      color: 'bg-blue-600',
      image: null,
    },
    {
      icon: Server,
      title: 'AppKit Gateway',
      subtitle: 'REST API',
      desc: 'Express server receives NDJSON payloads, validates headers, extracts user identity, and forwards to the ZeroBus SDK.',
      color: 'bg-[var(--dbx-red)]',
      image: '/images/databricks-symbol-color.svg',
    },
    {
      icon: Radio,
      title: 'ZeroBus',
      subtitle: 'Stream Bridge',
      desc: 'Streams records into Unity Catalog bronze table with no external infrastructure. Decouples API from table writes.',
      color: 'bg-[var(--dbx-orange)]',
      image: '/images/databricks-symbol-color.svg',
    },
    {
      icon: null,
      title: 'Unity Catalog',
      subtitle: 'Bronze Table',
      desc: 'Raw NDJSON stored as VARIANT column. Full HTTP headers preserved. Schema-on-read for maximum flexibility.',
      color: 'bg-[var(--dbx-green)]',
      image: '/images/unity-catalog-lockup-no-db-full-color.svg',
    },
    {
      icon: Layers,
      title: 'SDP Pipeline',
      subtitle: 'Silver → Gold',
      desc: 'Spark Declarative Pipelines read bronze, clean and validate to silver, aggregate to gold for analytics.',
      color: 'bg-purple-600',
      image: null,
    },
  ];

  return (
    <section className="py-20 px-6 bg-[var(--background)]">
      <div className="max-w-6xl mx-auto">
        <SectionHeader
          label="Architecture"
          title="Component Breakdown"
          subtitle="Each stage in the data pipeline from wrist to Lakehouse."
        />

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mt-12">
          {steps.map((step, i) => (
            <div key={i} className="relative group">
              <div className="bg-[var(--card)] border border-[var(--border)] rounded-xl p-6 shadow-sm hover:shadow-lg transition-all duration-300 h-full">
                {/* Step number */}
                <div className="absolute -top-3 -left-2 w-7 h-7 rounded-full gradient-red flex items-center justify-center text-white text-xs font-bold shadow-md">
                  {i + 1}
                </div>

                {/* Icon — official image or lucide icon */}
                {step.image && step.title === 'Unity Catalog' ? (
                  <div className="mb-4 h-12 flex items-center">
                    <img src={step.image} alt={step.title} className="h-10" />
                  </div>
                ) : step.image ? (
                  <div className={`${step.color} w-12 h-12 rounded-xl flex items-center justify-center mb-4 p-2`}>
                    <img src={step.image} alt="" className="h-7 w-7 brightness-0 invert" />
                  </div>
                ) : step.icon ? (
                  <div className={`${step.color} w-12 h-12 rounded-xl flex items-center justify-center mb-4`}>
                    <step.icon className="h-6 w-6 text-white" />
                  </div>
                ) : null}

                <h3 className="text-lg font-bold text-[var(--foreground)]">
                  {step.title}
                </h3>
                <p className="text-xs font-medium text-[var(--dbx-red)] uppercase tracking-wider mb-2">
                  {step.subtitle}
                </p>
                <p className="text-sm text-[var(--muted-foreground)] leading-relaxed">
                  {step.desc}
                </p>

                {/* Arrow connector */}
                {i < steps.length - 1 && (i + 1) % 3 !== 0 && (
                  <div className="hidden lg:block absolute -right-3 top-1/2 -translate-y-1/2 z-10">
                    <ArrowRight className="h-5 w-5 text-[var(--dbx-red)]" />
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

/* ── ZeroBus Explainer ────────────────────────────────────────────── */
function ZeroBusSection() {
  return (
    <section className="py-20 px-6 bg-[var(--muted)]">
      <div className="max-w-5xl mx-auto">
        <SectionHeader
          label="Core Technology"
          title="What is ZeroBus?"
          subtitle="A zero-infrastructure event bridge built into Databricks."
        />

        <div className="grid md:grid-cols-2 gap-8 mt-12">
          <div className="space-y-6">
            <p className="text-[var(--foreground)] leading-relaxed">
              <strong>ZeroBus Ingest</strong> is a Databricks-native streaming
              connector that lets applications write data directly into Unity
              Catalog tables via a REST API — no Kafka, no Kinesis, no
              external message brokers required.
            </p>
            <p className="text-[var(--muted-foreground)] leading-relaxed">
              The ZeroBus SDK runs inside this AppKit application. When the
              iOS HealthKit app POSTs an NDJSON payload, the Express route
              handler builds a typed record and calls the SDK&apos;s ingest
              method. ZeroBus handles batching, delivery guarantees, and
              writing to the target Delta table in Unity Catalog.
            </p>

            <div className="space-y-3 mt-6">
              {[
                'No external infrastructure to manage',
                'Direct write to Unity Catalog Delta tables',
                'OAuth2 M2M authentication via service principal',
                'Automatic batching and delivery guarantees',
                'Schema-on-read with VARIANT column support',
              ].map((item, i) => (
                <div key={i} className="flex items-start gap-3">
                  <div className="mt-1 w-5 h-5 rounded-full bg-[var(--dbx-green)] flex items-center justify-center flex-shrink-0">
                    <svg className="h-3 w-3 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                    </svg>
                  </div>
                  <span className="text-sm text-[var(--foreground)]">{item}</span>
                </div>
              ))}
            </div>

            {/* Powered by badges */}
            <div className="flex items-center gap-6 mt-8 pt-6 border-t border-[var(--border)]">
              <div className="flex items-center gap-2">
                <img src="/images/databricks-symbol-color.svg" alt="" className="h-6 w-6" />
                <span className="text-xs font-medium text-[var(--muted-foreground)]">AppKit</span>
              </div>
              <div className="flex items-center gap-2">
                <img src="/images/databricks-symbol-color.svg" alt="" className="h-6 w-6" />
                <span className="text-xs font-medium text-[var(--muted-foreground)]">ZeroBus</span>
              </div>
              <div className="flex items-center gap-2">
                <img src="/images/unity-catalog-lockup-no-db-full-color.svg" alt="Unity Catalog" className="h-5" />
              </div>
            </div>
          </div>

          <div className="code-block text-sm">
            <pre>{`// ZeroBus flow inside AppKit
// server/routes/zerobus/ingest-routes.ts

`}<span className="comment">// 1. iOS app POSTs NDJSON payload</span>{`
POST /api/v1/healthkit/ingest
`}<span className="header-name">Content-Type:</span>{` application/x-ndjson
`}<span className="header-name">X-Record-Type:</span>{` samples

`}<span className="comment">// 2. Express route parses NDJSON lines</span>{`
`}<span className="keyword">const</span>{` { lines } = parseNdjson(rawBody);

`}<span className="comment">// 3. Build typed records</span>{`
`}<span className="keyword">const</span>{` records = lines.map(line =>
  zeroBusService.buildRecord(
    line, headers, recordType,
    sourcePlatform, userId
  )
);

`}<span className="comment">// 4. ZeroBus SDK streams to bronze</span>{`
`}<span className="keyword">await</span>{` zeroBusService.ingestRecords(records);

`}<span className="comment">// → Data lands in Unity Catalog table</span>{`
`}<span className="comment">//   as VARIANT (schema-on-read)</span></pre>
          </div>
        </div>
      </div>
    </section>
  );
}

/* ── Authentication ───────────────────────────────────────────────── */
function AuthSection() {
  const authMethods = [
    {
      icon: Lock,
      title: 'Bearer JWT (Mobile Clients)',
      priority: 'Priority 1',
      desc: 'Direct client authentication via Bearer token. The iOS/Android app obtains a JWT from Lakebase, which is validated on each request. The token\'s sub claim (Lakebase user UUID) becomes the user_id.',
      status: 'In Development',
      statusColor: 'text-amber-500 bg-amber-50',
    },
    {
      icon: Shield,
      title: 'x-forwarded-email (Workspace)',
      priority: 'Priority 2',
      desc: 'For requests originating from Databricks notebooks, jobs, or services. AppKit\'s reverse proxy injects the authenticated user\'s email after OAuth validation. Cannot be spoofed — the proxy strips client-supplied forwarded headers.',
      status: 'Active',
      statusColor: 'text-[var(--dbx-green)] bg-emerald-50',
    },
    {
      icon: Shield,
      title: 'Anonymous (Fallback)',
      priority: 'Priority 3',
      desc: 'When no authentication context is available — pre-auth clients, health checks, or development/testing. Records are still ingested but tagged with user_id = "anonymous".',
      status: 'Active',
      statusColor: 'text-[var(--dbx-green)] bg-emerald-50',
    },
  ];

  return (
    <section className="py-20 px-6 bg-[var(--background)]">
      <div className="max-w-5xl mx-auto">
        <SectionHeader
          label="Security"
          title="Authentication &amp; Identity"
          subtitle="Three-way priority for determining user identity on each request."
        />

        <div className="space-y-4 mt-12">
          {authMethods.map((method, i) => (
            <div
              key={i}
              className="bg-[var(--card)] border border-[var(--border)] rounded-xl p-6 flex gap-6 items-start hover:shadow-md transition-shadow"
            >
              <div className="w-12 h-12 rounded-xl bg-[var(--dbx-dark-teal)] flex items-center justify-center flex-shrink-0">
                <method.icon className="h-6 w-6 text-white" />
              </div>
              <div className="flex-1">
                <div className="flex items-center gap-3 mb-1">
                  <h3 className="font-bold text-[var(--foreground)]">{method.title}</h3>
                  <span className="text-xs font-mono text-[var(--muted-foreground)]">{method.priority}</span>
                  <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${method.statusColor}`}>
                    {method.status}
                  </span>
                </div>
                <p className="text-sm text-[var(--muted-foreground)] leading-relaxed">{method.desc}</p>
              </div>
            </div>
          ))}
        </div>

        {/* Lakebase auth detail */}
        <div className="mt-8 bg-[var(--dbx-dark-teal)] rounded-xl p-6 text-white">
          <h4 className="font-bold mb-3 flex items-center gap-2">
            <Database className="h-5 w-5" />
            Lakebase — Operational Database for Auth State
          </h4>
          <p className="text-gray-300 text-sm leading-relaxed">
            Lakebase (Postgres-compatible) manages user registration, JWT token issuance,
            and session state. The AppKit app connects via the <code className="text-[var(--dbx-orange)] bg-white/10 px-1.5 py-0.5 rounded text-xs">lakebase</code> plugin
            which handles OAuth token rotation and connection pooling automatically.
            The ZeroBus service principal credentials are stored in a Databricks secret scope,
            separate from user-facing auth.
          </p>
        </div>
      </div>
    </section>
  );
}

/* ── Record Types ─────────────────────────────────────────────────── */
function RecordTypesSection() {
  const types = [
    { type: 'samples', icon: Heart, desc: 'Quantity/category samples — step count, heart rate, distance, energy burned, VO2 max, SpO2, stand hours, and more', color: 'bg-red-500' },
    { type: 'workouts', icon: Footprints, desc: 'Workout sessions with activity type, duration, energy burned, and distance (70+ activity types supported)', color: 'bg-blue-500' },
    { type: 'sleep', icon: Moon, desc: 'Sleep sessions grouped from contiguous sleep stage samples — inBed, asleepCore, asleepDeep, asleepREM, awake', color: 'bg-indigo-500' },
    { type: 'activity_summaries', icon: Flame, desc: 'Daily Apple Activity ring data — active energy, exercise minutes, stand hours with goals', color: 'bg-orange-500' },
    { type: 'deletes', icon: Trash2, desc: 'Lightweight deletion records (UUID + sample type) for soft-delete matching on the backend', color: 'bg-gray-500' },
  ];

  return (
    <section className="py-20 px-6 bg-[var(--muted)]">
      <div className="max-w-5xl mx-auto">
        <SectionHeader
          label="Data Model"
          title="HealthKit Record Types"
          subtitle="Five record types sent via the X-Record-Type header. Unknown types are accepted but logged."
        />

        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4 mt-12">
          {types.map((t) => (
            <div key={t.type} className="bg-[var(--card)] border border-[var(--border)] rounded-xl p-5 hover:shadow-md transition-shadow">
              <div className="flex items-center gap-3 mb-3">
                <div className={`${t.color} w-10 h-10 rounded-lg flex items-center justify-center`}>
                  <t.icon className="h-5 w-5 text-white" />
                </div>
                <code className="text-sm font-mono font-bold text-[var(--foreground)]">{t.type}</code>
              </div>
              <p className="text-xs text-[var(--muted-foreground)] leading-relaxed">{t.desc}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

/* ── Medallion Architecture ───────────────────────────────────────── */
function MedallionSection() {
  const layers = [
    {
      name: 'Bronze',
      color: 'bg-amber-700',
      border: 'border-amber-600',
      desc: 'Raw ingested data. Full HealthKit JSON body as VARIANT. HTTP headers preserved in separate VARIANT column. Schema-on-read — no structure imposed at ingestion.',
      table: 'wearables_zerobus',
    },
    {
      name: 'Silver',
      color: 'bg-gray-400',
      border: 'border-gray-400',
      desc: 'Cleaned, validated, deduplicated records. VARIANT exploded into typed columns. Deduplication by record UUID. Data quality expectations enforced.',
      table: 'silver_*',
    },
    {
      name: 'Gold',
      color: 'bg-yellow-500',
      border: 'border-yellow-500',
      desc: 'Business-level aggregations ready for AI/BI dashboards. Daily activity summaries, weekly trends, health score composites.',
      table: 'gold_*',
    },
  ];

  return (
    <section className="py-20 px-6 bg-[var(--background)]">
      <div className="max-w-5xl mx-auto">
        <SectionHeader
          label="Data Architecture"
          title="Medallion Architecture"
          subtitle="Progressive data refinement from raw ingestion to business analytics."
        />

        <div className="grid md:grid-cols-3 gap-6 mt-12">
          {layers.map((layer, i) => (
            <div key={i} className={`bg-[var(--card)] border-t-4 ${layer.border} border border-[var(--border)] rounded-xl p-6`}>
              <div className="flex items-center gap-3 mb-4">
                <div className={`${layer.color} w-10 h-10 rounded-lg flex items-center justify-center`}>
                  <BarChart3 className="h-5 w-5 text-white" />
                </div>
                <div>
                  <h3 className="font-bold text-[var(--foreground)]">{layer.name}</h3>
                  <code className="text-xs text-[var(--muted-foreground)]">{layer.table}</code>
                </div>
              </div>
              <p className="text-sm text-[var(--muted-foreground)] leading-relaxed">{layer.desc}</p>
            </div>
          ))}
        </div>

        {/* Unity Catalog badge */}
        <div className="mt-8 flex justify-center">
          <div className="inline-flex items-center gap-3 px-5 py-3 rounded-xl bg-[var(--muted)] border border-[var(--border)]">
            <img src="/images/unity-catalog-lockup-no-db-full-color.svg" alt="Unity Catalog" className="h-6" />
            <span className="text-xs text-[var(--muted-foreground)]">All tables governed by Unity Catalog</span>
          </div>
        </div>
      </div>
    </section>
  );
}

/* ── Shared Section Header ────────────────────────────────────────── */
function SectionHeader({
  label,
  title,
  subtitle,
}: {
  label: string;
  title: string;
  subtitle: string;
}) {
  return (
    <div className="text-center mb-4">
      <span className="inline-block text-xs font-bold uppercase tracking-widest text-[var(--dbx-red)] mb-2">
        {label}
      </span>
      <h2 className="text-3xl font-bold text-[var(--foreground)] mb-3">{title}</h2>
      <p className="text-[var(--muted-foreground)] max-w-2xl mx-auto">{subtitle}</p>
    </div>
  );
}
