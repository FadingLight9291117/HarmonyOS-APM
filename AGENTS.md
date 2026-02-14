# AGENTS.md — HarmonyOS-APM

## Project Overview

HarmonyOS APM (Application Performance Monitoring) SDK built with ArkTS and C++.
Modules: `apm` (core SDK library, HSP), `entry` (demo app, HAP), `native_error_demo` (crash simulator, HSP).
Target: HarmonyOS SDK 6.0.0(20), Stage Model.

## Build System

Build tool: **Hvigor** (HarmonyOS build system, similar to Gradle).
Package manager: **OHPM** (OpenHarmony Package Manager).

```bash
# Install dependencies
ohpm install

# Build the project (run from DevEco Studio or CLI)
hvigorw assembleHap           # Build entry HAP
hvigorw assembleHsp           # Build shared packages (apm, native_error_demo)
hvigorw clean                 # Clean build artifacts

# Lint (HarmonyOS built-in code linter, configured in code-linter.json5)
hvigorw lint                  # Run code linter on all .ets files
```

## Test Commands

Test framework: `@ohos/hypium` (v1.0.24) with `@ohos/hamock` (v1.0.0) for mocking.
Test files live in `<module>/src/test/` (unit) and `<module>/src/ohosTest/` (instrumented).
Entry point: `List.test.ets` in each test directory.

```bash
# Run all unit tests for a module
hvigorw --mode module -p module=apm@default test

# Run instrumented (device) tests
hvigorw --mode module -p module=apm@default ohosTest

# Run a single test: No built-in single-test CLI flag.
# Filter by editing the test's List.test.ets to import only the target test file,
# or use `describe.only` / `it.only` within the Hypium test file.
```

## Code Linting

Configured in `code-linter.json5`. Applies to `**/*.ets` files (excludes test/mock/build dirs).
Rule sets:
- `plugin:@performance/recommended`
- `plugin:@typescript-eslint/recommended`
- All `@security/no-unsafe-*` rules set to `error` (AES, hash, RSA, DH, DSA, 3DES, etc.)

## Project Structure

```
apm/
  Index.ets                          # Public API: ApmStarter, APMConfig, APMConfigBuilder
  src/main/ets/apm/
    ApmStarter.ets                   # SDK entry point
    core/APMCore.ets                 # Core singleton, orchestrates all services
    config/                          # Config types, defaults, builder, manager
    services/                        # TokenService, NetworkService, ReportService, CacheService, etc.
    utils/                           # Functional wrappers (withRetry, withLock, withTimeout, etc.)
    types/                           # Report/network/upload type definitions
    platform/                        # Platform abstractions (FileSystem, Crypto, NetworkClient, Compression)
    cache/                           # Cache save/scan/clean/use logic
    data_collection/                 # Event monitoring (EventChannel, AppMonitor, NativeCrash)
  src/main/cpp/                      # Native C++ crash handler (NAPI)
entry/
  src/main/ets/                      # Demo app (EntryAbility, pages)
native_error_demo/
  src/main/cpp/                      # Native crash simulation functions
```

## Code Style Guidelines

### Language

- **ArkTS** (`.ets`) — HarmonyOS's extended TypeScript. Stricter than TS: no object spread
  (`...`), no object destructuring. Access properties manually instead.
- **C++** for native crash handlers, built via CMake.

### Imports

- Use **relative paths** within a module (`'./config/types'`, `'../utils'`).
- Use **bare module names** for cross-module imports (`'apm'`, `'native_error_demo'`).
- Use **`@kit.*`** for HarmonyOS SDK imports (`@kit.AbilityKit`, `@kit.ArkUI`, `@kit.CryptoArchitectureKit`).
- Group order: HarmonyOS SDK imports, then project imports. No blank line required between groups.
- Re-export public APIs through barrel files (`Index.ets`, `utils/index.ets`).

### Naming Conventions

