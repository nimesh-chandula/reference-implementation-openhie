import ballerina/uuid;
import ballerina/time;
import ballerinax/health.fhir.r4;
import wso2/FRCoreService.fhir_utils;
import wso2/FRCoreService.search_registry;
import wso2/FRCoreService.r4_api_config;

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
// Pure function: accepts IGConfig as parameter so it can be unit-tested without module-level I/O.
function buildCapabilityStatement(string baseUrl, fhir_utils:IGConfig igConfig) returns json {
    // Build the resource capability entries — profile URLs via profileAdapter
    json[] resourceCapabilities = [];
    foreach fhir_utils:IGResourceConfig rc in igConfig.resources {
        string profile = fhir_utils:profileAdapter.getProfileUrl(rc.resourceType, "");
        json[] searchParams = getSearchParamsForResource(rc.resourceType);
        resourceCapabilities.push(
            buildResourceCapability(
                rc.resourceType,
                profile,
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

    // Build transaction description from enabled transactions only (igConfig.transactions)
    string[] txParts = [];
    if igConfig.transactions.iti90 {
        txParts.push("ITI-90 (Find Matching Care Services)");
    }
    if igConfig.transactions.iti91 {
        txParts.push("ITI-91 (Request Care Services Updates)");
    }
    if igConfig.transactions.iti130 {
        txParts.push("ITI-130 (Care Services Feed)");
    }
    string txDesc = buildTxDescription(txParts);

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
            + igConfig.name + " Directory Actor." + txDesc,
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
                "documentation": "FR Core " + igConfig.name + " Directory actor." + txDesc,
                "resource": resourceCapabilities
            }
        ]
    };
}

// Join enabled transaction names into a human-readable sentence fragment.
// Returns "" if no transactions are enabled.
isolated function buildTxDescription(string[] txParts) returns string {
    if txParts.length() == 0 {
        return "";
    }
    string joined = "";
    foreach int i in 0 ..< txParts.length() {
        if i > 0 {
            joined += ", ";
        }
        joined += txParts[i];
    }
    return " Supports " + joined + ".";
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
// Search parameter definitions per resource type.
//
// Param names come from r4_api_config (single source of truth — same config
// that drives the FHIR server routing). paramType + expression come from
// search_registry metadata. Adding a param to r4_api_config automatically
// makes it appear here with no registry change required.
// ─────────────────────────────────────────────────────────────────────────────
function getSearchParamsForResource(string resourceType) returns json[] {
    r4:ResourceAPIConfig? apiCfg = r4_api_config:getResourceApiConfig(resourceType);
    if apiCfg is () {
        return [];
    }
    json[] result = [];
    foreach var sp in apiCfg.searchParameters {
        if sp.active {
            search_registry:SearchParamMeta meta = search_registry:getParamMeta(sp.name);
            result.push({"name": sp.name, "type": meta.paramType, "documentation": meta.expression});
        }
    }
    return result;
}
