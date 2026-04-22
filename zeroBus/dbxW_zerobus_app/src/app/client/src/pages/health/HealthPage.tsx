import { useState, useEffect, useCallback } from 'react';
import {
  CheckCircle2,
  XCircle,
  AlertTriangle,
  RefreshCw,
  Clock,
  Zap,
  Radio,
} from 'lucide-react';
import { BrandIcon } from '@/components/BrandIcon';
import type { IconKey } from '@/icons';

/* ═════════════════════════════════════════════════════════════════
   HealthPage — System health dashboard
   Checks: API health, Lakebase, ZeroBus stream, env configuration
   ═════════════════════════════════════════════════════════════════ */

type CheckStatus = 'idle' | 'loading' | 'ok' | 'warning' | 'error';

interface StreamPoolState {
  pool_size: number;
  active_streams: number;
  initialized: boolean;
  inflight_requests: number;
  draining: boolean;
  auto_scale?: {
    enabled: boolean;
    min_size: number;
    max_size: number;
  };
}

interface HealthCheck {
  id: string;
  name: string;
  description: string;
  brandKey: IconKey;
  status: CheckStatus;
  message: string;
  details?: Record<string, unknown>;
  streamPool?: StreamPoolState;
  latencyMs?: number;
}

export function HealthPage() {
  const [checks, setChecks] = useState<HealthCheck[]>(initialChecks());
  const [lastRefresh, setLastRefresh] = useState<Date | null>(null);
  const [isRefreshing, setIsRefreshing] = useState(false);

  const runChecks = useCallback(async () => {
    setIsRefreshing(true);
    const updated = await Promise.all(
      checks.map((check) => runSingleCheck(check))
    );
    setChecks(updated);
    setLastRefresh(new Date());
    setIsRefreshing(false);
  }, [checks]);

  useEffect(() => {
    runChecks();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const overallStatus = checks.every((c) => c.status === 'ok')
    ? 'ok'
    : checks.some((c) => c.status === 'error')
      ? 'error'
      : checks.some((c) => c.status === 'loading' || c.status === 'idle')
        ? 'loading'
        : 'warning';

  return (
    <div className="max-w-5xl mx-auto py-12 px-6">
      {/* Header */}
      <div className="flex items-center justify-between mb-8">
        <div>
          <h1 className="text-3xl font-bold text-[var(--foreground)] flex items-center gap-3">
            <img src="/images/apps-lockup-no-db-full-color.svg" alt="Databricks Apps" className="h-8" />
            System Health
          </h1>
          <p className="text-[var(--muted-foreground)] mt-1">
            Real-time status of all gateway components
          </p>
        </div>
        <button
          onClick={runChecks}
          disabled={isRefreshing}
          className="flex items-center gap-2 px-4 py-2.5 rounded-lg gradient-red text-white text-sm font-medium shadow-md shadow-[var(--dbx-lava-600)]/20 hover:shadow-[var(--dbx-lava-600)]/40 transition-all disabled:opacity-60"
        >
          <RefreshCw className={`h-4 w-4 ${isRefreshing ? 'animate-spin' : ''}`} />
          Refresh
        </button>
      </div>

      {/* Overall status banner */}
      <OverallBanner status={overallStatus} lastRefresh={lastRefresh} />

      {/* Individual checks */}
      <div className="grid gap-4 mt-8">
        {checks.map((check) => (
          <HealthCheckCard key={check.id} check={check} />
        ))}
      </div>

      {/* Environment info */}
      <EnvInfoSection />
    </div>
  );
}

/* ── Overall banner ─────────────────────────────────────────────────────────── */
function OverallBanner({
  status,
  lastRefresh,
}: {
  status: CheckStatus;
  lastRefresh: Date | null;
}) {
  const config = {
    ok: {
      bg: 'bg-emerald-50 border-emerald-200',
      icon: CheckCircle2,
      iconColor: 'text-[var(--dbx-green-600)]',
      text: 'All Systems Operational',
      pulse: 'status-pulse',
    },
    warning: {
      bg: 'bg-amber-50 border-amber-200',
      icon: AlertTriangle,
      iconColor: 'text-amber-500',
      text: 'Degraded Performance',
      pulse: '',
    },
    error: {
      bg: 'bg-red-50 border-red-200',
      icon: XCircle,
      iconColor: 'text-red-500',
      text: 'System Issues Detected',
      pulse: '',
    },
    loading: {
      bg: 'bg-blue-50 border-blue-200',
      icon: RefreshCw,
      iconColor: 'text-blue-500 animate-spin',
      text: 'Checking Systems...',
      pulse: '',
    },
    idle: {
      bg: 'bg-gray-50 border-gray-200',
      icon: Clock,
      iconColor: 'text-gray-400',
      text: 'Waiting...',
      pulse: '',
    },
  }[status];

  const Icon = config.icon;

  return (
    <div className={`${config.bg} border rounded-xl p-5 flex items-center justify-between`}>
      <div className="flex items-center gap-4">
        <div className={`w-4 h-4 rounded-full ${status === 'ok' ? 'bg-[var(--dbx-green-600)]' : status === 'error' ? 'bg-red-500' : status === 'warning' ? 'bg-amber-500' : 'bg-blue-400'} ${config.pulse}`} />
        <Icon className={`h-6 w-6 ${config.iconColor}`} />
        <span className="font-bold text-[var(--foreground)] text-lg">{config.text}</span>
      </div>
      {lastRefresh && (
        <span className="text-xs text-[var(--muted-foreground)] flex items-center gap-1">
          <Clock className="h-3 w-3" />
          Last checked: {lastRefresh.toLocaleTimeString()}
        </span>
      )}
    </div>
  );
}

/* ── Individual health check card ─────────────────────────────────────────── */
function HealthCheckCard({ check }: { check: HealthCheck }) {
  const statusConfig = {
    ok: { icon: CheckCircle2, color: 'text-[var(--dbx-green-600)]', badge: 'bg-emerald-50 text-[var(--dbx-green-600)]', label: 'Healthy' },
    warning: { icon: AlertTriangle, color: 'text-amber-500', badge: 'bg-amber-50 text-amber-600', label: 'Warning' },
    error: { icon: XCircle, color: 'text-red-500', badge: 'bg-red-50 text-red-600', label: 'Error' },
    loading: { icon: RefreshCw, color: 'text-blue-500 animate-spin', badge: 'bg-blue-50 text-blue-500', label: 'Checking' },
    idle: { icon: Clock, color: 'text-gray-400', badge: 'bg-gray-50 text-gray-500', label: 'Pending' },
  }[check.status];

  const StatusIcon = statusConfig.icon;

  return (
    <div className="bg-[var(--card)] border border-[var(--border)] rounded-xl p-5 flex items-start gap-5 hover:shadow-md transition-shadow">
      {/* Component icon */}
      <div className="w-12 h-12 rounded-xl bg-[var(--dbx-navy-800)] flex items-center justify-center flex-shrink-0">
        <BrandIcon name={check.brandKey} className="h-6 w-6" />
      </div>

      {/* Info */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-3 mb-1">
          <h3 className="font-bold text-[var(--foreground)]">{check.name}</h3>
          <span className={`text-xs font-medium px-2.5 py-0.5 rounded-full ${statusConfig.badge}`}>
            {statusConfig.label}
          </span>
          {check.latencyMs !== undefined && check.status !== 'loading' && check.status !== 'idle' && (
            <span className="text-xs text-[var(--muted-foreground)] font-mono">
              {check.latencyMs}ms
            </span>
          )}
        </div>
        <p className="text-xs text-[var(--muted-foreground)] mb-1">{check.description}</p>
        <p className="text-sm text-[var(--foreground)]">{check.message}</p>

        {/* Details */}
        {check.details && Object.keys(check.details).length > 0 && (
          <div className="mt-3 bg-[var(--muted)] rounded-lg p-3 overflow-hidden">
            <div className="grid grid-cols-2 gap-x-6 gap-y-1 text-xs">
              {Object.entries(check.details).map(([k, v]) => (
                <div key={k} className="flex justify-between gap-3 min-w-0">
                  <span className="text-[var(--muted-foreground)] font-mono flex-shrink-0">{k}</span>
                  <span className="text-[var(--foreground)] font-medium truncate" title={String(v)}>{String(v)}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Stream Pool Section */}
        {check.streamPool && <StreamPoolSection pool={check.streamPool} />}
      </div>

      {/* Status icon */}
      <StatusIcon className={`h-6 w-6 flex-shrink-0 ${statusConfig.color}`} />
    </div>
  );
}

/* ── Stream Pool Status Section ───────────────────────────────────────────── */
function StreamPoolSection({ pool }: { pool: StreamPoolState }) {
  const isActive = pool.initialized && pool.active_streams > 0;
  const isIdle = pool.initialized && pool.active_streams === 0;
  const isWaiting = !pool.initialized;
  const isDraining = pool.draining;

  // Determine overall pool status for header badge
  let statusLabel: string;
  let statusBg: string;
  let statusIcon: typeof Zap;
  if (isDraining) {
    statusLabel = 'Draining';
    statusBg = 'bg-amber-100 text-amber-700';
    statusIcon = AlertTriangle;
  } else if (isActive) {
    statusLabel = 'Streaming';
    statusBg = 'bg-emerald-100 text-emerald-700';
    statusIcon = Zap;
  } else if (isIdle) {
    statusLabel = 'Idle';
    statusBg = 'bg-blue-100 text-blue-700';
    statusIcon = Radio;
  } else {
    statusLabel = 'Waiting for first request';
    statusBg = 'bg-gray-100 text-gray-600';
    statusIcon = Clock;
  }
  const PoolStatusIcon = statusIcon;

  return (
    <div className="mt-3 border border-[var(--border)] rounded-lg overflow-hidden">
      {/* Header */}
      <div className="bg-[var(--dbx-navy-800)] px-4 py-2.5 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <BrandIcon name="spark-streaming" className="h-4 w-4" />
          <span className="text-xs font-bold text-white uppercase tracking-wider">
            ZeroBus Stream Pool
          </span>
        </div>
        <div className="flex items-center gap-2">
          <span className={`text-xs font-medium px-2 py-0.5 rounded-full flex items-center gap-1 ${statusBg}`}>
            <PoolStatusIcon className="h-3 w-3" />
            {statusLabel}
          </span>
        </div>
      </div>

      {/* Metrics grid */}
      <div className="bg-[var(--muted)] p-3">
        <div className="grid grid-cols-3 gap-3">
          {/* Active Streams — primary metric */}
          <div className="bg-[var(--card)] rounded-lg p-3 text-center border border-[var(--border)]">
            <div className="flex items-center justify-center gap-1.5 mb-1">
              {isActive && (
                <div className="w-2 h-2 rounded-full bg-[var(--dbx-green-600)] status-pulse" />
              )}
              <span className={`text-2xl font-bold tabular-nums ${
                isActive
                  ? 'text-[var(--dbx-green-600)]'
                  : isIdle
                    ? 'text-blue-500'
                    : 'text-[var(--muted-foreground)]'
              }`}>
                {pool.active_streams}
              </span>
              <span className="text-sm text-[var(--muted-foreground)]">/</span>
              <span className="text-sm text-[var(--muted-foreground)]">{pool.pool_size}</span>
            </div>
            <span className="text-[10px] text-[var(--muted-foreground)] uppercase tracking-wider font-medium">
              Active Streams
            </span>
          </div>

          {/* In-flight Requests */}
          <div className="bg-[var(--card)] rounded-lg p-3 text-center border border-[var(--border)]">
            <div className="text-2xl font-bold tabular-nums text-[var(--foreground)] mb-1">
              {pool.inflight_requests}
            </div>
            <span className="text-[10px] text-[var(--muted-foreground)] uppercase tracking-wider font-medium">
              In-flight
            </span>
          </div>

          {/* Pool Size (configured or auto-scale range) */}
          <div className="bg-[var(--card)] rounded-lg p-3 text-center border border-[var(--border)]">
            <div className="text-2xl font-bold tabular-nums text-[var(--foreground)] mb-1">
              {pool.pool_size}
            </div>
            <span className="text-[10px] text-[var(--muted-foreground)] uppercase tracking-wider font-medium">
              {pool.auto_scale?.enabled
                ? `Pool (${pool.auto_scale.min_size}–${pool.auto_scale.max_size})`
                : 'Pool Size'}
            </span>
          </div>
        </div>

        {/* Status indicators row */}
        <div className="flex items-center gap-4 mt-3 px-1">
          <StatusDot
            label="Initialized"
            active={pool.initialized}
            activeColor="bg-[var(--dbx-green-600)]"
          />
          <StatusDot
            label="Auto-scale"
            active={pool.auto_scale?.enabled ?? false}
            activeColor="bg-[var(--dbx-green-600)]"
          />
          <StatusDot
            label="Draining"
            active={pool.draining}
            activeColor="bg-amber-500"
            inactiveIsGood
          />
        </div>

        {/* Contextual hint for demos */}
        {isWaiting && (
          <div className="mt-3 bg-blue-50 border border-blue-200 rounded-lg px-3 py-2 flex items-start gap-2">
            <Clock className="h-3.5 w-3.5 text-blue-500 mt-0.5 flex-shrink-0" />
            <p className="text-xs text-blue-700 leading-relaxed">
              <strong>Lazy initialization:</strong> The stream pool starts when the first
              record is ingested, not at server startup. Send a record via the{' '}
              <a href="/docs" className="underline font-medium">Try It</a>{' '}
              panel, then refresh to see the streams activate.
            </p>
          </div>
        )}
        {isIdle && (
          <div className="mt-3 bg-blue-50 border border-blue-200 rounded-lg px-3 py-2 flex items-start gap-2">
            <Radio className="h-3.5 w-3.5 text-blue-500 mt-0.5 flex-shrink-0" />
            <p className="text-xs text-blue-700 leading-relaxed">
              <strong>Pool initialized, streams idle.</strong> The gRPC connections are
              established but no records are actively in flight. Streams will show as
              active during the next ingest request.
            </p>
          </div>
        )}
        {isActive && (
          <div className="mt-3 bg-emerald-50 border border-emerald-200 rounded-lg px-3 py-2 flex items-start gap-2">
            <Zap className="h-3.5 w-3.5 text-emerald-600 mt-0.5 flex-shrink-0" />
            <p className="text-xs text-emerald-700 leading-relaxed">
              <strong>Streams active.</strong> {pool.active_streams} persistent gRPC
              connection{pool.active_streams !== 1 ? 's' : ''} to the ZeroBus Ingest
              server. Records are written with offset-based durability.
            </p>
          </div>
        )}
        {isDraining && (
          <div className="mt-3 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2 flex items-start gap-2">
            <AlertTriangle className="h-3.5 w-3.5 text-amber-600 mt-0.5 flex-shrink-0" />
            <p className="text-xs text-amber-700 leading-relaxed">
              <strong>Graceful shutdown in progress.</strong> The pool is draining in-flight
              requests before closing streams. No new records will be accepted.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}

/* ── Status dot indicator ─────────────────────────────────────────────────── */
function StatusDot({
  label,
  active,
  activeColor,
  inactiveIsGood,
}: {
  label: string;
  active: boolean;
  activeColor: string;
  inactiveIsGood?: boolean;
}) {
  const dotColor = active
    ? activeColor
    : inactiveIsGood
      ? 'bg-[var(--dbx-green-600)]'
      : 'bg-gray-300';

  return (
    <div className="flex items-center gap-1.5">
      <div className={`w-2 h-2 rounded-full ${dotColor}`} />
      <span className="text-xs text-[var(--muted-foreground)]">
        {label}: <span className="font-medium text-[var(--foreground)]">{active ? 'Yes' : 'No'}</span>
      </span>
    </div>
  );
}

/* ── Environment info section ─────────────────────────────────────────────── */
function EnvInfoSection() {
  return (
    <div className="mt-12 bg-[var(--dbx-navy-800)] rounded-xl p-6 text-white">
      <h3 className="font-bold text-lg mb-4 flex items-center gap-2">
        <img src="/images/databricks-symbol-light.svg" alt="" className="h-5 w-5" />
        Environment Configuration
      </h3>
      <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4 text-sm">
        {[
          { label: 'Runtime', value: 'Databricks AppKit' },
          { label: 'Server', value: 'Express + TypeScript' },
          { label: 'Client', value: 'React + Vite + Tailwind' },
          { label: 'Stream', value: 'ZeroBus Ingest SDK' },
          { label: 'Database', value: 'Lakebase (Postgres)' },
          { label: 'Catalog', value: 'Unity Catalog' },
        ].map((item) => (
          <div key={item.label} className="bg-white/5 rounded-lg p-3 border border-white/10">
            <span className="text-gray-400 text-xs block">{item.label}</span>
            <span className="font-medium">{item.value}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

/* ── Initial check definitions ────────────────────────────────────────────── */
function initialChecks(): HealthCheck[] {
  return [
    {
      id: 'api-health',
      name: 'API Health Endpoint',
      description: 'GET /api/v1/healthkit/health — Verifies the Express server and ZeroBus configuration.',
      brandKey: 'webhook',
      status: 'idle',
      message: 'Waiting to check...',
    },
    {
      id: 'api-ingest',
      name: 'Ingest Endpoint',
      description: 'POST /api/v1/healthkit/ingest — Validates the ingestion endpoint is reachable.',
      brandKey: 'streaming',
      status: 'idle',
      message: 'Waiting to check...',
    },
    {
      id: 'lakebase',
      name: 'Lakebase Database',
      description: 'GET /api/lakebase/health — Postgres-compatible operational database for user auth and app state.',
      brandKey: 'delta-table',
      status: 'idle',
      message: 'Waiting to check...',
    },
  ];
}

/* ── Run a single health check ────────────────────────────────────────────── */
async function runSingleCheck(check: HealthCheck): Promise<HealthCheck> {
  const start = performance.now();

  try {
    switch (check.id) {
      case 'api-health': {
        const res = await fetch('/api/v1/healthkit/health', { signal: AbortSignal.timeout(10000) });
        const latencyMs = Math.round(performance.now() - start);
        if (!res.ok) {
          return {
            ...check,
            status: 'error',
            message: `HTTP ${res.status} — endpoint returned an error`,
            latencyMs,
          };
        }
        const data = await res.json();
        const pool: StreamPoolState | undefined = data.stream_pool
          ? {
              pool_size: data.stream_pool.pool_size ?? 0,
              active_streams: data.stream_pool.active_streams ?? 0,
              initialized: data.stream_pool.initialized ?? false,
              inflight_requests: data.stream_pool.inflight_requests ?? 0,
              draining: data.stream_pool.draining ?? false,
              auto_scale: data.stream_pool.auto_scale ?? undefined,
            }
          : undefined;

        // Build message based on pool state
        let message: string;
        if (!data.env_configured) {
          message = `Missing env vars: ${data.missing_env_vars?.join(', ') || 'unknown'}`;
        } else if (pool?.draining) {
          message = 'ZeroBus stream pool is draining — graceful shutdown in progress';
        } else if (pool?.initialized && pool.active_streams > 0) {
          message = `ZeroBus streaming — ${pool.active_streams}/${pool.pool_size} gRPC streams active`;
        } else if (pool?.initialized) {
          message = `ZeroBus initialized — ${pool.pool_size} streams ready, idle (no active ingest)`;
        } else if (pool) {
          message = 'ZeroBus configured — stream pool starts on first ingest request';
        } else {
          message = 'ZeroBus environment fully configured and ready';
        }

        return {
          ...check,
          status: data.env_configured ? 'ok' : 'warning',
          message,
          details: {
            service: data.service,
            target_table: data.target_table,
            env_configured: String(data.env_configured),
          },
          streamPool: pool,
          latencyMs,
        };
      }

      case 'api-ingest': {
        // OPTIONS/HEAD check — don't actually ingest
        const res = await fetch('/api/v1/healthkit/ingest', {
          method: 'POST',
          headers: { 'Content-Type': 'text/plain' },
          body: '', // Empty body → should return 400 (expected)
          signal: AbortSignal.timeout(10000),
        });
        const latencyMs = Math.round(performance.now() - start);
        // A 400 means the endpoint is alive but rejected empty body — that's OK
        if (res.status === 400) {
          return {
            ...check,
            status: 'ok',
            message: 'Endpoint reachable and validating requests correctly',
            details: { response_code: '400 (expected for empty body)' },
            latencyMs,
          };
        }
        if (res.ok) {
          return { ...check, status: 'ok', message: 'Endpoint reachable', latencyMs };
        }
        return {
          ...check,
          status: 'error',
          message: `Unexpected response: HTTP ${res.status}`,
          latencyMs,
        };
      }

      case 'lakebase': {
        // Dedicated Lakebase health probe — runs SELECT 1 on Postgres
        const res = await fetch('/api/lakebase/health', { signal: AbortSignal.timeout(10000) });
        const latencyMs = Math.round(performance.now() - start);
        if (res.ok) {
          const data = await res.json();
          return {
            ...check,
            status: 'ok',
            message: 'Lakebase connection healthy — Postgres queries succeeding',
            details: { pg_latency_ms: `${data.latency_ms ?? '—'}ms` },
            latencyMs,
          };
        }
        // 503 = server returned a structured error from the health endpoint
        if (res.status === 503) {
          const data = await res.json().catch(() => ({}));
          return {
            ...check,
            status: 'error',
            message: `Lakebase connection failed: ${data.message || 'unknown error'}`,
            latencyMs,
          };
        }
        return {
          ...check,
          status: 'warning',
          message: `Lakebase returned HTTP ${res.status} — connection may be degraded`,
          latencyMs,
        };
      }

      default:
        return { ...check, status: 'warning', message: 'Unknown check type' };
    }
  } catch (err) {
    const latencyMs = Math.round(performance.now() - start);
    const message = err instanceof Error ? err.message : String(err);
    return {
      ...check,
      status: 'error',
      message: `Connection failed: ${message}`,
      latencyMs,
    };
  }
}
