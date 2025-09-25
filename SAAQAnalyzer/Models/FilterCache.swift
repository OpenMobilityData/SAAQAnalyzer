import Foundation

/// Database statistics for caching
struct CachedDatabaseStats: Codable {
    // Vehicle data statistics
    let totalVehicleRecords: Int
    let vehicleYearRange: String
    let availableVehicleYearsCount: Int

    // License data statistics
    let totalLicenseRecords: Int
    let licenseYearRange: String
    let availableLicenseYearsCount: Int

    // Shared statistics
    let municipalities: Int
    let regions: Int
    let fileSizeBytes: Int64
    let lastUpdated: Date

    // Computed properties for backward compatibility and convenience
    var totalRecords: Int {
        totalVehicleRecords + totalLicenseRecords
    }

    var yearRange: String {
        let vehicleEmpty = vehicleYearRange == "No data"
        let licenseEmpty = licenseYearRange == "No data"

        if vehicleEmpty && licenseEmpty {
            return "No data"
        } else if vehicleEmpty {
            return licenseYearRange
        } else if licenseEmpty {
            return vehicleYearRange
        } else {
            return "\(vehicleYearRange) (vehicles), \(licenseYearRange) (licenses)"
        }
    }

    var availableYearsCount: Int {
        max(availableVehicleYearsCount, availableLicenseYearsCount)
    }
}

/// Manages caching of filter options to avoid expensive database queries on every app launch
class FilterCache {
    private let userDefaults = UserDefaults.standard
    
    // Cache keys
    private enum CacheKeys {
        // Shared metadata
        static let databaseStats = "FilterCache.databaseStats"
        static let lastUpdated = "FilterCache.lastUpdated"
        static let dataVersion = "FilterCache.dataVersion"
        static let municipalityCodeToName = "FilterCache.municipalityCodeToName"

        // Vehicle cache keys
        static let vehicleYears = "FilterCache.vehicleYears"
        static let vehicleRegions = "FilterCache.vehicleRegions"
        static let vehicleMRCs = "FilterCache.vehicleMRCs"
        static let vehicleMunicipalities = "FilterCache.vehicleMunicipalities"
        static let vehicleClassifications = "FilterCache.vehicleClassifications"
        static let vehicleMakes = "FilterCache.vehicleMakes"
        static let vehicleModels = "FilterCache.vehicleModels"
        static let vehicleColors = "FilterCache.vehicleColors"
        static let vehicleModelYears = "FilterCache.vehicleModelYears"

        // License cache keys
        static let licenseYears = "FilterCache.licenseYears"
        static let licenseRegions = "FilterCache.licenseRegions"
        static let licenseMRCs = "FilterCache.licenseMRCs"
        static let licenseMunicipalities = "FilterCache.licenseMunicipalities"
        static let licenseTypes = "FilterCache.licenseTypes"
        static let licenseAgeGroups = "FilterCache.licenseAgeGroups"
        static let licenseGenders = "FilterCache.licenseGenders"
        static let licenseExperienceLevels = "FilterCache.licenseExperienceLevels"
        static let licenseClasses = "FilterCache.licenseClasses"

        // Legacy keys for backward compatibility
        static let years = "FilterCache.years"
        static let regions = "FilterCache.regions"
        static let mrcs = "FilterCache.mrcs"
        static let municipalities = "FilterCache.municipalities"
        static let classifications = "FilterCache.classifications"
        static let modelYears = "FilterCache.modelYears"
        static let ageGroups = "FilterCache.ageGroups"
        static let genders = "FilterCache.genders"
        static let experienceLevels = "FilterCache.experienceLevels"
    }
    
    // MARK: - Cache Status
    
    /// Check if cache exists and is valid for the specified data type
    func hasCachedData(for dataType: DataEntityType) -> Bool {
        // Check if we have basic metadata
        guard userDefaults.object(forKey: CacheKeys.lastUpdated) != nil,
              userDefaults.object(forKey: CacheKeys.databaseStats) != nil else {
            return false
        }

        switch dataType {
        case .vehicle:
            let vehicleKeys = [
                CacheKeys.vehicleYears,
                CacheKeys.vehicleRegions,
                CacheKeys.vehicleMRCs,
                CacheKeys.vehicleMunicipalities,
                CacheKeys.vehicleClassifications,
                CacheKeys.vehicleMakes,
                CacheKeys.vehicleModels,
                CacheKeys.vehicleColors,
                CacheKeys.vehicleModelYears
            ]
            return vehicleKeys.allSatisfy { userDefaults.object(forKey: $0) != nil }

        case .license:
            let licenseKeys = [
                CacheKeys.licenseYears,
                CacheKeys.licenseRegions,
                CacheKeys.licenseMRCs,
                CacheKeys.licenseMunicipalities,
                CacheKeys.licenseTypes,
                CacheKeys.licenseAgeGroups,
                CacheKeys.licenseGenders,
                CacheKeys.licenseExperienceLevels,
                CacheKeys.licenseClasses
            ]
            return licenseKeys.allSatisfy { userDefaults.object(forKey: $0) != nil }
        }
    }

