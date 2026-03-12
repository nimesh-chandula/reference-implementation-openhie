import ballerina/http;
import ballerina/test;

http:Client testClient = check new ("http://localhost:9098");

// Test ITI-130: Create a Facility Location
@test:Config {}
function testCreateLocation() {
    json locationPayload = {
        "resourceType": "Location",
        "name": "Colombo National Hospital",
        "status": "active",
        "type": [
            {
                "coding": [
                    {
                        "system": "https://profiles.ihe.net/ITI/mCSD/CodeSystem/IHE.mCSD.Organization.Location.Types",
                        "code": "facility"
                    }
                ]
            }
        ],
        "managingOrganization": {
            "reference": "Organization/facility-org-001"
        },
        "position": {
            "latitude": 6.9271,
            "longitude": 79.8612
        },
        "address": {
            "text": "Regent Street, Colombo 10",
            "city": "Colombo",
            "state": "Western Province",
            "country": "LK"
        }
    };

    http:Response|error response = testClient->/fhir/Location.post(locationPayload,
        mediaType = "application/fhir+json");
    test:assertTrue(response is http:Response, msg = "Expected http:Response for POST /fhir/Location");
    if response is http:Response {
        test:assertEquals(response.statusCode, 201, msg = "Expected 201 Created");
        boolean hasLocationHeader = response.getHeader("Location") is string;
        test:assertTrue(hasLocationHeader, msg = "Expected Location header in response");
    }
}

// Test ITI-90: Search Organizations — should return a FHIR searchset Bundle
@test:Config {}
function testSearchOrganization() {
    json|error response = testClient->/fhir/Organization();
    test:assertTrue(response is json, msg = "Expected JSON response from GET /fhir/Organization");
    if response is json {
        json|error rt = response.resourceType;
        test:assertTrue(rt is json, msg = "Expected resourceType field");
        if rt is json {
            test:assertEquals(rt.toString(), "Bundle", msg = "Expected Bundle resourceType");
        }

        json|error bundleType = response.'type;
        if bundleType is json {
            test:assertEquals(bundleType.toString(), "searchset", msg = "Expected searchset Bundle type");
        }

        json|error total = response.total;
        test:assertTrue(total is json, msg = "Expected total field in Bundle");
    }
}

// Test GET /fhir/metadata — should return a CapabilityStatement
@test:Config {}
function testCapabilityStatement() {
    json|error response = testClient->/fhir/metadata();
    test:assertTrue(response is json, msg = "Expected JSON from GET /fhir/metadata");
    if response is json {
        json|error rt = response.resourceType;
        if rt is json {
            test:assertEquals(rt.toString(), "CapabilityStatement", msg = "Expected CapabilityStatement resourceType");
        }

        json|error status = response.status;
        if status is json {
            test:assertEquals(status.toString(), "active", msg = "Expected active status");
        }

        json|error fhirVersion = response.fhirVersion;
        if fhirVersion is json {
            test:assertEquals(fhirVersion.toString(), "4.0.1", msg = "Expected FHIR R4 version");
        }
    }
}

// Test ITI-130: Create an Organization
@test:Config {}
function testCreateOrganization() {
    json orgPayload = {
        "resourceType": "Organization",
        "name": "Test Facility Administration",
        "active": true,
        "type": [
            {
                "coding": [
                    {
                        "system": "https://profiles.ihe.net/ITI/mCSD/CodeSystem/IHE.mCSD.Organization.Location.Types",
                        "code": "facility"
                    }
                ]
            }
        ]
    };

    http:Response|error response = testClient->/fhir/Organization.post(orgPayload,
        mediaType = "application/fhir+json");
    test:assertTrue(response is http:Response, msg = "Expected http:Response for POST /fhir/Organization");
    if response is http:Response {
        test:assertEquals(response.statusCode, 201, msg = "Expected 201 Created");
    }
}

// Test ITI-91: History endpoint — should return a history Bundle
@test:Config {dependsOn: [testCreateLocation]}
function testLocationHistory() {
    json|error response = testClient->/fhir/Location/_history();
    test:assertTrue(response is json, msg = "Expected JSON from GET /fhir/Location/_history");
    if response is json {
        json|error rt = response.resourceType;
        if rt is json {
            test:assertEquals(rt.toString(), "Bundle", msg = "Expected Bundle");
        }

        json|error bundleType = response.'type;
        if bundleType is json {
            test:assertEquals(bundleType.toString(), "history", msg = "Expected history Bundle type");
        }
    }
}

// Test Admin API: statistics
@test:Config {}
function testAdminStatistics() {
    json|error response = testClient->/api/admin/statistics();
    test:assertTrue(response is json, msg = "Expected JSON from GET /api/admin/statistics");
    if response is json {
        json|error total = response.totalLocations;
        test:assertTrue(total is json, msg = "Expected totalLocations field");
    }
}
