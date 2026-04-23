import { useState, useEffect, useCallback } from 'react';
import {
  History, ChevronDown, ChevronUp,
  User, ArrowUpDown, RefreshCw,
} from 'lucide-react';

/* ═════════════════════════════════════════════════════════════════
   LoadTestHistory — Historical Load Test Runs Timeline
   Fetches from GET /api/v1/testing/history and displays a sortable
   table of past load test runs with per-type breakdown.
   ═════════════════════════════════════════════════════════════════ */

// ── Types ─────────────────────────────────────────────────────────────

interface TypeResult {
  record_type: string;
  payload_count: number;
  record_count: number | null;
  duration_ms: number | null;
  records_per_sec: number | null;
}

interface HistoryRun {
  run_id: string;
  user_id: string;
  user_ip: string | null;
  started_at: string;
  completed_at: string | null;
  duration_ms: number | null;
  status: string;
  error_message: string | null;
  preset_label: string | null;
  batch_size: number;
  total_payloads: number;
  total_records: number | null;
  records_per_sec: number | null;
  pool_size_start: number | null;
  pool_size_end: number | null;
  auto_scale_enabled: boolean;
  auto_scale_min: number | null;
  auto_scale_max: number | null;
  type_results: TypeResult[] | string;
}

type SortField = 'started_at' | 'total_records' | 'records_per_sec' | 'duration_ms' | 'preset_label';
type SortDir = 'asc' | 'desc';

// ── Helpers ───────────────────────────────────────────────────────────

function formatNumber(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return String(n);
}

function formatDuration(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60_000) return `${(ms / 1000).toFixed(1)}s`;
  return `${Math.floor(ms / 60_000)}m ${Math.round((ms % 60_000) / 1000)}s`;
}

