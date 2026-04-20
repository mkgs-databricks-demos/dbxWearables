import { useState, useEffect, useCallback } from 'react';
import {
  CheckCircle2,
  XCircle,
  AlertTriangle,
  RefreshCw,
  Clock,
} from 'lucide-react';
import { BrandIcon } from '@/components/BrandIcon';
import type { IconKey } from '@/icons';

/* ═════════════════════════════════════════════════════════════════
   HealthPage — System health dashboard
   Checks: API health, Lakebase, ZeroBus stream, env configuration
   ═════════════════════════════════════════════════════════════════ */

type CheckStatus = 'idle' | 'loading' | 'ok' | 'warning' | 'error';

interface HealthCheck {
  id: string;
  name: string;
  description: string;
  brandKey: IconKey;
  status: CheckStatus;
  message: string;
  details?: Record<string, unknown>;
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

/* ── Overall banner ───────────────────────────────────────────────────── */
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

/* ── Individual health check card ─────────────────────────────────────── */
function HealthCheckCard({ check }: { check: HealthCheck }) {
  const statusConfig = {
    ok: { icon: CheckCircle2, color: 'text-[var(--dbx-green-600)]', badge: 'bg-emerald-50 text-[var(--dbx-green-600)]', label: 'Healthy' },
    warning: { icon: AlertTriangle, color: 'text-amber-500', badge: 'bg-amber-50 text-amber-600', label: 'Warning' },
    error: { icon: XCircle, color: 'text-red-500', badge: 'bg-red-50 text-red-600', label: 'Error' },
    loading: { icon: RefreshCw, color: 'text-blue-500 animate-spin', badge: 'bg-blue-50 text-blue-500', label: 'Checking' },
    idle: { icon: Clock, color: 'text-gray-400', badge: 'bg-gray-50 text-gray-500', label: 'Pending' },
  }[check.status];

  const StatusIcon = statusConfig.icon;
  // Brand icon from registry

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
          <div className="mt-3 bg-[var(--muted)] rounded-lg p-3">
            <div className="grid grid-cols-2 gap-x-6 gap-y-1 text-xs">
              {Object.entries(check.details).map(([k, v]) => (
                <div key={k} className="flex justify-between">
                  <span className="text-[var(--muted-foreground)] font-mono">{k}</span>
                  <span className="text-[var(--foreground)] font-medium">{String(v)}</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>

      {/* Status icon */}
      <StatusIcon className={`h-6 w-6 flex-shrink-0 ${statusConfig.color}`} />
    </div>
  );
}

/* ── Environment info section ─────────────────────────────────────────── */
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

/* ── Initial check definitions ────────────────────────────────────────── */
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

/* ── Run a single health check ────────────────────────────────────────── */
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
        return {
          ...check,
          status: data.env_configured ? 'ok' : 'warning',
          message: data.env_configured
            ? 'ZeroBus environment fully configured and ready'
            : `Missing env vars: ${data.missing_env_vars?.join(', ') || 'unknown'}`,
          details: {
            service: data.service,
            target_table: data.target_table,
            env_configured: String(data.env_configured),
          },
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
