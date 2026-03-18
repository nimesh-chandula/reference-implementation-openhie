# Migration Plan: fr-core → Reusable Design Patterns

## Context

The fr-core codebase is being refactored from a monolithic Ballerina service into a composable, IG-agnostic platform following the mCSD Reusable Design Patterns spec. A partial migration is already in progress (modules/ directory exists, old handler files deleted). This plan completes the structural migration — patterns and interfaces first, business logic preserved as-is — so each phase results in a compilable, testable service.

**Priority:** Structure and pattern interfaces before business logic migration.

---

## Current State

- **Root-level files** (service entry points): `service.bal`, `admin.bal`, `audit.bal`, `bulk_import.bal`, `capability.bal`, `event_bus.bal`, `fhir_repository.bal`, `history.bal`, `search.bal`
- **New modules (partial)**: `modules/admin/`, `modules/db/`, `modules/organization/`, `modules/location/`, `modules/healthcare_service/`, `modules/endpoint/`, `modules/org_affiliation/`, `modules/history/`, `modules/fhir_utils/`, `modules/types/`, `modules/r4_api_config/`
- **Deleted**: All old `*_handler.bal`, `database_provider*.bal`, `records.bal` (root-level)

---

## Step 1 — Baseline Validation

**Goal:** Confirm the current in-progress state compiles cleanly.

### Actions
1. Run `bal build` in `fr-core/` and document all errors
2. Run `bal test` for any existing tests
3. Fix any import path errors caused by deleted files that are still referenced in root-level `.bal` files
4. Ensure `service.bal` compiles with all module imports resolved

### Ballerina Notes
- Ballerina module imports use `import wso2/FRCoreService.moduleName` pattern — verify all module names in `Ballerina.toml`
- Deleted files that are still referenced will cause `undefined symbol` errors in `service.bal`
- Module names must match directory names exactly (snake_case)

### Validation
- `bal build` exits with code 0
- `bal run` starts the service without panics
- `GET /fhir/metadata` returns 200

---

## Step 2 — Canonicalize Module Structure

**Goal:** Ensure every logical concern lives in exactly one module directory with correct Ballerina module naming.

### Actions
1. Verify module names in `Ballerina.toml` `[[package.modules]]` or use auto-discovery (`modules/` subdirs)
2. Confirm `modules/db/` exports: `DatabaseProvider`, `DatabaseProviderFactory`, `getDbClient`, `initDatabase`
3. Confirm `modules/types/` exports all shared record types (`OrgSearchParams`, `HistoryRow`, etc.)
4. Confirm `modules/fhir_utils/` exports: `buildSearchBundle`, `stampMeta`, `ProfileAdapter`, `IGConfig`
5. Confirm `modules/r4_api_config/` exports one `ResourceAPIConfig` per resource
6. Add `modules/validation/` directory with a placeholder `validation.bal` (empty module, no logic yet)
7. Add `modules/search_registry/` directory with a placeholder `search_registry.bal`
8. Add `modules/transaction/` directory with a placeholder `transaction.bal`

### Ballerina Notes
- Each `modules/<name>/` directory is a separate Ballerina sub-module: `wso2/FRCoreService.<name>`
- Module-level `public` declarations are the API surface — keep internal helpers `private` or package-private
- Placeholder files need at least one valid Ballerina construct to compile (e.g., a `public const string VERSION = "1.0.0";`)

### Validation
- `bal build` still passes
- `bal doc` generates documentation showing all modules listed
- Each placeholder module appears in the build output

---

## Step 3 — Repository Pattern (FhirRepository Interface)

**Goal:** Move `FhirRepository` interface into a dedicated module and implement `DatabaseFhirRepository` by delegating to the already-complete `modules/db/` layer (H2 for dev, PostgreSQL for prod — configured via Config.toml).

### Actions
1. Create `modules/repository/` directory
2. Move the `FhirRepository` object type from root `fhir_repository.bal` into `modules/repository/fhir_repository.bal`
3. Add `DatabaseFhirRepository` isolated class — implements all `FhirRepository` methods by calling existing functions from `modules/db/` (`getDbClient()`, `recordHistory()`, etc.)
4. Export factory function `getFhirRepository() returns FhirRepository`
5. Delete root `fhir_repository.bal` and update imports in `service.bal` to use `wso2/FRCoreService.repository`

