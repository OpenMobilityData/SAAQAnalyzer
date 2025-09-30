import Foundation
import SQLite3

/// Manages caching of filter options with integer IDs and display names
/// Loads data from enumeration tables instead of raw string columns
class FilterCacheManager {
    private weak var databaseManager: DatabaseManager?
    private var db: OpaquePointer? { databaseManager?.db }

    // Cache storage for filter items
    private var cachedYears: [Int] = []
    private var cachedRegions: [FilterItem] = []
    private var cachedMRCs: [FilterItem] = []
    private var cachedMunicipalities: [FilterItem] = []
    private var cachedClassifications: [FilterItem] = []
    private var cachedMakes: [FilterItem] = []
    private var cachedModels: [FilterItem] = []
    private var cachedColors: [FilterItem] = []
    private var cachedFuelTypes: [FilterItem] = []
    private var cachedLicenseTypes: [FilterItem] = []
    private var cachedAgeGroups: [FilterItem] = []
    private var cachedGenders: [FilterItem] = []

    private var isInitialized = false

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    // MARK: - Cache Loading

    /// Initialize all filter caches from enumeration tables
    func initializeCache() async throws {
        guard !isInitialized else { return }

        print("🔄 Loading filter cache from enumeration tables...")

        try await loadYears()
        try await loadRegions()
        try await loadMRCs()
        try await loadMunicipalities()
        try await loadClassifications()
        try await loadMakes()
        try await loadModels()
        try await loadColors()
        try await loadFuelTypes()
        try await loadLicenseTypes()
        try await loadAgeGroups()
        try await loadGenders()

        isInitialized = true
        print("✅ Filter cache initialized with enumeration data")
    }

    // MARK: - Individual Cache Loaders

    private func loadYears() async throws {
        let sql = "SELECT DISTINCT year FROM year_enum ORDER BY year;"
        cachedYears = try await executeIntQuery(sql)
    }

    private func loadRegions() async throws {
        let sql = "SELECT id, name || ' (' || code || ')' FROM admin_region_enum ORDER BY name;"
        cachedRegions = try await executeFilterItemQuery(sql)
    }

    private func loadMRCs() async throws {
        let sql = "SELECT id, name || ' (' || code || ')' FROM mrc_enum ORDER BY name;"
        cachedMRCs = try await executeFilterItemQuery(sql)
    }

    private func loadMunicipalities() async throws {
        let sql = """
        SELECT id,
               CASE
                   WHEN name = code THEN 'Unlisted (' || code || ')'
                   ELSE name || ' (' || code || ')'
               END
        FROM municipality_enum ORDER BY name;
        """
        cachedMunicipalities = try await executeFilterItemQuery(sql)
    }

    private func loadClassifications() async throws {
        let sql = "SELECT id, code FROM classification_enum ORDER BY code;"
        cachedClassifications = try await executeFilterItemQuery(sql)
    }

    private func loadMakes() async throws {
        let sql = "SELECT id, name FROM make_enum ORDER BY name;"
        cachedMakes = try await executeFilterItemQuery(sql)
    }

    private func loadModels() async throws {
        let sql = """
        SELECT m.id, m.name || ' (' || mk.name || ')' as display_name
        FROM model_enum m
        JOIN make_enum mk ON m.make_id = mk.id
        ORDER BY mk.name, m.name;
        """
        cachedModels = try await executeFilterItemQuery(sql)
    }

    private func loadColors() async throws {
        let sql = "SELECT id, name FROM color_enum ORDER BY name;"
        cachedColors = try await executeFilterItemQuery(sql)
    }

    private func loadFuelTypes() async throws {
        let sql = "SELECT id, description FROM fuel_type_enum ORDER BY description;"
        cachedFuelTypes = try await executeFilterItemQuery(sql)
    }

    private func loadLicenseTypes() async throws {
        let sql = "SELECT id, type_name FROM license_type_enum ORDER BY type_name;"
        cachedLicenseTypes = try await executeFilterItemQuery(sql)
    }

    private func loadAgeGroups() async throws {
        let sql = "SELECT id, range_text FROM age_group_enum ORDER BY id;"
        cachedAgeGroups = try await executeFilterItemQuery(sql)
    }

    private func loadGenders() async throws {
        let sql = "SELECT id, description FROM gender_enum ORDER BY description;"
        cachedGenders = try await executeFilterItemQuery(sql)
    }

    // MARK: - Public Access Methods

    func getAvailableYears() async throws -> [Int] {
        if !isInitialized { try await initializeCache() }
        return cachedYears
    }

    func getAvailableRegions() async throws -> [FilterItem] {
        if !isInitialized { try await initializeCache() }
        return cachedRegions
    }

    func getAvailableMRCs() async throws -> [FilterItem] {
        if !isInitialized { try await initializeCache() }
        return cachedMRCs
    }

    func getAvailableMunicipalities() async throws -> [FilterItem] {
        if !isInitialized { try await initializeCache() }
        return cachedMunicipalities
    }

    func getAvailableClassifications() async throws -> [FilterItem] {
        if !isInitialized { try await initializeCache() }
        return cachedClassifications
    }

    func getAvailableMakes() async throws -> [FilterItem] {
        if !isInitialized { try await initializeCache() }
        return cachedMakes
    }

    func getAvailableModels() async throws -> [FilterItem] {
        if !isInitialized { try await initializeCache() }
        return cachedModels
    }

    func getAvailableColors() async throws -> [FilterItem] {
        if !isInitialized { try await initializeCache() }
        return cachedColors
    }

    func getAvailableFuelTypes() async throws -> [FilterItem] {
        if !isInitialized { try await initializeCache() }
        return cachedFuelTypes
    }

    func getAvailableLicenseTypes() async throws -> [FilterItem] {
        if !isInitialized { try await initializeCache() }
        return cachedLicenseTypes
    }

    func getAvailableAgeGroups() async throws -> [FilterItem] {
        if !isInitialized { try await initializeCache() }
        return cachedAgeGroups
    }

    func getAvailableGenders() async throws -> [FilterItem] {
        if !isInitialized { try await initializeCache() }
        return cachedGenders
    }

    // MARK: - Helper Methods

    private func executeIntQuery(_ sql: String) async throws -> [Int] {
        guard let db = self.db else { throw DatabaseError.notConnected }

        return try await withCheckedThrowingContinuation { continuation in
            var results: [Int] = []
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let value = Int(sqlite3_column_int(stmt, 0))
                    results.append(value)
                }
                continuation.resume(returning: results)
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to load integers: \(error)"))
            }
        }
    }

    private func executeFilterItemQuery(_ sql: String) async throws -> [FilterItem] {
        guard let db = self.db else { throw DatabaseError.notConnected }

        return try await withCheckedThrowingContinuation { continuation in
            var results: [FilterItem] = []
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let displayName = String(cString: sqlite3_column_text(stmt, 1))
                    results.append(FilterItem(id: id, displayName: displayName))
                }
                continuation.resume(returning: results)
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to load filter items: \(error)"))
            }
        }
    }

    // MARK: - Cache Invalidation

    func invalidateCache() {
        isInitialized = false
        cachedYears.removeAll()
        cachedRegions.removeAll()
        cachedMRCs.removeAll()
        cachedMunicipalities.removeAll()
        cachedClassifications.removeAll()
        cachedMakes.removeAll()
        cachedModels.removeAll()
        cachedColors.removeAll()
        cachedFuelTypes.removeAll()
        cachedLicenseTypes.removeAll()
        cachedAgeGroups.removeAll()
        cachedGenders.removeAll()
    }
}