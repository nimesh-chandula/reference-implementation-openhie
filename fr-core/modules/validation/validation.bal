import wso2/FRCoreService.fhir_utils;

// ─────────────────────────────────────────────────────────────────────────────
// Validation Pipeline — Chain of Responsibility Pattern (§3.5)
//
// Defines the interface for FHIR resource validation before write operations.
// Rules are chained in order; the pipeline stops on the first failure.
// ─────────────────────────────────────────────────────────────────────────────

// Context passed to every validation rule.
public type ValidationContext record {|
    // FHIR resource type being validated (e.g., "Organization")
    string resourceType;
    // Raw JSON payload from the request
    json payload;
    // Active tenant/IG identifier (e.g., "mcsd")
    string tenantId;
    // Write operation type
    string operation; // "create" | "update"
|};

// Result returned by each rule and the pipeline.
public type ValidationResult record {|
    boolean valid;
    string[] errors;
|};

// Interface: a single validation rule.
public type ValidationRule object {
    public function validate(ValidationContext ctx) returns ValidationResult;
    public function getName() returns string;
};

// Interface: a chain of validation rules.
public type ValidationPipeline object {
    public function addRule(ValidationRule rule) returns ValidationPipeline;
    public function run(ValidationContext ctx) returns ValidationResult;
};

// ─────────────────────────────────────────────────────────────────────────────
// DefaultValidationPipeline — iterates rules, stops on first failure.
// ─────────────────────────────────────────────────────────────────────────────
public class DefaultValidationPipeline {
    *ValidationPipeline;
    private ValidationRule[] rules;

    public function init(ValidationRule[] rules = []) {
        self.rules = rules;
    }

    public function addRule(ValidationRule rule) returns ValidationPipeline {
        self.rules.push(rule);
        return self;
    }

