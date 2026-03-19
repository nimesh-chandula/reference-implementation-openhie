// ─────────────────────────────────────────────────────────────────────────────
// McsdIGTypeAdapter — IHE mCSD v4.0.1 implementation of IGTypeAdapter
//
// THIS IS THE ONLY FILE IN THE ENTIRE CODEBASE THAT IMPORTS mcsd_package.
// All IG-specific type coupling is isolated here.
//
// To add LK IG support: create lk_ig_adapter.bal with an LkIGTypeAdapter class
// that imports lk_package, then change igAdapterType in Config.toml.
// ─────────────────────────────────────────────────────────────────────────────
import healthcare_samples/mcsd_package;

public class McsdIGTypeAdapter {
    *IGTypeAdapter;

    public function initialize() {
        mcsd_package:initialize();
    }

    public function parseResource(string resourceType, string typeCode, json payload)
            returns json|error {
        if resourceType == "Organization" {
            if typeCode == "jurisdiction" {
                mcsd_package:MCSDJurisdictionOrganization org =
                    check payload.cloneWithType(mcsd_package:MCSDJurisdictionOrganization);
                return org.toJson();
            }
            mcsd_package:MCSDFacilityOrganization org =
                check payload.cloneWithType(mcsd_package:MCSDFacilityOrganization);
            return org.toJson();
        }
        if resourceType == "Location" {
            if typeCode == "jurisdiction" {
                mcsd_package:MCSDJurisdictionLocation loc =
                    check payload.cloneWithType(mcsd_package:MCSDJurisdictionLocation);
                return loc.toJson();
            }
            mcsd_package:MCSDFacilityLocation loc =
                check payload.cloneWithType(mcsd_package:MCSDFacilityLocation);
            return loc.toJson();
        }
        if resourceType == "HealthcareService" {
            mcsd_package:MCSDHealthcareService svc =
                check payload.cloneWithType(mcsd_package:MCSDHealthcareService);
            return svc.toJson();
        }
        if resourceType == "Endpoint" {
            mcsd_package:MCSDEndpoint ep =
                check payload.cloneWithType(mcsd_package:MCSDEndpoint);
            return ep.toJson();
        }
        if resourceType == "OrganizationAffiliation" {
            mcsd_package:MCSDOrganizationAffiliation aff =
                check payload.cloneWithType(mcsd_package:MCSDOrganizationAffiliation);
            return aff.toJson();
        }
        return payload;
    }

    public function validateRequiredFields(string resourceType, map<json> payload)
            returns string[] {
        string[] errors = [];
        if resourceType == "Organization" {
            if !hasNonEmptyField(payload, "name") {
                errors.push("Organization.name is required");
            }
        } else if resourceType == "Location" {
            if !hasNonEmptyField(payload, "name") {
                errors.push("Location.name is required");
            }
            if !hasNonEmptyField(payload, "status") {
                errors.push("Location.status is required");
            } else {
                json? statusVal = payload["status"];
                string status = statusVal is () ? "" : statusVal.toString();
                if status != "active" && status != "suspended" && status != "inactive" {
                    errors.push("Location.status must be one of: active, suspended, inactive — got: '" + status + "'");
                }
            }
        } else if resourceType == "Endpoint" {
            if !hasNonEmptyField(payload, "status") {
                errors.push("Endpoint.status is required");
            }
            if !hasNonEmptyField(payload, "connectionType") {
                errors.push("Endpoint.connectionType is required");
            }
            if !hasNonEmptyField(payload, "address") {
                errors.push("Endpoint.address is required");
            }
        }
        return errors;
    }

    public function getTypeCodeSystem() returns string =>
        "https://profiles.ihe.net/ITI/mCSD/CodeSystem/IHE.mCSD.Organization.Location.Types";

    public function getPackageName() returns string =>
        "healthcare_samples/mcsd_package:1.0.0";
}

// ─────────────────────────────────────────────────────────────────────────────
// Private helper
// ─────────────────────────────────────────────────────────────────────────────
isolated function hasNonEmptyField(map<json> payload, string fieldName) returns boolean {
    json? val = payload[fieldName];
    if val is () { return false; }
    string str = val.toString();
    return str.trim().length() > 0 && str != "null";
}
