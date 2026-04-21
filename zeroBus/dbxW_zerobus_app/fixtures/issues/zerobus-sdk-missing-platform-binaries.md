# `index.js` missing from published npm tarball — SDK unusable at runtime

**Repository:** https://github.com/databricks/zerobus-sdk/tree/main/typescript
**Package:** `@databricks/zerobus-ingest-sdk@1.0.0`
**Environment:** Databricks Apps (AppKit, Node.js v22.16.0, Linux x64)

---

## Summary

The published npm tarball for `@databricks/zerobus-ingest-sdk@1.0.0` declares `"main": "index.js"` in its `package.json`, but **`index.js` and `index.d.ts` are not included in the tarball**. The NAPI-RS pre-built `.node` binaries for all 5 platforms ARE present, but the JS entry point that loads them was never packaged. This causes `ERR_MODULE_NOT_FOUND` at runtime in any consumer.

## Root Cause

The tarball appears to have been published before the NAPI-RS build step (`napi build` or `npm run build`) that generates `index.js` (the JS shim that detects the platform and loads the correct `.node` binary). The Rust source (`src/lib.rs`, `build.rs`, `Cargo.toml`) and all 5 pre-built binaries are included, but the generated JS/TS artifacts are not.

## Tarball Contents (13 files, 11.7 MB)

Downloaded and inspected via:
```bash
npm pack @databricks/zerobus-ingest-sdk@1.0.0 --dry-run
```

| File | Size | Status |
| --- | --- | --- |
| `package.json` | 3.2 KB | Present — declares `"main": "index.js"` |
| **`index.js`** | — | **MISSING** (NAPI-RS loader shim) |
| **`index.d.ts`** | — | **MISSING** (TypeScript type definitions) |
| `Cargo.toml` | 1.5 KB | Present — Rust build config |
| `build.rs` | 65 B | Present — Rust build script |
| `src/lib.rs` | 61 KB | Present — Rust source |
| `src/headers_provider.ts` | 2.7 KB | Present — TS source (not compiled) |
| `utils/descriptor.ts` | 3.5 KB | Present — TS source (not compiled) |
| `schemas/air_quality.proto` | 217 B | Present — example proto |
| `README.md` | 39 KB | Present |
| `zerobus-ingest-sdk.linux-x64-gnu.node` | 5.4 MB | Present ✔ |
| `zerobus-ingest-sdk.linux-arm64-gnu.node` | 4.9 MB | Present ✔ |
| `zerobus-ingest-sdk.darwin-x64.node` | 4.7 MB | Present ✔ |
| `zerobus-ingest-sdk.darwin-arm64.node` | 4.3 MB | Present ✔ |
| `zerobus-ingest-sdk.win32-x64-msvc.node` | 6.4 MB | Present ✔ |

All 5 platform binaries are bundled correctly. Only the JS entry point is missing.

## Runtime Error

```
Error: Cannot find package
  '/app/python/source_code/node_modules/@databricks/zerobus-ingest-sdk/index.js'
  imported from /app/python/source_code/dist/services/zerobus-service.js
    at legacyMainResolve (node:internal/modules/esm/resolve:204:26)
    at packageResolve (node:internal/modules/esm/resolve:778:12)
    at moduleResolve (node:internal/modules/esm/resolve:854:18)
    at defaultResolve (node:internal/modules/esm/resolve:984:11)
  code: 'ERR_MODULE_NOT_FOUND'

Node.js v22.16.0
```

Node's ESM resolver finds the package directory, reads `package.json`, sees `"main": "index.js"`, calls `FSLegacyMainResolve` — and the file doesn't exist.

## Reproduction

```bash
# Download and inspect the tarball
mkdir /tmp/sdk-inspect && cd /tmp/sdk-inspect
npm pack @databricks/zerobus-ingest-sdk@1.0.0
tar -tzf databricks-zerobus-ingest-sdk-1.0.0.tgz | sort

# Confirm index.js is missing
tar -tzf databricks-zerobus-ingest-sdk-1.0.0.tgz | grep 'index\.js'
# (no output)

# Confirm .node binaries ARE present
tar -tzf databricks-zerobus-ingest-sdk-1.0.0.tgz | grep '\.node$'
# package/zerobus-ingest-sdk.darwin-arm64.node
# package/zerobus-ingest-sdk.darwin-x64.node
# package/zerobus-ingest-sdk.linux-arm64-gnu.node
# package/zerobus-ingest-sdk.linux-x64-gnu.node
# package/zerobus-ingest-sdk.win32-x64-msvc.node
```

## Suggested Fix

1. **Run the NAPI-RS build before publishing** — `napi build --release` (or `npm run build`) generates `index.js` and `index.d.ts` from the Rust bindings. These must be included in the tarball.

2. **Add generated files to the `files` array** in `package.json`:
   ```json
   "files": [
     "index.js",
     "index.d.ts",
     "*.node",
     "utils/",
     "src/headers_provider.ts",
     "schemas/"
   ]
   ```

3. **Add a `prepublishOnly` script** to prevent future regressions:
   ```json
   "scripts": {
     "prepublishOnly": "napi build --release && test -f index.js"
   }
   ```

## Additional Issues Found During Investigation

### 1. Missing `exports` field (ESM compatibility)

The package has `"main": "index.js"` but no `exports` field. When consumed by an ESM application (`"type": "module"`), Node.js falls back to `legacyMainResolve()`. Adding an `exports` field would provide proper ESM support:

```json
"exports": {
  ".": {
    "import": "./index.js",
    "require": "./index.js",
    "types": "./index.d.ts"
  },
  "./utils/descriptor": {
    "import": "./utils/descriptor.js",
    "types": "./utils/descriptor.d.ts"
  }
}
```

### 2. Phantom `apache-arrow` peer dependency

The package declares `peerOptional: "apache-arrow": "^56.0.0"` but `apache-arrow@^56.0.0` does not exist on npm (latest published is ~18.x). This causes `npm error code ETARGET` during install. Workaround: add `"apache-arrow": "^21.1.0"` to the consumer's `overrides`.

### 3. Platform binary packages declared but not published

The 5 `optionalDependencies` packages (`@databricks/zerobus-ingest-sdk-linux-x64-gnu`, etc.) all return 404 on npm. This is a secondary issue since the binaries are bundled in the main tarball, but the orphaned `optionalDependencies` entries add confusion during `npm install` (ERESOLVE warnings).

### 4. TypeScript source files shipped uncompiled

`src/headers_provider.ts` and `utils/descriptor.ts` are included as raw `.ts` files without compiled `.js` counterparts. Consumers using `import { loadDescriptorProto } from '@databricks/zerobus-ingest-sdk/utils/descriptor'` (as shown in the README) will get module resolution errors since Node.js cannot import `.ts` files directly.

## Environment Details

* **Databricks Apps container:** Linux x64, Node.js v22.16.0
* **Consumer app:** ESM (`"type": "module"`), built with tsdown v0.20.3 / rolldown v1.0.0-rc.3
* **tsconfig:** `moduleResolution: "bundler"`, `module: "ESNext"`
* **SDK version:** `@databricks/zerobus-ingest-sdk@1.0.0` (only published version)

## Impact

The SDK is completely unusable as published. Every consumer will hit `ERR_MODULE_NOT_FOUND` at runtime regardless of platform, since the JS entry point is missing from the tarball.
