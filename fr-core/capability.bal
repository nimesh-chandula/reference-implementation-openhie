import ballerina/uuid;
import ballerina/time;
import wso2/FRCoreService.fhir_utils;
import wso2/FRCoreService.search_registry;

// ─────────────────────────────────────────────────────────────────────────────
// CapabilityStatement Builder — Builder Pattern (§3.10)
//
// Generates the FHIR R4 CapabilityStatement from igConfig (tenant_config.bal).
// Server metadata, resource types, profiles, and interaction sets are all
// driven by Config.toml — no hardcoded values in this file.
//
// Search parameters are sourced from the Search Parameter Registry (modules/search_registry/).
// The registry is populated at module init from the default mCSD param set.
// ─────────────────────────────────────────────────────────────────────────────

// Build the complete FHIR R4 CapabilityStatement for the active tenant/IG.
function buildCapabilityStatement(string baseUrl) returns json {
    fhir_utils:IGConfig igConfig = fhir_utils:getIgConfig();

    // Build the resource capability entries from igConfig
    json[] resourceCapabilities = [];
    foreach fhir_utils:IGResourceConfig rc in igConfig.resources {
        json[] searchParams = getSearchParamsForResource(rc.resourceType);
        resourceCapabilities.push(
            buildResourceCapability(
                rc.resourceType,
                rc.profile,
                searchParams,
                rc.interactions,
                rc.supportsHistory
            )
        );
    }

    // Build instantiates array from igConfig
    json[] instantiatesJson = [];
    foreach string url in igConfig.instantiates {
        instantiatesJson.push(url);
    }

    return {
        "resourceType": "CapabilityStatement",
        "id": uuid:createType1AsString(),
        "url": baseUrl + "/fhir/metadata",
        "version": igConfig.serverVersion,
        "name": igConfig.serverName,
        "title": igConfig.name + " Facility Registry — Capability Statement",
        "status": "active",
        "experimental": false,
        "date": time:utcToString(time:utcNow()),
        "publisher": igConfig.publisher,
        "description": "Capability Statement for the Facility Registry (FR) implementing "
            + igConfig.name + " Directory Actor. "
            + "Supports ITI-90 (Find Matching Care Services), "
            + "ITI-91 (Request Care Services Updates), and "
            + "ITI-130 (Care Services Feed).",
        "kind": "instance",
        "instantiates": instantiatesJson,
        "software": {
            "name": "wso2/FRCoreService",
            "version": igConfig.serverVersion
        },
        "implementation": {
            "description": "OpenHIE Facility Registry — FR Core Ballerina Service",
            "url": baseUrl + "/fhir"
        },
        "fhirVersion": igConfig.fhirVersion,
        "format": ["application/fhir+json", "application/json"],
        "rest": [
            {
                "mode": "server",
                "documentation": "FR Core " + igConfig.name + " Directory actor implementing ITI-90, ITI-91, ITI-130",
                "resource": resourceCapabilities
            }
        ]
    };
}

// Build a resource capability entry.
// searchParams is a json[] of {name, type, documentation} objects.
isolated function buildResourceCapability(
    string resourceType,
    string profile,
    json[] searchParams,
    string[] interactions,
    boolean supportsHistory
) returns json {
    json[] interactionList = [];
    foreach string interaction in interactions {
        interactionList.push({"code": interaction});
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
        "searchParam": searchParams
    };

    if operationList.length() > 0 {
        map<json> capMap = <map<json>>capability;
        capMap["operation"] = operationList;
        return capMap;
    }
    return capability;
}

// ─────────────────────────────────────────────────────────────────────────────
// Search parameter definitions per resource type — delegated to Search Registry.
//
// Queries the SearchParamRegistry (modules/search_registry/) and converts each
// SearchParamDef to the json shape expected by buildResourceCapability().
// ─────────────────────────────────────────────────────────────────────────────
function getSearchParamsForResource(string resourceType) returns json[] {
    search_registry:SearchParamDef[] defs = search_registry:getSearchParams(resourceType);
    json[] result = [];
    foreach search_registry:SearchParamDef def in defs {
        result.push({"name": def.name, "type": def.paramType, "documentation": def.expression});
    }
    return result;
}
