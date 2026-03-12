import ballerinax/health.fhir.r4;

public final r4:ResourceAPIConfig healthcareServiceApiConfig = {
    resourceType: "HealthcareService",
    profiles: [
        "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.HealthcareService"
    ],
    defaultProfile: (),
    searchParameters: [
        {name: "active", active: true},
        {name: "identifier", active: true},
        {name: "location", active: true},
        {name: "name", active: true},
        {name: "organization", active: true},
        {name: "service-type", active: true}
    ],
    operations: [],
    serverConfig: (),
    authzConfig: ()
};
