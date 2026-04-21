import { useState } from 'react';
import {
  Copy,
  Check,
  ChevronDown,
  ChevronRight,
  ArrowUpRight,
  Tag,
  AlertCircle,
} from 'lucide-react';
import { BrandIcon } from '@/components/BrandIcon';

/* ═════════════════════════════════════════════════════════════════
   DocsPage — API Documentation (Swagger-style)
   Interactive docs for POST /api/v1/healthkit/ingest and
   GET /api/v1/healthkit/health
   ═════════════════════════════════════════════════════════════════ */

export function DocsPage() {
  return (
    <div className="max-w-5xl mx-auto py-12 px-6">
      {/* Header */}
      <div className="mb-10">
        <div className="flex items-center gap-3 mb-2">
          <img src="/images/apps-lockup-no-db-full-color.svg" alt="Databricks Apps" className="h-8" />
          <h1 className="text-3xl font-bold text-[var(--foreground)]">API Documentation</h1>
        </div>
        <p className="text-[var(--muted-foreground)]">
          REST API reference for the dbxWearables ZeroBus Health Data Gateway.
        </p>
        <div className="flex items-center gap-4 mt-4 text-sm">
          <span className="bg-[var(--dbx-green-600)]/10 text-[var(--dbx-green-600)] px-3 py-1 rounded-full font-medium">
            v1.0
          </span>
          <span className="text-[var(--muted-foreground)]">
            Base URL: <code className="bg-[var(--muted)] px-2 py-0.5 rounded text-xs font-mono">/api/v1</code>
          </span>
        </div>
      </div>

      {/* Streaming Architecture */}
      <StreamingArchitecture />

      {/* Endpoints */}
      <div className="space-y-6">
        <IngestEndpoint />
        <HealthEndpoint />
      </div>

      {/* Record types reference */}
      <RecordTypesRef />

      {/* Error codes */}
      <ErrorCodesRef />
    </div>
  );
}