| Element             | Convention         | Example                                    |
|---------------------|--------------------|--------------------------------------------|
| Classes             | PascalCase         | `APMCore`, `TokenService`, `ApmStarter`    |
| Interfaces          | PascalCase         | `APMConfig`, `RetryOptions`, `ReportPayload` |
| Functions           | camelCase          | `getToken()`, `scanAndUpload()`            |
| Variables/fields    | camelCase          | `tokenExpireAt`, `isScanning`              |
| Constants           | UPPER_SNAKE_CASE   | `DEFAULT_RETRY_INTERVAL`, `CLEANUP_DELAY_MS` |
| Namespaces          | PascalCase         | `Crypto`, `Compression`, `CacheValidation` |
| Files (classes)     | PascalCase.ets     | `APMCore.ets`, `TokenService.ets`          |
| Files (utilities)   | camelCase.ets      | `withRetry.ets`, `safeOperations.ets`      |
| Directories         | snake_case         | `core`, `config`, `cache`                  |
| TAG constants       | class name string  | `private readonly TAG = 'APMCore'`         |

### Types and Generics

- Always annotate function parameters and return types.
- Use `Partial<APMConfig>` for optional config overrides.
- Prefer `interface` over `type` for object shapes.
- Use generic type parameters on utility wrappers: `withRetry<T>`, `withLock<T>`.
- Use `??` (nullish coalescing) for defaults: `options.maxRetries ?? 3`.
- Avoid object destructuring — ArkTS does not support it. Access properties directly.

### String Style

- **Single quotes** for imports and general strings: `'APMCore'`.
- **Template literals** (backticks) for interpolation: `` `attempt ${attempt}/${max}` ``.
- **Double quotes** only in JSON-like payloads or header keys.

### Error Handling

- Wrap risky operations in `try/catch`. Catch as `Error` with `error as Error`.
- Log errors with `this.log.error('context message', error.message)`.
- Re-throw when the caller needs to handle: `throw error as Error`.
- Return empty/default values for non-critical failures (e.g., `md5()` returns `''` on error).
- Use `finally` blocks for cleanup (e.g., resetting `isScanning` flags).
- Error callbacks use the pattern: `(reason: Error) => void`.

### Logging

- Use the custom logger, NOT `hilog` directly (except in `entry/` demo code):
  ```
  private readonly TAG = 'ClassName';
  private readonly log = getLogger(this.TAG);
  ```
- Logger levels: `debug`, `info`, `warn`, `error`.
- For `static` contexts: `const log = getLogger(ClassName.TAG)`.
- Log structured data with `JSON.stringify({...})`.

### Comments and Documentation

- **Bilingual**: Chinese for implementation notes, English for JSDoc/API docs.
- Use JSDoc (`/** */`) for public APIs with `@param`, `@returns`, `@example`.
- Use inline `//` for implementation explanations.
- Mark internal/test APIs with `@internal`.

### Design Patterns

- **Singleton**: `private static instance`, `static getInstance()`, `static reset()` for testing.
- **Builder**: Fluent API returning `this`. E.g., `APMConfigBuilder`, `ZipBuilder`.
- **Functional wrappers** (`with*` pattern): `withRetry`, `withLock`, `withTimeout`,
  `withTiming`, `withResource`, `withTask` for cross-cutting concerns.
- **Namespace**: Use `namespace` to group static utility functions (`Crypto`, `Compression`).
- **No object spread**: Manually merge properties with dedicated `merge*` helper functions.

### HarmonyOS Decorators

- `@Concurrent` — on top-level functions for `taskpool` execution (worker threads).
- `@Entry` — marks the entry component of a page.
- `@Component` — marks an ArkUI component struct.
- `@State` — reactive state in UI components.

### Access Modifiers

- `private` for internal fields and methods.
- `private readonly` for TAG, log, and immutable fields.
- `private static` for singleton instances.
- `export` only for public API surface. Avoid exporting internals.
- Constructors of singletons are `private`.

### Async Patterns

- Prefer `async/await` over raw Promises.
- Use `void` prefix for fire-and-forget async calls: `void withLock(...)`.
- Chain methods return `this` for fluent APIs: `APMCore.init().startCacheServices().startNetConService()`.

## Security Notes

- Never hardcode encryption keys, passwords, or API tokens in source files.
- Use placeholder values (`<YOUR_AES_KEY>`, `<YOUR_APP_ID>`) in committed code.
- The `build-profile.json5` signing config uses placeholders — fill in locally, never commit real credentials.
- All `@security/no-unsafe-*` linter rules are enforced as errors.
