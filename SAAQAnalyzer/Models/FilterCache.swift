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
        static let years = "FilterCache.years"
        static let regions = "FilterCache.regions"
        static let mrcs = "FilterCache.mrcs"
        static let municipalities = "FilterCache.municipalities"
        static let classifications = "FilterCache.classifications"
        static let vehicleMakes = "FilterCache.vehicleMakes"
        static let vehicleModels = "FilterCache.vehicleModels"
        static let vehicleColors = "FilterCache.vehicleColors"
        static let modelYears = "FilterCache.modelYears"
        static let databaseStats = "FilterCache.databaseStats"
        static let lastUpdated = "FilterCache.lastUpdated"
        static let dataVersion = "FilterCache.dataVersion"
    }
    
    // MARK: - Cache Status
    
    /// Check if cache exists and is valid (all required fields present)
    var hasCachedData: Bool {
        // Check if we have a last updated timestamp and basic data
        guard userDefaults.object(forKey: CacheKeys.lastUpdated) != nil,
              !getCachedYears().isEmpty else {
            return false
        }

        // Check that all required cache keys exist (even if empty arrays)
        // This ensures new fields trigger a cache refresh when first added
        let requiredKeys = [
            CacheKeys.regions,
            CacheKeys.mrcs,
            CacheKeys.municipalities,
            CacheKeys.classifications,
            CacheKeys.vehicleMakes,
            CacheKeys.vehicleModels,
            CacheKeys.vehicleColors,
            CacheKeys.modelYears,
            CacheKeys.databaseStats
        ]

        return requiredKeys.allSatisfy { key in
            userDefaults.object(forKey: key) != nil
        }
    }
    
    /// Get the last cache update timestamp
    var lastUpdated: Date? {
        return userDefaults.object(forKey: CacheKeys.lastUpdated) as? Date
    }
    
    /// Get the data version when cache was last updated
    var cachedDataVersion: String? {
        return userDefaults.string(forKey: CacheKeys.dataVersion)
    }
    
    // MARK: - Cache Reading
    
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
    
    func getCachedClassifications() -> [String] {
        return userDefaults.stringArray(forKey: CacheKeys.classifications) ?? []
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

    func getCachedModelYears() -> [Int] {
        return userDefaults.array(forKey: CacheKeys.modelYears) as? [Int] ?? []
    }

    func getCachedDatabaseStats() -> CachedDatabaseStats? {
        guard let data = userDefaults.data(forKey: CacheKeys.databaseStats) else { return nil }
        return try? JSONDecoder().decode(CachedDatabaseStats.self, from: data)
    }

    // MARK: - Cache Writing
    
    /// Update the entire cache with fresh data
    func updateCache(years: [Int], regions: [String], mrcs: [String], municipalities: [String],
                    classifications: [String], vehicleMakes: [String], vehicleModels: [String],
                    vehicleColors: [String], modelYears: [Int],
                    databaseStats: CachedDatabaseStats, dataVersion: String) {
        userDefaults.set(years, forKey: CacheKeys.years)
        userDefaults.set(regions, forKey: CacheKeys.regions)
        userDefaults.set(mrcs, forKey: CacheKeys.mrcs)
        userDefaults.set(municipalities, forKey: CacheKeys.municipalities)
        userDefaults.set(classifications, forKey: CacheKeys.classifications)
        userDefaults.set(vehicleMakes, forKey: CacheKeys.vehicleMakes)
        userDefaults.set(vehicleModels, forKey: CacheKeys.vehicleModels)
        userDefaults.set(vehicleColors, forKey: CacheKeys.vehicleColors)
        userDefaults.set(modelYears, forKey: CacheKeys.modelYears)

        // Cache database stats as JSON data
        if let statsData = try? JSONEncoder().encode(databaseStats) {
            userDefaults.set(statsData, forKey: CacheKeys.databaseStats)
        }

        userDefaults.set(Date(), forKey: CacheKeys.lastUpdated)
        userDefaults.set(dataVersion, forKey: CacheKeys.dataVersion)

        print("💾 Filter cache updated with \(years.count) years, \(regions.count) regions, \(mrcs.count) MRCs, \(municipalities.count) municipalities, \(classifications.count) classifications, \(vehicleMakes.count) makes, \(vehicleModels.count) models, \(vehicleColors.count) colors, \(modelYears.count) model years, database stats")
    }
    
    /// Clear the entire cache
    func clearCache() {
        userDefaults.removeObject(forKey: CacheKeys.years)
        userDefaults.removeObject(forKey: CacheKeys.regions)
        userDefaults.removeObject(forKey: CacheKeys.mrcs)
        userDefaults.removeObject(forKey: CacheKeys.municipalities)
        userDefaults.removeObject(forKey: CacheKeys.classifications)
        userDefaults.removeObject(forKey: CacheKeys.vehicleMakes)
        userDefaults.removeObject(forKey: CacheKeys.vehicleModels)
        userDefaults.removeObject(forKey: CacheKeys.vehicleColors)
        userDefaults.removeObject(forKey: CacheKeys.modelYears)
        userDefaults.removeObject(forKey: CacheKeys.databaseStats)
        userDefaults.removeObject(forKey: CacheKeys.lastUpdated)
        userDefaults.removeObject(forKey: CacheKeys.dataVersion)
        
        print("🗑️ Filter cache cleared")
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