    public function run(ValidationContext ctx) returns ValidationResult {
        foreach ValidationRule rule in self.rules {
            ValidationResult result = rule.validate(ctx);
            if !result.valid {
                return result;
            }
        }
        return {valid: true, errors: []};
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// FhirBaseValidator — validates FHIR resource structure.
//
// Checks:
//   1. Payload is a JSON object
//   2. `resourceType` field is present and matches ctx.resourceType
//   3. For update: `id` field is required
//   4. `id` format is valid if present: [A-Za-z0-9\-\.]{1,64}
// ─────────────────────────────────────────────────────────────────────────────
public isolated class FhirBaseValidator {
    *ValidationRule;

    public function validate(ValidationContext ctx) returns ValidationResult {
        map<json>|error payloadMap = ctx.payload.ensureType();
        if payloadMap is error {
            return {valid: false, errors: ["Payload must be a JSON object"]};
        }

        // resourceType must be present and match the expected resource type
        json? rtField = payloadMap["resourceType"];
        if rtField is () {
            return {valid: false, errors: ["Missing required field: 'resourceType'"]};
        }
        string rtValue = rtField.toString();
        if rtValue != ctx.resourceType {
            return {
                valid: false,
                errors: ["'resourceType' in payload ('" + rtValue + "') does not match expected '" + ctx.resourceType + "'"]
            };
        }

        // id is required for update operations
        json? idField = payloadMap["id"];
        if ctx.operation == "update" {
            if idField is () || idField.toString().trim().length() == 0 {
                return {valid: false, errors: ["Field 'id' is required for update operations"]};
            }
        }

        // Validate id format if present (FHIR id: [A-Za-z0-9\-\.]{1,64})
        if !(idField is ()) {
            string idValue = idField.toString();
            if !isValidFhirId(idValue) {
                return {
                    valid: false,
                    errors: ["Invalid 'id' format — FHIR id must be 1-64 characters matching [A-Za-z0-9\\-\\.], got: '" + idValue + "'"]
                };
            }
        }

        return {valid: true, errors: []};
    }

    public function getName() returns string => "FhirBaseValidator";
}

// ─────────────────────────────────────────────────────────────────────────────
// ProfileValidator — validates IG profile conformance.
//
// Checks:
//   1. Resource type is enabled in the active IG (from igConfig via profileAdapter)
//   2. Resource-specific required fields are present:
//        Organization  : name
//        Location      : name, status (active|suspended|inactive)
//        Endpoint      : status, connectionType, address
//        HealthcareService, OrganizationAffiliation: no hard required fields
// ─────────────────────────────────────────────────────────────────────────────
public class ProfileValidator {
    *ValidationRule;

    public function validate(ValidationContext ctx) returns ValidationResult {
        // Check resource type is enabled in the active IG configuration
        if !fhir_utils:profileAdapter.isResourceEnabled(ctx.resourceType) {
            return {
                valid: false,
                errors: ["Resource type '" + ctx.resourceType + "' is not enabled in the active IG configuration"]
            };
        }

        map<json>|error payloadMap = ctx.payload.ensureType();
        if payloadMap is error {
            return {valid: false, errors: ["Payload must be a JSON object"]};
        }

        return validateRequiredFields(ctx.resourceType, payloadMap);
    }

    public function getName() returns string => "ProfileValidator";
}

// ─────────────────────────────────────────────────────────────────────────────
// Private helpers
// ─────────────────────────────────────────────────────────────────────────────

// Validate resource-specific required fields. Collects all violations at once
// so the caller sees the full list of missing fields in one response.
function validateRequiredFields(string resourceType, map<json> payload) returns ValidationResult {
    string[] errors = [];

    if resourceType == "Organization" {
        // Organization.name is required (1..1 per FHIR R4)
        if !hasNonEmptyField(payload, "name") {
            errors.push("Organization.name is required");
        }

    } else if resourceType == "Location" {
        // Location.name is required per mCSD profile
        if !hasNonEmptyField(payload, "name") {
            errors.push("Location.name is required");
        }
        // Location.status is required; must be a valid FHIR Location status code
        if !hasNonEmptyField(payload, "status") {
            errors.push("Location.status is required");
        } else {
            json? statusVal = payload["status"];
            string status = statusVal is () ? "" : statusVal.toString();
            if status != "active" && status != "suspended" && status != "inactive" {
                errors.push("Location.status must be one of: active, suspended, inactive — got: '" + status + "'");
            }
        }

    } else if resourceType == "Endpoint" {
        // Endpoint: status, connectionType, and address (url) are required
        if !hasNonEmptyField(payload, "status") {
            errors.push("Endpoint.status is required");
        }
        if !hasNonEmptyField(payload, "connectionType") {
            errors.push("Endpoint.connectionType is required");
        }
        if !hasNonEmptyField(payload, "address") {
            errors.push("Endpoint.address is required");
        }
    }
    // HealthcareService and OrganizationAffiliation have no hard required fields
    // in the base FHIR spec or the current IGs — skip.

    if errors.length() > 0 {
        return {valid: false, errors: errors};
    }
    return {valid: true, errors: []};
}

// Returns true if `field` is present in `payload`, is non-null, and non-empty string.
function hasNonEmptyField(map<json> payload, string fieldName) returns boolean {
    json? val = payload[fieldName];
    if val is () {
        return false;
    }
    string str = val.toString();
    return str.trim().length() > 0 && str != "null";
}

// Returns true if `id` conforms to the FHIR id type: [A-Za-z0-9\-\.]{1,64}
isolated function isValidFhirId(string id) returns boolean {
    if id.length() == 0 || id.length() > 64 {
        return false;
    }
    return id.matches(re`[A-Za-z0-9\-\.]+`);
}

// ─────────────────────────────────────────────────────────────────────────────
// Factory — builds the default pipeline with the standard rule set.
// ─────────────────────────────────────────────────────────────────────────────
public function buildDefaultPipeline() returns ValidationPipeline =>
    new DefaultValidationPipeline([new FhirBaseValidator(), new ProfileValidator()]);
