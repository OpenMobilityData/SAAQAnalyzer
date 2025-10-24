//
//  FilterCacheTests.swift
//  SAAQAnalyzerTests
//
//  Created by Claude Code on 2025-01-27.
//

import XCTest
@testable import SAAQAnalyzer

final class FilterCacheTests: XCTestCase {

    var filterCache: FilterCache!
    var testSuiteName: String!

    override func setUpWithError() throws {
        // Create a fresh FilterCache instance for each test
        // Note: FilterCache uses UserDefaults.standard, so we'll clear test keys after each test
        filterCache = FilterCache()
        testSuiteName = "FilterCacheTests-\(UUID().uuidString)"

        // Clear any existing test data
        clearTestData()
    }

    override func tearDownWithError() throws {
        // Clean up test data from UserDefaults
        clearTestData()
        filterCache = nil
        testSuiteName = nil
    }

    private func clearTestData() {
        // Clear all cache keys to ensure test isolation
        let testKeys = [
            "FilterCache.vehicleYears", "FilterCache.vehicleRegions", "FilterCache.vehicleMRCs",
            "FilterCache.licenseYears", "FilterCache.licenseRegions", "FilterCache.licenseMRCs",
            "FilterCache.licenseTypes", "FilterCache.licenseAgeGroups", "FilterCache.licenseGenders",
            "FilterCache.licenseExperienceLevels", "FilterCache.licenseClasses",
            "FilterCache.years", "FilterCache.regions", "FilterCache.mrcs", "FilterCache.municipalities",
            "FilterCache.classifications", "FilterCache.vehicleMakes", "FilterCache.vehicleModels",
            "FilterCache.vehicleColors", "FilterCache.modelYears", "FilterCache.ageGroups",
            "FilterCache.genders", "FilterCache.experienceLevels", "FilterCache.municipalityCodeToName",
            "FilterCache.databaseStats", "FilterCache.lastUpdated", "FilterCache.dataVersion"
        ]

        for key in testKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.synchronize()
    }

    // MARK: - Cache Separation Tests

    func testVehicleCacheSeparation() throws {
        // Given: Vehicle cache data
        let vehicleYears = [2020, 2021, 2022]
        let vehicleRegions = ["Montreal", "Quebec", "Laval"]
        let vehicleMRCs = ["06", "23", "65"]

        // When: Updating vehicle cache
        filterCache.updateVehicleCache(
            years: vehicleYears,
            regions: vehicleRegions,
            mrcs: vehicleMRCs,
            municipalities: [],
            classifications: [],
            vehicleMakes: [],
            vehicleModels: [],
            vehicleColors: [],
            modelYears: []
        )

        // Then: Vehicle data should be retrievable with correct keys
        XCTAssertEqual(filterCache.getCachedYears(for: .vehicle), vehicleYears)
        XCTAssertEqual(filterCache.getCachedRegions(for: .vehicle), vehicleRegions)
        XCTAssertEqual(filterCache.getCachedMRCs(for: .vehicle), vehicleMRCs)

        // And: License cache should be empty (no cross-contamination)
        XCTAssertTrue(filterCache.getCachedYears(for: .license).isEmpty)
        XCTAssertTrue(filterCache.getCachedRegions(for: .license).isEmpty)
        XCTAssertTrue(filterCache.getCachedMRCs(for: .license).isEmpty)
    }

    func testLicenseCacheSeparation() throws {
        // Given: License cache data
        let licenseYears = [2019, 2020, 2021]
        let licenseRegions = ["Montreal", "Quebec", "Sherbrooke", "Trois-Rivieres", "Gatineau"] // More regions than vehicle
        let licenseMRCs = ["06", "23", "43", "37"] // Different MRCs than vehicle
        let licenseTypes = ["REGULIER", "PROBATOIRE", "APPRENTI"]
        let ageGroups = ["16-19", "20-24", "25-34", "35-44", "45-54"]

        // When: Updating license cache
        filterCache.updateLicenseCache(
            years: licenseYears,
            regions: licenseRegions,
            mrcs: licenseMRCs,
            licenseTypes: licenseTypes,
            ageGroups: ageGroups,
            genders: [],
            experienceLevels: [],
            licenseClasses: []
        )

        // Then: License data should be retrievable with correct keys
        XCTAssertEqual(filterCache.getCachedYears(for: .license), licenseYears)
        XCTAssertEqual(filterCache.getCachedRegions(for: .license), licenseRegions)
        XCTAssertEqual(filterCache.getCachedMRCs(for: .license), licenseMRCs)
        XCTAssertEqual(filterCache.getCachedLicenseTypes(), licenseTypes)
        XCTAssertEqual(filterCache.getCachedLicenseAgeGroups(), ageGroups)

        // And: Vehicle cache should be empty (no cross-contamination)
        XCTAssertTrue(filterCache.getCachedYears(for: .vehicle).isEmpty)
        XCTAssertTrue(filterCache.getCachedRegions(for: .vehicle).isEmpty)
        XCTAssertTrue(filterCache.getCachedMRCs(for: .vehicle).isEmpty)
    }

