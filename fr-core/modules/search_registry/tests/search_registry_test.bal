import ballerina/test;

// ─────────────────────────────────────────────────────────────────────────────
// Search Parameter Registry Tests
// (Symbols are directly accessible — no self-import needed for module tests)
// ─────────────────────────────────────────────────────────────────────────────

@test:Config {}
function testGetSearchParamsOrganizationReturnsAtLeastFive() {
    SearchParamDef[] params = getSearchParams("Organization");
    test:assertTrue(params.length() >= 5,
        msg = "Organization should have at least 5 search params, got " + params.length().toString());
}

@test:Config {}
function testGetSearchParamsLocationReturnsAtLeastFive() {
    SearchParamDef[] params = getSearchParams("Location");
    test:assertTrue(params.length() >= 5,
        msg = "Location should have at least 5 search params, got " + params.length().toString());
}

@test:Config {}
function testGetSearchParamsUnknownResourceReturnsEmpty() {
    SearchParamDef[] params = getSearchParams("UnknownResource");
    test:assertEquals(params.length(), 0,
        msg = "Unknown resource type should return empty array");
}

@test:Config {}
function testBuildDefaultRegistryContainsAllFiveResourceTypes() {
    SearchParamRegistry reg = buildDefaultRegistry();
    string[] expected = ["Organization", "Location", "HealthcareService", "Endpoint", "OrganizationAffiliation"];
    foreach string resourceType in expected {
        test:assertTrue(reg.byResourceType.hasKey(resourceType),
            msg = "Default registry missing resource type: " + resourceType);
    }
}

@test:Config {}
function testBuildDefaultRegistryOrganizationHasNameParam() {
    SearchParamRegistry reg = buildDefaultRegistry();
    SearchParamDef[]? orgParams = reg.byResourceType["Organization"];
    test:assertTrue(orgParams is SearchParamDef[],
        msg = "Organization params should not be null");
    if orgParams is SearchParamDef[] {
        boolean hasName = false;
        foreach SearchParamDef p in orgParams {
            if p.name == "name" {
                hasName = true;
            }
        }
        test:assertTrue(hasName, msg = "Organization search params should include 'name'");
    }
}

@test:Config {}
function testRegisterSearchParamAddsNewParam() {
    SearchParamDef newParam = {
        name: "custom-param",
        paramType: "token",
        expression: "Organization.extension.value",
        supportedIGs: ["test-ig"]
    };
    registerSearchParam("Organization", newParam);
    SearchParamDef[] params = getSearchParams("Organization");
    boolean found = false;
    foreach SearchParamDef p in params {
        if p.name == "custom-param" {
            found = true;
        }
    }
    test:assertTrue(found, msg = "Dynamically registered param should be present in registry");
}

@test:Config {}
function testRegisterSearchParamNewResourceType() {
    SearchParamDef param = {
        name: "patient",
        paramType: "reference",
        expression: "Practitioner.patient",
        supportedIGs: []
    };
    registerSearchParam("Practitioner", param);
    SearchParamDef[] params = getSearchParams("Practitioner");
    test:assertEquals(params.length(), 1,
        msg = "New resource type should have exactly 1 registered param");
    test:assertEquals(params[0].name, "patient",
        msg = "Registered param name should match");
}
