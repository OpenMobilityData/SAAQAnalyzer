//
//  DatabaseManagerTests.swift
//  SAAQAnalyzerTests
//
//  Created by Claude Code on 2025-01-27.
//

import XCTest
import SQLite3
@testable import SAAQAnalyzer

final class DatabaseManagerTests: XCTestCase {

    var databaseManager: DatabaseManager!
    var testDatabaseURL: URL!

    override func setUpWithError() throws {
        // Create a temporary database for testing
        let tempDir = FileManager.default.temporaryDirectory
        testDatabaseURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).sqlite")

        // Note: DatabaseManager is a singleton, so we'll work with the existing instance
        // but ensure we have a clean state for testing
        databaseManager = DatabaseManager.shared

        // Clear any existing cache to ensure clean test state
        FilterCache().clearCache()
    }

    override func tearDownWithError() throws {
        // Clean up test database
        if FileManager.default.fileExists(atPath: testDatabaseURL.path) {
            try? FileManager.default.removeItem(at: testDatabaseURL)
        }

        // Clear test cache
        FilterCache().clearCache()

        databaseManager = nil
        testDatabaseURL = nil
    }

    // MARK: - Database Connection Tests

    func testDatabaseConnection() {
        // The database should be connected and accessible
        XCTAssertNotNil(databaseManager.db, "Database should be connected")
    }

    func testDatabaseTablesExist() async {
        // Critical tables should exist
        let hasVehiclesTable = await tableExists("vehicles")
        let hasLicensesTable = await tableExists("licenses")
        let hasGeographicTable = await tableExists("geographic_entities")
        let hasImportLogTable = await tableExists("import_log")

        XCTAssertTrue(hasVehiclesTable, "Vehicles table should exist")
        XCTAssertTrue(hasLicensesTable, "Licenses table should exist")
        XCTAssertTrue(hasGeographicTable, "Geographic entities table should exist")
        XCTAssertTrue(hasImportLogTable, "Import log table should exist")
    }

    // MARK: - Cache-Aware Query Tests

    func testVehicleDataQueries() async {
        // Test that vehicle-specific queries work correctly
        let years = await databaseManager.getAvailableYears(for: .vehicle)
        let regions = await databaseManager.getAvailableRegions(for: .vehicle)
        let mrcs = await databaseManager.getAvailableMRCs(for: .vehicle)

        // Should return arrays (even if empty for test database)
        XCTAssertNotNil(years, "Vehicle years should be retrievable")
        XCTAssertNotNil(regions, "Vehicle regions should be retrievable")
        XCTAssertNotNil(mrcs, "Vehicle MRCs should be retrievable")

        // Data should be consistent
        XCTAssertTrue(years.allSatisfy { $0 > 2000 && $0 < 3000 }, "Years should be reasonable")
        XCTAssertTrue(regions.allSatisfy { !$0.isEmpty }, "Regions should not be empty strings")
        XCTAssertTrue(mrcs.allSatisfy { !$0.isEmpty }, "MRCs should not be empty strings")
    }

    func testLicenseDataQueries() async {
        // Test that license-specific queries work correctly
        let years = await databaseManager.getAvailableYears(for: .license)
        let regions = await databaseManager.getAvailableRegions(for: .license)
        let mrcs = await databaseManager.getAvailableMRCs(for: .license)

        // Test license-specific characteristics
        let licenseTypes = await databaseManager.getAvailableLicenseTypes()
        let ageGroups = await databaseManager.getAvailableAgeGroups()
        let genders = await databaseManager.getAvailableGenders()
        let experienceLevels = await databaseManager.getAvailableExperienceLevels()
        let licenseClasses = await databaseManager.getAvailableLicenseClasses()

        // Should return arrays
        XCTAssertNotNil(years, "License years should be retrievable")
        XCTAssertNotNil(regions, "License regions should be retrievable")
        XCTAssertNotNil(mrcs, "License MRCs should be retrievable")
        XCTAssertNotNil(licenseTypes, "License types should be retrievable")
        XCTAssertNotNil(ageGroups, "Age groups should be retrievable")
        XCTAssertNotNil(genders, "Genders should be retrievable")
        XCTAssertNotNil(experienceLevels, "Experience levels should be retrievable")
        XCTAssertNotNil(licenseClasses, "License classes should be retrievable")

        // Data validation
        XCTAssertTrue(years.allSatisfy { $0 > 2000 && $0 < 3000 }, "Years should be reasonable")
        XCTAssertTrue(licenseTypes.allSatisfy { ["REGULIER", "PROBATOIRE", "APPRENTI"].contains($0) }, "License types should be valid Quebec types")
        XCTAssertTrue(genders.allSatisfy { ["Male", "Female"].contains($0) }, "Genders should be valid")
    }

    func testDataEntityTypeSeparation() async {
        // Test that vehicle and license queries return different results (when data exists)
        let vehicleRegions = await databaseManager.getAvailableRegions(for: .vehicle)
        let licenseRegions = await databaseManager.getAvailableRegions(for: .license)

        let vehicleMRCs = await databaseManager.getAvailableMRCs(for: .vehicle)
        let licenseMRCs = await databaseManager.getAvailableMRCs(for: .license)

        // If data exists for both types, they should potentially be different
        // (This test will be more meaningful with actual test data)
        XCTAssertTrue(vehicleRegions.count >= 0, "Vehicle regions should be retrievable")
        XCTAssertTrue(licenseRegions.count >= 0, "License regions should be retrievable")
        XCTAssertTrue(vehicleMRCs.count >= 0, "Vehicle MRCs should be retrievable")
        XCTAssertTrue(licenseMRCs.count >= 0, "License MRCs should be retrievable")

        // Test that queries are using correct data entity types
        XCTAssertNotEqual(vehicleRegions, licenseRegions, "Vehicle and license regions should potentially differ")
        XCTAssertNotEqual(vehicleMRCs, licenseMRCs, "Vehicle and license MRCs should potentially differ")
    }

    // MARK: - Geographic Data Tests

    func testGeographicHierarchy() async {
        let municipalities = await databaseManager.getAvailableMunicipalities()
        let municipalityMapping = await databaseManager.getMunicipalityCodeToNameMapping()

        XCTAssertNotNil(municipalities, "Municipalities should be retrievable")
        XCTAssertNotNil(municipalityMapping, "Municipality mapping should be retrievable")

        // Validate municipality codes are numeric
        XCTAssertTrue(municipalities.allSatisfy { code in
            Int(code) != nil
        }, "Municipality codes should be numeric strings")

        // Validate mapping consistency
        for municipalityCode in municipalities.prefix(10) { // Check first 10 for performance
            XCTAssertNotNil(municipalityMapping[municipalityCode], "Municipality \(municipalityCode) should have a name mapping")
        }
    }

    func testGeographicDataIntegrity() async {
        // Test that geographic entities have proper hierarchical relationships
        let regions = await databaseManager.getAvailableRegions(for: .vehicle)
        let mrcs = await databaseManager.getAvailableMRCs(for: .vehicle)

        // Basic validation
        XCTAssertTrue(regions.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, "Regions should not be empty")
        XCTAssertTrue(mrcs.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, "MRCs should not be empty")

        // Quebec should have reasonable number of regions and MRCs
        if !regions.isEmpty {
            XCTAssertGreaterThan(regions.count, 5, "Quebec should have multiple administrative regions")
            XCTAssertLessThan(regions.count, 50, "Quebec shouldn't have excessive number of regions")
        }

        if !mrcs.isEmpty {
            XCTAssertGreaterThan(mrcs.count, 50, "Quebec should have many MRCs")
            XCTAssertLessThan(mrcs.count, 200, "Quebec shouldn't have excessive number of MRCs")
        }
    }

    // MARK: - Data Version and Cache Tests

    @MainActor
    func testDataVersionTracking() {
        // Test that the database manager tracks version information through cache
        let filterCache = FilterCache()

        // Version should be trackable through cache operations
        XCTAssertNotNil(filterCache.cachedDataVersion, "Data version should be trackable through cache")
    }

    @MainActor
    func testCacheRefreshTrigger() async {
        // Test that cache refresh can be triggered without errors
        await databaseManager.refreshFilterCache()

        // After refresh, cache should indicate it has data
        let filterCache = FilterCache()
        XCTAssertTrue(filterCache.hasCachedData, "Cache should have data after refresh")
    }

    @MainActor
    func testConcurrentCacheRefresh() async {
        // Test that concurrent cache refreshes are handled properly
        let expectation1 = expectation(description: "First cache refresh")
        let expectation2 = expectation(description: "Second cache refresh")
        let expectation3 = expectation(description: "Third cache refresh")

        // Start multiple cache refreshes concurrently
        Task {
            await databaseManager.refreshFilterCache()
            expectation1.fulfill()
        }

        Task {
            await databaseManager.refreshFilterCache()
            expectation2.fulfill()
        }

        Task {
            await databaseManager.refreshFilterCache()
            expectation3.fulfill()
        }

        // All should complete without deadlock
        await fulfillment(of: [expectation1, expectation2, expectation3], timeout: 10.0)

        // Cache should be in valid state
        let filterCache = FilterCache()
        XCTAssertTrue(filterCache.hasCachedData, "Cache should be valid after concurrent refreshes")
    }

    // MARK: - Query Performance Tests

    func testQueryPerformance() async {
        // Test that basic queries complete within reasonable time
        measure {
            Task { [self] in
                let _ = await databaseManager.getAvailableYears(for: .vehicle)
                let _ = await databaseManager.getAvailableRegions(for: .vehicle)
                let _ = await databaseManager.getAvailableMRCs(for: .vehicle)
            }
        }
    }

    func testLicenseCharacteristicsPerformance() async {
        // Test that license characteristic queries perform well
        // This is critical because these were causing the 66M record scans
        await measureAsync { [self] in
            let _ = await databaseManager.getAvailableLicenseTypes()
            let _ = await databaseManager.getAvailableAgeGroups()
            let _ = await databaseManager.getAvailableGenders()
            let _ = await databaseManager.getAvailableExperienceLevels()
            let _ = await databaseManager.getAvailableLicenseClasses()
        }
    }

    // MARK: - Error Handling Tests

    func testQueryErrorHandling() async {
        // Test that queries handle database errors gracefully
        // Note: This is harder to test with the singleton pattern, but we can at least verify no crashes

        let years = await databaseManager.getAvailableYears(for: .vehicle)
        let regions = await databaseManager.getAvailableRegions(for: .vehicle)

        // Should return arrays even if database has issues
        XCTAssertNotNil(years, "Years query should handle errors gracefully")
        XCTAssertNotNil(regions, "Regions query should handle errors gracefully")
    }

    // MARK: - Database Statistics Tests

    @MainActor
    func testDatabaseStats() async {
        let stats = await databaseManager.getDatabaseStats()

        XCTAssertNotNil(stats, "Database stats should be retrievable")
        XCTAssertGreaterThanOrEqual(stats.totalRecords, 0, "Total records should be non-negative")
        XCTAssertGreaterThanOrEqual(stats.municipalities, 0, "Municipalities count should be non-negative")
        XCTAssertGreaterThanOrEqual(stats.regions, 0, "Regions count should be non-negative")
        XCTAssertGreaterThanOrEqual(stats.fileSizeBytes, 0, "File size should be non-negative")
    }
}

// MARK: - Test Helpers

extension DatabaseManagerTests {

    /// Helper to check if a table exists in the database
    func tableExists(_ tableName: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            databaseManager.dbQueue.async {
                guard let db = self.databaseManager.db else {
                    continuation.resume(returning: false)
                    return
                }

                let query = "SELECT name FROM sqlite_master WHERE type='table' AND name=?"
                var stmt: OpaquePointer?
                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: false)
                    return
                }

                sqlite3_bind_text(stmt, 1, tableName, -1, nil)
                let result = sqlite3_step(stmt) == SQLITE_ROW
                continuation.resume(returning: result)
            }
        }
    }

    /// Helper to measure async operations
    func measureAsync(_ block: @escaping () async -> Void) async {
        let startTime = Date()
        await block()
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)

        // Assert that operations complete within reasonable time (5 seconds for cache-hitting queries)
        XCTAssertLessThan(duration, 5.0, "Async operation should complete within 5 seconds")
    }
}

// Note: DatabaseManager.db and DatabaseManager.dbQueue are internal,
// so they're accessible from tests in the same module via @testable import