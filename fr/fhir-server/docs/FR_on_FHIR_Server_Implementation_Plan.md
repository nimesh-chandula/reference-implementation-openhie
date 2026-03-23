# Implementation Plan: Facility Registry on top of `fhir-server`

## Overview

The generic `fhir-server` provides CRUD, search (CSV-driven FHIRPath), history, references, and transaction rollback for all R4 resource types. The Facility Registry (FR) is built on top of it by:

1. Restricting the server to the 5 mCSD resources
2. Ensuring mCSD search parameters are in the CSV
3. Adding mCSD profile validation on write
4. Adding IHE transaction enable/disable flags (ITI-90 / ITI-91 / ITI-130)
5. Adding audit event emission

---

## Phase 1 — Fork & Rename the Package

**Goal:** Create a new Ballerina project based on `fhir-server`.

### Steps

1. Copy `fhir-server/` into the repo as `fr-service/` (or replace `fr-core/` entirely).
2. Update `Ballerina.toml`:

```toml
[package]
org = "wso2"
name = "facility_registry"
version = "1.0.0"
distribution = "2201.12.11"

[[platform.java21.dependency]]
artifactId = "h2"
version = "2.3.232"
groupId = "com.h2database"

[[platform.java21.dependency]]
artifactId = "postgresql"
version = "42.7.9"
groupId = "org.postgresql"
```

3. Update all `import ballerina_fhir_server.*` statements across every `.bal` file to `import wso2/facility_registry.*`.

---

## Phase 2 — Restrict to 5 mCSD Resources

**Goal:** Remove all non-FR resource types from `service.bal` and `modules/r4_api_config/`.

### 2a. `modules/r4_api_config/`

Delete every `*_api_config.bal` file **except**:
- `organization_api_config.bal`
- `location_api_config.bal`
- `healthcareservice_api_config.bal`
- `endpoint_api_config.bal`
- `organizationaffiliation_api_config.bal`

### 2b. `service.bal` — Resource type declarations

Remove all `public type X international401:X` declarations **except**:
```ballerina
public type Organization      international401:Organization;
public type Location          international401:Location;
public type HealthcareService international401:HealthcareService;
public type Endpoint          international401:Endpoint;
public type OrganizationAffiliation international401:OrganizationAffiliation;
```

### 2c. `service.bal` — Service blocks

Keep only the 5 `http:Service /fhir/r4/[ResourceType]` service blocks and their corresponding `fhirr4:Listener` registrations for the 5 FR resources.

Remove:
- IPS export service and `ExportJob` types
- `service http:Service /fhir/r4/$export` and bulk export logic
- `loadCustomProfiles()` and `StructureDefinition` auto-registration (optional — keep if mCSD SDs will be loaded at startup)

### 2d. Update `init()`

Remove Device auto-creation and IPS bootstrap. Simplify to:
```ballerina
function init() returns error? {
    boolean|error? dbStatus = dbHandler.initDatabase(jdbcClient);
    if dbStatus is boolean && dbStatus {
        log:printInfo("Facility Registry DB initialized");
    }
    log:printInfo("Facility Registry started", port = port);
}
```

---

## Phase 3 — mCSD Search Parameters in the CSV

**Goal:** Ensure `assets/r4-searchParam-Expression.csv` has the mCSD-relevant search params for all 5 resources.

The standard R4 CSV already covers base params. Verify the following are present (add if missing):

