// ─────────────────────────────────────────────────────────────────────────────
// Search Parameter Metadata Registry — §3.4
//
// Stores paramType + expression metadata keyed by param name.
// Param names are sourced from r4_api_config (ResourceAPIConfig.searchParameters)
// so this registry only holds the extra context the CapabilityStatement needs:
//   - paramType  ("token" | "string" | "reference" | "date" | "special")
//   - expression (FHIRPath or human-readable documentation)
//
// If a param name is not in the metadata map, getParamMeta() returns a safe
// fallback so new params added to r4_api_config never break the build.
// ─────────────────────────────────────────────────────────────────────────────

// Metadata for a single FHIR search parameter.
// The param name itself comes from r4_api_config — not stored here.
// readonly: allows safe return from lock blocks without cloning.
public type SearchParamMeta readonly & record {|
    // FHIR search param type: "token" | "string" | "reference" | "date" | "special"
    string paramType;
    // FHIRPath expression or human-readable documentation
    string expression;
|};

// Module-level metadata store — keyed by param name.
isolated map<SearchParamMeta> paramMetadata = {};

// Return metadata for a param name.
// Falls back to {paramType: "string", expression: name} for unknown params —
// forward-compatible when new params are added to r4_api_config.
public isolated function getParamMeta(string name) returns SearchParamMeta {
    lock {
        return paramMetadata[name] ?: {paramType: "string", expression: name};
    }
}

// Build the default metadata map from the mCSD param set.
// Flat map keyed by param name — params shared across resource types
// (e.g., "_id", "identifier", "name") appear only once.
public function buildDefaultMetadata() returns map<SearchParamMeta> {
    return {
        "_id":                        {paramType: "token",     expression: "Resource logical ID"},
        "active":                     {paramType: "token",     expression: "Filter by active status (true|false)"},
        "identifier":                 {paramType: "token",     expression: "Search by identifier (system|value)"},
        "name":                       {paramType: "string",    expression: "Resource name. Supports :contains and :exact modifiers"},
        "type":                       {paramType: "token",     expression: "Resource type code"},
        "partof":                     {paramType: "reference", expression: "Reference to parent resource"},
        "_lastUpdated":               {paramType: "date",      expression: "Filter by modification date with prefixes gt,lt,ge,le"},
        "organization":               {paramType: "reference", expression: "Reference to managing Organization"},
        "status":                     {paramType: "token",     expression: "Resource status code"},
        "near":                       {paramType: "special",   expression: "lat|lon|distance|units — Location Distance Option"},
        "location":                   {paramType: "reference", expression: "Reference to Location where service is offered"},
        "service-type":               {paramType: "token",     expression: "Type of service"},
        "participating-organization": {paramType: "reference", expression: "Participating Organization"},
        "primary-organization":       {paramType: "reference", expression: "Primary Organization"},
        "role":                       {paramType: "token",     expression: "Affiliation role code"},
        "_include":                   {paramType: "special",   expression: "Include referenced resources in results"},
        "_revInclude":                {paramType: "special",   expression: "Include resources that reference this resource"}
    };
}

// Populate the module-level metadata store at program startup.
function init() {
    map<SearchParamMeta> meta = buildDefaultMetadata();
    lock {
        paramMetadata = meta.clone();
    }
}
