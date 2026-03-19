// ─────────────────────────────────────────────────────────────────────────────
// IGTypeAdapter — Plug-and-Play IG Package Abstraction
//
// Decouples the service layer from any specific IG Ballerina package
// (e.g., mcsd_package, lk_package).  Only the concrete adapter implementation
// file imports the IG package; all other files in the codebase depend only on
// this interface.
//
// To switch IGs:
//   1. Generate a new package from the target IG (e.g., lk_package)
//   2. Write a LkIGTypeAdapter implementing this interface
//   3. Change `igAdapterType = "lk"` in Config.toml
//   4. Recompile — zero other files need changing
// ─────────────────────────────────────────────────────────────────────────────

// IGTypeAdapter interface
// All consumers call this; they never import the IG package directly.
public type IGTypeAdapter object {

    // Called once at module startup (replaces mcsd_package:initialize()).
    public function initialize();

    // Validates `payload` against the IG-specific typed record for the given
    // resource type and type code.  Returns the (unchanged) validated json on
    // success, or an error whose message contains the constraint violation(s).
    //
    // resourceType : "Organization" | "Location" | "HealthcareService"
    //               | "Endpoint" | "OrganizationAffiliation"
    // typeCode     : "facility" | "jurisdiction" | "" (for single-variant resources)
    public function parseResource(string resourceType, string typeCode, json payload) returns json|error;

    // Returns IG-specific required-field violations for the given resource type.
    // Called by ProfileValidator instead of hardcoded per-resource checks.
    // Returns an empty array when all required fields are present.
    public function validateRequiredFields(string resourceType, map<json> payload) returns string[];

    // Returns the code system URL used for facility/jurisdiction type codings.
    // Used by the CSV import path to build correctly typed resource JSON.
    public function getTypeCodeSystem() returns string;

    // Human-readable package identifier — used for logging.
    public function getPackageName() returns string;
};