| Resource | Parameter | Type | FHIRPath Expression |
|---|---|---|---|
| Organization | name | string | Organization.name |
| Organization | identifier | token | Organization.identifier |
| Organization | type | token | Organization.type |
| Organization | partof | reference | Organization.partOf |
| Organization | active | token | Organization.active |
| Organization | endpoint | reference | Organization.endpoint |
| Location | name | string | Location.name |
| Location | identifier | token | Location.identifier |
| Location | type | token | Location.type |
| Location | status | token | Location.status |
| Location | organization | reference | Location.managingOrganization |
| Location | partof | reference | Location.partOf |
| Location | address | string | Location.address |
| HealthcareService | name | string | HealthcareService.name |
| HealthcareService | identifier | token | HealthcareService.identifier |
| HealthcareService | type | token | HealthcareService.type |
| HealthcareService | organization | reference | HealthcareService.providedBy |
| HealthcareService | location | reference | HealthcareService.location |
| HealthcareService | active | token | HealthcareService.active |
| Endpoint | identifier | token | Endpoint.identifier |
| Endpoint | status | token | Endpoint.status |
| Endpoint | organization | reference | Endpoint.managingOrganization |
| Endpoint | connection-type | token | Endpoint.connectionType |
| OrganizationAffiliation | identifier | token | OrganizationAffiliation.identifier |
| OrganizationAffiliation | active | token | OrganizationAffiliation.active |
| OrganizationAffiliation | organization | reference | OrganizationAffiliation.organization |
| OrganizationAffiliation | participating-organization | reference | OrganizationAffiliation.participatingOrganization |
| OrganizationAffiliation | role | token | OrganizationAffiliation.code |
| OrganizationAffiliation | location | reference | OrganizationAffiliation.location |
| OrganizationAffiliation | service | reference | OrganizationAffiliation.healthcareService |
| OrganizationAffiliation | endpoint | reference | OrganizationAffiliation.endpoint |

**How:** Open the CSV and grep for each resource name. Add missing rows at the end of the file — they are auto-loaded into `SEARCH_PARAM_RES_EXPRESSIONS` at startup by `DBHandler.populateSearchParamExpressionTable()`.

---

## Phase 4 — mCSD Profile Validation on Write

**Goal:** Reject writes that violate mCSD required field constraints before they reach the DB.

### 4a. Add a `modules/validation/` module

Create `modules/validation/validation.bal` with:

- `ValidationContext` record: `{ resourceType, payload, operation }`
- `ValidationResult` record: `{ boolean valid, string[] errors }`
- `ValidationRule` object type with `validate(ctx)` method
- `DefaultValidationPipeline` class that chains rules, stops on first failure

### 4b. Implement the two standard rules

**`FhirBaseValidator`** (reuse from `fr-core` directly):
- Payload must be a JSON object
- `resourceType` field present and matches expected type
- `id` present and valid format for update operations

**`McsdProfileValidator`**:
- Organization: `name` required
- Location: `name` and `status` (active|suspended|inactive) required
- Endpoint: `status`, `connectionType`, `address` required
- HealthcareService, OrganizationAffiliation: no hard required fields

### 4c. Wire into `performResourceCreate` and `performResourceUpdate` in `service.bal`

```ballerina
final ValidationPipeline validationPipeline = validation:buildDefaultPipeline();

isolated function performResourceCreate(string resourceType, json resourceJson)
        returns any|r4:OperationOutcome|r4:FHIRError {
    // Validate before writing
    ValidationResult result = validationPipeline.run({
        resourceType: resourceType,
        payload: resourceJson,
        operation: "create"
    });
    if !result.valid {
        return r4:createFHIRError(result.errors[0], r4:ERROR, r4:PROCESSING,
                httpStatusCode = 422);
    }
    // ... existing create logic
}
```

---

## Phase 5 — IHE Transaction Enable/Disable Flags

**Goal:** Allow deployers to enable/disable ITI-90, ITI-91, ITI-130 per deployment via config.

### 5a. Add to `Config.toml`

```toml
[transactions]
iti90Enabled  = true    # ITI-90  Find Matching Care Services (Search)
iti91Enabled  = true    # ITI-91  Request Care Services Updates (History)
iti130Enabled = true    # ITI-130 Maintain Care Services (CRUD)
```

### 5b. Add to `service.bal`

```ballerina
configurable boolean iti90Enabled  = true;
configurable boolean iti91Enabled  = true;
configurable boolean iti130Enabled = true;

isolated function checkTransactionEnabled(string transaction) returns r4:FHIRError? {
    boolean enabled = (transaction == "ITI-90" && iti90Enabled)
        || (transaction == "ITI-91" && iti91Enabled)
        || (transaction == "ITI-130" && iti130Enabled);
    if !enabled {
        return r4:createFHIRError(
            transaction + " is not enabled for this deployment",
            r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
    }
    return ();
}
```

