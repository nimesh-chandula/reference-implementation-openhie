import ballerina/http;
import ballerina/url;
import ballerinax/health.fhir.r4;

// Parse Organization search parameters from an HTTP request
function parseOrgSearchParams(http:Request req) returns OrgSearchParams|error {
    map<string[]> queryParams = req.getQueryParams();
    OrgSearchParams params = {};

    foreach string key in queryParams.keys() {
        string[] values = queryParams[key] ?: [];
        string val = values.length() > 0 ? values[0] : "";
        string decodedKey = check url:decode(key, "UTF-8");
        string decodedVal = check url:decode(val, "UTF-8");

        if decodedKey == "_id" { params._id = decodedVal; }
        else if decodedKey == "active" { params.active = decodedVal; }
        else if decodedKey == "identifier" { params.identifier = decodedVal; }
        else if decodedKey == "name" { params.name = decodedVal; }
        else if decodedKey == "name:contains" { params.name = decodedVal; params.nameModifier = "contains"; }
        else if decodedKey == "name:exact" { params.name = decodedVal; params.nameModifier = "exact"; }
        else if decodedKey == "type" { params.'type = decodedVal; }
        else if decodedKey == "partof" { params.partof = decodedVal; }
        else if decodedKey == "_include" { params._include = decodedVal; }
        else if decodedKey == "_revInclude" { params._revInclude = decodedVal; }
        else if decodedKey == "_count" {
            int|error countVal = int:fromString(decodedVal);
            if countVal is int && countVal > 0 { params._count = countVal; }
        }
        else if decodedKey == "_offset" {
            int|error offsetVal = int:fromString(decodedVal);
            if offsetVal is int && offsetVal >= 0 { params._offset = offsetVal; }
        }
        else if decodedKey == "_lastUpdated" {
            LastUpdatedFilter filter = parseLastUpdated(decodedVal);
            params._lastUpdated = filter.value;
            params._lastUpdatedPrefix = filter.prefix;
        }
    }
    return params;
}

// Parse Location search parameters from an HTTP request
function parseLocationSearchParams(http:Request req) returns LocationSearchParams|error {
    map<string[]> queryParams = req.getQueryParams();
    LocationSearchParams params = {};

    foreach string key in queryParams.keys() {
        string[] values = queryParams[key] ?: [];
        string val = values.length() > 0 ? values[0] : "";
        string decodedKey = check url:decode(key, "UTF-8");
        string decodedVal = check url:decode(val, "UTF-8");

        if decodedKey == "_id" { params._id = decodedVal; }
        else if decodedKey == "identifier" { params.identifier = decodedVal; }
        else if decodedKey == "name" { params.name = decodedVal; }
        else if decodedKey == "name:contains" { params.name = decodedVal; params.nameModifier = "contains"; }
        else if decodedKey == "name:exact" { params.name = decodedVal; params.nameModifier = "exact"; }
        else if decodedKey == "organization" { params.organization = decodedVal; }
        else if decodedKey == "status" { params.status = decodedVal; }
        else if decodedKey == "type" { params.'type = decodedVal; }
        else if decodedKey == "partof" { params.partof = decodedVal; }
        else if decodedKey == "near" { params.near = decodedVal; }
        else if decodedKey == "_include" { params._include = decodedVal; }
        else if decodedKey == "_count" {
            int|error countVal = int:fromString(decodedVal);
            if countVal is int && countVal > 0 { params._count = countVal; }
        }
        else if decodedKey == "_offset" {
            int|error offsetVal = int:fromString(decodedVal);
            if offsetVal is int && offsetVal >= 0 { params._offset = offsetVal; }
        }
        else if decodedKey == "_lastUpdated" {
            LastUpdatedFilter filter = parseLastUpdated(decodedVal);
            params._lastUpdated = filter.value;
            params._lastUpdatedPrefix = filter.prefix;
        }
    }
    return params;
}

// Parse HealthcareService search parameters
function parseSvcSearchParams(http:Request req) returns HealthcareServiceSearchParams|error {
    map<string[]> queryParams = req.getQueryParams();
    HealthcareServiceSearchParams params = {};

    foreach string key in queryParams.keys() {
        string[] values = queryParams[key] ?: [];
        string val = values.length() > 0 ? values[0] : "";
        string decodedKey = check url:decode(key, "UTF-8");
        string decodedVal = check url:decode(val, "UTF-8");

        if decodedKey == "active" { params.active = decodedVal; }
        else if decodedKey == "identifier" { params.identifier = decodedVal; }
        else if decodedKey == "location" { params.location = decodedVal; }
        else if decodedKey == "name" { params.name = decodedVal; }
        else if decodedKey == "name:contains" { params.name = decodedVal; params.nameModifier = "contains"; }
        else if decodedKey == "name:exact" { params.name = decodedVal; params.nameModifier = "exact"; }
        else if decodedKey == "organization" { params.organization = decodedVal; }
        else if decodedKey == "service-type" { params.serviceType = decodedVal; }
        else if decodedKey == "_count" {
            int|error countVal = int:fromString(decodedVal);
            if countVal is int && countVal > 0 { params._count = countVal; }
        }
        else if decodedKey == "_offset" {
            int|error offsetVal = int:fromString(decodedVal);
            if offsetVal is int && offsetVal >= 0 { params._offset = offsetVal; }
        }
    }
    return params;
}

// Parse Endpoint search parameters
function parseEndpointSearchParams(http:Request req) returns EndpointSearchParams|error {
    map<string[]> queryParams = req.getQueryParams();
    EndpointSearchParams params = {};

    foreach string key in queryParams.keys() {
        string[] values = queryParams[key] ?: [];
        string val = values.length() > 0 ? values[0] : "";
        string decodedKey = check url:decode(key, "UTF-8");
        string decodedVal = check url:decode(val, "UTF-8");

        if decodedKey == "identifier" { params.identifier = decodedVal; }
        else if decodedKey == "organization" { params.organization = decodedVal; }
        else if decodedKey == "status" { params.status = decodedVal; }
        else if decodedKey == "_count" {
            int|error countVal = int:fromString(decodedVal);
            if countVal is int && countVal > 0 { params._count = countVal; }
        }
        else if decodedKey == "_offset" {
            int|error offsetVal = int:fromString(decodedVal);
            if offsetVal is int && offsetVal >= 0 { params._offset = offsetVal; }
        }
    }
    return params;
}

// Parse OrganizationAffiliation search parameters
function parseAffiliationSearchParams(http:Request req) returns OrgAffiliationSearchParams|error {
    map<string[]> queryParams = req.getQueryParams();
    OrgAffiliationSearchParams params = {};

    foreach string key in queryParams.keys() {
        string[] values = queryParams[key] ?: [];
        string val = values.length() > 0 ? values[0] : "";
        string decodedKey = check url:decode(key, "UTF-8");
        string decodedVal = check url:decode(val, "UTF-8");

        if decodedKey == "active" { params.active = decodedVal; }
        else if decodedKey == "identifier" { params.identifier = decodedVal; }
        else if decodedKey == "participating-organization" { params.participatingOrganization = decodedVal; }
        else if decodedKey == "primary-organization" { params.primaryOrganization = decodedVal; }
        else if decodedKey == "role" { params.role = decodedVal; }
        else if decodedKey == "_count" {
            int|error countVal = int:fromString(decodedVal);
            if countVal is int && countVal > 0 { params._count = countVal; }
        }
        else if decodedKey == "_offset" {
            int|error offsetVal = int:fromString(decodedVal);
            if offsetVal is int && offsetVal >= 0 { params._offset = offsetVal; }
        }
    }
    return params;
}

// Parse a form-urlencoded body (for POST _search)
function parseFormBody(string body) returns map<string>|error {
    map<string> result = {};
    string[] pairs = re`&`.split(body);
    foreach string pair in pairs {
        string[] kv = re`=`.split(pair);
        if kv.length() >= 2 {
            string k = check url:decode(kv[0], "UTF-8");
            string v = check url:decode(kv[1], "UTF-8");
            result[k] = v;
        } else if kv.length() == 1 {
            string k = check url:decode(kv[0], "UTF-8");
            result[k] = "";
        }
    }
    return result;
}

// Parse a FHIR 'near' parameter: "lat|lon|distance|units" (e.g. "6.9271|79.8612|10|km")
function parseNearParam(string near) returns NearParam|error {
    string[] parts = re`\|`.split(near);
    if parts.length() < 3 {
        return error("Invalid 'near' parameter format. Expected: lat|lon|distance[|units]");
    }
    decimal lat = check decimal:fromString(parts[0].trim());
    decimal lon = check decimal:fromString(parts[1].trim());
    decimal distance = check decimal:fromString(parts[2].trim());

    // Convert to km if units specified
    decimal distanceKm = distance;
    if parts.length() >= 4 {
        string units = parts[3].trim().toLowerAscii();
        if units == "mi" || units == "miles" {
            distanceKm = distance * 1.60934d;
        } else if units == "m" || units == "meters" {
            distanceKm = distance / 1000.0d;
        }
        // km and [km] are already in km
    }

    return {lat: lat, lon: lon, distanceKm: distanceKm};
}

// Build OrgSearchParams from a map<string> (for POST _search body parsing)
function mapToOrgSearchParams(map<string> params) returns OrgSearchParams {
    OrgSearchParams result = {};
    string? id = params["_id"];
    if id is string { result._id = id; }
    string? active = params["active"];
    if active is string { result.active = active; }
    string? name = params["name"];
    if name is string { result.name = name; }
    string? nameContains = params["name:contains"];
    if nameContains is string { result.name = nameContains; result.nameModifier = "contains"; }
    string? nameExact = params["name:exact"];
    if nameExact is string { result.name = nameExact; result.nameModifier = "exact"; }
    string? typeCode = params["type"];
    if typeCode is string { result.'type = typeCode; }
    string? partof = params["partof"];
    if partof is string { result.partof = partof; }
    string? lastUpdated = params["_lastUpdated"];
    if lastUpdated is string {
        LastUpdatedFilter filter = parseLastUpdated(lastUpdated);
        result._lastUpdated = filter.value;
        result._lastUpdatedPrefix = filter.prefix;
    }
    return result;
}

// ─────────────────────────────────────────────────────────────
// FHIRContext bridge functions — extract search params from r4:FHIRContext
// ─────────────────────────────────────────────────────────────

// Get first string value for a named search param from the FHIR context
function getSearchParamValue(r4:FHIRContext ctx, string name) returns string? {
    r4:RequestSearchParameter[]? params = ctx.getRequestSearchParameter(name);
    if params is r4:RequestSearchParameter[] && params.length() > 0 {
        return params[0].value;
    }
    return ();
}

// Get the modifier ("contains", "exact", etc.) for a named search param
function getSearchParamModifier(r4:FHIRContext ctx, string name) returns string? {
    r4:RequestSearchParameter[]? params = ctx.getRequestSearchParameter(name);
    if params is r4:RequestSearchParameter[] && params.length() > 0 {
        r4:FHIRTypedSearchParameter typedVal = params[0].typedValue;
        r4:FHIRSearchParameterModifier|string? modifier = typedVal.modifier;
        if modifier is string {
            return modifier;
        }
    }
    return ();
}

// Convert FHIRContext search parameters to OrgSearchParams
function fhirContextToOrgSearchParams(r4:FHIRContext ctx) returns OrgSearchParams {
    OrgSearchParams params = {};

    string? id = getSearchParamValue(ctx, "_id");
    if id is string { params._id = id; }

    string? active = getSearchParamValue(ctx, "active");
    if active is string { params.active = active; }

    string? identifier = getSearchParamValue(ctx, "identifier");
    if identifier is string { params.identifier = identifier; }

    string? name = getSearchParamValue(ctx, "name");
    if name is string {
        params.name = name;
        string? modifier = getSearchParamModifier(ctx, "name");
        if modifier is string { params.nameModifier = modifier; }
    }

    string? typeCode = getSearchParamValue(ctx, "type");
    if typeCode is string { params.'type = typeCode; }

    string? partof = getSearchParamValue(ctx, "partof");
    if partof is string { params.partof = partof; }

    string? include = getSearchParamValue(ctx, "_include");
    if include is string { params._include = include; }

    string? revInclude = getSearchParamValue(ctx, "_revInclude");
    if revInclude is string { params._revInclude = revInclude; }

    string? lastUpdated = getSearchParamValue(ctx, "_lastUpdated");
    if lastUpdated is string {
        LastUpdatedFilter filter = parseLastUpdated(lastUpdated);
        params._lastUpdated = filter.value;
        params._lastUpdatedPrefix = filter.prefix;
    }

    string? countStr = getSearchParamValue(ctx, "_count");
    if countStr is string {
        int|error countVal = int:fromString(countStr);
        if countVal is int && countVal > 0 { params._count = countVal; }
    }

    string? offsetStr = getSearchParamValue(ctx, "_offset");
    if offsetStr is string {
        int|error offsetVal = int:fromString(offsetStr);
        if offsetVal is int && offsetVal >= 0 { params._offset = offsetVal; }
    }

    // Page-based pagination fallback (fhirr4 pagination context)
    r4:PaginationContext? paginationCtx = ctx.getPaginationContext();
    if paginationCtx is r4:PaginationContext && paginationCtx.paginationEnabled {
        params._count = paginationCtx.pageSize;
        params._offset = (paginationCtx.page - 1) * paginationCtx.pageSize;
    }

    return params;
}

// Convert FHIRContext search parameters to LocationSearchParams
function fhirContextToLocationSearchParams(r4:FHIRContext ctx) returns LocationSearchParams {
    LocationSearchParams params = {};

    string? id = getSearchParamValue(ctx, "_id");
    if id is string { params._id = id; }

    string? identifier = getSearchParamValue(ctx, "identifier");
    if identifier is string { params.identifier = identifier; }

    string? name = getSearchParamValue(ctx, "name");
    if name is string {
        params.name = name;
        string? modifier = getSearchParamModifier(ctx, "name");
        if modifier is string { params.nameModifier = modifier; }
    }

    string? organization = getSearchParamValue(ctx, "organization");
    if organization is string { params.organization = organization; }

    string? status = getSearchParamValue(ctx, "status");
    if status is string { params.status = status; }

    string? typeCode = getSearchParamValue(ctx, "type");
    if typeCode is string { params.'type = typeCode; }

    string? partof = getSearchParamValue(ctx, "partof");
    if partof is string { params.partof = partof; }

    string? near = getSearchParamValue(ctx, "near");
    if near is string { params.near = near; }

    string? include = getSearchParamValue(ctx, "_include");
    if include is string { params._include = include; }

    string? lastUpdated = getSearchParamValue(ctx, "_lastUpdated");
    if lastUpdated is string {
        LastUpdatedFilter filter = parseLastUpdated(lastUpdated);
        params._lastUpdated = filter.value;
        params._lastUpdatedPrefix = filter.prefix;
    }

    string? countStr = getSearchParamValue(ctx, "_count");
    if countStr is string {
        int|error countVal = int:fromString(countStr);
        if countVal is int && countVal > 0 { params._count = countVal; }
    }

    string? offsetStr = getSearchParamValue(ctx, "_offset");
    if offsetStr is string {
        int|error offsetVal = int:fromString(offsetStr);
        if offsetVal is int && offsetVal >= 0 { params._offset = offsetVal; }
    }

    r4:PaginationContext? paginationCtx = ctx.getPaginationContext();
    if paginationCtx is r4:PaginationContext && paginationCtx.paginationEnabled {
        params._count = paginationCtx.pageSize;
        params._offset = (paginationCtx.page - 1) * paginationCtx.pageSize;
    }

    return params;
}

// Convert FHIRContext search parameters to HealthcareServiceSearchParams
function fhirContextToSvcSearchParams(r4:FHIRContext ctx) returns HealthcareServiceSearchParams {
    HealthcareServiceSearchParams params = {};

    string? active = getSearchParamValue(ctx, "active");
    if active is string { params.active = active; }

    string? identifier = getSearchParamValue(ctx, "identifier");
    if identifier is string { params.identifier = identifier; }

    string? location = getSearchParamValue(ctx, "location");
    if location is string { params.location = location; }

    string? name = getSearchParamValue(ctx, "name");
    if name is string {
        params.name = name;
        string? modifier = getSearchParamModifier(ctx, "name");
        if modifier is string { params.nameModifier = modifier; }
    }

    string? organization = getSearchParamValue(ctx, "organization");
    if organization is string { params.organization = organization; }

    string? serviceType = getSearchParamValue(ctx, "service-type");
    if serviceType is string { params.serviceType = serviceType; }

    string? countStr = getSearchParamValue(ctx, "_count");
    if countStr is string {
        int|error countVal = int:fromString(countStr);
        if countVal is int && countVal > 0 { params._count = countVal; }
    }

    string? offsetStr = getSearchParamValue(ctx, "_offset");
    if offsetStr is string {
        int|error offsetVal = int:fromString(offsetStr);
        if offsetVal is int && offsetVal >= 0 { params._offset = offsetVal; }
    }

    r4:PaginationContext? paginationCtx = ctx.getPaginationContext();
    if paginationCtx is r4:PaginationContext && paginationCtx.paginationEnabled {
        params._count = paginationCtx.pageSize;
        params._offset = (paginationCtx.page - 1) * paginationCtx.pageSize;
    }

    return params;
}

// Convert FHIRContext search parameters to EndpointSearchParams
function fhirContextToEndpointSearchParams(r4:FHIRContext ctx) returns EndpointSearchParams {
    EndpointSearchParams params = {};

    string? identifier = getSearchParamValue(ctx, "identifier");
    if identifier is string { params.identifier = identifier; }

    string? organization = getSearchParamValue(ctx, "organization");
    if organization is string { params.organization = organization; }

    string? status = getSearchParamValue(ctx, "status");
    if status is string { params.status = status; }

    string? countStr = getSearchParamValue(ctx, "_count");
    if countStr is string {
        int|error countVal = int:fromString(countStr);
        if countVal is int && countVal > 0 { params._count = countVal; }
    }

    string? offsetStr = getSearchParamValue(ctx, "_offset");
    if offsetStr is string {
        int|error offsetVal = int:fromString(offsetStr);
        if offsetVal is int && offsetVal >= 0 { params._offset = offsetVal; }
    }

    r4:PaginationContext? paginationCtx = ctx.getPaginationContext();
    if paginationCtx is r4:PaginationContext && paginationCtx.paginationEnabled {
        params._count = paginationCtx.pageSize;
        params._offset = (paginationCtx.page - 1) * paginationCtx.pageSize;
    }

    return params;
}

// Convert FHIRContext search parameters to OrgAffiliationSearchParams
function fhirContextToAffiliationSearchParams(r4:FHIRContext ctx) returns OrgAffiliationSearchParams {
    OrgAffiliationSearchParams params = {};

    string? active = getSearchParamValue(ctx, "active");
    if active is string { params.active = active; }

    string? identifier = getSearchParamValue(ctx, "identifier");
    if identifier is string { params.identifier = identifier; }

    string? participatingOrg = getSearchParamValue(ctx, "participating-organization");
    if participatingOrg is string { params.participatingOrganization = participatingOrg; }

    string? primaryOrg = getSearchParamValue(ctx, "primary-organization");
    if primaryOrg is string { params.primaryOrganization = primaryOrg; }

    string? role = getSearchParamValue(ctx, "role");
    if role is string { params.role = role; }

    string? countStr = getSearchParamValue(ctx, "_count");
    if countStr is string {
        int|error countVal = int:fromString(countStr);
        if countVal is int && countVal > 0 { params._count = countVal; }
    }

    string? offsetStr = getSearchParamValue(ctx, "_offset");
    if offsetStr is string {
        int|error offsetVal = int:fromString(offsetStr);
        if offsetVal is int && offsetVal >= 0 { params._offset = offsetVal; }
    }

    r4:PaginationContext? paginationCtx = ctx.getPaginationContext();
    if paginationCtx is r4:PaginationContext && paginationCtx.paginationEnabled {
        params._count = paginationCtx.pageSize;
        params._offset = (paginationCtx.page - 1) * paginationCtx.pageSize;
    }

    return params;
}

// Build LocationSearchParams from a map<string>
function mapToLocationSearchParams(map<string> params) returns LocationSearchParams {
    LocationSearchParams result = {};
    string? id = params["_id"];
    if id is string { result._id = id; }
    string? name = params["name"];
    if name is string { result.name = name; }
    string? nameContains = params["name:contains"];
    if nameContains is string { result.name = nameContains; result.nameModifier = "contains"; }
    string? status = params["status"];
    if status is string { result.status = status; }
    string? typeCode = params["type"];
    if typeCode is string { result.'type = typeCode; }
    string? near = params["near"];
    if near is string { result.near = near; }
    string? organization = params["organization"];
    if organization is string { result.organization = organization; }
    return result;
}

