/**
 * OpenTelemetry instrumentation bootstrap.
 *
 * This file MUST be loaded before any application code (via node --import)
 * so that auto-instrumentation can monkey-patch Node.js modules (http,
 * express, pg, etc.) before they are first imported.
 *
 * When app telemetry is enabled in the Databricks App resource definition,
 * the platform auto-injects:
 *   OTEL_EXPORTER_OTLP_ENDPOINT  = http://localhost:4314
 *   OTEL_EXPORTER_OTLP_PROTOCOL  = grpc
 *   OTEL_SERVICE_NAME            = <app-name>
 *   OTEL_RESOURCE_ATTRIBUTES     = workspace.id=<id>,app.name=<name>
 *   OTEL_BSP_*  / OTEL_BLRP_*   = batch processor config
 *
 * The SDK reads these env vars automatically — no hardcoded endpoints here.
 *
 * @see https://docs.databricks.com/aws/en/dev-tools/databricks-apps/observability/
 */

import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { PeriodicExportingMetricReader } from '@opentelemetry/sdk-metrics';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-proto';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-proto';
import { OTLPLogExporter } from '@opentelemetry/exporter-logs-otlp-proto';
import {
  BatchLogRecordProcessor,
  LoggerProvider,
} from '@opentelemetry/sdk-logs';

// ---------------------------------------------------------------------------
// Initialize the OpenTelemetry Node SDK
// ---------------------------------------------------------------------------

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter(),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter(),
    // Export metrics every 10s (platform batch config handles span/log timing)
    exportIntervalMillis: 10_000,
  }),
  logRecordProcessor: new BatchLogRecordProcessor(new OTLPLogExporter()),
  instrumentations: [
    getNodeAutoInstrumentations({
      // Disable fs instrumentation — too noisy for bundled apps
      '@opentelemetry/instrumentation-fs': { enabled: false },
      // Disable dns to reduce noise
      '@opentelemetry/instrumentation-dns': { enabled: false },
    }),
  ],
});

try {
  sdk.start();
  console.log('[otel] OpenTelemetry SDK initialized');
} catch (err) {
  console.error('[otel] Failed to start OpenTelemetry SDK:', err);
}

// ---------------------------------------------------------------------------
// Graceful shutdown — flush pending telemetry before process exits
// ---------------------------------------------------------------------------

async function shutdown(): Promise<void> {
  console.log('[otel] Shutting down OpenTelemetry SDK...');
  try {
    await sdk.shutdown();
    console.log('[otel] OpenTelemetry SDK shut down successfully');
  } catch (err) {
    console.error('[otel] OpenTelemetry SDK shutdown error:', err);
  } finally {
    process.exit(0);
  }
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
