import ballerina/sql;
import ballerina/uuid;
import ballerinax/java.jdbc;
import healthcare_samples/mcsd_package;
import wso2/FRCoreService.types;
import wso2/FRCoreService.db;
import wso2/FRCoreService.fhir_utils;

// ─────────────────────────────────────────────────────────────
// ORGANIZATION AFFILIATION
// ─────────────────────────────────────────────────────────────
public function createOrgAffiliation(mcsd_package:MCSDOrganizationAffiliation aff) returns string|error {
    string id = uuid:createType1AsString();
    json affJson = aff.toJson();
    string profile = fhir_utils:getMcsdProfile("OrganizationAffiliation", "");
    json stamped = check fhir_utils:stampMeta(affJson, id, 1, profile);

    boolean active = aff.active;
    string primaryOrgId = "";
    string participatingOrgId = "";
    json|error orgRef = affJson.organization;
    if orgRef is json {
        json|error ref = orgRef.reference;
        if ref is json {
            string[] parts = re `/`.split(ref.toString());
            primaryOrgId = parts[parts.length() - 1];
        }
    }
    json|error partRef = affJson.participatingOrganization;
    if partRef is json {
        json|error ref = partRef.reference;
        if ref is json {
            string[] parts = re `/`.split(ref.toString());
            participatingOrgId = parts[parts.length() - 1];
        }
    }

    jdbc:Client dbClient = check db:getDbClient();
    _ = check dbClient->execute(`
        INSERT INTO org_affiliation (id, active, primary_org_id, participating_org_id, fhir_resource, last_updated)
        VALUES (${id}, ${active}, ${primaryOrgId}, ${participatingOrgId}, ${stamped.toJsonString()}, NOW())
    `);
    check db:recordHistory("OrganizationAffiliation", id, 1, "CREATE", stamped);
    return id;
}

public function getOrgAffiliation(string id) returns json|()|error {
    jdbc:Client dbClient = check db:getDbClient();
    record {string fhir_resource;}|error row = dbClient->queryRow(
        `SELECT fhir_resource FROM org_affiliation WHERE id = ${id} AND is_deleted = FALSE`);
    if row is record {string fhir_resource;} {
        return check row.fhir_resource.fromJsonString();
    }
    return ();
}

public function searchOrgAffiliations(types:OrgAffiliationSearchParams params) returns json[]|error {
    jdbc:Client dbClient = check db:getDbClient();
    sql:ParameterizedQuery query = `SELECT fhir_resource FROM org_affiliation WHERE is_deleted = FALSE`;
    string? active = params.active;
    if active is string {
        boolean av = active == "true";
        query = sql:queryConcat(query, ` AND active = ${av}`);
    }
    query = sql:queryConcat(query, ` ORDER BY last_updated DESC LIMIT ${params._count} OFFSET ${params._offset}`);
    stream<record {string fhir_resource;}, sql:Error?> rs = dbClient->query(query);
    return db:streamToJsonArray(rs);
}
