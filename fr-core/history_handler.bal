import ballerina/sql;
import ballerinax/java.jdbc;

// ─────────────────────────────────────────────────────────────
// HISTORY (ITI-91)
// ─────────────────────────────────────────────────────────────
function getResourceHistory(string resourceType, string? since) returns HistoryRow[]|error {
    jdbc:Client db = check getDbClient();
    sql:ParameterizedQuery query = `
        SELECT resource_id AS "resourceId", version_id AS "versionId",
               action, fhir_resource AS "fhirResource",
               CAST(timestamp AS VARCHAR) AS "timestamp"
        FROM resource_history WHERE resource_type = ${resourceType}
    `;
    if since is string {
        string dbTs = toDbTimestamp(since);
        query = sql:queryConcat(query, ` AND timestamp >= ${dbTs}`);
    }
    query = sql:queryConcat(query, ` ORDER BY timestamp ASC`);

    HistoryRow[] rows = [];
    stream<HistoryRow, sql:Error?> rs = db->query(query);
    check from HistoryRow row in rs do { rows.push(row); };
    return rows;
}
