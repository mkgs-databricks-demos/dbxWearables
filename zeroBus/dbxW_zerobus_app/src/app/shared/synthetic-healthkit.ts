// Synthetic HealthKit Data Generator — Shared Module
//
// Pure utility functions for generating realistic Apple HealthKit test data.
// Ported from validate-zerobus-ingest.ipynb (Python) to TypeScript.
//
// Isomorphic: works in both browser (DocsPage Try It panel) and Node.js
// (server-side synthetic-data-service for bulk load testing).
//
// Uses realistic statistical distributions:
//   - Gaussian (Box-Muller) for heart rate, step count, SpO2, respiratory rate
//   - Triangular for workout duration, sleep hours, activity calories
//   - Uniform for time offsets, distance variance
//
// Sample payloads produce variable record counts (1-8, avg ~3.4) with
// randomly selected HealthKit quantity types weighted by real-world frequency.
//
// Every call generates fresh UUIDs and timestamps anchored to Date.now().

// ── Types ────────────────────────────────────────────────────────────────

export type RecordType =
  | 'samples'
  | 'workouts'
  | 'sleep'
  | 'activity_summaries'
  | 'deletes';

export interface GeneratedPayload {
  /** NDJSON string — one JSON object per line, ready for POST body */
  ndjson: string;
  /** Parsed records (same data as ndjson, but as objects) */
  records: Record<string, unknown>[];
  /** Number of records in this payload */
  recordCount: number;
  /** Human-readable description of what was generated */
  description: string;
}

// ── Statistical Distributions ────────────────────────────────────────────

/** Gaussian random using Box-Muller transform */
export function gaussRandom(mean: number, stdDev: number): number {
  const u1 = Math.random();
  const u2 = Math.random();
  const z = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
  return mean + z * stdDev;
}

/** Triangular distribution random */
export function triangularRandom(
  min: number,
  max: number,
  mode: number,
): number {
  const u = Math.random();
  const fc = (mode - min) / (max - min);
  if (u < fc) {
    return min + Math.sqrt(u * (max - min) * (mode - min));
  }
  return max - Math.sqrt((1 - u) * (max - min) * (max - mode));
}

// ── Primitive Helpers ────────────────────────────────────────────────────

/** Generate uppercase UUID matching HealthKit format */
export function uuid(): string {
  return crypto.randomUUID().toUpperCase();
}