/* ── Streaming Architecture Panel ─────────────────────────────────────── */
function StreamingArchitecture() {
  const [expanded, setExpanded] = useState(false);

  return (
    <div className="mb-8">
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full bg-[var(--dbx-navy-800)] text-white rounded-xl p-6 text-left hover:bg-[var(--dbx-navy-800)]/90 transition-colors"
      >
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-4">
            <BrandIcon name="spark-streaming" className="h-7 w-7" />
            <div>
              <h2 className="text-lg font-bold">Streaming Architecture</h2>
              <p className="text-sm text-gray-400 mt-0.5">
                ZeroBus Ingest SDK — persistent gRPC stream pool for enterprise-scale throughput
              </p>
            </div>
          </div>
          {expanded ? <ChevronDown className="h-5 w-5 text-gray-400" /> : <ChevronRight className="h-5 w-5 text-gray-400" />}
        </div>
      </button>

      {expanded && (
        <div className="bg-[var(--card)] border border-[var(--border)] border-t-0 rounded-b-xl p-6 space-y-8 -mt-3 pt-8">

          {/* How it works */}
          <div>
            <h3 className="font-bold text-[var(--foreground)] mb-3 flex items-center gap-2">
              <BrandIcon name="data-flow" className="h-4 w-4" />
              How It Works
            </h3>
            <p className="text-sm text-[var(--muted-foreground)] leading-relaxed mb-4">
              This gateway uses the{' '}
              <a href="https://github.com/databricks/zerobus-sdk" target="_blank" rel="noopener noreferrer"
                className="text-[var(--dbx-lava-600)] hover:underline font-medium">
                ZeroBus Ingest SDK
              </a>{' '}
              (<code className="bg-[var(--muted)] px-1.5 py-0.5 rounded text-xs font-mono">@databricks/zerobus-ingest-sdk</code>)
              to maintain a pool of persistent gRPC streams to the ZeroBus Ingest server. When your iOS app
              POSTs an NDJSON payload to this REST API, the server writes each record through the stream pool —
              no per-request HTTP calls to Databricks. Records are durably committed to the Unity Catalog
              bronze table with offset-based acknowledgments.
            </p>

            <div className="grid sm:grid-cols-2 gap-4">
              {[
                {
                  title: 'REST API (what you call)',
                  items: [
                    'Standard HTTP POST with NDJSON body',
                    'X-Record-Type header for routing',
                    'Synchronous response with record IDs',
                    'Works with any HTTP client (curl, iOS, etc.)',
                  ],
                },
                {
                  title: 'SDK Stream Pool (what happens inside)',
                  items: [
                    'N persistent gRPC streams (configurable)',
                    'Round-robin stream selection per request',
                    'SDK-managed OAuth token refresh',
                    'Offset-based durability (waitForOffset)',
                  ],
                },
              ].map((col) => (
                <div key={col.title} className="bg-[var(--muted)] rounded-lg p-4">
                  <h4 className="text-xs font-bold text-[var(--foreground)] uppercase tracking-wider mb-3">{col.title}</h4>
                  <ul className="space-y-2">
                    {col.items.map((item, i) => (
                      <li key={i} className="flex items-start gap-2 text-xs text-[var(--muted-foreground)]">
                        <div className="mt-1 w-1.5 h-1.5 rounded-full bg-[var(--dbx-green-600)] flex-shrink-0" />
                        {item}
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
            </div>
          </div>

          {/* Enterprise scaling */}
          <div>
            <h3 className="font-bold text-[var(--foreground)] mb-3 flex items-center gap-2">
              <BrandIcon name="spark-streaming" className="h-4 w-4" />
              Enterprise Scaling
            </h3>
            <p className="text-sm text-[var(--muted-foreground)] leading-relaxed mb-4">
              The stream pool architecture is designed for millions of concurrent iOS users.
              Each gRPC stream handles many records per second with automatic batching and
              flow control. Scaling strategy: increase the pool size to open more connections.
            </p>

            <div className="border border-[var(--border)] rounded-lg overflow-hidden">
              <table className="w-full text-sm">
                <thead className="bg-[var(--muted)]">
                  <tr>
                    <th className="text-left py-2 px-4 font-medium text-[var(--muted-foreground)]">Config</th>
                    <th className="text-left py-2 px-4 font-medium text-[var(--muted-foreground)]">Value</th>
                    <th className="text-left py-2 px-4 font-medium text-[var(--muted-foreground)]">Description</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[var(--border)]">
                  {[
                    ['Pool Size', 'ZEROBUS_STREAM_POOL_SIZE', 'Number of concurrent gRPC streams (dev=2, prod=4+)'],
                    ['Recovery', 'Automatic', 'SDK reconnects and replays unacked batches on transient failures'],
                    ['Durability', 'Offset-based', 'HTTP response sent only after server acknowledges the record'],
                    ['Auth', 'SDK-managed OAuth', 'M2M client credentials with automatic token refresh'],
                    ['Shutdown', '3-phase graceful', 'Drain gate \u2192 in-flight timeout \u2192 stream flush + close'],
                  ].map(([config, value, desc], i) => (
                    <tr key={i} className="hover:bg-[var(--muted)]/50">
                      <td className="py-2.5 px-4 text-xs font-medium text-[var(--foreground)]">{config}</td>
                      <td className="py-2.5 px-4 font-mono text-xs text-[var(--dbx-lava-500)]">{value}</td>
                      <td className="py-2.5 px-4 text-xs text-[var(--muted-foreground)]">{desc}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          {/* Current limitations */}
          <div>
            <h3 className="font-bold text-[var(--foreground)] mb-3 flex items-center gap-2">
              <AlertCircle className="h-4 w-4 text-amber-500" />
              Current Limitations &amp; Known Issues
            </h3>
            <p className="text-sm text-[var(--muted-foreground)] leading-relaxed mb-3">
              Full transparency on the current state of the SDK integration:
            </p>
            <div className="space-y-3">
              {[
                {
                  severity: 'Workaround',
                  severityColor: 'bg-amber-50 text-amber-600',
                  title: 'SDK v1.0.0 packaging bug — NAPI-RS patch required',
                  desc: 'The published npm tarball is missing index.js (the JS entry point for the native Rust binary). We vendor locally-built files and apply them via a postinstall script. This is transparent at runtime but requires a one-time local Rust build. See patches/zerobus-ingest-sdk/README.md.',
                },
                {
                  severity: 'Info',
                  severityColor: 'bg-blue-50 text-blue-600',
                  title: 'Cross-stream ordering not guaranteed',
                  desc: 'Each gRPC stream has independent ordering. Records from different HTTP requests may arrive in different order in the bronze table. This is acceptable because each iOS POST is an independent batch — ordering within a batch IS preserved.',
                },
                {
                  severity: 'Info',
                  severityColor: 'bg-blue-50 text-blue-600',
                  title: 'Lazy pool initialization',
                  desc: 'The stream pool is created on the first ingest request, not at server startup. This means the first request takes ~900ms (pool creation + gRPC handshakes). Subsequent requests are 100-200ms.',
                },
                {
                  severity: 'Planned',
                  severityColor: 'bg-gray-100 text-gray-500',
                  title: 'No dynamic pool scaling',
                  desc: 'Pool size is fixed at startup via ZEROBUS_STREAM_POOL_SIZE. Dynamic scaling based on request load is not yet implemented.',
                },
              ].map((item, i) => (
                <div key={i} className="flex items-start gap-3 bg-[var(--muted)] rounded-lg p-4">
                  <span className={`text-xs font-medium px-2 py-0.5 rounded flex-shrink-0 mt-0.5 ${item.severityColor}`}>
                    {item.severity}
                  </span>
                  <div>
                    <h4 className="text-sm font-medium text-[var(--foreground)]">{item.title}</h4>
                    <p className="text-xs text-[var(--muted-foreground)] mt-1 leading-relaxed">{item.desc}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>

        </div>
      )}
    </div>
  );
}

/* ── POST /api/v1/healthkit/ingest ────────────────────────────────────── */
function IngestEndpoint() {
  const [expanded, setExpanded] = useState(false);
  const [tryItOpen, setTryItOpen] = useState(false);

  return (
    <div className="bg-[var(--card)] border border-[var(--border)] rounded-xl overflow-hidden">
      {/* Endpoint header */}
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full flex items-center gap-4 p-5 hover:bg-[var(--muted)]/50 transition-colors"
      >
        <span className="px-3 py-1 rounded-md text-xs font-bold uppercase tracking-wider bg-[var(--dbx-green-600)] text-white">
          POST
        </span>
        <code className="text-sm font-mono font-bold text-[var(--foreground)] flex-1 text-left">
          /api/v1/healthkit/ingest
        </code>
        <span className="text-xs text-[var(--muted-foreground)]">Ingest HealthKit data via NDJSON</span>
        {expanded ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
      </button>

      {expanded && (
        <div className="border-t border-[var(--border)] p-6 space-y-6">
          <p className="text-sm text-[var(--muted-foreground)] leading-relaxed">
            Receives NDJSON (Newline Delimited JSON) payloads from the iOS HealthKit app
            and streams each record to the Unity Catalog bronze table via the ZeroBus Ingest SDK\'s persistent gRPC stream pool.
            Each line in the NDJSON body becomes a separate record in the bronze table.
          </p>

          {/* Headers */}
          <div>
            <h4 className="font-bold text-sm text-[var(--foreground)] mb-3 flex items-center gap-2">
              <Tag className="h-4 w-4 text-[var(--dbx-lava-600)]" />
              Request Headers
            </h4>
            <div className="border border-[var(--border)] rounded-lg overflow-hidden">
              <table className="w-full text-sm">
                <thead className="bg-[var(--muted)]">
                  <tr>
                    <th className="text-left py-2 px-4 font-medium text-[var(--muted-foreground)]">Header</th>
                    <th className="text-left py-2 px-4 font-medium text-[var(--muted-foreground)]">Required</th>
                    <th className="text-left py-2 px-4 font-medium text-[var(--muted-foreground)]">Description</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[var(--border)]">
                  <tr>
                    <td className="py-2.5 px-4 font-mono text-xs text-[var(--dbx-lava-500)]">Content-Type</td>
                    <td className="py-2.5 px-4"><RequiredBadge /></td>
                    <td className="py-2.5 px-4 text-xs text-[var(--muted-foreground)]">
                      <code>application/x-ndjson</code>, <code>application/ndjson</code>, or <code>text/plain</code>
                    </td>
                  </tr>
                  <tr>
                    <td className="py-2.5 px-4 font-mono text-xs text-[var(--dbx-lava-500)]">X-Record-Type</td>
                    <td className="py-2.5 px-4"><RequiredBadge /></td>
                    <td className="py-2.5 px-4 text-xs text-[var(--muted-foreground)]">
                      Any non-empty string identifying the payload type:
                      <code className="ml-1">samples</code>, <code>workouts</code>, <code>sleep</code>, <code>activity_summaries</code>, <code>deletes</code>
                    </td>
                  </tr>
                  <tr>
                    <td className="py-2.5 px-4 font-mono text-xs text-[var(--dbx-lava-500)]">X-Platform</td>
                    <td className="py-2.5 px-4"><OptionalBadge /></td>
                    <td className="py-2.5 px-4 text-xs text-[var(--muted-foreground)]">
                      Source platform identifier (e.g., <code>ios</code>, <code>android</code>). Defaults to <code>unknown</code>.
                    </td>
                  </tr>
                  <tr>
                    <td className="py-2.5 px-4 font-mono text-xs text-[var(--dbx-lava-500)]">Authorization</td>
                    <td className="py-2.5 px-4"><OptionalBadge /></td>
                    <td className="py-2.5 px-4 text-xs text-[var(--muted-foreground)]">
                      <code>Bearer &lt;JWT&gt;</code> — Direct client auth. Token&apos;s <code>sub</code> claim becomes user_id.
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          {/* Request body */}
          <div>
            <h4 className="font-bold text-sm text-[var(--foreground)] mb-3">Request Body</h4>
            <p className="text-xs text-[var(--muted-foreground)] mb-3">
              NDJSON format — one JSON object per line. Each line is parsed independently.
              Maximum 10,000 lines per request. Maximum body size: 10MB.
            </p>
            <CodeBlock
              title="Example: samples"
              code={`{"type":"HKQuantityTypeIdentifierStepCount","value":8432,"unit":"count","startDate":"2025-01-15T08:00:00Z","endDate":"2025-01-15T08:30:00Z","sourceBundle":"com.apple.health"}
{"type":"HKQuantityTypeIdentifierHeartRate","value":72,"unit":"count/min","startDate":"2025-01-15T08:15:00Z","endDate":"2025-01-15T08:15:00Z","sourceBundle":"com.apple.health"}`}
            />
          </div>

          {/* Response */}
          <div>
            <h4 className="font-bold text-sm text-[var(--foreground)] mb-3">Success Response</h4>
            <CodeBlock
              title="200 OK"
              code={`{
  "status": "success",
  "message": "2 record(s) ingested",
  "record_id": "a1b2c3d4-...",
  "records_ingested": 2,
  "record_ids": ["a1b2c3d4-...", "e5f6g7h8-..."],
  "duration_ms": 145
}`}
            />
          </div>

          {/* Try it */}
          <div>
            <button
              onClick={() => setTryItOpen(!tryItOpen)}
              className="flex items-center gap-2 text-sm font-medium text-[var(--dbx-lava-600)] hover:text-[var(--dbx-lava-500)] transition-colors"
            >
              <BrandIcon name="data-flow" className="h-4 w-4" />
              Try it out
              {tryItOpen ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
            </button>
            {tryItOpen && <TryItPanel />}
          </div>

          {/* cURL example */}
          <div>
            <h4 className="font-bold text-sm text-[var(--foreground)] mb-3 flex items-center gap-2">
              <ArrowUpRight className="h-4 w-4 text-[var(--dbx-lava-600)]" />
              cURL Example
            </h4>
            <CodeBlock
              title="bash"
              code={`curl -X POST /api/v1/healthkit/ingest \\
  -H "Content-Type: application/x-ndjson" \\
  -H "X-Record-Type: samples" \\
  -H "X-Platform: ios" \\
  -d '{"type":"HKQuantityTypeIdentifierStepCount","value":8432,"unit":"count","startDate":"2025-01-15T08:00:00Z","endDate":"2025-01-15T08:30:00Z"}'`}
            />
          </div>
        </div>
      )}
    </div>
  );
}

/* ── GET /api/v1/healthkit/health ─────────────────────────────────────── */
function HealthEndpoint() {
  const [expanded, setExpanded] = useState(false);

  return (
    <div className="bg-[var(--card)] border border-[var(--border)] rounded-xl overflow-hidden">
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full flex items-center gap-4 p-5 hover:bg-[var(--muted)]/50 transition-colors"
      >
        <span className="px-3 py-1 rounded-md text-xs font-bold uppercase tracking-wider bg-blue-500 text-white">
          GET
        </span>
        <code className="text-sm font-mono font-bold text-[var(--foreground)] flex-1 text-left">
          /api/v1/healthkit/health
        </code>
        <span className="text-xs text-[var(--muted-foreground)]">Health / readiness check</span>
        {expanded ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
      </button>

      {expanded && (
        <div className="border-t border-[var(--border)] p-6 space-y-6">
          <p className="text-sm text-[var(--muted-foreground)] leading-relaxed">
            Lightweight health and readiness check. Returns the ZeroBus configuration status,
            target table name, stream pool state, and lists any missing environment variables.
          </p>

          {/* Stream pool field reference */}
          <div>
            <h4 className="font-bold text-sm text-[var(--foreground)] mb-3 flex items-center gap-2">
              <BrandIcon name="spark-streaming" className="h-4 w-4" />
              Stream Pool Fields
            </h4>
            <div className="border border-[var(--border)] rounded-lg overflow-hidden">
              <table className="w-full text-sm">
                <thead className="bg-[var(--muted)]">
                  <tr>
                    <th className="text-left py-2 px-4 font-medium text-[var(--muted-foreground)]">Field</th>
                    <th className="text-left py-2 px-4 font-medium text-[var(--muted-foreground)]">Type</th>
                    <th className="text-left py-2 px-4 font-medium text-[var(--muted-foreground)]">Description</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[var(--border)]">
                  {[
                    ['pool_size', 'number', 'Configured number of gRPC streams (from ZEROBUS_STREAM_POOL_SIZE)'],
                    ['active_streams', 'number', 'Streams currently connected to the ZeroBus Ingest server'],
                    ['initialized', 'boolean', 'Whether the pool has been created (false until first ingest request)'],
                    ['inflight_requests', 'number', 'HTTP requests currently being processed through the pool'],
                    ['draining', 'boolean', 'True during graceful shutdown — no new requests accepted'],
                  ].map(([field, type, desc], i) => (
                    <tr key={i} className="hover:bg-[var(--muted)]/50">
                      <td className="py-2 px-4 font-mono text-xs text-[var(--dbx-lava-500)]">
                        stream_pool.{field}
                      </td>
                      <td className="py-2 px-4 text-xs">
                        <code className="bg-[var(--muted)] px-1.5 py-0.5 rounded">{type}</code>
                      </td>
                      <td className="py-2 px-4 text-xs text-[var(--muted-foreground)]">{desc}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <p className="text-xs text-[var(--muted-foreground)] mt-2 flex items-center gap-1">
              <AlertCircle className="h-3 w-3" />
              The pool uses <strong>lazy initialization</strong> — <code className="bg-[var(--muted)] px-1 py-0.5 rounded">initialized</code> is{' '}
              <code className="bg-[var(--muted)] px-1 py-0.5 rounded">false</code> and{' '}
              <code className="bg-[var(--muted)] px-1 py-0.5 rounded">active_streams</code> is{' '}
              <code className="bg-[var(--muted)] px-1 py-0.5 rounded">0</code> until the first ingest request triggers pool creation (~900ms).
              Subsequent requests are 100–200ms.
            </p>
          </div>

          <div>
            <h4 className="font-bold text-sm text-[var(--foreground)] mb-3">Response (streams active)</h4>
            <CodeBlock
              title="200 OK"
              code={`{
  "status": "ok",
  "service": "zerobus-healthkit-ingest",
  "env_configured": true,
  "target_table": "hls_fde.wearables.wearables_zerobus",
  "stream_pool": {
    "pool_size": 2,
    "active_streams": 2,
    "initialized": true,
    "inflight_requests": 0,
    "draining": false
  }
}`}
            />
          </div>

          <div>
            <h4 className="font-bold text-sm text-[var(--foreground)] mb-3">Response (before first ingest — pool not yet initialized)</h4>
            <CodeBlock
              title="200 OK"
              code={`{
  "status": "ok",
  "service": "zerobus-healthkit-ingest",
  "env_configured": true,
  "target_table": "hls_fde.wearables.wearables_zerobus",
  "stream_pool": {
    "pool_size": 2,
    "active_streams": 0,
    "initialized": false,
    "inflight_requests": 0,
    "draining": false
  }
}`}
            />
          </div>

          <div>
            <h4 className="font-bold text-sm text-[var(--foreground)] mb-3">Response (missing config)</h4>
            <CodeBlock
              title="200 OK"
              code={`{
  "status": "ok",
  "service": "zerobus-healthkit-ingest",
  "env_configured": false,
  "target_table": "(not set)",
  "missing_env_vars": ["ZEROBUS_ENDPOINT", "ZEROBUS_TARGET_TABLE"]
}`}
            />
          </div>

          <div>
            <h4 className="font-bold text-sm text-[var(--foreground)] mb-3 flex items-center gap-2">
              <ArrowUpRight className="h-4 w-4 text-[var(--dbx-lava-600)]" />
              cURL Example
            </h4>
            <CodeBlock
              title="bash"
              code={`curl -s /api/v1/healthkit/health | python3 -m json.tool`}
            />
          </div>
        </div>
      )}
    </div>
  );
}

/* ── Try It Panel ───────────────────────────────────────────────────── */
function TryItPanel() {
  const [recordType, setRecordType] = useState('samples');
  const [body, setBody] = useState(
    '{"type":"HKQuantityTypeIdentifierStepCount","value":8432,"unit":"count","startDate":"2025-01-15T08:00:00Z","endDate":"2025-01-15T08:30:00Z"}'
  );
  const [response, setResponse] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [status, setStatus] = useState<number | null>(null);

  const sendRequest = async () => {
    setLoading(true);
    setResponse(null);
    setStatus(null);
    try {
      const res = await fetch('/api/v1/healthkit/ingest', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-ndjson',
          'X-Record-Type': recordType,
          'X-Platform': 'web-docs',
        },
        body,
      });
      setStatus(res.status);
      const data = await res.json();
      setResponse(JSON.stringify(data, null, 2));
    } catch (err) {
      setResponse(String(err));
      setStatus(0);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="mt-4 bg-[var(--muted)] rounded-xl p-5 space-y-4">
      <div className="grid sm:grid-cols-2 gap-4">
        <div>
          <label className="block text-xs font-medium text-[var(--muted-foreground)] mb-1">
            X-Record-Type
          </label>
          <select
            value={recordType}
            onChange={(e) => setRecordType(e.target.value)}
            className="w-full bg-[var(--card)] border border-[var(--border)] rounded-lg px-3 py-2 text-sm font-mono text-[var(--foreground)]"
          >
            {['samples', 'workouts', 'sleep', 'activity_summaries', 'deletes'].map((t) => (
              <option key={t} value={t}>{t}</option>
            ))}
          </select>
        </div>
      </div>

      <div>
        <label className="block text-xs font-medium text-[var(--muted-foreground)] mb-1">
          Request Body (NDJSON)
        </label>
        <textarea
          value={body}
          onChange={(e) => setBody(e.target.value)}
          rows={4}
          className="w-full bg-[var(--card)] border border-[var(--border)] rounded-lg px-3 py-2 text-xs font-mono text-[var(--foreground)] resize-y"
          placeholder="One JSON object per line..."
        />
      </div>

      <button
        onClick={sendRequest}
        disabled={loading}
        className="gradient-red text-white px-5 py-2 rounded-lg text-sm font-medium shadow-md hover:shadow-lg transition-all disabled:opacity-60 flex items-center gap-2"
      >
        <BrandIcon name="data-flow" className="h-4 w-4" />
        {loading ? 'Sending...' : 'Send Request'}
      </button>

      {response && (
        <div>
          <div className="flex items-center gap-2 mb-2">
            <span className="text-xs font-medium text-[var(--muted-foreground)]">Response</span>
            <span className={`text-xs font-mono px-2 py-0.5 rounded ${
              status && status >= 200 && status < 300
                ? 'bg-emerald-50 text-[var(--dbx-green-600)]'
                : 'bg-red-50 text-red-600'
            }`}>
              {status}
            </span>
          </div>
          <div className="code-block text-xs">
            <pre>{response}</pre>
          </div>
        </div>
      )}
    </div>
  );
}

/* ── Record Types Reference ─────────────────────────────────────────── */
function RecordTypesRef() {
  return (
    <div className="mt-12">
      <h2 className="text-xl font-bold text-[var(--foreground)] mb-4">Record Types Reference</h2>
      <div className="border border-[var(--border)] rounded-xl overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-[var(--muted)]">
            <tr>
              <th className="text-left py-3 px-4 font-medium text-[var(--muted-foreground)]">X-Record-Type</th>
              <th className="text-left py-3 px-4 font-medium text-[var(--muted-foreground)]">Payload</th>
              <th className="text-left py-3 px-4 font-medium text-[var(--muted-foreground)]">Description</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--border)]">
            {[
              ['samples', 'HK quantity/category samples', 'Step count, heart rate, distance, energy burned, VO2 max, SpO2, sleep analysis, stand hours'],
              ['workouts', 'Workout records', 'Activity type, duration, energy burned, distance — 70+ activity types'],
              ['sleep', 'Sleep sessions', 'Grouped from contiguous sleep stage samples (inBed, asleepCore, asleepDeep, asleepREM, awake)'],
              ['activity_summaries', 'Daily ring data', 'Active energy, exercise minutes, stand hours with goals'],
              ['deletes', 'Deletion records', 'UUID + sample_type for soft-delete matching on backend'],
            ].map(([type, payload, desc]) => (
              <tr key={type} className="hover:bg-[var(--muted)]/50">
                <td className="py-3 px-4 font-mono text-xs text-[var(--dbx-lava-500)] font-bold">{type}</td>
                <td className="py-3 px-4 text-xs text-[var(--foreground)]">{payload}</td>
                <td className="py-3 px-4 text-xs text-[var(--muted-foreground)]">{desc}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="text-xs text-[var(--muted-foreground)] mt-2 flex items-center gap-1">
        <AlertCircle className="h-3 w-3" />
        Unknown record types are accepted and ingested but logged at warn level for visibility.
      </p>
    </div>
  );
}

/* ── Error Codes Reference ──────────────────────────────────────────── */
function ErrorCodesRef() {
  return (
    <div className="mt-10">
      <h2 className="text-xl font-bold text-[var(--foreground)] mb-4">Error Responses</h2>
      <div className="border border-[var(--border)] rounded-xl overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-[var(--muted)]">
            <tr>
              <th className="text-left py-3 px-4 font-medium text-[var(--muted-foreground)]">Status</th>
              <th className="text-left py-3 px-4 font-medium text-[var(--muted-foreground)]">Condition</th>
              <th className="text-left py-3 px-4 font-medium text-[var(--muted-foreground)]">Example Message</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--border)]">
            {[
              ['400', 'Missing X-Record-Type header', 'Missing X-Record-Type header. Provide any non-empty string...'],
              ['400', 'Empty request body', 'Request body is empty. Expected NDJSON...'],
              ['400', 'No valid JSON lines', 'No valid records found. Parse errors: Line 1: invalid JSON'],
              ['500', 'ZeroBus SDK stream failure', 'Ingestion failed: stream write error — SDK will attempt automatic recovery'],
            ].map(([code, condition, msg], i) => (
              <tr key={i} className="hover:bg-[var(--muted)]/50">
                <td className="py-3 px-4">
                  <span className={`font-mono text-xs font-bold px-2 py-0.5 rounded ${
                    code === '400' ? 'bg-amber-50 text-amber-600' : 'bg-red-50 text-red-600'
                  }`}>
                    {code}
                  </span>
                </td>
                <td className="py-3 px-4 text-xs text-[var(--foreground)]">{condition}</td>
                <td className="py-3 px-4 text-xs text-[var(--muted-foreground)] font-mono">{msg}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

/* ── Shared components ────────────────────────────────────────────────── */
function RequiredBadge() {
  return <span className="text-xs font-medium px-2 py-0.5 rounded bg-red-50 text-red-600">required</span>;
}

function OptionalBadge() {
  return <span className="text-xs font-medium px-2 py-0.5 rounded bg-gray-100 text-gray-500">optional</span>;
}

function CodeBlock({ title, code }: { title: string; code: string }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    await navigator.clipboard.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="relative">
      <div className="flex items-center justify-between bg-[#0D1117] rounded-t-lg px-4 py-2 border-b border-white/10">
        <span className="text-xs text-gray-400 font-mono">{title}</span>
        <button
          onClick={handleCopy}
          className="text-gray-400 hover:text-white transition-colors p-1"
          title="Copy to clipboard"
        >
          {copied ? <Check className="h-3.5 w-3.5 text-[var(--dbx-green-600)]" /> : <Copy className="h-3.5 w-3.5" />}
        </button>
      </div>
      <div className="code-block rounded-t-none">
        <pre className="whitespace-pre-wrap break-all">{code}</pre>
      </div>
    </div>
  );
}
