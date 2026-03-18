# OpenHIE Facility Registry — Reusable Design Patterns & Implementation Plan

> **Designed for reuse:** This architecture implements the **OpenHIE Facility Registry (FR)** component using IHE mCSD as the FHIR transaction standard. It is built as a jurisdiction-agnostic platform that can be configured to serve any national IG. Two reference configurations are provided: IHE mCSD v4.0.1 (international baseline) and the Sri Lanka HIU Facility Registry IG v0.1.0.
>
> **Specification Sources:**
> - OpenHIE Architecture Specification: https://guides.ohie.org/arch-spec/
> - OpenHIE FR Component Spec: https://guides.ohie.org/arch-spec/openhie-component-specifications-1/openhie-facility-registry-fr
> - OpenHIE Care Services Discovery Workflows: https://guides.ohie.org/arch-spec/introduction/care-services-discovery
> - IHE mCSD v4.0.1: https://build.fhir.org/ig/IHE/ITI.mCSD/
> - Sri Lanka FR IG v0.1.0: https://ig.hiu.lk/fhir/facilityregistry/

---

## Table of Contents

1. [OpenHIE Architecture Context](#1-openhie-architecture-context)
2. [Problem Statement & Design Goals](#2-problem-statement--design-goals)
3. [Architecture Overview](#3-architecture-overview)
4. [Design Patterns](#4-design-patterns)
   - 4.1 [Profile Adapter Pattern](#41-profile-adapter-pattern)
   - 4.2 [Pluggable Validation Pipeline](#42-pluggable-validation-pipeline)
   - 4.3 [Repository Abstraction (Strategy Pattern)](#43-repository-abstraction-strategy-pattern)
   - 4.4 [Search Parameter Registry (Registry Pattern)](#44-search-parameter-registry-registry-pattern)
   - 4.5 [Transaction Orchestrator (Template Method)](#45-transaction-orchestrator-template-method)
   - 4.6 [Terminology Binding SPI](#46-terminology-binding-spi)
   - 4.7 [Tenant Context & Multi-IG Support](#47-tenant-context--multi-ig-support)
   - 4.8 [Event-Driven Sync (Observer Pattern)](#48-event-driven-sync-observer-pattern)
   - 4.9 [Facade Pattern for Cross-Registry Orchestration](#49-facade-pattern-for-cross-registry-orchestration)
   - 4.10 [CapabilityStatement Generator (Builder Pattern)](#410-capabilitystatement-generator-builder-pattern)
   - 4.11 [Interoperability Layer Gateway (Mediator Pattern)](#411-interoperability-layer-gateway-mediator-pattern)
5. [Gap Analysis: IHE mCSD vs. Sri Lanka HIU FR IG](#5-gap-analysis-ihe-mcsd-vs-sri-lanka-hiu-fr-ig)
6. [Module Architecture](#6-module-architecture)
7. [Data Model Design](#7-data-model-design)
8. [Implementation Phases](#8-implementation-phases)
9. [Configuration Reference](#9-configuration-reference)
10. [Deployment Topologies](#10-deployment-topologies)
11. [Testing Strategy](#11-testing-strategy)
12. [OpenHIE Functional Requirements Traceability](#12-openhie-functional-requirements-traceability)

---

## 1. OpenHIE Architecture Context

### 1.1 Where the Facility Registry Sits in OpenHIE

The OpenHIE architecture defines a set of interoperable components connected through an Interoperability Layer (IOL). The Facility Registry (FR) is one of several registries that together form the backbone of a national Health Information Exchange:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         OpenHIE Architecture                                  │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │              Point-of-Service Systems (PoS)                             │ │
│  │   EMR / EHR / mHealth / DHIS2 / LMIS / Labs / Community Apps           │ │
│  └────────────────────────────┬────────────────────────────────────────────┘ │
│                               │                                              │
│  ┌────────────────────────────▼────────────────────────────────────────────┐ │
│  │           Interoperability Layer (IOL)                                   │ │
│  │   • Single entry point into the HIE                                     │ │
│  │   • Authentication, Authorization, Encryption (IHE ATNA)                │ │
│  │   • Transaction routing, orchestration, logging                         │ │
│  │   • Error management, rerun failed transactions                         │ │
│  │   • Message transformation (adapters)                                   │ │
│  │   Reference impl: OpenHIM                                               │ │
│  └──┬──────┬──────┬──────┬──────┬──────┬──────┬──────┬────────────────────┘ │
│     │      │      │      │      │      │      │      │                       │
│  ┌──▼──┐┌──▼──┐┌──▼──┐┌──▼──┐┌──▼──┐┌──▼──┐┌──▼──┐┌──▼──┐                 │
│  │ CR  ││ FR  ││ HWR ││ SHR ││ TS  ││HMIS ││LMIS ││ FIS │                 │
│  │     ││*THIS*││     ││     ││     ││     ││     ││     │                 │
│  └─────┘└─────┘└─────┘└─────┘└─────┘└─────┘└─────┘└─────┘                 │
│  Client  Facility Health  Shared  Termi-  Health  Logis-  Finance           │
│  Registry Registry Worker  Health  nology  Mgmt   tics   & Insurance       │
│                  Registry Record  Service  Info   Mgmt                      │
│                                            System  Info                     │
│                                                    System                   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │      InterLinked Registry (ILR) / InfoManager                           │ │
│  │   • mCSD Update Client (polls FR + HWR via ITI-91)                      │ │
│  │   • mCSD Directory (serves merged data via ITI-90)                      │ │
│  │   • Merges facilities + health workers per jurisdictional policy        │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 OpenHIE FR Component Specification

The OpenHIE Architecture Specification defines the FR as the **central authority to collect, store, and distribute an up-to-date and standardized facility dataset** — the Master Facility List (MFL). The spec distinguishes between the FR (the technology) and the MFL (the standardized data it manages).

**Required workflow (FRWF-1):** The FR must support the "Query Health Worker and/or Facility Records" workflow, which maps directly to IHE mCSD ITI-90 (Find Matching Care Services) and ITI-91 (Request Care Services Updates).

**Key functional requirements from OpenHIE FR spec:**

| Req ID | Requirement | Conformance | How We Address It |
|--------|-------------|-------------|-------------------|
| FRF-1 | Create, define, and evolve attributes & data dictionary | Required | Profile Adapter pattern — IG packages define the data dictionary; new attributes added via StructureDefinitions |
| FRF-2 | Create, define, maintain multi-organizational hierarchies + geo-objects | Required | `Organization.partOf`, `Location.partOf` hierarchies; jurisdiction Location with `location-boundary-geojson` |
| FRF-3 | WHO/USAID minimum facility attributes (name, type, ownership, address, contact, status, admin level, geocoordinates, unique ID, services, HR, hours, identifiers, infrastructure) | Recommended | mCSD resource model covers all: Organization (ownership, type), Location (address, geocoordinates, status), HealthcareService (services, hours), Practitioner/PractitionerRole (HR by cadre) |
| FRF-4 | User management, permissions for read/write/admin | Required | IOL Gateway (ATNA/IUA) + RBAC authorization module |
| FRF-5 | Role-based access (Master Admin, Data Curator, Health Officer) | Recommended | Configurable RBAC in auth module |
| FRF-6 | Flexible standards-based APIs, preferably RESTful | Recommended | FHIR R4 RESTful API — mCSD ITI-90/91/130 |
| FRF-7 | Push/pull data to other systems (CSV) | Recommended | ITI-130 (push), ITI-91 (pull); CSV export via bulk data or custom operation |
| FRF-8 | Bulk imports | Required | ITI-130 transaction Bundle (atomic batch); custom `$import` operation for CSV/Excel |
| FRF-9 | Search for facilities by attribute | Recommended | ITI-90 with configurable search parameters per resource |
| FRF-10 | Facility on a map (geolocation) | Recommended | Location Distance Option (`near` search); `Location.position` (lat/long) |
| FRF-11 | Public access to relevant data (e.g., services) | Recommended | Configurable public vs. authenticated endpoints per resource type |
| FRF-12 | Facility data curation (closures, openings, service changes) | Recommended | ITI-130 update/delete + `Location.status` / `Organization.active` lifecycle |
| FR-13 | Standard and customizable reports | Recommended | FHIR `$everything` operation + analytics views; integration with HMIS (DHIS2) |
| FR-14 | Align with primary Master Facility List | Recommended | FR *is* the MFL technology; Event-Driven Sync publishes changes to downstream consumers |

### 1.3 OpenHIE Care Services Discovery Workflows

The OpenHIE architecture defines four Care Services Discovery workflows that the FR participates in. These map directly to mCSD transactions:

**Workflow 1: Query Health Worker and/or Facility Records (FRWF-1 — Required)**

This is the legacy CSD (ITI-73/ITI-74) workflow, now transitioning to mCSD. In the OpenHIE model:

```
PoS ──ITI-90──▶ IOL ──ITI-90──▶ ILR (InfoManager) ──ITI-91──▶ FR (Directory)
                                                     ──ITI-91──▶ HWR (Directory)
```

The ILR is an **Update Client** that periodically polls both the FR and HWR via ITI-91, merges the data per jurisdictional policy, and then serves as a **Directory** to the IOL and downstream PoS systems via ITI-90.

**Workflow 2: Query Care Services Records (mCSD — Maturing)**

Direct FHIR-based query flow using mCSD:

```
PoS ──ITI-90──▶ IOL ──ITI-90──▶ ILR (Directory)
                                  │
                      ┌───────────┼───────────┐
                      ▼           ▼           ▼
               FR (Directory) HWR (Directory) ...
              via ITI-91 polling
```

**Workflow 3: Search Care Services (mCSD — Direct)**

For simpler deployments without an ILR:

```
PoS ──ITI-90──▶ ILR/FR (Directory)
```

**Workflow 4: Request Care Services Updates**

```
ILR (Update Client) ──ITI-91──▶ FR (Directory)
ILR (Update Client) ──ITI-91──▶ HWR (Directory)
```

### 1.4 Actor Mapping: OpenHIE Components → mCSD Actors

| OpenHIE Component | mCSD Actor(s) | Transactions |
|-------------------|---------------|-------------|
| **Facility Registry (FR)** | Directory (+ Feed Option) | ITI-90 responder, ITI-91 responder, ITI-130 responder |
| **Health Worker Registry (HWR)** | Directory | ITI-90 responder, ITI-91 responder |
| **InterLinked Registry (ILR/InfoManager)** | Update Client + Directory | ITI-91 initiator (polling FR/HWR), ITI-90 responder (serving merged data) |
| **Interoperability Layer (IOL)** | Transparent proxy (not an mCSD actor) | Routes ITI-90/91/130 transactions; handles auth, audit, logging |
| **Point-of-Service (PoS)** | Query Client | ITI-90 initiator |
| **Hospital/Facility (Data Source)** | Data Source | ITI-130 initiator |
| **DHIS2 / HMIS** | Update Client or Query Client | ITI-91 initiator (bulk sync) or ITI-90 initiator (ad-hoc queries) |
| **LMIS** | Update Client | ITI-91 initiator (supply chain facility list sync) |

### 1.5 What This Means for Our Implementation

The FR doesn't operate in isolation — it's one node in the OpenHIE mesh. Our implementation must:

1. **Be IOL-aware:** All external traffic arrives through the IOL (e.g., OpenHIM). The FR doesn't need to implement its own public-facing auth gateway in a full OpenHIE deployment — the IOL handles ATNA, authentication, and routing. But it must support standalone deployment (with its own auth) for non-OpenHIE contexts.

2. **Support the ILR polling pattern:** The ILR (InfoManager) is an Update Client that polls the FR via ITI-91 on a schedule. The FR must support `_history` with `_since` reliably and with good performance, even for large datasets.

3. **Coexist with the HWR:** In the OpenHIE model, Practitioners live in the HWR, not the FR. The FR manages Organizations, Locations, and HealthcareServices. The ILR merges them. The Sri Lanka IG follows this exact split — Practitioner/PractitionerRole in the Provider Registry, facilities in the FR. Our tenant configuration must support this split cleanly.

4. **Support downstream consumers:** DHIS2, LMIS, and other systems consume facility data via ITI-91 or ITI-90. The FR must handle concurrent polling from multiple Update Clients efficiently.

5. **Serve as the MFL:** The FR is the authoritative source for the Master Facility List. Bulk import (FRF-8), data curation (FRF-12), and hierarchical management (FRF-2) are required capabilities, not nice-to-haves.

---

## 2. Problem Statement & Design Goals

### The Problem

Different jurisdictions publish their own FHIR Implementation Guides that constrain the same base resources differently. The Sri Lanka Ministry of Health's Facility Registry IG defines `LKOrganization`, `LKLocation`, and `LKService` profiles with Sri Lanka-specific constraints (mandatory identifiers, LKAddress data type, specific reference targets). Meanwhile, the IHE mCSD IG defines a broader set of profiles (`IHE.mCSD.Organization`, `IHE.mCSD.FacilityOrganization`, `IHE.mCSD.Location`, etc.) with its own constraint set. Building a separate server for each IG is wasteful and prevents reuse.

### Design Goals

| Goal | Metric |
|------|--------|
| **IG-Agnostic Core** | Zero core code changes required to adopt a new IG |
| **Profile Swappability** | New profiles added via configuration + validation package, not code changes |
| **Terminology Extensibility** | Code systems and value sets loaded from external packages |
| **Search Configurability** | Search parameters declared per-tenant, not hardcoded |
| **Deployment Flexibility** | Same binary runs as single-tenant MoH registry or multi-tenant OpenHIE node |
| **Transaction Completeness** | Full ITI-90, ITI-91, ITI-130 support as optional, composable modules |
| **Federated-Ready** | Built-in support for Update Client (ITI-91 consumer) aggregation |

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        API Gateway / TLS                            │
│                   (IHE IUA / OAuth 2.0 / mTLS)                      │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────────┐
│                      FHIR REST Controller                           │
│  ┌──────────┐  ┌───────────┐  ┌──────────┐  ┌───────────────────┐  │
│  │ ITI-90   │  │  ITI-91   │  │ ITI-130  │  │  /metadata        │  │
│  │ Search   │  │  History  │  │  Feed    │  │  CapabilityStmt   │  │
│  └────┬─────┘  └─────┬─────┘  └────┬─────┘  └────────┬──────────┘  │
└───────┼──────────────┼──────────────┼─────────────────┼─────────────┘
        │              │              │                  │
┌───────▼──────────────▼──────────────▼─────────────────▼─────────────┐
│                    Service Layer (Domain Logic)                      │
│  ┌────────────────┐  ┌──────────────────┐  ┌─────────────────────┐  │
│  │  SearchService │  │  HistoryService  │  │   FeedService       │  │
│  └───────┬────────┘  └────────┬─────────┘  └──────────┬──────────┘  │
│          │                    │                        │             │
│  ┌───────▼────────────────────▼────────────────────────▼──────────┐  │
│  │              Validation Pipeline (per-tenant)                  │  │
│  │   ┌─────────────┐   ┌──────────────┐   ┌──────────────────┐   │  │
│  │   │ FHIR Base   │──▶│ mCSD Profile │──▶│ LK/Jurisdiction  │   │  │
│  │   │ Validation  │   │ Validation   │   │ Profile Valid.    │   │  │
│  │   └─────────────┘   └──────────────┘   └──────────────────┘   │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │              Search Parameter Registry                         │  │
│  │   Loaded from IG package → per-resource, per-tenant            │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │              Terminology Service (SPI)                          │  │
│  │   In-memory ValueSets ─OR─ External SVCM endpoint              │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────┬───────────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────────┐
│                  Repository Layer (Strategy)                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │
│  │  PostgreSQL   │  │  HAPI JPA    │  │  In-Memory (testing)     │  │
│  │  + JSONB      │  │  Backend     │  │                          │  │
│  └──────────────┘  └──────────────┘  └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────────┐
│                   Cross-Cutting Concerns                             │
│  ┌─────────────┐  ┌──────────┐  ┌──────────┐  ┌────────────────┐  │
│  │ Audit (ATNA)│  │Provenance│  │ Event Bus│  │  CapStatement  │  │
│  │             │  │ Tracker  │  │ (Sync)   │  │  Builder       │  │
│  └─────────────┘  └──────────┘  └──────────┘  └────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. Design Patterns

### 3.1 Profile Adapter Pattern

**Problem:** The same FHIR resource (e.g., `Organization`) is constrained differently by mCSD (`IHE.mCSD.Organization`, `IHE.mCSD.FacilityOrganization`) and Sri Lanka (`LKOrganization`). The core server shouldn't know which profile is in play.

**Solution:** Define a `ProfileAdapter` interface that maps between the IG-specific profile URLs and the core resource handling.

```
ProfileAdapter
├── getCanonicalUrl(): string              // e.g. "http://ig.hiu.lk/.../LKOrganization"
├── getBaseResourceType(): string          // e.g. "Organization"
├── getRequiredElements(): string[]        // e.g. ["identifier", "address"]
├── getSearchParameters(): SearchParam[]   // Parameters this profile supports
├── getReferenceTargets(element): string[] // e.g. LKService.providedBy → LKOrganization
└── getStructureDefinition(): JSON         // The full StructureDefinition
```

**Configuration-driven loading:**

```yaml
# config/profiles/lk-facility-registry.yaml
ig:
  package: "fhir.lk.facilityregistry#0.1.0"
  canonical: "http://ig.hiu.lk/fhir/facilityregistry"
  profiles:
    - resource: Organization
      profile: LKOrganization
      url: "http://ig.hiu.lk/fhir/facilityregistry/StructureDefinition/LKOrganization"
    - resource: Location
      profile: LKLocation
      url: "http://ig.hiu.lk/fhir/facilityregistry/StructureDefinition/LKLocation"
    - resource: HealthcareService
      profile: LKService
      url: "http://ig.hiu.lk/fhir/facilityregistry/StructureDefinition/LKService"

# config/profiles/mcsd.yaml
ig:
  package: "ihe.iti.mcsd#4.0.1"
  canonical: "https://profiles.ihe.net/ITI/mCSD"
  profiles:
    - resource: Organization
      profile: IHE.mCSD.Organization
      url: "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.Organization"
    - resource: Organization
      profile: IHE.mCSD.FacilityOrganization
      url: "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.FacilityOrganization"
    # ... 12 more profiles
```

**Key benefit:** Adding the Sri Lanka IG is a YAML file + dropping the IG npm package into the validation classpath. Zero code changes.

---

### 3.2 Pluggable Validation Pipeline

**Problem:** Validation must layer: FHIR R4 base → mCSD profile → jurisdiction profile. Different tenants need different pipelines.

**Solution:** Chain of Responsibility pattern with ordered validators.

```
ValidationPipeline
├── FhirBaseValidator          // R4 schema, cardinality, data types
├── ProfileValidator           // StructureDefinition constraints (from IG package)
├── TerminologyValidator       // ValueSet bindings (required vs preferred)
├── ReferenceIntegrityValidator // Check that references resolve
├── BusinessRuleValidator      // Jurisdiction-specific (e.g., LK: identifier 1..*)
└── CustomValidator[]          // Pluggable hooks for deployment-specific rules
```

Each validator returns a `ValidationResult` with severity (error/warning/info). The pipeline short-circuits on errors or collects all issues depending on configuration.

**Per-tenant pipeline example:**

```yaml
tenants:
  sri-lanka-moh:
    validation:
      chain:
        - fhir-r4-base
        - profile: "fhir.lk.facilityregistry#0.1.0"
        - terminology: inline    # ValueSets bundled in IG package
        - reference-integrity: strict
        - business-rules: "lk-facility-rules"

  openhie-reference:
    validation:
      chain:
        - fhir-r4-base
        - profile: "ihe.iti.mcsd#4.0.1"
        - terminology: svcm      # External terminology service
        - reference-integrity: lenient
```

---

### 3.3 Repository Abstraction (Strategy Pattern)

**Problem:** Different deployments need different storage backends — PostgreSQL for production, HAPI JPA for FHIR-native environments, in-memory for testing.

**Solution:** Repository interface with swappable implementations.

```
FhirRepository<T extends Resource>
├── create(resource: T): T
├── read(type: string, id: string): T
├── update(resource: T): T
├── delete(type: string, id: string): void
├── search(type: string, params: SearchParams): Bundle
├── history(type: string, since?: Instant): Bundle
├── historyInstance(type: string, id: string): Bundle
└── transaction(bundle: Bundle): Bundle
```

**PostgreSQL implementation (recommended):**

```
┌────────────────────────────────────────────────────────┐
│                   fhir_resources                        │
├────────────────────────────────────────────────────────┤
│ id             UUID PRIMARY KEY                        │
│ resource_type  VARCHAR(64) NOT NULL                    │
│ fhir_id        VARCHAR(64) NOT NULL                    │
│ version_id     INTEGER NOT NULL DEFAULT 1              │
│ last_updated   TIMESTAMPTZ NOT NULL                    │
│ is_deleted     BOOLEAN NOT NULL DEFAULT false          │
│ tenant_id      VARCHAR(64) NOT NULL                    │
│ resource_json  JSONB NOT NULL                          │
│ UNIQUE(tenant_id, resource_type, fhir_id)             │
├────────────────────────────────────────────────────────┤
│ GIN index on resource_json                             │
│ B-tree index on (tenant_id, resource_type, fhir_id)   │
│ B-tree index on (tenant_id, resource_type, last_updated│)
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│               fhir_resource_history                     │
├────────────────────────────────────────────────────────┤
│ id             UUID PRIMARY KEY                        │
│ resource_id    UUID REFERENCES fhir_resources(id)      │
│ version_id     INTEGER NOT NULL                        │
│ last_updated   TIMESTAMPTZ NOT NULL                    │
│ request_method VARCHAR(10)  -- POST/PUT/DELETE         │
│ resource_json  JSONB                                   │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│          search_index_token (denormalized)              │
├────────────────────────────────────────────────────────┤
│ resource_id    UUID REFERENCES fhir_resources(id)      │
│ tenant_id      VARCHAR(64)                             │
│ resource_type  VARCHAR(64)                             │
│ param_name     VARCHAR(128)  -- e.g. "identifier"      │
│ system         VARCHAR(512)                            │
│ code           VARCHAR(512)                            │
│ INDEX (tenant_id, resource_type, param_name, system, code)
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│          search_index_string (denormalized)             │
├────────────────────────────────────────────────────────┤
│ resource_id    UUID                                    │
│ tenant_id      VARCHAR(64)                             │
│ resource_type  VARCHAR(64)                             │
│ param_name     VARCHAR(128)  -- e.g. "name"            │
│ value          VARCHAR(1024)                           │
│ value_normalized VARCHAR(1024)  -- lowercase, trimmed   │
│ INDEX (tenant_id, resource_type, param_name, value_normalized)
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│          search_index_reference (denormalized)          │
├────────────────────────────────────────────────────────┤
│ resource_id    UUID                                    │
│ tenant_id      VARCHAR(64)                             │
│ resource_type  VARCHAR(64)                             │
│ param_name     VARCHAR(128)  -- e.g. "organization"    │
│ target_type    VARCHAR(64)                             │
│ target_id      VARCHAR(64)                             │
│ INDEX (tenant_id, resource_type, param_name, target_type, target_id)
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│          search_index_location (PostGIS)                │
├────────────────────────────────────────────────────────┤
│ resource_id    UUID                                    │
│ tenant_id      VARCHAR(64)                             │
│ geom           GEOMETRY(Point, 4326)                   │
│ SPATIAL INDEX on geom                                  │
└────────────────────────────────────────────────────────┘
```

**Why JSONB + denormalized indexes:**
The full resource is stored as JSONB (lossless, supports arbitrary extensions). Denormalized search index tables are populated on write by the Search Indexer service, which reads the Search Parameter Registry to know which fields to extract. This avoids runtime JSONB path queries for search while keeping storage flexible for any IG.

---

### 3.4 Search Parameter Registry (Registry Pattern)

**Problem:** mCSD requires specific search parameters per resource (e.g., Organization must support `active`, `identifier`, `name`, `type`, `partof`). The LK IG has a different, smaller set (`_id`, `active`, `address`, `name`). These must be configurable per tenant without code changes.

**Solution:** A runtime registry of search parameters loaded from configuration.

```yaml
# Loaded at startup from IG package SearchParameter definitions
search-parameters:
  Organization:
    - name: "_id"
      type: token
      expression: "Organization.id"
      required: true        # All IGs
    - name: "active"
      type: token
      expression: "Organization.active"
      igs: [mcsd, lk-fr]    # Both IGs need this
    - name: "identifier"
      type: token
      expression: "Organization.identifier"
      igs: [mcsd, lk-fr]
    - name: "name"
      type: string
      expression: "Organization.name"
      modifiers: [contains, exact]  # mCSD requires these
      igs: [mcsd, lk-fr]
    - name: "type"
      type: token
      expression: "Organization.type"
      igs: [mcsd]           # mCSD only
    - name: "address"
      type: string
      expression: "Organization.address"
      igs: [lk-fr]          # LK FR only
    - name: "partof"
      type: reference
      expression: "Organization.partOf"
      igs: [mcsd]
      conformance: SHOULD   # mCSD says SHOULD, not SHALL
```

The **Search Indexer** reads this registry on every create/update to build the denormalized index rows. The **Search Service** reads it to validate incoming query parameters and build SQL.

---

### 3.5 Transaction Orchestrator (Template Method)

**Problem:** ITI-90 (search), ITI-91 (history), and ITI-130 (feed/CRUD) share common patterns (auth check → validate → execute → audit → respond) but differ in core logic. Some deployments need only ITI-90; others need all three.

**Solution:** Template Method pattern with optional transaction modules.

```
abstract TransactionHandler
├── authenticate(request)          // Shared: IUA/OAuth
├── authorize(request, resource)   // Shared: RBAC
├── abstract execute(request)      // Subclass-specific
├── audit(request, response)       // Shared: ATNA
└── respond(result)                // Shared: content negotiation

ITI90SearchHandler extends TransactionHandler
├── execute: parse search params → query repository → build searchset Bundle

ITI91HistoryHandler extends TransactionHandler
├── execute: parse _since → query history → build history Bundle

ITI130CreateHandler extends TransactionHandler
├── execute: validate → run pipeline → repository.create → index → 201

ITI130UpdateHandler extends TransactionHandler
├── execute: validate → check exists → repository.update → re-index → 200

ITI130DeleteHandler extends TransactionHandler
├── execute: check exists → repository.delete (soft) → de-index → 200/204

ITI130TransactionHandler extends TransactionHandler
├── execute: parse Bundle → validate all → atomic repository.transaction → 200
```

**Module enablement via configuration:**

```yaml
transactions:
  iti-90: true           # Always on (required for Directory)
  iti-91: true           # Update Option
  iti-130: true          # Feed Option
  location-distance: true # Location Distance Option
```

---

### 3.6 Terminology Binding SPI

**Problem:** mCSD may mandate jurisdiction-specific terminologies. The LK IG uses standard FHIR ValueSets (e.g., `LocationStatus`). Others may have custom code systems. The validation layer needs to resolve bindings without hardcoding.

**Solution:** Service Provider Interface for terminology resolution.

```
TerminologyService (SPI)
├── validateCode(system, code, valueSetUrl): ValidationResult
├── expandValueSet(valueSetUrl): List<Coding>
├── lookup(system, code): CodeSystem.Concept
└── translate(source, target, coding): ConceptMap.Match

InMemoryTerminologyService implements TerminologyService
  // Loads ValueSets/CodeSystems from IG packages at startup
  // Suitable for standalone deployments

SVCMTerminologyService implements TerminologyService
  // Proxies to an external IHE SVCM-compliant server
  // Suitable for federated/cross-jurisdictional deployments

CachingTerminologyService implements TerminologyService
  // Wraps either implementation with TTL-based cache
```

---

### 3.7 Tenant Context & Multi-IG Support

**Problem:** A single server deployment may need to serve both the LK Facility Registry (for MoH) and an mCSD-compliant directory (for OpenHIE interoperability) — or a future Bangladeshi or Kenyan IG.

**Solution:** Tenant context resolved from the request (URL path, header, or subdomain) that selects the active IG configuration.

```
Request flow:
  POST /lk-moh/Organization → TenantResolver → tenant="lk-moh"
  GET  /openhie/Organization?name=test → TenantResolver → tenant="openhie"

TenantContext:
  tenantId: "lk-moh"
  igPackage: "fhir.lk.facilityregistry#0.1.0"
  profiles: [LKOrganization, LKLocation, LKService]
  searchParams: {Organization: [...], Location: [...], ...}
  validationPipeline: [fhir-r4, lk-profiles, lk-terminology]
  transactions: [iti-90, iti-130]
  capabilityStatement: (generated)
```

For single-tenant deployments, the tenant is implicit and the path prefix is omitted.

---

### 3.8 Event-Driven Sync (Observer Pattern)

**Problem:** In federated deployments, an Update Client needs to poll multiple Directories and aggregate data. Changes in one Directory should be propagable. Also, search indexes need to be updated on every write.

**Solution:** Internal event bus with observers.

```
Events:
  RESOURCE_CREATED   { tenantId, resourceType, resourceId, resource }
  RESOURCE_UPDATED   { tenantId, resourceType, resourceId, resource, previousVersion }
  RESOURCE_DELETED   { tenantId, resourceType, resourceId }

Observers:
  SearchIndexer          → rebuilds denormalized search index rows
  HistoryRecorder        → writes to fhir_resource_history
  AuditLogger            → creates AuditEvent per ATNA
  ProvenanceTracker      → creates Provenance resource
  FederationPublisher    → notifies upstream Update Clients (webhook/polling flag)
  DuplicateDetector      → flags potential duplicates for review
```

---

### 3.9 Facade Pattern for Cross-Registry Orchestration

**Problem:** The LK IG explicitly calls out that common queries like "Who is this Provider working for?" require multi-step queries across the Facility Registry and the Provider Registry. The IG recommends a facade/orchestration layer.

**Solution:** FHIR Operations facade that composes multi-registry queries.

```
FacilityRegistryFacade
├── $find-providers-by-organization(orgId)
│   → GET /HealthcareService?organization=Organization/{orgId}
│   → for each service: GET /PractitionerRole?service=HealthcareService/{id}
│   → return aggregated Bundle
│
├── $find-services-at-location(locationId)
│   → GET /HealthcareService?location=Location/{locationId}
│   → _include=HealthcareService:organization
│   → return Bundle
│
├── $find-nearest-service(lat, lon, serviceType)
│   → GET /Location?near={lat}|{lon}
│   → _has:HealthcareService:location:service-type={type}
│   → return Bundle with distance
```

This sits as an optional module on top of the core FHIR REST layer. It handles the cross-registry orchestration the LK IG describes, while the underlying repositories remain clean and single-purpose.

---

### 3.10 CapabilityStatement Generator (Builder Pattern)

**Problem:** Each IG/tenant combination produces a different CapabilityStatement. This must be auto-generated from the active configuration, not hand-coded.

**Solution:** Builder that reads the active profile adapters, search parameter registry, and enabled transactions to produce a conformant CapabilityStatement.

```
CapabilityStatementBuilder
  .withTenant(tenantContext)
  .withServerInfo(name, version, fhirVersion)
  .withProfiles(tenantContext.profiles)
  .withSearchParams(tenantContext.searchParams)
  .withTransactions(tenantContext.transactions)
  .withSecurityScheme(oauth2, iua)
  .build() → CapabilityStatement resource
```

The generated CapabilityStatement is cached and served at `GET [base]/metadata`. It automatically reflects which resources, search parameters, and operations are available for the current tenant.

---

### 4.11 Interoperability Layer Gateway (Mediator Pattern)

**Problem:** In the OpenHIE architecture, the FR doesn't face the public internet directly. The Interoperability Layer (IOL — typically OpenHIM) sits in front, handling authentication, audit logging, routing, and orchestration. But the FR must also work standalone for non-OpenHIE deployments. Additionally, the IOL needs to orchestrate multi-registry queries (e.g., merging FR + HWR data) before returning results to the PoS.

**Solution:** A Mediator pattern with two deployment modes — IOL-fronted and standalone.

```
Mode 1: OpenHIE Deployment (IOL-fronted)
┌─────┐     ┌──────────────────────────────┐     ┌──────────────┐
│ PoS │────▶│ IOL (OpenHIM)                │────▶│ FR (mCSD     │
│     │     │ • ATNA audit logging         │     │  Directory)  │
│     │     │ • OAuth2/mTLS authentication │     │ • Trusts IOL │
│     │     │ • Route to FR or ILR         │     │   headers    │
│     │     │ • Error management           │     │ • No public  │
│     │     │ • Transaction logging        │     │   auth       │
│     │◀────│ • Orchestration (merge       │◀────│              │
│     │     │   FR+HWR responses)          │     │              │
└─────┘     └──────────────────────────────┘     └──────────────┘

Mode 2: Standalone Deployment (no IOL)
┌─────┐     ┌──────────────────────────────────────────┐
│ PoS │────▶│ FR (mCSD Directory)                       │
│     │     │ • Built-in OAuth2/IUA auth                │
│     │     │ • Built-in ATNA audit                     │
│     │     │ • Built-in rate limiting                  │
│     │◀────│ • Serves PoS directly                     │
└─────┘     └──────────────────────────────────────────┘
```

**Configuration:**

```yaml
deployment:
  mode: openhie          # or "standalone"

  openhie:
    iol:
      trust-headers: true                    # Trust X-OpenHIM-* auth headers
      expected-source-ips: ["10.0.0.0/8"]   # Only accept from IOL network
      audit-delegation: true                 # IOL handles ATNA; FR skips
      registration:                          # Register as OpenHIM mediator
        url: "https://openhim-core:8080"
        urn: "urn:mediator:facility-registry"

  standalone:
    auth:
      provider: oauth2
      issuer: "https://auth.health.gov.lk"
    audit: atna-internal
    rate-limiting: true
```

**OpenHIM Mediator Registration:**

In OpenHIE deployments, the FR registers itself as an OpenHIM mediator, declaring its routes and capabilities. The IOL then knows how to route ITI-90/91/130 traffic to the FR, and can orchestrate multi-step workflows (e.g., query FR then HWR then merge).

```
IOL Orchestration Example: Query Care Services Records Workflow
═══════════════════════════════════════════════════════════════

Step 0: ILR (InfoManager) periodically polls FR and HWR via ITI-91
        ILR merges data into its local cache

Step 1: PoS sends ITI-90 search to IOL
Step 2: IOL checks PoS authentication + authorization
Step 3: IOL routes ITI-90 to ILR (which has merged FR+HWR data)
Step 4: ILR returns FHIR Bundle
Step 5: IOL logs the transaction and returns response to PoS

If no ILR exists (simple deployment):
Step 3: IOL routes directly to FR
Step 4: FR returns FHIR Bundle (facility data only — no health workers)
```

This pattern ensures the FR implements pure FHIR mCSD logic while the IOL handles all cross-cutting infrastructure concerns. The FR doesn't need to know whether it's behind an IOL or serving clients directly — the deployment mode configuration swaps the auth and audit layers.

---

## 5. Gap Analysis: IHE mCSD vs. Sri Lanka HIU FR IG

| Aspect | IHE mCSD v4.0.1 | Sri Lanka FR IG v0.1.0 | Adapter Strategy |
|--------|-----------------|----------------------|-----------------|
| **Resources** | Organization, Location, Practitioner, PractitionerRole, HealthcareService, Endpoint, OrganizationAffiliation (9 profiles) | Organization, Location, HealthcareService only (3 profiles) | Profile Adapter pattern — LK tenant loads only 3 profiles; mCSD tenant loads all 9 |
| **Practitioner/PractitionerRole** | Managed within mCSD Directory | Explicitly excluded — managed by separate Provider Registry | Tenant config excludes these resources; facade handles cross-registry queries |
| **Endpoint** | Core resource for network discovery | Not in scope | Enabled per-tenant; LK tenant disables |
| **OrganizationAffiliation** | Core resource for non-hierarchical relationships | Not in scope | Enabled per-tenant |
| **Facility model** | Location + Organization pair via `managingOrganization` | HealthcareService → Organization (`providedBy` 1..1) + HealthcareService → Location (`location` 0..1) | Different linking strategy: mCSD links Location→Organization; LK links via HealthcareService as the hub. Profile Adapter maps both |
| **Organization.identifier** | 0..* (base FHIR) | 1..* (mandatory) | Validation pipeline enforces per-IG cardinality |
| **Location.identifier** | 0..* (base FHIR) | 1..* (mandatory) | Validation pipeline enforces per-IG |
| **Location.address** | 0..1 (base FHIR) | 1..1 (mandatory, constrained to `LKAddress`) | Custom data type validation in LK pipeline |
| **HealthcareService.providedBy** | 0..1 (base) | 1..1 (mandatory, must reference `LKOrganization`) | Reference target validation in LK pipeline |
| **HealthcareService.location** | 0..* (base) | 0..1 (max 1, must reference `LKLocation`) | Cardinality + reference target validation |
| **Search: Organization** | `active`, `identifier`, `name`, `type`, `partof`, multiple `_include`/`_revInclude` | `_id`, `active`, `address`, `name` | Search Parameter Registry loads per-tenant |
| **Search: Location** | `identifier`, `name`, `organization`, `status`, `type`, `partof`, `near` | `_id`, `address`, `name`, `near`, `status` | Search Parameter Registry loads per-tenant |
| **Search: HealthcareService** | `active`, `identifier`, `location`, `name`, `organization`, `service-type` | `_id`, `active`, `characteristic`, `location`, `name`, `organization`, `program`, `service-category`, `service-type`, `specialty` | LK actually has *more* HS search params than mCSD — union registered |
| **String modifiers** | `:contains` and `:exact` required | Not specified | Enabled for mCSD; optional for LK |
| **ITI-91 (History/Update)** | Optional (Update Option) | `vread` supported (instance history) | ITI-91 module handles both full history and instance vread |
| **ITI-130 (Feed/CRUD)** | Optional (Feed Option) — POST, PUT, DELETE, transaction Bundle | POST and PUT specified; no transaction Bundle mentioned | LK uses a subset of ITI-130; transaction Bundle disabled for LK tenant |
| **Cross-registry queries** | Self-contained (all resources in one Directory) | Multi-registry (Facility + Provider separate) | Facade pattern handles orchestration; direct FHIR queries still exposed |

---

## 5. Module Architecture

```
mcsd-platform/
├── core/                          # IG-agnostic, never changes per jurisdiction
│   ├── fhir-model/                # FHIR R4 resource model (HAPI structures or custom)
│   ├── repository-api/            # FhirRepository interface + SearchParams model
│   ├── validation-api/            # Validator interface + ValidationResult
│   ├── search-engine/             # Query builder, param parsing, modifier support
│   ├── event-bus/                 # RESOURCE_CREATED/UPDATED/DELETED events
│   └── capability-builder/        # CapabilityStatement auto-generator
│
├── transactions/                  # Composable IHE transaction modules
│   ├── iti-90-search/             # Find Matching Care Services
│   ├── iti-91-history/            # Request Care Services Updates
│   ├── iti-130-feed/              # Care Services Feed (CRUD + transaction)
│   └── location-distance/         # near search parameter support (PostGIS)
│
├── adapters/                      # Swappable infrastructure
│   ├── repository-postgres/       # PostgreSQL + JSONB + denormalized indexes
│   ├── repository-hapi-jpa/       # HAPI FHIR JPA backend
│   ├── repository-inmemory/       # For testing
│   ├── terminology-inline/        # ValueSets loaded from IG packages
│   ├── terminology-svcm/          # External SVCM proxy
│   ├── auth-iua/                  # IHE IUA implementation
│   ├── auth-oauth2/               # Standard OAuth 2.0
│   └── audit-atna/                # ATNA audit logging
│
├── ig-packages/                   # Dropped-in IG definitions
│   ├── ihe.iti.mcsd-4.0.1/        # mCSD StructureDefinitions, CapabilityStatements
│   └── fhir.lk.facilityregistry-0.1.0/  # LK profiles, CapabilityStatement
│
├── tenants/                       # Per-tenant configuration
│   ├── mcsd-default.yaml          # IHE mCSD reference config
│   ├── lk-facility-registry.yaml  # Sri Lanka MoH config
│   └── custom-template.yaml       # Template for new jurisdictions
│
├── facade/                        # Optional orchestration layer
│   └── cross-registry-operations/ # $find-providers-by-organization, etc.
│
└── server/                        # Application shell
    ├── rest-controller/           # HTTP routing, content negotiation
    ├── tenant-resolver/           # Resolves tenant from request
    └── config-loader/             # Loads tenant YAML + IG packages
```

---

## 6. Data Model Design

### 6.1 Facility Linking Strategy Abstraction

The core difference between mCSD and the LK IG is how they model a "facility":

**mCSD:** Facility = Location (with `managingOrganization` → Organization)
```
Location ──managingOrganization──▶ Organization
```

**Sri Lanka FR IG:** Facility = HealthcareService as the hub
```
HealthcareService ──providedBy──▶ Organization
HealthcareService ──location──▶ Location
```

Both are stored as standard FHIR resources in the repository. The difference is enforced by the validation pipeline and the search parameter registry — not by the data model. The repository stores whatever valid FHIR resources are submitted; the IG configuration determines what's valid.

### 6.2 Hierarchy Support

Both IGs support hierarchical organizations (`Organization.partOf`). The LK IG demonstrates this with hospital departments (Emergency Dept., Cardiology Dept.) as child Organizations.

mCSD adds `Location.partOf` for location hierarchies (country → province → district → facility) and `OrganizationAffiliation` for non-hierarchical relationships (HIE memberships, supply chains).

The repository supports all these via the reference search index — `partof` queries traverse the `search_index_reference` table regardless of which IG is active.

---

## 7. Implementation Phases

### Phase 1: Core Platform (Weeks 1–4)

| Task | Deliverable |
|------|------------|
| Set up project scaffold with module structure | Build system, dependency management |
| Implement `FhirRepository` interface + PostgreSQL adapter | CRUD + JSONB storage + history table |
| Implement Search Indexer with denormalized tables | Token, string, reference indexes populated on write |
| Implement Tenant Resolver + Config Loader | YAML-driven tenant configuration |
| Implement Profile Adapter + IG package loader | Load StructureDefinitions from IG packages |
| Implement CapabilityStatement Builder | Auto-generated `/metadata` per tenant |

### Phase 2: ITI-90 — Search (Weeks 5–7)

| Task | Deliverable |
|------|------------|
| Search Parameter Registry from IG config | Per-tenant parameter sets |
| Search query builder (SQL generation from FHIR params) | `_id`, `_lastUpdated`, string (`:contains`, `:exact`), token, reference |
| `_include` / `_revInclude` support | JOIN-based inclusion in search results |
| Pagination (Bundle.link `next`) | Cursor-based or offset pagination |
| Content negotiation (JSON + XML) | Accept header handling |
| Read interaction (`GET [base]/[type]/[id]`) | Direct retrieval + 404 handling |

### Phase 3: Validation Pipeline (Weeks 8–9)

| Task | Deliverable |
|------|------------|
| FHIR R4 base validator | Schema, cardinality, data type validation |
| Profile validator (from StructureDefinition) | IG-specific constraints (e.g., LKOrganization.identifier 1..*) |
| Terminology validator (inline ValueSets) | Required/preferred binding enforcement |
| Reference integrity validator | Check that referenced resources exist |
| Validation pipeline composer (per-tenant chain) | Configurable chain from YAML |

### Phase 4: ITI-130 — Feed (Weeks 10–12)

| Task | Deliverable |
|------|------------|
| Create (POST) with validation pipeline | Profile-validated create, 201 response |
| Update (PUT) with version checking | Optimistic locking, 200 response |
| Delete (soft-delete) | Mark as deleted, preserve history |
| Transaction Bundle (atomic) | All-or-nothing Bundle processing |
| LK-specific: disable transaction Bundle | Per-tenant transaction feature flags |

### Phase 5: ITI-91 — History + Location Distance (Weeks 13–14)

| Task | Deliverable |
|------|------------|
| FHIR history (`_history`) with `_since` | History Bundle from `fhir_resource_history` table |
| Instance vread (`[type]/[id]/_history/[vid]`) | Version-specific retrieval (needed by LK IG) |
| PostGIS integration for `near` search | Spatial index + Haversine distance query |
| Distance-sorted results | Order by ST_Distance |

### Phase 6: Security, Audit & Provenance (Weeks 15–16)

| Task | Deliverable |
|------|------------|
| TLS termination (gateway or server) | HTTPS enforcement |
| OAuth 2.0 / IUA auth module | Token validation, scope checking |
| RBAC authorization | Read-only (Query Client), read-write (Data Source) |
| ATNA audit events | Per-transaction audit logging |
| Provenance tracking for ITI-130 | Auto-created Provenance on write |

### Phase 7: Facade & Federation (Weeks 17–19)

| Task | Deliverable |
|------|------------|
| Cross-registry facade operations | `$find-providers-by-organization`, etc. |
| Update Client polling agent | Scheduled ITI-91 polling of remote Directories |
| Conflict resolution framework | Pluggable duplicate detection + resolution strategies |
| Federation event publisher | Notify upstream on local changes |

### Phase 8: Testing & Certification (Weeks 20–22)

| Task | Deliverable |
|------|------------|
| Profile validation test suite | Validate sample resources against both IGs |
| ITI-90 conformance tests | All search params, modifiers, _include, pagination |
| ITI-91 conformance tests | History with _since, instance vread |
| ITI-130 conformance tests | Create, update, delete, transaction Bundle |
| LK IG conformance tests | LK-specific cardinality, reference targets, search params |
| Multi-tenant integration tests | Same server serving both IGs simultaneously |
| Performance benchmarks | Search latency, write throughput, history query speed |

---

## 8. Configuration Reference

### 8.1 Tenant Configuration Template

```yaml
# tenants/[jurisdiction].yaml
tenant:
  id: "lk-facility-registry"
  name: "Sri Lanka Ministry of Health Facility Registry"
  description: "National Facility Registry per HIU IG v0.1.0"

ig:
  package: "fhir.lk.facilityregistry#0.1.0"
  canonical: "http://ig.hiu.lk/fhir/facilityregistry"

resources:
  enabled:
    - Organization
    - Location
    - HealthcareService
  disabled:
    - Practitioner           # Managed by Provider Registry
    - PractitionerRole       # Managed by Provider Registry
    - Endpoint               # Not in LK FR scope
    - OrganizationAffiliation # Not in LK FR scope

profiles:
  Organization: "LKOrganization"
  Location: "LKLocation"
  HealthcareService: "LKService"

transactions:
  iti-90: true               # Search — required
  iti-91:
    enabled: true
    instance-vread: true     # GET [type]/[id]/_history/[vid]
    type-history: false      # Full type-level _history not specified in LK IG
  iti-130:
    enabled: true
    create: true
    update: true
    delete: false            # Not specified in LK IG
    transaction-bundle: false # Not specified in LK IG

search:
  Organization:
    params: [_id, active, address, name]
    modifiers: []            # No :contains/:exact specified
  Location:
    params: [_id, address, name, near, status]
    modifiers: []
  HealthcareService:
    params: [_id, active, characteristic, location, name, organization,
             program, service-category, service-type, specialty]
    modifiers: []

validation:
  chain:
    - fhir-r4-base
    - ig-profile
    - terminology-inline
    - reference-integrity

terminology:
  source: inline             # ValueSets from IG package

security:
  auth: oauth2
  audit: atna
  tls: required

federation:
  enabled: false             # Single-tenant for MoH
```

### 8.2 Adding a New Jurisdiction

To add support for a new country's IG (e.g., Bangladesh):

1. **Drop the IG package** into `ig-packages/fhir.bd.facilityregistry-1.0.0/`
2. **Create a tenant YAML** at `tenants/bd-facility-registry.yaml` using the template above
3. **Map profiles** — list which StructureDefinitions apply to which resources
4. **Configure search params** — list the search parameters per resource
5. **Configure transactions** — enable/disable ITI-90/91/130 features
6. **Restart** — the config loader picks up the new tenant

**Zero code changes required.**

---

## 9. Deployment Topologies

### 9.1 Single-Tenant: Sri Lanka MoH Facility Registry

```
┌──────────────────────────────────────────────────┐
│  Sri Lanka MoH Network                           │
│                                                  │
│  ┌──────────┐     ┌─────────────────────────┐   │
│  │ DHIS2    │────▶│  Facility Registry      │   │
│  │ (Query   │     │  (Directory)            │   │
│  │  Client) │◀────│  tenant: lk-moh         │   │
│  └──────────┘     │  IG: fhir.lk.fr#0.1.0  │   │
│                   └────────────▲────────────┘   │
│  ┌──────────┐                  │                │
│  │ Hospital │  ITI-130 Feed    │                │
│  │ (Data    │──────────────────┘                │
│  │  Source) │                                    │
│  └──────────┘                                    │
│                                                  │
│  ┌──────────────────────────┐                    │
│  │ Provider Registry        │◀── Cross-registry │
│  │ (Separate system)        │    facade queries  │
│  └──────────────────────────┘                    │
└──────────────────────────────────────────────────┘
```

### 9.2 Multi-Tenant: OpenHIE Reference + Sri Lanka MoH

```
┌──────────────────────────────────────────────────────────┐
│  Shared Infrastructure                                    │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │  mCSD Platform (single deployment)                │   │
│  │                                                    │   │
│  │  /lk-moh/*  → tenant: lk-moh                     │   │
│  │               IG: fhir.lk.facilityregistry#0.1.0  │   │
│  │               Resources: Org, Location, HcService │   │
│  │                                                    │   │
│  │  /openhie/*  → tenant: openhie                    │   │
│  │               IG: ihe.iti.mcsd#4.0.1              │   │
│  │               Resources: All 9 resource types     │   │
│  │               Transactions: ITI-90, 91, 130       │   │
│  └──────────────────────────────────────────────────┘   │
│                         │                                 │
│  ┌──────────────────────▼──────────────────────────┐    │
│  │  PostgreSQL (shared, tenant-partitioned)          │    │
│  └──────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

### 9.3 Federated: National → Provincial (Sri Lanka)

```
┌──────────────────────────────────────────────────────────────┐
│  National Level                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  National Facility Registry                           │   │
│  │  Directory + Update Client                            │   │
│  │  Aggregates from all provinces                        │   │
│  └────────────▲──────────────────────▲──────────────────┘   │
│               │ ITI-91               │ ITI-91                │
│  ┌────────────┴───────┐  ┌──────────┴──────────┐           │
│  │  Western Province  │  │  Central Province   │  ...       │
│  │  Directory         │  │  Directory          │            │
│  │  + Data Sources    │  │  + Data Sources     │            │
│  └────────────────────┘  └─────────────────────┘            │
└──────────────────────────────────────────────────────────────┘
```

---

## 10. Testing Strategy

### 10.1 Test Layers

| Layer | What | How |
|-------|------|-----|
| **Unit** | Repository, Search Indexer, Validation Pipeline, Query Builder | In-memory repository, mock IG packages |
| **Profile Conformance** | Resources validated against StructureDefinitions | FHIR Validator (Java) or Inferno |
| **Transaction Conformance** | ITI-90, 91, 130 behavior | HTTP-level integration tests |
| **Multi-IG** | Same server validates LK resources against LK IG AND mCSD resources against mCSD IG | Parallel tenant tests |
| **Performance** | Search latency, write throughput | k6 or Gatling load tests |
| **Interoperability** | Test against HAPI FHIR reference server | Cross-server query tests |

### 10.2 Conformance Test Matrix

| Test | mCSD | LK FR | Both |
|------|------|-------|------|
| Organization search by name | ✓ | ✓ | ✓ |
| Organization search by type | ✓ | — | — |
| Organization search by address | — | ✓ | — |
| Location `near` search | ✓ | ✓ | ✓ |
| HealthcareService search by service-type | ✓ | ✓ | ✓ |
| HealthcareService search by specialty | — | ✓ | — |
| String modifier `:contains` | ✓ | — | — |
| String modifier `:exact` | ✓ | — | — |
| `_include` Organization:endpoint | ✓ | — | — |
| `_include` HealthcareService:organization | — | ✓ | — |
| `_include` HealthcareService:location | — | ✓ | — |
| `_revInclude` Location:organization | ✓ | — | — |
| Create Organization with identifier 1..* | — | ✓ | — |
| Create HealthcareService with providedBy 1..1 | — | ✓ | — |
| Create HealthcareService with location 0..1 max | — | ✓ | — |
| Instance vread | ✓ | ✓ | ✓ |
| History with `_since` | ✓ | — | — |
| Transaction Bundle (atomic) | ✓ | — | — |
| CapabilityStatement reflects active tenant config | ✓ | ✓ | ✓ |

---

## 12. OpenHIE Functional Requirements Traceability

This matrix maps every OpenHIE FR functional requirement to the specific design pattern, module, and implementation phase that addresses it.

| OpenHIE Req | Requirement Summary | Design Pattern | Module | Phase | mCSD Transaction |
|-------------|-------------------|----------------|--------|-------|-----------------|
| **FRF-1** | Create/evolve attributes & data dictionary | Profile Adapter (4.1) | `ig-packages/`, `core/validation-api/` | Phase 1, 3 | — |
| **FRF-2** | Multi-organizational hierarchies + geo-objects | Repository Abstraction (4.3) + Search Registry (4.4) | `core/repository-api/`, `transactions/location-distance/` | Phase 1, 5 | ITI-90 (`partof`, `near`) |
| **FRF-3** | WHO/USAID minimum facility attributes | Profile Adapter (4.1) + Validation (4.2) | `ig-packages/` (StructureDefinitions enforce attribute set) | Phase 3 | ITI-130 (enforce on create/update) |
| **FRF-4** | User/permission management | IOL Gateway (4.11) + Auth modules | `adapters/auth-iua/`, `adapters/auth-oauth2/` | Phase 6 | — (cross-cutting) |
| **FRF-5** | Role-based access | IOL Gateway (4.11) | `adapters/auth-*/` RBAC configuration | Phase 6 | — |
| **FRF-6** | RESTful standards-based APIs | All patterns | Core FHIR REST controller | Phase 1–4 | ITI-90, ITI-91, ITI-130 |
| **FRF-7** | Push/pull to other systems (CSV) | Event-Driven Sync (4.8) + Facade (4.9) | `facade/bulk-operations/` | Phase 7 | ITI-91 (pull), ITI-130 (push), `$export` |
| **FRF-8** | Bulk imports | Transaction Orchestrator (4.5) | `transactions/iti-130-feed/` (transaction Bundle) | Phase 4 | ITI-130 (transaction Bundle) |
| **FRF-9** | Search by attribute | Search Registry (4.4) | `core/search-engine/`, `transactions/iti-90-search/` | Phase 2 | ITI-90 |
| **FRF-10** | Facility on map | Location Distance Option | `transactions/location-distance/` (PostGIS) | Phase 5 | ITI-90 (`near` param) |
| **FRF-11** | Public access to relevant data | IOL Gateway (4.11) + Tenant Config (4.7) | Configurable public endpoints per resource | Phase 6 | ITI-90 (public subset) |
| **FRF-12** | Data curation (closures, status changes) | Transaction Orchestrator (4.5) + Event Sync (4.8) | `transactions/iti-130-feed/` | Phase 4 | ITI-130 (update status/active) |
| **FR-13** | Reports and analytics | Facade (4.9) | `facade/analytics/` + FHIR `$everything` | Phase 7 | ITI-90 (aggregate queries) |
| **FR-14** | Align with MFL | Event-Driven Sync (4.8) | FR *is* the MFL; sync observers publish to consumers | Phase 7 | ITI-91 (downstream consumers poll) |

### OpenHIE Workflow Traceability

| OpenHIE Workflow | mCSD Transaction | Our Actor Role | Key Module |
|-----------------|-----------------|----------------|------------|
| **FRWF-1**: Query HW and/or Facility Records | ITI-90 (via ILR) + ITI-91 (ILR polls FR) | FR = Directory (ITI-91 responder) | `transactions/iti-91-history/` |
| **Query Care Services Records** | ITI-90 (PoS→IOL→ILR) + ITI-91 (ILR→FR) | FR = Directory (ITI-90 + ITI-91 responder) | `transactions/iti-90-search/`, `transactions/iti-91-history/` |
| **Search Care Services** | ITI-90 (PoS→FR direct) | FR = Directory (ITI-90 responder) | `transactions/iti-90-search/` |
| **Request Care Services Updates** | ITI-91 (ILR→FR) | FR = Directory (ITI-91 responder) | `transactions/iti-91-history/` |

### OpenHIE IOL Integration Traceability

| IOL Req | Requirement | How FR Supports It |
|---------|-------------|-------------------|
| IOLWF-1 | IHE ATNA (Audit Trail + Node Authentication) | FR logs ATNA audit events; accepts mTLS from IOL in OpenHIE mode |
| IOLF-1 | Central point of access | FR registers as OpenHIM mediator; IOL routes to FR |
| IOLF-2 | Routing to correct service provider | FR declares its routes on mediator registration |
| IOLF-3 | Central logging | FR provides transaction metadata; IOL handles logging |
| IOLF-6 | Orchestration (multi-registry) | FR responds to individual queries; IOL/ILR orchestrates FR+HWR merge |
| IOLF-13 | Auth and encryption | FR trusts IOL headers in OpenHIE mode; handles its own auth in standalone |

---

## References

- OpenHIE Architecture Specification: https://guides.ohie.org/arch-spec/
- OpenHIE FR Component Spec: https://guides.ohie.org/arch-spec/openhie-component-specifications-1/openhie-facility-registry-fr
- OpenHIE Care Services Discovery: https://guides.ohie.org/arch-spec/introduction/care-services-discovery
- OpenHIE IOL Spec: https://guides.ohie.org/arch-spec/openhie-component-specifications-1/openhie-interoperability-layer-iol
- IHE mCSD IG: https://build.fhir.org/ig/IHE/ITI.mCSD/
- Sri Lanka FR IG: https://ig.hiu.lk/fhir/facilityregistry/
- FHIR R4: http://hl7.org/fhir/R4/
- IHE IUA Profile: https://profiles.ihe.net/ITI/IUA/
- IHE ATNA Profile: https://profiles.ihe.net/ITI/TF/Volume1/ch-9.html
- IHE SVCM Profile: https://profiles.ihe.net/ITI/SVCM/
- OpenHIM (Reference IOL): https://openhim.org/
- WHO MFL Resource Package: https://www.who.int/publications/i/item/9789241516495
