import ballerinax/health.fhir.r4;

public final r4:ResourceAPIConfig organizationAffiliationApiConfig = {
    resourceType: "OrganizationAffiliation",
    profiles: [
        "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.OrganizationAffiliation"
    ],
    defaultProfile: (),
    searchParameters: [
        {name: "active", active: true},
        {name: "identifier", active: true},
        {name: "participating-organization", active: true},
        {name: "primary-organization", active: true},
        {name: "role", active: true}
    ],
    operations: [],
    serverConfig: (),
    authzConfig: ()
};
