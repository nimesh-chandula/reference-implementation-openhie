import ballerina/sql;
import ballerina/uuid;
import ballerinax/java.jdbc;
import healthcare_samples/mcsd_package;
import wso2/FRCoreService.types;
import wso2/FRCoreService.db;
import wso2/FRCoreService.fhir_utils;

// ─────────────────────────────────────────────────────────────
// LOCATION
// ─────────────────────────────────────────────────────────────
public function createLocation(mcsd_package:MCSDFacilityLocation|mcsd_package:MCSDJurisdictionLocation loc) returns string|error {
    string id = uuid:createType1AsString();
    json locJson = loc.toJson();
    string typeCode = fhir_utils:extractTypeCode(locJson);
    string profile = fhir_utils:getMcsdProfile("Location", typeCode);
    json stamped = check fhir_utils:stampMeta(locJson, id, 1, profile);

    json|error nameVal = stamped.name;
    string name = nameVal is json ? nameVal.toString() : "";

    json|error statusVal = stamped.status;
    string status = statusVal is json ? statusVal.toString() : "active";

    decimal? lat = ();
    decimal? lon = ();
    json|error posJson = stamped.position;
    if posJson is json {
        json|error latVal = posJson.latitude;
        json|error lonVal = posJson.longitude;
        if latVal is json { lat = check latVal.ensureType(decimal); }
        if lonVal is json { lon = check lonVal.ensureType(decimal); }
    }

    string? managingOrgId = ();
    json|error manOrgJson = stamped.managingOrganization;
    if manOrgJson is json {
        json|error ref = manOrgJson.reference;
        if ref is json {
            string[] parts = re `/`.split(ref.toString());
            managingOrgId = parts[parts.length() - 1];
        }
    }

    string? addressText = ();
    string? addressCity = ();
    string? addressState = ();
    string? addressCountry = ();
    json|error addrJson = stamped.address;
    if addrJson is json {
        json|error tv = addrJson.text; if tv is json { addressText = tv.toString(); }
        json|error cv = addrJson.city; if cv is json { addressCity = cv.toString(); }
        json|error sv = addrJson.state; if sv is json { addressState = sv.toString(); }
        json|error cov = addrJson.country; if cov is json { addressCountry = cov.toString(); }
    }

    jdbc:Client dbClient = check db:getDbClient();

    // Validate managing organization reference exists
    if managingOrgId is string {
        record {int cnt;}|error orgCheck = dbClient->queryRow(
            `SELECT COUNT(*) AS cnt FROM organization WHERE id = ${managingOrgId} AND is_deleted = FALSE`);
        if orgCheck is record {int cnt;} && orgCheck.cnt == 0 {
            return error("Referenced managingOrganization 'Organization/" + managingOrgId + "' does not exist");
        }
    }

    _ = check dbClient->execute(`
        INSERT INTO location (id, version_id, status, name, type_code, managing_org_id,
                              latitude, longitude, address_text, address_city, address_state,
                              address_country, fhir_resource, last_updated, created_at)
        VALUES (${id}, 1, ${status}, ${name}, ${typeCode}, ${managingOrgId},
                ${lat}, ${lon}, ${addressText}, ${addressCity}, ${addressState},
                ${addressCountry}, ${stamped.toJsonString()}, NOW(), NOW())
    `);
    check db:recordHistory("Location", id, 1, "CREATE", stamped);
    return id;
}

public function updateLocation(string id, json locJson) returns boolean|error {
    jdbc:Client dbClient = check db:getDbClient();
    json|error nameVal = locJson.name;
    string name = nameVal is json ? nameVal.toString() : "";
    json|error statusVal = locJson.status;
    string status = statusVal is json ? statusVal.toString() : "active";

    sql:ExecutionResult result = check dbClient->execute(`
        UPDATE location
        SET name = ${name}, status = ${status},
            fhir_resource = ${locJson.toJsonString()},
            last_updated = NOW(), version_id = version_id + 1
        WHERE id = ${id} AND is_deleted = FALSE
    `);
    if result.affectedRowCount == 0 { return false; }
    check db:recordHistory("Location", id, 0, "UPDATE", locJson);
    return true;
}

public function deleteLocation(string id) returns boolean|error {
    jdbc:Client dbClient = check db:getDbClient();
    sql:ExecutionResult result = check dbClient->execute(`
        UPDATE location SET is_deleted = TRUE, last_updated = NOW()
        WHERE id = ${id} AND is_deleted = FALSE
    `);
    if result.affectedRowCount == 0 { return false; }
    check db:recordHistory("Location", id, 0, "DELETE", ());
    return true;
}

