import ballerina/http;
import ballerina/log;
import wso2/FRCoreService.organization;
import wso2/FRCoreService.location;
import wso2/FRCoreService.healthcare_service;
import wso2/FRCoreService.endpoint as ep;
import wso2/FRCoreService.org_affiliation;
import wso2/FRCoreService.history;
import wso2/FRCoreService.types;
import wso2/FRCoreService.fhir_utils;
import healthcare_samples/mcsd_package;

// ─────────────────────────────────────────────────────────────────────────────
// Public Types
// ─────────────────────────────────────────────────────────────────────────────

public type TransactionContext record {|
    string transactionType; // "ITI-90" | "ITI-91" | "ITI-130"
    string resourceType;
    string tenantId;
    http:Request request;
|};

public type TransactionHandler object {
    public function authenticate(TransactionContext ctx) returns error?;
    public function authorize(TransactionContext ctx) returns error?;
    public function execute(TransactionContext ctx) returns http:Response|error;
    public function audit(TransactionContext ctx, http:Response resp) returns error?;
};

// ─────────────────────────────────────────────────────────────────────────────
// Default behaviours — shared by BaseTransactionHandler and all concrete classes
// (Ballerina class inclusion copies type signatures, not implementations)
// ─────────────────────────────────────────────────────────────────────────────

function defaultAuthenticate(TransactionContext ctx) returns error? {
    // Pass-through: no auth enforcement — override for production auth
    return ();
}

function defaultAuthorize(TransactionContext ctx) returns error? {
    // Pass-through: no authz enforcement — override for production authz
    return ();
}

function defaultAudit(TransactionContext ctx, http:Response resp) returns error? {
    // TODO: wire from service.bal via event_bus:publishEvent() in Step 9
    log:printDebug("Transaction audit stub",
        transactionType = ctx.transactionType,
        resourceType = ctx.resourceType,
        statusCode = resp.statusCode);
    return ();
}

// ─────────────────────────────────────────────────────────────────────────────
// BaseTransactionHandler — concrete class usable standalone (e.g. in tests)
// ─────────────────────────────────────────────────────────────────────────────

public class BaseTransactionHandler {
    *TransactionHandler;

    public function authenticate(TransactionContext ctx) returns error? =>
        defaultAuthenticate(ctx);

    public function authorize(TransactionContext ctx) returns error? =>
        defaultAuthorize(ctx);

    public function execute(TransactionContext ctx) returns http:Response|error =>
        error("execute() must be overridden by a concrete TransactionHandler");

    public function audit(TransactionContext ctx, http:Response resp) returns error? =>
        defaultAudit(ctx, resp);
}

// ─────────────────────────────────────────────────────────────────────────────
// Private Helpers — query param extraction
// ─────────────────────────────────────────────────────────────────────────────

isolated function getFirst(map<string[]> qp, string key) returns string? {
    string[]? vals = qp[key];
    return vals is string[] && vals.length() > 0 ? vals[0] : ();
}

isolated function parseIntOrDefault(string? val, int defaultVal) returns int {
    if val is string {
        int|error n = int:fromString(val);
        return n is int ? n : defaultVal;
    }
    return defaultVal;
}

function buildOrgParams(map<string[]> qp) returns types:OrgSearchParams => {
    _id: getFirst(qp, "_id"),
    active: getFirst(qp, "active"),
    identifier: getFirst(qp, "identifier"),
    name: getFirst(qp, "name"),
    nameModifier: getFirst(qp, "name:modifier"),
    'type: getFirst(qp, "type"),
    partof: getFirst(qp, "partof"),
    _lastUpdated: getFirst(qp, "_lastUpdated"),
    _lastUpdatedPrefix: getFirst(qp, "_lastUpdatedPrefix"),
    _count: parseIntOrDefault(getFirst(qp, "_count"), 20),
    _offset: parseIntOrDefault(getFirst(qp, "_offset"), 0)
};

function buildLocationParams(map<string[]> qp) returns types:LocationSearchParams => {
    _id: getFirst(qp, "_id"),
    identifier: getFirst(qp, "identifier"),
    name: getFirst(qp, "name"),
    nameModifier: getFirst(qp, "name:modifier"),
    organization: getFirst(qp, "organization"),
    status: getFirst(qp, "status"),
    'type: getFirst(qp, "type"),
    partof: getFirst(qp, "partof"),
    near: getFirst(qp, "near"),
    _lastUpdated: getFirst(qp, "_lastUpdated"),
    _lastUpdatedPrefix: getFirst(qp, "_lastUpdatedPrefix"),
    _count: parseIntOrDefault(getFirst(qp, "_count"), 20),
    _offset: parseIntOrDefault(getFirst(qp, "_offset"), 0)
};