### 5c. Gate each shared utility function

| Utility function | Transaction to check |
|---|---|
| `performResourceSearch` | ITI-90 |
| History service endpoints | ITI-91 |
| `performResourceCreate` | ITI-130 |
| `performResourceUpdate` | ITI-130 |
| `performResourceDelete` | ITI-130 |

---

## Phase 6 — Audit Event Emission

**Goal:** Emit a FHIR `AuditEvent` to a configurable audit service after every successful operation.

### 6a. Add config

```toml
auditServiceUrl = "http://localhost:9099/audits"
auditEnabled    = true
```

### 6b. Create `audit.bal` (port from `fr-core`)

```ballerina
configurable string auditServiceUrl = "http://localhost:9099/audits";
configurable boolean auditEnabled   = true;

final http:Client? auditClient = auditEnabled ? check new (auditServiceUrl) : ();

function sendAudit(string action, string resourceType, string resourceId, string outcome) {
    if !auditEnabled { return; }
    // Build AuditEvent JSON and POST async (separate strand)
    _ = start postAuditEvent(action, resourceType, resourceId, outcome);
}
```

The `postAuditEvent` function builds a FHIR `AuditEvent` (reuse directly from `fr-core/audit.bal`).

### 6c. Wire into shared utility functions

After each successful operation in `performResourceCreate/Update/Delete/Search`:
```ballerina
sendAudit("create", resourceType, newId, "0");
```

---

## Phase 7 — Configuration & Service Path

**Goal:** Match IHE mCSD base path and set FR-appropriate defaults.

### 7a. Update service base path

The current fhir-server uses `/fhir/r4`. The FR uses `/fhir`. Update the service path annotations and `fhirBaseUrl` config accordingly, or keep `/fhir/r4` — either is valid as long as it's consistent.

### 7b. `Config.toml` final shape

```toml
port            = 9098
fhirBaseUrl     = "http://localhost:9098/fhir/r4"
dbType          = "h2"
dbUrl           = "jdbc:h2:./db/FR_DB"
dbUser          = "sa"
dbPassword      = ""

auditServiceUrl = "http://localhost:9099/audits"
auditEnabled    = true

iti90Enabled    = true
iti91Enabled    = true
iti130Enabled   = true
```

---

## What is Deleted vs. What is Kept vs. What is Added

| Component | Action | Notes |
|---|---|---|
| `handlers/` (DBHandler, ReadHandler, UpdateHandler, DeleteHandler, HistoryHandler) | **Keep as-is** | No changes needed |
| `mappers/` (ReadMapper, UpdateMapper, FHIRMapper) | **Keep as-is** | No changes needed |
| `assets/r4-searchParam-Expression.csv` | **Extend** | Add missing mCSD params |
| `modules/r4_api_config/` (150+ files) | **Delete 145, keep 5** | Only FR resources |
| `service.bal` resource type declarations | **Delete 145, keep 5** | Only FR resources |
| `service.bal` IPS/Export logic | **Delete** | Not needed for FR |
| `modules/validation/` | **Add new** | Port from fr-core |
| `audit.bal` | **Add new** | Port from fr-core |
| `Config.toml` IHE transaction flags | **Add new** | ITI-90/91/130 |
| `service.bal` transaction gate checks | **Add new** | Thin wrappers |

---

## Work Order Summary

| Phase | Effort | Risk |
|---|---|---|
| 1 — Fork & rename | Low | Low — mechanical rename |
| 2 — Remove non-FR resources | Low | Low — pure deletion |
| 3 — mCSD CSV params | Low | Low — data change only |
| 4 — Validation module | Medium | Medium — port & wire in |
| 5 — ITI transaction flags | Low | Low — config + thin guards |
| 6 — Audit emission | Low | Low — direct port from fr-core |
| 7 — Config & path | Low | Low — config only |
