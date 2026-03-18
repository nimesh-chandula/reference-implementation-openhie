// ─────────────────────────────────────────────────────────────────────────────
// Profile Adapter Pattern (§3.1)
//
// Defines the ProfileAdapter interface and a DefaultProfileAdapter backed by
// the igConfig loaded in tenant_config.bal.
//
// The interface decouples the rest of the codebase from the specific IG in use.
// A future LKProfileAdapter or BDProfileAdapter simply implements this type —
// no changes to callers required.
// ─────────────────────────────────────────────────────────────────────────────

// ProfileAdapter interface
// Consumers call this interface; they never reference igConfig directly.
public type ProfileAdapter object {
    // Returns the profile URL for the given resource type + type code.
    // typeCode: "facility" | "jurisdiction" | "" (fallback to base profile)
    public function getProfileUrl(string resourceType, string typeCode) returns string;

    // Returns the base FHIR resource type for a given profile URL.
    // e.g., "https://profiles.ihe.net/ITI/mCSD/StructureDefinition/IHE.mCSD.FacilityOrganization"
    //       → "Organization"
    public function getBaseResourceType(string profileUrl) returns string;

    // Returns the canonical base URL of the active IG.
    public function getCanonicalUrl() returns string;

    // Returns the list of FHIR resource type names supported by this tenant.
    public function getSupportedResourceTypes() returns string[];

    // Returns true if the given resource type is enabled in this tenant config.
    public function isResourceEnabled(string resourceType) returns boolean;
};

// ─────────────────────────────────────────────────────────────────────────────
// Default implementation — reads from igConfig (tenant_config.bal)
// ─────────────────────────────────────────────────────────────────────────────
public class DefaultProfileAdapter {
    *ProfileAdapter;

    public function getProfileUrl(string resourceType, string typeCode) returns string {
        // Delegates to the accessor helper in tenant_config.bal
        return getProfileUrl(resourceType, typeCode);
    }

    public function getBaseResourceType(string profileUrl) returns string {
        // Extract resource type from the profile URL's trailing segment.
        // e.g., ".../IHE.mCSD.FacilityOrganization" → look up which resource it belongs to.
        foreach IGResourceConfig rc in igConfig.resources {
            if rc.profile == profileUrl {
                return rc.resourceType;
            }
            string? fp = rc.facilityProfile;
            if fp is string && fp == profileUrl {
                return rc.resourceType;
            }
            string? jp = rc.jurisdictionProfile;
            if jp is string && jp == profileUrl {
                return rc.resourceType;
            }
        }
        // Fallback: extract the last path segment and strip any IG prefix (e.g., "IHE.mCSD.")
        int? slash = profileUrl.lastIndexOf("/");
        string segment = slash is int ? profileUrl.substring(slash + 1) : profileUrl;
        // Strip common IG prefixes to get the base resource type name
        string[] knownPrefixes = ["IHE.mCSD.", "LK", "BD"];
        foreach string prefix in knownPrefixes {
            if segment.startsWith(prefix) {
                return segment.substring(prefix.length());
            }
        }
        return segment;
    }

    public function getCanonicalUrl() returns string {
        return igConfig.canonical;
    }

    public function getSupportedResourceTypes() returns string[] {
        string[] types = [];
        foreach IGResourceConfig rc in igConfig.resources {
            types.push(rc.resourceType);
        }
        return types;
    }

    public function isResourceEnabled(string resourceType) returns boolean {
        return getResourceConfig(resourceType) is IGResourceConfig;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Module-level singleton — initialised once at startup.
// All other modules import this via `profileAdapter`.
// ─────────────────────────────────────────────────────────────────────────────
public final ProfileAdapter profileAdapter = new DefaultProfileAdapter();
