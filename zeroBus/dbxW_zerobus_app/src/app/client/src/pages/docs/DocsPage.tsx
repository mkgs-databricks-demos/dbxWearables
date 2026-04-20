import { useState } from 'react';
import {
  Copy,
  Check,
  ChevronDown,
  ChevronRight,
  Send,
  ArrowUpRight,
  Tag,
  AlertCircle,
} from 'lucide-react';

/* ═══════════════════════════════════════════════════════════════════
   DocsPage — API Documentation (Swagger-style)
   Interactive docs for POST /api/v1/healthkit/ingest and
   GET /api/v1/healthkit/health
   ═══════════════════════════════════════════════════════════════════ */

export function DocsPage() {
  return (
    <div className="max-w-5xl mx-auto py-12 px-6">
      {/* Header */}
      <div className="mb-10">
        <div className="flex items-center gap-3 mb-2">
          <img src="/images/databricks-symbol-color.svg" alt="" className="h-8 w-8" />
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

/* ── POST /api/v1/healthkit/ingest ────────────────────────────────── */
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
            and streams each record to the Unity Catalog bronze table via the ZeroBus REST API.
            Each line in the NDJSON body becomes a separate record in the bronze table.
          </p>

          {/* Headers */}
          <div>
            <h4 className="font-bold text-sm text-[var(--foreground)] mb-3 flex items-center gap-2">
              <Tag className="h-4 w-4 text-[var(--dbx-red)]" />
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
              className="flex items-center gap-2 text-sm font-medium text-[var(--dbx-red)] hover:text-[var(--dbx-lava-500)] transition-colors"
            >
              <Send className="h-4 w-4" />
              Try it out
              {tryItOpen ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
            </button>
            {tryItOpen && <TryItPanel />}
          </div>

          {/* cURL example */}
          <div>
            <h4 className="font-bold text-sm text-[var(--foreground)] mb-3 flex items-center gap-2">
              <ArrowUpRight className="h-4 w-4 text-[var(--dbx-red)]" />
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

/* ── GET /api/v1/healthkit/health ─────────────────────────────────── */
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
            target table name, and lists any missing environment variables.
          </p>

          <div>
            <h4 className="font-bold text-sm text-[var(--foreground)] mb-3">Response</h4>
            <CodeBlock
              title="200 OK"
              code={`{
  "status": "ok",
  "service": "zerobus-healthkit-ingest",
  "env_configured": true,
  "target_table": "hls_fde.wearables.wearables_zerobus"
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
              <ArrowUpRight className="h-4 w-4 text-[var(--dbx-red)]" />
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

/* ── Try It Panel ─────────────────────────────────────────────────── */
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
        <Send className="h-4 w-4" />
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

/* ── Record Types Reference ───────────────────────────────────────── */
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

/* ── Error Codes Reference ────────────────────────────────────────── */
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
              ['500', 'ZeroBus SDK failure', 'Ingestion failed: stream write error'],
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

/* ── Shared components ────────────────────────────────────────────── */
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
