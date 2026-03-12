import ballerina/sql;
import ballerina/uuid;
import ballerinax/java.jdbc;
import healthcare_samples/mcsd_package;

// ─────────────────────────────────────────────────────────────
// ORGANIZATION
// ─────────────────────────────────────────────────────────────
function createOrganization(mcsd_package:MCSDFacilityOrganization|mcsd_package:MCSDJurisdictionOrganization org) returns string|error {
    string id = uuid:createType1AsString();
    json orgJson = org.toJson();
    string typeCode = extractTypeCode(orgJson);
    string profile = getMcsdProfile("Organization", typeCode);
    json stamped = check stampMeta(orgJson, id, 1, profile);

    json|error nameVal = orgJson.name;
    string name = nameVal is json ? nameVal.toString() : "";

    string? partOfId = ();
    json|error partOfJson = orgJson.partOf;
    if partOfJson is json {
        json|error ref = partOfJson.reference;
        if ref is json {
            string[] parts = re `/`.split(ref.toString());
            partOfId = parts[parts.length() - 1];
        }
    }

    jdbc:Client db = check getDbClient();
    _ = check db->execute(`
        INSERT INTO organization (id, version_id, active, name, type_code, part_of_id, fhir_resource, last_updated, created_at)
        VALUES (${id}, 1, TRUE, ${name}, ${typeCode}, ${partOfId}, ${stamped.toJsonString()}, NOW(), NOW())
    `);
    check recordHistory("Organization", id, 1, "CREATE", stamped);
    return id;
}

function updateOrganization(string id, json orgJson) returns boolean|error {
    jdbc:Client db = check getDbClient();
    string typeCode = extractTypeCode(orgJson);
    json|error nameVal = orgJson.name;
    string name = nameVal is json ? nameVal.toString() : "";

    sql:ExecutionResult result = check db->execute(`
        UPDATE organization
        SET name = ${name}, type_code = ${typeCode},
            fhir_resource = ${orgJson.toJsonString()},
            last_updated = NOW(), version_id = version_id + 1
        WHERE id = ${id} AND is_deleted = FALSE
    `);
    if result.affectedRowCount == 0 {
        return false;
    }
    int ver = 1;
    record {int version_id;}|error vRow = db->queryRow(
        `SELECT version_id FROM organization WHERE id = ${id}`);
    if vRow is record {int version_id;} {
        ver = vRow.version_id;
    }
    check recordHistory("Organization", id, ver, "UPDATE", orgJson);
    return true;
}

function deleteOrganization(string id) returns boolean|error {
    jdbc:Client db = check getDbClient();
    sql:ExecutionResult result = check db->execute(`
        UPDATE organization SET is_deleted = TRUE, last_updated = NOW()
        WHERE id = ${id} AND is_deleted = FALSE
    `);
    if result.affectedRowCount == 0 { return false; }
    check recordHistory("Organization", id, 0, "DELETE", ());
    return true;
}

function getOrganization(string id) returns json|()|error {
    jdbc:Client db = check getDbClient();
    record {string fhir_resource;}|error row = db->queryRow(
        `SELECT fhir_resource FROM organization WHERE id = ${id} AND is_deleted = FALSE`);
    if row is record {string fhir_resource;} {
        return check row.fhir_resource.fromJsonString();
    }
    return ();
}

function searchOrganizations(OrgSearchParams params) returns json[]|error {
    jdbc:Client db = check getDbClient();
    sql:ParameterizedQuery query = `SELECT fhir_resource FROM organization WHERE is_deleted = FALSE`;
    query = applyOrgFilters(query, params);
    query = sql:queryConcat(query, ` ORDER BY last_updated DESC LIMIT ${params._count} OFFSET ${params._offset}`);
    stream<record {string fhir_resource;}, sql:Error?> rs = db->query(query);
    return streamToJsonArray(rs);
}

function countOrganizations(OrgSearchParams params) returns int|error {
    jdbc:Client db = check getDbClient();
    sql:ParameterizedQuery query = `SELECT COUNT(*) AS cnt FROM organization WHERE is_deleted = FALSE`;
    query = applyOrgFilters(query, params);
    record {int cnt;}|error row = db->queryRow(query);
    if row is record {int cnt;} { return row.cnt; }
    return 0;
}

isolated function applyOrgFilters(sql:ParameterizedQuery base, OrgSearchParams params) returns sql:ParameterizedQuery {
    sql:ParameterizedQuery q = base;
    string? id = params._id;
    if id is string { q = sql:queryConcat(q, ` AND id = ${id}`); }
    string? active = params.active;
    if active is string {
        boolean activeVal = active == "true";
        q = sql:queryConcat(q, ` AND active = ${activeVal}`);
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
    string? typeCode = params.'type;
    if typeCode is string { q = sql:queryConcat(q, ` AND type_code = ${typeCode}`); }
    string? partof = params.partof;
    if partof is string {
        string[] parts = re `/`.split(partof);
        string partofId = parts[parts.length() - 1];
        q = sql:queryConcat(q, ` AND part_of_id = ${partofId}`);
    }
    string? lastUpdated = params._lastUpdated;
    string? lastUpdatedPrefix = params._lastUpdatedPrefix;
    if lastUpdated is string {
        string dbTs = toDbTimestamp(lastUpdated);
        string prefix = lastUpdatedPrefix ?: "ge";
        if prefix == "gt" { q = sql:queryConcat(q, ` AND last_updated > ${dbTs}`); }
        else if prefix == "lt" { q = sql:queryConcat(q, ` AND last_updated < ${dbTs}`); }
        else if prefix == "ge" { q = sql:queryConcat(q, ` AND last_updated >= ${dbTs}`); }
        else if prefix == "le" { q = sql:queryConcat(q, ` AND last_updated <= ${dbTs}`); }
    }
    return q;
}
