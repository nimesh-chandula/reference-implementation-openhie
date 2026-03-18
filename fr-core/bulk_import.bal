import ballerina/http;
import ballerina/log;
import ballerina/mime;
import ballerinax/health.fhir.r4;
import healthcare_samples/mcsd_package;
import wso2/FRCoreService.types;
import wso2/FRCoreService.fhir_utils;
import wso2/FRCoreService.organization as organizationMod;
import wso2/FRCoreService.location as locationMod;
import wso2/FRCoreService.healthcare_service as healthcareServiceMod;
import wso2/FRCoreService.endpoint as endpointMod;
import wso2/FRCoreService.org_affiliation as orgAffiliationMod;

// POST /api/admin/bulk-import — Process a FHIR Bundle (batch or transaction)
function handleBundleImport(json bundle) returns types:BulkImportResult|error {
    types:BulkImportResult result = {total: 0, created: 0, updated: 0, failed: 0, errors: []};

    json|error bundleType = bundle.resourceType;
    if bundleType is error || bundleType.toString() != "Bundle" {
        return error("Payload must be a FHIR Bundle");
    }

    json|error entriesJson = bundle.entry;
    if !(entriesJson is json[]) {
        return error("Bundle must contain an 'entry' array");
    }
    json[] entries = <json[]>entriesJson;
    result.total = entries.length();

    // Sort entries by dependency order: Organizations first, then Locations,
    // then HealthcareServices/Endpoints, then OrganizationAffiliations
    json[] sorted = sortBundleEntries(entries);

    foreach json entry in sorted {
        json|error resourceJson = entry.'resource;
        if !(resourceJson is json) {
            result.failed += 1;
            result.errors.push("Entry missing 'resource' field");
            continue;
        }

        json|error rtJson = resourceJson.resourceType;
        if !(rtJson is json) {
            result.failed += 1;
            result.errors.push("Entry resource missing 'resourceType'");
            continue;
        }
        string resourceType = rtJson.toString();

        // Determine method: check entry.request.method or infer from presence of id
        string method = "POST";
        json|error requestJson = entry.request;
        if requestJson is json {
            json|error methodJson = requestJson.method;
            if methodJson is json { method = methodJson.toString(); }
        } else {
            json|error idJson = resourceJson.id;
            if idJson is json && idJson.toString() != "" && idJson.toString() != "null" {
                method = "PUT";
            }
        }

        string|error outcome = processResourceEntry(resourceType, method, resourceJson);
        if outcome is error {
            result.failed += 1;
            result.errors.push(resourceType + ": " + outcome.message());
            log:printWarn("Bulk import entry failed", 'error = outcome, resourceType = resourceType);
        } else {
            if outcome == "created" { result.created += 1; }
            else { result.updated += 1; }
        }
    }

    return result;
}

// Process a single resource entry during bulk import
function processResourceEntry(string resourceType, string method, json resourceJson) returns string|error {
    if resourceType == "Location" {
        if method == "PUT" {
            json|error idJson = resourceJson.id;
            if !(idJson is json) { return error("PUT requires resource.id"); }
            _ = check locationMod:updateLocation(idJson.toString(), resourceJson);
            return "updated";
        } else {
            string typeCode = fhir_utils:extractTypeCode(resourceJson);
            if typeCode == "jurisdiction" {
                mcsd_package:MCSDJurisdictionLocation loc = check resourceJson.cloneWithType(mcsd_package:MCSDJurisdictionLocation);
                _ = check locationMod:createLocation(loc);
            } else {
                mcsd_package:MCSDFacilityLocation loc = check resourceJson.cloneWithType(mcsd_package:MCSDFacilityLocation);
                _ = check locationMod:createLocation(loc);
            }
            return "created";
        }
    } else if resourceType == "Organization" {
        if method == "PUT" {
            json|error idJson = resourceJson.id;
            if !(idJson is json) { return error("PUT requires resource.id"); }
            _ = check organizationMod:updateOrganization(idJson.toString(), resourceJson);
            return "updated";
        } else {
            string typeCode = fhir_utils:extractTypeCode(resourceJson);
            if typeCode == "jurisdiction" {
                mcsd_package:MCSDJurisdictionOrganization org = check resourceJson.cloneWithType(mcsd_package:MCSDJurisdictionOrganization);
                _ = check organizationMod:createOrganization(org);
            } else {
                mcsd_package:MCSDFacilityOrganization org = check resourceJson.cloneWithType(mcsd_package:MCSDFacilityOrganization);
                _ = check organizationMod:createOrganization(org);
            }
            return "created";
        }
    } else if resourceType == "HealthcareService" {
        if method == "PUT" {
            json|error idJson = resourceJson.id;
            if !(idJson is json) { return error("PUT requires resource.id"); }
            _ = check healthcareServiceMod:updateHealthcareService(idJson.toString(), resourceJson);
            return "updated";
        } else {
            mcsd_package:MCSDHealthcareService svc = check resourceJson.cloneWithType(mcsd_package:MCSDHealthcareService);
            _ = check healthcareServiceMod:createHealthcareService(svc);
            return "created";
        }
    } else if resourceType == "Endpoint" {
        mcsd_package:MCSDEndpoint ep = check resourceJson.cloneWithType(mcsd_package:MCSDEndpoint);
        _ = check endpointMod:createEndpoint(ep);
        return "created";
    } else if resourceType == "OrganizationAffiliation" {
        mcsd_package:MCSDOrganizationAffiliation aff = check resourceJson.cloneWithType(mcsd_package:MCSDOrganizationAffiliation);
        _ = check orgAffiliationMod:createOrgAffiliation(aff);
        return "created";
    }

    return error("Unsupported resource type: " + resourceType);
}

// Sort bundle entries by FK dependency order so parents are created before children
function sortBundleEntries(json[] entries) returns json[] {
    json[] orgEntries = [];
    json[] locEntries = [];
    json[] svcEntries = [];
    json[] otherEntries = [];

    foreach json entry in entries {
        json|error resourceJson = entry.'resource;
        if resourceJson is json {
            json|error rtJson = resourceJson.resourceType;
            string rt = rtJson is json ? rtJson.toString() : "";
            if rt == "Organization" {
                orgEntries.push(entry);
            } else if rt == "Location" {
                locEntries.push(entry);
            } else if rt == "HealthcareService" || rt == "Endpoint" {
                svcEntries.push(entry);
            } else {
                otherEntries.push(entry);
            }
        } else {
            otherEntries.push(entry);
        }
    }

    json[] sorted = [];
    foreach json e in orgEntries { sorted.push(e); }
    foreach json e in locEntries { sorted.push(e); }
    foreach json e in svcEntries { sorted.push(e); }
    foreach json e in otherEntries { sorted.push(e); }
    return sorted;
}

// POST /api/admin/bulk-import/csv — Process a CSV file upload (multipart/form-data)
function handleCsvImport(http:Request req) returns types:BulkImportResult|error {
    types:BulkImportResult result = {total: 0, created: 0, updated: 0, failed: 0, errors: []};

    mime:Entity[]|http:ClientError bodyParts = req.getBodyParts();
    if bodyParts is http:ClientError {
        return error("Failed to parse multipart form data: " + bodyParts.message());
    }

    byte[] csvData = [];
    foreach mime:Entity part in bodyParts {
        string|mime:HeaderNotFoundError contentDisposition = part.getHeader("content-disposition");
        if contentDisposition is string && contentDisposition.includes("name=\"file\"") {
            byte[]|mime:ParserError partContent = part.getByteArray();
            if partContent is byte[] {
                csvData = partContent;
                break;
            }
        }
    }

    if csvData.length() == 0 {
        return error("No 'file' field found in multipart form data");
    }

    string csvText = check string:fromBytes(csvData);
    string[] lines = re`\n`.split(csvText);
    if lines.length() < 2 {
        return error("CSV must have a header row and at least one data row");
    }

    // Parse header row
    string[] headers = re`,`.split(lines[0].trim());
    map<int> headerIndex = {};
    int i = 0;
    foreach string header in headers {
        headerIndex[header.trim().toLowerAscii()] = i;
        i += 1;
    }

    result.total = lines.length() - 1;

    // Process data rows
    int lineNum = 1;
    while lineNum < lines.length() {
        string line = lines[lineNum].trim();
        if line.length() == 0 {
            lineNum += 1;
            continue;
        }

        string[] fields = re`,`.split(line);
        map<string> row = {};
        foreach string headerKey in headerIndex.keys() {
            int idx = headerIndex[headerKey] ?: 0;
            row[headerKey] = idx < fields.length() ? fields[idx].trim() : "";
        }

        string|error outcome = processCsvRow(row);
        if outcome is error {
            result.failed += 1;
            result.errors.push("Row " + lineNum.toString() + ": " + outcome.message());
        } else {
            if outcome == "created" { result.created += 1; }
            else { result.updated += 1; }
        }

        lineNum += 1;
    }

    return result;
}

// Process a single CSV row — creates a paired MCSDFacilityLocation + MCSDFacilityOrganization
function processCsvRow(map<string> row) returns string|error {
    string name = row["name"] ?: "";
    if name.length() == 0 {
        return error("Missing required field: name");
    }

    string typeCode = row["type"] ?: "facility";
    string status = row["status"] ?: "active";
    string city = row["city"] ?: "";
    string district = row["district"] ?: "";
    string state = row["state"] ?: "";
    string country = row["country"] ?: "";
    string addressText = row["address"] ?: "";
    string latStr = row["latitude"] ?: "";
    string lonStr = row["longitude"] ?: "";

    // Build Organization first (to get its ID for Location.managingOrganization)
    string mCSDTypeSystem = "https://profiles.ihe.net/ITI/mCSD/CodeSystem/IHE.mCSD.Organization.Location.Types";

    r4:CodeableConcept orgTypeConcept = {
        coding: [{
            system: mCSDTypeSystem,
            code: typeCode
        }]
    };

    mcsd_package:MCSDFacilityOrganization org = {
        name: name + " Administration",
        'type: [orgTypeConcept]
    };

    string orgId = check organizationMod:createOrganization(org);

    // Build position if lat/lon provided
    mcsd_package:MCSDFacilityLocationPosition? position = ();
    if latStr.length() > 0 && lonStr.length() > 0 {
        decimal|error lat = decimal:fromString(latStr);
        decimal|error lon = decimal:fromString(lonStr);
        if lat is decimal && lon is decimal {
            position = {latitude: lat, longitude: lon};
        }
    }

    // Build address
    r4:Address? address = ();
    if addressText.length() > 0 || city.length() > 0 {
        address = {
            text: addressText.length() > 0 ? addressText : (),
            city: city.length() > 0 ? city : (),
            district: district.length() > 0 ? district : (),
            state: state.length() > 0 ? state : (),
            country: country.length() > 0 ? country : ()
        };
    }

    r4:CodeableConcept locTypeConcept = {
        coding: [{
            system: mCSDTypeSystem,
            code: typeCode
        }]
    };

    mcsd_package:MCSDFacilityLocation loc = {
        name: name,
        status: status,
        'type: [locTypeConcept],
        managingOrganization: {reference: "Organization/" + orgId},
        position: position,
        address: address
    };

    _ = check locationMod:createLocation(loc);
    return "created";
}