    func testCacheKeyCorrectness() throws {
        // This test prevents the cache key mismatch bug we fixed
        // Given: License-specific data
        let experienceLevels = ["Moins de 2 ans", "2 à 5 ans", "6 à 9 ans", "10 ans ou plus", "Absente"]
        let ageGroups = ["16-19", "20-24", "25-34", "35-44"]
        let genders = ["Male", "Female"]
        let licenseClasses = ["1-2-3-4", "5", "6A-6B-6C-6E"]

        // When: Storing license data
        filterCache.updateLicenseCache(
            years: [],
            regions: [],
            mrcs: [],
            licenseTypes: [],
            ageGroups: ageGroups,
            genders: genders,
            experienceLevels: experienceLevels,
            licenseClasses: licenseClasses
        )

        // Then: Data should be retrievable with license-specific methods
        XCTAssertEqual(filterCache.getCachedLicenseExperienceLevels(), experienceLevels)
        XCTAssertEqual(filterCache.getCachedLicenseAgeGroups(), ageGroups)
        XCTAssertEqual(filterCache.getCachedLicenseGenders(), genders)
        XCTAssertEqual(filterCache.getCachedLicenseClasses(), licenseClasses)
    }

    // MARK: - Cache State Management Tests

    func testCacheDataPresence() throws {
        // Given: Empty cache initially
        XCTAssertFalse(filterCache.hasCachedData)
        XCTAssertFalse(filterCache.hasLicenseDataCached)

        // When: Adding vehicle data only
        filterCache.updateVehicleCache(
            years: [2022],
            regions: ["Montreal"],
            mrcs: ["06"],
            municipalities: [],
            classifications: [],
            vehicleMakes: [],
            vehicleModels: [],
            vehicleColors: [],
            modelYears: []
        )

        // Then: General cache should be true, but license cache should be false
        XCTAssertTrue(filterCache.hasCachedData)
        XCTAssertFalse(filterCache.hasLicenseDataCached)

        // When: Adding license data
        filterCache.updateLicenseCache(
            years: [2022],
            regions: ["Montreal"],
            mrcs: ["06"],
            licenseTypes: ["REGULIER"],
            ageGroups: [],
            genders: [],
            experienceLevels: [],
            licenseClasses: []
        )

        // Then: Both caches should be true
        XCTAssertTrue(filterCache.hasCachedData)
        XCTAssertTrue(filterCache.hasLicenseDataCached)
    }

    func testDataVersionHandling() throws {
        let testVersion = "1234567890"

        // Given: No cached version initially
        XCTAssertNil(filterCache.cachedDataVersion)

        // When: Finalizing cache update with version
        let testStats = CachedDatabaseStats(
            totalVehicleRecords: 0,
            vehicleYearRange: "No data",
            availableVehicleYearsCount: 0,
            totalLicenseRecords: 0,
            licenseYearRange: "No data",
            availableLicenseYearsCount: 0,
            municipalities: 0,
            regions: 0,
            fileSizeBytes: 0,
            pageSizeBytes: 4096,
            lastUpdated: Date()
        )

        filterCache.finalizeCacheUpdate(
            municipalityCodeToName: [:],
            databaseStats: testStats,
            dataVersion: testVersion
        )

        // Then: Version should be stored and retrievable
        XCTAssertEqual(filterCache.cachedDataVersion, testVersion)

        // When: Checking if refresh is needed with same version
        XCTAssertFalse(filterCache.needsRefresh(currentDataVersion: testVersion))

        // When: Checking with different version
        XCTAssertTrue(filterCache.needsRefresh(currentDataVersion: "9876543210"))
    }

    func testVersionMigration() throws {
        // Given: Old version format (short integer)
        let oldVersion = "5"
        let newVersion = "1234567890" // Timestamp format

        filterCache.updateDataVersion(oldVersion)
        XCTAssertEqual(filterCache.cachedDataVersion, oldVersion)

        // When: Checking refresh with new version format
        let needsRefresh = filterCache.needsRefresh(currentDataVersion: newVersion)

        // Then: Should trigger refresh due to format migration
        XCTAssertTrue(needsRefresh)
        // And version should be automatically updated
        XCTAssertEqual(filterCache.cachedDataVersion, newVersion)
    }