function formatDate(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function shortUser(userId: string): string {
  // "matthew.giglia@databricks.com" -> "matthew.giglia@"
  const at = userId.indexOf('@');
  if (at > 0) return userId.slice(0, at + 1);
  return userId;
}

function statusBadge(status: string) {
  const colors: Record<string, string> = {
    complete: 'bg-[var(--dbx-green-600)]/15 text-[var(--dbx-green-600)]',
    running: 'bg-[var(--dbx-blue-600)]/15 text-[var(--dbx-blue-600)]',
    error: 'bg-[var(--dbx-lava-600)]/15 text-[var(--dbx-lava-600)]',
    aborted: 'bg-[var(--dbx-yellow-600)]/15 text-[var(--dbx-yellow-600)]',
  };
  return (
    <span className={`text-xs font-bold px-2 py-0.5 rounded-full ${colors[status] ?? 'bg-[var(--muted)] text-[var(--muted-foreground)]'}`}>
      {status}
    </span>
  );
}

function presetBadge(label: string | null) {
  if (!label) return null;
  const tier: Record<string, string> = {
    Smoke: 'bg-[var(--dbx-gray-400)]/15 text-[var(--dbx-gray-600)]',
    Small: 'bg-[var(--dbx-blue-600)]/10 text-[var(--dbx-blue-600)]',
    Medium: 'bg-[var(--dbx-green-600)]/10 text-[var(--dbx-green-600)]',
    Large: 'bg-[var(--dbx-yellow-600)]/10 text-[var(--dbx-yellow-600)]',
    Massive: 'bg-[var(--dbx-lava-600)]/10 text-[var(--dbx-lava-600)]',
    Custom: 'bg-[var(--muted)] text-[var(--muted-foreground)]',
  };
  return (
    <span className={`text-xs font-bold px-2 py-0.5 rounded-full ${tier[label] ?? tier.Custom}`}>
      {label}
    </span>
  );
}

// ── Props ──────────────────────────────────────────────────────────

interface LoadTestHistoryProps {
  /**
   * Increment this counter to trigger a history refresh from the parent.
   * Used to refresh after a test starts (shows 'running') or completes.
   */
  refreshTrigger?: number;
}

// ── Component ─────────────────────────────────────────────────────────

export function LoadTestHistory({ refreshTrigger = 0 }: LoadTestHistoryProps) {
  const [runs, setRuns] = useState<HistoryRun[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [expandedRun, setExpandedRun] = useState<string | null>(null);
  const [sortField, setSortField] = useState<SortField>('started_at');
  const [sortDir, setSortDir] = useState<SortDir>('desc');

  const fetchHistory = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch('/api/v1/testing/history?limit=50');
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      const fetched: HistoryRun[] = data.runs ?? [];
      setRuns(fetched);

      // Auto-expand the most recently completed (or running) run
      const mostRecent = fetched.find(
        (r) => r.status === 'running' || r.status === 'complete',
      );
      if (mostRecent) {
        setExpandedRun(mostRecent.run_id);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  }, []);

  // Initial fetch + refresh whenever refreshTrigger increments
  useEffect(() => {
    fetchHistory();
  }, [fetchHistory, refreshTrigger]);

  // Poll every 10s so all users see running / completed tests in near-real-time
  useEffect(() => {
    const id = setInterval(() => fetchHistory(), 10_000);
    return () => clearInterval(id);
  }, [fetchHistory]);

  // Sort runs client-side
  const sortedRuns = [...runs].sort((a, b) => {
    const dir = sortDir === 'asc' ? 1 : -1;
    switch (sortField) {
      case 'started_at':
        return dir * (new Date(a.started_at).getTime() - new Date(b.started_at).getTime());
      case 'total_records':
        return dir * ((a.total_records ?? 0) - (b.total_records ?? 0));
      case 'records_per_sec':
        return dir * ((a.records_per_sec ?? 0) - (b.records_per_sec ?? 0));
      case 'duration_ms':
        return dir * ((a.duration_ms ?? 0) - (b.duration_ms ?? 0));
      case 'preset_label':
        return dir * (a.preset_label ?? '').localeCompare(b.preset_label ?? '');
      default:
        return 0;
    }
  });

  const toggleSort = (field: SortField) => {
    if (sortField === field) {
      setSortDir(sortDir === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDir('desc');
    }
  };

  const SortIcon = ({ field }: { field: SortField }) => (
    <ArrowUpDown
      className={`inline h-3 w-3 ml-1 ${sortField === field ? 'opacity-100' : 'opacity-30'}`}
    />
  );

  // Parse type_results (may be a JSON string from Lakebase)
  const getTypeResults = (run: HistoryRun): TypeResult[] => {
    if (typeof run.type_results === 'string') {
      try { return JSON.parse(run.type_results); } catch { return []; }
    }
    return run.type_results ?? [];
  };

  return (
    <div className="mt-10">
      {/* Section Header */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <History className="h-5 w-5 text-[var(--dbx-lava-500)]" />
          <h2 className="text-xl font-bold text-[var(--foreground)]">Test History</h2>
          {!loading && (
            <span className="text-xs text-[var(--muted-foreground)] font-mono">
              {runs.length} run{runs.length !== 1 ? 's' : ''}
            </span>
          )}
        </div>
        <button
          onClick={fetchHistory}
          disabled={loading}
          className="flex items-center gap-1.5 text-xs text-[var(--muted-foreground)] hover:text-[var(--foreground)] transition-colors disabled:opacity-50"
        >
          <RefreshCw className={`h-3.5 w-3.5 ${loading ? 'animate-spin' : ''}`} />
          Refresh
        </button>
      </div>

      {/* Error state */}
      {error && (
        <div className="bg-[var(--dbx-lava-600)]/10 border border-[var(--dbx-lava-600)]/30 rounded-xl p-4 mb-4">
          <p className="text-sm text-[var(--dbx-lava-600)]">
            Failed to load history: {error}
          </p>
        </div>
      )}

      {/* Loading state */}
      {loading && !error && (
        <div className="bg-[var(--card)] border border-[var(--border)] rounded-xl p-12 text-center">
          <RefreshCw className="h-8 w-8 mx-auto mb-3 animate-spin text-[var(--muted-foreground)]" />
          <p className="text-sm text-[var(--muted-foreground)]">Loading history...</p>
        </div>
      )}

      {/* Empty state */}
      {!loading && !error && runs.length === 0 && (
        <div className="bg-[var(--card)] border border-[var(--border)] border-dashed rounded-xl p-12 text-center">
          <History className="h-10 w-10 mx-auto mb-3 opacity-20" />
          <h3 className="text-lg font-bold text-[var(--foreground)] mb-1">No History Yet</h3>
          <p className="text-sm text-[var(--muted-foreground)]">
            Run a load test to see results here. History is stored in Lakebase
            and synced to Unity Catalog via Lakehouse Sync.
          </p>
        </div>
      )}

      {/* Timeline Table */}
      {!loading && runs.length > 0 && (
        <div className="bg-[var(--card)] border border-[var(--border)] rounded-xl overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-[var(--border)] bg-[var(--muted)]/30">
                <th
                  className="text-left px-4 py-3 font-bold text-xs text-[var(--muted-foreground)] cursor-pointer hover:text-[var(--foreground)]"
                  onClick={() => toggleSort('started_at')}
                >
                  Date/Time <SortIcon field="started_at" />
                </th>
                <th className="text-left px-4 py-3 font-bold text-xs text-[var(--muted-foreground)]">
                  User
                </th>
                <th
                  className="text-left px-4 py-3 font-bold text-xs text-[var(--muted-foreground)] cursor-pointer hover:text-[var(--foreground)]"
                  onClick={() => toggleSort('preset_label')}
                >
                  Preset <SortIcon field="preset_label" />
                </th>
                <th
                  className="text-right px-4 py-3 font-bold text-xs text-[var(--muted-foreground)] cursor-pointer hover:text-[var(--foreground)]"
                  onClick={() => toggleSort('total_records')}
                >
                  Records <SortIcon field="total_records" />
                </th>
                <th
                  className="text-right px-4 py-3 font-bold text-xs text-[var(--muted-foreground)] cursor-pointer hover:text-[var(--foreground)]"
                  onClick={() => toggleSort('records_per_sec')}
                >
                  Throughput <SortIcon field="records_per_sec" />
                </th>
                <th
                  className="text-right px-4 py-3 font-bold text-xs text-[var(--muted-foreground)] cursor-pointer hover:text-[var(--foreground)]"
                  onClick={() => toggleSort('duration_ms')}
                >
                  Duration <SortIcon field="duration_ms" />
                </th>
                <th className="text-center px-4 py-3 font-bold text-xs text-[var(--muted-foreground)]">
                  Pool
                </th>
                <th className="text-center px-4 py-3 font-bold text-xs text-[var(--muted-foreground)]">
                  Status
                </th>
              </tr>
            </thead>
            <tbody>
              {sortedRuns.map((run) => {
                const typeResults = getTypeResults(run);
                const isExpanded = expandedRun === run.run_id;

                return (
                  <>
                    <tr
                      key={run.run_id}
                      className="border-b border-[var(--border)] hover:bg-[var(--muted)]/20 cursor-pointer transition-colors"
                      onClick={() => setExpandedRun(isExpanded ? null : run.run_id)}
                    >
                      <td className="px-4 py-3 font-mono text-xs text-[var(--foreground)]">
                        <div className="flex items-center gap-1.5">
                          {isExpanded ? <ChevronUp className="h-3 w-3" /> : <ChevronDown className="h-3 w-3 opacity-40" />}
                          {formatDate(run.started_at)}
                        </div>
                      </td>
                      <td className="px-4 py-3 text-xs text-[var(--muted-foreground)]">
                        <div className="flex items-center gap-1">
                          <User className="h-3 w-3 opacity-50" />
                          {shortUser(run.user_id)}
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        {presetBadge(run.preset_label)}
                      </td>
                      <td className="px-4 py-3 text-right font-mono font-bold text-[var(--foreground)]">
                        {run.total_records != null ? formatNumber(run.total_records) : '—'}
                      </td>
                      <td className="px-4 py-3 text-right font-mono text-[var(--dbx-green-600)]">
                        {run.records_per_sec != null ? `${formatNumber(run.records_per_sec)}/s` : '—'}
                      </td>
                      <td className="px-4 py-3 text-right font-mono text-[var(--muted-foreground)]">
                        {run.duration_ms != null ? formatDuration(run.duration_ms) : '—'}
                      </td>
                      <td className="px-4 py-3 text-center font-mono text-xs">
                        {run.pool_size_start != null && run.pool_size_end != null ? (
                          <span>
                            {run.pool_size_start}→{run.pool_size_end}
                            {run.auto_scale_enabled && (
                              <span className="text-[var(--dbx-blue-600)] ml-1" title="Auto-scale">⚡</span>
                            )}
                          </span>
                        ) : '—'}
                      </td>
                      <td className="px-4 py-3 text-center">
                        {statusBadge(run.status)}
                      </td>
                    </tr>

                    {/* Expanded row: per-type breakdown */}
                    {isExpanded && typeResults.length > 0 && (
                      <tr key={`${run.run_id}-detail`} className="bg-[var(--muted)]/10">
                        <td colSpan={8} className="px-4 py-3">
                          <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
                            {typeResults.map((tr) => (
                              <div
                                key={tr.record_type}
                                className="bg-[var(--card)] border border-[var(--border)] rounded-lg p-3"
                              >
                                <div className="text-xs font-mono text-[var(--dbx-lava-500)] mb-1">
                                  {tr.record_type}
                                </div>
                                <div className="flex items-baseline gap-2">
                                  <span className="text-lg font-bold font-mono text-[var(--foreground)]">
                                    {tr.record_count != null ? formatNumber(tr.record_count) : '—'}
                                  </span>
                                  <span className="text-xs text-[var(--muted-foreground)]">
                                    records
                                  </span>
                                </div>
                                {tr.records_per_sec != null && (
                                  <div className="text-xs font-mono text-[var(--dbx-green-600)] mt-0.5">
                                    {formatNumber(tr.records_per_sec)}/s
                                  </div>
                                )}
                                {tr.duration_ms != null && (
                                  <div className="text-xs text-[var(--muted-foreground)] mt-0.5">
                                    {formatDuration(tr.duration_ms)}
                                  </div>
                                )}
                              </div>
                            ))}
                          </div>

                          {/* Run metadata */}
                          <div className="mt-3 flex flex-wrap gap-x-6 gap-y-1 text-xs text-[var(--muted-foreground)]">
                            <span>Batch size: <strong className="font-mono">{run.batch_size}</strong></span>
                            <span>Payloads: <strong className="font-mono">{formatNumber(run.total_payloads)}</strong></span>
                            {run.auto_scale_enabled && run.auto_scale_min != null && (
                              <span>Auto-scale: <strong className="font-mono">{run.auto_scale_min}–{run.auto_scale_max}</strong></span>
                            )}
                            <span className="font-mono opacity-50" title="Run ID">{run.run_id.slice(0, 8)}...</span>
                          </div>

                          {run.error_message && (
                            <div className="mt-2 text-xs text-[var(--dbx-lava-600)] font-mono bg-[var(--dbx-lava-600)]/10 rounded p-2">
                              {run.error_message}
                            </div>
                          )}
                        </td>
                      </tr>
                    )}
                  </>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
