import ballerina/sql;
import ballerina/uuid;
import ballerinax/java.jdbc;
import healthcare_samples/mcsd_package;

// ─────────────────────────────────────────────────────────────
// ENDPOINT
// ─────────────────────────────────────────────────────────────
function createEndpoint(mcsd_package:MCSDEndpoint ep) returns string|error {
    string id = uuid:createType1AsString();
    json epJson = ep.toJson();
    string profile = getMcsdProfile("Endpoint", "");
    json stamped = check stampMeta(epJson, id, 1, profile);

    string status = ep.status;
    string connectionType = ep.connectionType.code ?: "";
    string address = ep.address;
    string? managingOrgId = ();
    json|error manOrgJson = epJson.managingOrganization;
    if manOrgJson is json {
        json|error ref = manOrgJson.reference;
        if ref is json {
            string[] parts = re `/`.split(ref.toString());
            managingOrgId = parts[parts.length() - 1];
        }
    }

    jdbc:Client db = check getDbClient();
    _ = check db->execute(`
        INSERT INTO endpoint (id, status, connection_type, managing_org_id, address_url, fhir_resource, last_updated)
        VALUES (${id}, ${status}, ${connectionType}, ${managingOrgId}, ${address}, ${stamped.toJsonString()}, NOW())
    `);
    check recordHistory("Endpoint", id, 1, "CREATE", stamped);
    return id;
}

function getEndpoint(string id) returns json|()|error {
    jdbc:Client db = check getDbClient();
    record {string fhir_resource;}|error row = db->queryRow(
        `SELECT fhir_resource FROM endpoint WHERE id = ${id} AND is_deleted = FALSE`);
    if row is record {string fhir_resource;} {
        return check row.fhir_resource.fromJsonString();
    }
    return ();
}

function searchEndpoints(EndpointSearchParams params) returns json[]|error {
    jdbc:Client db = check getDbClient();
    sql:ParameterizedQuery query = `SELECT fhir_resource FROM endpoint WHERE is_deleted = FALSE`;
    string? status = params.status;
    if status is string { query = sql:queryConcat(query, ` AND status = ${status}`); }
    query = sql:queryConcat(query, ` ORDER BY last_updated DESC LIMIT ${params._count} OFFSET ${params._offset}`);
    stream<record {string fhir_resource;}, sql:Error?> rs = db->query(query);
    return streamToJsonArray(rs);
}
