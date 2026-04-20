import {
  ArrowRight,
  Footprints,
  Moon,
  Flame,
  Trash2,
} from 'lucide-react';
import { BrandIcon } from '@/components/BrandIcon';
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
              <BrandIcon name="spark-streaming" className="h-4 w-4 text-[var(--dbx-lava-500)]" />
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
                className="gradient-red text-white px-6 py-3 rounded-lg font-semibold text-sm shadow-lg shadow-[var(--dbx-lava-600)]/30 hover:shadow-[var(--dbx-lava-600)]/50 transition-all"
              >
                View API Docs
              </Link>
              <Link
                to="/status"
                className="bg-white/10 border border-white/20 text-white px-6 py-3 rounded-lg font-semibold text-sm hover:bg-white/20 transition-all"
              >
                System Health
              </Link>
              <Link
                to="/security"
                className="bg-white/10 border border-white/20 text-white px-6 py-3 rounded-lg font-semibold text-sm hover:bg-white/20 transition-all"
              >
                Security Design
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
      brandKey: 'iot' as const,
      title: 'Apple HealthKit',
      subtitle: 'Data Source',
      desc: 'Apple Watch and Health app collect activity, workouts, sleep, and vitals. The iOS app reads data via anchored HealthKit queries.',
      logo: null as string | null,
      logoDark: null as string | null,
    },
    {
      brandKey: 'smartphone' as const,
      title: 'iOS App',
      subtitle: 'NDJSON Serializer',
      desc: 'SwiftUI app maps HKSamples to Codable structs, serializes as NDJSON, and POSTs batches with X-Record-Type headers.',
      logo: null as string | null,
      logoDark: null as string | null,
    },
    {
      brandKey: null,
      title: 'AppKit Gateway',
      subtitle: 'REST API',
      desc: 'Express server receives NDJSON payloads, validates headers, extracts user identity, and forwards to the ZeroBus SDK.',
      logo: '/images/apps-lockup-no-db-full-color.svg',
      logoDark: '/images/apps-lockup-no-db-full-color-white-container.svg',
    },
    {
      brandKey: null,
      title: 'ZeroBus',
      subtitle: 'Stream Bridge',
      desc: 'Streams records into Unity Catalog bronze table with no external infrastructure. Decouples API from table writes.',
      logo: '/images/data-streaming-icon-full-color-container.svg',
      logoDark: '/images/data-streaming-icon-full-color-container.svg',
    },
    {
      brandKey: null,
      title: 'Unity Catalog',
      subtitle: 'Bronze Table',
      desc: 'Raw NDJSON stored as VARIANT column. Full HTTP headers preserved. Schema-on-read for maximum flexibility.',
      logo: '/images/unity-catalog-lockup-no-db-full-color.svg',
      logoDark: '/images/unity-catalog-lockup-no-db-full-color-white.svg',
    },
    {
      brandKey: null,
      title: 'SDP Pipeline',
      subtitle: 'Silver → Gold',
      desc: 'Spark Declarative Pipelines read bronze, clean and validate to silver, aggregate to gold for analytics.',
      logo: '/images/apache-spark-logo-black-rgb.svg',
      logoDark: '/images/apache-spark-logo-white-rgb.svg',
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

                {/* Logo — product lockup or brand icon (no box) */}
                <div className="mb-4 h-10 flex items-center">
                  {step.logo ? (
                    <>
                      <img src={step.logo} alt={step.title} className="h-8 block dark:hidden" />
                      <img src={step.logoDark ?? step.logo} alt={step.title} className="h-8 hidden dark:block" />
                    </>
                  ) : step.brandKey ? (
                    <BrandIcon name={step.brandKey as any} className="h-8 w-8 invert dark:invert-0" />
                  ) : null}
                </div>

                <h3 className="text-lg font-bold text-[var(--foreground)]">
                  {step.title}
                </h3>
                <p className="text-xs font-medium text-[var(--dbx-lava-600)] uppercase tracking-wider mb-2">
                  {step.subtitle}
                </p>
                <p className="text-sm text-[var(--muted-foreground)] leading-relaxed">
                  {step.desc}
                </p>

                {/* Arrow connector — centered in grid gap, aligned with logo row */}
                {i < steps.length - 1 && (i + 1) % 3 !== 0 && (
                  <div className="hidden lg:flex items-center justify-center absolute left-full top-10 z-10 w-6 h-6">
                    <ArrowRight className="h-5 w-5 text-[var(--dbx-lava-600)]" />
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
                  <div className="mt-1 w-5 h-5 rounded-full bg-[var(--dbx-green-600)] flex items-center justify-center flex-shrink-0">
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
                <img src="/images/apps-lockup-no-db-full-color.svg" alt="AppKit" className="h-5" />
              </div>
              <div className="flex items-center gap-2">
                <img src="/images/data-streaming-lockup-no-db-full-color-white.svg" alt="ZeroBus" className="h-5" />
              </div>
              <div className="flex items-center gap-2">
                <img src="/images/unity-catalog-lockup-no-db-full-color-white.svg" alt="Unity Catalog" className="h-5" />
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

/* ── Record Types ─────────────────────────────────────────────────── */
function RecordTypesSection() {
  const types = [
    { type: 'samples', brandKey: 'human' as const, desc: 'Quantity/category samples — step count, heart rate, distance, energy burned, VO2 max, SpO2, stand hours, and more', color: 'bg-red-500' },
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
                  {'brandKey' in t
                    ? <BrandIcon name={(t as any).brandKey} className="h-5 w-5" />
                    : <t.icon className="h-5 w-5 text-white" />
                  }
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
                  <BrandIcon name="analytics" className="h-5 w-5 text-white" />
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
            <img src="/images/unity-catalog-lockup-no-db-full-color-white.svg" alt="Unity Catalog" className="h-6" />
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
      <span className="inline-block text-xs font-bold uppercase tracking-widest text-[var(--dbx-lava-600)] mb-2">
        {label}
      </span>
      <h2 className="text-3xl font-bold text-[var(--foreground)] mb-3">{title}</h2>
      <p className="text-[var(--muted-foreground)] max-w-2xl mx-auto">{subtitle}</p>
    </div>
  );
}