    /// Check if cache exists for any data type (for backward compatibility)
    var hasCachedData: Bool {
        return hasCachedData(for: .vehicle) || hasCachedData(for: .license)
    }
    
    /// Get the last cache update timestamp
    var lastUpdated: Date? {
        return userDefaults.object(forKey: CacheKeys.lastUpdated) as? Date
    }
    
    /// Get the data version when cache was last updated
    var cachedDataVersion: String? {
        let version = userDefaults.string(forKey: CacheKeys.dataVersion)
        print("🔍 Reading cached data version: \(version ?? "nil")")
        return version
    }
    
    // MARK: - Cache Reading

    func getCachedYears(for dataType: DataEntityType) -> [Int] {
        switch dataType {
        case .vehicle:
            return userDefaults.array(forKey: CacheKeys.vehicleYears) as? [Int] ?? []
        case .license:
            return userDefaults.array(forKey: CacheKeys.licenseYears) as? [Int] ?? []
        }
    }

    func getCachedRegions(for dataType: DataEntityType) -> [String] {
        switch dataType {
        case .vehicle:
            return userDefaults.stringArray(forKey: CacheKeys.vehicleRegions) ?? []
        case .license:
            return userDefaults.stringArray(forKey: CacheKeys.licenseRegions) ?? []
        }
    }

    func getCachedMRCs(for dataType: DataEntityType) -> [String] {
        switch dataType {
        case .vehicle:
            return userDefaults.stringArray(forKey: CacheKeys.vehicleMRCs) ?? []
        case .license:
            return userDefaults.stringArray(forKey: CacheKeys.licenseMRCs) ?? []
        }
    }

    func getCachedMunicipalities(for dataType: DataEntityType) -> [String] {
        switch dataType {
        case .vehicle:
            return userDefaults.stringArray(forKey: CacheKeys.vehicleMunicipalities) ?? []
        case .license:
            return userDefaults.stringArray(forKey: CacheKeys.licenseMunicipalities) ?? []
        }
    }

    // Legacy methods for backward compatibility
    func getCachedYears() -> [Int] {
        return userDefaults.array(forKey: CacheKeys.years) as? [Int] ?? []
    }

    func getCachedRegions() -> [String] {
        return userDefaults.stringArray(forKey: CacheKeys.regions) ?? []
    }

    func getCachedMRCs() -> [String] {
        return userDefaults.stringArray(forKey: CacheKeys.mrcs) ?? []
    }
    
    func getCachedMunicipalities() -> [String] {
        return userDefaults.stringArray(forKey: CacheKeys.municipalities) ?? []
    }

