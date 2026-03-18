import ballerina/sql;
import ballerina/uuid;
import ballerinax/java.jdbc;
import wso2/FRCoreService.types;
import wso2/FRCoreService.db;
import wso2/FRCoreService.fhir_utils;
import wso2/FRCoreService.history;

// ─────────────────────────────────────────────────────────────────────────────
// FhirRepository Interface — Repository Abstraction / Strategy Pattern (§3.3)
//
// Defines the contract for all storage backends. The rest of the service
// depends only on this interface — it never references SQL or a specific DB.
//
// DB backend (H2 for dev, PostgreSQL for prod) is selected transparently
// via Config.toml through the DatabaseProvider strategy in modules/db/.
// ─────────────────────────────────────────────────────────────────────────────

public type FhirRepository object {

    // ── ITI-130: Create ───────────────────────────────────────────────────────
    public function createResource(string resourceType, json 'resource) returns json|error;

    // ── ITI-130: Read ─────────────────────────────────────────────────────────
    public function readResource(string resourceType, string id) returns json|error;

    // ── ITI-130: Update ───────────────────────────────────────────────────────
    public function updateResource(string resourceType, string id, json 'resource) returns json|error;

    // ── ITI-130: Delete (soft) ────────────────────────────────────────────────
    public function deleteResource(string resourceType, string id) returns error?;

    // ── ITI-90: Search ────────────────────────────────────────────────────────
    public function searchResources(string resourceType, map<string[]> params) returns json[]|error;

    // ── ITI-90: Count ─────────────────────────────────────────────────────────
    public function countResources(string resourceType, map<string[]> params) returns int|error;

    // ── ITI-91: Type-level history ────────────────────────────────────────────
    public function getTypeHistory(string resourceType, string? since) returns types:HistoryRow[]|error;

    // ── ITI-91: Instance history ──────────────────────────────────────────────
    public function getInstanceHistory(string resourceType, string id) returns types:HistoryRow[]|error;
};

// ─────────────────────────────────────────────────────────────────────────────
// DatabaseFhirRepository — Concrete implementation.
// Delegates to modules/db/ for all storage. H2 / PostgreSQL is selected
// transparently via Config.toml — no changes needed here when switching DBs.
// ─────────────────────────────────────────────────────────────────────────────
public class DatabaseFhirRepository {
    *FhirRepository;

    public function createResource(string resourceType, json 'resource) returns json|error {
        string id = uuid:createType1AsString();
        string typeCode = fhir_utils:extractTypeCode('resource);
        string profile = fhir_utils:getMcsdProfile(resourceType, typeCode);
        json stamped = check fhir_utils:stampMeta('resource, id, 1, profile);
        jdbc:Client dbClient = check db:getDbClient();
        string stampedStr = stamped.toJsonString();

        if resourceType == "Organization" {
            string name = jsonStr(stamped, "name", "Unknown");
            string? partOfId = extractRefId(stamped, "partOf");
            _ = check dbClient->execute(`
                INSERT INTO organization (id, version_id, active, name, type_code, part_of_id, fhir_resource, last_updated, created_at)
                VALUES (${id}, 1, TRUE, ${name}, ${typeCode}, ${partOfId}, ${stampedStr}, NOW(), NOW())
            `);
        } else if resourceType == "Location" {
            string name = jsonStr(stamped, "name", "Unknown");
            string status = jsonStr(stamped, "status", "active");
            _ = check dbClient->execute(`
                INSERT INTO location (id, version_id, status, name, type_code, fhir_resource, last_updated, created_at)
                VALUES (${id}, 1, ${status}, ${name}, ${typeCode}, ${stampedStr}, NOW(), NOW())
            `);
        } else if resourceType == "HealthcareService" {
            string name = jsonStr(stamped, "name", "Unknown");
            _ = check dbClient->execute(`
                INSERT INTO healthcare_service (id, version_id, active, name, fhir_resource, last_updated, created_at)
                VALUES (${id}, 1, TRUE, ${name}, ${stampedStr}, NOW(), NOW())
            `);
        } else if resourceType == "Endpoint" {
            string status = jsonStr(stamped, "status", "active");
            string connType = extractEndpointConnType(stamped);
            string address = jsonStr(stamped, "address", "");
            _ = check dbClient->execute(`
                INSERT INTO endpoint (id, status, connection_type, address_url, fhir_resource, last_updated)
                VALUES (${id}, ${status}, ${connType}, ${address}, ${stampedStr}, NOW())
            `);
        } else if resourceType == "OrganizationAffiliation" {
            string primaryOrgId = extractRefId(stamped, "organization") ?: "";
            string participatingOrgId = extractRefId(stamped, "participatingOrganization") ?: "";
            _ = check dbClient->execute(`
                INSERT INTO org_affiliation (id, active, primary_org_id, participating_org_id, fhir_resource, last_updated)
                VALUES (${id}, TRUE, ${primaryOrgId}, ${participatingOrgId}, ${stampedStr}, NOW())
            `);
        } else {
            return error("Unsupported resource type: " + resourceType);
        }

        check db:recordHistory(resourceType, id, 1, "CREATE", stamped);
        return stamped;
    }

    public function readResource(string resourceType, string id) returns json|error {
        jdbc:Client dbClient = check db:getDbClient();
        record {string fhir_resource;}|error row;

        if resourceType == "Organization" {
            row = dbClient->queryRow(`SELECT fhir_resource FROM organization WHERE id = ${id} AND is_deleted = FALSE`);
        } else if resourceType == "Location" {
            row = dbClient->queryRow(`SELECT fhir_resource FROM location WHERE id = ${id} AND is_deleted = FALSE`);
        } else if resourceType == "HealthcareService" {
            row = dbClient->queryRow(`SELECT fhir_resource FROM healthcare_service WHERE id = ${id} AND is_deleted = FALSE`);
        } else if resourceType == "Endpoint" {
            row = dbClient->queryRow(`SELECT fhir_resource FROM endpoint WHERE id = ${id} AND is_deleted = FALSE`);
        } else if resourceType == "OrganizationAffiliation" {
            row = dbClient->queryRow(`SELECT fhir_resource FROM org_affiliation WHERE id = ${id} AND is_deleted = FALSE`);
        } else {
            return error("Unsupported resource type: " + resourceType);
        }

        if row is record {string fhir_resource;} {
            return check row.fhir_resource.fromJsonString();
        }
        return error(resourceType + "/" + id + " not found");
    }

    public function updateResource(string resourceType, string id, json 'resource) returns json|error {
        jdbc:Client dbClient = check db:getDbClient();
        string resourceStr = 'resource.toJsonString();
        sql:ExecutionResult result;
        int newVersion = 1;

        if resourceType == "Organization" {
            string name = jsonStr('resource, "name", "Unknown");
            string typeCode = fhir_utils:extractTypeCode('resource);
            result = check dbClient->execute(`
                UPDATE organization SET name = ${name}, type_code = ${typeCode},
                    fhir_resource = ${resourceStr}, last_updated = NOW(), version_id = version_id + 1
                WHERE id = ${id} AND is_deleted = FALSE
            `);
            record {int version_id;}|error vRow = dbClient->queryRow(`SELECT version_id FROM organization WHERE id = ${id}`);
            if vRow is record {int version_id;} { newVersion = vRow.version_id; }
        } else if resourceType == "Location" {
            string name = jsonStr('resource, "name", "Unknown");
            string status = jsonStr('resource, "status", "active");
            result = check dbClient->execute(`
                UPDATE location SET name = ${name}, status = ${status},
                    fhir_resource = ${resourceStr}, last_updated = NOW(), version_id = version_id + 1
                WHERE id = ${id} AND is_deleted = FALSE
            `);
            record {int version_id;}|error vRow = dbClient->queryRow(`SELECT version_id FROM location WHERE id = ${id}`);
            if vRow is record {int version_id;} { newVersion = vRow.version_id; }
        } else if resourceType == "HealthcareService" {
            string name = jsonStr('resource, "name", "Unknown");
            result = check dbClient->execute(`
                UPDATE healthcare_service SET name = ${name},
                    fhir_resource = ${resourceStr}, last_updated = NOW(), version_id = version_id + 1
                WHERE id = ${id} AND is_deleted = FALSE
            `);
            record {int version_id;}|error vRow = dbClient->queryRow(`SELECT version_id FROM healthcare_service WHERE id = ${id}`);
            if vRow is record {int version_id;} { newVersion = vRow.version_id; }
        } else if resourceType == "Endpoint" {
            string status = jsonStr('resource, "status", "active");
            string connType = extractEndpointConnType('resource);
            string address = jsonStr('resource, "address", "");
            result = check dbClient->execute(`
                UPDATE endpoint SET status = ${status}, connection_type = ${connType},
                    address_url = ${address}, fhir_resource = ${resourceStr}, last_updated = NOW()
                WHERE id = ${id} AND is_deleted = FALSE
            `);
        } else if resourceType == "OrganizationAffiliation" {
            result = check dbClient->execute(`
                UPDATE org_affiliation SET fhir_resource = ${resourceStr}, last_updated = NOW()
                WHERE id = ${id} AND is_deleted = FALSE
            `);
        } else {
            return error("Unsupported resource type: " + resourceType);
        }

        if result.affectedRowCount == 0 {
            return error(resourceType + "/" + id + " not found");
        }
        check db:recordHistory(resourceType, id, newVersion, "UPDATE", 'resource);
        return 'resource;
    }

    public function deleteResource(string resourceType, string id) returns error? {
        jdbc:Client dbClient = check db:getDbClient();
        sql:ExecutionResult result;

        if resourceType == "Organization" {
            result = check dbClient->execute(`UPDATE organization SET is_deleted = TRUE, last_updated = NOW() WHERE id = ${id} AND is_deleted = FALSE`);
        } else if resourceType == "Location" {
            result = check dbClient->execute(`UPDATE location SET is_deleted = TRUE, last_updated = NOW() WHERE id = ${id} AND is_deleted = FALSE`);
        } else if resourceType == "HealthcareService" {
            result = check dbClient->execute(`UPDATE healthcare_service SET is_deleted = TRUE, last_updated = NOW() WHERE id = ${id} AND is_deleted = FALSE`);
        } else if resourceType == "Endpoint" {
            result = check dbClient->execute(`UPDATE endpoint SET is_deleted = TRUE, last_updated = NOW() WHERE id = ${id} AND is_deleted = FALSE`);
        } else if resourceType == "OrganizationAffiliation" {
            result = check dbClient->execute(`UPDATE org_affiliation SET is_deleted = TRUE, last_updated = NOW() WHERE id = ${id} AND is_deleted = FALSE`);
        } else {
            return error("Unsupported resource type: " + resourceType);
        }

        if result.affectedRowCount == 0 {
            return error(resourceType + "/" + id + " not found");
        }
        check db:recordHistory(resourceType, id, 0, "DELETE", ());
    }

    public function searchResources(string resourceType, map<string[]> params) returns json[]|error {
        jdbc:Client dbClient = check db:getDbClient();
        string[]? idVals = params["_id"];
        string? idFilter = idVals is string[] && idVals.length() > 0 ? idVals[0] : ();

        sql:ParameterizedQuery q;
        if resourceType == "Organization" {
            q = `SELECT fhir_resource FROM organization WHERE is_deleted = FALSE`;
        } else if resourceType == "Location" {
            q = `SELECT fhir_resource FROM location WHERE is_deleted = FALSE`;
        } else if resourceType == "HealthcareService" {
            q = `SELECT fhir_resource FROM healthcare_service WHERE is_deleted = FALSE`;
        } else if resourceType == "Endpoint" {
            q = `SELECT fhir_resource FROM endpoint WHERE is_deleted = FALSE`;
        } else if resourceType == "OrganizationAffiliation" {
            q = `SELECT fhir_resource FROM org_affiliation WHERE is_deleted = FALSE`;
        } else {
            return error("Unsupported resource type: " + resourceType);
        }
        if idFilter is string { q = sql:queryConcat(q, ` AND id = ${idFilter}`); }
        stream<record {string fhir_resource;}, sql:Error?> rs = dbClient->query(q);
        return db:streamToJsonArray(rs);
    }

    public function countResources(string resourceType, map<string[]> params) returns int|error {
        jdbc:Client dbClient = check db:getDbClient();
        string[]? idVals = params["_id"];
        string? idFilter = idVals is string[] && idVals.length() > 0 ? idVals[0] : ();

        if resourceType == "Organization" {
            sql:ParameterizedQuery q = `SELECT COUNT(*) AS cnt FROM organization WHERE is_deleted = FALSE`;
            if idFilter is string { q = sql:queryConcat(q, ` AND id = ${idFilter}`); }
            record {int cnt;}|error row = dbClient->queryRow(q);
            if row is record {int cnt;} { return row.cnt; }
        } else if resourceType == "Location" {
            sql:ParameterizedQuery q = `SELECT COUNT(*) AS cnt FROM location WHERE is_deleted = FALSE`;
            if idFilter is string { q = sql:queryConcat(q, ` AND id = ${idFilter}`); }
            record {int cnt;}|error row = dbClient->queryRow(q);
            if row is record {int cnt;} { return row.cnt; }
        } else if resourceType == "HealthcareService" {
            sql:ParameterizedQuery q = `SELECT COUNT(*) AS cnt FROM healthcare_service WHERE is_deleted = FALSE`;
            if idFilter is string { q = sql:queryConcat(q, ` AND id = ${idFilter}`); }
            record {int cnt;}|error row = dbClient->queryRow(q);
            if row is record {int cnt;} { return row.cnt; }
        } else if resourceType == "Endpoint" {
            sql:ParameterizedQuery q = `SELECT COUNT(*) AS cnt FROM endpoint WHERE is_deleted = FALSE`;
            if idFilter is string { q = sql:queryConcat(q, ` AND id = ${idFilter}`); }
            record {int cnt;}|error row = dbClient->queryRow(q);
            if row is record {int cnt;} { return row.cnt; }
        } else if resourceType == "OrganizationAffiliation" {
            sql:ParameterizedQuery q = `SELECT COUNT(*) AS cnt FROM org_affiliation WHERE is_deleted = FALSE`;
            if idFilter is string { q = sql:queryConcat(q, ` AND id = ${idFilter}`); }
            record {int cnt;}|error row = dbClient->queryRow(q);
            if row is record {int cnt;} { return row.cnt; }
        } else {
            return error("Unsupported resource type: " + resourceType);
        }
        return 0;
    }

    public function getTypeHistory(string resourceType, string? since) returns types:HistoryRow[]|error {
        return history:getResourceHistory(resourceType, since);
    }

    public function getInstanceHistory(string resourceType, string id) returns types:HistoryRow[]|error {
        jdbc:Client dbClient = check db:getDbClient();
        types:HistoryRow[] rows = [];
        stream<types:HistoryRow, sql:Error?> rs = dbClient->query(`
            SELECT resource_id AS "resourceId", version_id AS "versionId",
                   action, fhir_resource AS "fhirResource",
                   CAST(timestamp AS VARCHAR) AS "timestamp"
            FROM resource_history
            WHERE resource_type = ${resourceType} AND resource_id = ${id}
            ORDER BY timestamp ASC
        `);
        check from types:HistoryRow row in rs do { rows.push(row); };
        return rows;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Factory
// ─────────────────────────────────────────────────────────────────────────────
public function getFhirRepository() returns FhirRepository {
    return new DatabaseFhirRepository();
}

// ─────────────────────────────────────────────────────────────────────────────
// Private helpers
// ─────────────────────────────────────────────────────────────────────────────

// Extract a string field from JSON, returning defaultVal if absent.
isolated function jsonStr(json j, string key, string defaultVal) returns string {
    map<json>|error m = j.ensureType();
    if m is map<json> {
        json? val = m[key];
        if val is string { return val; }
        if !(val is ()) { return val.toString(); }
    }
    return defaultVal;
}

// Extract the last path segment of a FHIR reference field (e.g. "Organization/abc" → "abc").
isolated function extractRefId(json j, string key) returns string? {
    map<json>|error m = j.ensureType();
    if m is map<json> {
        json? refObj = m[key];
        if refObj is map<json> {
            json? ref = refObj["reference"];
            if ref is string {
                string[] parts = re `/`.split(ref);
                return parts[parts.length() - 1];
            }
        }
    }
    return ();
}

// Extract connection type code from Endpoint.connectionType (a Coding, not CodeableConcept).
isolated function extractEndpointConnType(json j) returns string {
    json|error ct = j.connectionType;
    if ct is json {
        json|error code = ct.code;
        if code is string { return code; }
        if code is json { return code.toString(); }
    }
    return "";
}
