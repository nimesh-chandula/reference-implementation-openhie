import ballerinax/health.fhir.r4;

// Returns the ResourceAPIConfig for a given FHIR resource type name.
// Returns () if the resource type is not registered in this service.
// Used by capability.bal to read search parameter names from a single source of truth.
public function getResourceApiConfig(string resourceType) returns r4:ResourceAPIConfig? {
    match resourceType {
        "Organization"            => { return organizationApiConfig; }
        "Location"                => { return locationApiConfig; }
        "HealthcareService"       => { return healthcareServiceApiConfig; }
        "Endpoint"                => { return endpointApiConfig; }
        "OrganizationAffiliation" => { return organizationAffiliationApiConfig; }
    }
    return ();
}
