# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Read AGENTS.md first

`AGENTS.md` is the canonical reference for **build/test/lint commands** and **code style** (ArkTS rules, naming, imports, error handling, logging, design patterns). It is detailed and current — don't duplicate it here. This file covers only the cross-file architecture that AGENTS.md doesn't.

Two reminders that bite constantly when editing `.ets`:
- **ArkTS is not TypeScript.** No object spread (`...`), no object destructuring. Merge/access properties manually (look for `merge*` helpers).
- Use the project logger (`getLogger(TAG)`), not `hilog` directly — except in `entry/` demo code.

## Quick command reference

```bash
ohpm install                                          # install deps
hvigorw assembleHsp                                   # build SDK (apm, native_error_demo) — HSP
hvigorw assembleHap                                   # build demo app (entry) — HAP
hvigorw lint                                          # code-linter.json5 rules
hvigorw --mode module -p module=apm@default test      # unit tests (no single-test CLI flag; use it.only / List.test.ets)
```

## Module layout (build-profile.json5)

Three Hvigor modules:
- **`apm`** — the SDK itself, packaged as an HSP (shared library). This is where nearly all work happens.
- **`entry`** — demo HAP that consumes `apm` to exercise the SDK.
- **`native_error_demo`** — HSP exposing C++ functions that deliberately crash, for testing native-crash capture.

Cross-module imports use bare names (`import ... from 'apm'`); within a module use relative paths. The SDK's public surface is the barrel `apm/Index.ets` → `ApmStarter`, `APMConfig`, `APMConfigBuilder`.

## Initialization & threading model — the key thing to understand

Entry point is `ApmStarter.start(context, config)` (`apm/src/main/ets/apm/ApmStarter.ets`). It does **two** initializations on **two threads**, and this is the most important architectural fact:

1. **Main thread**: `APMCore.init(config).startCacheServices().startNetConService().onError(...)` — runs cache cleanup/upload, the network-recovery listener, and JS error capture (`errorManager.on('globalErrorOccurred' / 'globalUnhandledRejectionDetected'`, with a fallback to the legacy `error`/`unhandledRejection` API).
2. **Worker thread** via `withLongTask(...)` → `@Concurrent function startMonitorServices` → `APMCore.init(config).startMonitorServices()` — runs AppFreeze + native-crash monitoring.

Because `taskpool`/`@Concurrent` workers don't share heap, **each thread constructs its own `APMCore` singleton** independently. `APMCore.init()` throws if called twice *on the same thread*, but is expected to run once per thread. Anything you add must work given this duplicated-singleton reality. `config` passed to the worker is run through `filterConfig()` first because `@Concurrent` args must be serializable (no functions/context) — e.g. `setUserIdFunc` cannot cross the boundary.

`APMCore.reset()` exists to tear down the singleton for tests (it stops scheduled-cleanup timers to avoid leaks).

## `APMCore` is the orchestrator

`apm/src/main/ets/apm/core/APMCore.ets` constructs and wires every service; it owns no monitoring logic itself, only sequencing. Services live in `apm/src/main/ets/apm/services/`:

- `NetworkService` — connectivity checks + `registerNetConnListen` (fires cache re-upload on network recovery).
- `TokenService` — auth token fetch/cache (depends on NetworkService).
- `CacheService` — the disk-persistence funnel; all "save a report to disk" logic converges here (e.g. `saveJsError`).
- `EncryptCompressService` — AES-256-CBC encrypt + GZIP (keys from `config.keys[0]`/`[1]`).
- `ReportService` — builds the upload payload, encrypts/compresses/zips, uploads with retry/backoff.
- `CacheScanUploadService` — scans cached files and back-fills uploads (`scanAndUpload`); guarded by an `isScanning` flag in APMCore.
- `AppMonitorService`, `NativeCrashService` — start the data-collection monitors.

The two public report paths: `APMCore.reportError(...)` (JS errors — **always lands on disk via CacheService first**, then attempts immediate upload; offline reports are back-filled by the scan), and `APMCore.reportFile(payload, source)` (file/ZIP uploads, skipped when offline).

## Data-collection pipeline

`apm/src/main/ets/apm/data_collection/` captures system events: `event/EventChannel.ets`, `ApmEventMonitor`, and `event/system/` (including `crash/`) subscribe to HarmonyOS system events (`APP_FREEZE`, etc.) and feed them back into the report path.

## `platform/` is the OS-abstraction seam

Services never touch HarmonyOS `@kit.*` file/crypto/network/compression APIs directly — they go through `apm/src/main/ets/apm/platform/` (`FileSystem`, `Crypto`, `NetworkClient`, `Compression`). Every service in `services/` imports from here. When adding an OS-level capability, extend the relevant platform module rather than calling the SDK from a service, so the dependency stays in one place.

## Native crash handling (C++ ↔ ArkTS bridge)

`apm/src/main/cpp/` (built via `CMakeLists.txt`, exposed through NAPI in `napi_init.cpp` / `crash_napi.cpp`, typed in `cpp/types/libapm/Index.d.ts`):

The signal handler (`signal_handler.cpp`) catches SIGSEGV/SIGABRT/SIGFPE/SIGILL/SIGBUS, then uses a **Crash Delayer** (`sigsuspend`) to keep the process alive so the ArkTS layer can persist + upload the crash before exit. HiAppEvent delivers the crash to ArkTS; ArkTS signals completion back with **SIGUSR2**; a 3s timeout guards against hangs. See `docs/apm_crash_handling_architecture.md`, `docs/native_crash_design.md`, and `docs/native_crash_signal_mapping.md` before touching this path.

## Cross-cutting `with*` wrappers

`apm/src/main/ets/apm/utils/` provides functional wrappers used pervasively instead of ad-hoc control flow — `withRetry`, `withLock`/`withLockSync`, `withTimeout`, `withTiming`/`withTimingSync`, `withResource`, `withTask`/`withLongTask`. Prefer composing these (as APMCore/ApmStarter do) over hand-rolling retry/locking/timing. They're re-exported from `utils/index.ets`.
