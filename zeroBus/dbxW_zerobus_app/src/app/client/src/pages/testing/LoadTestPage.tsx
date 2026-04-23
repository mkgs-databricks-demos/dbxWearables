import { useState, useCallback, useRef, useEffect } from 'react';
import { Play, Square, RefreshCw, Zap, Clock, BarChart3, Layers, ArrowUpCircle, ArrowDownCircle, Settings2, Sparkles } from 'lucide-react';
import { BrandIcon } from '@/components/BrandIcon';
import { LoadTestHistory } from './LoadTestHistory';
import { type RecordType, RECORD_TYPES } from '@shared/synthetic-healthkit';

/* ═══════════════════════════════════════════════════════════════════
   LoadTestPage — Synthetic Data Generation at Scale
   Connects to POST /api/v1/testing/load-test/stream via SSE
   for real-time progress during million-record ingestion tests.
   Server streams progress events after each batch; client reads
   via fetch() + ReadableStream (single HTTP connection).
   ═══════════════════════════════════════════════════════════════════ */

// ── Types ────────────────────────────────────────────────────────────

type RecordCounts = Partial<Record<RecordType, number>>;

interface TestState {
  phase: 'idle' | 'running' | 'complete' | 'error';
  chunksCompleted: number;
  chunksTotal: number;
  totalRecords: number;
  totalDurationMs: number;
  recordsPerSec: number;
  perType: Map<RecordType, { records: number; durationMs: number }>;
  error?: string;
}


interface PoolStatus {
  pool_size: number;
  active_streams: number;
  initialized: boolean;
  inflight_requests: number;
  draining: boolean;
  auto_scale: {
    enabled: boolean;
    min_size: number;
    max_size: number;
  };
}


interface ResizeEvent {
  timestamp: string;
  trigger: 'auto-scale-up' | 'auto-scale-down' | 'manual' | 'initial';
  oldSize: number;
  newSize: number;
  durationMs: number;
  peakInflight?: number;
  idleChecks?: number;
  callRate?: number;
}

// ── Presets ───────────────────────────────────────────────────────────

interface Preset {
  label: string;
  description: string;
  counts: RecordCounts;
  batchSize: number;
}

const PRESETS: Preset[] = [
  {
    label: 'Smoke',
    description: '5 payloads — verify the pipeline',
    counts: { samples: 2, workouts: 1, sleep: 1, activity_summaries: 1 },
    batchSize: 500,
  },
  {
    label: 'Small',
    description: '500 payloads (~1.5K records)',
    counts: { samples: 200, workouts: 100, sleep: 100, activity_summaries: 50, deletes: 50 },
    batchSize: 500,
  },
  {
    label: 'Medium',
    description: '5K payloads (~15K records)',
    counts: { samples: 2000, workouts: 1000, sleep: 1000, activity_summaries: 500, deletes: 500 },
    batchSize: 1000,
  },
  {
    label: 'Large',
    description: '50K payloads (~150K records)',
    counts: { samples: 20000, workouts: 10000, sleep: 10000, activity_summaries: 5000, deletes: 5000 },
    batchSize: 2000,
  },
  {
    label: 'Massive',
    description: '500K payloads (~1.5M records)',
    counts: { samples: 200000, workouts: 100000, sleep: 100000, activity_summaries: 50000, deletes: 50000 },
    batchSize: 5000,
  },
];

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

function totalPayloads(counts: RecordCounts): number {
  return Object.values(counts).reduce((sum, n) => sum + (n ?? 0), 0);
}

// ── Component ────────────────────────────────────────────────────────

