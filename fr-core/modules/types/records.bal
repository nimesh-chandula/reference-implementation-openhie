// Search parameter records — one per FHIR resource type
// nameModifier values: "contains" | "exact" | "" (default = starts-with)

public type OrgSearchParams record {|
    string? _id = ();
    string? active = ();
    string? identifier = ();
    string? name = ();
    string? nameModifier = ();
    string? 'type = ();
    string? partof = ();
    string? _lastUpdated = ();
    string? _lastUpdatedPrefix = ();
    string? _include = ();
    string? _revInclude = ();
    int _count = 20;
    int _offset = 0;
|};

public type LocationSearchParams record {|
    string? _id = ();
    string? identifier = ();
    string? name = ();
    string? nameModifier = ();
    string? organization = ();
    string? status = ();
    string? 'type = ();
    string? partof = ();
    string? near = ();
    string? _lastUpdated = ();
    string? _lastUpdatedPrefix = ();
    string? _include = ();
    int _count = 20;
    int _offset = 0;
|};

public type HealthcareServiceSearchParams record {|
    string? active = ();
    string? identifier = ();
    string? location = ();
    string? name = ();
    string? nameModifier = ();
    string? organization = ();
    string? serviceType = ();
    int _count = 20;
    int _offset = 0;
|};

public type EndpointSearchParams record {|
    string? identifier = ();
    string? organization = ();
    string? status = ();
    int _count = 20;
    int _offset = 0;
|};

public type OrgAffiliationSearchParams record {|
    string? active = ();
    string? identifier = ();
    string? participatingOrganization = ();
    string? primaryOrganization = ();
    string? role = ();
    int _count = 20;
    int _offset = 0;
|};

// Internal DB result row — carries the raw FHIR JSON string from JSONB column
public type ResourceRow record {|
    string id;
    int versionId;
    string fhirResource;
    string lastUpdated;
    boolean isDeleted;
|};

// For ITI-91 history
public type HistoryRow record {|
    string resourceId;
    int versionId;
    string action;       // "CREATE" | "UPDATE" | "DELETE"
    string? fhirResource;
    string timestamp;
|};

// Admin stats response
public type RegistryStats record {|
    int totalOrganizations;
    int totalLocations;
    int totalHealthcareServices;
    int totalEndpoints;
    int activeOrganizations;
    int activeLocations;
    int facilitiesCount;
    int jurisdictionsCount;
|};

// Bulk import result summary
public type BulkImportResult record {|
    int total;
    int created;
    int updated;
    int failed;
    string[] errors;
|};

// Geographic near-search parsed parameter
public type NearParam record {|
    decimal lat;
    decimal lon;
    decimal distanceKm;
|};

// Parsed _lastUpdated parameter (e.g. "gt2026-01-01T00:00:00Z")
public type LastUpdatedFilter record {|
    string prefix;   // "gt" | "lt" | "ge" | "le" | "sa" | "eb"
    string value;    // ISO 8601 datetime string
|};
