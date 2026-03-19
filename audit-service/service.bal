import ballerina/http;
import ballerinax/health.fhir.r4.international401;
import ballerinax/health.fhir.r4;
import ballerina/io;
import ballerina/log;
import ballerina/cache;
import ballerina/uuid;
import ballerinax/health.fhir.r4.terminology;
import ballerina/task;
import ballerina/file;

// in Choreo context, this is expected to be a path in a file mount
configurable string auditLogPath = "/tmp/audit-logs/fhir-audit.log";
// capacity of the cache used to store the failed audit events till they are retried
configurable int cacheCapacity = 1000;
// name of the fhir server. This is used as the source observer name in the FHIR audit event
configurable string fhirServerName = "wso2fhirserver.com";
// agent type of the audit event. This is used as the agent type in the FHIR audit event
configurable string agentType = "humanuser";
// rotate the log file when it exceeds this size in MB (0 disables rotation)
configurable int maxLogFileSizeMB = 10;
// maximum number of rotated log files to keep (.1 through .N)
configurable int maxRotatedFiles = 5;

// This creates a new cache with the advanced configuration.
final cache:Cache cache = new ({
    capacity: cacheCapacity
});

// Retry failed audit events
class RetryFailedAuditEvents {

    *task:Job;

    public function init() {
        log:printDebug("Initialized the `retry failed audit events` task.");
    }

