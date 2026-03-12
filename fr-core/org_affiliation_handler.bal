import ballerina/sql;
import ballerina/uuid;
import ballerinax/java.jdbc;
import healthcare_samples/mcsd_package;

// ─────────────────────────────────────────────────────────────
// ORGANIZATION AFFILIATION
// ─────────────────────────────────────────────────────────────
function createOrgAffiliation(mcsd_package:MCSDOrganizationAffiliation aff) returns string|error {
    string id = uuid:createType1AsString();
    json affJson = aff.toJson();
    string profile = getMcsdProfile("OrganizationAffiliation", "");
    json stamped = check stampMeta(affJson, id, 1, profile);

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

    jdbc:Client db = check getDbClient();
    _ = check db->execute(`
        INSERT INTO org_affiliation (id, active, primary_org_id, participating_org_id, fhir_resource, last_updated)
        VALUES (${id}, ${active}, ${primaryOrgId}, ${participatingOrgId}, ${stamped.toJsonString()}, NOW())
    `);
    check recordHistory("OrganizationAffiliation", id, 1, "CREATE", stamped);
    return id;
}

function getOrgAffiliation(string id) returns json|()|error {
    jdbc:Client db = check getDbClient();
    record {string fhir_resource;}|error row = db->queryRow(
        `SELECT fhir_resource FROM org_affiliation WHERE id = ${id} AND is_deleted = FALSE`);
    if row is record {string fhir_resource;} {
        return check row.fhir_resource.fromJsonString();
    }
    return ();
}

function searchOrgAffiliations(OrgAffiliationSearchParams params) returns json[]|error {
    jdbc:Client db = check getDbClient();
    sql:ParameterizedQuery query = `SELECT fhir_resource FROM org_affiliation WHERE is_deleted = FALSE`;
    string? active = params.active;
    if active is string {
        boolean av = active == "true";
        query = sql:queryConcat(query, ` AND active = ${av}`);
    }
    query = sql:queryConcat(query, ` ORDER BY last_updated DESC LIMIT ${params._count} OFFSET ${params._offset}`);
    stream<record {string fhir_resource;}, sql:Error?> rs = db->query(query);
    return streamToJsonArray(rs);
}
