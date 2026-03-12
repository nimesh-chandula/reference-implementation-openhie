import ballerina/http;
import ballerina/log;

configurable string auditServiceUrl = "http://localhost:9096";

final http:Client auditProxyClient = check new (auditServiceUrl);

// GET /api/admin/hierarchy — Returns the organizational hierarchy tree
function handleGetHierarchy() returns json|error {
    return getHierarchyTree();
}

// GET /api/admin/statistics — Returns registry statistics
function handleGetStatistics() returns json|error {
    RegistryStats stats = check getStats();
    return {
        "totalOrganizations": stats.totalOrganizations,
        "totalLocations": stats.totalLocations,
        "totalHealthcareServices": stats.totalHealthcareServices,
        "totalEndpoints": stats.totalEndpoints,
        "activeOrganizations": stats.activeOrganizations,
        "activeLocations": stats.activeLocations,
        "facilitiesCount": stats.facilitiesCount,
        "jurisdictionsCount": stats.jurisdictionsCount
    };
}

// GET /api/admin/facilities/map — Returns a GeoJSON FeatureCollection for map display
function handleGetMapGeoJson() returns json|error {
    return getMapGeoJson();
}

// POST /api/admin/facilities/{id}/status — Update a facility's operational status
// Body: {"status": "inactive", "reason": "Facility closed"}
function handleUpdateStatus(string id, json body) returns json|error {
    json|error newStatusVal = body.status;
    if newStatusVal is error {
        return error("Missing 'status' field in request body");
    }
    string newStatus = newStatusVal.toString();

    // Try Location first, then Organization
    json|()|error locResult = getLocation(id);
    if locResult is json {
        map<json> locMap = check locResult.ensureType();
        locMap["status"] = newStatus;
        _ = check updateLocation(id, locMap);
        return {"updated": true, "resourceType": "Location", "id": id, "status": newStatus};
    }

    json|()|error orgResult = getOrganization(id);
    if orgResult is json {
        map<json> orgMap = check orgResult.ensureType();
        boolean activeVal = newStatus == "active";
        orgMap["active"] = activeVal;
        _ = check updateOrganization(id, orgMap);
        return {"updated": true, "resourceType": "Organization", "id": id, "active": activeVal};
    }

    return error("Resource not found: " + id);
}

// GET /api/admin/audit-logs — Proxy to audit-service /audits
function handleGetAuditLogs(http:Request req) returns json|error {
    http:Response|error response = auditProxyClient->/audits(
        action = req.getQueryParamValue("action") ?: "",
        subtype = req.getQueryParamValue("subtype") ?: "",
        since = req.getQueryParamValue("since") ?: "",
        before = req.getQueryParamValue("before") ?: ""
    );
    if response is error {
        log:printError("Failed to proxy audit-logs request", 'error = response);
        return error("Failed to retrieve audit logs: " + response.message());
    }
    json|error payload = response.getJsonPayload();
    if payload is error {
        return error("Failed to parse audit-service response");
    }
    return payload;
}