/** Format Date as ISO 8601 UTC string (no milliseconds) */
export function iso(date: Date): string {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

/** Add hours to a date */
export function addHours(date: Date, hours: number): Date {
  return new Date(date.getTime() + hours * 60 * 60 * 1000);
}

/** Add minutes to a date */
export function addMinutes(date: Date, minutes: number): Date {
  return new Date(date.getTime() + minutes * 60 * 1000);
}

/** Random choice from array */
export function randomChoice<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

// ── Biometric Value Generators ───────────────────────────────────────────

/** Heart rate: resting 55-85, occasional elevated 90-140 */
export function heartRate(): number {
  if (Math.random() > 0.2) {
    return Math.round(gaussRandom(72, 12) * 10) / 10;
  }
  return Math.round((90 + Math.random() * 50) * 10) / 10;
}

/** Step count: ~4000-8000 steps/hour walking */
export function stepCount(durationHours: number = 1.0): number {
  const base = gaussRandom(5500, 1500) * durationHours;
  return Math.round(Math.max(100, base));
}

/** Workout duration: most 20-60 min, some longer */
export function workoutDurationMin(): number {
  return Math.round(triangularRandom(15, 90, 35));
}

/** Calories from duration: ~8-12 kcal/min for moderate activity */
export function caloriesFromDuration(
  durationMin: number,
  intensity: number = 1.0,
): number {
  return (
    Math.round(durationMin * (8 + Math.random() * 4) * intensity * 10) / 10
  );
}

/** Distance from duration based on activity type (meters) */
export function distanceFromDuration(
  durationMin: number,
  activity: string,
): number {
  const pacePerMin: Record<string, number> = {
    running: 180,
    walking: 85,
    cycling: 350,
    swimming: 50,
  };
  const pace = pacePerMin[activity] || 100;
  return Math.round(durationMin * pace * (0.8 + Math.random() * 0.4));
}

/** Sleep hours: 6.5-8.5 typical */
export function sleepHours(): number {
  return Math.round(triangularRandom(5.5, 9.5, 7.5) * 100) / 100;
}

// ── Sample Type Registry ─────────────────────────────────────────────────
//
// Each entry defines how to generate a realistic HealthKit quantity sample.
// Used by generateSamplesPayload() to produce variable-type, variable-count
// payloads that mimic real iOS sync batches. Weights approximate real-world
// frequency: heart rate and step count dominate, vitals are less common.

interface SampleTypeConfig {
  type: string;
  unit: string;
  value: () => number;
  sources: string[];
  /** If true, end_date = start_date + random duration; else point-in-time */
  isDuration: boolean;
  /** Duration range in minutes [min, max] — only when isDuration is true */
  durationRange?: [number, number];
  /** Optional metadata generator */
  metadata?: () => Record<string, string> | null;
  /** Relative weight for random selection (higher = more frequent) */
  weight: number;
}

const SAMPLE_TYPES: SampleTypeConfig[] = [
  {
    type: 'HKQuantityTypeIdentifierHeartRate',
    unit: 'count/min',
    value: heartRate,
    sources: ['Apple Watch'],
    isDuration: false,
    metadata: () => Math.random() > 0.4
      ? { HKMetadataKeyHeartRateMotionContext: String(randomChoice([0, 1, 2])) }
      : null,
    weight: 3,
  },
  {
    type: 'HKQuantityTypeIdentifierStepCount',
    unit: 'count',
    value: () => stepCount(0.5 + Math.random() * 1.5),
    sources: ['iPhone', 'Apple Watch'],
    isDuration: true,
    durationRange: [15, 120],
    weight: 2,
  },
  {
    type: 'HKQuantityTypeIdentifierActiveEnergyBurned',
    unit: 'kcal',
    value: () => Math.round(triangularRandom(50, 400, 180) * 10) / 10,
    sources: ['Apple Watch'],
    isDuration: true,
    durationRange: [15, 60],
    weight: 2,
  },
  {
    type: 'HKQuantityTypeIdentifierBasalEnergyBurned',
    unit: 'kcal',
    value: () => Math.round(triangularRandom(50, 90, 65) * 10) / 10,
    sources: ['Apple Watch'],
    isDuration: true,
    durationRange: [55, 65],
    weight: 1,
  },
  {
    type: 'HKQuantityTypeIdentifierRestingHeartRate',
    unit: 'count/min',
    value: () => Math.round(gaussRandom(62, 8) * 10) / 10,
    sources: ['Apple Watch'],
    isDuration: false,
    weight: 1,
  },
  {
    type: 'HKQuantityTypeIdentifierHeartRateVariabilitySDNN',
    unit: 'ms',
    value: () => Math.max(5, Math.round(gaussRandom(45, 15) * 10) / 10),
    sources: ['Apple Watch'],
    isDuration: false,
    weight: 1,
  },
  {
    type: 'HKQuantityTypeIdentifierOxygenSaturation',
    unit: '%',
    value: () => Math.min(100, Math.max(90, Math.round(gaussRandom(97.5, 1.2) * 10) / 10)),
    sources: ['Apple Watch'],
    isDuration: false,
    weight: 1,
  },
  {
    type: 'HKQuantityTypeIdentifierRespiratoryRate',
    unit: 'count/min',
    value: () => Math.max(8, Math.round(gaussRandom(15, 2) * 10) / 10),
    sources: ['Apple Watch'],
    isDuration: false,
    weight: 1,
  },
  {
    type: 'HKQuantityTypeIdentifierDistanceWalkingRunning',
    unit: 'm',
    value: () => Math.max(10, Math.round(gaussRandom(800, 400))),
    sources: ['iPhone', 'Apple Watch'],
    isDuration: true,
    durationRange: [5, 45],
    weight: 2,
  },
  {
    type: 'HKQuantityTypeIdentifierFlightsClimbed',
    unit: 'count',
    value: () => 1 + Math.floor(Math.random() * 8),
    sources: ['iPhone', 'Apple Watch'],
    isDuration: true,
    durationRange: [2, 15],
    weight: 1,
  },
];

// Pre-compute weighted selection array for O(1) random picks
const _weightedSampleTypes: SampleTypeConfig[] = [];
for (const config of SAMPLE_TYPES) {
  for (let i = 0; i < config.weight; i++) {
    _weightedSampleTypes.push(config);
  }
}

/** Pick a random sample type, weighted by real-world frequency */
function randomSampleType(): SampleTypeConfig {
  return randomChoice(_weightedSampleTypes);
}

/**
 * Random sample count per payload: 1-8, skewed toward 2-4.
 *
 * Distribution: 1 (5%), 2 (20%), 3 (30%), 4 (25%), 5 (10%), 6-8 (10%)
 * Weighted average: ~3.4 records per payload
 */
function randomSampleCount(): number {
  const r = Math.random();
  if (r < 0.05) return 1;
  if (r < 0.25) return 2;
  if (r < 0.55) return 3;
  if (r < 0.80) return 4;
  if (r < 0.90) return 5;
  return 6 + Math.floor(Math.random() * 3);
}

/** Generate a single HealthKit quantity sample record */
function generateSingleSample(config: SampleTypeConfig, now: Date): Record<string, unknown> {
  const startTime = addHours(now, -(Math.random() * 6));
  let endTime = startTime;

  if (config.isDuration && config.durationRange) {
    const [minMin, maxMin] = config.durationRange;
    const durationMin = minMin + Math.random() * (maxMin - minMin);
    endTime = addMinutes(startTime, durationMin);
  }

  return {
    uuid: uuid(),
    type: config.type,
    value: config.value(),
    unit: config.unit,
    start_date: iso(startTime),
    end_date: iso(endTime),
    source_name: randomChoice(config.sources),
    source_bundle_id: `com.apple.health.${uuid()}`,
    metadata: config.metadata ? config.metadata() : null,
  };
}

// ── Per-Record-Type Payload Generators ───────────────────────────────────

/**
 * Generate samples payload: variable count (1-8) of mixed HealthKit sample types.
 *
 * Mirrors real iOS sync behavior where each POST contains a variable number
 * of samples collected since the last sync — some heart rate, some steps,
 * some active energy, etc. The mix and count vary every call.
 *
 * Average: ~3.4 records per payload (weighted toward 2-4).
 * Types: weighted random from 10 HealthKit quantity types.
 */
export function generateSamplesPayload(): GeneratedPayload {
  const now = new Date();
  const count = randomSampleCount();
  const records: Record<string, unknown>[] = [];
  const typeCounts = new Map<string, number>();

  for (let i = 0; i < count; i++) {
    const config = randomSampleType();
    records.push(generateSingleSample(config, now));
    const shortType = config.type.replace('HKQuantityTypeIdentifier', '');
    typeCounts.set(shortType, (typeCounts.get(shortType) || 0) + 1);
  }

  // Build description like "3 samples (2 HeartRate, 1 StepCount)"
  const typeDesc = Array.from(typeCounts.entries())
    .map(([t, n]) => `${n} ${t}`)
    .join(', ');

  return {
    ndjson: records.map((r) => JSON.stringify(r)).join('\n'),
    records,
    recordCount: records.length,
    description: `${count} sample${count > 1 ? 's' : ''} (${typeDesc})`,
  };
}

/** Generate workouts payload: 1 running/walking/cycling session */
export function generateWorkoutsPayload(): GeneratedPayload {
  const now = new Date();
  const workoutStart = addHours(now, -(4 + Math.random() * 6));
  const durationMin = workoutDurationMin();
  const activity = randomChoice(['running', 'walking', 'cycling']);
  const activityRawMap: Record<string, number> = {
    running: 37,
    walking: 52,
    cycling: 13,
  };

  const records = [
    {
      uuid: uuid(),
      activity_type: activity,
      activity_type_raw: activityRawMap[activity] || 0,
      start_date: iso(workoutStart),
      end_date: iso(addMinutes(workoutStart, durationMin)),
      duration_seconds: durationMin * 60,
      total_energy_burned_kcal: caloriesFromDuration(durationMin),
      total_distance_meters: distanceFromDuration(durationMin, activity),
      source_name: 'Apple Watch',
      metadata: null,
    },
  ];

  return {
    ndjson: records.map((w) => JSON.stringify(w)).join('\n'),
    records,
    recordCount: records.length,
    description: `1 ${activity} session (${durationMin} min)`,
  };
}

/** Generate sleep payload: 1 session with 4 realistic stage breakdowns */
export function generateSleepPayload(): GeneratedPayload {
  const now = new Date();
  const sleepHr = sleepHours();

  // Sleep ended this morning between 5-8 AM
  const sleepEnd = new Date(now);
  sleepEnd.setHours(
    5 + Math.floor(Math.random() * 4),
    Math.floor(Math.random() * 60),
    0,
    0,
  );
  if (sleepEnd > now) {
    sleepEnd.setDate(sleepEnd.getDate() - 1);
  }
  const sleepStart = addHours(sleepEnd, -sleepHr);

  // Stage breakdown: ~5% awake, ~50% core, ~20% deep, ~25% REM
  const stageFracs: [string, number][] = [
    ['awake', 0.05],
    ['asleepCore', 0.5],
    ['asleepDeep', 0.2],
    ['asleepREM', 0.25],
  ];

  let cursor = sleepStart;
  const stages = stageFracs.map(([stageName, frac]) => {
    const stageDurMs = sleepHr * frac * 60 * 60 * 1000;
    const stageStart = new Date(cursor);
    cursor = new Date(cursor.getTime() + stageDurMs);
    return {
      uuid: uuid(),
      stage: stageName,
      start_date: iso(stageStart),
      end_date: iso(cursor),
    };
  });

  const records = [
    {
      start_date: iso(sleepStart),
      end_date: iso(sleepEnd),
      stages,
    },
  ];

  return {
    ndjson: records.map((s) => JSON.stringify(s)).join('\n'),
    records,
    recordCount: records.length,
    description: `1 sleep session (${sleepHr.toFixed(1)} hours, 4 stages)`,
  };
}

/** Generate activity summaries payload: yesterday's rings */
export function generateActivitySummariesPayload(): GeneratedPayload {
  const now = new Date();
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);

  const activeCal =
    Math.round(triangularRandom(300, 700, 480) * 10) / 10;
  const exerciseMin = Math.round(triangularRandom(15, 60, 32));
  const standHr = 8 + Math.floor(Math.random() * 7);

  const records = [
    {
      date: yesterday.toISOString().split('T')[0],
      active_energy_burned_kcal: activeCal,
      active_energy_burned_goal_kcal: randomChoice([400.0, 500.0, 600.0]),
      exercise_minutes: exerciseMin,
      exercise_minutes_goal: 30.0,
      stand_hours: standHr,
      stand_hours_goal: 12,
    },
  ];

  return {
    ndjson: records.map((s) => JSON.stringify(s)).join('\n'),
    records,
    recordCount: records.length,
    description: `Yesterday's activity rings (${activeCal} kcal, ${exerciseMin} min, ${standHr} hrs)`,
  };
}

