import ballerina/http;
import ballerina/log;
import ballerinax/health.fhir.r4;
import ballerinax/health.fhirr4;
import healthcare_samples/mcsd_package;
import wso2/FRCoreService.r4_api_config;
import wso2/FRCoreService.types;
import wso2/FRCoreService.db;
import wso2/FRCoreService.fhir_utils;
import wso2/FRCoreService.organization as organizationMod;
import wso2/FRCoreService.location as locationMod;
import wso2/FRCoreService.healthcare_service as healthcareServiceMod;
import wso2/FRCoreService.endpoint as endpointMod;
import wso2/FRCoreService.org_affiliation as orgAffiliationMod;
import wso2/FRCoreService.validation;

// Validation pipeline — shared across all resource write handlers (Step 5)
final validation:ValidationPipeline validationPipeline = validation:buildDefaultPipeline();

configurable int port = 9098;
configurable int adminPort = 9099;
configurable string fhirBaseUrl = "http://localhost:9098/fhir";

// Admin listener — separate port to avoid conflict with fhirr4:Listener's internal http:Listener
listener http:Listener adminListener = check new (adminPort);

// Per-resource FHIR listeners (all share port via Ballerina port-sharing)
listener fhirr4:Listener orgFhirListener = check new fhirr4:Listener(config = r4_api_config:organizationApiConfig);
listener fhirr4:Listener locFhirListener = check new fhirr4:Listener(config = r4_api_config:locationApiConfig);
listener fhirr4:Listener svcFhirListener = check new fhirr4:Listener(config = r4_api_config:healthcareServiceApiConfig);
listener fhirr4:Listener epFhirListener = check new fhirr4:Listener(config = r4_api_config:endpointApiConfig);
listener fhirr4:Listener affFhirListener = check new fhirr4:Listener(config = r4_api_config:organizationAffiliationApiConfig);

// ─────────────────────────────────────────────────────────────
// Module init — run once at startup
// ─────────────────────────────────────────────────────────────
function init() returns error? {
    registerObserver(auditObserver);
    mcsd_package:initialize();
    check db:initDatabase();
    log:printInfo("FR Core Service started", port = port, fhirBaseUrl = fhirBaseUrl);
}

