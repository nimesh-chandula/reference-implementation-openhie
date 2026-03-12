import ballerinax/health.fhir.r4;

public final r4:ResourceAPIConfig locationApiConfig = {
    resourceType: "Location",
    profiles: [
        "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.Location",
        "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.FacilityLocation",
        "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.JurisdictionLocation"
    ],
    defaultProfile: (),
    searchParameters: [
        {name: "_id", active: true},
        {name: "identifier", active: true},
        {name: "name", active: true},
        {name: "organization", active: true},
        {name: "status", active: true},
        {name: "type", active: true},
        {name: "partof", active: true},
        {name: "near", active: true},
        {name: "_lastUpdated", active: true},
        {name: "_include", active: true}
    ],
    operations: [],
    serverConfig: (),
    authzConfig: ()
};
