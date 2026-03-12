import ballerina/sql;
import ballerinax/java.jdbc;

// ─────────────────────────────────────────────────────────────
// ADMIN
// ─────────────────────────────────────────────────────────────
function getStats() returns RegistryStats|error {
    jdbc:Client db = check getDbClient();
    int totalOrgs = 0; int totalLocs = 0; int totalSvcs = 0; int totalEps = 0;
    int activeOrgs = 0; int activeLocs = 0; int facilities = 0; int jurisdictions = 0;

    record {int cnt;}|error r;

    r = db->queryRow(`SELECT COUNT(*) AS cnt FROM organization WHERE is_deleted = FALSE`);
    if r is record {int cnt;} { totalOrgs = r.cnt; }

    r = db->queryRow(`SELECT COUNT(*) AS cnt FROM location WHERE is_deleted = FALSE`);
    if r is record {int cnt;} { totalLocs = r.cnt; }

    r = db->queryRow(`SELECT COUNT(*) AS cnt FROM healthcare_service WHERE is_deleted = FALSE`);
    if r is record {int cnt;} { totalSvcs = r.cnt; }

    r = db->queryRow(`SELECT COUNT(*) AS cnt FROM endpoint WHERE is_deleted = FALSE`);
    if r is record {int cnt;} { totalEps = r.cnt; }

    r = db->queryRow(`SELECT COUNT(*) AS cnt FROM organization WHERE is_deleted = FALSE AND active = TRUE`);
    if r is record {int cnt;} { activeOrgs = r.cnt; }

    r = db->queryRow(`SELECT COUNT(*) AS cnt FROM location WHERE is_deleted = FALSE AND status = 'active'`);
    if r is record {int cnt;} { activeLocs = r.cnt; }

    r = db->queryRow(`SELECT COUNT(*) AS cnt FROM organization WHERE is_deleted = FALSE AND type_code = 'facility'`);
    if r is record {int cnt;} { facilities = r.cnt; }

    r = db->queryRow(`SELECT COUNT(*) AS cnt FROM organization WHERE is_deleted = FALSE AND type_code = 'jurisdiction'`);
    if r is record {int cnt;} { jurisdictions = r.cnt; }

    return {
        totalOrganizations: totalOrgs, totalLocations: totalLocs,
        totalHealthcareServices: totalSvcs, totalEndpoints: totalEps,
        activeOrganizations: activeOrgs, activeLocations: activeLocs,
        facilitiesCount: facilities, jurisdictionsCount: jurisdictions
    };
}

function getHierarchyTree() returns json|error {
    jdbc:Client db = check getDbClient();
    sql:ParameterizedQuery query = `
        SELECT fhir_resource FROM organization
        WHERE is_deleted = FALSE AND part_of_id IS NULL
        ORDER BY name
    `;
    stream<record {string fhir_resource;}, sql:Error?> rs = db->query(query);
    return streamToJsonArray(rs);
}

function getMapGeoJson() returns json|error {
    jdbc:Client db = check getDbClient();
    json[] features = [];
    stream<record {string fhir_resource; decimal? latitude; decimal? longitude;}, sql:Error?> rs =
        db->query(`
            SELECT fhir_resource, latitude, longitude FROM location
            WHERE is_deleted = FALSE AND latitude IS NOT NULL AND longitude IS NOT NULL
        `);
    check from record {string fhir_resource; decimal? latitude; decimal? longitude;} row in rs do {
        decimal? lat = row.latitude;
        decimal? lon = row.longitude;
        if lat is decimal && lon is decimal {
            json|error parsed = row.fhir_resource.fromJsonString();
            if parsed is json {
                json|error idVal = parsed.id;
                json|error nameVal = parsed.name;
                json|error statusVal = parsed.status;
                features.push({
                    "type": "Feature",
                    "geometry": {"type": "Point", "coordinates": [lon, lat]},
                    "properties": {
                        "id": idVal is json ? idVal : "",
                        "name": nameVal is json ? nameVal : "",
                        "status": statusVal is json ? statusVal : "",
                        "type": extractTypeCode(parsed)
                    }
                });
            }
        }
    };
    return {"type": "FeatureCollection", "features": features};
}
