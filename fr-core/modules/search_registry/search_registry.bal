// ─────────────────────────────────────────────────────────────────────────────
// Search Parameter Registry — §3.4
//
// Runtime registry for FHIR search parameter definitions per resource type.
// Replaces hardcoded search params in capability.bal with a queryable registry.
//
// Populated at module init from the default mCSD param set.
// Supports dynamic registration for IG extensions.
// ─────────────────────────────────────────────────────────────────────────────

// A single FHIR search parameter definition.
public type SearchParamDef record {|
    // FHIR search param name (e.g., "_id", "name", "partof")
    string name;
    // FHIR search param type: "token" | "string" | "reference" | "date" | "special"
    string paramType;
    // FHIRPath expression or human-readable documentation (e.g., "Organization.name")
    string expression;
    // IGs that support this param; empty array means supported by all IGs
    string[] supportedIGs;
|};

// Registry keyed by FHIR resource type name.
public type SearchParamRegistry record {|
    map<SearchParamDef[]> byResourceType;
|};

// Module-level isolated registry — populated at init, mutable via registerSearchParam.
isolated SearchParamRegistry registry = {byResourceType: {}};

// Register a search parameter for a resource type at runtime.
// Thread-safe: uses lock to guard isolated module state.
public function registerSearchParam(string resourceType, SearchParamDef param) {
    lock {
        SearchParamDef[] existing = registry.byResourceType[resourceType] ?: [];
        existing.push(param.clone());
        registry.byResourceType[resourceType] = existing;
    }
}

// Return all registered search parameters for a resource type.
// Returns an empty array if the resource type is unknown.
public function getSearchParams(string resourceType) returns SearchParamDef[] {
    lock {
        SearchParamDef[]? params = registry.byResourceType[resourceType];
        if params is SearchParamDef[] {
            return params.clone();
        }
        return [];
    }
}

// Build the default mCSD search parameter registry from the existing hardcoded set.
// Mirrors the params previously defined in capability.bal getSearchParamsForResource().
public function buildDefaultRegistry() returns SearchParamRegistry {
    map<SearchParamDef[]> byResource = {};

    byResource["Organization"] = [
        {name: "_id",          paramType: "token",     expression: "Resource logical ID",                                                supportedIGs: []},
        {name: "active",       paramType: "token",     expression: "Filter by active status (true|false)",                               supportedIGs: []},
        {name: "identifier",   paramType: "token",     expression: "Search by identifier (system|value or value)",                       supportedIGs: []},
        {name: "name",         paramType: "string",    expression: "Organization name. Supports :contains and :exact modifiers",         supportedIGs: []},
        {name: "type",         paramType: "token",     expression: "Organization type (facility|jurisdiction)",                          supportedIGs: []},
        {name: "partof",       paramType: "reference", expression: "Reference to parent Organization",                                   supportedIGs: []},
        {name: "_lastUpdated", paramType: "date",      expression: "Filter by modification date with prefixes gt,lt,ge,le",              supportedIGs: []}
    ];

    byResource["Location"] = [
        {name: "_id",          paramType: "token",     expression: "Resource logical ID",                                                supportedIGs: []},
        {name: "identifier",   paramType: "token",     expression: "Search by identifier (system|value)",                                supportedIGs: []},
        {name: "name",         paramType: "string",    expression: "Facility/jurisdiction name. Supports :contains, :exact",             supportedIGs: []},
        {name: "organization", paramType: "reference", expression: "Reference to managing Organization",                                 supportedIGs: []},
        {name: "status",       paramType: "token",     expression: "active | suspended | inactive",                                      supportedIGs: []},
        {name: "type",         paramType: "token",     expression: "Location type (facility|jurisdiction)",                              supportedIGs: []},
        {name: "partof",       paramType: "reference", expression: "Reference to parent Location",                                       supportedIGs: []},
        {name: "near",         paramType: "special",   expression: "lat|lon|distance|units — Location Distance Option",                  supportedIGs: []},
        {name: "_lastUpdated", paramType: "date",      expression: "Filter by modification date with prefixes",                          supportedIGs: []}
    ];

    byResource["HealthcareService"] = [
        {name: "active",       paramType: "token",     expression: "Filter active services",                                             supportedIGs: []},
        {name: "identifier",   paramType: "token",     expression: "Service identifier",                                                 supportedIGs: []},
        {name: "location",     paramType: "reference", expression: "Reference to Location where service is offered",                     supportedIGs: []},
        {name: "name",         paramType: "string",    expression: "Service name. Supports :contains, :exact",                           supportedIGs: []},
        {name: "organization", paramType: "reference", expression: "Reference to providing Organization",                                supportedIGs: []},
        {name: "service-type", paramType: "token",     expression: "Type of service (e.g., HIV, TB, Lab)",                               supportedIGs: []}
    ];

    byResource["Endpoint"] = [
        {name: "identifier",   paramType: "token",     expression: "Endpoint identifier",                                                supportedIGs: []},
        {name: "organization", paramType: "reference", expression: "Reference to managing Organization",                                 supportedIGs: []},
        {name: "status",       paramType: "token",     expression: "active | suspended | error | off | test",                            supportedIGs: []}
    ];

    byResource["OrganizationAffiliation"] = [
        {name: "active",                   paramType: "token",     expression: "Filter active affiliations",     supportedIGs: []},
        {name: "identifier",               paramType: "token",     expression: "Affiliation identifier",         supportedIGs: []},
        {name: "participating-organization", paramType: "reference", expression: "Participating Organization",   supportedIGs: []},
        {name: "primary-organization",     paramType: "reference", expression: "Primary Organization",           supportedIGs: []},
        {name: "role",                     paramType: "token",     expression: "Affiliation role code",          supportedIGs: []}
    ];

    return {byResourceType: byResource};
}

// Populate the module-level registry from the default mCSD search param set.
function init() {
    SearchParamRegistry defaultReg = buildDefaultRegistry();
    lock {
        registry = defaultReg.clone();
    }
}
