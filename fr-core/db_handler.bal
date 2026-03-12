import ballerina/log;
import ballerina/sql;
import ballerinax/java.jdbc;

configurable string dbType = "h2";
configurable string dbUrl = "jdbc:h2:./db/FR_CORE_DB";
configurable string dbUser = "sa";
configurable string dbPassword = "";
configurable int dbPoolMaxSize = 20;
configurable int dbPoolMinIdle = 5;

// ─────────────────────────────────────────────────────────────
// JDBC client (lazy init with connection pool)
// ─────────────────────────────────────────────────────────────
jdbc:Client? dbClient = ();

function getDbClient() returns jdbc:Client|error {
    jdbc:Client? existing = dbClient;
    if existing is jdbc:Client {
        return existing;
    }
    sql:ConnectionPool pool = {
        maxOpenConnections: dbPoolMaxSize,
        minIdleConnections: dbPoolMinIdle
    };
    jdbc:Client jdbcClient = check new (dbUrl, dbUser, dbPassword, connectionPool = pool);
    dbClient = jdbcClient;
    return jdbcClient;
}

// ─────────────────────────────────────────────────────────────
// Schema initialization
// ─────────────────────────────────────────────────────────────
function initDatabase() returns error? {
    jdbc:Client db = check getDbClient();
    DatabaseProvider provider = getDatabaseProvider(dbType);
    boolean dbExists = check provider.isDatabaseExists(db);

    if !dbExists {
        log:printInfo("Initializing database schema", dbType = dbType);
        check provider.executeSchema(db);
        log:printInfo("Database schema initialized successfully");
    } else {
        log:printInfo("Database already initialized, skipping schema setup", dbType = dbType);
    }
}

function dropAllTables(jdbc:Client db) returns error? {
    if dbType == "h2" {
        _ = check db->execute(`SET REFERENTIAL_INTEGRITY FALSE`);
        _ = check db->execute(`DROP TABLE IF EXISTS resource_history`);
        _ = check db->execute(`DROP TABLE IF EXISTS service_location`);
        _ = check db->execute(`DROP TABLE IF EXISTS identifier`);
        _ = check db->execute(`DROP TABLE IF EXISTS org_affiliation`);
        _ = check db->execute(`DROP TABLE IF EXISTS endpoint`);
        _ = check db->execute(`DROP TABLE IF EXISTS healthcare_service`);
        _ = check db->execute(`DROP TABLE IF EXISTS location`);
        _ = check db->execute(`DROP TABLE IF EXISTS organization`);
        _ = check db->execute(`SET REFERENTIAL_INTEGRITY TRUE`);
    } else {
        _ = check db->execute(`DROP TABLE IF EXISTS resource_history CASCADE`);
        _ = check db->execute(`DROP TABLE IF EXISTS service_location CASCADE`);
        _ = check db->execute(`DROP TABLE IF EXISTS identifier CASCADE`);
        _ = check db->execute(`DROP TABLE IF EXISTS org_affiliation CASCADE`);
        _ = check db->execute(`DROP TABLE IF EXISTS endpoint CASCADE`);
        _ = check db->execute(`DROP TABLE IF EXISTS healthcare_service CASCADE`);
        _ = check db->execute(`DROP TABLE IF EXISTS location CASCADE`);
        _ = check db->execute(`DROP TABLE IF EXISTS organization CASCADE`);
    }
}

// ─────────────────────────────────────────────────────────────
// Timestamp helper — normalize ISO 8601 to JDBC-compatible format
// ─────────────────────────────────────────────────────────────
isolated function toDbTimestamp(string isoTs) returns string {
    string s = isoTs;
    int? tIdx = s.indexOf("T");
    if tIdx is int {
        s = s.substring(0, tIdx) + " " + s.substring(tIdx + 1);
    }
    if s.endsWith("Z") {
        s = s.substring(0, s.length() - 1);
    }
    return s;
}

// ─────────────────────────────────────────────────────────────
// History record helper
// ─────────────────────────────────────────────────────────────
function recordHistory(string resourceType, string id, int versionId, string action, json? fhirJson) returns error? {
    jdbc:Client db = check getDbClient();
    string? fhirStr = fhirJson is json ? fhirJson.toJsonString() : ();
    _ = check db->execute(`
        INSERT INTO resource_history (resource_type, resource_id, version_id, action, fhir_resource)
        VALUES (${resourceType}, ${id}, ${versionId}, ${action}, ${fhirStr})
    `);
}

// ─────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────
function streamToJsonArray(stream<record {string fhir_resource;}, sql:Error?> resultStream) returns json[]|error {
    json[] results = [];
    check from record {string fhir_resource;} row in resultStream do {
        json|error parsed = row.fhir_resource.fromJsonString();
        if parsed is json {
            results.push(parsed);
        } else {
            log:printWarn("Failed to parse fhir_resource JSON", 'error = parsed);
        }
    };
    return results;
}
