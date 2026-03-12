
import ballerinax/java.jdbc;

// ─────────────────────────────────────────────────────────────
// Database Provider Interface
// ─────────────────────────────────────────────────────────────
public type DatabaseProvider object {
    public function isDatabaseExists(jdbc:Client jdbcClient) returns boolean|error;
    public function getSchemaFilePath() returns string;
    public function getDatabaseType() returns string;
    public function executeSchema(jdbc:Client jdbcClient) returns error?;
};