    // MARK: - Cache Clearing Tests

    func testFullCacheClear() throws {
        // Given: Cache with both vehicle and license data
        filterCache.updateVehicleCache(
            years: [2022],
            regions: ["Montreal"],
            mrcs: ["06"],
            municipalities: [],
            classifications: [],
            vehicleMakes: [],
            vehicleModels: [],
            vehicleColors: [],
            modelYears: []
        )

        filterCache.updateLicenseCache(
            years: [2022],
            regions: ["Montreal"],
            mrcs: ["06"],
            licenseTypes: ["REGULIER"],
            ageGroups: ["25-34"],
            genders: [],
            experienceLevels: [],
            licenseClasses: []
        )

        XCTAssertTrue(filterCache.hasCachedData)
        XCTAssertTrue(filterCache.hasLicenseDataCached)

        // When: Clearing full cache
        filterCache.clearCache()

        // Then: All cache should be empty
        XCTAssertFalse(filterCache.hasCachedData)
        XCTAssertFalse(filterCache.hasLicenseDataCached)
        XCTAssertTrue(filterCache.getCachedYears(for: .vehicle).isEmpty)
        XCTAssertTrue(filterCache.getCachedYears(for: .license).isEmpty)
        XCTAssertTrue(filterCache.getCachedLicenseTypes().isEmpty)
    }

    func testLicenseOnlyCacheClear() throws {
        // Given: Cache with both vehicle and license data
        filterCache.updateVehicleCache(
            years: [2022],
            regions: ["Montreal"],
            mrcs: ["06"],
            municipalities: [],
            classifications: [],
            vehicleMakes: [],
            vehicleModels: [],
            vehicleColors: [],
            modelYears: []
        )

        filterCache.updateLicenseCache(
            years: [2022],
            regions: ["Quebec"],
            mrcs: ["23"],
            licenseTypes: ["REGULIER"],
            ageGroups: ["25-34"],
            genders: [],
            experienceLevels: [],
            licenseClasses: []
        )

        let vehicleYearsBefore = filterCache.getCachedYears(for: .vehicle)
        let vehicleRegionsBefore = filterCache.getCachedRegions(for: .vehicle)

        // When: Clearing only license cache
        filterCache.clearLicenseCache()

        // Then: License data should be cleared
        XCTAssertFalse(filterCache.hasLicenseDataCached)
        XCTAssertTrue(filterCache.getCachedYears(for: .license).isEmpty)
        XCTAssertTrue(filterCache.getCachedRegions(for: .license).isEmpty)
        XCTAssertTrue(filterCache.getCachedLicenseTypes().isEmpty)

        // And: Vehicle data should remain intact
        XCTAssertTrue(filterCache.hasCachedData)
        XCTAssertEqual(filterCache.getCachedYears(for: .vehicle), vehicleYearsBefore)
        XCTAssertEqual(filterCache.getCachedRegions(for: .vehicle), vehicleRegionsBefore)
    }

    // MARK: - Performance Tests

    func testCachePerformance() throws {
        // Test that cache operations are fast even with realistic data sizes
        let years = Array(2012...2023) // 12 years
        let regions = Array(1...35).map { "Region \($0)" } // 35 regions like license mode
        let mrcs = Array(1...106).map { "MRC \($0)" } // 106 MRCs
        // Performance test for cache update (no municipalities for license cache)
        measure {
            filterCache.updateLicenseCache(
                years: years,
                regions: regions,
                mrcs: mrcs,
                licenseTypes: ["REGULIER", "PROBATOIRE", "APPRENTI"],
                ageGroups: ["16-19", "20-24", "25-34", "35-44", "45-54", "55-64", "65-74", "75+"],
                genders: ["Male", "Female"],
                experienceLevels: ["Moins de 2 ans", "2 à 5 ans", "6 à 9 ans", "10 ans ou plus", "Absente"],
                licenseClasses: ["1-2-3-4", "5", "6A-6B-6C-6E", "6D", "8", "Learner 1-2-3", "Learner 5", "Learner 6A-6R"]
            )
        }

        // Verify all data was stored correctly
        XCTAssertEqual(filterCache.getCachedYears(for: .license).count, 12)
        XCTAssertEqual(filterCache.getCachedRegions(for: .license).count, 35)
        XCTAssertEqual(filterCache.getCachedMRCs(for: .license).count, 106)
        XCTAssertEqual(filterCache.getCachedLicenseTypes().count, 3)
        XCTAssertEqual(filterCache.getCachedLicenseClasses().count, 8)
    }
}

// MARK: - Test Helpers

// Note: FilterCache uses UserDefaults.standard directly, which limits test isolation.
// In a future refactor, consider dependency injection for better testability.