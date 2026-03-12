import ballerinax/health.fhir.r4;

public final r4:ResourceAPIConfig endpointApiConfig = {
    resourceType: "Endpoint",
    profiles: [
        "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.Endpoint"
    ],
    defaultProfile: (),
    searchParameters: [
        {name: "identifier", active: true},
        {name: "organization", active: true},
        {name: "status", active: true}
    ],
    operations: [],
    serverConfig: (),
    authzConfig: ()
};