function buildSvcParams(map<string[]> qp) returns types:HealthcareServiceSearchParams => {
    active: getFirst(qp, "active"),
    identifier: getFirst(qp, "identifier"),
    location: getFirst(qp, "location"),
    name: getFirst(qp, "name"),
    nameModifier: getFirst(qp, "name:modifier"),
    organization: getFirst(qp, "organization"),
    serviceType: getFirst(qp, "service-type"),
    _count: parseIntOrDefault(getFirst(qp, "_count"), 20),
    _offset: parseIntOrDefault(getFirst(qp, "_offset"), 0)
};

function buildEndpointParams(map<string[]> qp) returns types:EndpointSearchParams => {
    identifier: getFirst(qp, "identifier"),
    organization: getFirst(qp, "organization"),
    status: getFirst(qp, "status"),
    _count: parseIntOrDefault(getFirst(qp, "_count"), 20),
    _offset: parseIntOrDefault(getFirst(qp, "_offset"), 0)
};

function buildAffiliationParams(map<string[]> qp) returns types:OrgAffiliationSearchParams => {
    active: getFirst(qp, "active"),
    identifier: getFirst(qp, "identifier"),
    participatingOrganization: getFirst(qp, "participating-organization"),
    primaryOrganization: getFirst(qp, "primary-organization"),
    role: getFirst(qp, "role"),
    _count: parseIntOrDefault(getFirst(qp, "_count"), 20),
    _offset: parseIntOrDefault(getFirst(qp, "_offset"), 0)
};

// ─────────────────────────────────────────────────────────────────────────────
// Private Helpers — ITI-130 CRUD dispatch
// ─────────────────────────────────────────────────────────────────────────────

function dispatchCreate(string resourceType, json payload) returns string|error {
    match resourceType {
        "Organization" => {
            // Try FacilityOrganization first, fall back to JurisdictionOrganization
            mcsd_package:MCSDFacilityOrganization|error fac =
                payload.cloneWithType(mcsd_package:MCSDFacilityOrganization);
            if fac is mcsd_package:MCSDFacilityOrganization {
                return organization:createOrganization(fac);
            }
            mcsd_package:MCSDJurisdictionOrganization jur =
                check payload.cloneWithType(mcsd_package:MCSDJurisdictionOrganization);
            return organization:createOrganization(jur);
        }
        "Location" => {
            // Try FacilityLocation first, fall back to JurisdictionLocation
            mcsd_package:MCSDFacilityLocation|error fac =
                payload.cloneWithType(mcsd_package:MCSDFacilityLocation);
            if fac is mcsd_package:MCSDFacilityLocation {
                return location:createLocation(fac);
            }
            mcsd_package:MCSDJurisdictionLocation jur =
                check payload.cloneWithType(mcsd_package:MCSDJurisdictionLocation);
            return location:createLocation(jur);
        }
        "HealthcareService" => {
            mcsd_package:MCSDHealthcareService svc =
                check payload.cloneWithType(mcsd_package:MCSDHealthcareService);
            return healthcare_service:createHealthcareService(svc);
        }
        "Endpoint" => {
            mcsd_package:MCSDEndpoint e =
                check payload.cloneWithType(mcsd_package:MCSDEndpoint);
            return ep:createEndpoint(e);
        }
        "OrganizationAffiliation" => {
            mcsd_package:MCSDOrganizationAffiliation aff =
                check payload.cloneWithType(mcsd_package:MCSDOrganizationAffiliation);
            return org_affiliation:createOrgAffiliation(aff);
        }
        _ => {
            return error("Unsupported resource type for ITI-130 create: " + resourceType);
        }
    }
}

function dispatchUpdate(string resourceType, string id, json payload) returns boolean|error {
    match resourceType {
        "Organization"    => { return organization:updateOrganization(id, payload); }
        "Location"        => { return location:updateLocation(id, payload); }
        "HealthcareService" => { return healthcare_service:updateHealthcareService(id, payload); }
        // Endpoint and OrganizationAffiliation only support create per mCSD interactions
        "Endpoint"        => { return error("Update not supported for Endpoint (ITI-130)"); }
        "OrganizationAffiliation" => { return error("Update not supported for OrganizationAffiliation (ITI-130)"); }
        _                 => { return error("Unsupported resource type for ITI-130 update: " + resourceType); }
    }
}

