import ballerina/test;
import wso2/FRCoreService.validation;

// ─────────────────────────────────────────────────────────────────────────────
// LK-FR Validation Tests (package-level)
//
// Tests the validation pipeline for the Sri Lanka HIU Facility Registry IG.
// LK-FR supports: Organization, Location, HealthcareService only.
// Endpoint and OrganizationAffiliation are not part of this IG.
//
// Uses a hardcoded readonly resource list so no Config.toml override is needed
// (avoids affecting service_test.bal which runs in the same package test suite).
// ─────────────────────────────────────────────────────────────────────────────

// LkFrResourceEnabledRule — gates write operations to the 3 LK-FR resources.
isolated class LkFrResourceEnabledRule {
    *validation:ValidationRule;
    private final readonly & string[] enabledResources =
        ["Organization", "Location", "HealthcareService"];

    public function validate(validation:ValidationContext ctx) returns validation:ValidationResult {
        boolean enabled = self.enabledResources.indexOf(ctx.resourceType) is int;
        if !enabled {
            return {
                valid: false,
                errors: ["Resource type '" + ctx.resourceType + "' is not enabled in the LK-FR IG"]
            };
        }
        return {valid: true, errors: []};
    }

    public function getName() returns string => "LkFrResourceEnabledRule";
}

// Test 1: LkFrResourceEnabledRule passes for Organization (enabled in LK-FR).
@test:Config {}
function testLkFrResourceEnabledRulePassesForOrganization() {
    validation:DefaultValidationPipeline pipeline = new ([new LkFrResourceEnabledRule()]);
    validation:ValidationResult result = pipeline.run({
        resourceType: "Organization",
        payload: {"resourceType": "Organization"},
        tenantId: "lk-fr",
        operation: "create"
    });
    test:assertTrue(result.valid,
        msg = "Organization is enabled in LK-FR — rule should pass");
    test:assertEquals(result.errors.length(), 0);
}

// Test 2: LkFrResourceEnabledRule passes for Location (enabled in LK-FR).
@test:Config {}
function testLkFrResourceEnabledRulePassesForLocation() {
    validation:DefaultValidationPipeline pipeline = new ([new LkFrResourceEnabledRule()]);
    validation:ValidationResult result = pipeline.run({
        resourceType: "Location",
        payload: {"resourceType": "Location"},
        tenantId: "lk-fr",
        operation: "create"
    });
    test:assertTrue(result.valid,
        msg = "Location is enabled in LK-FR — rule should pass");
}

// Test 3: LkFrResourceEnabledRule rejects Endpoint (not in LK-FR IG).
@test:Config {}
function testLkFrResourceEnabledRuleRejectsEndpoint() {
    validation:DefaultValidationPipeline pipeline = new ([new LkFrResourceEnabledRule()]);
    validation:ValidationResult result = pipeline.run({
        resourceType: "Endpoint",
        payload: {"resourceType": "Endpoint"},
        tenantId: "lk-fr",
        operation: "create"
    });
    test:assertFalse(result.valid,
        msg = "Endpoint is NOT in LK-FR — rule should reject it");
    test:assertEquals(result.errors[0],
        "Resource type 'Endpoint' is not enabled in the LK-FR IG");
}

// Test 4: LkFrResourceEnabledRule rejects OrganizationAffiliation (not in LK-FR IG).
@test:Config {}
function testLkFrResourceEnabledRuleRejectsOrgAffiliation() {
    validation:DefaultValidationPipeline pipeline = new ([new LkFrResourceEnabledRule()]);
    validation:ValidationResult result = pipeline.run({
        resourceType: "OrganizationAffiliation",
        payload: {"resourceType": "OrganizationAffiliation"},
        tenantId: "lk-fr",
        operation: "create"
    });
    test:assertFalse(result.valid,
        msg = "OrganizationAffiliation is NOT in LK-FR — rule should reject it");
    test:assertTrue(result.errors[0].includes("OrganizationAffiliation"));
}

// Test 5: ProfileValidator rejects Organization missing required name field.
@test:Config {}
function testProfileValidatorRejectsMissingOrgName() {
    validation:DefaultValidationPipeline pipeline = new ([new validation:ProfileValidator()]);
    validation:ValidationResult result = pipeline.run({
        resourceType: "Organization",
        payload: {"resourceType": "Organization"},
        tenantId: "mcsd",
        operation: "create"
    });
    test:assertFalse(result.valid,
        msg = "Organization without name should fail ProfileValidator");
    test:assertEquals(result.errors[0], "Organization.name is required");
}

// Test 6: ProfileValidator rejects Location with invalid status.
@test:Config {}
function testProfileValidatorRejectsInvalidLocationStatus() {
    validation:DefaultValidationPipeline pipeline = new ([new validation:ProfileValidator()]);
    validation:ValidationResult result = pipeline.run({
        resourceType: "Location",
        payload: {"resourceType": "Location", "name": "Test", "status": "unknown"},
        tenantId: "mcsd",
        operation: "create"
    });
    test:assertFalse(result.valid,
        msg = "Location with invalid status should fail ProfileValidator");
    test:assertTrue(result.errors[0].includes("active, suspended, inactive"));
}

// Test 7: ProfileValidator passes a valid Location payload.
@test:Config {}
function testProfileValidatorPassesValidLocation() {
    validation:DefaultValidationPipeline pipeline = new ([new validation:ProfileValidator()]);
    validation:ValidationResult result = pipeline.run({
        resourceType: "Location",
        payload: {"resourceType": "Location", "name": "Ward A", "status": "active"},
        tenantId: "mcsd",
        operation: "create"
    });
    test:assertTrue(result.valid,
        msg = "Valid Location payload should pass ProfileValidator");
}

// Test 8: Full LK-FR pipeline — FhirBaseValidator + ProfileValidator + LkFrResourceEnabledRule.
// HealthcareService passes; OrganizationAffiliation fails.
@test:Config {}
function testLkFrFullPipeline() {
    validation:DefaultValidationPipeline pipeline = new ([
        new validation:FhirBaseValidator(),
        new validation:ProfileValidator(),
        new LkFrResourceEnabledRule()
    ]);

    validation:ValidationResult pass = pipeline.run({
        resourceType: "HealthcareService",
        payload: {"resourceType": "HealthcareService", "name": "Radiology"},
        tenantId: "lk-fr",
        operation: "create"
    });
    test:assertTrue(pass.valid,
        msg = "HealthcareService is enabled in LK-FR — full pipeline should pass");

    validation:ValidationResult rejectResult = pipeline.run({
        resourceType: "OrganizationAffiliation",
        payload: {"resourceType": "OrganizationAffiliation"},
        tenantId: "lk-fr",
        operation: "create"
    });
    test:assertFalse(rejectResult.valid,
        msg = "OrganizationAffiliation is NOT in LK-FR — pipeline should reject it");
    test:assertTrue(rejectResult.errors[0].includes("OrganizationAffiliation"));
}
