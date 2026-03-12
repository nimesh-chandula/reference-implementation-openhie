-- FR Core H2 Schema
-- IHE mCSD v4.0.0 Facility Registry
-- H2 Embedded Database (Development)

-- ─────────────────────────────────────────────────────────────
-- ORGANIZATION
-- Stores FHIR Organization resources for Facilities and Jurisdictions
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS organization (
    id              VARCHAR(36) DEFAULT RANDOM_UUID() PRIMARY KEY,
    version_id      INTEGER NOT NULL DEFAULT 1,
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    name            VARCHAR(500) NOT NULL,
    type_code       VARCHAR(100) NOT NULL,
    part_of_id      VARCHAR(36) REFERENCES organization(id),
    fhir_resource   CLOB NOT NULL,
    last_updated    DATETIME NOT NULL DEFAULT NOW(),
    created_at      DATETIME NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE
);

-- ─────────────────────────────────────────────────────────────
-- LOCATION
-- Stores FHIR Location resources for physical facilities and jurisdictions
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS location (
    id                  VARCHAR(36) DEFAULT RANDOM_UUID() PRIMARY KEY,
    version_id          INTEGER NOT NULL DEFAULT 1,
    status              VARCHAR(20) NOT NULL DEFAULT 'active',
    name                VARCHAR(500) NOT NULL,
    type_code           VARCHAR(100) NOT NULL,
    physical_type       VARCHAR(50),
    managing_org_id     VARCHAR(36) REFERENCES organization(id),
    part_of_id          VARCHAR(36) REFERENCES location(id),
    latitude            DECIMAL(10,7),
    longitude           DECIMAL(10,7),
    address_text        VARCHAR(1000),
    address_line        VARCHAR(500),
    address_city        VARCHAR(200),
    address_district    VARCHAR(200),
    address_state       VARCHAR(200),
    address_country     VARCHAR(10),
    boundary_geojson    CLOB,
    fhir_resource       CLOB NOT NULL,
    last_updated        DATETIME NOT NULL DEFAULT NOW(),
    created_at          DATETIME NOT NULL DEFAULT NOW(),
    is_deleted          BOOLEAN NOT NULL DEFAULT FALSE
);

-- ─────────────────────────────────────────────────────────────
-- HEALTHCARE_SERVICE
-- Stores FHIR HealthcareService resources
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS healthcare_service (
    id              VARCHAR(36) DEFAULT RANDOM_UUID() PRIMARY KEY,
    version_id      INTEGER NOT NULL DEFAULT 1,
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    name            VARCHAR(500) NOT NULL,
    category_code   VARCHAR(100),
    type_code       VARCHAR(100),
    provided_by_id  VARCHAR(36) REFERENCES organization(id),
    fhir_resource   CLOB NOT NULL,
    last_updated    DATETIME NOT NULL DEFAULT NOW(),
    created_at      DATETIME NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE
);

-- ─────────────────────────────────────────────────────────────
-- IDENTIFIER
-- Cross-resource identifier lookup (MFL codes, DHIS2 IDs, HFR codes, etc.)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS identifier (
    id            BIGINT AUTO_INCREMENT PRIMARY KEY,
    resource_type VARCHAR(50) NOT NULL,
    resource_id   VARCHAR(36) NOT NULL,
    "system"      VARCHAR(500),
    "value"       VARCHAR(500) NOT NULL,
    "use"         VARCHAR(20)
);

-- ─────────────────────────────────────────────────────────────
-- SERVICE_LOCATION (many-to-many join)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS service_location (
    service_id  VARCHAR(36) NOT NULL REFERENCES healthcare_service(id) ON DELETE CASCADE,
    location_id VARCHAR(36) NOT NULL REFERENCES location(id) ON DELETE CASCADE,
    PRIMARY KEY (service_id, location_id)
);

-- ─────────────────────────────────────────────────────────────
-- ENDPOINT
-- Stores FHIR Endpoint resources for electronic service connectivity
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS endpoint (
    id                VARCHAR(36) DEFAULT RANDOM_UUID() PRIMARY KEY,
    status            VARCHAR(20) NOT NULL,
    connection_type   VARCHAR(100) NOT NULL,
    managing_org_id   VARCHAR(36) REFERENCES organization(id),
    address_url       VARCHAR(1000) NOT NULL,
    fhir_resource     CLOB NOT NULL,
    last_updated      DATETIME NOT NULL DEFAULT NOW(),
    is_deleted        BOOLEAN NOT NULL DEFAULT FALSE
);

