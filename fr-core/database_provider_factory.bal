// ─────────────────────────────────────────────────────────────
// Database Provider Factory
// ─────────────────────────────────────────────────────────────
function getDatabaseProvider(string dbTypeName) returns DatabaseProvider {
    if dbTypeName == "postgresql" {
        return new PostgreSQLDatabaseProvider();
    }
    return new H2DatabaseProvider();
}
