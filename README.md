# Facility Registry — OpenHIE Reference Implementation

FHIR R4 Facility Registry implementing the [IHE mCSD (Mobile Care Services Discovery)](https://profiles.ihe.net/ITI/mCSD/) standard. Built with [Ballerina](https://ballerina.io/) and designed for OpenHIE-compliant health information exchange.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Supported Resources & Transactions](#supported-resources--transactions)
- [API Reference](#api-reference)
- [Configuration](#configuration)
- [Database Setup](#database-setup)
- [Running the Service](#running-the-service)
- [Admin APIs](#admin-apis)
- [Bulk Import](#bulk-import)
- [Extending to a New IG](#extending-to-a-new-ig)
- [Testing](#testing)
- [Project Structure](#project-structure)

---

## Overview

| Property | Value |
|---|---|
| Language | Ballerina 2201.13.1 |
| FHIR Version | R4 (4.0.1) |
| Default IG | IHE mCSD v4.0.1 |
| Default DB | H2 (embedded); PostgreSQL for production |
| FHIR Service Port | 9098 |
| Admin API Port | 9099 |

---
Key design patterns used:

- **Profile Adapter Pattern** — `IGTypeAdapter` interface decouples the service from any specific IG Ballerina package. See [Extending to a New IG](#extending-to-a-new-ig) for the full set of files that need updating when switching IGs.
- **Validation Pipeline** — Chain-of-responsibility rules run before every create/update.
- **Transaction Handler** — Pluggable `TransactionHandler` interface for authentication, authorisation, and auditing per IHE transaction.
- **Observer/Event Bus** — Audit events are published internally and delivered to the external audit service asynchronously.

---

## Supported Resources & Transactions

### FHIR Resources

| Resource | Description |
|---|---|
| `Organization` | Healthcare organizations, facilities, jurisdictions |
| `Location` | Physical locations with coordinates |
| `HealthcareService` | Services provided by organizations |
| `Endpoint` | Technical connection endpoints (URLs, protocols) |
| `OrganizationAffiliation` | Relationships between organizations |

### IHE mCSD Transactions

| Transaction | Description | Operations |
|---|---|---|
| ITI-90 | Find Matching Care Services | Read, Search |
| ITI-91 | Request Care Services Updates | History |
| ITI-130 | Care Services Feed | Create, Update, Delete |

Each transaction can be individually enabled or disabled in `Config.toml`.

---

## API Reference

### Base URL

```
http://localhost:9098/fhir
```

### FHIR Metadata

| Method | Path | Description |
|---|---|---|
| GET | `/fhir/metadata` | CapabilityStatement (dynamically generated from tenant config) |

### Organization

| Method | Path | Transaction |
|---|---|---|
| GET | `/fhir/Organization` | ITI-90 Search |
| GET | `/fhir/Organization/{id}` | ITI-90 Read |
| GET | `/fhir/Organization/_history` | ITI-91 Type history |
| GET | `/fhir/Organization/{id}/_history` | ITI-91 Instance history |
| POST | `/fhir/Organization` | ITI-130 Create |
| PUT | `/fhir/Organization/{id}` | ITI-130 Update |
| DELETE | `/fhir/Organization/{id}` | ITI-130 Delete |

**Search Parameters**: `_id`, `active`, `identifier`, `name` (`:contains`, `:exact`), `type`, `partof`, `_lastUpdated`, `_include`, `_revInclude`

### Location

Same operations as Organization (ITI-90, ITI-91, ITI-130).

**Additional Search Parameters**: `status`, `organization`, `near` (geo distance), `partof`

### HealthcareService

Same operations as Organization (ITI-90, ITI-91, ITI-130).

**Search Parameters**: `active`, `identifier`, `location`, `name`, `organization`, `service-type`

### Endpoint

| Method | Path | Transaction |
|---|---|---|
| GET | `/fhir/Endpoint` | ITI-90 Search |
| GET | `/fhir/Endpoint/{id}` | ITI-90 Read |
| POST | `/fhir/Endpoint` | ITI-130 Create |

**Search Parameters**: `identifier`, `organization`, `status`

### OrganizationAffiliation

| Method | Path | Transaction |
|---|---|---|
| GET | `/fhir/OrganizationAffiliation` | ITI-90 Search |
| GET | `/fhir/OrganizationAffiliation/{id}` | ITI-90 Read |
| POST | `/fhir/OrganizationAffiliation` | ITI-130 Create |

**Search Parameters**: `active`, `identifier`, `participating-organization`, `primary-organization`, `role`

---

## Configuration

All runtime configuration lives in `Config.toml`.

### Service

```toml
port = 9098
adminPort = 9099
auditServiceUrl = "http://localhost:9096"
fhirBaseUrl = "http://localhost:9098/fhir"
```

### IG Adapter

```toml
# Selects the active IG adapter. Supported values: "mcsd"
# To add a new IG: implement IGTypeAdapter, then set this to its key.
igAdapterType = "mcsd"
```

### IG / Tenant Profile

```toml
[wso2.FRCoreService.fhir_utils.igConfig]
id = "mcsd"
name = "IHE mCSD v4.0.1"
canonical = "https://profiles.ihe.net/ITI/mCSD"
fhirVersion = "4.0.1"
serverName = "FRCoreMCSDCapabilityStatement"
serverVersion = "1.0.0"
publisher = "WSO2 / OpenHIE"
instantiates = ["https://profiles.ihe.net/ITI/mCSD/CapabilityStatement/IHE.mCSD.CareServicesSelectiveSupplier"]
```

### Transaction Enablement

```toml
[wso2.FRCoreService.fhir_utils.igConfig.transactions]
iti90 = true    # Find Matching Care Services (read/search)
iti91 = true    # Request Care Services Updates (history)
iti130 = true   # Care Services Feed (create/update/delete)
```

### Per-Resource Configuration

```toml
[[wso2.FRCoreService.fhir_utils.igConfig.resources]]
resourceType = "Organization"
profile = "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.Organization"
facilityProfile = "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.FacilityOrganization"
jurisdictionProfile = "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.JurisdictionOrganization"
interactions = ["read", "search-type", "create", "update", "delete"]
supportsHistory = true
```

Repeat the `[[...resources]]` block for each resource type.

---

## Database Setup

### H2 — Development (default)

```toml
[wso2.FRCoreService.db]
dbType = "h2"
dbUrl = "jdbc:h2:./db/FR_CORE_DB"
dbUser = "sa"
dbPassword = ""
dbPoolMaxSize = 20
dbPoolMinIdle = 5
```

No setup required. The schema is auto-created on first run.

### PostgreSQL — Production

```toml
[wso2.FRCoreService.db]
dbType = "postgresql"
dbUrl = "jdbc:postgresql://localhost:5432/facility_registry"
dbUser = "postgres"
dbPassword = "postgres"
dbPoolMaxSize = 20
dbPoolMinIdle = 5
```

Create the database before starting the service. The schema tables are auto-initialised on startup.

**Tables created**:

| Table | Description |
|---|---|
| `organization` | Organization resources with type, name, part_of hierarchy |
| `location` | Location resources with lat/lon, address, managing org |
| `healthcare_service` | Service resources linked to organizations |
| `endpoint` | Connection endpoint resources |
| `org_affiliation` | Organization relationship resources |
| `resource_history` | Version history for ITI-91 (action: CREATE/UPDATE/DELETE) |
| `identifier` | Cross-resource identifier index |
| `service_location` | HealthcareService ↔ Location join table |

---

## Running the Service

```bash
# Run with default Config.toml
bal run

# Run with an alternative config (e.g., Sri Lanka FR)
bal run -- --config-file Config-lk-fr.toml

# Build a deployable artifact
bal build

# Run tests
bal test
```

**Startup sequence**:
1. Load `Config.toml`
2. Register audit observer on the internal event bus
3. Resolve and initialise the `IGTypeAdapter` (mCSD by default)
4. Initialise the database and run schema migrations if needed
5. Start FHIR HTTP listener on `port` and Admin listener on `adminPort`

---

## Admin APIs

Base URL: `http://localhost:9099/api/admin`

| Method | Path | Description |
|---|---|---|
| GET | `/hierarchy` | Nested organizational hierarchy tree |
| GET | `/statistics` | Registry statistics (counts by resource type and status) |
| GET | `/facilities/map` | GeoJSON FeatureCollection for map visualisation |
| POST | `/facilities/{id}/status` | Update facility operational status |
| POST | `/bulk-import` | Import a FHIR Bundle (JSON body) |
| POST | `/bulk-import/csv` | Import from CSV (multipart form data) |
| GET | `/audit-logs` | Retrieve audit logs from the audit service |

### Statistics Response Shape

```json
{
  "totalOrganizations": 42,
  "totalLocations": 38,
  "totalHealthcareServices": 15,
  "totalEndpoints": 8,
  "activeOrganizations": 40,
  "activeLocations": 36,
  "facilitiesCount": 30,
  "jurisdictionsCount": 12
}
```

### Status Update Request

```json
{ "status": "inactive", "reason": "Facility closed" }
```

### Audit Log Query Parameters

`action`, `subtype`, `since`, `before` — proxied to the external audit service at `auditServiceUrl`.

---

## Bulk Import

### FHIR Bundle (`POST /api/admin/bulk-import`)

Accepts a FHIR `Bundle` resource. Entries are processed in dependency order:

1. Organizations
2. Locations
3. HealthcareServices and Endpoints
4. OrganizationAffiliations

The HTTP method per entry is determined by `entry.request.method`, or inferred from the presence of `resource.id` (PUT if present, POST if absent). The same validation pipeline used for individual creates/updates applies to each entry.

### CSV Import (`POST /api/admin/bulk-import/csv`)

Accepts a CSV file as multipart form data.

### Response

Both methods return a `BulkImportResult`:

```json
{
  "total": 50,
  "created": 45,
  "updated": 3,
  "failed": 2,
  "errors": ["Entry 12: Organization.name is required"]
}
```

---

## Extending to a New IG

The service uses the `IGTypeAdapter` interface to decouple FHIR resource handling from any specific IG Ballerina package. The example below uses Sri Lanka FR (`lk-fr`) as the target IG.

### Step-by-step

**1. Add the IG Ballerina package dependency**

In `fr-core/Ballerina.toml`, replace the `mcsd_package` dependency with your IG package:

```toml
[[dependency]]
org = "healthcare_samples"
name = "lk_package"
version = "1.0.0"
repository = "local"
```

`fr-core/Dependencies.toml` is auto-generated — it updates automatically when you run `bal build`.

**2. Create a new IG adapter**

Add `fr-core/modules/fhir_utils/lk_ig_adapter.bal` implementing `IGTypeAdapter`:

- `parseResource(resourceType, typeCode, payload)` — type-coerce payload into IG-typed records
- `validateRequiredFields(resourceType, payload)` — return field violation messages
- `getTypeCodeSystem()` — return the code system URL for type codings (e.g., `https://ig.hiu.lk/fhir/facilityregistry/CodeSystem/...`)
- `getPackageName()` — return a human-readable identifier for logging

**3. Register the adapter**

In `fr-core/modules/fhir_utils/tenant_config.bal`, add a branch in `resolveIgTypeAdapter()`:

```ballerina
function resolveIgTypeAdapter() returns IGTypeAdapter {
    if igAdapterType == "mcsd" {
        return new McsdIGTypeAdapter();
    }
    if igAdapterType == "lk-fr" {
        return new LkFrIGTypeAdapter();   // <-- add this
    }
    return new McsdIGTypeAdapter();
}
```

**4. Update the r4_api_config profile URLs**

Each file under `fr-core/modules/r4_api_config/` hardcodes the mCSD profile URLs that are used for CapabilityStatement generation and profile validation. Replace all `profiles` arrays with the new IG's profile URLs:

| File | Profiles to replace |
|---|---|
| `organization_api_config.bal` | `IHE.mCSD.Organization`, `IHE.mCSD.FacilityOrganization`, `IHE.mCSD.JurisdictionOrganization` |
| `location_api_config.bal` | `IHE.mCSD.Location`, `IHE.mCSD.FacilityLocation`, `IHE.mCSD.JurisdictionLocation` |
| `healthcareservice_api_config.bal` | `IHE.mCSD.HealthcareService` |
| `endpoint_api_config.bal` | `IHE.mCSD.Endpoint` |
| `organizationaffiliation_api_config.bal` | `IHE.mCSD.OrganizationAffiliation` |

If the new IG does not include a resource type (e.g., LK-FR has no `Endpoint` or `OrganizationAffiliation`), leave its `profiles` array empty — the validation pipeline will treat the resource as unsupported.

**5. Update Config.toml (or create a new config file)**

```toml
# Switch adapter
igAdapterType = "lk-fr"

[wso2.FRCoreService.fhir_utils.igConfig]
id         = "lk-fr"
name       = "Sri Lanka HIU Facility Registry v0.1.0"
canonical  = "https://ig.hiu.lk/fhir/facilityregistry"
fhirVersion = "4.0.1"
serverName  = "LKFacilityRegistryCapabilityStatement"
serverVersion = "1.0.0"
publisher   = "HIU Sri Lanka"
instantiates = ["https://ig.hiu.lk/fhir/facilityregistry/CapabilityStatement/..."]

[wso2.FRCoreService.fhir_utils.igConfig.transactions]
iti90  = true
iti91  = true
iti130 = true

[[wso2.FRCoreService.fhir_utils.igConfig.resources]]
resourceType = "Organization"
profile = "https://ig.hiu.lk/fhir/facilityregistry/StructureDefinition/LKOrganization"
interactions = ["read", "search-type", "create", "update", "delete"]
supportsHistory = true

# Repeat for Location, HealthcareService (omit Endpoint / OrganizationAffiliation if not in IG)
```

A ready-made example for LK-FR is in `fr-core/Config-lk-fr.toml`. To run with it:

```bash
bal run -- --config-file Config-lk-fr.toml
```

**6. (Optional) Update profile_adapter.bal**

`fr-core/modules/fhir_utils/profile_adapter.bal` contains a list of known IG prefixes used to reverse-map profile URLs back to resource types. If your IG uses a distinct profile URL prefix, add it to the list:

```ballerina
// existing
string[] igPrefixes = ["IHE.mCSD.", "LK", "BD"];
// add your prefix, e.g. "TZ" for Tanzania
```

### Complete file change checklist

| File | Change required |
|---|---|
| `fr-core/Ballerina.toml` | Replace IG package dependency |
| `fr-core/modules/fhir_utils/lk_ig_adapter.bal` | **Create** — implement `IGTypeAdapter` |
| `fr-core/modules/fhir_utils/tenant_config.bal` | Add branch in `resolveIgTypeAdapter()` |
| `fr-core/modules/r4_api_config/organization_api_config.bal` | Replace profile URLs |
| `fr-core/modules/r4_api_config/location_api_config.bal` | Replace profile URLs |
| `fr-core/modules/r4_api_config/healthcareservice_api_config.bal` | Replace profile URL |
| `fr-core/modules/r4_api_config/endpoint_api_config.bal` | Replace or clear profile URL |
| `fr-core/modules/r4_api_config/organizationaffiliation_api_config.bal` | Replace or clear profile URL |
| `fr-core/Config.toml` (or new `Config-<ig>.toml`) | Update `igAdapterType` and entire `igConfig` section |
| `fr-core/modules/fhir_utils/profile_adapter.bal` | Add new IG prefix (if needed) |
| `fr-core/Dependencies.toml` | Auto-generated — no manual edit needed |

---

## Testing

Tests are located under `fr-core/tests/` and `fr-core/modules/*/tests/`.

```bash
bal test
```

**Coverage includes**:
- CRUD operations per resource type (create → 201, read → 200, update, delete → 204)
- Search operations (returns FHIR `Bundle` with `searchset` type)
- CapabilityStatement metadata (resource types, supported transactions)
- History bundles (ITI-91)
- Validation pipeline (valid and invalid payloads)
- Search parameter parsing and filtering
- Admin APIs (hierarchy, statistics, status update)
- Transaction handler base classes

---

## Project Structure

```
fr-core/
├── service.bal              # Main FHIR HTTP service (all resource endpoints)
├── admin.bal                # Admin API handlers
├── bulk_import.bal          # Bundle and CSV bulk import
├── capability.bal           # CapabilityStatement builder
├── history.bal              # ITI-91 history handling
├── audit.bal                # Audit event dispatch
├── event_bus.bal            # Internal observer/event bus
├── Config.toml              # Runtime configuration
├── Ballerina.toml           # Package metadata
└── modules/
    ├── organization/        # Organization CRUD + search
    ├── location/            # Location CRUD + geo search
    ├── healthcare_service/  # HealthcareService CRUD + search
    ├── endpoint/            # Endpoint CRUD + search
    ├── org_affiliation/     # OrganizationAffiliation CRUD + search
    ├── db/                  # Database abstraction (H2 / PostgreSQL)
    ├── fhir_utils/          # FHIR utilities, tenant config, IG adapter interface
    ├── validation/          # Validation pipeline (chain of responsibility)
    ├── search_registry/     # Search parameter metadata registry
    ├── r4_api_config/       # Per-resource API configuration
    ├── repository/          # Generic FHIR repository interface
    ├── history/             # History tracking queries
    ├── admin/               # Admin statistics and hierarchy queries
    ├── transaction/         # IHE transaction handler base classes
    └── types/               # Shared record type definitions
```
