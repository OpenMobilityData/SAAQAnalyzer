import Foundation

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
        static let lastUpdated = "FilterCache.lastUpdated"
        static let dataVersion = "FilterCache.dataVersion"
    }
    
    // MARK: - Cache Status
    
    /// Check if cache exists and is valid
    var hasCachedData: Bool {
        return userDefaults.object(forKey: CacheKeys.lastUpdated) != nil &&
               !getCachedYears().isEmpty
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
    
    // MARK: - Cache Writing
    
    /// Update the entire cache with fresh data
    func updateCache(years: [Int], regions: [String], mrcs: [String], municipalities: [String], classifications: [String], dataVersion: String) {
        userDefaults.set(years, forKey: CacheKeys.years)
        userDefaults.set(regions, forKey: CacheKeys.regions)
        userDefaults.set(mrcs, forKey: CacheKeys.mrcs)
        userDefaults.set(municipalities, forKey: CacheKeys.municipalities)
        userDefaults.set(classifications, forKey: CacheKeys.classifications)
        userDefaults.set(Date(), forKey: CacheKeys.lastUpdated)
        userDefaults.set(dataVersion, forKey: CacheKeys.dataVersion)
        
        print("💾 Filter cache updated with \(years.count) years, \(regions.count) regions, \(mrcs.count) MRCs, \(municipalities.count) municipalities, \(classifications.count) classifications")
    }
    
    /// Clear the entire cache
    func clearCache() {
        userDefaults.removeObject(forKey: CacheKeys.years)
        userDefaults.removeObject(forKey: CacheKeys.regions)
        userDefaults.removeObject(forKey: CacheKeys.mrcs)
        userDefaults.removeObject(forKey: CacheKeys.municipalities)
        userDefaults.removeObject(forKey: CacheKeys.classifications)
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
        
        let needsRefresh = cachedVersion != currentDataVersion
        if needsRefresh {
            print("📊 Data version changed (\(cachedVersion) → \(currentDataVersion)), refresh needed")
        }
        
        return needsRefresh
    }
}