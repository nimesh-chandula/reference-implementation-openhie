import ballerina/test;
import wso2/FRCoreService.fhir_utils;
import wso2/FRCoreService.r4_api_config;

// ─────────────────────────────────────────────────────────────────────────────
// Step 8 Validation Tests — CapabilityStatement Builder
//
// Tests that buildCapabilityStatement() is fully driven by the passed IGConfig
// and the Search Parameter Registry — no hardcoded values.
// ─────────────────────────────────────────────────────────────────────────────

// Helper: minimal IGConfig for testing
isolated function minimalConfig(string id, fhir_utils:IGResourceConfig[] resources, fhir_utils:IGTransactionConfig txConfig)
        returns fhir_utils:IGConfig {
    return {
        id: id,
        name: "Test IG " + id,
        canonical: "http://example.org/ig/" + id,
        fhirVersion: "4.0.1",
        serverName: "TestCS-" + id,
        serverVersion: "1.0.0",
        publisher: "Test",
        instantiates: [],
        transactions: txConfig,
        resources: resources
    };
}

// Helper: navigate to rest[0].resource from a CapabilityStatement json
isolated function getRestResources(json cs) returns json[]|error {
    json|error restField = cs.rest;
    if restField is error {
        return restField;
    }
    json[] restArr = check restField.ensureType();
    if restArr.length() == 0 {
        return error("rest array is empty");
    }
    map<json> rest0 = check restArr[0].ensureType();
    json resourcesField = rest0["resource"] ?: [];
    return check resourcesField.ensureType();
}

// Test: resource list in CapabilityStatement is driven by igConfig.resources
// Only Organization is in the config — only it should appear in rest[0].resource.
@test:Config {}
function testCapabilityStatementResourcesDrivenByConfig() {
    fhir_utils:IGConfig cfg = minimalConfig(
        "step8-res",
        [
            {
                resourceType: "Organization",
                profile: "http://example.org/ig/step8-res/StructureDefinition/Organization",
                interactions: ["read", "search-type", "create"],
                supportsHistory: true
            }
        ],
        {iti90: true, iti91: true, iti130: true}
    );

    json cs = buildCapabilityStatement("http://localhost:9098", cfg);

    json[]|error resArr = getRestResources(cs);
    test:assertTrue(resArr is json[], msg = "Expected resource array in CapabilityStatement rest[0]");
    if resArr is json[] {
        test:assertEquals(resArr.length(), 1,
            msg = "Expected exactly 1 resource — only Organization is configured");
        json|error rType = resArr[0].'type;
        test:assertEquals(rType, "Organization",
            msg = "Expected resource type to be Organization");
    }
}

// Test: search params in CapabilityStatement come from r4_api_config, not hardcoded registry
// Verifies that the param count and names match organizationApiConfig.searchParameters
@test:Config {}
function testCapabilityStatementSearchParamsFromR4ApiConfig() {
    fhir_utils:IGConfig cfg = minimalConfig(
        "step8-sp",
        [
            {
                resourceType: "Organization",
                profile: "http://example.org/ig/step8-sp/StructureDefinition/Organization",
                interactions: ["read", "search-type"],
                supportsHistory: false
            }
        ],
        {iti90: true, iti91: false, iti130: false}
    );

    json cs = buildCapabilityStatement("http://localhost:9098", cfg);

    // Count active params from the source of truth
    int expectedCount = 0;
    foreach var sp in r4_api_config:organizationApiConfig.searchParameters {
        if sp.active {
            expectedCount += 1;
        }
    }

    // Verify CapabilityStatement has the same count and includes "_id"
    json[]|error resArr = getRestResources(cs);
    if resArr is json[] && resArr.length() > 0 {
        json|error searchParams = resArr[0].searchParam;
        if searchParams is json {
            json[]|error spArr = searchParams.ensureType();
            if spArr is json[] {
                test:assertEquals(spArr.length(), expectedCount,
                    msg = "searchParam count should match active params in organizationApiConfig");
                boolean hasId = false;
                foreach json sp in spArr {
                    json|error spName = sp.name;
                    if spName is json && spName.toString() == "_id" {
                        hasId = true;
                    }
                }
                test:assertTrue(hasId, msg = "'_id' param should appear in CapabilityStatement");
            }
        }
    }
}

// Test: description contains only enabled transactions (not disabled ones)
@test:Config {}
function testCapabilityStatementDescriptionReflectsTransactions() {
    // Only ITI-90 enabled
    fhir_utils:IGConfig cfg = minimalConfig(
        "step8-tx",
        [],
        {iti90: true, iti91: false, iti130: false}
    );

    json cs = buildCapabilityStatement("http://localhost:9098", cfg);

    json|error desc = cs.description;
    test:assertTrue(desc is json, msg = "Expected description field");
    if desc is json {
        string descStr = desc.toString();
        test:assertTrue(descStr.includes("ITI-90"), msg = "ITI-90 should appear in description (enabled)");
        test:assertFalse(descStr.includes("ITI-91"), msg = "ITI-91 should NOT appear in description (disabled)");
        test:assertFalse(descStr.includes("ITI-130"), msg = "ITI-130 should NOT appear in description (disabled)");
    }
}

// Test: all three transactions enabled — all appear in description
@test:Config {}
function testCapabilityStatementDescriptionAllTransactionsEnabled() {
    fhir_utils:IGConfig cfg = minimalConfig(
        "step8-tx-all",
        [],
        {iti90: true, iti91: true, iti130: true}
    );

    json cs = buildCapabilityStatement("http://localhost:9098", cfg);

    json|error desc = cs.description;
    if desc is json {
        string descStr = desc.toString();
        test:assertTrue(descStr.includes("ITI-90"), msg = "ITI-90 should appear (enabled)");
        test:assertTrue(descStr.includes("ITI-91"), msg = "ITI-91 should appear (enabled)");
        test:assertTrue(descStr.includes("ITI-130"), msg = "ITI-130 should appear (enabled)");
    }
}

// Test: profile URL in CapabilityStatement matches igConfig value (routed via profileAdapter)
@test:Config {}
function testCapabilityStatementProfileFromAdapter() {
    string expectedProfile = "http://example.org/ig/step8-prof/StructureDefinition/Organization";
    fhir_utils:IGConfig cfg = minimalConfig(
        "step8-prof",
        [
            {
                resourceType: "Organization",
                profile: expectedProfile,
                interactions: ["read"],
                supportsHistory: false
            }
        ],
        {iti90: true, iti91: false, iti130: false}
    );

    json cs = buildCapabilityStatement("http://localhost:9098", cfg);

    json[]|error resArr = getRestResources(cs);
    if resArr is json[] && resArr.length() > 0 {
        json|error profile = resArr[0].profile;
        test:assertEquals(profile, expectedProfile,
            msg = "Profile URL should match igConfig value (via profileAdapter)");
    }
}
