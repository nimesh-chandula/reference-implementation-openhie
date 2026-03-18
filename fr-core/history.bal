import wso2/FRCoreService.types;
import wso2/FRCoreService.history as historyMod;
import wso2/FRCoreService.fhir_utils;
// ITI-91: Request Care Services Updates
// Handles _history endpoint logic for Location, Organization, HealthcareService

// Allowed resource types for history queries
final string[] HISTORY_RESOURCE_TYPES = ["Location", "Organization", "HealthcareService"];

// Fetch and build a FHIR history Bundle for a given resource type
// since: optional ISO 8601 datetime string (e.g. "2026-01-01T00:00:00Z")
function handleHistory(string resourceType, string? since, string baseUrl) returns json|error {
    if !HISTORY_RESOURCE_TYPES.some(isolated function(string rt) returns boolean { return rt == resourceType; }) {
        return error("History not supported for resource type: " + resourceType);
    }

    types:HistoryRow[] rows = check historyMod:getResourceHistory(resourceType, since);
    return fhir_utils:buildHistoryBundle(rows, resourceType, baseUrl);
}

// Validate an ISO 8601 datetime string for the _since parameter
// Returns true if the format looks valid (basic check)
function isValidSince(string since) returns boolean {
    // Must start with a 4-digit year
    if since.length() < 10 {
        return false;
    }
    // Simple structural check: YYYY-MM-DD minimum
    string year = since.substring(0, 4);
    int|error y = int:fromString(year);
    return y is int && y > 1900 && y < 2200;
}
