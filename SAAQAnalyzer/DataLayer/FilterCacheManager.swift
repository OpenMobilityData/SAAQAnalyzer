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
    private var cachedVehicleClasses: [FilterItem] = []
    private var cachedVehicleTypes: [FilterItem] = []
    private var cachedMakes: [FilterItem] = []
    private var cachedModels: [FilterItem] = []
    private var cachedColors: [FilterItem] = []
    private var cachedFuelTypes: [FilterItem] = []
    private var cachedLicenseTypes: [FilterItem] = []
    private var cachedAgeGroups: [FilterItem] = []
    private var cachedGenders: [FilterItem] = []

    private var isInitialized = false

    // Regularization display info: maps "makeId_modelId" to (canonicalMake, canonicalModel, recordCount)
    private var regularizationInfo: [String: (canonicalMake: String, canonicalModel: String, recordCount: Int)] = [:]

    // Uncurated Make/Model pairs: maps "makeId_modelId" to record count in uncurated years
    private var uncuratedPairs: [String: Int] = [:]

    // Make regularization info: maps "makeId" to (canonicalMake, recordCount) - derived from Make/Model mappings
    private var makeRegularizationInfo: [String: (canonicalMake: String, recordCount: Int)] = [:]

    // Uncurated Makes: maps "makeId" to record count in uncurated years (only Makes that exist ONLY in uncurated years)
    private var uncuratedMakes: [String: Int] = [:]

    // Model to Make mapping: maps modelId to makeId (for hierarchical filtering)
    private var modelToMakeMapping: [Int: Int] = [:]

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    // MARK: - Cache Loading

    /// Initialize all filter caches from enumeration tables
    func initializeCache() async throws {
        try await initializeCache(for: nil)  // Load all caches
    }

    /// Initialize filter caches for a specific data type only
    func initializeCache(for dataType: DataEntityType?) async throws {
        guard !isInitialized else { return }

        print("🔄 Loading filter cache from enumeration tables...")

        // Shared enum tables loaded for all types
        try await loadYears()
        try await loadRegions()
        try await loadMRCs()
        try await loadMunicipalities()

        // Load type-specific enum tables
        if dataType == nil || dataType == .vehicle {
            // Vehicle-specific: expensive regularization queries and large Make/Model tables
            try await loadRegularizationInfo()
            try await loadUncuratedPairs()
            try await loadMakeRegularizationInfo()
            try await loadUncuratedMakes()
            try await loadVehicleClasses()
            try await loadVehicleTypes()
            try await loadMakes()
            try await loadModels()
            try await loadColors()
            try await loadFuelTypes()
            print("✅ Loaded vehicle-specific enum caches")
        }

        if dataType == nil || dataType == .license {
            // License-specific: lightweight enum tables
            try await loadLicenseTypes()
            try await loadAgeGroups()
            try await loadGenders()
            print("✅ Loaded license-specific enum caches")
        }

        isInitialized = true
        print("✅ Filter cache initialized with enumeration data")
    }

    // MARK: - Individual Cache Loaders

    private func loadRegularizationInfo() async throws {
        guard let regularizationManager = databaseManager?.regularizationManager else {
            print("⚠️ RegularizationManager not available - skipping regularization info")
            regularizationInfo = [:]
            return
        }

        do {
            regularizationInfo = try await regularizationManager.getRegularizationDisplayInfo()
            print("✅ Loaded regularization info for \(regularizationInfo.count) Make/Model pairs")
        } catch {
            print("⚠️ Could not load regularization info: \(error)")
            regularizationInfo = [:]
        }
    }

    private func loadUncuratedPairs() async throws {
        guard let db = self.db,
              let regularizationManager = databaseManager?.regularizationManager else {
            print("⚠️ Cannot load uncurated pairs - database or RegularizationManager not available")
            uncuratedPairs = [:]
            return
        }

        let yearConfig = regularizationManager.getYearConfiguration()
        let uncuratedYearsList = Array(yearConfig.uncuratedYears).sorted()

        guard !uncuratedYearsList.isEmpty else {
            print("⚠️ No uncurated years configured")
            uncuratedPairs = [:]
            return
        }

        let uncuratedPlaceholders = uncuratedYearsList.map { _ in "?" }.joined(separator: ",")

        let sql = """
        SELECT v.make_id, v.model_id, COUNT(*) as record_count
        FROM vehicles v
        JOIN year_enum y ON v.year_id = y.id
        WHERE y.year IN (\(uncuratedPlaceholders))
        GROUP BY v.make_id, v.model_id;
        """

        uncuratedPairs = try await withCheckedThrowingContinuation { continuation in
            var results: [String: Int] = [:]
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                // Bind uncurated years
                for (index, year) in uncuratedYearsList.enumerated() {
                    sqlite3_bind_int(stmt, Int32(index + 1), Int32(year))
                }

                while sqlite3_step(stmt) == SQLITE_ROW {
                    let makeId = Int(sqlite3_column_int(stmt, 0))
                    let modelId = Int(sqlite3_column_int(stmt, 1))
                    let recordCount = Int(sqlite3_column_int(stmt, 2))

                    let key = "\(makeId)_\(modelId)"
                    results[key] = recordCount
                }
                continuation.resume(returning: results)
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                print("⚠️ Could not load uncurated pairs: \(error)")
                continuation.resume(returning: [:])
            }
        }

        print("✅ Loaded \(uncuratedPairs.count) uncurated Make/Model pairs")

        // Debug: Show first 5 keys
        if uncuratedPairs.count > 0 {
            print("   First 5 uncurated pair keys:")
            for (index, key) in uncuratedPairs.keys.prefix(5).enumerated() {
                print("   \(index + 1). Key: \(key), Count: \(uncuratedPairs[key] ?? 0)")
            }
        }
    }

    private func loadMakeRegularizationInfo() async throws {
        guard let regularizationManager = databaseManager?.regularizationManager else {
            print("⚠️ RegularizationManager not available - skipping Make regularization info")
            makeRegularizationInfo = [:]
            return
        }

        do {
            makeRegularizationInfo = try await regularizationManager.getMakeRegularizationDisplayInfo()
            if !makeRegularizationInfo.isEmpty {
                print("✅ Loaded derived Make regularization info for \(makeRegularizationInfo.count) Makes")
            }
        } catch {
            print("⚠️ Could not load Make regularization info: \(error)")
            makeRegularizationInfo = [:]
        }
    }

    private func loadUncuratedMakes() async throws {
        guard let db = self.db,
              let regularizationManager = databaseManager?.regularizationManager else {
            print("⚠️ Cannot load uncurated Makes - database or RegularizationManager not available")
            uncuratedMakes = [:]
            return
        }

        let yearConfig = regularizationManager.getYearConfiguration()
        let curatedYearsList = Array(yearConfig.curatedYears).sorted()
        let uncuratedYearsList = Array(yearConfig.uncuratedYears).sorted()

        guard !uncuratedYearsList.isEmpty else {
            print("⚠️ No uncurated years configured")
            uncuratedMakes = [:]
            return
        }

        let curatedPlaceholders = curatedYearsList.map { _ in "?" }.joined(separator: ",")
        let uncuratedPlaceholders = uncuratedYearsList.map { _ in "?" }.joined(separator: ",")

        // Find Makes that exist ONLY in uncurated years (not in curated years)
        let sql = """
        SELECT v.make_id, COUNT(*) as record_count
        FROM vehicles v
        JOIN year_enum y ON v.year_id = y.id
        WHERE y.year IN (\(uncuratedPlaceholders))
        AND v.make_id NOT IN (
            SELECT DISTINCT v2.make_id
            FROM vehicles v2
            JOIN year_enum y2 ON v2.year_id = y2.id
            WHERE y2.year IN (\(curatedPlaceholders))
        )
        GROUP BY v.make_id;
        """

        uncuratedMakes = try await withCheckedThrowingContinuation { continuation in
            var results: [String: Int] = [:]
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                var bindIndex: Int32 = 1

                // Bind uncurated years
                for year in uncuratedYearsList {
                    sqlite3_bind_int(stmt, bindIndex, Int32(year))
                    bindIndex += 1
                }

                // Bind curated years
                for year in curatedYearsList {
                    sqlite3_bind_int(stmt, bindIndex, Int32(year))
                    bindIndex += 1
                }

                while sqlite3_step(stmt) == SQLITE_ROW {
                    let makeId = Int(sqlite3_column_int(stmt, 0))
                    let recordCount = Int(sqlite3_column_int(stmt, 1))

                    let key = String(makeId)
                    results[key] = recordCount
                }
                continuation.resume(returning: results)
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                print("⚠️ Could not load uncurated Makes: \(error)")
                continuation.resume(returning: [:])
            }
        }

        if !uncuratedMakes.isEmpty {
            print("✅ Loaded \(uncuratedMakes.count) uncurated Makes (only in uncurated years)")
        }
    }

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

    private func loadVehicleClasses() async throws {
        let sql = "SELECT id, code FROM vehicle_class_enum ORDER BY code;"
        cachedVehicleClasses = try await executeFilterItemQuery(sql)
    }

    private func loadVehicleTypes() async throws {
        let sql = "SELECT id, code FROM vehicle_type_enum ORDER BY code;"
        cachedVehicleTypes = try await executeFilterItemQuery(sql)
    }

    private func loadMakes() async throws {
        guard let db = self.db else { throw DatabaseError.notConnected }

        let sql = "SELECT id, name FROM make_enum ORDER BY name;"

        cachedMakes = try await withCheckedThrowingContinuation { continuation in
            var results: [FilterItem] = []
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let makeId = Int(sqlite3_column_int(stmt, 0))

                    // Safely handle NULL text columns
                    guard let makeNamePtr = sqlite3_column_text(stmt, 1) else {
                        print("⚠️ Skipping Make with NULL name (id: \(makeId))")
                        continue
                    }
                    let makeName = String(cString: makeNamePtr)

                    // Base display name: just the Make name
                    var displayName = makeName

                    let key = String(makeId)

                    // Check if this Make has been regularized (derived from Make/Model mappings)
                    if let regInfo = makeRegularizationInfo[key] {
                        // Only show badge if uncurated name differs from canonical name
                        if makeName != regInfo.canonicalMake {
                            // Regularized: show mapping and record count
                            let formattedCount = NumberFormatter.localizedString(from: NSNumber(value: regInfo.recordCount), number: .decimal)
                            displayName += " → \(regInfo.canonicalMake) (\(formattedCount) records)"
                            print("   🔗 Make regularized: \(makeName) → \(regInfo.canonicalMake)")
                        } else {
                            print("   ℹ️ Make \(makeName) has regularization mapping but name matches canonical - no badge")
                        }
                    } else if let uncuratedCount = uncuratedMakes[key] {
                        // Uncurated but not yet regularized: show record count
                        let formattedCount = NumberFormatter.localizedString(from: NSNumber(value: uncuratedCount), number: .decimal)
                        displayName += " [uncurated: \(formattedCount) records]"
                        print("   🔴 Uncurated Make: \(makeName) - \(formattedCount) records")
                    }
                    // Otherwise: canonical Make from curated years (no badge)

                    results.append(FilterItem(id: makeId, displayName: displayName))
                }
                continuation.resume(returning: results)
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to load makes: \(error)"))
            }
        }
    }

    private func loadModels() async throws {
        guard let db = self.db else { throw DatabaseError.notConnected }

        let sql = """
        SELECT m.id, m.name, mk.id as make_id, mk.name as make_name
        FROM model_enum m
        JOIN make_enum mk ON m.make_id = mk.id
        ORDER BY mk.name, m.name;
        """

        cachedModels = try await withCheckedThrowingContinuation { continuation in
            var results: [FilterItem] = []
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let modelId = Int(sqlite3_column_int(stmt, 0))

                    // Safely handle NULL text columns
                    guard let modelNamePtr = sqlite3_column_text(stmt, 1),
                          let makeNamePtr = sqlite3_column_text(stmt, 3) else {
                        print("⚠️ Skipping Model with NULL name (id: \(modelId))")
                        continue
                    }
                    let modelName = String(cString: modelNamePtr)
                    let makeId = Int(sqlite3_column_int(stmt, 2))
                    let makeName = String(cString: makeNamePtr)

                    // Base display name: "Model (Make)"
                    var displayName = "\(modelName) (\(makeName))"

                    let key = "\(makeId)_\(modelId)"

                    // Check if this Make/Model pair has been regularized
                    if let regInfo = regularizationInfo[key] {
                        // Only show badge if uncurated differs from canonical (Make OR Model)
                        if makeName != regInfo.canonicalMake || modelName != regInfo.canonicalModel {
                            // Regularized: show full canonical Make/Model pair with record count
                            let formattedCount = NumberFormatter.localizedString(from: NSNumber(value: regInfo.recordCount), number: .decimal)
                            displayName += " → \(regInfo.canonicalMake) \(regInfo.canonicalModel) (\(formattedCount) records)"
                            print("   🔗 Regularized: \(modelName) (\(makeName)) → \(regInfo.canonicalMake) \(regInfo.canonicalModel)")
                        } else {
                            print("   ℹ️ Model \(modelName) (\(makeName)) has regularization mapping but names match canonical - no badge")
                        }
                    } else if let uncuratedCount = uncuratedPairs[key] {
                        // Uncurated but not yet regularized: show record count
                        let formattedCount = NumberFormatter.localizedString(from: NSNumber(value: uncuratedCount), number: .decimal)
                        displayName += " [uncurated: \(formattedCount) records]"
                        print("   🔴 Uncurated: \(modelName) (\(makeName)) - \(formattedCount) records")
                    }
                    // Otherwise: canonical pair from curated years (no badge)

                    // Store model-to-make mapping for hierarchical filtering
                    modelToMakeMapping[modelId] = makeId

                    results.append(FilterItem(id: modelId, displayName: displayName))
                }
                continuation.resume(returning: results)
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to load models: \(error)"))
            }
        }
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
        let sql = "SELECT id, code FROM gender_enum ORDER BY code;"
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

    func getAvailableVehicleClasses() async throws -> [FilterItem] {
        if !isInitialized { try await initializeCache() }
        return cachedVehicleClasses
    }

    func getAvailableVehicleTypes() async throws -> [FilterItem] {
        if !isInitialized { try await initializeCache() }
        return cachedVehicleTypes
    }

    func getAvailableMakes(limitToCuratedYears: Bool = false) async throws -> [FilterItem] {
        if !isInitialized { try await initializeCache() }

        // If limiting to curated years, filter out uncurated-only Makes
        if limitToCuratedYears {
            return cachedMakes.filter { make in
                let makeId = String(make.id)
                // Exclude if this Make exists ONLY in uncurated years
                return uncuratedMakes[makeId] == nil
            }
        }

        return cachedMakes
    }

    func getAvailableModels(limitToCuratedYears: Bool = false, forMakeIds: Set<Int>? = nil) async throws -> [FilterItem] {
        if !isInitialized { try await initializeCache() }

        var filteredModels = cachedModels

        // If limiting to curated years, filter out uncurated Make/Model pairs
        if limitToCuratedYears {
            filteredModels = filteredModels.filter { model in
                // Extract makeId and modelId from the cached model
                // The model's ID is the modelId, we need to find its makeId from the display name
                // Format: "Model (Make)" or "Model (Make) [badges...]"

                // Parse makeId from model_enum JOIN - we need to query this differently
                // For now, check if the model has an uncurated badge in its display name
                let displayName = model.displayName

                // If display contains "[uncurated:" badge, it's an uncurated pair
                if displayName.contains("[uncurated:") {
                    return false
                }

                return true
            }
        }

        // If hierarchical filtering requested, filter models by selected makes
        if let makeIds = forMakeIds, !makeIds.isEmpty {
            filteredModels = try await filterModelsByMakes(filteredModels, makeIds: makeIds)
        }

        return filteredModels
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

    // MARK: - Hierarchical Filtering Helper

    /// Filters models by their associated makes
    private func filterModelsByMakes(_ models: [FilterItem], makeIds: Set<Int>) async throws -> [FilterItem] {
        return models.filter { model in
            if let makeId = modelToMakeMapping[model.id] {
                return makeIds.contains(makeId)
            }
            return false
        }
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

                    // Safely handle NULL text columns (can happen with empty enum tables)
                    guard let textPtr = sqlite3_column_text(stmt, 1) else {
                        print("⚠️ Skipping row with NULL display name (id: \(id))")
                        continue
                    }
                    let displayName = String(cString: textPtr)
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
        cachedVehicleClasses.removeAll()
        cachedVehicleTypes.removeAll()
        cachedMakes.removeAll()
        cachedModels.removeAll()
        cachedColors.removeAll()
        cachedFuelTypes.removeAll()
        cachedLicenseTypes.removeAll()
        cachedAgeGroups.removeAll()
        cachedGenders.removeAll()
        regularizationInfo.removeAll()
        uncuratedPairs.removeAll()
        makeRegularizationInfo.removeAll()
        uncuratedMakes.removeAll()
        modelToMakeMapping.removeAll()
    }
}
