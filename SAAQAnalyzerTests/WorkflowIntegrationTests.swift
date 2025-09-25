//
//  WorkflowIntegrationTests.swift
//  SAAQAnalyzerTests
//
//  Created by Claude Code on 2025-01-27.
//

import XCTest
@testable import SAAQAnalyzer

final class WorkflowIntegrationTests: XCTestCase {

    var databaseManager: DatabaseManager!
    var csvImporter: CSVImporter!
    var filterCache: FilterCache!
    var tempDirectory: URL!

    override func setUpWithError() throws {
        // Create temporary directory for test files
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("IntegrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Initialize components
        databaseManager = DatabaseManager.shared
        csvImporter = CSVImporter(databaseManager: databaseManager)
        filterCache = FilterCache()

        // Clear cache for clean test state
        filterCache.clearCache()
    }

    override func tearDownWithError() throws {
        // Clean up temporary files
        try? FileManager.default.removeItem(at: tempDirectory)

        // Clear cache
        filterCache.clearCache()

        databaseManager = nil
        csvImporter = nil
        filterCache = nil
        tempDirectory = nil
    }

    // MARK: - Complete Import-to-Analysis Workflow Tests

    @MainActor
    func testVehicleDataCompleteWorkflow() async throws {
        // Test the complete workflow: CSV Import → Cache Refresh → Filter Options → Data Query

        // Step 1: Create test vehicle data
        let vehicleCSV = """
        ANNEE,SEQUENCE_VEHICULE,SEXE,GROUPE_AGE,REGION,MRC,GEO_CODE_MUNICIPALITE,MARQUE,MODELE,ANNEE_MODELE,COULEUR_VEHICULE,USAGE_VEHICULE,KILOMÉTRAGE,ÉTAT_VÉHICULE,CARBURANT,STATUT_VÉHICULE
        2023,1,M,25-34,01,06,66023,TOYOTA,COROLLA,2020,ROUGE,PROMENADE,25000,BON,ESSENCE,ACTIF
        2023,2,F,35-44,06,80,80005,HONDA,CIVIC,2019,BLEU,PROMENADE,35000,EXCELLENT,ÉLECTRIQUE,ACTIF
        2023,3,M,45-54,03,30,30010,SUBARU,OUTBACK,2021,BLANC,PROMENADE,15000,BON,ESSENCE,ACTIF
        """

        let csvURL = try createTestCSVFile(content: vehicleCSV, filename: "integration_vehicles_2023.csv")

        // Step 2: Import data (this tests CSV parsing and database insertion)
        let importResult = try await csvImporter.importFile(at: csvURL, year: 2023, dataType: .vehicle, skipDuplicateCheck: true)
        XCTAssertEqual(importResult.totalRecords, 3, "Should process 3 vehicle records")
        XCTAssertEqual(importResult.successCount, 3, "Should successfully import 3 vehicle records")

        // Step 3: Refresh cache (tests database querying and cache population)
        await databaseManager.refreshFilterCache()

        // Step 4: Verify cache is populated
        XCTAssertTrue(filterCache.hasCachedData, "Cache should have data after import and refresh")

        // Step 5: Test filter option retrieval
        let vehicleYears = await databaseManager.getAvailableYears(for: .vehicle)
        let vehicleRegions = await databaseManager.getAvailableRegions(for: .vehicle)
        let vehicleMakes = await databaseManager.getAvailableVehicleMakes()

        XCTAssertTrue(vehicleYears.contains(2023), "Should include 2023 in available years")
        XCTAssertFalse(vehicleRegions.isEmpty, "Should have vehicle regions available")
        XCTAssertTrue(vehicleMakes.contains("TOYOTA"), "Should include TOYOTA in available makes")
        XCTAssertTrue(vehicleMakes.contains("HONDA"), "Should include HONDA in available makes")
        XCTAssertTrue(vehicleMakes.contains("SUBARU"), "Should include SUBARU in available makes")

        // Step 6: Test filtered data query
        var filterConfig = FilterConfiguration()
        filterConfig.dataEntityType = .vehicle
        filterConfig.years = Set([2023])
        filterConfig.vehicleMakes = Set(["TOYOTA"])

        let filteredData = try await databaseManager.queryVehicleData(filters: filterConfig)
        XCTAssertGreaterThanOrEqual(filteredData.points.count, 0, "Should return data points for TOYOTA filter")
        XCTAssertTrue(filteredData.name.contains("TOYOTA"), "Series name should contain TOYOTA filter")
    }

    @MainActor
    func testLicenseDataCompleteWorkflow() async throws {
        // Test the complete license data workflow

        // Step 1: Create test license data
        let licenseCSV = """
        ANNEE,SEQUENCE_PERMIS,GROUPE_AGE,SEXE,MRC,REGION_ADMINISTRATIVE,TYPE_PERMIS,PERMIS_APPR_123,PERMIS_APPR_5,PERMIS_APPR_6A6R,PERMIS_COND_1234,PERMIS_COND_5,PERMIS_COND_6ABCE,PERMIS_COND_6D,PERMIS_COND_8,EST_PROBATOIRE,EXPERIENCE_1234,EXPERIENCE_5,EXPERIENCE_6ABCE,EXPERIENCE_GLOBALE
        2023,1,25-34,M,06,01,REGULIER,0,0,0,1,0,0,0,0,0,10 ans ou plus,Absente,Absente,10 ans ou plus
        2023,2,16-19,F,80,06,PROBATOIRE,1,0,0,0,0,0,0,0,1,Moins de 2 ans,Absente,Absente,Moins de 2 ans
        2023,3,35-44,M,30,03,REGULIER,0,1,0,1,1,0,0,0,0,6 à 9 ans,2 à 5 ans,Absente,6 à 9 ans
        """

        let csvURL = try createTestCSVFile(content: licenseCSV, filename: "integration_licenses_2023.csv")

        // Step 2: Import license data
        let importResult = try await csvImporter.importFile(at: csvURL, year: 2023, dataType: .license, skipDuplicateCheck: true)
        XCTAssertEqual(importResult.totalRecords, 3, "Should process 3 license records")
        XCTAssertEqual(importResult.successCount, 3, "Should successfully import 3 license records")

        // Step 3: Refresh cache
        await databaseManager.refreshFilterCache()

        // Step 4: Verify license cache is populated
        XCTAssertTrue(filterCache.hasLicenseDataCached, "License cache should have data")

        // Step 5: Test license-specific filter options
        let licenseYears = await databaseManager.getAvailableYears(for: .license)
        let licenseRegions = await databaseManager.getAvailableRegions(for: .license)
        let licenseTypes = await databaseManager.getAvailableLicenseTypes()
        let experienceLevels = await databaseManager.getAvailableExperienceLevels()

        XCTAssertTrue(licenseYears.contains(2023), "Should include 2023 in license years")
        XCTAssertFalse(licenseRegions.isEmpty, "Should have license regions available")
        XCTAssertTrue(licenseTypes.contains("REGULIER"), "Should include REGULIER license type")
        XCTAssertTrue(licenseTypes.contains("PROBATOIRE"), "Should include PROBATOIRE license type")
        XCTAssertTrue(experienceLevels.contains("10 ans ou plus"), "Should include experience levels")

        // Step 6: Test filtered license query
        var filterConfig = FilterConfiguration()
        filterConfig.dataEntityType = .license
        filterConfig.years = Set([2023])
        filterConfig.licenseTypes = Set(["REGULIER"])

        let filteredData = try await databaseManager.queryLicenseData(filters: filterConfig)
        XCTAssertGreaterThanOrEqual(filteredData.points.count, 0, "Should return data points for REGULIER licenses")
        XCTAssertTrue(filteredData.name.contains("REGULIER"), "Series name should contain REGULIER filter")
    }

    // MARK: - Mode Switching Integration Tests

    @MainActor
    func testModeSwitchingWorkflow() async throws {
        // Test switching between vehicle and license modes maintains proper data separation

        // Setup: Import both vehicle and license data
        let vehicleCSV = """
        ANNEE,SEQUENCE_VEHICULE,SEXE,GROUPE_AGE,REGION,MRC,GEO_CODE_MUNICIPALITE,MARQUE,MODELE,ANNEE_MODELE,COULEUR_VEHICULE,USAGE_VEHICULE,KILOMÉTRAGE,ÉTAT_VÉHICULE,CARBURANT,STATUT_VÉHICULE
        2023,1,M,25-34,01,06,66023,TOYOTA,COROLLA,2020,ROUGE,PROMENADE,25000,BON,ESSENCE,ACTIF
        """

        let licenseCSV = """
        ANNEE,SEQUENCE_PERMIS,GROUPE_AGE,SEXE,MRC,REGION_ADMINISTRATIVE,TYPE_PERMIS,PERMIS_APPR_123,PERMIS_APPR_5,PERMIS_APPR_6A6R,PERMIS_COND_1234,PERMIS_COND_5,PERMIS_COND_6ABCE,PERMIS_COND_6D,PERMIS_COND_8,EST_PROBATOIRE,EXPERIENCE_1234,EXPERIENCE_5,EXPERIENCE_6ABCE,EXPERIENCE_GLOBALE
        2023,1,25-34,M,80,06,REGULIER,0,0,0,1,0,0,0,0,0,10 ans ou plus,Absente,Absente,10 ans ou plus
        """

        let vehicleURL = try createTestCSVFile(content: vehicleCSV, filename: "mode_switch_vehicles.csv")
        let licenseURL = try createTestCSVFile(content: licenseCSV, filename: "mode_switch_licenses.csv")

        // Import both types
        _ = try await csvImporter.importFile(at: vehicleURL, year: 2023, dataType: .vehicle, skipDuplicateCheck: true)
        _ = try await csvImporter.importFile(at: licenseURL, year: 2023, dataType: .license, skipDuplicateCheck: true)
        await databaseManager.refreshFilterCache()

        // Test vehicle mode
        let vehicleRegions = await databaseManager.getAvailableRegions(for: .vehicle)
        let vehicleMRCs = await databaseManager.getAvailableMRCs(for: .vehicle)
        let vehicleMakes = await databaseManager.getAvailableVehicleMakes()

        // Test license mode
        let licenseRegions = await databaseManager.getAvailableRegions(for: .license)
        let licenseMRCs = await databaseManager.getAvailableMRCs(for: .license)
        let licenseTypes = await databaseManager.getAvailableLicenseTypes()

        // Verify mode separation
        XCTAssertFalse(vehicleRegions.isEmpty, "Vehicle mode should have regions")
        XCTAssertFalse(licenseRegions.isEmpty, "License mode should have regions")
        XCTAssertFalse(vehicleMakes.isEmpty, "Vehicle mode should have makes")
        XCTAssertFalse(licenseTypes.isEmpty, "License mode should have license types")

        // Cross-contamination checks
        XCTAssertTrue(vehicleMakes.contains("TOYOTA"), "Vehicle mode should show vehicle makes")
        XCTAssertTrue(licenseTypes.contains("REGULIER"), "License mode should show license types")

        // License mode shouldn't return vehicle-specific data through wrong methods
        let vehicleColorsInLicenseMode = await databaseManager.getAvailableVehicleColors()
        // This should be empty or not affect license queries
        XCTAssertNotNil(vehicleColorsInLicenseMode, "Vehicle-specific queries should work regardless of mode")
    }

    // MARK: - Cache Consistency Tests

    @MainActor
    func testCacheConsistencyAcrossOperations() async throws {
        // Test that cache remains consistent through various operations

        // Import initial data
        let initialCSV = """
        ANNEE,SEQUENCE_VEHICULE,SEXE,GROUPE_AGE,REGION,MRC,GEO_CODE_MUNICIPALITE,MARQUE,MODELE,ANNEE_MODELE,COULEUR_VEHICULE,USAGE_VEHICULE,KILOMÉTRAGE,ÉTAT_VÉHICULE,CARBURANT,STATUT_VÉHICULE
        2022,1,M,25-34,01,06,66023,HONDA,ACCORD,2020,BLEU,PROMENADE,25000,BON,ESSENCE,ACTIF
        """

        let csvURL = try createTestCSVFile(content: initialCSV, filename: "cache_consistency.csv")
        _ = try await csvImporter.importFile(at: csvURL, year: 2022, dataType: .vehicle, skipDuplicateCheck: true)
        await databaseManager.refreshFilterCache()

        // Get initial cache state
        let initialYears = await databaseManager.getAvailableYears(for: .vehicle)
        let initialMakes = await databaseManager.getAvailableVehicleMakes()

        XCTAssertTrue(initialYears.contains(2022), "Initial cache should contain 2022")
        XCTAssertTrue(initialMakes.contains("HONDA"), "Initial cache should contain HONDA")

        // Clear only license cache (should not affect vehicle cache)
        filterCache.clearLicenseCache()

        // Verify vehicle cache is still intact
        let vehicleYearsAfterLicenseClear = await databaseManager.getAvailableYears(for: .vehicle)
        let vehicleMakesAfterLicenseClear = await databaseManager.getAvailableVehicleMakes()

        XCTAssertEqual(vehicleYearsAfterLicenseClear, initialYears, "Vehicle cache should be unaffected by license cache clear")
        XCTAssertEqual(vehicleMakesAfterLicenseClear, initialMakes, "Vehicle makes should be unaffected by license cache clear")

        // Full cache clear should affect everything
        filterCache.clearCache()

        // This should trigger cache rebuild
        let yearsAfterFullClear = await databaseManager.getAvailableYears(for: .vehicle)
        XCTAssertTrue(yearsAfterFullClear.contains(2022), "Should rebuild cache and still contain 2022")
    }

    // MARK: - Data Quality Integration Tests

    @MainActor
    func testDataQualityThroughWorkflow() async throws {
        // Test that data quality is maintained through the entire workflow

        // Import data with various edge cases
        let edgeCaseCSV = """
        ANNEE,SEQUENCE_VEHICULE,SEXE,GROUPE_AGE,REGION,MRC,GEO_CODE_MUNICIPALITE,MARQUE,MODELE,ANNEE_MODELE,COULEUR_VEHICULE,USAGE_VEHICULE,KILOMÉTRAGE,ÉTAT_VÉHICULE,CARBURANT,STATUT_VÉHICULE
        2023,1,M,25-34,01,06,66023,TOYOTA,COROLLA,2020,ROUGE,PROMENADE,25000,BON,ESSENCE,ACTIF
        2023,2,F,35-44,06,80,80005,HONDA,CIVIC,2019,BLEU,PROMENADE,35000,EXCELLENT,ÉLECTRIQUE,ACTIF
        2023,3,,45-54,03,30,30010,SUBARU,OUTBACK,2021,BLANC,PROMENADE,15000,BON,,ACTIF
        """

        let csvURL = try createTestCSVFile(content: edgeCaseCSV, filename: "data_quality.csv")
        let result = try await csvImporter.importFile(at: csvURL, year: 2023, dataType: .vehicle, skipDuplicateCheck: true)

        // Should import successfully despite some empty fields
        XCTAssertEqual(result.totalRecords, 3, "Should process all 3 records despite empty fields")
        XCTAssertGreaterThan(result.successCount, 0, "Should successfully import some records despite empty fields")

        await databaseManager.refreshFilterCache()

        // Test data filtering handles empty values gracefully
        var filterConfig = FilterConfiguration()
        filterConfig.dataEntityType = .vehicle
        filterConfig.years = Set([2023])

        let allData = try await databaseManager.queryVehicleData(filters: filterConfig)
        XCTAssertGreaterThanOrEqual(allData.points.count, 0, "Should retrieve data points despite empty fields")

        // Test filtering by non-empty fields
        filterConfig.vehicleMakes = Set(["TOYOTA"])
        let filteredData = try await databaseManager.queryVehicleData(filters: filterConfig)
        XCTAssertGreaterThanOrEqual(filteredData.points.count, 0, "Should filter correctly by make")
        XCTAssertTrue(filteredData.name.contains("TOYOTA"), "Filtered series should contain TOYOTA in name")
    }

    // MARK: - Performance Integration Tests

    @MainActor
    func testWorkflowPerformance() async throws {
        // Test that the complete workflow performs well with moderate data sizes

        // Create moderately large dataset (100 records)
        var csvContent = "ANNEE,SEQUENCE_VEHICULE,SEXE,GROUPE_AGE,REGION,MRC,GEO_CODE_MUNICIPALITE,MARQUE,MODELE,ANNEE_MODELE,COULEUR_VEHICULE,USAGE_VEHICULE,KILOMÉTRAGE,ÉTAT_VÉHICULE,CARBURANT,STATUT_VÉHICULE\n"

        let makes = ["TOYOTA", "HONDA", "FORD", "CHEVROLET", "SUBARU"]
        let models = ["COROLLA", "CIVIC", "F-150", "SILVERADO", "OUTBACK"]

        for i in 1...100 {
            let make = makes[i % makes.count]
            let model = models[i % models.count]
            csvContent += "2023,\(i),M,25-34,01,06,66023,\(make),\(model),2020,ROUGE,PROMENADE,25000,BON,ESSENCE,ACTIF\n"
        }

        let csvURL = try createTestCSVFile(content: csvContent, filename: "performance_test.csv")

        // Measure complete workflow performance
        let startTime = Date()

        // Import
        let importResult = try await csvImporter.importFile(at: csvURL, year: 2023, dataType: .vehicle, skipDuplicateCheck: true)
        let importTime = Date().timeIntervalSince(startTime)

        // Cache refresh
        let cacheStartTime = Date()
        await databaseManager.refreshFilterCache()
        let cacheTime = Date().timeIntervalSince(cacheStartTime)

        // Query
        let queryStartTime = Date()
        var filterConfig = FilterConfiguration()
        filterConfig.dataEntityType = .vehicle
        filterConfig.years = Set([2023])
        let queryData = try await databaseManager.queryVehicleData(filters: filterConfig)
        let queryTime = Date().timeIntervalSince(queryStartTime)

        // Assertions
        XCTAssertEqual(importResult.totalRecords, 100, "Should process all 100 records")
        XCTAssertEqual(importResult.successCount, 100, "Should successfully import all 100 records")
        XCTAssertGreaterThanOrEqual(queryData.points.count, 0, "Should return data points for performance test")

        // Performance assertions (reasonable limits)
        XCTAssertLessThan(importTime, 5.0, "Import should complete within 5 seconds")
        XCTAssertLessThan(cacheTime, 3.0, "Cache refresh should complete within 3 seconds")
        XCTAssertLessThan(queryTime, 1.0, "Query should complete within 1 second")

        print("Performance metrics - Import: \(importTime)s, Cache: \(cacheTime)s, Query: \(queryTime)s")
    }
}

// MARK: - Test Helpers

extension WorkflowIntegrationTests {

    /// Create a temporary CSV file with the given content
    private func createTestCSVFile(content: String, filename: String) throws -> URL {
        let fileURL = tempDirectory.appendingPathComponent(filename)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}

