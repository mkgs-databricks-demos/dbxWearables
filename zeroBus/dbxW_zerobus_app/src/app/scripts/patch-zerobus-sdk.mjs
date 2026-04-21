#!/usr/bin/env node
/**
 * patch-zerobus-sdk.mjs
 *
 * Copies the locally-built NAPI-RS JS shim (index.js + index.d.ts) into
 * node_modules/@databricks/zerobus-ingest-sdk/.
 *
 * Why: The published npm tarball for @databricks/zerobus-ingest-sdk@1.0.0
 * is missing index.js and index.d.ts — the NAPI-RS build step was not run
 * before `npm publish`. The pre-built .node binaries for all 5 platforms
 * ARE included, but without the JS entry point that loads them, Node.js
 * throws ERR_MODULE_NOT_FOUND at runtime.
 *
 * The user builds the SDK locally (requires Rust 1.70+) and copies the
 * generated index.js + index.d.ts into patches/zerobus-ingest-sdk/.
 * This script is run via postinstall to apply the patch after every
 * `npm install`.
 *
 * Local build steps:
 *   git clone https://github.com/databricks/zerobus-sdk.git
 *   cd zerobus-sdk/typescript
 *   npm install && npm run build
 *   cp index.js index.d.ts <app>/patches/zerobus-ingest-sdk/
 *
 * See: fixtures/issues/zerobus-sdk-missing-platform-binaries.md
 */

import { existsSync, copyFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");

const PATCH_DIR = join(ROOT, "patches", "zerobus-ingest-sdk");
const TARGET_DIR = join(ROOT, "node_modules", "@databricks", "zerobus-ingest-sdk");

const FILES = ["index.js", "index.d.ts"];

// ── Check prerequisites ──────────────────────────────────────────────────

if (!existsSync(PATCH_DIR)) {
  console.log(
    "[patch:zerobus-sdk] No patches directory found at patches/zerobus-ingest-sdk/"
  );
  console.log(
    "[patch:zerobus-sdk] To create it, build the SDK locally (requires Rust 1.70+):"
  );
  console.log(
    "[patch:zerobus-sdk]   git clone https://github.com/databricks/zerobus-sdk.git"
  );
  console.log(
    "[patch:zerobus-sdk]   cd zerobus-sdk/typescript && npm install && npm run build"
  );
  console.log(
    "[patch:zerobus-sdk]   cp index.js index.d.ts <app>/patches/zerobus-ingest-sdk/"
  );
  process.exit(0); // non-fatal
}

if (!existsSync(TARGET_DIR)) {
  console.log(
    "[patch:zerobus-sdk] Target not found: node_modules/@databricks/zerobus-ingest-sdk/"
  );
  console.log(
    "[patch:zerobus-sdk] The SDK package may not be installed. Skipping patch."
  );
  process.exit(0); // non-fatal
}

// ── Apply patches ────────────────────────────────────────────────────────

let patched = 0;
let missing = 0;

for (const file of FILES) {
  const src = join(PATCH_DIR, file);
  const dst = join(TARGET_DIR, file);

  if (!existsSync(src)) {
    console.log(`[patch:zerobus-sdk] SKIP ${file} (not found in patches/)`);
    missing++;
    continue;
  }

  copyFileSync(src, dst);
  console.log(`[patch:zerobus-sdk] OK   ${file} -> node_modules/@databricks/zerobus-ingest-sdk/`);
  patched++;
}

// ── Summary ──────────────────────────────────────────────────────────────

if (patched > 0) {
  console.log(
    `[patch:zerobus-sdk] Patched ${patched}/${FILES.length} files. SDK should now load at runtime.`
  );
} else {
  console.log(
    `[patch:zerobus-sdk] WARNING: No files were patched (${missing} missing from patches/).`
  );
}
