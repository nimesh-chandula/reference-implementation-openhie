// ─────────────────────────────────────────────────────────────────────────────
// Tenant Configuration — Profile Adapter Pattern (§3.1) + Tenant Context (§3.7)
//
// Loads the active IG configuration from Config.toml via Ballerina configurable.
// Provides accessor helpers used by profile_adapter.bal and capability.bal.
//
// To switch IGs (e.g., Sri Lanka FR), update [igConfig] in Config.toml only —
// no code changes required.
// ─────────────────────────────────────────────────────────────────────────────

// Per-resource IG configuration entry
public type IGResourceConfig record {|
    // FHIR resource type name (e.g., "Organization")
    string resourceType;
    // Base profile URL for this resource
    string profile;
    // Optional: profile URL for the "facility" type code variant
    string facilityProfile?;
    // Optional: profile URL for the "jurisdiction" type code variant
    string jurisdictionProfile?;
    // FHIR interactions this resource supports (e.g., ["read", "search-type", "create"])
    string[] interactions;
    // Whether this resource type supports ITI-91 history
    boolean supportsHistory;
|};

// Which IHE mCSD transactions are enabled for this tenant
public type IGTransactionConfig record {|
    boolean iti90 = true;   // ITI-90 Find Matching Care Services (search + read)
    boolean iti91 = true;   // ITI-91 Request Care Services Updates (history)
    boolean iti130 = true;  // ITI-130 Care Services Feed (create/update/delete)
|};

// Top-level IG/tenant configuration — loaded from Config.toml [igConfig] section
public type IGConfig record {|
    // Short identifier for this IG/tenant (e.g., "mcsd", "lk-fr")
    string id;
    // Human-readable IG name
    string name;
    // Canonical base URL of the IG
    string canonical;
    // FHIR version this IG targets
    string fhirVersion;
    // Server name published in CapabilityStatement.name
    string serverName;
    // Server version published in CapabilityStatement.version
    string serverVersion;
    // Publisher name published in CapabilityStatement.publisher
    string publisher;
    // CapabilityStatement.instantiates — which canonical CS this server instantiates
    string[] instantiates;
    // Enabled transaction modules
    IGTransactionConfig transactions;
    // Per-resource configuration entries
    IGResourceConfig[] resources;
|};

// ─────────────────────────────────────────────────────────────────────────────
// Configurable IG config — can be overridden in Config.toml [igConfig] section.
// Default values replicate the existing hardcoded mCSD behaviour exactly.
// ─────────────────────────────────────────────────────────────────────────────
configurable IGConfig igConfig = {
    id: "mcsd",
    name: "IHE mCSD v4.0.1",
    canonical: "https://profiles.ihe.net/ITI/mCSD",
    fhirVersion: "4.0.1",
    serverName: "FRCoreMCSDCapabilityStatement",
    serverVersion: "1.0.0",
    publisher: "WSO2 / OpenHIE",
    instantiates: [
        "https://profiles.ihe.net/ITI/mCSD/CapabilityStatement/IHE.mCSD.CareServicesSelectiveSupplier"
    ],
    transactions: {
        iti90: true,
        iti91: true,
        iti130: true
    },
    resources: [
        {
            resourceType: "Organization",
            profile: "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.Organization",
            facilityProfile: "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.FacilityOrganization",
            jurisdictionProfile: "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.JurisdictionOrganization",
            interactions: ["read", "search-type", "create", "update", "delete"],
            supportsHistory: true
        },
        {
            resourceType: "Location",
            profile: "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.Location",
            facilityProfile: "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.FacilityLocation",
            jurisdictionProfile: "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.JurisdictionLocation",
            interactions: ["read", "search-type", "create", "update", "delete"],
            supportsHistory: true
        },
        {
            resourceType: "HealthcareService",
            profile: "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.HealthcareService",
            interactions: ["read", "search-type", "create", "update", "delete"],
            supportsHistory: true
        },
        {
            resourceType: "Endpoint",
            profile: "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.Endpoint",
            interactions: ["read", "search-type", "create"],
            supportsHistory: false
        },
        {
            resourceType: "OrganizationAffiliation",
            profile: "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.OrganizationAffiliation",
            interactions: ["read", "search-type", "create"],
            supportsHistory: false
        }
    ]
};

// ─────────────────────────────────────────────────────────────────────────────
// Accessor helpers
// ─────────────────────────────────────────────────────────────────────────────

// Returns the full IGConfig — used by capability.bal (root module)
public function getIgConfig() returns IGConfig {
    return igConfig;
}

// Returns the IGResourceConfig for the given FHIR resource type, or () if not configured.
public function getResourceConfig(string resourceType) returns IGResourceConfig? {
    foreach IGResourceConfig rc in igConfig.resources {
        if rc.resourceType == resourceType {
            return rc;
        }
    }
    return ();
}

// Returns the profile URL for the given resource type and type code.
// typeCode is "facility" | "jurisdiction" | "" (default).
// Falls back to the base profile if no facility/jurisdiction variant is configured.
public function getProfileUrl(string resourceType, string typeCode) returns string {
    IGResourceConfig? rc = getResourceConfig(resourceType);
    if rc is () {
        return igConfig.canonical + "/StructureDefinition/" + resourceType;
    }
    if typeCode == "jurisdiction" {
        string? jp = rc.jurisdictionProfile;
        if jp is string {
            return jp;
        }
    }
    if typeCode == "facility" {
        string? fp = rc.facilityProfile;
        if fp is string {
            return fp;
        }
    }
    return rc.profile;
}
