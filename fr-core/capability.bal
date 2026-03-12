import ballerina/uuid;
import ballerina/time;

// Build a complete FHIR R4 CapabilityStatement for the FR Core mCSD Directory
function buildCapabilityStatement(string baseUrl) returns json {
    return {
        "resourceType": "CapabilityStatement",
        "id": uuid:createType1AsString(),
        "url": baseUrl + "/fhir/metadata",
        "version": "1.0.0",
        "name": "FRCoreMCSDCapabilityStatement",
        "title": "FR Core mCSD Facility Registry — Capability Statement",
        "status": "active",
        "experimental": false,
        "date": time:utcToString(time:utcNow()),
        "publisher": "WSO2 / OpenHIE",
        "description": "Capability Statement for the Facility Registry (FR) Core Service implementing IHE mCSD v4.0.0 Directory Actor. Supports ITI-90 (Find Matching Care Services), ITI-91 (Request Care Services Updates), and ITI-130 (Care Services Feed).",
        "kind": "instance",
        "instantiates": [
            "https://profiles.ihe.net/ITI/mCSD/CapabilityStatement/IHE.mCSD.CareServicesSelectiveSupplier"
        ],
        "software": {
            "name": "wso2/FRCoreService",
            "version": "1.0.0"
        },
        "implementation": {
            "description": "OpenHIE Facility Registry — FR Core Ballerina Service",
            "url": baseUrl + "/fhir"
        },
        "fhirVersion": "4.0.1",
        "format": ["application/fhir+json", "application/json"],
        "rest": [
            {
                "mode": "server",
                "documentation": "FR Core mCSD Directory actor implementing ITI-90, ITI-91, ITI-130",
                "resource": [
                    buildResourceCapability(
                        "Organization",
                        "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.Organization",
                        [
                            {name: "_id", 'type: "token", documentation: "Resource logical ID"},
                            {name: "active", 'type: "token", documentation: "Filter by active status (true|false)"},
                            {name: "identifier", 'type: "token", documentation: "Search by identifier (system|value or value)"},
                            {name: "name", 'type: "string", documentation: "Organization name. Supports :contains and :exact modifiers"},
                            {name: "type", 'type: "token", documentation: "Organization type (facility|jurisdiction)"},
                            {name: "partof", 'type: "reference", documentation: "Reference to parent Organization"},
                            {name: "_lastUpdated", 'type: "date", documentation: "Filter by modification date with prefixes gt,lt,ge,le"}
                        ],
                        ["read", "search-type", "create", "update", "delete"],
                        true
                    ),
                    buildResourceCapability(
                        "Location",
                        "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.Location",
                        [
                            {name: "_id", 'type: "token", documentation: "Resource logical ID"},
                            {name: "identifier", 'type: "token", documentation: "Search by identifier (system|value)"},
                            {name: "name", 'type: "string", documentation: "Facility/jurisdiction name. Supports :contains, :exact"},
                            {name: "organization", 'type: "reference", documentation: "Reference to managing Organization"},
                            {name: "status", 'type: "token", documentation: "active | suspended | inactive"},
                            {name: "type", 'type: "token", documentation: "Location type (facility|jurisdiction)"},
                            {name: "partof", 'type: "reference", documentation: "Reference to parent Location"},
                            {name: "near", 'type: "special", documentation: "lat|lon|distance|units — Location Distance Option"},
                            {name: "_lastUpdated", 'type: "date", documentation: "Filter by modification date with prefixes"}
                        ],
                        ["read", "search-type", "create", "update", "delete"],
                        true
                    ),
                    buildResourceCapability(
                        "HealthcareService",
                        "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.HealthcareService",
                        [
                            {name: "active", 'type: "token", documentation: "Filter active services"},
                            {name: "identifier", 'type: "token", documentation: "Service identifier"},
                            {name: "location", 'type: "reference", documentation: "Reference to Location where service is offered"},
                            {name: "name", 'type: "string", documentation: "Service name. Supports :contains, :exact"},
                            {name: "organization", 'type: "reference", documentation: "Reference to providing Organization"},
                            {name: "service-type", 'type: "token", documentation: "Type of service (e.g., HIV, TB, Lab)"}
                        ],
                        ["read", "search-type", "create", "update", "delete"],
                        true
                    ),
                    buildResourceCapability(
                        "Endpoint",
                        "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.Endpoint",
                        [
                            {name: "identifier", 'type: "token", documentation: "Endpoint identifier"},
                            {name: "organization", 'type: "reference", documentation: "Reference to managing Organization"},
                            {name: "status", 'type: "token", documentation: "active | suspended | error | off | test"}
                        ],
                        ["read", "search-type", "create"],
                        false
                    ),
                    buildResourceCapability(
                        "OrganizationAffiliation",
                        "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.OrganizationAffiliation",
                        [
                            {name: "active", 'type: "token", documentation: "Filter active affiliations"},
                            {name: "identifier", 'type: "token", documentation: "Affiliation identifier"},
                            {name: "participating-organization", 'type: "reference", documentation: "Participating Organization"},
                            {name: "primary-organization", 'type: "reference", documentation: "Primary Organization"},
                            {name: "role", 'type: "token", documentation: "Affiliation role code"}
                        ],
                        ["read", "search-type", "create"],
                        false
                    )
                ]
            }
        ]
    };
}

// Build a resource capability entry
isolated function buildResourceCapability(
    string resourceType,
    string profile,
    record {string name; string 'type; string documentation;}[] searchParams,
    string[] interactions,
    boolean supportsHistory
) returns json {
    json[] interactionList = [];
    foreach string interaction in interactions {
        interactionList.push({"code": interaction});
    }

    json[] searchParamList = [];
    foreach var sp in searchParams {
        searchParamList.push({
            "name": sp.name,
            "type": sp.'type,
            "documentation": sp.documentation
        });
    }

    json[] operationList = [];
    if supportsHistory {
        operationList.push({
            "name": "_history",
            "definition": "http://hl7.org/fhir/OperationDefinition/Resource-history",
            "documentation": "ITI-91: Request Care Services Updates via FHIR _history with _since"
        });
    }

    json capability = {
        "type": resourceType,
        "profile": profile,
        "interaction": interactionList,
        "searchParam": searchParamList
    };

    if operationList.length() > 0 {
        map<json> capMap = <map<json>>capability;
        capMap["operation"] = operationList;
        return capMap;
    }
    return capability;
}