### Ballerina Notes
- `modules/db/` is already complete — do NOT add new DB code there
- `type FhirRepository object {...}` — method signatures only (interface)
- `isolated class DatabaseFhirRepository { *FhirRepository; ... }` — object inclusion pattern
- All SQL goes through `db:getDbClient()` (already handles H2/PostgreSQL transparently)
- History recording uses existing `db:recordHistory()` — call it from write operations
- DB backend selection (H2 vs PostgreSQL) is already handled by `DatabaseProviderFactory` in `modules/db/`

### Validation
- Write `modules/repository/tests/repository_test.bal`
- Tests run against H2 (configured in test `Config.toml`)
- Test: create a resource via `DatabaseFhirRepository.createResource()`, then `readResource()` — assert id matches
- Test: `deleteResource()` then `readResource()` — assert soft-delete (resource not found or marked deleted)
- Run `bal test modules/repository`

---

## Step 4 — Search Parameter Registry

**Goal:** Replace hardcoded search params in `capability.bal` with a runtime registry.

### Actions
1. In `modules/search_registry/search_registry.bal`, define:
   ```ballerina
   public type SearchParamDef record {|
       string name;
       string paramType; // "token" | "string" | "reference" | "date" | "special"
       string expression;
       string[] supportedIGs; // empty = all IGs
   |};
   public type SearchParamRegistry record {|
       map<SearchParamDef[]> byResourceType;
   |};
   ```
2. Add `registerSearchParam(string resourceType, SearchParamDef param)` function
3. Add `getSearchParams(string resourceType) returns SearchParamDef[]` function
4. Add `buildDefaultRegistry() returns SearchParamRegistry` — populates from current hardcoded list in `capability.bal`
5. Initialize registry at module init (`init()` function in Ballerina)
6. Update `capability.bal`'s `getSearchParamsForResource()` to delegate to the registry instead of hardcoding

### Ballerina Notes
- Module-level `init()` function runs at program startup — use it to populate the registry
- Use `isolated` functions and a module-level `isolated SearchParamRegistry registry` variable (Ballerina isolated state)
- `lock` block required when mutating module-level state across strands

### Validation
- Write `modules/search_registry/tests/search_registry_test.bal`
- Test: `getSearchParams("Organization")` returns at least 5 params
- Test: `buildDefaultRegistry()` contains all 5 resource types
- Run `bal test modules/search_registry`
- Integration: `GET /fhir/metadata` still returns search params section correctly

---

## Step 5 — Pluggable Validation Pipeline

**Goal:** Define validation interface and chain — no business logic yet, just the structural pattern.

### Actions
1. In `modules/validation/validation.bal`, define:
   ```ballerina
   public type ValidationContext record {|
       string resourceType;
       json resource;
       string tenantId;
       string operation; // "create" | "update"
   |};
   public type ValidationResult record {|
       boolean valid;
       string[] errors;
   |};
   public type ValidationRule object {
       public function validate(ValidationContext ctx) returns ValidationResult;
       public function getName() returns string;
   };
   public type ValidationPipeline object {
       public function addRule(ValidationRule rule) returns ValidationPipeline;
       public function run(ValidationContext ctx) returns ValidationResult;
   };
   ```
2. Implement `DefaultValidationPipeline` class — iterates rules, accumulates errors, returns first failure
3. Implement stub rules: `FhirBaseValidator` (always passes — placeholder), `ProfileValidator` (always passes — placeholder)
4. Export `buildDefaultPipeline() returns ValidationPipeline`
5. Wire into `service.bal` POST handler for Organization (create) as proof-of-concept — call pipeline before DB insert; return 422 if invalid

### Ballerina Notes
- Object types as interfaces: method signatures without implementation
- `class DefaultValidationPipeline { *ValidationPipeline; ValidationRule[] rules = []; ... }`
- Return `http:Response` with status 422 and OperationOutcome body on validation failure — use existing `buildOperationOutcome()` from `fhir_utils`
- Keep stub validators as `isolated class` to avoid concurrency issues

### Validation
- Write `modules/validation/tests/validation_test.bal`
- Test: pipeline with no rules passes any input
- Test: pipeline with a rule that always fails returns `valid = false`
- Test: pipeline runs rules in order, stops on first failure
- Integration: POST invalid JSON to `/fhir/Organization` returns 422 (once wired)
- Run `bal test modules/validation`

---

## Step 6 — Transaction Orchestrator (Template Method Pattern)

