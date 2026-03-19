// Active participant in the audit event
type AuditAgent record {|
    // Value Set http://hl7.org/fhir/ValueSet/participation-role-type
    string typeCode = "";
    // Human-readable name for the agent (separate from who.display)
    string name = "";
    // Display name of who performed the action
    string whoDisplay = "";
    // System URI identifying the agent's identity provider
    string whoIdentifierSystem = "";
    // Unique identifier for the agent (e.g. user ID, process ID)
    string whoIdentifierValue = "";
    // Alternative identifier (e.g. Kerberos principal, process name)
    string altId = "";
    // Network access point address (IP address or hostname)
    string networkAddress = "";
    // Network access point type: 1=machine name, 2=IP, 3=telephone, 4=email, 5=URI
    string networkType = "2";
    // Access policy URIs authorizing this agent
    string[] policy = [];
    // Value Set http://terminology.hl7.org/ValueSet/v3-PurposeOfUse
    string purposeOfUseCode = "";
    boolean requestor = false;
|};

// Entity involved in the audit event
type AuditEntity record {|
    // Value Set http://hl7.org/fhir/ValueSet/audit-entity-type
    string typeCode = "";
    // Value Set http://hl7.org/fhir/ValueSet/object-role
    string roleCode = "";
    // Relative path reference (e.g. "Patient/example")
    string whatReference = "";
    // System URI for the entity identifier (e.g. http://example.org/mrn)
    string whatIdentifierSystem = "";
    // Identifier value for the entity (e.g. patient MRN)
    string whatIdentifierValue = "";
    // Human-readable name for the entity
    string name = "";
    // Raw query string for query-type events — will be base64-encoded in entity.query
    string queryDetail = "";
    // Value Set http://terminology.hl7.org/CodeSystem/dicom-audit-lifecycle
    string lifecycleCode = "";
    // Confidentiality/security label codes on the entity
    // Value Set http://terminology.hl7.org/CodeSystem/v3-Confidentiality
    string[] securityLabelCodes = [];
|};

// Holds the information needed to form an audit event based on the FHIR AuditEvent resource
// http://hl7.org/fhir/R4/auditevent.html
type InternalAuditEvent record {|
    // Value Set http://hl7.org/fhir/ValueSet/audit-event-type
    string typeCode = "rest";
    // Value Set http://hl7.org/fhir/ValueSet/audit-event-sub-type
    string subTypeCode;
    // Value Set http://hl7.org/fhir/ValueSet/audit-event-action
    string actionCode;
    // Value Set http://hl7.org/fhir/ValueSet/audit-event-outcome
    string outcomeCode;
    // Free text description of the outcome (e.g., failure reason)
    string outcomeDesc = "";
    string recordedTime;
    // Optional period during which the activity actually occurred (distinct from recordedTime)
    string periodStart = "";
    string periodEnd = "";
    // Why the event was triggered — Value Set http://terminology.hl7.org/ValueSet/v3-PurposeOfUse
    string purposeOfEventCode = "";
    // Active participants — ATNA requires at least two: human requestor + network node
    AuditAgent[] agents;
    // Source of the event
    string sourceObserverName;
    string sourceObserverIdentifierSystem = "";
    string sourceObserverIdentifierValue = "";
    string sourceSite = "";
    // Value Set http://hl7.org/fhir/R4/valueset-audit-source-type.html
    string sourceObserverType;
    // Entities involved — include a patient entity when accessing non-Patient resources
    AuditEntity[] entities;
|};