    func getCachedMunicipalityCodeToName() -> [String: String] {
        guard let data = userDefaults.data(forKey: CacheKeys.municipalityCodeToName) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
    
    // Vehicle-specific cache methods
    func getCachedVehicleClassifications() -> [String] {
        return userDefaults.stringArray(forKey: CacheKeys.vehicleClassifications) ?? []
    }

    func getCachedVehicleMakes() -> [String] {
        return userDefaults.stringArray(forKey: CacheKeys.vehicleMakes) ?? []
    }

    func getCachedVehicleModels() -> [String] {
        return userDefaults.stringArray(forKey: CacheKeys.vehicleModels) ?? []
    }

    func getCachedVehicleColors() -> [String] {
        return userDefaults.stringArray(forKey: CacheKeys.vehicleColors) ?? []
    }

    func getCachedVehicleModelYears() -> [Int] {
        return userDefaults.array(forKey: CacheKeys.vehicleModelYears) as? [Int] ?? []
    }

    // Legacy vehicle methods for backward compatibility
    func getCachedClassifications() -> [String] {
        return userDefaults.stringArray(forKey: CacheKeys.classifications) ?? []
    }

    func getCachedModelYears() -> [Int] {
        return userDefaults.array(forKey: CacheKeys.modelYears) as? [Int] ?? []
    }

    func getCachedDatabaseStats() -> CachedDatabaseStats? {
        guard let data = userDefaults.data(forKey: CacheKeys.databaseStats) else { return nil }
        return try? JSONDecoder().decode(CachedDatabaseStats.self, from: data)
    }

    // License-specific cache reading methods
    func getCachedLicenseTypes() -> [String] {
        return userDefaults.stringArray(forKey: CacheKeys.licenseTypes) ?? []
    }

    func getCachedLicenseAgeGroups() -> [String] {
        return userDefaults.stringArray(forKey: CacheKeys.licenseAgeGroups) ?? []
    }

    func getCachedLicenseGenders() -> [String] {
        return userDefaults.stringArray(forKey: CacheKeys.licenseGenders) ?? []
    }

    func getCachedLicenseExperienceLevels() -> [String] {
        return userDefaults.stringArray(forKey: CacheKeys.licenseExperienceLevels) ?? []
    }

    func getCachedLicenseClasses() -> [String] {
        return userDefaults.stringArray(forKey: CacheKeys.licenseClasses) ?? []
    }

    // Legacy license methods for backward compatibility
    func getCachedAgeGroups() -> [String] {
        return userDefaults.stringArray(forKey: CacheKeys.ageGroups) ?? []
    }

    func getCachedGenders() -> [String] {
        return userDefaults.stringArray(forKey: CacheKeys.genders) ?? []
    }

    func getCachedExperienceLevels() -> [String] {
        return userDefaults.stringArray(forKey: CacheKeys.licenseExperienceLevels) ?? []
    }

    /// Check if license data is cached
    var hasLicenseDataCached: Bool {
        // Check if any license cache key exists
        return userDefaults.object(forKey: CacheKeys.licenseTypes) != nil
    }

    // MARK: - Cache Writing
    
    /// Update the vehicle cache with fresh data
    func updateVehicleCache(years: [Int], regions: [String], mrcs: [String], municipalities: [String],
                           classifications: [String], vehicleMakes: [String], vehicleModels: [String],
                           vehicleColors: [String], modelYears: [Int]) {
        // Vehicle-specific data
        userDefaults.set(years, forKey: CacheKeys.vehicleYears)
        userDefaults.set(regions, forKey: CacheKeys.vehicleRegions)
        userDefaults.set(mrcs, forKey: CacheKeys.vehicleMRCs)
        userDefaults.set(municipalities, forKey: CacheKeys.vehicleMunicipalities)
        userDefaults.set(classifications, forKey: CacheKeys.vehicleClassifications)
        userDefaults.set(vehicleMakes, forKey: CacheKeys.vehicleMakes)
        userDefaults.set(vehicleModels, forKey: CacheKeys.vehicleModels)
        userDefaults.set(vehicleColors, forKey: CacheKeys.vehicleColors)
        userDefaults.set(modelYears, forKey: CacheKeys.vehicleModelYears)

        print("💾 Vehicle cache updated with \(years.count) years, \(regions.count) regions, \(mrcs.count) MRCs, \(municipalities.count) municipalities, \(classifications.count) classifications, \(vehicleMakes.count) makes, \(vehicleModels.count) models, \(vehicleColors.count) colors, \(modelYears.count) model years")
    }

    /// Update the license cache with fresh data
    func updateLicenseCache(years: [Int], regions: [String], mrcs: [String], municipalities: [String],
                           licenseTypes: [String], ageGroups: [String], genders: [String],
                           experienceLevels: [String], licenseClasses: [String]) {
        // License-specific data
        userDefaults.set(years, forKey: CacheKeys.licenseYears)
        userDefaults.set(regions, forKey: CacheKeys.licenseRegions)
        userDefaults.set(mrcs, forKey: CacheKeys.licenseMRCs)
        userDefaults.set(municipalities, forKey: CacheKeys.licenseMunicipalities)
        userDefaults.set(licenseTypes, forKey: CacheKeys.licenseTypes)
        userDefaults.set(ageGroups, forKey: CacheKeys.licenseAgeGroups)
        userDefaults.set(genders, forKey: CacheKeys.licenseGenders)
        userDefaults.set(experienceLevels, forKey: CacheKeys.licenseExperienceLevels)
        userDefaults.set(licenseClasses, forKey: CacheKeys.licenseClasses)

        print("💾 License cache updated with \(years.count) years, \(regions.count) regions, \(mrcs.count) MRCs, \(municipalities.count) municipalities, \(licenseTypes.count) license types, \(ageGroups.count) age groups, \(genders.count) genders, \(experienceLevels.count) experience levels, \(licenseClasses.count) license classes")
    }

    /// Update shared metadata and finish cache update
    func finalizeCacheUpdate(municipalityCodeToName: [String: String], databaseStats: CachedDatabaseStats, dataVersion: String) {
        print("🔧 finalizeCacheUpdate called with dataVersion: \(dataVersion)")
        // Cache municipality mapping as JSON data
        if let mappingData = try? JSONEncoder().encode(municipalityCodeToName) {
            userDefaults.set(mappingData, forKey: CacheKeys.municipalityCodeToName)
        }

        // Cache database stats as JSON data
        if let statsData = try? JSONEncoder().encode(databaseStats) {
            userDefaults.set(statsData, forKey: CacheKeys.databaseStats)
        }

        userDefaults.set(Date(), forKey: CacheKeys.lastUpdated)
        userDefaults.set(dataVersion, forKey: CacheKeys.dataVersion)

        // Force synchronization to ensure the write completes
        userDefaults.synchronize()

        print("💾 Cache metadata updated - data version set to: \(dataVersion)")

        // Verify the write succeeded
        let verifyVersion = userDefaults.string(forKey: CacheKeys.dataVersion)
        print("💾 Verification - cached version is now: \(verifyVersion ?? "nil")")
    }
    
    /// Clear the entire cache
    func clearCache() {
        // Shared keys
        userDefaults.removeObject(forKey: CacheKeys.years)
        userDefaults.removeObject(forKey: CacheKeys.regions)
        userDefaults.removeObject(forKey: CacheKeys.mrcs)
        userDefaults.removeObject(forKey: CacheKeys.municipalities)
        userDefaults.removeObject(forKey: CacheKeys.municipalityCodeToName)
        userDefaults.removeObject(forKey: CacheKeys.databaseStats)
        userDefaults.removeObject(forKey: CacheKeys.lastUpdated)
        userDefaults.removeObject(forKey: CacheKeys.dataVersion)

        // Vehicle-specific keys
        userDefaults.removeObject(forKey: CacheKeys.vehicleRegions)
        userDefaults.removeObject(forKey: CacheKeys.vehicleMRCs)
        userDefaults.removeObject(forKey: CacheKeys.classifications)
        userDefaults.removeObject(forKey: CacheKeys.vehicleMakes)
        userDefaults.removeObject(forKey: CacheKeys.vehicleModels)
        userDefaults.removeObject(forKey: CacheKeys.vehicleColors)
        userDefaults.removeObject(forKey: CacheKeys.modelYears)

        // License-specific keys
        userDefaults.removeObject(forKey: CacheKeys.licenseRegions)
        userDefaults.removeObject(forKey: CacheKeys.licenseMRCs)
        userDefaults.removeObject(forKey: CacheKeys.licenseTypes)
        userDefaults.removeObject(forKey: CacheKeys.ageGroups)
        userDefaults.removeObject(forKey: CacheKeys.genders)
        userDefaults.removeObject(forKey: CacheKeys.experienceLevels)
        userDefaults.removeObject(forKey: CacheKeys.licenseClasses)

        print("🗑️ Filter cache cleared")
    }

    /// Clear only license-specific cache to force refresh of license data
    func clearLicenseCache() {
        // License-specific keys
        userDefaults.removeObject(forKey: CacheKeys.licenseYears)
        userDefaults.removeObject(forKey: CacheKeys.licenseRegions)
        userDefaults.removeObject(forKey: CacheKeys.licenseMRCs)
        userDefaults.removeObject(forKey: CacheKeys.licenseMunicipalities)
        userDefaults.removeObject(forKey: CacheKeys.licenseTypes)
        userDefaults.removeObject(forKey: CacheKeys.licenseAgeGroups)
        userDefaults.removeObject(forKey: CacheKeys.licenseGenders)
        userDefaults.removeObject(forKey: CacheKeys.licenseExperienceLevels)
        userDefaults.removeObject(forKey: CacheKeys.licenseClasses)

        print("🗑️ License cache cleared")
    }
    
    /// Check if cache needs refresh based on data version
    func needsRefresh(currentDataVersion: String) -> Bool {
        guard let cachedVersion = cachedDataVersion else {
            print("📊 No cached data version, refresh needed")
            return true
        }

        // Handle migration from old integer-based versions to timestamp-based versions
        // Old versions were simple integers (1, 2, 3...), new versions are timestamps (10+ digits)
        if cachedVersion.count < 10 && currentDataVersion.count >= 10 {
            print("📊 Migrating from old version system (\(cachedVersion) → \(currentDataVersion)), updating cache version")
            // Immediately update the cache version to prevent repeated migration checks
            updateDataVersion(currentDataVersion)
            return true
        }

        let needsRefresh = cachedVersion != currentDataVersion
        if needsRefresh {
            print("📊 Data version changed (\(cachedVersion) → \(currentDataVersion)), refresh needed")
        }

        return needsRefresh
    }

    /// Updates only the data version in cache (for migration scenarios)
    func updateDataVersion(_ newVersion: String) {
        userDefaults.set(newVersion, forKey: CacheKeys.dataVersion)
        print("📊 Cache data version updated to: \(newVersion)")
    }
}