-- ─────────────────────────────────────────────────────────────
-- ORG_AFFILIATION
-- Stores FHIR OrganizationAffiliation resources for non-hierarchical relationships
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS org_affiliation (
    id                      VARCHAR(36) DEFAULT RANDOM_UUID() PRIMARY KEY,
    active                  BOOLEAN NOT NULL DEFAULT TRUE,
    primary_org_id          VARCHAR(36) NOT NULL REFERENCES organization(id),
    participating_org_id    VARCHAR(36) NOT NULL REFERENCES organization(id),
    role_code               VARCHAR(100),
    fhir_resource           CLOB NOT NULL,
    last_updated            DATETIME NOT NULL DEFAULT NOW(),
    is_deleted              BOOLEAN NOT NULL DEFAULT FALSE
);

-- ─────────────────────────────────────────────────────────────
-- RESOURCE_HISTORY (append-only)
-- Every CREATE, UPDATE, DELETE appends a row — supports ITI-91
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS resource_history (
    id            BIGINT AUTO_INCREMENT PRIMARY KEY,
    resource_type VARCHAR(50) NOT NULL,
    resource_id   VARCHAR(36) NOT NULL,
    version_id    INTEGER NOT NULL,
    action        VARCHAR(10) NOT NULL,
    fhir_resource CLOB,
    timestamp     DATETIME NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────
-- INDEXES
-- ─────────────────────────────────────────────────────────────

-- Organization
CREATE INDEX IF NOT EXISTS idx_org_name       ON organization (name);
CREATE INDEX IF NOT EXISTS idx_org_type       ON organization (type_code);
CREATE INDEX IF NOT EXISTS idx_org_partof     ON organization (part_of_id);
CREATE INDEX IF NOT EXISTS idx_org_updated    ON organization (last_updated);
CREATE INDEX IF NOT EXISTS idx_org_active     ON organization (active);

-- Location
CREATE INDEX IF NOT EXISTS idx_loc_name       ON location (name);
CREATE INDEX IF NOT EXISTS idx_loc_type       ON location (type_code);
CREATE INDEX IF NOT EXISTS idx_loc_status     ON location (status);
CREATE INDEX IF NOT EXISTS idx_loc_org        ON location (managing_org_id);
CREATE INDEX IF NOT EXISTS idx_loc_partof     ON location (part_of_id);
CREATE INDEX IF NOT EXISTS idx_loc_updated    ON location (last_updated);
CREATE INDEX IF NOT EXISTS idx_loc_lat        ON location (latitude);
CREATE INDEX IF NOT EXISTS idx_loc_lon        ON location (longitude);

-- HealthcareService
CREATE INDEX IF NOT EXISTS idx_svc_name       ON healthcare_service (name);
CREATE INDEX IF NOT EXISTS idx_svc_type       ON healthcare_service (type_code);
CREATE INDEX IF NOT EXISTS idx_svc_updated    ON healthcare_service (last_updated);
CREATE INDEX IF NOT EXISTS idx_svc_provided   ON healthcare_service (provided_by_id);

-- Identifier (fast external ID lookup)
CREATE INDEX IF NOT EXISTS idx_identifier_val ON identifier (resource_type, "value");
CREATE INDEX IF NOT EXISTS idx_identifier_res ON identifier (resource_id);

-- Endpoint
CREATE INDEX IF NOT EXISTS idx_ep_org         ON endpoint (managing_org_id);
CREATE INDEX IF NOT EXISTS idx_ep_status      ON endpoint (status);

-- OrgAffiliation
CREATE INDEX IF NOT EXISTS idx_aff_primary        ON org_affiliation (primary_org_id);
CREATE INDEX IF NOT EXISTS idx_aff_participating  ON org_affiliation (participating_org_id);

-- ResourceHistory (ITI-91 _since queries)
CREATE INDEX IF NOT EXISTS idx_history_lookup ON resource_history (resource_type, resource_id, version_id);
CREATE INDEX IF NOT EXISTS idx_history_since  ON resource_history (resource_type, timestamp);
