import ballerinax/health.fhir.r4;

public final r4:ResourceAPIConfig organizationApiConfig = {
    resourceType: "Organization",
    profiles: [
        "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.Organization",
        "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.FacilityOrganization",
        "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.JurisdictionOrganization"
    ],
    defaultProfile: (),
    searchParameters: [
        {name: "_id", active: true},
        {name: "active", active: true},
        {name: "identifier", active: true},
        {name: "name", active: true},
        {name: "type", active: true},
        {name: "partof", active: true},
        {name: "_lastUpdated", active: true},
        {name: "_include", active: true},
        {name: "_revInclude", active: true}
    ],
    operations: [],
    serverConfig: (),
    authzConfig: ()
};
