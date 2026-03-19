import ballerina/test;

// ─────────────────────────────────────────────────────────────────────────────
// Search Parameter Metadata Registry Tests
// (Symbols directly accessible — module-level test file, no self-import)
// ─────────────────────────────────────────────────────────────────────────────

// Test: getParamMeta returns correct type for a token param
@test:Config {}
function testGetParamMetaTokenParam() {
    SearchParamMeta meta = getParamMeta("_id");
    test:assertEquals(meta.paramType, "token", msg = "_id should be a token param");
}

// Test: getParamMeta returns correct type for a string param
@test:Config {}
function testGetParamMetaStringParam() {
    SearchParamMeta meta = getParamMeta("name");
    test:assertEquals(meta.paramType, "string", msg = "name should be a string param");
}

// Test: getParamMeta returns correct type for a special param
@test:Config {}
function testGetParamMetaSpecialParam() {
    SearchParamMeta meta = getParamMeta("near");
    test:assertEquals(meta.paramType, "special", msg = "near should be a special param");
}

// Test: getParamMeta returns correct type for a reference param
@test:Config {}
function testGetParamMetaReferenceParam() {
    SearchParamMeta meta = getParamMeta("partof");
    test:assertEquals(meta.paramType, "reference", msg = "partof should be a reference param");
}

// Test: getParamMeta returns correct type for a date param
@test:Config {}
function testGetParamMetaDateParam() {
    SearchParamMeta meta = getParamMeta("_lastUpdated");
    test:assertEquals(meta.paramType, "date", msg = "_lastUpdated should be a date param");
}

// Test: buildDefaultMetadata contains at least 10 entries
@test:Config {}
function testBuildDefaultMetadataHasSufficientEntries() {
    map<SearchParamMeta> meta = buildDefaultMetadata();
    test:assertTrue(meta.length() >= 10,
        msg = "Default metadata should have at least 10 entries, got " + meta.length().toString());
}

// Test: buildDefaultMetadata covers all common cross-resource params
@test:Config {}
function testBuildDefaultMetadataCoversCommonParams() {
    map<SearchParamMeta> meta = buildDefaultMetadata();
    string[] commonParams = ["_id", "active", "identifier", "name", "status", "_lastUpdated"];
    foreach string p in commonParams {
        test:assertTrue(meta.hasKey(p),
            msg = "Default metadata missing common param: " + p);
    }
}

// Test: getParamMeta falls back gracefully for unknown param names
// — forward-compatible when new params are added to r4_api_config without updating registry
@test:Config {}
function testGetParamMetaFallbackForUnknownParam() {
    SearchParamMeta meta = getParamMeta("unknown-custom-param");
    test:assertEquals(meta.paramType, "string",
        msg = "Unknown param should fall back to type 'string'");
    test:assertEquals(meta.expression, "unknown-custom-param",
        msg = "Unknown param expression should fall back to the param name itself");
}
