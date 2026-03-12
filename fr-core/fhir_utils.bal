import ballerina/uuid;
import ballerina/time;

// Build a FHIR R4 searchset Bundle from an array of resource JSON entries
function buildSearchBundle(string resourceType, json[] entries, int total, string selfUrl) returns json {
    string bundleId = uuid:createType1AsString();
    string now = time:utcToString(time:utcNow());

    int? qIdx = selfUrl.indexOf("?");
    string baseUrl = qIdx is int ? selfUrl.substring(0, qIdx) : selfUrl;
    if baseUrl.endsWith("/") {
        baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
    }

    json[] bundleEntries = [];
    foreach json entry in entries {
        json|error idVal = entry.id;
        string resourceId = idVal is json ? idVal.toString() : "";
        bundleEntries.push({
            "fullUrl": baseUrl + "/" + resourceType + "/" + resourceId,
            "resource": entry,
            "search": {"mode": "match"}
        });
    }

    return {
        "resourceType": "Bundle",
        "id": bundleId,
        "meta": {"lastUpdated": now},
        "type": "searchset",
        "total": total,
        "link": [{"relation": "self", "url": selfUrl}],
        "entry": bundleEntries
    };
}

// Build a FHIR R4 history Bundle per ITI-91
function buildHistoryBundle(HistoryRow[] rows, string resourceType, string baseUrl) returns json {
    string bundleId = uuid:createType1AsString();
    string now = time:utcToString(time:utcNow());

    json[] bundleEntries = [];
    foreach HistoryRow row in rows {
        string resourceUrl = baseUrl + "/" + resourceType + "/" + row.resourceId;
        string versionUrl = resourceUrl + "/_history/" + row.versionId.toString();

        json entry;
        if row.action == "DELETE" {
            entry = {
                "fullUrl": versionUrl,
                "request": {
                    "method": "DELETE",
                    "url": resourceType + "/" + row.resourceId
                },
                "response": {
                    "status": "204 No Content"
                }
            };
        } else {
            string method = row.action == "CREATE" ? "POST" : "PUT";
            json resourceJson = {};
            string? fhirRes = row.fhirResource;
            if fhirRes is string {
                json|error parsed = fhirRes.fromJsonString();
                if parsed is json {
                    resourceJson = parsed;
                }
            }
            entry = {
                "fullUrl": versionUrl,
                "resource": resourceJson,
                "request": {
                    "method": method,
                    "url": resourceType + (row.action == "CREATE" ? "" : "/" + row.resourceId)
                },
                "response": {
                    "status": row.action == "CREATE" ? "201 Created" : "200 OK",
                    "lastModified": row.timestamp
                }
            };
        }
        bundleEntries.push(entry);
    }

    return {
        "resourceType": "Bundle",
        "id": bundleId,
        "meta": {"lastUpdated": now},
        "type": "history",
        "total": bundleEntries.length(),
        "entry": bundleEntries
    };
}

// Build a FHIR R4 OperationOutcome for error responses
function buildOperationOutcome(string severity, string code, string diagnostics) returns json {
    return {
        "resourceType": "OperationOutcome",
        "issue": [
            {
                "severity": severity,
                "code": code,
                "diagnostics": diagnostics
            }
        ]
    };
}

// Stamp FHIR meta fields onto a resource JSON
// Returns updated JSON with meta.versionId, meta.lastUpdated, meta.profile[], id
function stampMeta(json 'resource, string id, int versionId, string profile) returns json|error {
    string now = time:utcToString(time:utcNow());

    // Build the updated map
    map<json> resourceMap = check 'resource.ensureType();
    resourceMap["id"] = id;
    resourceMap["meta"] = {
        "versionId": versionId.toString(),
        "lastUpdated": now,
        "profile": [profile]
    };
    return resourceMap;
}

// Return the mCSD StructureDefinition profile URI for a given resource type + type code
function getMcsdProfile(string resourceType, string typeCode) returns string {
    if resourceType == "Location" {
        if typeCode == "jurisdiction" {
            return "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.JurisdictionLocation";
        }
        return "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.FacilityLocation";
    } else if resourceType == "Organization" {
        if typeCode == "jurisdiction" {
            return "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.JurisdictionOrganization";
        }
        return "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.FacilityOrganization";
    } else if resourceType == "HealthcareService" {
        return "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.HealthcareService";
    } else if resourceType == "Endpoint" {
        return "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.Endpoint";
    } else if resourceType == "OrganizationAffiliation" {
        return "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.OrganizationAffiliation";
    }
    return "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.Location";
}

// Parse a FHIR _lastUpdated parameter like "gt2026-01-01T00:00:00Z" into prefix + value
function parseLastUpdated(string raw) returns LastUpdatedFilter {
    string[] prefixes = ["gt", "lt", "ge", "le", "sa", "eb", "ne"];
    foreach string prefix in prefixes {
        if raw.startsWith(prefix) {
            return {prefix: prefix, value: raw.substring(prefix.length())};
        }
    }
    // No prefix: treat as exact match using "ge" semantics
    return {prefix: "ge", value: raw};
}

// Extract the type code ("facility" | "jurisdiction") from the first type coding of a FHIR resource
function extractTypeCode(json res) returns string {
    json|error typeArr = res.'type;
    if typeArr is json[] && typeArr.length() > 0 {
        json|error codings = typeArr[0].coding;
        if codings is json[] && codings.length() > 0 {
            json|error code = codings[0].code;
            if code is json {
                string codeStr = code.toString();
                if codeStr == "jurisdiction" {
                    return "jurisdiction";
                }
            }
        }
    }
    return "facility";
}

// Apply SQL comparison for _lastUpdated filter given a field value and filter
function matchesLastUpdated(string fieldValue, LastUpdatedFilter filter) returns boolean {
    string prefix = filter.prefix;
    string filterVal = filter.value;
    if prefix == "gt" {
        return fieldValue > filterVal;
    } else if prefix == "lt" {
        return fieldValue < filterVal;
    } else if prefix == "ge" {
        return fieldValue >= filterVal;
    } else if prefix == "le" {
        return fieldValue <= filterVal;
    } else if prefix == "sa" {
        return fieldValue > filterVal;
    } else if prefix == "eb" {
        return fieldValue < filterVal;
    }
    return fieldValue == filterVal;
}

// Haversine distance in km between two lat/lon points (for in-memory near search)
function haversineKm(decimal lat1, decimal lon1, decimal lat2, decimal lon2) returns decimal {
    decimal r = 6371.0d;
    decimal dLat = (lat2 - lat1) * 3.14159265358979d / 180.0d;
    decimal dLon = (lon2 - lon1) * 3.14159265358979d / 180.0d;
    decimal a = 0.0d;
    // Simplified approximation using small angle: distance ≈ R * sqrt(dLat² + cos(lat)*dLon²)
    decimal cosLat = 1.0d - (lat1 * 3.14159265358979d / 180.0d) * (lat1 * 3.14159265358979d / 180.0d) / 2.0d;
    a = dLat * dLat + cosLat * cosLat * dLon * dLon;
    return r * <decimal>(<float>a).sqrt();
}
