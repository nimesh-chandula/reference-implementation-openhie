import ballerina/test;
import ballerina/http;
import wso2/FRCoreService.db;

// ─────────────────────────────────────────────────────────────────────────────
// Test Setup — initialise H2 schema before running DB-backed tests
// ─────────────────────────────────────────────────────────────────────────────

@test:BeforeSuite
function beforeSuite() returns error? {
    check db:initDatabase();
}

// ─────────────────────────────────────────────────────────────────────────────
// Factory — getHandler() happy paths
// ─────────────────────────────────────────────────────────────────────────────

@test:Config {}
function testGetHandlerITI90() returns error? {
    TransactionHandler h = check getHandler("ITI-90", "Organization");
    test:assertNotEquals(h, (), msg = "ITI-90 handler should not be null");
}

@test:Config {}
function testGetHandlerITI91() returns error? {
    TransactionHandler h = check getHandler("ITI-91", "Organization");
    test:assertNotEquals(h, (), msg = "ITI-91 handler should not be null");
}

@test:Config {}
function testGetHandlerITI130() returns error? {
    TransactionHandler h = check getHandler("ITI-130", "Organization");
    test:assertNotEquals(h, (), msg = "ITI-130 handler should not be null");
}

// ─────────────────────────────────────────────────────────────────────────────
// Factory — getHandler() unknown type returns error
// ─────────────────────────────────────────────────────────────────────────────

@test:Config {}
function testGetHandlerUnknownType() {
    TransactionHandler|error h = getHandler("ITI-99", "Organization");
    test:assertTrue(h is error, msg = "Unknown transaction type should return error");
}

// ─────────────────────────────────────────────────────────────────────────────
// BaseTransactionHandler — authenticate and authorize pass-throughs
// ─────────────────────────────────────────────────────────────────────────────

@test:Config {}
function testBaseAuthenticate() returns error? {
    http:Request req = new;
    TransactionContext ctx = {
        transactionType: "ITI-90",
        resourceType: "Organization",
        tenantId: "test-tenant",
        request: req
    };
    BaseTransactionHandler base = new;
    error? result = base.authenticate(ctx);
    test:assertEquals(result, (), msg = "authenticate() should return nil (pass-through)");
}

@test:Config {}
function testBaseAuthorize() returns error? {
    http:Request req = new;
    TransactionContext ctx = {
        transactionType: "ITI-90",
        resourceType: "Organization",
        tenantId: "test-tenant",
        request: req
    };
    BaseTransactionHandler base = new;
    error? result = base.authorize(ctx);
    test:assertEquals(result, (), msg = "authorize() should return nil (pass-through)");
}

// ─────────────────────────────────────────────────────────────────────────────
// ITI-91 — execute() returns 200 Bundle for Organization history (H2 backed)
// ─────────────────────────────────────────────────────────────────────────────

@test:Config {}
function testITI91ExecuteOrganizationHistory() returns error? {
    http:Request req = new;
    TransactionContext ctx = {
        transactionType: "ITI-91",
        resourceType: "Organization",
        tenantId: "test-tenant",
        request: req
    };
    ITI91HistoryHandler handler = new;
    http:Response resp = check handler.execute(ctx);

    test:assertEquals(resp.statusCode, 200,
        msg = "ITI-91 execute should return HTTP 200");
    json body = check resp.getJsonPayload();
    test:assertEquals((check body.resourceType).toString(), "Bundle",
        msg = "ITI-91 response body should be a FHIR Bundle");
    test:assertEquals((check body.'type).toString(), "history",
        msg = "ITI-91 Bundle type should be 'history'");
}

@test:Config {}
function testITI91ExecuteLocationHistory() returns error? {
    http:Request req = new;
    TransactionContext ctx = {
        transactionType: "ITI-91",
        resourceType: "Location",
        tenantId: "test-tenant",
        request: req
    };
    ITI91HistoryHandler handler = new;
    http:Response resp = check handler.execute(ctx);
    test:assertEquals(resp.statusCode, 200,
        msg = "ITI-91 execute for Location should return HTTP 200");
}

// ─────────────────────────────────────────────────────────────────────────────
// ITI-90 — execute() returns 200 searchset Bundle for Organization (H2 backed)
// ─────────────────────────────────────────────────────────────────────────────

@test:Config {}
function testITI90ExecuteOrganizationSearch() returns error? {
    http:Request req = new;
    TransactionContext ctx = {
        transactionType: "ITI-90",
        resourceType: "Organization",
        tenantId: "test-tenant",
        request: req
    };
    ITI90SearchHandler handler = new;
    http:Response resp = check handler.execute(ctx);

    test:assertEquals(resp.statusCode, 200,
        msg = "ITI-90 execute should return HTTP 200");
    json body = check resp.getJsonPayload();
    test:assertEquals((check body.resourceType).toString(), "Bundle",
        msg = "ITI-90 response body should be a FHIR Bundle");
    test:assertEquals((check body.'type).toString(), "searchset",
        msg = "ITI-90 Bundle type should be 'searchset'");
}

@test:Config {}
function testITI90ExecuteUnsupportedResourceType() {
    http:Request req = new;
    TransactionContext ctx = {
        transactionType: "ITI-90",
        resourceType: "Patient",
        tenantId: "test-tenant",
        request: req
    };
    ITI90SearchHandler handler = new;
    http:Response|error resp = handler.execute(ctx);
    test:assertTrue(resp is error, msg = "Unsupported resource type should return error");
}