/**
 * Generate deletes payload: 1-3 soft-delete references.
 *
 * Distribution: 70% single, 18% double, 12% triple.
 * Average: ~1.4 records per payload.
 * References any of the 10 HealthKit sample types.
 */
export function generateDeletesPayload(): GeneratedPayload {
  const count = Math.random() < 0.7 ? 1 : (Math.random() < 0.6 ? 2 : 3);

  const deleteTypes = SAMPLE_TYPES.map((s) => s.type);
  const records = Array.from({ length: count }, () => ({
    uuid: uuid(),
    sample_type: randomChoice(deleteTypes),
  }));

  return {
    ndjson: records.map((d) => JSON.stringify(d)).join('\n'),
    records,
    recordCount: records.length,
    description: `${count} deletion${count > 1 ? 's' : ''} (soft-delete reference${count > 1 ? 's' : ''})`,
  };
}

// ── Dispatcher ───────────────────────────────────────────────────────────

const GENERATORS: Record<RecordType, () => GeneratedPayload> = {
  samples: generateSamplesPayload,
  workouts: generateWorkoutsPayload,
  sleep: generateSleepPayload,
  activity_summaries: generateActivitySummariesPayload,
  deletes: generateDeletesPayload,
};

/** All valid record types */
export const RECORD_TYPES: RecordType[] = Object.keys(GENERATORS) as RecordType[];

