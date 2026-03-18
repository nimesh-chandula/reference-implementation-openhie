import ballerina/sql;
import ballerina/uuid;
import ballerinax/java.jdbc;
import healthcare_samples/mcsd_package;
import wso2/FRCoreService.types;
import wso2/FRCoreService.db;
import wso2/FRCoreService.fhir_utils;

// ─────────────────────────────────────────────────────────────
// HEALTHCARE SERVICE
// ─────────────────────────────────────────────────────────────
public function createHealthcareService(mcsd_package:MCSDHealthcareService svc) returns string|error {
    string id = uuid:createType1AsString();
    json svcJson = svc.toJson();
    string profile = fhir_utils:getMcsdProfile("HealthcareService", "");
    json stamped = check fhir_utils:stampMeta(svcJson, id, 1, profile);

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

    jdbc:Client dbClient = check db:getDbClient();
    _ = check dbClient->execute(`
        INSERT INTO healthcare_service (id, version_id, active, name, provided_by_id, fhir_resource, last_updated, created_at)
        VALUES (${id}, 1, TRUE, ${name}, ${providedById}, ${stamped.toJsonString()}, NOW(), NOW())
    `);
    check db:recordHistory("HealthcareService", id, 1, "CREATE", stamped);
    return id;
}

public function updateHealthcareService(string id, json svcJson) returns boolean|error {
    jdbc:Client dbClient = check db:getDbClient();
    json|error nameVal = svcJson.name;
    string name = nameVal is json ? nameVal.toString() : "";

    sql:ExecutionResult result = check dbClient->execute(`
        UPDATE healthcare_service
        SET name = ${name}, fhir_resource = ${svcJson.toJsonString()},
            last_updated = NOW(), version_id = version_id + 1
        WHERE id = ${id} AND is_deleted = FALSE
    `);
    if result.affectedRowCount == 0 { return false; }
    check db:recordHistory("HealthcareService", id, 0, "UPDATE", svcJson);
    return true;
}

public function deleteHealthcareService(string id) returns boolean|error {
    jdbc:Client dbClient = check db:getDbClient();
    sql:ExecutionResult result = check dbClient->execute(`
        UPDATE healthcare_service SET is_deleted = TRUE, last_updated = NOW()
        WHERE id = ${id} AND is_deleted = FALSE
    `);
    if result.affectedRowCount == 0 { return false; }
    check db:recordHistory("HealthcareService", id, 0, "DELETE", ());
    return true;
}

public function getHealthcareService(string id) returns json|()|error {
    jdbc:Client dbClient = check db:getDbClient();
    record {string fhir_resource;}|error row = dbClient->queryRow(
        `SELECT fhir_resource FROM healthcare_service WHERE id = ${id} AND is_deleted = FALSE`);
    if row is record {string fhir_resource;} {
        return check row.fhir_resource.fromJsonString();
    }
    return ();
}

public function searchHealthcareServices(types:HealthcareServiceSearchParams params) returns json[]|error {
    jdbc:Client dbClient = check db:getDbClient();
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
    stream<record {string fhir_resource;}, sql:Error?> rs = dbClient->query(query);
    return db:streamToJsonArray(rs);
}
