import ballerina/test;

// ─────────────────────────────────────────────────────────────────────────────
// Tenant Config Tests (Step 7)
//
// Tests getTenantId(), isTransactionEnabled(), getIgConfig(), getResourceConfig(),
// and getProfileUrl() against the default igConfig values.
//
// Note: configurable variables are immutable after module init, so "override"
// scenarios (e.g. iti130 = false) require a separate test run with a custom
// Config.toml. The default config has all transactions enabled (iti90/91/130 = true).
// ─────────────────────────────────────────────────────────────────────────────

// ─── getTenantId ──────────────────────────────────────────────────────────────

@test:Config {}
function testGetTenantIdReturnsMcsd() {
    string tenantId = getTenantId();
    test:assertEquals(tenantId, "mcsd", msg = "Default tenant ID should be 'mcsd'");
}

@test:Config {}
function testGetTenantIdMatchesIgConfigId() {
    test:assertEquals(getTenantId(), getIgConfig().id,
        msg = "getTenantId() should match getIgConfig().id");
}

// ─── isTransactionEnabled — default config (all true) ─────────────────────────

@test:Config {}
function testIsTransactionEnabledITI90DefaultTrue() {
    test:assertTrue(isTransactionEnabled("ITI-90"),
        msg = "ITI-90 should be enabled by default");
}

@test:Config {}
function testIsTransactionEnabledITI91DefaultTrue() {
    test:assertTrue(isTransactionEnabled("ITI-91"),
        msg = "ITI-91 should be enabled by default");
}

@test:Config {}
function testIsTransactionEnabledITI130DefaultTrue() {
    test:assertTrue(isTransactionEnabled("ITI-130"),
        msg = "ITI-130 should be enabled by default");
}

@test:Config {}
function testIsTransactionEnabledUnknownReturnsFalse() {
    test:assertFalse(isTransactionEnabled("ITI-999"),
        msg = "Unknown transaction type should return false");
}

@test:Config {}
function testIsTransactionEnabledEmptyStringReturnsFalse() {
    test:assertFalse(isTransactionEnabled(""),
        msg = "Empty string transaction type should return false");
}

// ─── getIgConfig ──────────────────────────────────────────────────────────────

@test:Config {}
function testGetIgConfigReturnsExpectedId() {
    IGConfig config = getIgConfig();
    test:assertEquals(config.id, "mcsd", msg = "Default IG config id should be 'mcsd'");
}

@test:Config {}
function testGetIgConfigContainsFiveResources() {
    IGConfig config = getIgConfig();
    test:assertEquals(config.resources.length(), 5,
        msg = "Default IG config should have 5 resources");
}

@test:Config {}
function testGetIgConfigTransactionsAllEnabled() {
    IGConfig config = getIgConfig();
    test:assertTrue(config.transactions.iti90, msg = "iti90 should be enabled");
    test:assertTrue(config.transactions.iti91, msg = "iti91 should be enabled");
    test:assertTrue(config.transactions.iti130, msg = "iti130 should be enabled");
}

// ─── getResourceConfig ────────────────────────────────────────────────────────

@test:Config {}
function testGetResourceConfigOrganizationNotNull() {
    IGResourceConfig? rc = getResourceConfig("Organization");
    test:assertTrue(rc is IGResourceConfig,
        msg = "Organization should have a resource config");
}

@test:Config {}
function testGetResourceConfigLocationNotNull() {
    IGResourceConfig? rc = getResourceConfig("Location");
    test:assertTrue(rc is IGResourceConfig,
        msg = "Location should have a resource config");
}

@test:Config {}
function testGetResourceConfigUnknownReturnsNull() {
    IGResourceConfig? rc = getResourceConfig("Practitioner");
    test:assertTrue(rc is (),
        msg = "Unconfigured resource type should return ()");
}

@test:Config {}
function testGetResourceConfigOrganizationSupportsHistory() {
    IGResourceConfig? rc = getResourceConfig("Organization");
    if rc is IGResourceConfig {
        test:assertTrue(rc.supportsHistory,
            msg = "Organization should support history");
    }
}

@test:Config {}
function testGetResourceConfigEndpointDoesNotSupportHistory() {
    IGResourceConfig? rc = getResourceConfig("Endpoint");
    if rc is IGResourceConfig {
        test:assertFalse(rc.supportsHistory,
            msg = "Endpoint should not support history");
    }
}

// ─── getProfileUrl ────────────────────────────────────────────────────────────

@test:Config {}
function testGetProfileUrlOrganizationBaseProfile() {
    string url = getProfileUrl("Organization", "");
    test:assertTrue(url.includes("mCSD"),
        msg = "Organization base profile URL should reference mCSD");
    test:assertTrue(url.includes("Organization"),
        msg = "Organization base profile URL should contain 'Organization'");
}

@test:Config {}
function testGetProfileUrlOrganizationFacilityProfile() {
    string url = getProfileUrl("Organization", "facility");
    test:assertTrue(url.includes("Facility"),
        msg = "Organization facility profile URL should reference 'Facility'");
}

@test:Config {}
function testGetProfileUrlOrganizationJurisdictionProfile() {
    string url = getProfileUrl("Organization", "jurisdiction");
    test:assertTrue(url.includes("Jurisdiction"),
        msg = "Organization jurisdiction profile URL should reference 'Jurisdiction'");
}

@test:Config {}
function testGetProfileUrlHealthcareServiceNoFacilityVariant() {
    string urlBase = getProfileUrl("HealthcareService", "");
    string urlFacility = getProfileUrl("HealthcareService", "facility");
    // HealthcareService has no facilityProfile — should fall back to base profile
    test:assertEquals(urlBase, urlFacility,
        msg = "HealthcareService facility profile should fall back to base profile");
}

@test:Config {}
function testGetProfileUrlUnknownResourceFallsBackToCanonical() {
    string url = getProfileUrl("UnknownResource", "");
    test:assertTrue(url.includes("UnknownResource"),
        msg = "Unknown resource should produce a fallback URL containing the resource type name");
}
