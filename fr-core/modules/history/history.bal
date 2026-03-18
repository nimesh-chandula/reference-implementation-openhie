import ballerina/sql;
import ballerinax/java.jdbc;
import wso2/FRCoreService.types;
import wso2/FRCoreService.db;

// ─────────────────────────────────────────────────────────────
// HISTORY (ITI-91)
// ─────────────────────────────────────────────────────────────
public function getResourceHistory(string resourceType, string? since) returns types:HistoryRow[]|error {
    jdbc:Client dbClient = check db:getDbClient();
    sql:ParameterizedQuery query = `
        SELECT resource_id AS "resourceId", version_id AS "versionId",
               action, fhir_resource AS "fhirResource",
               CAST(timestamp AS VARCHAR) AS "timestamp"
        FROM resource_history WHERE resource_type = ${resourceType}
    `;
    if since is string {
        string dbTs = db:toDbTimestamp(since);
        query = sql:queryConcat(query, ` AND timestamp >= ${dbTs}`);
    }
    query = sql:queryConcat(query, ` ORDER BY timestamp ASC`);

    types:HistoryRow[] rows = [];
    stream<types:HistoryRow, sql:Error?> rs = dbClient->query(query);
    check from types:HistoryRow row in rs do { rows.push(row); };
    return rows;
}