**Goal:** Define abstract transaction handler shape for ITI-90, ITI-91, ITI-130.

### Actions
1. In `modules/transaction/transaction.bal`, define:
   ```ballerina
   public type TransactionContext record {|
       string transactionType; // "ITI-90" | "ITI-91" | "ITI-130"
       string resourceType;
       string tenantId;
       http:Request request;
   |};
   public type TransactionHandler object {
       public function authenticate(TransactionContext ctx) returns error?;
       public function authorize(TransactionContext ctx) returns error?;
       public function execute(TransactionContext ctx) returns http:Response|error;
       public function audit(TransactionContext ctx, http:Response resp) returns error?;
   };
   ```
2. Implement `BaseTransactionHandler` class with default `authenticate` (pass-through) and `audit` (delegates to event bus)
3. Create stub classes: `ITI90SearchHandler`, `ITI91HistoryHandler`, `ITI130FeedHandler` — each extends base, `execute` delegates to existing module functions
4. Export `getHandler(string txType, string resourceType) returns TransactionHandler|error`
5. **Do not** replace `service.bal` routing yet — just ensure the handlers compile and delegate correctly

### Ballerina Notes
- Ballerina doesn't have inheritance; use object inclusion (`*BaseTransactionHandler`) for shared behavior
- Default method bodies can be provided in abstract-like classes via object inclusion
- `service.bal` can optionally call `handler.execute(ctx)` as optional wiring — keep old code path as fallback with `// TODO: migrate` comments

### Validation
- Write `modules/transaction/tests/transaction_test.bal`
- Test: `getHandler("ITI-90", "Organization")` returns non-null handler
- Test: `ITI90SearchHandler.execute(ctx)` calls through to search module without error (mock HTTP request)
- Run `bal test modules/transaction`

---

## Step 7 — Tenant Context Hardening

**Goal:** Ensure `tenant_config.bal` + `profile_adapter.bal` in `modules/fhir_utils/` are the single source of truth; root-level `service.bal` reads only from these.

### Actions
1. Audit all places in root `.bal` files where profile URLs, resource types, or config values are hardcoded
2. Replace each with calls to `getIgConfig()`, `getResourceConfig(resourceType)`, `getProfileUrl(resourceType, typeCode)` from `modules/fhir_utils`
3. Ensure `profileAdapter` singleton in `modules/fhir_utils/profile_adapter.bal` is used consistently for all profile URL lookups
4. Add a `getTenantId() returns string` function to tenant_config (returns configurable `igConfig.id`)
5. Add a `isTransactionEnabled(string txType) returns boolean` function that checks `igConfig.transactions`
6. Wire `isTransactionEnabled` into `service.bal` handlers — if a transaction type is disabled, return 501 Not Implemented

### Ballerina Notes
- Configurable variables (`configurable IGConfig igConfig = {...}`) are set from `Config.toml` — these are safe as module-level singletons
- `isolated` functions that read module-level configurables don't need `lock` (configurables are immutable after init)
- Test with multiple `Config.toml` variations using Ballerina test `Config.toml` override mechanism

### Validation
- Write `modules/fhir_utils/tests/tenant_config_test.bal`
- Test: `getIgConfig().id` returns the configured tenant ID
- Test: `isTransactionEnabled("ITI-130")` returns `true` (default config)
- Test: override config with `iti130 = false` — `isTransactionEnabled("ITI-130")` returns `false`
- Integration: disable a transaction in `Config.toml` → endpoint returns 501
- Run `bal test modules/fhir_utils`

---

## Step 8 — CapabilityStatement Builder Wiring

**Goal:** `capability.bal` fully driven by Search Parameter Registry + Tenant Config — no hardcoded values.

### Actions
1. Replace `getSearchParamsForResource()` body in `capability.bal` with `searchRegistry:getSearchParams(resourceType)` call
2. Replace hardcoded resource list with `igConfig.resources` (from `getIgConfig()`)
3. Replace hardcoded transaction flags with `igConfig.transactions` values
4. Replace hardcoded profile URIs with `profileAdapter.getProfileUrl()` calls
5. Remove any remaining string literals that duplicate configuration

### Ballerina Notes
- Import `wso2/FRCoreService.search_registry as searchRegistry` etc. — verify module alias doesn't conflict
- `buildCapabilityStatement()` should be a pure function (no I/O) — takes `IGConfig` as parameter rather than reading module state directly (easier to test)