// ─────────────────────────────────────────────────────────────
// ORGANIZATION — ITI-90 (Read + Search) + ITI-91 (History) + ITI-130 (CRUD)
// ─────────────────────────────────────────────────────────────
service /fhir/Organization on orgFhirListener {

    // ITI-90 Search (also handles POST /_search automatically)
    resource function get .(r4:FHIRContext fhirContext) returns json|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-90") {
            return r4:createFHIRError("ITI-90 Find Matching Care Services is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("GET", "/fhir/Organization");
        types:OrgSearchParams params = fhirContextToOrgSearchParams(fhirContext);
        json[]|error results = organizationMod:searchOrganizations(params);
        if results is error {
            return r4:createFHIRError("Organization search failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = results.message());
        }
        int|error total = organizationMod:countOrganizations(params);
        int totalVal = total is int ? total : results.length();
        sendAudit("search", "Organization", "*", "0");
        return fhir_utils:buildSearchBundle("Organization", results, totalVal, fhirBaseUrl + "/Organization");
    }

    // ITI-90 Read
    resource function get [string id](r4:FHIRContext fhirContext)
            returns mcsd_package:MCSDOrganization|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-90") {
            return r4:createFHIRError("ITI-90 Find Matching Care Services is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("GET", "/fhir/Organization/" + id);
        json|()|error result = organizationMod:getOrganization(id);
        if result is error {
            return r4:createFHIRError("Organization read failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = result.message());
        }
        if result is () {
            return r4:createFHIRError("Organization/" + id + " not found", r4:ERROR, r4:PROCESSING_NOT_FOUND,
                    httpStatusCode = 404);
        }
        mcsd_package:MCSDOrganization|error org = result.cloneWithType(mcsd_package:MCSDOrganization);
        if org is error {
            return r4:createFHIRError("Organization parse failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = org.message());
        }
        sendAudit("read", "Organization", id, "0");
        return org;
    }

    // ITI-91 Type History
    resource function get _history(r4:FHIRContext fhirContext) returns json|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-91") {
            return r4:createFHIRError("ITI-91 Request Care Services Updates is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("GET", "/fhir/Organization/_history");
        r4:RequestSearchParameter[]? sinceParams = fhirContext.getRequestSearchParameter("_since");
        string? since = sinceParams is r4:RequestSearchParameter[] && sinceParams.length() > 0
                ? sinceParams[0].value : ();
        json|error bundle = handleHistory("Organization", since, fhirBaseUrl);
        if bundle is error {
            return r4:createFHIRError("Organization history failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = bundle.message());
        }
        sendAudit("history", "Organization", "*", "0");
        return bundle;
    }

    // ITI-91 Instance History
    resource function get [string id]/_history(r4:FHIRContext fhirContext) returns json|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-91") {
            return r4:createFHIRError("ITI-91 Request Care Services Updates is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("GET", "/fhir/Organization/" + id + "/_history");
        json|error bundle = handleHistory("Organization", (), fhirBaseUrl);
        if bundle is error {
            return r4:createFHIRError("Organization history failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = bundle.message());
        }
        sendAudit("history", "Organization", id, "0");
        return bundle;
    }

    // ITI-130 Create
    resource function post .(r4:FHIRContext fhirContext, json payload)
            returns mcsd_package:MCSDOrganization|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-130") {
            return r4:createFHIRError("ITI-130 Care Services Feed is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("POST", "/fhir/Organization");

        // Validate payload
        validation:ValidationResult vr = validationPipeline.run({
            resourceType: "Organization",
            payload: payload,
            tenantId: fhir_utils:getIgConfig().id,
            operation: "create"
        });
        if !vr.valid {
            return r4:createFHIRError(vr.errors[0], r4:ERROR, r4:INVALID, httpStatusCode = 422);
        }

        string typeCode = fhir_utils:extractTypeCode(payload);
        string|error createdId;
        if typeCode == "jurisdiction" {
            mcsd_package:MCSDJurisdictionOrganization|error org =
                    payload.cloneWithType(mcsd_package:MCSDJurisdictionOrganization);
            if org is error {
                return r4:createFHIRError("Invalid MCSDJurisdictionOrganization", r4:ERROR, r4:INVALID,
                        diagnostic = org.message(), httpStatusCode = 400);
            }
            createdId = organizationMod:createOrganization(org);
        } else {
            mcsd_package:MCSDFacilityOrganization|error org =
                    payload.cloneWithType(mcsd_package:MCSDFacilityOrganization);
            if org is error {
                return r4:createFHIRError("Invalid MCSDFacilityOrganization", r4:ERROR, r4:INVALID,
                        diagnostic = org.message(), httpStatusCode = 400);
            }
            createdId = organizationMod:createOrganization(org);
        }
        if createdId is error {
            log:printError("Create Organization error", 'error = createdId);
            return r4:createFHIRError("Create Organization failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = createdId.message());
        }
        json|()|error created = organizationMod:getOrganization(createdId);
        if created !is json {
            return r4:createFHIRError("Could not retrieve created Organization", r4:ERROR, r4:TRANSIENT_EXCEPTION);
        }
        mcsd_package:MCSDOrganization|error org = created.cloneWithType(mcsd_package:MCSDOrganization);
        if org is error {
            return r4:createFHIRError("Organization parse failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = org.message());
        }
        sendAudit("create", "Organization", createdId, "0");
        fhirContext.setResponseStatusCode(201);
        fhirContext.addResponseHeader("Location", fhirBaseUrl + "/Organization/" + createdId);
        return org;
    }

    // ITI-130 Update
    resource function put [string id](r4:FHIRContext fhirContext, json payload)
            returns mcsd_package:MCSDOrganization|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-130") {
            return r4:createFHIRError("ITI-130 Care Services Feed is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("PUT", "/fhir/Organization/" + id);
        // Validate payload
        validation:ValidationResult vrOrg = validationPipeline.run({
            resourceType: "Organization",
            payload: payload,
            tenantId: fhir_utils:getIgConfig().id,
            operation: "update"
        });
        if !vrOrg.valid {
            return r4:createFHIRError(vrOrg.errors[0], r4:ERROR, r4:INVALID, httpStatusCode = 422);
        }
        boolean|error updated = organizationMod:updateOrganization(id, payload);
        if updated is error {
            return r4:createFHIRError("Update Organization failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = updated.message());
        }
        if !updated {
            return r4:createFHIRError("Organization/" + id + " not found", r4:ERROR, r4:PROCESSING_NOT_FOUND,
                    httpStatusCode = 404);
        }
        json|()|error result = organizationMod:getOrganization(id);
        if result !is json {
            return r4:createFHIRError("Could not retrieve updated Organization", r4:ERROR, r4:TRANSIENT_EXCEPTION);
        }
        mcsd_package:MCSDOrganization|error org = result.cloneWithType(mcsd_package:MCSDOrganization);
        if org is error {
            return r4:createFHIRError("Organization parse failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = org.message());
        }
        sendAudit("update", "Organization", id, "0");
        return org;
    }

    // ITI-130 Delete
    resource function delete [string id](r4:FHIRContext fhirContext) returns r4:FHIRError? {
        if !fhir_utils:isTransactionEnabled("ITI-130") {
            return r4:createFHIRError("ITI-130 Care Services Feed is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("DELETE", "/fhir/Organization/" + id);
        boolean|error deleted = organizationMod:deleteOrganization(id);
        if deleted is error {
            return r4:createFHIRError("Delete Organization failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = deleted.message());
        }
        if !deleted {
            return r4:createFHIRError("Organization/" + id + " not found", r4:ERROR, r4:PROCESSING_NOT_FOUND,
                    httpStatusCode = 404);
        }
        sendAudit("delete", "Organization", id, "0");
        fhirContext.setResponseStatusCode(204);
        return ();
    }
}

// ─────────────────────────────────────────────────────────────
// LOCATION — ITI-90 + ITI-91 + ITI-130
// ─────────────────────────────────────────────────────────────
service /fhir/Location on locFhirListener {

    resource function get .(r4:FHIRContext fhirContext) returns json|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-90") {
            return r4:createFHIRError("ITI-90 Find Matching Care Services is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("GET", "/fhir/Location");
        types:LocationSearchParams params = fhirContextToLocationSearchParams(fhirContext);
        json[]|error results = locationMod:searchLocations(params);
        if results is error {
            return r4:createFHIRError("Location search failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = results.message());
        }
        int|error total = locationMod:countLocations(params);
        int totalVal = total is int ? total : results.length();
        sendAudit("search", "Location", "*", "0");
        return fhir_utils:buildSearchBundle("Location", results, totalVal, fhirBaseUrl + "/Location");
    }

    resource function get [string id](r4:FHIRContext fhirContext)
            returns mcsd_package:MCSDLocation|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-90") {
            return r4:createFHIRError("ITI-90 Find Matching Care Services is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("GET", "/fhir/Location/" + id);
        json|()|error result = locationMod:getLocation(id);
        if result is error {
            return r4:createFHIRError("Location read failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = result.message());
        }
        if result is () {
            return r4:createFHIRError("Location/" + id + " not found", r4:ERROR, r4:PROCESSING_NOT_FOUND,
                    httpStatusCode = 404);
        }
        mcsd_package:MCSDLocation|error loc = result.cloneWithType(mcsd_package:MCSDLocation);
        if loc is error {
            return r4:createFHIRError("Location parse failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = loc.message());
        }
        sendAudit("read", "Location", id, "0");
        return loc;
    }

    resource function get _history(r4:FHIRContext fhirContext) returns json|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-91") {
            return r4:createFHIRError("ITI-91 Request Care Services Updates is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("GET", "/fhir/Location/_history");
        r4:RequestSearchParameter[]? sinceParams = fhirContext.getRequestSearchParameter("_since");
        string? since = sinceParams is r4:RequestSearchParameter[] && sinceParams.length() > 0
                ? sinceParams[0].value : ();
        json|error bundle = handleHistory("Location", since, fhirBaseUrl);
        if bundle is error {
            return r4:createFHIRError("Location history failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = bundle.message());
        }
        sendAudit("history", "Location", "*", "0");
        return bundle;
    }

    resource function get [string id]/_history(r4:FHIRContext fhirContext) returns json|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-91") {
            return r4:createFHIRError("ITI-91 Request Care Services Updates is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("GET", "/fhir/Location/" + id + "/_history");
        json|error bundle = handleHistory("Location", (), fhirBaseUrl);
        if bundle is error {
            return r4:createFHIRError("Location history failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = bundle.message());
        }
        sendAudit("history", "Location", id, "0");
        return bundle;
    }

    resource function post .(r4:FHIRContext fhirContext, json payload)
            returns mcsd_package:MCSDLocation|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-130") {
            return r4:createFHIRError("ITI-130 Care Services Feed is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("POST", "/fhir/Location");
        // Validate payload
        validation:ValidationResult vrLoc = validationPipeline.run({
            resourceType: "Location",
            payload: payload,
            tenantId: fhir_utils:getIgConfig().id,
            operation: "create"
        });
        if !vrLoc.valid {
            return r4:createFHIRError(vrLoc.errors[0], r4:ERROR, r4:INVALID, httpStatusCode = 422);
        }
        string typeCode = fhir_utils:extractTypeCode(payload);
        string|error createdId;
        if typeCode == "jurisdiction" {
            mcsd_package:MCSDJurisdictionLocation|error loc =
                    payload.cloneWithType(mcsd_package:MCSDJurisdictionLocation);
            if loc is error {
                return r4:createFHIRError("Invalid MCSDJurisdictionLocation", r4:ERROR, r4:INVALID,
                        diagnostic = loc.message(), httpStatusCode = 400);
            }
            createdId = locationMod:createLocation(loc);
        } else {
            mcsd_package:MCSDFacilityLocation|error loc =
                    payload.cloneWithType(mcsd_package:MCSDFacilityLocation);
            if loc is error {
                return r4:createFHIRError("Invalid MCSDFacilityLocation", r4:ERROR, r4:INVALID,
                        diagnostic = loc.message(), httpStatusCode = 400);
            }
            createdId = locationMod:createLocation(loc);
        }
        if createdId is error {
            log:printError("Create Location error", 'error = createdId);
            return r4:createFHIRError("Create Location failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = createdId.message());
        }
        json|()|error created = locationMod:getLocation(createdId);
        if created !is json {
            return r4:createFHIRError("Could not retrieve created Location", r4:ERROR, r4:TRANSIENT_EXCEPTION);
        }
        mcsd_package:MCSDLocation|error loc = created.cloneWithType(mcsd_package:MCSDLocation);
        if loc is error {
            return r4:createFHIRError("Location parse failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = loc.message());
        }
        sendAudit("create", "Location", createdId, "0");
        fhirContext.setResponseStatusCode(201);
        fhirContext.addResponseHeader("Location", fhirBaseUrl + "/Location/" + createdId);
        return loc;
    }

    resource function put [string id](r4:FHIRContext fhirContext, json payload)
            returns mcsd_package:MCSDLocation|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-130") {
            return r4:createFHIRError("ITI-130 Care Services Feed is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("PUT", "/fhir/Location/" + id);
        // Validate payload
        validation:ValidationResult vrLocUpd = validationPipeline.run({
            resourceType: "Location",
            payload: payload,
            tenantId: fhir_utils:getIgConfig().id,
            operation: "update"
        });
        if !vrLocUpd.valid {
            return r4:createFHIRError(vrLocUpd.errors[0], r4:ERROR, r4:INVALID, httpStatusCode = 422);
        }
        boolean|error updated = locationMod:updateLocation(id, payload);
        if updated is error {
            return r4:createFHIRError("Update Location failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = updated.message());
        }
        if !updated {
            return r4:createFHIRError("Location/" + id + " not found", r4:ERROR, r4:PROCESSING_NOT_FOUND,
                    httpStatusCode = 404);
        }
        json|()|error result = locationMod:getLocation(id);
        if result !is json {
            return r4:createFHIRError("Could not retrieve updated Location", r4:ERROR, r4:TRANSIENT_EXCEPTION);
        }
        mcsd_package:MCSDLocation|error loc = result.cloneWithType(mcsd_package:MCSDLocation);
        if loc is error {
            return r4:createFHIRError("Location parse failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = loc.message());
        }
        sendAudit("update", "Location", id, "0");
        return loc;
    }

    resource function delete [string id](r4:FHIRContext fhirContext) returns r4:FHIRError? {
        if !fhir_utils:isTransactionEnabled("ITI-130") {
            return r4:createFHIRError("ITI-130 Care Services Feed is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("DELETE", "/fhir/Location/" + id);
        boolean|error deleted = locationMod:deleteLocation(id);
        if deleted is error {
            return r4:createFHIRError("Delete Location failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = deleted.message());
        }
        if !deleted {
            return r4:createFHIRError("Location/" + id + " not found", r4:ERROR, r4:PROCESSING_NOT_FOUND,
                    httpStatusCode = 404);
        }
        sendAudit("delete", "Location", id, "0");
        fhirContext.setResponseStatusCode(204);
        return ();
    }
}

// ─────────────────────────────────────────────────────────────
// HEALTHCARE SERVICE — ITI-90 + ITI-91 + ITI-130
// ─────────────────────────────────────────────────────────────
service /fhir/HealthcareService on svcFhirListener {

    resource function get .(r4:FHIRContext fhirContext) returns json|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-90") {
            return r4:createFHIRError("ITI-90 Find Matching Care Services is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("GET", "/fhir/HealthcareService");
        types:HealthcareServiceSearchParams params = fhirContextToSvcSearchParams(fhirContext);
        json[]|error results = healthcareServiceMod:searchHealthcareServices(params);
        if results is error {
            return r4:createFHIRError("HealthcareService search failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = results.message());
        }
        sendAudit("search", "HealthcareService", "*", "0");
        return fhir_utils:buildSearchBundle("HealthcareService", results, results.length(), fhirBaseUrl + "/HealthcareService");
    }

    resource function get [string id](r4:FHIRContext fhirContext)
            returns mcsd_package:MCSDHealthcareService|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-90") {
            return r4:createFHIRError("ITI-90 Find Matching Care Services is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("GET", "/fhir/HealthcareService/" + id);
        json|()|error result = healthcareServiceMod:getHealthcareService(id);
        if result is error {
            return r4:createFHIRError("HealthcareService read failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = result.message());
        }
        if result is () {
            return r4:createFHIRError("HealthcareService/" + id + " not found", r4:ERROR, r4:PROCESSING_NOT_FOUND,
                    httpStatusCode = 404);
        }
        mcsd_package:MCSDHealthcareService|error svc = result.cloneWithType(mcsd_package:MCSDHealthcareService);
        if svc is error {
            return r4:createFHIRError("HealthcareService parse failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = svc.message());
        }
        sendAudit("read", "HealthcareService", id, "0");
        return svc;
    }

    resource function get _history(r4:FHIRContext fhirContext) returns json|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-91") {
            return r4:createFHIRError("ITI-91 Request Care Services Updates is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("GET", "/fhir/HealthcareService/_history");
        r4:RequestSearchParameter[]? sinceParams = fhirContext.getRequestSearchParameter("_since");
        string? since = sinceParams is r4:RequestSearchParameter[] && sinceParams.length() > 0
                ? sinceParams[0].value : ();
        json|error bundle = handleHistory("HealthcareService", since, fhirBaseUrl);
        if bundle is error {
            return r4:createFHIRError("HealthcareService history failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = bundle.message());
        }
        sendAudit("history", "HealthcareService", "*", "0");
        return bundle;
    }

    resource function post .(r4:FHIRContext fhirContext, json payload)
            returns mcsd_package:MCSDHealthcareService|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-130") {
            return r4:createFHIRError("ITI-130 Care Services Feed is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("POST", "/fhir/HealthcareService");
        // Validate payload
        validation:ValidationResult vrHs = validationPipeline.run({
            resourceType: "HealthcareService",
            payload: payload,
            tenantId: fhir_utils:getIgConfig().id,
            operation: "create"
        });
        if !vrHs.valid {
            return r4:createFHIRError(vrHs.errors[0], r4:ERROR, r4:INVALID, httpStatusCode = 422);
        }
        mcsd_package:MCSDHealthcareService|error svc = payload.cloneWithType(mcsd_package:MCSDHealthcareService);
        if svc is error {
            return r4:createFHIRError("Invalid MCSDHealthcareService", r4:ERROR, r4:INVALID,
                    diagnostic = svc.message(), httpStatusCode = 400);
        }
        string|error createdId = healthcareServiceMod:createHealthcareService(svc);
        if createdId is error {
            return r4:createFHIRError("Create HealthcareService failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = createdId.message());
        }
        json|()|error created = healthcareServiceMod:getHealthcareService(createdId);
        if created !is json {
            return r4:createFHIRError("Could not retrieve created HealthcareService", r4:ERROR, r4:TRANSIENT_EXCEPTION);
        }
        mcsd_package:MCSDHealthcareService|error result = created.cloneWithType(mcsd_package:MCSDHealthcareService);
        if result is error {
            return r4:createFHIRError("HealthcareService parse failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = result.message());
        }
        sendAudit("create", "HealthcareService", createdId, "0");
        fhirContext.setResponseStatusCode(201);
        fhirContext.addResponseHeader("Location", fhirBaseUrl + "/HealthcareService/" + createdId);
        return result;
    }

    resource function put [string id](r4:FHIRContext fhirContext, json payload)
            returns mcsd_package:MCSDHealthcareService|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-130") {
            return r4:createFHIRError("ITI-130 Care Services Feed is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("PUT", "/fhir/HealthcareService/" + id);
        // Validate payload
        validation:ValidationResult vrHsUpd = validationPipeline.run({
            resourceType: "HealthcareService",
            payload: payload,
            tenantId: fhir_utils:getIgConfig().id,
            operation: "update"
        });
        if !vrHsUpd.valid {
            return r4:createFHIRError(vrHsUpd.errors[0], r4:ERROR, r4:INVALID, httpStatusCode = 422);
        }
        boolean|error updated = healthcareServiceMod:updateHealthcareService(id, payload);
        if updated is error {
            return r4:createFHIRError("Update HealthcareService failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = updated.message());
        }
        if !updated {
            return r4:createFHIRError("HealthcareService/" + id + " not found", r4:ERROR, r4:PROCESSING_NOT_FOUND,
                    httpStatusCode = 404);
        }
        json|()|error result2 = healthcareServiceMod:getHealthcareService(id);
        if result2 !is json {
            return r4:createFHIRError("Could not retrieve updated HealthcareService", r4:ERROR, r4:TRANSIENT_EXCEPTION);
        }
        mcsd_package:MCSDHealthcareService|error svc = result2.cloneWithType(mcsd_package:MCSDHealthcareService);
        if svc is error {
            return r4:createFHIRError("HealthcareService parse failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = svc.message());
        }
        sendAudit("update", "HealthcareService", id, "0");
        return svc;
    }

    resource function delete [string id](r4:FHIRContext fhirContext) returns r4:FHIRError? {
        if !fhir_utils:isTransactionEnabled("ITI-130") {
            return r4:createFHIRError("ITI-130 Care Services Feed is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("DELETE", "/fhir/HealthcareService/" + id);
        boolean|error deleted = healthcareServiceMod:deleteHealthcareService(id);
        if deleted is error {
            return r4:createFHIRError("Delete HealthcareService failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = deleted.message());
        }
        if !deleted {
            return r4:createFHIRError("HealthcareService/" + id + " not found", r4:ERROR, r4:PROCESSING_NOT_FOUND,
                    httpStatusCode = 404);
        }
        sendAudit("delete", "HealthcareService", id, "0");
        fhirContext.setResponseStatusCode(204);
        return ();
    }
}

// ─────────────────────────────────────────────────────────────
// ENDPOINT — ITI-90 (Read + Search) + Create
// ─────────────────────────────────────────────────────────────
service /fhir/Endpoint on epFhirListener {

    resource function get .(r4:FHIRContext fhirContext) returns json|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-90") {
            return r4:createFHIRError("ITI-90 Find Matching Care Services is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("GET", "/fhir/Endpoint");
        types:EndpointSearchParams params = fhirContextToEndpointSearchParams(fhirContext);
        json[]|error results = endpointMod:searchEndpoints(params);
        if results is error {
            return r4:createFHIRError("Endpoint search failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = results.message());
        }
        sendAudit("search", "Endpoint", "*", "0");
        return fhir_utils:buildSearchBundle("Endpoint", results, results.length(), fhirBaseUrl + "/Endpoint");
    }

    resource function get [string id](r4:FHIRContext fhirContext)
            returns mcsd_package:MCSDEndpoint|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-90") {
            return r4:createFHIRError("ITI-90 Find Matching Care Services is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("GET", "/fhir/Endpoint/" + id);
        json|()|error result = endpointMod:getEndpoint(id);
        if result is error {
            return r4:createFHIRError("Endpoint read failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = result.message());
        }
        if result is () {
            return r4:createFHIRError("Endpoint/" + id + " not found", r4:ERROR, r4:PROCESSING_NOT_FOUND,
                    httpStatusCode = 404);
        }
        mcsd_package:MCSDEndpoint|error ep = result.cloneWithType(mcsd_package:MCSDEndpoint);
        if ep is error {
            return r4:createFHIRError("Endpoint parse failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = ep.message());
        }
        sendAudit("read", "Endpoint", id, "0");
        return ep;
    }

    resource function post .(r4:FHIRContext fhirContext, json payload)
            returns mcsd_package:MCSDEndpoint|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-130") {
            return r4:createFHIRError("ITI-130 Care Services Feed is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("POST", "/fhir/Endpoint");
        // Validate payload
        validation:ValidationResult vrEp = validationPipeline.run({
            resourceType: "Endpoint",
            payload: payload,
            tenantId: fhir_utils:getIgConfig().id,
            operation: "create"
        });
        if !vrEp.valid {
            return r4:createFHIRError(vrEp.errors[0], r4:ERROR, r4:INVALID, httpStatusCode = 422);
        }
        mcsd_package:MCSDEndpoint|error ep = payload.cloneWithType(mcsd_package:MCSDEndpoint);
        if ep is error {
            return r4:createFHIRError("Invalid MCSDEndpoint", r4:ERROR, r4:INVALID,
                    diagnostic = ep.message(), httpStatusCode = 400);
        }
        string|error createdId = endpointMod:createEndpoint(ep);
        if createdId is error {
            return r4:createFHIRError("Create Endpoint failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = createdId.message());
        }
        json|()|error created = endpointMod:getEndpoint(createdId);
        if created !is json {
            return r4:createFHIRError("Could not retrieve created Endpoint", r4:ERROR, r4:TRANSIENT_EXCEPTION);
        }
        mcsd_package:MCSDEndpoint|error result = created.cloneWithType(mcsd_package:MCSDEndpoint);
        if result is error {
            return r4:createFHIRError("Endpoint parse failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = result.message());
        }
        sendAudit("create", "Endpoint", createdId, "0");
        fhirContext.setResponseStatusCode(201);
        fhirContext.addResponseHeader("Location", fhirBaseUrl + "/Endpoint/" + createdId);
        return result;
    }
}

// ─────────────────────────────────────────────────────────────
// ORGANIZATION AFFILIATION — ITI-90 (Read + Search) + Create
// ─────────────────────────────────────────────────────────────
service /fhir/OrganizationAffiliation on affFhirListener {

    resource function get .(r4:FHIRContext fhirContext) returns json|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-90") {
            return r4:createFHIRError("ITI-90 Find Matching Care Services is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("GET", "/fhir/OrganizationAffiliation");
        types:OrgAffiliationSearchParams params = fhirContextToAffiliationSearchParams(fhirContext);
        json[]|error results = orgAffiliationMod:searchOrgAffiliations(params);
        if results is error {
            return r4:createFHIRError("OrganizationAffiliation search failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = results.message());
        }
        sendAudit("search", "OrganizationAffiliation", "*", "0");
        return fhir_utils:buildSearchBundle("OrganizationAffiliation", results, results.length(),
                fhirBaseUrl + "/OrganizationAffiliation");
    }

    resource function get [string id](r4:FHIRContext fhirContext)
            returns mcsd_package:MCSDOrganizationAffiliation|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-90") {
            return r4:createFHIRError("ITI-90 Find Matching Care Services is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("GET", "/fhir/OrganizationAffiliation/" + id);
        json|()|error result = orgAffiliationMod:getOrgAffiliation(id);
        if result is error {
            return r4:createFHIRError("OrganizationAffiliation read failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = result.message());
        }
        if result is () {
            return r4:createFHIRError("OrganizationAffiliation/" + id + " not found", r4:ERROR,
                    r4:PROCESSING_NOT_FOUND, httpStatusCode = 404);
        }
        mcsd_package:MCSDOrganizationAffiliation|error aff =
                result.cloneWithType(mcsd_package:MCSDOrganizationAffiliation);
        if aff is error {
            return r4:createFHIRError("OrganizationAffiliation parse failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = aff.message());
        }
        sendAudit("read", "OrganizationAffiliation", id, "0");
        return aff;
    }

    resource function post .(r4:FHIRContext fhirContext, json payload)
            returns mcsd_package:MCSDOrganizationAffiliation|r4:FHIRError {
        if !fhir_utils:isTransactionEnabled("ITI-130") {
            return r4:createFHIRError("ITI-130 Care Services Feed is not enabled for this tenant",
                    r4:ERROR, r4:PROCESSING_NOT_SUPPORTED, httpStatusCode = 501);
        }
        logRequest("POST", "/fhir/OrganizationAffiliation");
        // Validate payload
        validation:ValidationResult vrAff = validationPipeline.run({
            resourceType: "OrganizationAffiliation",
            payload: payload,
            tenantId: fhir_utils:getIgConfig().id,
            operation: "create"
        });
        if !vrAff.valid {
            return r4:createFHIRError(vrAff.errors[0], r4:ERROR, r4:INVALID, httpStatusCode = 422);
        }
        mcsd_package:MCSDOrganizationAffiliation|error aff =
                payload.cloneWithType(mcsd_package:MCSDOrganizationAffiliation);
        if aff is error {
            return r4:createFHIRError("Invalid MCSDOrganizationAffiliation", r4:ERROR, r4:INVALID,
                    diagnostic = aff.message(), httpStatusCode = 400);
        }
        string|error createdId = orgAffiliationMod:createOrgAffiliation(aff);
        if createdId is error {
            return r4:createFHIRError("Create OrganizationAffiliation failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = createdId.message());
        }
        json|()|error created = orgAffiliationMod:getOrgAffiliation(createdId);
        if created !is json {
            return r4:createFHIRError("Could not retrieve created OrganizationAffiliation", r4:ERROR,
                    r4:TRANSIENT_EXCEPTION);
        }
        mcsd_package:MCSDOrganizationAffiliation|error result =
                created.cloneWithType(mcsd_package:MCSDOrganizationAffiliation);
        if result is error {
            return r4:createFHIRError("OrganizationAffiliation parse failed", r4:ERROR, r4:TRANSIENT_EXCEPTION,
                    diagnostic = result.message());
        }
        sendAudit("create", "OrganizationAffiliation", createdId, "0");
        fhirContext.setResponseStatusCode(201);
        fhirContext.addResponseHeader("Location", fhirBaseUrl + "/OrganizationAffiliation/" + createdId);
        return result;
    }
}

// ─────────────────────────────────────────────────────────────
// FHIR METADATA — CapabilityStatement (ITI-90)
// ─────────────────────────────────────────────────────────────
service /fhir on orgFhirListener {
    resource function get metadata(r4:FHIRContext fhirContext) returns json {
        logRequest("GET", "/fhir/metadata");
        return buildCapabilityStatement(fhirBaseUrl, fhir_utils:getIgConfig());
    }
}

// ─────────────────────────────────────────────────────────────
// ADMIN APIs (non-FHIR, plain http:Listener)
// ─────────────────────────────────────────────────────────────
service /api/admin on adminListener {

    resource function get hierarchy() returns http:Response {
        logRequest("GET", "/api/admin/hierarchy");
        json|error result = handleGetHierarchy();
        if result is error {
            return fhirResponse(500, fhir_utils:buildOperationOutcome("fatal", "exception", result.message()));
        }
        return jsonResponse(200, result);
    }

    resource function get statistics() returns http:Response {
        logRequest("GET", "/api/admin/statistics");
        json|error result = handleGetStatistics();
        if result is error {
            return fhirResponse(500, fhir_utils:buildOperationOutcome("fatal", "exception", result.message()));
        }
        return jsonResponse(200, result);
    }

    resource function get facilities/'map() returns http:Response {
        logRequest("GET", "/api/admin/facilities/map");
        json|error result = handleGetMapGeoJson();
        if result is error {
            return fhirResponse(500, fhir_utils:buildOperationOutcome("fatal", "exception", result.message()));
        }
        return jsonResponse(200, result);
    }

    resource function post facilities/[string id]/status(http:Request req) returns http:Response {
        logRequest("POST", "/api/admin/facilities/" + id + "/status");
        json|http:ClientError bodyJson = req.getJsonPayload();
        if bodyJson is http:ClientError {
            return fhirResponse(400, fhir_utils:buildOperationOutcome("error", "invalid", "Invalid JSON body"));
        }
        json|error result = handleUpdateStatus(id, bodyJson);
        if result is error {
            return fhirResponse(result.message().includes("not found") ? 404 : 500,
                    fhir_utils:buildOperationOutcome("error", "exception", result.message()));
        }
        return jsonResponse(200, result);
    }

    resource function post 'bulk\-import(http:Request req) returns http:Response {
        logRequest("POST", "/api/admin/bulk-import");
        json|http:ClientError bodyJson = req.getJsonPayload();
        if bodyJson is http:ClientError {
            return fhirResponse(400, fhir_utils:buildOperationOutcome("error", "invalid", "Invalid JSON body — expected a FHIR Bundle"));
        }
        types:BulkImportResult|error result = handleBundleImport(bodyJson);
        if result is error {
            return fhirResponse(400, fhir_utils:buildOperationOutcome("error", "invalid", result.message()));
        }
        return jsonResponse(200, result.toJson());
    }

    resource function post 'bulk\-import/csv(http:Request req) returns http:Response {
        logRequest("POST", "/api/admin/bulk-import/csv");
        types:BulkImportResult|error result = handleCsvImport(req);
        if result is error {
            return fhirResponse(400, fhir_utils:buildOperationOutcome("error", "invalid", result.message()));
        }
        return jsonResponse(200, result.toJson());
    }

    resource function get 'audit\-logs(http:Request req) returns http:Response {
        logRequest("GET", "/api/admin/audit-logs");
        json|error result = handleGetAuditLogs(req);
        if result is error {
            return fhirResponse(502, fhir_utils:buildOperationOutcome("error", "transient", result.message()));
        }
        return jsonResponse(200, result);
    }
}

// ─────────────────────────────────────────────────────────────
// Response helpers (admin APIs only — FHIR services use fhirr4 interceptors)
// ─────────────────────────────────────────────────────────────
isolated function fhirResponse(int statusCode, json body) returns http:Response {
    http:Response res = new;
    res.statusCode = statusCode;
    res.setHeader("Content-Type", "application/fhir+json");
    res.setJsonPayload(body);
    return res;
}

isolated function jsonResponse(int statusCode, json body) returns http:Response {
    http:Response res = new;
    res.statusCode = statusCode;
    res.setHeader("Content-Type", "application/json");
    res.setJsonPayload(body);
    return res;
}

isolated function logRequest(string method, string endpoint) {
    log:printInfo(method + " " + endpoint);
}