export function LoadTestPage() {
  const [counts, setCounts] = useState<RecordCounts>(PRESETS[1].counts);
  const [batchSize, setBatchSize] = useState(500);
  const [activePreset, setActivePreset] = useState(1);
  const abortControllerRef = useRef<AbortController | null>(null);

  const [state, setState] = useState<TestState>({
    phase: 'idle',
    chunksCompleted: 0,
    chunksTotal: 0,
    totalRecords: 0,
    totalDurationMs: 0,
    recordsPerSec: 0,
    perType: new Map(),
  });

  const applyPreset = useCallback((index: number) => {
    const preset = PRESETS[index];
    setCounts({ ...preset.counts });
    setBatchSize(preset.batchSize);
    setActivePreset(index);
  }, []);


  // ── Stream pool status ──────────────────────────────────────────
  const [pool, setPool] = useState<PoolStatus | null>(null);
  const [poolTarget, setPoolTarget] = useState(4);
  const [poolResizing, setPoolResizing] = useState(false);
  const [poolError, setPoolError] = useState('');
  const [autoScaleEnabled, setAutoScaleEnabled] = useState(true);
  const [autoScaleMin, setAutoScaleMin] = useState(2);
  const [autoScaleMax, setAutoScaleMax] = useState(16);
  const [autoScaleToggling, setAutoScaleToggling] = useState(false);
  const [resizeHistory, setResizeHistory] = useState<ResizeEvent[]>([]);

  const fetchPoolStatus = useCallback(async () => {
    try {
      const res = await fetch('/api/v1/testing/pool-status');
      const data = await res.json();
      if (data.status === 'ok') {
        setPool(data);
        setPoolTarget(data.pool_size);
        if (data.auto_scale) {
          setAutoScaleEnabled(data.auto_scale.enabled);
          if (data.auto_scale.enabled) {
            setAutoScaleMin(data.auto_scale.min_size);
            setAutoScaleMax(data.auto_scale.max_size);
          }
        }
        if (data.history) {
          setResizeHistory(data.history);
        }
      }
    } catch {
      // Pool status not critical — ignore
    }
  }, []);

  useEffect(() => {
    fetchPoolStatus();
  }, [fetchPoolStatus]);

  const resizePool = useCallback(async () => {
    setPoolResizing(true);
    setPoolError('');
    try {
      const res = await fetch('/api/v1/testing/pool-resize', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ poolSize: poolTarget }),
      });
      const data = await res.json();
      if (data.status !== 'success') {
        throw new Error(data.message || 'Resize failed');
      }
      await fetchPoolStatus();
    } catch (err) {
      setPoolError(err instanceof Error ? err.message : String(err));
    } finally {
      setPoolResizing(false);
    }
  }, [poolTarget, fetchPoolStatus]);


  const toggleAutoScale = useCallback(async (enable: boolean) => {
    setAutoScaleToggling(true);
    setPoolError('');
    try {
      const res = await fetch('/api/v1/testing/pool-autoscale', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(
          enable
            ? { enabled: true, minSize: autoScaleMin, maxSize: autoScaleMax }
            : { enabled: false },
        ),
      });
      const data = await res.json();
      if (data.status !== 'success') {
        throw new Error(data.message || 'Auto-scale toggle failed');
      }
      setAutoScaleEnabled(enable);
      await fetchPoolStatus();
    } catch (err) {
      setPoolError(err instanceof Error ? err.message : String(err));
    } finally {
      setAutoScaleToggling(false);
    }
  }, [autoScaleMin, autoScaleMax, fetchPoolStatus]);

  const updateCount = useCallback((rt: RecordType, value: number) => {
    setCounts((prev) => ({ ...prev, [rt]: Math.max(0, value) }));
    setActivePreset(-1);
  }, []);


  // Poll pool status while auto-scale is active and a test is running
  useEffect(() => {
    if (!autoScaleEnabled || state.phase !== 'running') return;
    const interval = setInterval(fetchPoolStatus, 3000);
    return () => clearInterval(interval);
  }, [autoScaleEnabled, state.phase, fetchPoolStatus]);

  // ── SSE streaming execution ─────────────────────────────────────
  //
  // Single fetch() to the SSE endpoint. The server processes all
  // batches and streams progress events. We read them via
  // ReadableStream + TextDecoder and update React state on each event.

  const runTest = useCallback(async () => {
    const abortController = new AbortController();
    abortControllerRef.current = abortController;

    setState({
      phase: 'running',
      chunksCompleted: 0,
      chunksTotal: 0,
      totalRecords: 0,
      totalDurationMs: 0,
      recordsPerSec: 0,
      perType: new Map(),
    });

    try {
      const response = await fetch('/api/v1/testing/load-test/stream', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          counts,
          batchSize,
          presetLabel: PRESETS[activePreset]?.label ?? 'Custom',
          sourcePlatform: 'synthetic',
        }),
        signal: abortController.signal,
      });

      if (!response.ok) {
        // Non-SSE error response (400, 500, etc.)
        const errorData = await response.json();
        throw new Error(errorData.message || `HTTP ${response.status}`);
      }

      // Read the SSE stream via ReadableStream
      const reader = response.body!.getReader();
      const decoder = new TextDecoder();
      let buffer = '';

      while (true) {
        const { value, done } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });

        // SSE events are delimited by double newlines
        const events = buffer.split('\n\n');
        buffer = events.pop() ?? ''; // Keep incomplete event in buffer

        for (const eventStr of events) {
          if (!eventStr.trim()) continue;

          // Parse SSE fields: "event: <type>\ndata: <json>"
          const lines = eventStr.split('\n');
          let eventType = '';
          let data = '';

          for (const line of lines) {
            if (line.startsWith('event: ')) eventType = line.slice(7);
            else if (line.startsWith('data: ')) data = line.slice(6);
          }

          if (!data) continue;

          const parsed = JSON.parse(data);

          // Build per-type map from the server's perType array
          const typeMap = new Map<RecordType, { records: number; durationMs: number }>();
          if (parsed.perType) {
            for (const tm of parsed.perType) {
              typeMap.set(tm.recordType, { records: tm.recordCount, durationMs: tm.durationMs });
            }
          }

          if (eventType === 'progress') {
            setState({
              phase: 'running',
              chunksCompleted: parsed.chunk,
              chunksTotal: parsed.chunksTotal,
              totalRecords: parsed.totalRecords,
              totalDurationMs: parsed.totalDurationMs,
              recordsPerSec: parsed.recordsPerSec,
              perType: typeMap,
            });
          } else if (eventType === 'complete') {
            setState({
              phase: 'complete',
              chunksCompleted: parsed.chunksTotal ?? parsed.chunk ?? 0,
              chunksTotal: parsed.chunksTotal ?? parsed.chunk ?? 0,
              totalRecords: parsed.totalRecords,
              totalDurationMs: parsed.totalDurationMs,
              recordsPerSec: parsed.recordsPerSec,
              perType: typeMap,
            });
            // Refresh pool status after test completes
            fetchPoolStatus();
          } else if (eventType === 'error') {
            setState((prev) => ({
              ...prev,
              phase: 'error',
              error: parsed.message,
            }));
          }
        }
      }
    } catch (err) {
      if ((err as Error).name === 'AbortError') {
        // User clicked Stop — records already ingested are preserved
        setState((prev) => ({ ...prev, phase: 'idle' }));
      } else {
        // Network errors during a running test (e.g., proxy timeout after
        // 5 minutes) should show partial success, not a hard failure.
        // The server likely completed — records are already ingested.
        setState((prev) => {
          if (prev.phase === 'running' && prev.totalRecords > 0) {
            return {
              ...prev,
              phase: 'complete',
              error: `Connection lost (${err instanceof Error ? err.message : 'network error'}). `
                + `${formatNumber(prev.totalRecords)} records were ingested before disconnect. `
                + `The server may have completed — check the event log.`,
            };
          }
          return {
            ...prev,
            phase: 'error',
            error: err instanceof Error ? err.message : String(err),
          };
        });
      }
    } finally {
      abortControllerRef.current = null;
      fetchPoolStatus();
    }
  }, [counts, batchSize]);

  const stopTest = useCallback(() => {
    abortControllerRef.current?.abort();
  }, []);

  const progress = state.chunksTotal > 0
    ? Math.round((state.chunksCompleted / state.chunksTotal) * 100)
    : 0;

  return (
    <div className="max-w-6xl mx-auto py-12 px-6">
      {/* Header */}
      <div className="mb-10">
        <div className="flex items-center gap-3 mb-2">
          <BrandIcon name="spark-streaming" className="h-8 w-8" />
          <h1 className="text-3xl font-bold text-[var(--foreground)]">Synthetic Load Test</h1>
        </div>
        <p className="text-[var(--muted-foreground)]">
          Generate millions of realistic HealthKit records and ingest them directly through the ZeroBus
          gRPC stream pool. Records bypass HTTP and write straight to the bronze table.
        </p>
      </div>

      <div className="grid lg:grid-cols-3 gap-8">
        {/* ── Left column: Configuration ─────────────────────────── */}
        <div className="lg:col-span-1 space-y-6">

          {/* Presets */}
          <div className="bg-[var(--card)] border border-[var(--border)] rounded-xl p-5">
            <h3 className="font-bold text-sm text-[var(--foreground)] mb-3">Scale Presets</h3>
            <div className="space-y-2">
              {PRESETS.map((preset, i) => (
                <button
                  key={preset.label}
                  onClick={() => applyPreset(i)}
                  disabled={state.phase === 'running'}
                  className={`w-full text-left px-4 py-3 rounded-lg border transition-all ${
                    activePreset === i
                      ? 'border-[var(--dbx-lava-600)] bg-[var(--dbx-lava-600)]/10 text-[var(--foreground)]'
                      : 'border-[var(--border)] hover:border-[var(--dbx-lava-600)]/50 text-[var(--muted-foreground)]'
                  } disabled:opacity-50`}
                >
                  <div className="flex items-center justify-between">
                    <span className="font-bold text-sm">{preset.label}</span>
                    <span className="text-xs font-mono opacity-60">
                      {formatNumber(totalPayloads(preset.counts))} payloads
                    </span>
                  </div>
                  <span className="text-xs opacity-70">{preset.description}</span>
                </button>
              ))}
            </div>
          </div>

          {/* Per-type counts */}
          <div className="bg-[var(--card)] border border-[var(--border)] rounded-xl p-5">
            <h3 className="font-bold text-sm text-[var(--foreground)] mb-3">Payloads Per Type</h3>
            <div className="space-y-3">
              {RECORD_TYPES.map((rt) => (
                <div key={rt}>
                  <label className="block text-xs font-mono text-[var(--dbx-lava-500)] mb-1">
                    {rt}
                  </label>
                  <input
                    type="number"
                    min={0}
                    value={counts[rt] ?? 0}
                    onChange={(e) => updateCount(rt, parseInt(e.target.value) || 0)}
                    disabled={state.phase === 'running'}
                    className="w-full bg-[var(--muted)] border border-[var(--border)] rounded-lg px-3 py-1.5 text-sm font-mono text-[var(--foreground)] disabled:opacity-50"
                  />
                </div>
              ))}
            </div>
            <div className="mt-3 pt-3 border-t border-[var(--border)] flex justify-between text-xs">
              <span className="text-[var(--muted-foreground)]">Total payloads</span>
              <span className="font-bold font-mono text-[var(--foreground)]">
                {formatNumber(totalPayloads(counts))}
              </span>
            </div>
          </div>


          {/* Stream pool */}
          <div className="bg-[var(--card)] border border-[var(--border)] rounded-xl p-5">
            <div className="flex items-center justify-between mb-3">
              <h3 className="font-bold text-sm text-[var(--foreground)]">Stream Pool</h3>
              {pool && (
                <span className={`text-xs font-mono px-2 py-0.5 rounded-full ${
                  pool.initialized
                    ? 'bg-[var(--dbx-green-600)]/10 text-[var(--dbx-green-600)]'
                    : 'bg-[var(--muted)] text-[var(--muted-foreground)]'
                }`}>
                  {pool.initialized ? `${pool.active_streams} stream${pool.active_streams !== 1 ? 's' : ''} active` : 'not initialized'}
                </span>
              )}
            </div>

            {/* Auto-scale toggle */}
            <div className="flex items-center justify-between mb-3 pb-3 border-b border-[var(--border)]">
              <div>
                <span className="text-xs font-medium text-[var(--foreground)]">Auto-scale</span>
                <span className="text-xs text-[var(--muted-foreground)] ml-1.5">
                  {autoScaleEnabled ? `${autoScaleMin}–${autoScaleMax}` : 'off'}
                </span>
              </div>
              <button
                onClick={() => toggleAutoScale(!autoScaleEnabled)}
                disabled={autoScaleToggling}
                className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors ${
                  autoScaleEnabled
                    ? 'bg-[var(--dbx-green-600)]'
                    : 'bg-[var(--muted)] border border-[var(--border)]'
                } ${autoScaleToggling ? 'opacity-50' : ''}`}
              >
                <span
                  className={`inline-block h-3.5 w-3.5 rounded-full bg-white shadow transition-transform ${
                    autoScaleEnabled ? 'translate-x-[18px]' : 'translate-x-[3px]'
                  }`}
                />
              </button>
            </div>

            {/* Auto-scale config (shown when enabled) */}
            {autoScaleEnabled && (
              <div className="grid grid-cols-2 gap-2 mb-3">
                <div>
                  <label className="block text-xs text-[var(--muted-foreground)] mb-1">Min</label>
                  <input
                    type="number"
                    min={1}
                    max={autoScaleMax - 1}
                    value={autoScaleMin}
                    onChange={(e) => setAutoScaleMin(Math.max(1, parseInt(e.target.value) || 1))}
                    onBlur={() => { if (autoScaleEnabled) toggleAutoScale(true); }}
                    className="w-full bg-[var(--muted)] border border-[var(--border)] rounded-lg px-3 py-1.5 text-sm font-mono text-[var(--foreground)]"
                  />
                </div>
                <div>
                  <label className="block text-xs text-[var(--muted-foreground)] mb-1">Max</label>
                  <input
                    type="number"
                    min={autoScaleMin + 1}
                    max={32}
                    value={autoScaleMax}
                    onChange={(e) => setAutoScaleMax(Math.min(32, parseInt(e.target.value) || 16))}
                    onBlur={() => { if (autoScaleEnabled) toggleAutoScale(true); }}
                    className="w-full bg-[var(--muted)] border border-[var(--border)] rounded-lg px-3 py-1.5 text-sm font-mono text-[var(--foreground)]"
                  />
                </div>
              </div>
            )}

            {/* Manual resize (disabled when auto-scale is active) */}
            {!autoScaleEnabled && (
              <div className="flex items-center gap-2">
                <input
                  type="number"
                  min={1}
                  max={32}
                  value={poolTarget}
                  onChange={(e) => setPoolTarget(Math.max(1, Math.min(32, parseInt(e.target.value) || 1)))}
                  disabled={poolResizing || state.phase === 'running'}
                  className="flex-1 bg-[var(--muted)] border border-[var(--border)] rounded-lg px-3 py-1.5 text-sm font-mono text-[var(--foreground)] disabled:opacity-50"
                />
                <button
                  onClick={resizePool}
                  disabled={poolResizing || state.phase === 'running' || poolTarget === (pool?.pool_size ?? 0)}
                  className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-bold rounded-lg border border-[var(--border)] text-[var(--foreground)] hover:bg-[var(--muted)] transition-colors disabled:opacity-40"
                >
                  <Layers className={`h-3.5 w-3.5 ${poolResizing ? 'animate-spin' : ''}`} />
                  {poolResizing ? 'Resizing...' : 'Resize'}
                </button>
              </div>
            )}

            {poolError && (
              <p className="text-xs text-red-500 mt-2">{poolError}</p>
            )}

            <p className="text-xs text-[var(--muted-foreground)] mt-3">
              {autoScaleEnabled
                ? 'Pool scales automatically: adds streams under load, removes them when idle.'
                : 'Concurrent gRPC streams to ZeroBus. More streams = higher throughput.'}
            </p>

            {pool && pool.inflight_requests > 0 && (
              <p className="text-xs text-[var(--dbx-lava-500)] mt-1 font-mono">
                {pool.inflight_requests} request{pool.inflight_requests !== 1 ? 's' : ''} in-flight
              </p>
            )}
          </div>

          {/* Advanced settings */}
          <div className="bg-[var(--card)] border border-[var(--border)] rounded-xl p-5">
            <h3 className="font-bold text-sm text-[var(--foreground)] mb-3">Advanced</h3>
            <div className="space-y-3">
              <div>
                <label className="block text-xs text-[var(--muted-foreground)] mb-1">
                  Batch size (records per gRPC write)
                </label>
                <input
                  type="number"
                  min={1}
                  max={5000}
                  value={batchSize}
                  onChange={(e) => setBatchSize(parseInt(e.target.value) || 500)}
                  disabled={state.phase === 'running'}
                  className="w-full bg-[var(--muted)] border border-[var(--border)] rounded-lg px-3 py-1.5 text-sm font-mono text-[var(--foreground)] disabled:opacity-50"
                />
              </div>
            </div>
          </div>
        </div>

        {/* ── Right column: Controls + Results ───────────────────── */}
        <div className="lg:col-span-2 space-y-6">

          {/* Action buttons */}
          <div className="flex items-center gap-4">
            {state.phase === 'running' ? (
              <button
                onClick={stopTest}
                className="flex items-center gap-2 px-6 py-3 bg-red-600 text-white rounded-xl text-sm font-bold shadow-lg hover:bg-red-700 transition-colors"
              >
                <Square className="h-4 w-4" />
                Stop Test
              </button>
            ) : (
              <button
                onClick={runTest}
                disabled={totalPayloads(counts) === 0}
                className="flex items-center gap-2 px-6 py-3 gradient-red text-white rounded-xl text-sm font-bold shadow-lg hover:shadow-xl transition-all disabled:opacity-50"
              >
                <Play className="h-4 w-4" />
                Start Load Test
              </button>
            )}

            {state.phase !== 'idle' && state.phase !== 'running' && (
              <button
                onClick={() => setState({ phase: 'idle', chunksCompleted: 0, chunksTotal: 0, totalRecords: 0, totalDurationMs: 0, recordsPerSec: 0, perType: new Map() })}
                className="flex items-center gap-2 px-4 py-3 border border-[var(--border)] rounded-xl text-sm font-medium text-[var(--foreground)] hover:bg-[var(--muted)] transition-colors"
              >
                <RefreshCw className="h-4 w-4" />
                Reset
              </button>
            )}
          </div>

          {/* Progress bar */}
          {(state.phase === 'running' || state.phase === 'complete') && (
            <div className="bg-[var(--card)] border border-[var(--border)] rounded-xl p-5">
              <div className="flex items-center justify-between mb-2">
                <span className="text-sm font-medium text-[var(--foreground)]">
                  {state.phase === 'running' ? 'Ingesting...' : 'Complete'}
                </span>
                <span className="text-xs font-mono text-[var(--muted-foreground)]">
                  {state.chunksCompleted}/{state.chunksTotal} batches
                </span>
              </div>
              <div className="w-full bg-[var(--muted)] rounded-full h-3 overflow-hidden">
                <div
                  className={`h-full rounded-full transition-all duration-300 ${
                    state.phase === 'complete'
                      ? 'bg-[var(--dbx-green-600)]'
                      : 'bg-[var(--dbx-lava-600)] animate-pulse'
                  }`}
                  style={{ width: `${progress}%` }}
                />
              </div>
              <div className="flex items-center justify-between mt-2 text-xs text-[var(--muted-foreground)]">
                <span>{progress}%</span>
                <span>{formatNumber(state.totalRecords)} records ingested</span>
              </div>
            </div>
          )}

          {/* Live metrics */}
          {state.phase !== 'idle' && (
            <div className="grid grid-cols-3 gap-4">
              <MetricCard
                icon={<BarChart3 className="h-5 w-5" />}
                label="Records Ingested"
                value={formatNumber(state.totalRecords)}
                color="text-[var(--dbx-lava-600)]"
              />
              <MetricCard
                icon={<Clock className="h-5 w-5" />}
                label="Duration"
                value={formatDuration(state.totalDurationMs)}
                color="text-blue-500"
              />
              <MetricCard
                icon={<Zap className="h-5 w-5" />}
                label="Throughput"
                value={`${formatNumber(state.recordsPerSec)}/s`}
                color="text-[var(--dbx-green-600)]"
              />
            </div>
          )}

          {/* Per-type breakdown */}
          {state.perType.size > 0 && (
            <div className="bg-[var(--card)] border border-[var(--border)] rounded-xl overflow-hidden">
              <div className="px-5 py-3 bg-[var(--muted)] border-b border-[var(--border)]">
                <h3 className="font-bold text-sm text-[var(--foreground)]">Per-Type Breakdown</h3>
              </div>
              <table className="w-full text-sm">
                <thead className="bg-[var(--muted)]/50">
                  <tr>
                    <th className="text-left py-2 px-5 font-medium text-[var(--muted-foreground)]">Record Type</th>
                    <th className="text-right py-2 px-5 font-medium text-[var(--muted-foreground)]">Records</th>
                    <th className="text-right py-2 px-5 font-medium text-[var(--muted-foreground)]">Duration</th>
                    <th className="text-right py-2 px-5 font-medium text-[var(--muted-foreground)]">Throughput</th>
                    <th className="text-left py-2 px-5 font-medium text-[var(--muted-foreground)] w-48">Progress</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[var(--border)]">
                  {RECORD_TYPES.filter((rt) => (counts[rt] ?? 0) > 0).map((rt) => {
                    const metrics = state.perType.get(rt);
                    const records = metrics?.records ?? 0;
                    // Estimate total expected records (payloads × avg records per payload)
                    const avgRecordsPerPayload = rt === 'samples' ? 3 : 1;
                    const expectedRecords = (counts[rt] ?? 0) * avgRecordsPerPayload;
                    const typeProgress = expectedRecords > 0 ? Math.min(100, Math.round((records / expectedRecords) * 100)) : 0;
                    const typeThroughput = metrics && metrics.durationMs > 0
                      ? Math.round((records / metrics.durationMs) * 1000)
                      : 0;

                    return (
                      <tr key={rt} className="hover:bg-[var(--muted)]/30">
                        <td className="py-2.5 px-5 font-mono text-xs text-[var(--dbx-lava-500)] font-bold">{rt}</td>
                        <td className="py-2.5 px-5 text-right font-mono text-xs">{formatNumber(records)}</td>
                        <td className="py-2.5 px-5 text-right font-mono text-xs text-[var(--muted-foreground)]">
                          {metrics ? formatDuration(metrics.durationMs) : '—'}
                        </td>
                        <td className="py-2.5 px-5 text-right font-mono text-xs text-[var(--dbx-green-600)]">
                          {typeThroughput > 0 ? `${formatNumber(typeThroughput)}/s` : '—'}
                        </td>
                        <td className="py-2.5 px-5">
                          <div className="w-full bg-[var(--muted)] rounded-full h-1.5">
                            <div
                              className="h-full rounded-full bg-[var(--dbx-lava-600)] transition-all duration-300"
                              style={{ width: `${typeProgress}%` }}
                            />
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}


          {/* Auto-scale event log */}
          {resizeHistory.length > 0 && (
            <div className="bg-[var(--card)] border border-[var(--border)] rounded-xl overflow-hidden">
              <div className="px-5 py-3 bg-[var(--muted)] border-b border-[var(--border)] flex items-center justify-between">
                <h3 className="font-bold text-sm text-[var(--foreground)]">Pool Resize History</h3>
                <span className="text-xs font-mono text-[var(--muted-foreground)]">
                  {resizeHistory.length} event{resizeHistory.length !== 1 ? 's' : ''}
                </span>
              </div>
              <div className="max-h-56 overflow-y-auto divide-y divide-[var(--border)]">
                {[...resizeHistory].reverse().map((evt, i) => (
                  <div key={i} className="flex items-center gap-3 px-5 py-2.5 hover:bg-[var(--muted)]/30">
                    {/* Icon */}
                    <div className={`flex-shrink-0 ${
                      evt.trigger === 'auto-scale-up' ? 'text-[var(--dbx-green-600)]' :
                      evt.trigger === 'auto-scale-down' ? 'text-blue-500' :
                      evt.trigger === 'initial' ? 'text-[var(--muted-foreground)]' :
                      'text-[var(--dbx-lava-600)]'
                    }`}>
                      {evt.trigger === 'auto-scale-up' && <ArrowUpCircle className="h-4 w-4" />}
                      {evt.trigger === 'auto-scale-down' && <ArrowDownCircle className="h-4 w-4" />}
                      {evt.trigger === 'manual' && <Settings2 className="h-4 w-4" />}
                      {evt.trigger === 'initial' && <Sparkles className="h-4 w-4" />}
                    </div>

                    {/* Details */}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="text-xs font-bold text-[var(--foreground)]">
                          {evt.oldSize} → {evt.newSize}
                        </span>
                        <span className={`text-[10px] font-mono px-1.5 py-0.5 rounded ${
                          evt.trigger.startsWith('auto') 
                            ? 'bg-[var(--dbx-green-600)]/10 text-[var(--dbx-green-600)]' 
                            : evt.trigger === 'manual'
                              ? 'bg-[var(--dbx-lava-600)]/10 text-[var(--dbx-lava-600)]'
                              : 'bg-[var(--muted)] text-[var(--muted-foreground)]'
                        }`}>
                          {evt.trigger === 'auto-scale-up' ? 'auto ↑' :
                           evt.trigger === 'auto-scale-down' ? 'auto ↓' :
                           evt.trigger}
                        </span>
                        {evt.peakInflight !== undefined && (
                          <span className="text-[10px] text-[var(--muted-foreground)]">
                            peak: {evt.peakInflight}
                          </span>
                        )}
                        {evt.callRate !== undefined && evt.callRate > 0 && (
                          <span className="text-[10px] text-[var(--muted-foreground)]">
                            calls: {evt.callRate}
                          </span>
                        )}
                        {evt.idleChecks !== undefined && (
                          <span className="text-[10px] text-[var(--muted-foreground)]">
                            idle: {evt.idleChecks}×
                          </span>
                        )}
                      </div>
                    </div>

                    {/* Timestamp + duration */}
                    <div className="flex-shrink-0 text-right">
                      <div className="text-[10px] font-mono text-[var(--muted-foreground)]">
                        {new Date(evt.timestamp).toLocaleTimeString()}
                      </div>
                      {evt.durationMs > 0 && (
                        <div className="text-[10px] font-mono text-[var(--muted-foreground)] opacity-60">
                          {evt.durationMs}ms
                        </div>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}


          {/* Connection lost warning (complete but with error = proxy timeout) */}
          {state.phase === 'complete' && state.error && (
            <div className="bg-yellow-50 border border-yellow-300 rounded-xl p-5">
              <h3 className="font-bold text-sm text-yellow-800 mb-1">Connection Lost During Test</h3>
              <p className="text-xs text-yellow-700">{state.error}</p>
            </div>
          )}

          {/* Error display */}
          {state.phase === 'error' && state.error && (
            <div className="bg-red-50 border border-red-200 rounded-xl p-5">
              <h3 className="font-bold text-sm text-red-800 mb-1">Load Test Failed</h3>
              <p className="text-xs text-red-600 font-mono">{state.error}</p>
              {state.totalRecords > 0 && (
                <p className="text-xs text-red-500 mt-2">
                  {formatNumber(state.totalRecords)} records were ingested before the failure.
                </p>
              )}
            </div>
          )}

          {/* Empty state */}
          {state.phase === 'idle' && (
            <div className="bg-[var(--card)] border border-[var(--border)] border-dashed rounded-xl p-12 text-center">
              <BrandIcon name="spark-streaming" className="h-12 w-12 mx-auto mb-4 opacity-30" />
              <h3 className="text-lg font-bold text-[var(--foreground)] mb-2">Ready to Load Test</h3>
              <p className="text-sm text-[var(--muted-foreground)] max-w-md mx-auto">
                Select a scale preset or configure custom payload counts, then hit Start.
                Records are generated with realistic distributions and ingested directly
                through the ZeroBus gRPC stream pool.
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

/* ── Metric Card ──────────────────────────────────────────────────── */

function MetricCard({
  icon,
  label,
  value,
  color,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  color: string;
}) {
  return (
    <div className="bg-[var(--card)] border border-[var(--border)] rounded-xl p-5">
      <div className={`${color} mb-2`}>{icon}</div>
      <div className="text-2xl font-bold font-mono text-[var(--foreground)]">{value}</div>
      <div className="text-xs text-[var(--muted-foreground)] mt-1">{label}</div>
    </div>
  );
}