/** Generate a single payload for the given record type */
export function generatePayload(recordType: RecordType): GeneratedPayload {
  const generator = GENERATORS[recordType];
  if (!generator) {
    throw new Error(
      `Unknown record type: ${recordType}. Valid types: ${RECORD_TYPES.join(', ')}`,
    );
  }
  return generator();
}

/**
 * Generate multiple payloads for the given record type.
 *
 * Each call to the generator produces a fresh payload with unique UUIDs
 * and timestamps. Used by synthetic-data-service for bulk generation.
 *
 * @param recordType - HealthKit record type
 * @param count - Number of payloads to generate
 * @returns Array of generated payloads
 */
export function generatePayloadBatch(
  recordType: RecordType,
  count: number,
): GeneratedPayload[] {
  return Array.from({ length: count }, () => generatePayload(recordType));
}

/**
 * Generate payloads across all record types.
 *
 * Useful for integration tests that need coverage of every record type.
 *
 * @param countsPerType - Number of payloads per type (default: 1 each)
 * @returns Map of record type to array of generated payloads
 */
export function generateAllTypes(
  countsPerType: number = 1,
): Map<RecordType, GeneratedPayload[]> {
  const result = new Map<RecordType, GeneratedPayload[]>();
  for (const rt of RECORD_TYPES) {
    result.set(rt, generatePayloadBatch(rt, countsPerType));
  }
  return result;
}

/** Average records per payload by type — used for progress estimation */
export const AVG_RECORDS_PER_PAYLOAD: Record<RecordType, number> = {
  samples: 3.4,
  workouts: 1,
  sleep: 1,
  activity_summaries: 1,
  deletes: 1.4,
};
