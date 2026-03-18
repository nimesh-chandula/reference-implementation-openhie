// ─────────────────────────────────────────────────────────────────────────────
// Event Bus — Observer Pattern (§3.8)
//
// Defines the internal resource event types and a lightweight observer registry.
// Observers register at startup (e.g., AuditLogger, HistoryRecorder).
// Publishers call publishEvent() after every create/update/delete/read operation.
//
// Each observer runs in its own strand (fire-and-forget) so the main request
// path is never blocked by observers.
// ─────────────────────────────────────────────────────────────────────────────

// Enumeration of resource lifecycle event types
public enum ResourceEventType {
    RESOURCE_CREATED,
    RESOURCE_UPDATED,
    RESOURCE_DELETED,
    RESOURCE_READ,
    RESOURCE_SEARCHED
}

// Payload passed to every observer when an event occurs
public type ResourceEvent record {|
    // The type of lifecycle event
    ResourceEventType eventType;
    // FHIR resource type name (e.g., "Organization")
    string resourceType;
    // Logical resource ID
    string resourceId;
    // FHIR outcome code: "0" = success, "4" = minor failure, "8" = serious failure
    string outcome;
    // Optional: the full FHIR resource JSON (present on create/update; absent on delete/read)
    json? 'resource = ();
|};

// Observer function type — receives a ResourceEvent, returns nothing
public type ResourceEventObserver function(ResourceEvent event);

// Module-level observer registry (not isolated — observers are registered at startup only)
ResourceEventObserver[] eventObservers = [];

// Register an observer. Call during module init / service startup.
public function registerObserver(ResourceEventObserver observer) {
    eventObservers.push(observer);
}

// Publish an event to all registered observers.
// Each observer is invoked in its own strand — callers are never blocked.
public function publishEvent(ResourceEvent event) {
    foreach ResourceEventObserver obs in eventObservers {
        _ = start obs(event);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Convenience helpers — map from the existing sendAudit()-style call signature
// to a ResourceEvent so that all existing call sites work without change.
// ─────────────────────────────────────────────────────────────────────────────

// Map a FHIR interaction string to the corresponding ResourceEventType.
function actionToEventType(string action) returns ResourceEventType {
    if action == "create" || action == "post" {
        return RESOURCE_CREATED;
    } else if action == "update" || action == "put" {
        return RESOURCE_UPDATED;
    } else if action == "delete" {
        return RESOURCE_DELETED;
    }
    // "read", "search", "history" etc.
    return RESOURCE_READ;
}
