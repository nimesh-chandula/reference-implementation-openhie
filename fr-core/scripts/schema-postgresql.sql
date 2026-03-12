-- FR Core PostgreSQL Schema
-- IHE mCSD v4.0.0 Facility Registry
-- Enable required extensions (run once by DBA before first deployment):
--   CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
--   CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ─────────────────────────────────────────────────────────────
-- ORGANIZATION
-- Stores FHIR Organization resources for Facilities and Jurisdictions
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS organization (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    version_id      INTEGER NOT NULL DEFAULT 1,
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    name            VARCHAR(500) NOT NULL,
    type_code       VARCHAR(100) NOT NULL,          -- 'facility' | 'jurisdiction'
    part_of_id      UUID REFERENCES organization(id),
    fhir_resource   JSONB NOT NULL,
    last_updated    TIMESTAMP NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE
);

-- ─────────────────────────────────────────────────────────────
-- LOCATION
-- Stores FHIR Location resources for physical facilities and jurisdictions
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS location (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    version_id          INTEGER NOT NULL DEFAULT 1,
    status              VARCHAR(20) NOT NULL DEFAULT 'active',
    name                VARCHAR(500) NOT NULL,
    type_code           VARCHAR(100) NOT NULL,      -- 'facility' | 'jurisdiction'
    physical_type       VARCHAR(50),
    managing_org_id     UUID REFERENCES organization(id),
    part_of_id          UUID REFERENCES location(id),
    latitude            DECIMAL(10,7),
    longitude           DECIMAL(10,7),
    address_text        VARCHAR(1000),
    address_line        VARCHAR(500),
    address_city        VARCHAR(200),
    address_district    VARCHAR(200),
    address_state       VARCHAR(200),
    address_country     VARCHAR(10),
    boundary_geojson    JSONB,
    fhir_resource       JSONB NOT NULL,
    last_updated        TIMESTAMP NOT NULL DEFAULT NOW(),
    created_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    is_deleted          BOOLEAN NOT NULL DEFAULT FALSE
);

-- ─────────────────────────────────────────────────────────────
-- HEALTHCARE_SERVICE
-- Stores FHIR HealthcareService resources
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS healthcare_service (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    version_id      INTEGER NOT NULL DEFAULT 1,
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    name            VARCHAR(500) NOT NULL,
    category_code   VARCHAR(100),
    type_code       VARCHAR(100),
    provided_by_id  UUID REFERENCES organization(id),
    fhir_resource   JSONB NOT NULL,
    last_updated    TIMESTAMP NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE
);

-- ─────────────────────────────────────────────────────────────
-- IDENTIFIER
-- Cross-resource identifier lookup (MFL codes, DHIS2 IDs, HFR codes, etc.)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS identifier (
    id            BIGSERIAL PRIMARY KEY,
    resource_type VARCHAR(50) NOT NULL,     -- 'Organization' | 'Location' | 'HealthcareService'
    resource_id   UUID NOT NULL,
    system        VARCHAR(500),             -- Identifier namespace URI
    value         VARCHAR(500) NOT NULL,
    use           VARCHAR(20)              -- 'usual' | 'official' | 'temp' | 'secondary' | 'old'
);

-- ─────────────────────────────────────────────────────────────
-- SERVICE_LOCATION (many-to-many join)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS service_location (
    service_id  UUID NOT NULL REFERENCES healthcare_service(id) ON DELETE CASCADE,
    location_id UUID NOT NULL REFERENCES location(id) ON DELETE CASCADE,
    PRIMARY KEY (service_id, location_id)
);

