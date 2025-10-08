import Foundation
import SQLite3

/// Manages Make/Model regularization mappings and query translation
class RegularizationManager {
    private weak var databaseManager: DatabaseManager?
    private var db: OpaquePointer? { databaseManager?.db }

    /// Cached year configuration
    private var yearConfig = RegularizationYearConfiguration.defaultConfiguration()

    /// Cached canonical hierarchy
    private var cachedHierarchy: MakeModelHierarchy?

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    // MARK: - Schema Creation

    /// Creates the regularization mapping table
    func createRegularizationTable() async throws {
        guard let db = db else { throw DatabaseError.notConnected }

        let sql = """
        CREATE TABLE IF NOT EXISTS make_model_regularization (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uncurated_make_id INTEGER NOT NULL,
            uncurated_model_id INTEGER NOT NULL,
            canonical_make_id INTEGER NOT NULL,
            canonical_model_id INTEGER NOT NULL,
            fuel_type_id INTEGER,
            vehicle_type_id INTEGER,
            record_count INTEGER NOT NULL DEFAULT 0,
            year_range_start INTEGER NOT NULL,
            year_range_end INTEGER NOT NULL,
            created_date TEXT NOT NULL,
            FOREIGN KEY (uncurated_make_id) REFERENCES make_enum(id),
            FOREIGN KEY (uncurated_model_id) REFERENCES model_enum(id),
            FOREIGN KEY (canonical_make_id) REFERENCES make_enum(id),
            FOREIGN KEY (canonical_model_id) REFERENCES model_enum(id),
            FOREIGN KEY (fuel_type_id) REFERENCES fuel_type_enum(id),
            FOREIGN KEY (vehicle_type_id) REFERENCES classification_enum(id),
            UNIQUE(uncurated_make_id, uncurated_model_id)
        );

        CREATE INDEX IF NOT EXISTS idx_regularization_uncurated
            ON make_model_regularization(uncurated_make_id, uncurated_model_id);

        CREATE INDEX IF NOT EXISTS idx_regularization_canonical
            ON make_model_regularization(canonical_make_id, canonical_model_id);
        """

        var errorMsg: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorMsg) }

        if sqlite3_exec(db, sql, nil, nil, &errorMsg) != SQLITE_OK {
            let error = errorMsg != nil ? String(cString: errorMsg!) : "Unknown error"
            throw DatabaseError.queryFailed("Failed to create regularization table: \(error)")
        }

        print("✅ Created make_model_regularization table")
    }

    // MARK: - Year Configuration

    /// Updates the year configuration
    func setYearConfiguration(_ config: RegularizationYearConfiguration) {
        self.yearConfig = config
        // Invalidate cached hierarchy when year configuration changes
        self.cachedHierarchy = nil
        print("📅 Updated regularization year configuration:")
        print("   Curated: \(config.curatedYearRange)")
        print("   Uncurated: \(config.uncuratedYearRange)")
    }

    /// Gets the current year configuration
    func getYearConfiguration() -> RegularizationYearConfiguration {
        return yearConfig
    }

    // MARK: - Canonical Hierarchy Generation

    /// Generates the hierarchical structure of canonical Make/Model/FuelType/VehicleType combinations
    func generateCanonicalHierarchy(forceRefresh: Bool = false) async throws -> MakeModelHierarchy {
        // Return cached hierarchy if available
        if !forceRefresh, let cached = cachedHierarchy {
            print("📦 Returning cached canonical hierarchy")
            return cached
        }

        guard let db = db else { throw DatabaseError.notConnected }

        let curatedYearsList = Array(yearConfig.curatedYears).sorted()
        guard !curatedYearsList.isEmpty else {
            throw DatabaseError.queryFailed("No curated years configured")
        }

        print("🔄 Generating canonical hierarchy from \(curatedYearsList.count) curated years: \(curatedYearsList)")

        // Build IN clause for curated years
        let yearPlaceholders = curatedYearsList.map { _ in "?" }.joined(separator: ",")

        // Query to get all Make/Model/FuelType/VehicleType combinations from curated years
        let sql = """
        SELECT
            mk.id as make_id,
            mk.name as make_name,
            md.id as model_id,
            md.name as model_name,
            ft.id as fuel_type_id,
            ft.code as fuel_type_code,
            ft.description as fuel_type_description,
            cl.id as vehicle_type_id,
            cl.code as vehicle_type_code,
            cl.description as vehicle_type_description,
            COUNT(*) as record_count
        FROM vehicles v
        JOIN year_enum y ON v.year_id = y.id
        JOIN make_enum mk ON v.make_id = mk.id
        JOIN model_enum md ON v.model_id = md.id
        LEFT JOIN fuel_type_enum ft ON v.fuel_type_id = ft.id
        LEFT JOIN classification_enum cl ON v.classification_id = cl.id
        WHERE y.year IN (\(yearPlaceholders))
        GROUP BY mk.id, md.id, ft.id, cl.id
        ORDER BY mk.name, md.name, ft.description, cl.code;
        """

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                // Bind all curated years
                for (index, year) in curatedYearsList.enumerated() {
                    sqlite3_bind_int(stmt, Int32(index + 1), Int32(year))
                }

                // Temporary storage for building hierarchy
                var makesDict: [Int: (name: String, models: [Int: (name: String, fuelTypes: [MakeModelHierarchy.FuelTypeInfo], vehicleTypes: [MakeModelHierarchy.VehicleTypeInfo])])] = [:]

                while sqlite3_step(stmt) == SQLITE_ROW {
                    let makeId = Int(sqlite3_column_int(stmt, 0))
                    let makeName = String(cString: sqlite3_column_text(stmt, 1))
                    let modelId = Int(sqlite3_column_int(stmt, 2))
                    let modelName = String(cString: sqlite3_column_text(stmt, 3))

                    let fuelTypeId: Int? = sqlite3_column_type(stmt, 4) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 4)) : nil
                    let fuelTypeCode: String? = sqlite3_column_type(stmt, 5) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 5)) : nil
                    let fuelTypeDesc: String? = sqlite3_column_type(stmt, 6) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 6)) : nil

                    let vehicleTypeId: Int? = sqlite3_column_type(stmt, 7) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 7)) : nil
                    let vehicleTypeCode: String? = sqlite3_column_type(stmt, 8) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 8)) : nil
                    let vehicleTypeDesc: String? = sqlite3_column_type(stmt, 9) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 9)) : nil

                    let recordCount = Int(sqlite3_column_int(stmt, 10))

                    // Initialize make if needed
                    if makesDict[makeId] == nil {
                        makesDict[makeId] = (name: makeName, models: [:])
                    }

                    // Initialize model if needed
                    if makesDict[makeId]!.models[modelId] == nil {
                        makesDict[makeId]!.models[modelId] = (name: modelName, fuelTypes: [], vehicleTypes: [])
                    }

                    // Add fuel type if present and not already added
                    if let ftId = fuelTypeId, let ftCode = fuelTypeCode, let ftDesc = fuelTypeDesc {
                        let fuelTypeInfo = MakeModelHierarchy.FuelTypeInfo(
                            id: ftId,
                            code: ftCode,
                            description: ftDesc,
                            recordCount: recordCount
                        )
                        if !makesDict[makeId]!.models[modelId]!.fuelTypes.contains(where: { $0.id == ftId }) {
                            makesDict[makeId]!.models[modelId]!.fuelTypes.append(fuelTypeInfo)
                        }
                    }

                    // Add vehicle type if present and not already added
                    if let vtId = vehicleTypeId, let vtCode = vehicleTypeCode, let vtDesc = vehicleTypeDesc {
                        let vehicleTypeInfo = MakeModelHierarchy.VehicleTypeInfo(
                            id: vtId,
                            code: vtCode,
                            description: vtDesc,
                            recordCount: recordCount
                        )
                        if !makesDict[makeId]!.models[modelId]!.vehicleTypes.contains(where: { $0.id == vtId }) {
                            makesDict[makeId]!.models[modelId]!.vehicleTypes.append(vehicleTypeInfo)
                        }
                    }
                }

                // Convert dictionary structure to MakeModelHierarchy
                let makes = makesDict.map { makeId, makeData in
                    let models = makeData.models.map { modelId, modelData in
                        MakeModelHierarchy.Model(
                            id: modelId,
                            name: modelData.name,
                            makeId: makeId,
                            fuelTypes: modelData.fuelTypes.sorted { $0.description < $1.description },
                            vehicleTypes: modelData.vehicleTypes.sorted { $0.code < $1.code }
                        )
                    }.sorted { $0.name < $1.name }

                    return MakeModelHierarchy.Make(
                        id: makeId,
                        name: makeData.name,
                        models: models
                    )
                }.sorted { $0.name < $1.name }

                let hierarchy = MakeModelHierarchy(makes: makes)

                // Cache the hierarchy
                self.cachedHierarchy = hierarchy

                print("✅ Generated canonical hierarchy: \(makes.count) makes, \(makes.reduce(0) { $0 + $1.models.count }) models")

                continuation.resume(returning: hierarchy)
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to generate canonical hierarchy: \(error)"))
            }
        }
    }

    // MARK: - Uncurated Pair Discovery

    /// Identifies Make/Model pairs in uncurated years that don't have exact matches in curated years
    func findUncuratedPairs() async throws -> [UnverifiedMakeModelPair] {
        guard let db = db else { throw DatabaseError.notConnected }

        let curatedYearsList = Array(yearConfig.curatedYears).sorted()
        let uncuratedYearsList = Array(yearConfig.uncuratedYears).sorted()

        guard !uncuratedYearsList.isEmpty else {
            throw DatabaseError.queryFailed("No uncurated years configured")
        }
        guard !curatedYearsList.isEmpty else {
            throw DatabaseError.queryFailed("No curated years configured")
        }

        print("🔍 Finding uncurated Make/Model pairs in \(uncuratedYearsList.count) uncurated years: \(uncuratedYearsList)")

        // Build IN clauses
        let uncuratedPlaceholders = uncuratedYearsList.map { _ in "?" }.joined(separator: ",")
        let curatedPlaceholders = curatedYearsList.map { _ in "?" }.joined(separator: ",")

        // Query to find Make/Model pairs in uncurated years that don't exist in curated years
        let sql = """
        WITH uncurated_pairs AS (
            SELECT DISTINCT
                v.make_id,
                v.model_id,
                mk.name as make_name,
                md.name as model_name,
                MIN(y.year) as earliest_year,
                MAX(y.year) as latest_year,
                COUNT(*) as record_count
            FROM vehicles v
            JOIN year_enum y ON v.year_id = y.id
            JOIN make_enum mk ON v.make_id = mk.id
            JOIN model_enum md ON v.model_id = md.id
            WHERE y.year IN (\(uncuratedPlaceholders))
            GROUP BY v.make_id, v.model_id
        ),
        curated_pairs AS (
            SELECT DISTINCT
                v.make_id,
                v.model_id
            FROM vehicles v
            JOIN year_enum y ON v.year_id = y.id
            WHERE y.year IN (\(curatedPlaceholders))
        ),
        total_records AS (
            SELECT COUNT(*) as total
            FROM vehicles v
            JOIN year_enum y ON v.year_id = y.id
            WHERE y.year IN (\(uncuratedPlaceholders))
        )
        SELECT
            u.make_id,
            u.model_id,
            u.make_name,
            u.model_name,
            u.earliest_year,
            u.latest_year,
            u.record_count,
            CAST(u.record_count AS REAL) / CAST(t.total AS REAL) * 100.0 as percentage
        FROM uncurated_pairs u
        LEFT JOIN curated_pairs c ON u.make_id = c.make_id AND u.model_id = c.model_id
        CROSS JOIN total_records t
        WHERE c.make_id IS NULL
        ORDER BY u.record_count DESC;
        """

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                var bindIndex: Int32 = 1

                // Bind uncurated years (first occurrence)
                for year in uncuratedYearsList {
                    sqlite3_bind_int(stmt, bindIndex, Int32(year))
                    bindIndex += 1
                }

                // Bind curated years
                for year in curatedYearsList {
                    sqlite3_bind_int(stmt, bindIndex, Int32(year))
                    bindIndex += 1
                }

                // Bind uncurated years (second occurrence for total)
                for year in uncuratedYearsList {
                    sqlite3_bind_int(stmt, bindIndex, Int32(year))
                    bindIndex += 1
                }

                var pairs: [UnverifiedMakeModelPair] = []

                while sqlite3_step(stmt) == SQLITE_ROW {
                    let makeId = Int(sqlite3_column_int(stmt, 0))
                    let modelId = Int(sqlite3_column_int(stmt, 1))
                    let makeName = String(cString: sqlite3_column_text(stmt, 2))
                    let modelName = String(cString: sqlite3_column_text(stmt, 3))
                    let earliestYear = Int(sqlite3_column_int(stmt, 4))
                    let latestYear = Int(sqlite3_column_int(stmt, 5))
                    let recordCount = Int(sqlite3_column_int(stmt, 6))
                    let percentage = sqlite3_column_double(stmt, 7)

                    let pair = UnverifiedMakeModelPair(
                        id: "\(makeId)_\(modelId)",
                        makeId: makeId,
                        modelId: modelId,
                        makeName: makeName,
                        modelName: modelName,
                        recordCount: recordCount,
                        percentageOfTotal: percentage,
                        earliestYear: earliestYear,
                        latestYear: latestYear
                    )
                    pairs.append(pair)
                }

                print("✅ Found \(pairs.count) uncurated Make/Model pairs")
                if pairs.count > 0 {
                    let topPairs = pairs.prefix(5)
                    print("   Top 5 by record count:")
                    for pair in topPairs {
                        print("   - \(pair.makeModelDisplay): \(pair.recordCount) records (\(String(format: "%.2f", pair.percentageOfTotal))%)")
                    }
                }

                continuation.resume(returning: pairs)
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to find uncurated pairs: \(error)"))
            }
        }
    }

    // MARK: - Mapping Management

    /// Saves a regularization mapping to the database
    /// One mapping per uncurated Make/Model pair
    /// FuelType and VehicleType are optional (NULL if user cannot disambiguate)
    func saveMapping(
        uncuratedMakeId: Int,
        uncuratedModelId: Int,
        canonicalMakeId: Int,
        canonicalModelId: Int,
        fuelTypeId: Int?,
        vehicleTypeId: Int?
    ) async throws {
        guard let db = db else { throw DatabaseError.notConnected }

        // Calculate record count for this mapping
        let recordCount = try await calculateRecordCount(
            makeId: uncuratedMakeId,
            modelId: uncuratedModelId
        )

        let sql = """
        INSERT OR REPLACE INTO make_model_regularization
            (uncurated_make_id, uncurated_model_id, canonical_make_id, canonical_model_id,
             fuel_type_id, vehicle_type_id, record_count, year_range_start, year_range_end, created_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(uncuratedMakeId))
                sqlite3_bind_int(stmt, 2, Int32(uncuratedModelId))
                sqlite3_bind_int(stmt, 3, Int32(canonicalMakeId))
                sqlite3_bind_int(stmt, 4, Int32(canonicalModelId))

                if let ftId = fuelTypeId {
                    sqlite3_bind_int(stmt, 5, Int32(ftId))
                } else {
                    sqlite3_bind_null(stmt, 5)
                }

                if let vtId = vehicleTypeId {
                    sqlite3_bind_int(stmt, 6, Int32(vtId))
                } else {
                    sqlite3_bind_null(stmt, 6)
                }

                sqlite3_bind_int(stmt, 7, Int32(recordCount))

                // Store min/max uncurated years
                let uncuratedYears = Array(yearConfig.uncuratedYears).sorted()
                let minYear = uncuratedYears.first ?? 2023
                let maxYear = uncuratedYears.last ?? 2024
                sqlite3_bind_int(stmt, 8, Int32(minYear))
                sqlite3_bind_int(stmt, 9, Int32(maxYear))

                let dateFormatter = ISO8601DateFormatter()
                let dateString = dateFormatter.string(from: Date())
                sqlite3_bind_text(stmt, 10, dateString, -1, nil)

                if sqlite3_step(stmt) == SQLITE_DONE {
                    print("✅ Saved regularization mapping: Make \(uncuratedMakeId)/Model \(uncuratedModelId) → Make \(canonicalMakeId)/Model \(canonicalModelId)")
                    print("   FuelType: \(fuelTypeId?.description ?? "NULL"), VehicleType: \(vehicleTypeId?.description ?? "NULL")")
                    continuation.resume()
                } else {
                    let error = String(cString: sqlite3_errmsg(db))
                    continuation.resume(throwing: DatabaseError.queryFailed("Failed to save mapping: \(error)"))
                }
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to prepare save mapping: \(error)"))
            }
        }
    }

    /// Deletes a regularization mapping
    func deleteMapping(id: Int) async throws {
        guard let db = db else { throw DatabaseError.notConnected }

        let sql = "DELETE FROM make_model_regularization WHERE id = ?;"

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(id))

                if sqlite3_step(stmt) == SQLITE_DONE {
                    print("✅ Deleted regularization mapping ID \(id)")
                    continuation.resume()
                } else {
                    let error = String(cString: sqlite3_errmsg(db))
                    continuation.resume(throwing: DatabaseError.queryFailed("Failed to delete mapping: \(error)"))
                }
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to prepare delete mapping: \(error)"))
            }
        }
    }

    /// Gets all regularization mappings
    func getAllMappings() async throws -> [RegularizationMapping] {
        guard let db = db else { throw DatabaseError.notConnected }

        let sql = """
        SELECT
            r.id,
            um.name as uncurated_make,
            umd.name as uncurated_model,
            cm.name as canonical_make,
            cmd.name as canonical_model,
            ft.description as fuel_type,
            cl.code as vehicle_type,
            r.record_count,
            r.year_range_start,
            r.year_range_end
        FROM make_model_regularization r
        JOIN make_enum um ON r.uncurated_make_id = um.id
        JOIN model_enum umd ON r.uncurated_model_id = umd.id
        JOIN make_enum cm ON r.canonical_make_id = cm.id
        JOIN model_enum cmd ON r.canonical_model_id = cmd.id
        LEFT JOIN fuel_type_enum ft ON r.fuel_type_id = ft.id
        LEFT JOIN classification_enum cl ON r.vehicle_type_id = cl.id
        ORDER BY r.record_count DESC;
        """

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                var mappings: [RegularizationMapping] = []
                var totalRecords = 0

                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let uncuratedMake = String(cString: sqlite3_column_text(stmt, 1))
                    let uncuratedModel = String(cString: sqlite3_column_text(stmt, 2))
                    let canonicalMake = String(cString: sqlite3_column_text(stmt, 3))
                    let canonicalModel = String(cString: sqlite3_column_text(stmt, 4))

                    let fuelType: String? = sqlite3_column_type(stmt, 5) != SQLITE_NULL
                        ? String(cString: sqlite3_column_text(stmt, 5)) : nil
                    let vehicleType: String? = sqlite3_column_type(stmt, 6) != SQLITE_NULL
                        ? String(cString: sqlite3_column_text(stmt, 6)) : nil

                    let recordCount = Int(sqlite3_column_int(stmt, 7))
                    totalRecords += recordCount

                    let yearStart = Int(sqlite3_column_int(stmt, 8))
                    let yearEnd = Int(sqlite3_column_int(stmt, 9))
                    let yearRange = "\(yearStart)-\(yearEnd)"

                    let mapping = RegularizationMapping(
                        id: id,
                        unverifiedMake: uncuratedMake,
                        unverifiedModel: uncuratedModel,
                        canonicalMake: canonicalMake,
                        canonicalModel: canonicalModel,
                        fuelType: fuelType,
                        vehicleType: vehicleType,
                        recordCount: recordCount,
                        percentageOfTotal: 0.0, // Will calculate after we have total
                        yearRange: yearRange
                    )
                    mappings.append(mapping)
                }

                // Calculate percentages
                if totalRecords > 0 {
                    mappings = mappings.map { mapping in
                        RegularizationMapping(
                            id: mapping.id,
                            unverifiedMake: mapping.unverifiedMake,
                            unverifiedModel: mapping.unverifiedModel,
                            canonicalMake: mapping.canonicalMake,
                            canonicalModel: mapping.canonicalModel,
                            fuelType: mapping.fuelType,
                            vehicleType: mapping.vehicleType,
                            recordCount: mapping.recordCount,
                            percentageOfTotal: Double(mapping.recordCount) / Double(totalRecords) * 100.0,
                            yearRange: mapping.yearRange
                        )
                    }
                }

                continuation.resume(returning: mappings)
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to get mappings: \(error)"))
            }
        }
    }

    /// Gets regularization statistics
    func getRegularizationStatistics() async throws -> (mappingCount: Int, coveredRecords: Int, totalRecords: Int) {
        guard let db = db else { throw DatabaseError.notConnected }

        let uncuratedYearsList = Array(yearConfig.uncuratedYears).sorted()
        guard !uncuratedYearsList.isEmpty else {
            return (0, 0, 0)
        }

        let uncuratedPlaceholders = uncuratedYearsList.map { _ in "?" }.joined(separator: ",")

        let sql = """
        SELECT
            COUNT(*) as mapping_count,
            COALESCE(SUM(record_count), 0) as covered_records,
            (SELECT COUNT(*) FROM vehicles v
             JOIN year_enum y ON v.year_id = y.id
             WHERE y.year IN (\(uncuratedPlaceholders))) as total_records
        FROM make_model_regularization;
        """

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                // Bind uncurated years
                for (index, year) in uncuratedYearsList.enumerated() {
                    sqlite3_bind_int(stmt, Int32(index + 1), Int32(year))
                }

                if sqlite3_step(stmt) == SQLITE_ROW {
                    let mappingCount = Int(sqlite3_column_int(stmt, 0))
                    let coveredRecords = Int(sqlite3_column_int(stmt, 1))
                    let totalRecords = Int(sqlite3_column_int(stmt, 2))

                    continuation.resume(returning: (mappingCount, coveredRecords, totalRecords))
                } else {
                    continuation.resume(returning: (0, 0, 0))
                }
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to get statistics: \(error)"))
            }
        }
    }

    // MARK: - Query Translation

    /// Expands a set of make/model IDs to include all regularized variants
    /// When regularization is enabled, this translates canonical IDs back to all uncurated variants
    func expandMakeModelIDs(
        makeIds: [Int],
        modelIds: [Int]
    ) async throws -> (makeIds: [Int], modelIds: [Int]) {
        guard let db = db else { throw DatabaseError.notConnected }
        guard !makeIds.isEmpty || !modelIds.isEmpty else {
            return (makeIds, modelIds)
        }

        // Start with original IDs
        var expandedMakeIds = Set(makeIds)
        var expandedModelIds = Set(modelIds)

        // Query regularization table for mappings where canonical IDs match
        let sql = """
        SELECT DISTINCT uncurated_make_id, uncurated_model_id
        FROM make_model_regularization
        WHERE canonical_make_id IN (\(makeIds.map { String($0) }.joined(separator: ",")))
           OR canonical_model_id IN (\(modelIds.map { String($0) }.joined(separator: ",")));
        """

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let uncuratedMakeId = Int(sqlite3_column_int(stmt, 0))
                    let uncuratedModelId = Int(sqlite3_column_int(stmt, 1))

                    expandedMakeIds.insert(uncuratedMakeId)
                    expandedModelIds.insert(uncuratedModelId)
                }

                let makeArray = Array(expandedMakeIds).sorted()
                let modelArray = Array(expandedModelIds).sorted()

                if makeArray.count > makeIds.count || modelArray.count > modelIds.count {
                    print("🔄 Regularization expanded IDs:")
                    print("   Makes: \(makeIds.count) → \(makeArray.count)")
                    print("   Models: \(modelIds.count) → \(modelArray.count)")
                }

                continuation.resume(returning: (makeArray, modelArray))
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to expand IDs: \(error)"))
            }
        }
    }

    // MARK: - Helper Methods

    /// Calculates the number of records for an uncurated Make/Model pair in uncurated years
    private func calculateRecordCount(
        makeId: Int,
        modelId: Int
    ) async throws -> Int {
        guard let db = db else { throw DatabaseError.notConnected }

        let uncuratedYearsList = Array(yearConfig.uncuratedYears).sorted()
        guard !uncuratedYearsList.isEmpty else {
            return 0
        }

        let uncuratedPlaceholders = uncuratedYearsList.map { _ in "?" }.joined(separator: ",")

        let sql = """
        SELECT COUNT(*)
        FROM vehicles v
        JOIN year_enum y ON v.year_id = y.id
        WHERE v.make_id = ? AND v.model_id = ?
        AND y.year IN (\(uncuratedPlaceholders));
        """

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(makeId))
                sqlite3_bind_int(stmt, 2, Int32(modelId))

                // Bind uncurated years
                for (index, year) in uncuratedYearsList.enumerated() {
                    sqlite3_bind_int(stmt, Int32(index + 3), Int32(year))
                }

                if sqlite3_step(stmt) == SQLITE_ROW {
                    let count = Int(sqlite3_column_int(stmt, 0))
                    continuation.resume(returning: count)
                } else {
                    continuation.resume(returning: 0)
                }
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to calculate record count: \(error)"))
            }
        }
    }
}
