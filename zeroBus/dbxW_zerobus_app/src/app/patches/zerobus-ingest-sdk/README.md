# ZeroBus Ingest SDK Patch

This directory holds locally-built files that are missing from the published
`@databricks/zerobus-ingest-sdk@1.0.0` npm tarball.

## Problem

The SDK's `package.json` declares `"main": "index.js"`, but `index.js` and
`index.d.ts` were not included in the published tarball. The NAPI-RS build
step that generates the JS shim (which loads the correct platform-specific
`.node` binary) was not run before `npm publish`.

The pre-built `.node` binaries for all 5 platforms ARE present in the tarball.
Only the JS entry point is missing.

See: `fixtures/issues/zerobus-sdk-missing-platform-binaries.md`

## Required Files

Place these two files in this directory:

| File | Source | Purpose |
| --- | --- | --- |
| `index.js` | Built by `napi build` | NAPI-RS JS shim — detects platform, loads `.node` binary |
| `index.d.ts` | Built by `napi build` | TypeScript type definitions |

## How to Build Locally

### Prerequisites

**macOS (Homebrew):**

```bash
# Xcode Command Line Tools — provides the C/C++ linker and system headers
# required by Rust's cc crate and any native compilation
xcode-select --install

# Rust toolchain 1.70+ — compiles the .node binary from Rust source
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup install 1.95.0
rustup default 1.95.0    # or a newer stable version

# protobuf — the SDK uses gRPC/tonic which requires the protoc compiler
brew install protobuf

# Node.js 18+ and npm — required for napi-rs CLI and npm run build
brew install node
```

| Dependency | Why | Install |
| --- | --- | --- |
| Xcode CLT | C linker, system headers (Rust `cc` crate) | `xcode-select --install` |
| Rust 1.70+ | Compiles native `.node` binary | `rustup install 1.70` |
| protobuf (`protoc`) | gRPC/tonic code generation | `brew install protobuf` |
| Node.js 18+ | NAPI-RS CLI, `npm run build` | `brew install node` |
| Python 3 (optional) | Some `node-gyp` native deps use `gyp` | Usually pre-installed on macOS |

**Verify prerequisites:**

```bash
xcode-select -p          # /Library/Developer/CommandLineTools (or Xcode.app path)
rustc --version           # rustc 1.70.0 or newer
protoc --version          # libprotoc 3.x / 4.x / 5.x
node --version            # v18.x or newer
npm --version             # 9.x or newer
```

### Build Steps

```bash
# 1. Clone the SDK
git clone https://github.com/databricks/zerobus-sdk.git
cd zerobus-sdk/typescript

# 2. Install dependencies and build
npm install
npm run build

# 3. Verify the generated files
ls -la index.js index.d.ts

# 4. Copy into this patches directory
cp index.js index.d.ts /path/to/dbxW_zerobus_app/src/app/patches/zerobus-ingest-sdk/
```

### Troubleshooting the Local Build

| Error | Cause | Fix |
| --- | --- | --- |
| `linker 'cc' not found` | Missing Xcode CLT | `xcode-select --install` |
| `protoc not found` or `Could not find protoc` | Missing protobuf compiler | `brew install protobuf` |
| `error[E0658]: use of unstable library feature` | Rust version too old | `rustup update && rustup default stable` |
| `node-gyp` rebuild errors | Missing Python or build tools | `brew install python-setuptools` |
| `napi build` not found | NAPI-RS CLI not installed | Should be in devDeps; run `npm install` first |
| Permission denied on `/usr/local/lib` | Homebrew permissions | `sudo chown -R $(whoami) /usr/local/lib` |

## How the Patch is Applied

The `postinstall` script in `package.json` runs `scripts/patch-zerobus-sdk.mjs`,
which copies `index.js` and `index.d.ts` from this directory into
`node_modules/@databricks/zerobus-ingest-sdk/`. This happens automatically
after every `npm install` — including in the Databricks Apps container during
deployment.

## When to Remove This Patch

Once the SDK team publishes a fixed tarball that includes `index.js`, this
patch directory and the `patch:zerobus-sdk` script can be removed. Check with:

```bash
npm pack @databricks/zerobus-ingest-sdk --dry-run 2>&1 | grep index.js
```

If `index.js` appears in the file list, the patch is no longer needed.
