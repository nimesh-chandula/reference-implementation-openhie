import ballerina/sql;
import ballerinax/java.jdbc;

// ─────────────────────────────────────────────────────────────
// H2 Database Provider Implementation
// ─────────────────────────────────────────────────────────────
public class H2DatabaseProvider {
    *DatabaseProvider;

    public function isDatabaseExists(jdbc:Client jdbcClient) returns boolean|error {
        sql:ParameterizedQuery query = `SELECT COUNT(TABLE_CATALOG)
                                        FROM INFORMATION_SCHEMA.TABLES
                                        WHERE TABLE_SCHEMA='PUBLIC'`;
        int count = check jdbcClient->queryRow(query);
        return count > 0;
    }

    public function getSchemaFilePath() returns string {
        return "./scripts/schema-h2.sql";
    }

    public function getDatabaseType() returns string {
        return "h2";
    }

    public function executeSchema(jdbc:Client jdbcClient) returns error? {
        _ = check jdbcClient->execute(`RUNSCRIPT FROM './scripts/schema-h2.sql'`);
    }
}