### Validation
- Test: modify `Config.toml` to disable one resource → that resource absent from CapabilityStatement
- Test: add a search param to the registry → appears in CapabilityStatement
- Integration: `GET /fhir/metadata` response passes FHIR validator (use `bal test` with FHIR assertion helpers)
- Run full `bal build && bal test`

---

## Step 9 — Event Bus + Audit Observer Hardening

**Goal:** Ensure event_bus.bal and audit.bal are correctly wired; publish events from all resource operations.

### Actions
1. Audit all `createX`, `updateX`, `deleteX` functions in resource modules — ensure each calls `publishEvent()` from `event_bus`
2. Verify audit observer is registered at service init (already in `service.bal` `init()`)
3. Add `SEARCHED` event publishing to all search functions
4. Add `READ` event publishing to all `getX` functions
5. Test isolation: ensure `publishEvent()` never blocks the caller (already uses separate strands — verify)

### Ballerina Notes
- `start observer(event)` in Ballerina spawns a new strand (non-blocking) — verify this pattern is used in `event_bus.bal`
- `isolated function` can't capture non-isolated variables — if observer functions access module state, they must be `isolated`
- Use `@strand { thread: "any" }` annotation if thread affinity matters for audit writes

### Validation
- Write integration test: create an Organization → check audit service received an AuditEvent (mock audit service or check event bus callback)
- Test: observer failure doesn't bubble up to the request handler (fault isolation)
- Run `bal test` with audit observer mock

---

## Step 10 — Final Integration & Smoke Test

**Goal:** All patterns wired; service runs end-to-end with all modules cooperating.

### Actions
1. Run full `bal build` — zero errors, zero warnings
2. Run `bal test` across all modules
3. Start service: `bal run` with default `Config.toml`
4. Run smoke test sequence via curl or Postman:
   - `GET /fhir/metadata` → 200, valid CapabilityStatement
   - `POST /fhir/Organization` (valid body) → 201, resource with id + meta
   - `GET /fhir/Organization/{id}` → 200, same resource
   - `GET /fhir/Organization?name=test` → 200, Bundle with entry
   - `GET /fhir/Organization/_history` → 200, history Bundle
   - `DELETE /fhir/Organization/{id}` → 204 or 200
   - `GET /api/admin/statistics` → 200, counts JSON
5. Document any remaining TODOs for business logic phase

### Validation
- All 7 smoke test calls return expected status codes
- No panics or unhandled errors in logs
- `bal test` reports 0 failures across all modules

---

## Module Dependency Map (after migration)

```
service.bal
  ├─ modules/transaction      ← orchestrates ITI-90/91/130 flow
  │     └─ modules/validation ← called per write operation
  ├─ modules/organization     ← resource CRUD (uses db + fhir_utils)
  ├─ modules/location         ←
  ├─ modules/healthcare_service ←
  ├─ modules/endpoint         ←
  ├─ modules/org_affiliation  ←
  ├─ modules/history          ←
  ├─ modules/admin            ←
  ├─ modules/db               ← database layer (DatabaseProvider strategy)
  ├─ modules/repository       ← FhirRepository interface + impls
  ├─ modules/fhir_utils       ← ProfileAdapter, TenantConfig, bundle builders
  ├─ modules/search_registry  ← SearchParam registry
  ├─ modules/types            ← shared records
  ├─ modules/r4_api_config    ← fhirr4 ResourceAPIConfig
  ├─ event_bus.bal            ← (root, shared observer pattern)
  ├─ audit.bal                ← observer implementation
  └─ capability.bal           ← builder (reads from search_registry + fhir_utils)
```

## Critical Files

| File | Role |
|------|------|
| `fr-core/service.bal` | Main service, entry point, init wiring |
| `fr-core/capability.bal` | CapabilityStatement builder |
| `fr-core/event_bus.bal` | Observer pattern hub |
| `fr-core/fhir_repository.bal` | Interface (to be moved to modules/repository/) |
| `fr-core/modules/fhir_utils/tenant_config.bal` | IGConfig, tenant accessor functions |
| `fr-core/modules/fhir_utils/profile_adapter.bal` | Profile URI abstraction |
| `fr-core/modules/types/records.bal` | Shared type definitions |
| `fr-core/modules/db/db_handler.bal` | Core DB access |
| `fr-core/Ballerina.toml` | Package manifest — module registration |
| `fr-core/Config.toml` | Runtime configuration |
