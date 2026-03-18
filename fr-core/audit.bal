import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;

// HTTP client for ATNA audit service
final http:Client auditClient = check new (auditServiceUrl);

// ─────────────────────────────────────────────────────────────────────────────
// Audit Observer — registered with the Event Bus (event_bus.bal) at startup.
//
// This is the AuditLogger observer (§3.8). When a ResourceEvent is published,
// this function builds a FHIR AuditEvent and POSTs it to the audit service.
// It runs in its own strand so it never blocks the main request path.
// ─────────────────────────────────────────────────────────────────────────────
function auditObserver(ResourceEvent event) {
    postAuditEvent(
        eventTypeToAction(event.eventType),
        event.resourceType,
        event.resourceId,
        event.outcome
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// sendAudit — backward-compatible public API.
//
// All existing call sites (service.bal, handler files) continue to work
// unchanged. Internally, this now publishes a ResourceEvent to the bus so
// all registered observers (including auditObserver) are notified.
// ─────────────────────────────────────────────────────────────────────────────
function sendAudit(string action, string resourceType, string resourceId, string outcome) {
    publishEvent({
        eventType: actionToEventType(action),
        resourceType: resourceType,
        resourceId: resourceId,
        outcome: outcome
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal implementation — builds and posts the FHIR AuditEvent
// ─────────────────────────────────────────────────────────────────────────────
function postAuditEvent(string action, string resourceType, string resourceId, string outcome) {
    string actionCode = mapActionCode(action);
    json auditEvent = {
        "resourceType": "AuditEvent",
        "id": uuid:createType1AsString(),
        "type": {
            "system": "http://terminology.hl7.org/CodeSystem/audit-event-type",
            "code": "rest"
        },
        "subtype": [{"system": "http://hl7.org/fhir/restful-interaction", "code": action}],
        "action": actionCode,
        "outcome": outcome,
        "recorded": time:utcToString(time:utcNow()),
        "agent": [{"requestor": true, "who": {"display": "fr-core-service"}}],
        "source": {"observer": {"display": "fr-core-service"}},
        "entity": [{"what": {"reference": resourceType + "/" + resourceId}}]
    };
    http:Response|error resp = auditClient->/audits.post(auditEvent);
    if resp is error {
        log:printWarn("Failed to send audit event", 'error = resp,
                action = action, resourceType = resourceType, resourceId = resourceId);
    }
}

function mapActionCode(string action) returns string {
    if action == "create" || action == "post" { return "C"; }
    if action == "update" || action == "put" { return "U"; }
    if action == "delete" { return "D"; }
    if action == "read" || action == "search" || action == "history" { return "R"; }
    return "E";
}

// Maps a ResourceEventType back to the action string expected by postAuditEvent
function eventTypeToAction(ResourceEventType eventType) returns string {
    if eventType == RESOURCE_CREATED { return "create"; }
    if eventType == RESOURCE_UPDATED { return "update"; }
    if eventType == RESOURCE_DELETED { return "delete"; }
    if eventType == RESOURCE_SEARCHED { return "search"; }
    return "read";
}