public function getLocation(string id) returns json|()|error {
    jdbc:Client dbClient = check db:getDbClient();
    record {string fhir_resource;}|error row = dbClient->queryRow(
        `SELECT fhir_resource FROM location WHERE id = ${id} AND is_deleted = FALSE`);
    if row is record {string fhir_resource;} {
        return check row.fhir_resource.fromJsonString();
    }
    return ();
}

public function searchLocations(types:LocationSearchParams params) returns json[]|error {
    jdbc:Client dbClient = check db:getDbClient();
    sql:ParameterizedQuery query = `SELECT fhir_resource FROM location WHERE is_deleted = FALSE`;
    query = applyLocationFilters(query, params);
    query = sql:queryConcat(query, ` ORDER BY last_updated DESC LIMIT ${params._count} OFFSET ${params._offset}`);
    stream<record {string fhir_resource;}, sql:Error?> queryStream = dbClient->query(query);
    json[] results = check db:streamToJsonArray(queryStream);

    // Apply near filter (haversine in-process, DB does not have PostGIS here)
    string? near = params.near;
    if near is string {
        types:NearParam|error nearParam = fhir_utils:parseNearParam(near);
        if nearParam is types:NearParam {
            json[] filtered = [];
            foreach json entry in results {
                json|error posJson = entry.position;
                if posJson is json {
                    json|error latVal = posJson.latitude;
                    json|error lonVal = posJson.longitude;
                    if latVal is json && lonVal is json {
                        decimal|error entLat = latVal.ensureType(decimal);
                        decimal|error entLon = lonVal.ensureType(decimal);
                        if entLat is decimal && entLon is decimal {
                            decimal dist = fhir_utils:haversineKm(nearParam.lat, nearParam.lon, entLat, entLon);
                            if dist <= nearParam.distanceKm {
                                filtered.push(entry);
                            }
                        }
                    }
                }
            }
            results = filtered;
        }
    }
    return results;
}

public function countLocations(types:LocationSearchParams params) returns int|error {
    jdbc:Client dbClient = check db:getDbClient();
    sql:ParameterizedQuery query = `SELECT COUNT(*) AS cnt FROM location WHERE is_deleted = FALSE`;
    query = applyLocationFilters(query, params);
    record {int cnt;}|error row = dbClient->queryRow(query);
    if row is record {int cnt;} { return row.cnt; }
    return 0;
}

isolated function applyLocationFilters(sql:ParameterizedQuery base, types:LocationSearchParams params) returns sql:ParameterizedQuery {
    sql:ParameterizedQuery q = base;
    string? id = params._id;
    if id is string { q = sql:queryConcat(q, ` AND id = ${id}`); }
    string? status = params.status;
    if status is string { q = sql:queryConcat(q, ` AND status = ${status}`); }
    string? typeCode = params.'type;
    if typeCode is string { q = sql:queryConcat(q, ` AND type_code = ${typeCode}`); }
    string? org = params.organization;
    if org is string {
        string[] parts = re `/`.split(org);
        string orgId = parts[parts.length() - 1];
        q = sql:queryConcat(q, ` AND managing_org_id = ${orgId}`);
    }
    string? name = params.name;
    string? nameMod = params.nameModifier;
    if name is string {
        if nameMod == "contains" {
            string pattern = "%" + name.toLowerAscii() + "%";
            q = sql:queryConcat(q, ` AND LOWER(name) LIKE ${pattern}`);
        } else if nameMod == "exact" {
            q = sql:queryConcat(q, ` AND name = ${name}`);
        } else {
            string pattern = name.toLowerAscii() + "%";
            q = sql:queryConcat(q, ` AND LOWER(name) LIKE ${pattern}`);
        }
    }
    string? partof = params.partof;
    if partof is string {
        string[] parts = re `/`.split(partof);
        string partofId = parts[parts.length() - 1];
        q = sql:queryConcat(q, ` AND part_of_id = ${partofId}`);
    }
    string? lastUpdated = params._lastUpdated;
    string? lastUpdatedPrefix = params._lastUpdatedPrefix;
    if lastUpdated is string {
        string dbTs = db:toDbTimestamp(lastUpdated);
        string prefix = lastUpdatedPrefix ?: "ge";
        if prefix == "gt" { q = sql:queryConcat(q, ` AND last_updated > ${dbTs}`); }
        else if prefix == "lt" { q = sql:queryConcat(q, ` AND last_updated < ${dbTs}`); }
        else if prefix == "ge" { q = sql:queryConcat(q, ` AND last_updated >= ${dbTs}`); }
        else if prefix == "le" { q = sql:queryConcat(q, ` AND last_updated <= ${dbTs}`); }
    }
    return q;
}
