import { useState, useCallback, useRef } from 'react';
import { Play, Square, RefreshCw, Zap, Clock, BarChart3 } from 'lucide-react';
import { BrandIcon } from '@/components/BrandIcon';
import { type RecordType, RECORD_TYPES } from '@shared/synthetic-healthkit';

/* ═══════════════════════════════════════════════════════════════════
   LoadTestPage — Synthetic Data Generation at Scale
   Sends chunked requests to POST /api/v1/testing/load-test for
   live progress feedback during million-record ingestion tests.
   ═══════════════════════════════════════════════════════════════════ */

// ── Types ────────────────────────────────────────────────────────────

type RecordCounts = Partial<Record<RecordType, number>>;

interface TypeMetrics {
  recordType: RecordType;
  recordCount: number;
  durationMs: number;
}

interface ChunkResult {
  status: string;
  totalRecords: number;
  totalDurationMs: number;
  recordsPerSec: number;
  perType: TypeMetrics[];
}

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

// ── Presets ───────────────────────────────────────────────────────────

interface Preset {
  label: string;
  description: string;
  counts: RecordCounts;
  chunkSize: number;
}

const PRESETS: Preset[] = [
  {
    label: 'Smoke',
    description: '5 payloads — verify the pipeline',
    counts: { samples: 2, workouts: 1, sleep: 1, activity_summaries: 1 },
    chunkSize: 10,
  },
  {
    label: 'Small',
    description: '500 payloads (~1.5K records)',
    counts: { samples: 200, workouts: 100, sleep: 100, activity_summaries: 50, deletes: 50 },
    chunkSize: 100,
  },
  {
    label: 'Medium',
    description: '5K payloads (~15K records)',
    counts: { samples: 2000, workouts: 1000, sleep: 1000, activity_summaries: 500, deletes: 500 },
    chunkSize: 500,
  },
  {
    label: 'Large',
    description: '50K payloads (~150K records)',
    counts: { samples: 20000, workouts: 10000, sleep: 10000, activity_summaries: 5000, deletes: 5000 },
    chunkSize: 1000,
  },
  {
    label: 'Massive',
    description: '500K payloads (~1.5M records)',
    counts: { samples: 200000, workouts: 100000, sleep: 100000, activity_summaries: 50000, deletes: 50000 },
    chunkSize: 2000,
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
  const [chunkSize, setChunkSize] = useState(PRESETS[1].chunkSize);
  const [batchSize, setBatchSize] = useState(500);
  const [activePreset, setActivePreset] = useState(1);
  const abortRef = useRef(false);

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
    setChunkSize(preset.chunkSize);
    setActivePreset(index);
  }, []);

  const updateCount = useCallback((rt: RecordType, value: number) => {
    setCounts((prev) => ({ ...prev, [rt]: Math.max(0, value) }));
    setActivePreset(-1);
  }, []);

  // ── Chunked execution loop ──────────────────────────────────────

  const runTest = useCallback(async () => {
    abortRef.current = false;

    // Build chunks: divide each type's count into chunkSize pieces
    const chunks: RecordCounts[] = [];
    for (const rt of RECORD_TYPES) {
      const total = counts[rt] ?? 0;
      if (total <= 0) continue;
      let remaining = total;
      let chunkIndex = 0;
      while (remaining > 0) {
        const size = Math.min(remaining, chunkSize);
        if (!chunks[chunkIndex]) chunks[chunkIndex] = {};
        chunks[chunkIndex][rt] = size;
        remaining -= size;
        chunkIndex++;
      }
    }

    // Interleave types across chunks for even distribution
    const maxChunks = Math.max(...RECORD_TYPES.map((rt) => {
      const total = counts[rt] ?? 0;
      return total > 0 ? Math.ceil(total / chunkSize) : 0;
    }));
    const interleavedChunks: RecordCounts[] = [];
    for (let i = 0; i < maxChunks; i++) {
      const chunk: RecordCounts = {};
      for (const rt of RECORD_TYPES) {
        const total = counts[rt] ?? 0;
        if (total <= 0) continue;
        const perChunk = Math.min(chunkSize, total - i * chunkSize);
        if (perChunk > 0) chunk[rt] = perChunk;
      }
      if (Object.keys(chunk).length > 0) interleavedChunks.push(chunk);
    }

    setState({
      phase: 'running',
      chunksCompleted: 0,
      chunksTotal: interleavedChunks.length,
      totalRecords: 0,
      totalDurationMs: 0,
      recordsPerSec: 0,
      perType: new Map(),
    });

    const startTime = performance.now();
    let cumulativeRecords = 0;
    const typeAccum = new Map<RecordType, { records: number; durationMs: number }>();

    try {
      for (let i = 0; i < interleavedChunks.length; i++) {
        if (abortRef.current) {
          setState((prev) => ({ ...prev, phase: 'idle', error: 'Aborted by user' }));
          return;
        }

        const res = await fetch('/api/v1/testing/load-test', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            counts: interleavedChunks[i],
            batchSize,
            userId: 'synthetic-load-test',
            sourcePlatform: 'synthetic',
          }),
        });

        const data: ChunkResult = await res.json();

        if (data.status !== 'success') {
          throw new Error(data.status || 'Unknown server error');
        }

        cumulativeRecords += data.totalRecords;
        const elapsedMs = Math.round(performance.now() - startTime);

        // Accumulate per-type metrics
        for (const tm of data.perType) {
          const existing = typeAccum.get(tm.recordType) ?? { records: 0, durationMs: 0 };
          existing.records += tm.recordCount;
          existing.durationMs += tm.durationMs;
          typeAccum.set(tm.recordType, existing);
        }

        setState({
          phase: 'running',
          chunksCompleted: i + 1,
          chunksTotal: interleavedChunks.length,
          totalRecords: cumulativeRecords,
          totalDurationMs: elapsedMs,
          recordsPerSec: elapsedMs > 0 ? Math.round((cumulativeRecords / elapsedMs) * 1000) : 0,
          perType: new Map(typeAccum),
        });
      }

      const finalMs = Math.round(performance.now() - startTime);
      setState((prev) => ({
        ...prev,
        phase: 'complete',
        totalDurationMs: finalMs,
        recordsPerSec: finalMs > 0 ? Math.round((cumulativeRecords / finalMs) * 1000) : 0,
      }));
    } catch (err) {
      const finalMs = Math.round(performance.now() - startTime);
      setState((prev) => ({
        ...prev,
        phase: 'error',
        totalDurationMs: finalMs,
        error: err instanceof Error ? err.message : String(err),
      }));
    }
  }, [counts, chunkSize, batchSize]);

  const stopTest = useCallback(() => {
    abortRef.current = true;
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
                <div key={rt} className="flex items-center gap-3">
                  <label className="text-xs font-mono text-[var(--dbx-lava-500)] w-32 flex-shrink-0">
                    {rt}
                  </label>
                  <input
                    type="number"
                    min={0}
                    value={counts[rt] ?? 0}
                    onChange={(e) => updateCount(rt, parseInt(e.target.value) || 0)}
                    disabled={state.phase === 'running'}
                    className="flex-1 bg-[var(--muted)] border border-[var(--border)] rounded-lg px-3 py-1.5 text-sm font-mono text-[var(--foreground)] disabled:opacity-50"
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

          {/* Advanced settings */}
          <div className="bg-[var(--card)] border border-[var(--border)] rounded-xl p-5">
            <h3 className="font-bold text-sm text-[var(--foreground)] mb-3">Advanced</h3>
            <div className="space-y-3">
              <div>
                <label className="block text-xs text-[var(--muted-foreground)] mb-1">
                  Chunk size (payloads per HTTP request)
                </label>
                <input
                  type="number"
                  min={1}
                  max={10000}
                  value={chunkSize}
                  onChange={(e) => setChunkSize(parseInt(e.target.value) || 500)}
                  disabled={state.phase === 'running'}
                  className="w-full bg-[var(--muted)] border border-[var(--border)] rounded-lg px-3 py-1.5 text-sm font-mono text-[var(--foreground)] disabled:opacity-50"
                />
              </div>
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
                  {state.chunksCompleted}/{state.chunksTotal} chunks
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