-- ─────────────────────────────────────────────────────────────
-- ENDPOINT
-- Stores FHIR Endpoint resources for electronic service connectivity
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS endpoint (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    status            VARCHAR(20) NOT NULL,           -- 'active' | 'suspended' | 'error' | 'off' | 'test'
    connection_type   VARCHAR(100) NOT NULL,
    managing_org_id   UUID REFERENCES organization(id),
    address_url       VARCHAR(1000) NOT NULL,
    fhir_resource     JSONB NOT NULL,
    last_updated      TIMESTAMP NOT NULL DEFAULT NOW(),
    is_deleted        BOOLEAN NOT NULL DEFAULT FALSE
);

-- ─────────────────────────────────────────────────────────────
-- ORG_AFFILIATION
-- Stores FHIR OrganizationAffiliation resources for non-hierarchical relationships
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS org_affiliation (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    active                  BOOLEAN NOT NULL DEFAULT TRUE,
    primary_org_id          UUID NOT NULL REFERENCES organization(id),
    participating_org_id    UUID NOT NULL REFERENCES organization(id),
    role_code               VARCHAR(100),
    fhir_resource           JSONB NOT NULL,
    last_updated            TIMESTAMP NOT NULL DEFAULT NOW(),
    is_deleted              BOOLEAN NOT NULL DEFAULT FALSE
);

-- ─────────────────────────────────────────────────────────────
-- RESOURCE_HISTORY (append-only)
-- Every CREATE, UPDATE, DELETE appends a row — supports ITI-91
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS resource_history (
    id            BIGSERIAL PRIMARY KEY,
    resource_type VARCHAR(50) NOT NULL,
    resource_id   UUID NOT NULL,
    version_id    INTEGER NOT NULL,
    action        VARCHAR(10) NOT NULL,         -- 'CREATE' | 'UPDATE' | 'DELETE'
    fhir_resource JSONB,                        -- NULL for DELETE entries
    timestamp     TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────
-- INDEXES
-- ─────────────────────────────────────────────────────────────

-- Organization
CREATE INDEX IF NOT EXISTS idx_org_name       ON organization USING GIN (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_org_type       ON organization (type_code) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_org_partof     ON organization (part_of_id) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_org_updated    ON organization (last_updated) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_org_active     ON organization (active) WHERE is_deleted = FALSE;

-- Location
CREATE INDEX IF NOT EXISTS idx_loc_name       ON location USING GIN (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_loc_type       ON location (type_code) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_loc_status     ON location (status) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_loc_org        ON location (managing_org_id) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_loc_partof     ON location (part_of_id) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_loc_updated    ON location (last_updated) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_loc_lat        ON location (latitude) WHERE is_deleted = FALSE AND latitude IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_loc_lon        ON location (longitude) WHERE is_deleted = FALSE AND longitude IS NOT NULL;

-- HealthcareService
CREATE INDEX IF NOT EXISTS idx_svc_name       ON healthcare_service USING GIN (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_svc_type       ON healthcare_service (type_code) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_svc_updated    ON healthcare_service (last_updated) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_svc_provided   ON healthcare_service (provided_by_id) WHERE is_deleted = FALSE;

-- Identifier (fast external ID lookup)
CREATE UNIQUE INDEX IF NOT EXISTS idx_identifier_lookup
    ON identifier (resource_type, system, value) WHERE system IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_identifier_val ON identifier (resource_type, value);
CREATE INDEX IF NOT EXISTS idx_identifier_res ON identifier (resource_id);

-- Endpoint
CREATE INDEX IF NOT EXISTS idx_ep_org         ON endpoint (managing_org_id) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_ep_status      ON endpoint (status) WHERE is_deleted = FALSE;

-- OrgAffiliation
CREATE INDEX IF NOT EXISTS idx_aff_primary        ON org_affiliation (primary_org_id) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_aff_participating  ON org_affiliation (participating_org_id) WHERE is_deleted = FALSE;

-- ResourceHistory (ITI-91 _since queries)
CREATE INDEX IF NOT EXISTS idx_history_lookup ON resource_history (resource_type, resource_id, version_id);
CREATE INDEX IF NOT EXISTS idx_history_since  ON resource_history (resource_type, timestamp);