    // Executes this function when the scheduled trigger fires.
    public function execute() {
        int i = 0;
        if cache.size() > 0 {
            log:printDebug("Retrying to write failed audit events to the log file.", numberOfFailedAuditEvents = cache.size());
        }
        while i < cache.size() {
            // retry to write to the audit log file
            international401:AuditEvent|error auditEvent = cache.get(cache.keys()[i]).ensureType();
            if (auditEvent is international401:AuditEvent) {
                io:Error? result = io:fileWriteLines(auditLogPath, [auditEvent.toJsonString()], option = io:APPEND);
                if !(result is io:Error) {
                    // if retrying is successful, remove from the cache
                    check cache.invalidate(cache.keys()[i]);
                    log:printDebug("Successfully wrote the audit event to the log file.", id = auditEvent.id);
                } else {
                    i += 1;
                    log:printDebug("Failed to retry writing the audit event to the log file. Retrying...", id = auditEvent.id, 'error = result);
                }
            }

        } on fail var e {
            // keep retrying
            log:printDebug("Failed to retry writing the audit event to the log file. Retrying...", e);
        }
    }
}

// Returns log files ordered newest to oldest: [fhir-audit.log, fhir-audit.log.1, ...]
// Only includes files that exist on disk.
isolated function getLogFiles() returns string[] {
    string[] files = [];
    boolean|file:Error exists = file:test(auditLogPath, file:EXISTS);
    if exists is boolean && exists {
        files.push(auditLogPath);
    }
    foreach int i in 1 ... maxRotatedFiles {
        string rotated = auditLogPath + "." + i.toString();
        boolean|file:Error rotatedExists = file:test(rotated, file:EXISTS);
        if rotatedExists is boolean && rotatedExists {
            files.push(rotated);
        }
    }
    return files;
}

// Rotates log files: deletes oldest, shifts .N-1->.N, ..., .1->.2, current->.1
isolated function rotateLogFile() {
    string oldest = auditLogPath + "." + maxRotatedFiles.toString();
    boolean|file:Error oldestExists = file:test(oldest, file:EXISTS);
    if oldestExists is boolean && oldestExists {
        do {
            check file:remove(oldest);
        } on fail error e {
            log:printWarn("Failed to remove oldest rotated log file.", 'error = e, path = oldest);
        }
    }
    int i = maxRotatedFiles - 1;
    while i >= 1 {
        string src = auditLogPath + "." + i.toString();
        string dst = auditLogPath + "." + (i + 1).toString();
        boolean|file:Error srcExists = file:test(src, file:EXISTS);
        if srcExists is boolean && srcExists {
            do {
                check file:rename(src, dst);
            } on fail error e {
                log:printWarn("Failed to rename rotated log file.", 'error = e, src = src, dst = dst);
            }
        }
        i -= 1;
    }
    boolean|file:Error currentExists = file:test(auditLogPath, file:EXISTS);
    if currentExists is boolean && currentExists {
        do {
            check file:rename(auditLogPath, auditLogPath + ".1");
        } on fail error e {
            log:printWarn("Failed to rotate current log file.", 'error = e);
        }
    }
    log:printInfo("Audit log rotated.", maxRotatedFiles = maxRotatedFiles);
}

// Returns the `recorded` timestamp of the first non-empty parseable line, or "" if none.
isolated function getFirstTimestamp(string[] lines) returns string {
    foreach string line in lines {
        if line.trim().length() == 0 {
            continue;
        }
        json|error parsed = line.fromJsonString();
        if parsed is json {
            json|error ts = parsed.recorded;
            if ts is json {
                return ts.toString();
            }
        }
        break;
    }
    return "";
}

// Returns the `recorded` timestamp of the last non-empty parseable line, or "" if none.
isolated function getLastTimestamp(string[] lines) returns string {
    int i = lines.length() - 1;
    while i >= 0 {
        string line = lines[i];
        if line.trim().length() > 0 {
            json|error parsed = line.fromJsonString();
            if parsed is json {
                json|error ts = parsed.recorded;
                if ts is json {
                    return ts.toString();
                }
            }
        }
        i -= 1;
    }
    return "";
}

configurable int port = 9096;

service / on new http:Listener(port) {

    function init() returns error? {
        // this is an internal task, hence the interval does not needs to be a configurable. 
        _ = check task:scheduleJobRecurByFrequency(
                            new RetryFailedAuditEvents(), 30);
        log:printInfo("FHIR Audit Service is started...", port = port);
    }

    // GET /audits - Read audit events from the log file
    isolated resource function get audits(http:Request req, string? action, string? subtype,
            string? since, string? before, int 'limit = 50, int offset = 0, string sortOrder = "desc")
            returns json|http:STATUS_INTERNAL_SERVER_ERROR {

        int effectiveLimit = 'limit < 1 ? 50 : 'limit;
        int startIdx = offset < 0 ? 0 : offset;
        int needed = startIdx + effectiveLimit;

        // Get log files: index 0 = newest. For asc, reverse to oldest-first.
        string[] logFiles = getLogFiles();
        if sortOrder == "asc" {
            logFiles = logFiles.reverse();
        }

        json[] allMatching = [];

        foreach string logFile in logFiles {
            // Early exit: we already have enough matching records
            if allMatching.length() >= needed {
                break;
            }

            string[]|io:Error linesResult = io:fileReadLines(logFile);
            if linesResult is io:Error {
                string errMsg = linesResult.message();
                if errMsg.includes("no such file") || errMsg.includes("does not exist") || errMsg.includes("cannot find") || errMsg.includes("FileNotFound") {
                    continue;
                }
                log:printError("Failed to read audit log file.", 'error = linesResult, path = logFile);
                return http:STATUS_INTERNAL_SERVER_ERROR;
            }
            string[] lines = linesResult;

            // Skip this file entirely if its time range doesn't overlap the query window
            if since is string || before is string {
                string fileStart = getFirstTimestamp(lines);
                string fileEnd = getLastTimestamp(lines);
                if fileStart != "" && before is string && fileStart > before {
                    // Entire file is newer than 'before' — skip
                    continue;
                }
                if fileEnd != "" && since is string && fileEnd < since {
                    // Entire file is older than 'since' — for desc, no older file can help either
                    if sortOrder != "asc" {
                        break;
                    }
                    continue;
                }
            }

            // For desc: process lines newest-first within this file
            string[] orderedLines = sortOrder == "asc" ? lines : lines.reverse();

            foreach string line in orderedLines {
                if allMatching.length() >= needed {
                    break;
                }
                if line.trim().length() == 0 {
                    continue;
                }
                json|error parsed = line.fromJsonString();
                if parsed is json {
                    // Skip framework-generated audit events
                    json|error sourceObserver = parsed.'source.observer.display;
                    if sourceObserver is json && sourceObserver.toString() == fhirServerName {
                        continue;
                    }

                    // Apply optional filters
                    boolean include = true;
                    if action is string {
                        json|error eventAction = parsed.action;
                        if eventAction is json {
                            include = eventAction.toString() == action;
                        }
                    }
                    if include && subtype is string {
                        json|error subtypeArr = parsed.subtype;
                        if subtypeArr is json {
                            include = subtypeArr.toString().includes(subtype);
                        }
                    }
                    if include && (since is string || before is string) {
                        json|error recordedTime = parsed.recorded;
                        if recordedTime is json {
                            string recorded = recordedTime.toString();
                            if since is string {
                                include = recorded > since;
                            }
                            if include && before is string {
                                include = recorded < before;
                            }
                        }
                    }
                    if include {
                        allMatching.push(parsed);
                    }
                }
            }
        }

        // Apply offset/limit — records are already in the correct sort order
        json[] paginated = [];
        int idx = startIdx;
        while idx < needed && idx < allMatching.length() {
            paginated.push(allMatching[idx]);
            idx += 1;
        }
        return paginated;
    }

    isolated resource function post audits(international401:AuditEvent audit) returns international401:AuditEvent|http:STATUS_ACCEPTED|http:STATUS_INTERNAL_SERVER_ERROR {
        international401:AuditEvent auditEvent = audit;
        if !(auditEvent.id is string) || auditEvent.id == "" {
            auditEvent.id = uuid:createType1AsString();
        }
        // Rotate log file if it exceeds the configured size limit
        if maxLogFileSizeMB > 0 {
            file:MetaData|file:Error meta = file:getMetaData(auditLogPath);
            if meta is file:MetaData && meta.size > maxLogFileSizeMB * 1024 * 1024 {
                rotateLogFile();
            }
        }
        io:Error? result = io:fileWriteLines(auditLogPath, [auditEvent.toJsonString()], option = io:APPEND);
        if result is io:Error {
            // keep track of failed audit events in an inmemory buffer and retry to write
            log:printWarn("Failed to write the audit event to the log file. Trying to put to a cache and retry later.", result, id = auditEvent.id, auditEvent = auditEvent.toJson());
            do {
                check cache.put(check auditEvent.id.ensureType(), auditEvent);
                return http:STATUS_ACCEPTED;
            } on fail error e {
                log:printError("[Critical] Failed to write to the log file and failed in adding it to the cache. Audit event will be lost.", 'error = e,
                auditEvent = auditEvent.toJson());
                return http:STATUS_INTERNAL_SERVER_ERROR;
            }
        } else {
            log:printDebug("Successfully wrote the audit event to the log file.", id = auditEvent.id);
        }
        return auditEvent;
    }
}

isolated function toFhirAuditEvent(InternalAuditEvent internalAuditEvent) returns international401:AuditEvent {
    international401:AuditEventAgent[] agents = [];
    foreach AuditAgent a in internalAuditEvent.agents {
        agents.push(getAgent(a));
    }

    international401:AuditEventEntity[] entities = [];
    foreach AuditEntity e in internalAuditEvent.entities {
        entities.push(getEntity(e));
    }

    international401:AuditEvent auditEvent = {
        id: uuid:createType1AsString(),
        'type: getCoding("http://terminology.hl7.org/CodeSystem/audit-event-type", internalAuditEvent.typeCode),
        subtype: [getCoding("http://hl7.org/fhir/restful-interaction", internalAuditEvent.subTypeCode)],
        action: internalAuditEvent.actionCode,
        outcome: internalAuditEvent.outcomeCode,
        outcomeDesc: internalAuditEvent.outcomeDesc != "" ? internalAuditEvent.outcomeDesc : (),
        recorded: internalAuditEvent.recordedTime,
        agent: agents,
        entity: entities,
        'source: {
            observer: getSourceObserver(internalAuditEvent),
            site: internalAuditEvent.sourceSite != "" ? internalAuditEvent.sourceSite : (),
            'type: [getCoding("http://terminology.hl7.org/CodeSystem/security-source-type", internalAuditEvent.sourceObserverType)]
        }
    };

    if internalAuditEvent.purposeOfEventCode != "" {
        auditEvent.purposeOfEvent = [{
            coding: [getCoding("http://terminology.hl7.org/CodeSystem/v3-ActReason", internalAuditEvent.purposeOfEventCode)]
        }];
    }

    if internalAuditEvent.periodStart != "" || internalAuditEvent.periodEnd != "" {
        auditEvent.period = {
            'start: internalAuditEvent.periodStart != "" ? internalAuditEvent.periodStart : (),
            end: internalAuditEvent.periodEnd != "" ? internalAuditEvent.periodEnd : ()
        };
    }

    return auditEvent;
};

isolated function getCoding(string system, string code) returns r4:Coding {
    r4:Coding|r4:FHIRError fhirCode = terminology:createCoding(system, code);
    if (fhirCode is r4:FHIRError) {
        // means the code system is not available in the terminology server
        // skip the error and mark the value as unknown.
        return {
            system: system,
            code: code,
            display: "Unknown"
        };
    }
    return fhirCode;
};

isolated function getAgent(AuditAgent agentData) returns international401:AuditEventAgent {
    r4:Reference who = {};
    if agentData.whoDisplay != "" {
        who.display = agentData.whoDisplay;
    }
    if agentData.whoIdentifierSystem != "" || agentData.whoIdentifierValue != "" {
        who.identifier = {
            system: agentData.whoIdentifierSystem != "" ? agentData.whoIdentifierSystem : (),
            value: agentData.whoIdentifierValue != "" ? agentData.whoIdentifierValue : ()
        };
    }

    international401:AuditEventAgent agent = {
        'type: {
            coding: [getCoding("http://terminology.hl7.org/CodeSystem/extra-security-role-type",
                agentData.typeCode == "" ? agentType : agentData.typeCode)]
        },
        who: who,
        requestor: agentData.requestor
    };

    if agentData.name != "" {
        agent.name = agentData.name;
    }
    if agentData.altId != "" {
        agent.altId = agentData.altId;
    }
    if agentData.networkAddress != "" {
        agent.network = {
            address: agentData.networkAddress,
            'type: agentData.networkType
        };
    }
    if agentData.policy.length() > 0 {
        agent.policy = agentData.policy;
    }
    if agentData.purposeOfUseCode != "" {
        agent.purposeOfUse = [{
            coding: [getCoding("http://terminology.hl7.org/CodeSystem/v3-ActReason", agentData.purposeOfUseCode)]
        }];
    }
    return agent;
};

isolated function getEntity(AuditEntity entityData) returns international401:AuditEventEntity {
    r4:Reference what = {};
    if entityData.whatReference != "" {
        what.reference = entityData.whatReference;
    }
    if entityData.whatIdentifierSystem != "" || entityData.whatIdentifierValue != "" {
        what.identifier = {
            system: entityData.whatIdentifierSystem != "" ? entityData.whatIdentifierSystem : (),
            value: entityData.whatIdentifierValue != "" ? entityData.whatIdentifierValue : ()
        };
    }

    international401:AuditEventEntity entity = {
        'type: getCoding("http://terminology.hl7.org/CodeSystem/audit-entity-type", entityData.typeCode),
        role: getCoding("http://terminology.hl7.org/CodeSystem/object-role", entityData.roleCode),
        what: what
    };

    if entityData.name != "" {
        entity.name = entityData.name;
    }
    if entityData.queryDetail != "" {
        international401:AuditEventEntityDetail queryEntry = {
            'type: "query",
            valueString: entityData.queryDetail
        };
        entity.detail = [queryEntry];
    }
    if entityData.lifecycleCode != "" {
        entity.lifecycle = getCoding("http://terminology.hl7.org/CodeSystem/dicom-audit-lifecycle", entityData.lifecycleCode);
    }
    if entityData.securityLabelCodes.length() > 0 {
        r4:Coding[] labels = [];
        foreach string code in entityData.securityLabelCodes {
            labels.push(getCoding("http://terminology.hl7.org/CodeSystem/v3-Confidentiality", code));
        }
        entity.securityLabel = labels;
    }
    return entity;
};

isolated function getSourceObserver(InternalAuditEvent e) returns r4:Reference {
    r4:Reference observer = {
        display: e.sourceObserverName == "" ? fhirServerName : e.sourceObserverName
    };
    if e.sourceObserverIdentifierSystem != "" || e.sourceObserverIdentifierValue != "" {
        observer.identifier = {
            system: e.sourceObserverIdentifierSystem != "" ? e.sourceObserverIdentifierSystem : (),
            value: e.sourceObserverIdentifierValue != "" ? e.sourceObserverIdentifierValue : ()
        };
    }
    return observer;
};
