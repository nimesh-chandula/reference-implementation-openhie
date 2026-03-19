# Facility Registry — OpenHIE Reference Implementation

A production-grade FHIR R4 Facility Registry implementing the [IHE mCSD (Mobile Care Services Discovery)](https://profiles.ihe.net/ITI/mCSD/) standard. Built with [Ballerina](https://ballerina.io/) and designed for OpenHIE-compliant health information exchange.

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

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     service.bal                         │
│         FHIR HTTP endpoints (port 9098)                 │
├──────────────┬──────────────────────────────────────────┤
│  Validation  │  IGTypeAdapter (plug-in IG profiles)     │
│  Pipeline    │  McsdIGTypeAdapter  ←  igAdapterType     │
├──────────────┴──────────────────────────────────────────┤
│  Resource Modules                                       │
│  organization │ location │ healthcare_service           │
│  endpoint     │ org_affiliation                         │
├─────────────────────────────────────────────────────────┤
│  db module  (H2 / PostgreSQL via JDBC)                  │
├─────────────────────────────────────────────────────────┤
│  admin.bal (port 9099) │ bulk_import.bal │ audit.bal    │
└─────────────────────────────────────────────────────────┘
```

Key design patterns used:

- **Profile Adapter Pattern** — `IGTypeAdapter` interface decouples the service from any specific IG Ballerina package. Swap IGs by changing one config value.
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

The service is decoupled from any specific IG Ballerina package via the `IGTypeAdapter` interface. To support a new Implementation Guide:

1. Generate (or write) a Ballerina package for the target IG.
2. Create a new adapter file (e.g., `lk_ig_adapter.bal`) implementing `IGTypeAdapter`:
   - `parseResource(resourceType, typeCode, payload)` — type-coerce payload into IG-typed records
   - `validateRequiredFields(resourceType, payload)` — return field violation messages
   - `getTypeCodeSystem()` — return the code system URL for type codings
   - `getPackageName()` — return a human-readable identifier for logging
3. Register the new adapter in `tenant_config.bal` `resolveIgTypeAdapter()`.
4. Set `igAdapterType = "your-key"` in `Config.toml`.
5. Update the `[wso2.FRCoreService.fhir_utils.igConfig]` section with the new IG's profile URLs.

No other files need to change.

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
