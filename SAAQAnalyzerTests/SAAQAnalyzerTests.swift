//
//  SAAQAnalyzerTests.swift
//  SAAQAnalyzerTests
//
//  Created by Rick Hoge on 2025-09-21.
//

import XCTest
@testable import SAAQAnalyzer

/// Main test suite entry point - comprehensive testing is handled by specialized test classes:
/// - FilterCacheTests: Cache separation and consistency validation
/// - DatabaseManagerTests: Query correctness and performance testing
/// - CSVImporterTests: Data import validation and encoding handling
/// - WorkflowIntegrationTests: End-to-end workflow verification
final class SAAQAnalyzerTests: XCTestCase {

    func testApplicationInitialization() throws {
        // Test that core components can be initialized without errors
        let databaseManager = DatabaseManager.shared
        let filterCache = FilterCache()

        XCTAssertNotNil(databaseManager, "DatabaseManager should initialize")
        XCTAssertNotNil(filterCache, "FilterCache should initialize")
    }

    func testDataModelTypes() throws {
        // Test that core data model enums are properly configured
        XCTAssertGreaterThan(VehicleClass.allCases.count, 0, "VehicleClass should have cases")
        XCTAssertGreaterThan(FuelType.allCases.count, 0, "FuelType should have cases")
        XCTAssertGreaterThan(LicenseType.allCases.count, 0, "LicenseType should have cases")
        XCTAssertGreaterThan(AgeGroup.allCases.count, 0, "AgeGroup should have cases")
        XCTAssertGreaterThan(Gender.allCases.count, 0, "Gender should have cases")
        XCTAssertGreaterThan(ExperienceLevel.allCases.count, 0, "ExperienceLevel should have cases")

        // Verify critical enum values exist
        XCTAssertNotNil(VehicleClass(rawValue: "AUTOMOBILE"), "AUTOMOBILE classification should exist")
        XCTAssertNotNil(FuelType(rawValue: "ESSENCE"), "ESSENCE fuel type should exist")
        XCTAssertNotNil(LicenseType(rawValue: "REGULIER"), "REGULIER license type should exist")
        XCTAssertNotNil(Gender(rawValue: "M"), "Male gender should exist")
        XCTAssertNotNil(Gender(rawValue: "F"), "Female gender should exist")
    }

    func testDataEntityTypes() throws {
        // Test DataEntityType enum functionality
        let vehicleClass = DataEntityType.vehicle
        let licenseType = DataEntityType.license

        XCTAssertEqual(vehicleClass.rawValue, "vehicle", "Vehicle type should have correct raw value")
        XCTAssertEqual(licenseType.rawValue, "license", "License type should have correct raw value")

        // Test that both types exist in all cases
        XCTAssertEqual(DataEntityType.allCases.count, 2, "Should have exactly 2 data entity types")
        XCTAssertTrue(DataEntityType.allCases.contains(.vehicle), "Should contain vehicle type")
        XCTAssertTrue(DataEntityType.allCases.contains(.license), "Should contain license type")
    }

    func testFilterConfiguration() throws {
        // Test FilterConfiguration initialization and basic functionality
        let config = FilterConfiguration()

        XCTAssertEqual(config.dataEntityType, .vehicle, "Default data entity type should be vehicle")
        XCTAssertTrue(config.years.isEmpty, "Default years should be empty")
        XCTAssertTrue(config.regions.isEmpty, "Default regions should be empty")
        XCTAssertTrue(config.vehicleMakes.isEmpty, "Default vehicle makes should be empty")
        XCTAssertTrue(config.licenseTypes.isEmpty, "Default license types should be empty")
    }

    @MainActor
    func testAppSettings() async throws {
        // Test AppSettings basic functionality
        let settings = AppSettings.shared

        XCTAssertNotNil(settings, "AppSettings should be accessible")
        XCTAssertGreaterThanOrEqual(settings.systemProcessorCount, 1, "Should detect at least 1 processor")
        XCTAssertGreaterThanOrEqual(settings.performanceCoreCount, 1, "Should detect at least 1 performance core")

        // Test performance settings bounds
        let threadCount = settings.getOptimalThreadCount(for: 100000)
        XCTAssertGreaterThan(threadCount, 0, "Thread count should be positive")
        XCTAssertLessThanOrEqual(threadCount, settings.maxThreadCount, "Thread count should not exceed maximum")
    }
}
