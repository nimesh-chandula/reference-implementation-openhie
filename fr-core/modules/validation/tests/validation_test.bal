import ballerina/test;

// ─────────────────────────────────────────────────────────────────────────────
// Module-level helper classes used by tests
// ─────────────────────────────────────────────────────────────────────────────

isolated class AlwaysFailRule {
    *ValidationRule;
    public function validate(ValidationContext ctx) returns ValidationResult =>
        {valid: false, errors: ["Intentional failure"]};
    public function getName() returns string => "AlwaysFailRule";
}

isolated class FirstFailRule {
    *ValidationRule;
    public function validate(ValidationContext ctx) returns ValidationResult =>
        {valid: false, errors: ["First rule failed"]};
    public function getName() returns string => "FirstFailRule";
}

isolated class TrackingRule {
    *ValidationRule;
    public function validate(ValidationContext ctx) returns ValidationResult =>
        {valid: true, errors: []};
    public function getName() returns string => "TrackingRule";
}

// ─────────────────────────────────────────────────────────────────────────────
// Validation Pipeline Tests
// ─────────────────────────────────────────────────────────────────────────────

// Test 1: Pipeline with no rules passes any input.
@test:Config {}
function testEmptyPipelinePasses() {
    DefaultValidationPipeline pipeline = new ([]);
    ValidationResult result = pipeline.run({
        resourceType: "Organization",
        payload: {"resourceType": "Organization"},
        tenantId: "mcsd",
        operation: "create"
    });
    test:assertTrue(result.valid, msg = "Empty pipeline should pass any input");
    test:assertEquals(result.errors.length(), 0, msg = "Empty pipeline should have no errors");
}

// Test 2: Pipeline with a rule that always fails returns valid = false.
@test:Config {}
function testFailingRuleReturnsFalse() {
    DefaultValidationPipeline pipeline = new ([new AlwaysFailRule()]);
    ValidationResult result = pipeline.run({
        resourceType: "Organization",
        payload: {},
        tenantId: "mcsd",
        operation: "create"
    });
    test:assertFalse(result.valid, msg = "Pipeline should fail when a rule fails");
    test:assertEquals(result.errors[0], "Intentional failure", msg = "Error message should be propagated");
}

// Test 3: Pipeline stops on first failure — second rule is never reached.
@test:Config {}
function testPipelineStopsOnFirstFailure() {
    DefaultValidationPipeline pipeline = new ([new FirstFailRule(), new TrackingRule()]);
    ValidationResult result = pipeline.run({
        resourceType: "Organization",
        payload: {},
        tenantId: "mcsd",
        operation: "create"
    });
    test:assertFalse(result.valid, msg = "Pipeline should fail on first failing rule");
    test:assertEquals(result.errors[0], "First rule failed", msg = "Error from first rule should be returned");
}

// Test 4: buildDefaultPipeline passes a valid Organization payload.
@test:Config {}
function testDefaultPipelinePasses() {
    ValidationPipeline pipeline = buildDefaultPipeline();
    ValidationResult result = pipeline.run({
        resourceType: "Organization",
        payload: {"resourceType": "Organization", "name": "Test Org"},
        tenantId: "mcsd",
        operation: "create"
    });
    test:assertTrue(result.valid, msg = "Valid Organization payload should pass the default pipeline");
}

// ─────────────────────────────────────────────────────────────────────────────
// FhirBaseValidator Tests
// ─────────────────────────────────────────────────────────────────────────────

// Test 5: Missing resourceType field is rejected.
@test:Config {}
function testBaseValidatorRejectsMissingResourceType() {
    FhirBaseValidator rule = new ();
    ValidationResult result = rule.validate({
        resourceType: "Organization",
        payload: {"name": "Test Org"},
        tenantId: "mcsd",
        operation: "create"
    });
    test:assertFalse(result.valid);
    test:assertEquals(result.errors[0], "Missing required field: 'resourceType'");
}

// Test 6: Mismatched resourceType is rejected.
@test:Config {}
function testBaseValidatorRejectsMismatchedResourceType() {
    FhirBaseValidator rule = new ();
    ValidationResult result = rule.validate({
        resourceType: "Organization",
        payload: {"resourceType": "Location", "name": "Test"},
        tenantId: "mcsd",
        operation: "create"
    });
    test:assertFalse(result.valid);
    test:assertTrue(result.errors[0].includes("does not match expected"));
}

// Test 7: Update without id is rejected.
@test:Config {}
function testBaseValidatorRejectsUpdateWithoutId() {
    FhirBaseValidator rule = new ();
    ValidationResult result = rule.validate({
        resourceType: "Organization",
        payload: {"resourceType": "Organization", "name": "Test Org"},
        tenantId: "mcsd",
        operation: "update"
    });
    test:assertFalse(result.valid);
    test:assertEquals(result.errors[0], "Field 'id' is required for update operations");
}

// Test 8: Invalid id format is rejected.
@test:Config {}
function testBaseValidatorRejectsInvalidIdFormat() {
    FhirBaseValidator rule = new ();
    ValidationResult result = rule.validate({
        resourceType: "Organization",
        payload: {"resourceType": "Organization", "id": "invalid id with spaces!", "name": "Test"},
        tenantId: "mcsd",
        operation: "update"
    });
    test:assertFalse(result.valid);
    test:assertTrue(result.errors[0].includes("Invalid 'id' format"));
}

// Test 9: Valid create payload passes FhirBaseValidator.
@test:Config {}
function testBaseValidatorPassesValidCreate() {
    FhirBaseValidator rule = new ();
    ValidationResult result = rule.validate({
        resourceType: "Organization",
        payload: {"resourceType": "Organization", "name": "Test Org"},
        tenantId: "mcsd",
        operation: "create"
    });
    test:assertTrue(result.valid);
}

// Test 10: Valid update payload with FHIR-compliant id passes.
@test:Config {}
function testBaseValidatorPassesValidUpdate() {
    FhirBaseValidator rule = new ();
    ValidationResult result = rule.validate({
        resourceType: "Organization",
        payload: {"resourceType": "Organization", "id": "org-001", "name": "Test Org"},
        tenantId: "mcsd",
        operation: "update"
    });
    test:assertTrue(result.valid);
}
