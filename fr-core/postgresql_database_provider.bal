import ballerina/io;
import ballerina/sql;
import ballerinax/java.jdbc;

// ─────────────────────────────────────────────────────────────
// PostgreSQL Database Provider Implementation
// ─────────────────────────────────────────────────────────────
public class PostgreSQLDatabaseProvider {
    *DatabaseProvider;

    public function isDatabaseExists(jdbc:Client jdbcClient) returns boolean|error {
        sql:ParameterizedQuery query = `SELECT COUNT(*)
                                        FROM information_schema.tables
                                        WHERE table_schema='public'`;
        int count = check jdbcClient->queryRow(query);
        return count > 0;
    }

    public function getSchemaFilePath() returns string {
        return "./scripts/schema-postgresql.sql";
    }

    public function getDatabaseType() returns string {
        return "postgresql";
    }

    public function executeSchema(jdbc:Client jdbcClient) returns error? {
        _ = check jdbcClient->execute(`
            CREATE OR REPLACE FUNCTION _fr_exec_ddl(ddl_text TEXT) RETURNS VOID AS $$
            BEGIN EXECUTE ddl_text; END $$ LANGUAGE plpgsql
        `);
        string[] lines = check io:fileReadLines(self.getSchemaFilePath());
        string current = "";
        foreach string line in lines {
            string trimmed = line.trim();
            if trimmed.startsWith("--") || trimmed.length() == 0 {
                continue;
            }
            current += " " + trimmed;
            if trimmed.endsWith(";") {
                string stmt = current.trim();
                string sqlText = stmt.substring(0, stmt.length() - 1).trim();
                string sqlLower = sqlText.toLowerAscii();
                if sqlLower.startsWith("create") || sqlLower.startsWith("drop") {
                    _ = check jdbcClient->execute(`SELECT _fr_exec_ddl(${sqlText})`);
                }
                current = "";
            }
        }
        _ = check jdbcClient->execute(`DROP FUNCTION IF EXISTS _fr_exec_ddl(TEXT)`);
    }
}