function dispatchDelete(string resourceType, string id) returns boolean|error {
    match resourceType {
        "Organization"    => { return organization:deleteOrganization(id); }
        "Location"        => { return location:deleteLocation(id); }
        "HealthcareService" => { return healthcare_service:deleteHealthcareService(id); }
        // Endpoint and OrganizationAffiliation only support create per mCSD interactions
        "Endpoint"        => { return error("Delete not supported for Endpoint (ITI-130)"); }
        "OrganizationAffiliation" => { return error("Delete not supported for OrganizationAffiliation (ITI-130)"); }
        _                 => { return error("Unsupported resource type for ITI-130 delete: " + resourceType); }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ITI-90 — mCSD Query (Find Matching Care Services)
// ─────────────────────────────────────────────────────────────────────────────

public class ITI90SearchHandler {
    *TransactionHandler;

    public function authenticate(TransactionContext ctx) returns error? =>
        defaultAuthenticate(ctx);

    public function authorize(TransactionContext ctx) returns error? =>
        defaultAuthorize(ctx);

    public function audit(TransactionContext ctx, http:Response resp) returns error? =>
        defaultAudit(ctx, resp);

    public function execute(TransactionContext ctx) returns http:Response|error {
        map<string[]> qp = ctx.request.getQueryParams();
        json[] results = [];
        int total = 0;
        string baseUrl = "/fhir/" + ctx.resourceType;

        match ctx.resourceType {
            "Organization" => {
                types:OrgSearchParams params = buildOrgParams(qp);
                results = check organization:searchOrganizations(params);
                total = check organization:countOrganizations(params);
            }
            "Location" => {
                types:LocationSearchParams params = buildLocationParams(qp);
                results = check location:searchLocations(params);
                total = check location:countLocations(params);
            }
            "HealthcareService" => {
                types:HealthcareServiceSearchParams params = buildSvcParams(qp);
                results = check healthcare_service:searchHealthcareServices(params);
                total = results.length();
            }
            "Endpoint" => {
                types:EndpointSearchParams params = buildEndpointParams(qp);
                results = check ep:searchEndpoints(params);
                total = results.length();
            }
            "OrganizationAffiliation" => {
                types:OrgAffiliationSearchParams params = buildAffiliationParams(qp);
                results = check org_affiliation:searchOrgAffiliations(params);
                total = results.length();
            }
            _ => {
                return error("Unsupported resource type for ITI-90: " + ctx.resourceType);
            }
        }

        json bundle = fhir_utils:buildSearchBundle(ctx.resourceType, results, total, baseUrl);
        http:Response resp = new;
        resp.statusCode = 200;
        resp.setJsonPayload(bundle);
        return resp;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ITI-91 — mCSD Subscription (Request Care Services Updates)
// ─────────────────────────────────────────────────────────────────────────────

public class ITI91HistoryHandler {
    *TransactionHandler;

    public function authenticate(TransactionContext ctx) returns error? =>
        defaultAuthenticate(ctx);

    public function authorize(TransactionContext ctx) returns error? =>
        defaultAuthorize(ctx);

    public function audit(TransactionContext ctx, http:Response resp) returns error? =>
        defaultAudit(ctx, resp);

    public function execute(TransactionContext ctx) returns http:Response|error {
        map<string[]> qp = ctx.request.getQueryParams();
        string? since = getFirst(qp, "_since");

        types:HistoryRow[] rows = check history:getResourceHistory(ctx.resourceType, since);
        string baseUrl = "/fhir/" + ctx.resourceType + "/_history";
        json bundle = fhir_utils:buildHistoryBundle(rows, ctx.resourceType, baseUrl);

        http:Response resp = new;
        resp.statusCode = 200;
        resp.setJsonPayload(bundle);
        return resp;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ITI-130 — Care Services Update Feed (Create / Update / Delete)
// ─────────────────────────────────────────────────────────────────────────────

public class ITI130FeedHandler {
    *TransactionHandler;

    public function authenticate(TransactionContext ctx) returns error? =>
        defaultAuthenticate(ctx);

    public function authorize(TransactionContext ctx) returns error? =>
        defaultAuthorize(ctx);

    public function audit(TransactionContext ctx, http:Response resp) returns error? =>
        defaultAudit(ctx, resp);

    public function execute(TransactionContext ctx) returns http:Response|error {
        string method = ctx.request.method;
        http:Response resp = new;

        match method {
            "POST" => {
                json payload = check ctx.request.getJsonPayload();
                string id = check dispatchCreate(ctx.resourceType, payload);
                resp.statusCode = 201;
                resp.setHeader("Location", "/fhir/" + ctx.resourceType + "/" + id);
                resp.setJsonPayload({"resourceType": ctx.resourceType, "id": id});
            }
            "PUT" => {
                json payload = check ctx.request.getJsonPayload();
                string id = (check payload.id).toString();
                boolean updated = check dispatchUpdate(ctx.resourceType, id, payload);
                resp.statusCode = updated ? 200 : 404;
            }
            "DELETE" => {
                // Extract resource ID from the last path segment (e.g. /fhir/Organization/{id})
                string rawPath = ctx.request.rawPath;
                string[] parts = re `/`.split(rawPath);
                string id = parts[parts.length() - 1];
                boolean deleted = check dispatchDelete(ctx.resourceType, id);
                resp.statusCode = deleted ? 204 : 404;
            }
            _ => {
                return error("Unsupported HTTP method for ITI-130: " + method);
            }
        }
        return resp;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Factory — resolve handler by transaction type
// ─────────────────────────────────────────────────────────────────────────────

public function getHandler(string txType, string resourceType) returns TransactionHandler|error {
    match txType {
        "ITI-90"  => { return new ITI90SearchHandler(); }
        "ITI-91"  => { return new ITI91HistoryHandler(); }
        "ITI-130" => { return new ITI130FeedHandler(); }
        _         => { return error("Unknown transaction type: " + txType); }
    }
}
