import ballerina/sql;
import ballerina/uuid;
import ballerinax/java.jdbc;
import healthcare_samples/mcsd_package;

// ─────────────────────────────────────────────────────────────
// HEALTHCARE SERVICE
// ─────────────────────────────────────────────────────────────
function createHealthcareService(mcsd_package:MCSDHealthcareService svc) returns string|error {
    string id = uuid:createType1AsString();
    json svcJson = svc.toJson();
    string profile = getMcsdProfile("HealthcareService", "");
    json stamped = check stampMeta(svcJson, id, 1, profile);

    string name = svc.name;
    string? providedById = ();
    json|error provJson = svcJson.providedBy;
    if provJson is json {
        json|error ref = provJson.reference;
        if ref is json {
            string[] parts = re `/`.split(ref.toString());
            providedById = parts[parts.length() - 1];
        }
    }

    jdbc:Client db = check getDbClient();
    _ = check db->execute(`
        INSERT INTO healthcare_service (id, version_id, active, name, provided_by_id, fhir_resource, last_updated, created_at)
        VALUES (${id}, 1, TRUE, ${name}, ${providedById}, ${stamped.toJsonString()}, NOW(), NOW())
    `);
    check recordHistory("HealthcareService", id, 1, "CREATE", stamped);
    return id;
}

function updateHealthcareService(string id, json svcJson) returns boolean|error {
    jdbc:Client db = check getDbClient();
    json|error nameVal = svcJson.name;
    string name = nameVal is json ? nameVal.toString() : "";

    sql:ExecutionResult result = check db->execute(`
        UPDATE healthcare_service
        SET name = ${name}, fhir_resource = ${svcJson.toJsonString()},
            last_updated = NOW(), version_id = version_id + 1
        WHERE id = ${id} AND is_deleted = FALSE
    `);
    if result.affectedRowCount == 0 { return false; }
    check recordHistory("HealthcareService", id, 0, "UPDATE", svcJson);
    return true;
}

function deleteHealthcareService(string id) returns boolean|error {
    jdbc:Client db = check getDbClient();
    sql:ExecutionResult result = check db->execute(`
        UPDATE healthcare_service SET is_deleted = TRUE, last_updated = NOW()
        WHERE id = ${id} AND is_deleted = FALSE
    `);
    if result.affectedRowCount == 0 { return false; }
    check recordHistory("HealthcareService", id, 0, "DELETE", ());
    return true;
}

function getHealthcareService(string id) returns json|()|error {
    jdbc:Client db = check getDbClient();
    record {string fhir_resource;}|error row = db->queryRow(
        `SELECT fhir_resource FROM healthcare_service WHERE id = ${id} AND is_deleted = FALSE`);
    if row is record {string fhir_resource;} {
        return check row.fhir_resource.fromJsonString();
    }
    return ();
}

function searchHealthcareServices(HealthcareServiceSearchParams params) returns json[]|error {
    jdbc:Client db = check getDbClient();
    sql:ParameterizedQuery query = `SELECT fhir_resource FROM healthcare_service WHERE is_deleted = FALSE`;
    string? active = params.active;
    if active is string {
        boolean av = active == "true";
        query = sql:queryConcat(query, ` AND active = ${av}`);
    }
    string? name = params.name;
    string? nameMod = params.nameModifier;
    if name is string {
        if nameMod == "contains" {
            string pattern = "%" + name.toLowerAscii() + "%";
            query = sql:queryConcat(query, ` AND LOWER(name) LIKE ${pattern}`);
        } else if nameMod == "exact" {
            query = sql:queryConcat(query, ` AND name = ${name}`);
        } else {
            string pattern = name.toLowerAscii() + "%";
            query = sql:queryConcat(query, ` AND LOWER(name) LIKE ${pattern}`);
        }
    }
    query = sql:queryConcat(query, ` ORDER BY last_updated DESC LIMIT ${params._count} OFFSET ${params._offset}`);
    stream<record {string fhir_resource;}, sql:Error?> rs = db->query(query);
    return streamToJsonArray(rs);
}
