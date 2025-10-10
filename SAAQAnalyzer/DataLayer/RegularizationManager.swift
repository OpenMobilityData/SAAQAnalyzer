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

    /// Creates the regularization mapping table (triplet-based: Make/Model/ModelYear)
    func createRegularizationTable() async throws {
        guard let db = db else { throw DatabaseError.notConnected }

        let sql = """
        CREATE TABLE IF NOT EXISTS make_model_regularization (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uncurated_make_id INTEGER NOT NULL,
            uncurated_model_id INTEGER NOT NULL,
            model_year_id INTEGER,
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
            FOREIGN KEY (model_year_id) REFERENCES model_year_enum(id),
            FOREIGN KEY (canonical_make_id) REFERENCES make_enum(id),
            FOREIGN KEY (canonical_model_id) REFERENCES model_enum(id),
            FOREIGN KEY (fuel_type_id) REFERENCES fuel_type_enum(id),
            FOREIGN KEY (vehicle_type_id) REFERENCES vehicle_type_enum(id),
            UNIQUE(uncurated_make_id, uncurated_model_id, model_year_id)
        );

        CREATE INDEX IF NOT EXISTS idx_regularization_uncurated_triplet
            ON make_model_regularization(uncurated_make_id, uncurated_model_id, model_year_id);

        CREATE INDEX IF NOT EXISTS idx_regularization_canonical
            ON make_model_regularization(canonical_make_id, canonical_model_id);
        """

        var errorMsg: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorMsg) }

        if sqlite3_exec(db, sql, nil, nil, &errorMsg) != SQLITE_OK {
            let error = errorMsg != nil ? String(cString: errorMsg!) : "Unknown error"
            throw DatabaseError.queryFailed("Failed to create regularization table: \(error)")
        }

        print("✅ Created make_model_regularization table (triplet-based)")
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

    /// Generates the hierarchical structure of canonical Make/Model/FuelType/VehicleClass combinations
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

        // First, generate the base hierarchy from curated data

        // Query to get all Make/Model/ModelYear/FuelType/VehicleType combinations from curated years
        // ModelYear dimension added for FuelType grouping (enables year-specific fuel type disambiguation)
        let sql = """
        SELECT
            mk.id as make_id,
            mk.name as make_name,
            md.id as model_id,
            md.name as model_name,
            my.id as model_year_id,
            my.year as model_year,
            ft.id as fuel_type_id,
            ft.code as fuel_type_code,
            ft.description as fuel_type_description,
            vt.id as vehicle_type_id,
            vt.code as vehicle_type_code,
            vt.description as vehicle_type_description,
            COUNT(*) as record_count
        FROM vehicles v
        JOIN year_enum y ON v.year_id = y.id
        JOIN make_enum mk ON v.make_id = mk.id
        JOIN model_enum md ON v.model_id = md.id
        LEFT JOIN model_year_enum my ON v.model_year_id = my.id
        LEFT JOIN fuel_type_enum ft ON v.fuel_type_id = ft.id
        LEFT JOIN vehicle_type_enum vt ON v.vehicle_type_id = vt.id
        WHERE y.year IN (\(yearPlaceholders))
        GROUP BY mk.id, md.id, my.id, ft.id, vt.id
        ORDER BY mk.name, md.name, my.year, ft.description, vt.code;
        """

        let baseHierarchy = try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                // Bind all curated years
                for (index, year) in curatedYearsList.enumerated() {
                    sqlite3_bind_int(stmt, Int32(index + 1), Int32(year))
                }

                // Temporary storage for building hierarchy (now includes ModelYear dimension)
                // Structure: makeId → modelId → modelYearId → (fuelTypes, vehicleTypes)
                var makesDict: [Int: (name: String, models: [Int: (name: String, modelYearFuelTypes: [Int?: [MakeModelHierarchy.FuelTypeInfo]], vehicleTypes: [MakeModelHierarchy.VehicleTypeInfo])])] = [:]

                while sqlite3_step(stmt) == SQLITE_ROW {
                    let makeId = Int(sqlite3_column_int(stmt, 0))
                    let makeName = String(cString: sqlite3_column_text(stmt, 1))
                    let modelId = Int(sqlite3_column_int(stmt, 2))
                    let modelName = String(cString: sqlite3_column_text(stmt, 3))

                    let modelYearId: Int? = sqlite3_column_type(stmt, 4) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 4)) : nil
                    let modelYear: Int? = sqlite3_column_type(stmt, 5) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 5)) : nil

                    let fuelTypeId: Int? = sqlite3_column_type(stmt, 6) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 6)) : nil
                    let fuelTypeCode: String? = sqlite3_column_type(stmt, 7) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 7)) : nil
                    let fuelTypeDesc: String? = sqlite3_column_type(stmt, 8) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 8)) : nil

                    let vehicleTypeId: Int? = sqlite3_column_type(stmt, 9) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 9)) : nil
                    let vehicleTypeCode: String? = sqlite3_column_type(stmt, 10) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 10)) : nil
                    let vehicleTypeDesc: String? = sqlite3_column_type(stmt, 11) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 11)) : nil

                    let recordCount = Int(sqlite3_column_int(stmt, 12))

                    // Initialize make if needed
                    if makesDict[makeId] == nil {
                        makesDict[makeId] = (name: makeName, models: [:])
                    }

                    // Initialize model if needed
                    if makesDict[makeId]!.models[modelId] == nil {
                        makesDict[makeId]!.models[modelId] = (name: modelName, modelYearFuelTypes: [:], vehicleTypes: [])
                    }

                    // Initialize model year entry (always, even if fuel type is NULL)
                    // This ensures pre-2017 model years (with NULL fuel_type) appear in the hierarchy
                    if makesDict[makeId]!.models[modelId]!.modelYearFuelTypes[modelYearId] == nil {
                        makesDict[makeId]!.models[modelId]!.modelYearFuelTypes[modelYearId] = []
                    }

                    // Add fuel type (grouped by model year) only if present
                    if let ftId = fuelTypeId, let ftCode = fuelTypeCode, let ftDesc = fuelTypeDesc {
                        let fuelTypeInfo = MakeModelHierarchy.FuelTypeInfo(
                            id: ftId,
                            code: ftCode,
                            description: ftDesc,
                            recordCount: recordCount,
                            modelYearId: modelYearId,
                            modelYear: modelYear
                        )

                        // Add fuel type if not already present for this model year
                        if !makesDict[makeId]!.models[modelId]!.modelYearFuelTypes[modelYearId]!.contains(where: { $0.id == ftId }) {
                            makesDict[makeId]!.models[modelId]!.modelYearFuelTypes[modelYearId]!.append(fuelTypeInfo)
                        }
                    } else if let myId = modelYearId, let myYear = modelYear {
                        // Fuel type is NULL (pre-2017 data) - add a placeholder to preserve model year information
                        // Use a negative ID to indicate this is a placeholder (won't conflict with real IDs)
                        // This ensures UI sorting/display works correctly for empty fuel type arrays
                        let placeholderInfo = MakeModelHierarchy.FuelTypeInfo(
                            id: -1,  // Placeholder ID
                            code: "",
                            description: "",
                            recordCount: recordCount,
                            modelYearId: myId,
                            modelYear: myYear
                        )

                        // Only add placeholder if array is still empty (avoid duplicates from multiple rows)
                        if makesDict[makeId]!.models[modelId]!.modelYearFuelTypes[modelYearId]!.isEmpty {
                            makesDict[makeId]!.models[modelId]!.modelYearFuelTypes[modelYearId]!.append(placeholderInfo)
                        }
                    }

                    // Add vehicle type (NOT grouped by model year - applies to all years)
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
                        // Sort fuel types within each model year group
                        let sortedModelYearFuelTypes = modelData.modelYearFuelTypes.mapValues { fuelTypes in
                            fuelTypes.sorted { $0.description < $1.description }
                        }

                        return MakeModelHierarchy.Model(
                            id: modelId,
                            name: modelData.name,
                            makeId: makeId,
                            modelYearFuelTypes: sortedModelYearFuelTypes,
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

                print("✅ Generated base canonical hierarchy: \(makes.count) makes, \(makes.reduce(0) { (total: Int, make: MakeModelHierarchy.Make) -> Int in total + make.models.count }) models")

                // DEBUG: Verify ModelYear grouping structure
                if let firstMake = makes.first, let firstModel = firstMake.models.first {
                    print("🔍 DEBUG - Verifying ModelYear-grouped FuelType structure:")
                    print("   First Model: \(firstMake.name) / \(firstModel.name)")
                    print("   ModelYear groups: \(firstModel.modelYearFuelTypes.count)")
                    for (yearId, fuelTypes) in firstModel.modelYearFuelTypes.sorted(by: {
                        // Sort by year, with nil last
                        guard let y1 = $0.value.first?.modelYear else { return false }
                        guard let y2 = $1.value.first?.modelYear else { return true }
                        return y1 < y2
                    }) {
                        let yearStr = yearId != nil ? String(yearId!) : "NULL"
                        let yearValStr = fuelTypes.first?.modelYear != nil ? String(fuelTypes.first!.modelYear!) : "nil"
                        print("      ModelYearId \(yearStr) (year: \(yearValStr)): \(fuelTypes.count) fuel types - \(fuelTypes.map { $0.code }.joined(separator: ", "))")
                    }
                }

                continuation.resume(returning: hierarchy)
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to generate canonical hierarchy: \(error)"))
            }
        }

        // Cache the hierarchy
        cachedHierarchy = baseHierarchy

        return baseHierarchy
    }


    // MARK: - Uncurated Pair Discovery

    /// Identifies Make/Model pairs in uncurated years that don't have exact matches in curated years
    func findUncuratedPairs(includeExactMatches: Bool = false) async throws -> [UnverifiedMakeModelPair] {
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
        print("   Include exact matches: \(includeExactMatches)")

        // Build IN clauses
        let uncuratedPlaceholders = uncuratedYearsList.map { _ in "?" }.joined(separator: ",")
        let curatedPlaceholders = curatedYearsList.map { _ in "?" }.joined(separator: ",")

        // Query to find Make/Model pairs in uncurated years
        // If includeExactMatches is false, exclude pairs that exist in curated years
        let whereClause = includeExactMatches ? "" : "WHERE c.make_id IS NULL"

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
        \(whereClause)
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
    /// Supports both pair-based (model_year_id = NULL) and triplet-based mappings
    /// FuelType and VehicleType are optional (NULL if user cannot disambiguate)
    func saveMapping(
        uncuratedMakeId: Int,
        uncuratedModelId: Int,
        modelYearId: Int? = nil,
        canonicalMakeId: Int,
        canonicalModelId: Int,
        fuelTypeId: Int?,
        vehicleTypeId: Int?
    ) async throws {
        guard let db = db else { throw DatabaseError.notConnected }

        // Validate Make consistency - ensure this doesn't conflict with existing mappings
        if let conflictError = try await validateMakeConsistency(
            uncuratedMakeId: uncuratedMakeId,
            canonicalMakeId: canonicalMakeId
        ) {
            throw DatabaseError.queryFailed(conflictError)
        }

        // Calculate record count for this mapping
        let recordCount = try await calculateRecordCount(
            makeId: uncuratedMakeId,
            modelId: uncuratedModelId,
            modelYearId: modelYearId
        )

        let sql = """
        INSERT OR REPLACE INTO make_model_regularization
            (uncurated_make_id, uncurated_model_id, model_year_id, canonical_make_id, canonical_model_id,
             fuel_type_id, vehicle_type_id, record_count, year_range_start, year_range_end, created_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(uncuratedMakeId))
                sqlite3_bind_int(stmt, 2, Int32(uncuratedModelId))

                if let myId = modelYearId {
                    sqlite3_bind_int(stmt, 3, Int32(myId))
                } else {
                    sqlite3_bind_null(stmt, 3)
                }

                sqlite3_bind_int(stmt, 4, Int32(canonicalMakeId))
                sqlite3_bind_int(stmt, 5, Int32(canonicalModelId))

                if let ftId = fuelTypeId {
                    sqlite3_bind_int(stmt, 6, Int32(ftId))
                } else {
                    sqlite3_bind_null(stmt, 6)
                }

                if let vtId = vehicleTypeId {
                    sqlite3_bind_int(stmt, 7, Int32(vtId))
                } else {
                    sqlite3_bind_null(stmt, 7)
                }

                sqlite3_bind_int(stmt, 8, Int32(recordCount))

                // Store min/max uncurated years
                let uncuratedYears = Array(yearConfig.uncuratedYears).sorted()
                let minYear = uncuratedYears.first ?? 2023
                let maxYear = uncuratedYears.last ?? 2024
                sqlite3_bind_int(stmt, 9, Int32(minYear))
                sqlite3_bind_int(stmt, 10, Int32(maxYear))

                let dateFormatter = ISO8601DateFormatter()
                let dateString = dateFormatter.string(from: Date())
                sqlite3_bind_text(stmt, 11, dateString, -1, nil)

                if sqlite3_step(stmt) == SQLITE_DONE {
                    let modelYearStr = modelYearId != nil ? "/ModelYear \(modelYearId!)" : " (all years)"
                    print("✅ Saved regularization mapping: Make \(uncuratedMakeId)/Model \(uncuratedModelId)\(modelYearStr) → Make \(canonicalMakeId)/Model \(canonicalModelId)")
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
            r.uncurated_make_id,
            r.uncurated_model_id,
            r.model_year_id,
            um.name as uncurated_make,
            umd.name as uncurated_model,
            my.year as model_year,
            cm.name as canonical_make,
            cmd.name as canonical_model,
            ft.description as fuel_type,
            vt.description as vehicle_type,
            r.record_count,
            r.year_range_start,
            r.year_range_end
        FROM make_model_regularization r
        JOIN make_enum um ON r.uncurated_make_id = um.id
        JOIN model_enum umd ON r.uncurated_model_id = umd.id
        LEFT JOIN model_year_enum my ON r.model_year_id = my.id
        JOIN make_enum cm ON r.canonical_make_id = cm.id
        JOIN model_enum cmd ON r.canonical_model_id = cmd.id
        LEFT JOIN fuel_type_enum ft ON r.fuel_type_id = ft.id
        LEFT JOIN vehicle_type_enum vt ON r.vehicle_type_id = vt.id
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
                    let uncuratedMakeId = Int(sqlite3_column_int(stmt, 1))
                    let uncuratedModelId = Int(sqlite3_column_int(stmt, 2))
                    let modelYearId: Int? = sqlite3_column_type(stmt, 3) != SQLITE_NULL
                        ? Int(sqlite3_column_int(stmt, 3)) : nil
                    let uncuratedMake = String(cString: sqlite3_column_text(stmt, 4))
                    let uncuratedModel = String(cString: sqlite3_column_text(stmt, 5))
                    let modelYear: Int? = sqlite3_column_type(stmt, 6) != SQLITE_NULL
                        ? Int(sqlite3_column_int(stmt, 6)) : nil
                    let canonicalMake = String(cString: sqlite3_column_text(stmt, 7))
                    let canonicalModel = String(cString: sqlite3_column_text(stmt, 8))

                    let fuelType: String? = sqlite3_column_type(stmt, 9) != SQLITE_NULL
                        ? String(cString: sqlite3_column_text(stmt, 9)) : nil
                    let vehicleType: String? = sqlite3_column_type(stmt, 10) != SQLITE_NULL
                        ? String(cString: sqlite3_column_text(stmt, 10)) : nil

                    let recordCount = Int(sqlite3_column_int(stmt, 11))
                    totalRecords += recordCount

                    let yearStart = Int(sqlite3_column_int(stmt, 12))
                    let yearEnd = Int(sqlite3_column_int(stmt, 13))
                    let yearRange = "\(yearStart)-\(yearEnd)"

                    let mapping = RegularizationMapping(
                        id: id,
                        uncuratedMakeId: uncuratedMakeId,
                        uncuratedModelId: uncuratedModelId,
                        modelYearId: modelYearId,
                        unverifiedMake: uncuratedMake,
                        unverifiedModel: uncuratedModel,
                        modelYear: modelYear,
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
                            uncuratedMakeId: mapping.uncuratedMakeId,
                            uncuratedModelId: mapping.uncuratedModelId,
                            modelYearId: mapping.modelYearId,
                            unverifiedMake: mapping.unverifiedMake,
                            unverifiedModel: mapping.unverifiedModel,
                            modelYear: mapping.modelYear,
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

    /// Gets detailed regularization statistics with field-specific coverage
    func getDetailedRegularizationStatistics() async throws -> DetailedRegularizationStatistics {
        guard let db = db else { throw DatabaseError.notConnected }

        let uncuratedYearsList = Array(yearConfig.uncuratedYears).sorted()
        guard !uncuratedYearsList.isEmpty else {
            // Return empty statistics if no uncurated years configured
            let emptyFieldCoverage = DetailedRegularizationStatistics.FieldCoverage(
                assignedCount: 0,
                unassignedCount: 0,
                totalRecords: 0
            )
            return DetailedRegularizationStatistics(
                mappingCount: 0,
                totalUncuratedRecords: 0,
                makeModelCoverage: emptyFieldCoverage,
                fuelTypeCoverage: emptyFieldCoverage,
                vehicleTypeCoverage: emptyFieldCoverage
            )
        }

        let uncuratedPlaceholders = uncuratedYearsList.map { _ in "?" }.joined(separator: ",")

        // Query for all statistics in one go
        let sql = """
        SELECT
            -- Mapping count
            (SELECT COUNT(*) FROM make_model_regularization) as mapping_count,

            -- Total uncurated records
            (SELECT COUNT(*) FROM vehicles v
             JOIN year_enum y ON v.year_id = y.id
             WHERE y.year IN (\(uncuratedPlaceholders))) as total_records,

            -- Make/Model coverage (records with canonical assignment)
            (SELECT COUNT(DISTINCT v.id) FROM vehicles v
             JOIN year_enum y ON v.year_id = y.id
             WHERE y.year IN (\(uncuratedPlaceholders))
             AND EXISTS (
                 SELECT 1 FROM make_model_regularization r
                 WHERE r.uncurated_make_id = v.make_id
                 AND r.uncurated_model_id = v.model_id
                 AND r.canonical_make_id IS NOT NULL
                 AND r.canonical_model_id IS NOT NULL
             )) as make_model_assigned,

            -- Fuel Type coverage (records with fuel type assigned)
            (SELECT COUNT(DISTINCT v.id) FROM vehicles v
             JOIN year_enum y ON v.year_id = y.id
             WHERE y.year IN (\(uncuratedPlaceholders))
             AND EXISTS (
                 SELECT 1 FROM make_model_regularization r
                 WHERE r.uncurated_make_id = v.make_id
                 AND r.uncurated_model_id = v.model_id
                 AND r.fuel_type_id IS NOT NULL
             )) as fuel_type_assigned,

            -- Vehicle Type coverage (records with vehicle type assigned)
            (SELECT COUNT(DISTINCT v.id) FROM vehicles v
             JOIN year_enum y ON v.year_id = y.id
             WHERE y.year IN (\(uncuratedPlaceholders))
             AND EXISTS (
                 SELECT 1 FROM make_model_regularization r
                 WHERE r.uncurated_make_id = v.make_id
                 AND r.uncurated_model_id = v.model_id
                 AND r.vehicle_type_id IS NOT NULL
             )) as vehicle_type_assigned;
        """

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                // Bind uncurated years (appears twice in the query)
                var bindIndex: Int32 = 1
                for _ in 0..<5 { // 5 subqueries use uncurated years
                    for year in uncuratedYearsList {
                        sqlite3_bind_int(stmt, bindIndex, Int32(year))
                        bindIndex += 1
                    }
                }

                if sqlite3_step(stmt) == SQLITE_ROW {
                    let mappingCount = Int(sqlite3_column_int(stmt, 0))
                    let totalRecords = Int(sqlite3_column_int(stmt, 1))
                    let makeModelAssigned = Int(sqlite3_column_int(stmt, 2))
                    let fuelTypeAssigned = Int(sqlite3_column_int(stmt, 3))
                    let vehicleTypeAssigned = Int(sqlite3_column_int(stmt, 4))

                    let makeModelCoverage = DetailedRegularizationStatistics.FieldCoverage(
                        assignedCount: makeModelAssigned,
                        unassignedCount: totalRecords - makeModelAssigned,
                        totalRecords: totalRecords
                    )

                    let fuelTypeCoverage = DetailedRegularizationStatistics.FieldCoverage(
                        assignedCount: fuelTypeAssigned,
                        unassignedCount: totalRecords - fuelTypeAssigned,
                        totalRecords: totalRecords
                    )

                    let vehicleTypeCoverage = DetailedRegularizationStatistics.FieldCoverage(
                        assignedCount: vehicleTypeAssigned,
                        unassignedCount: totalRecords - vehicleTypeAssigned,
                        totalRecords: totalRecords
                    )

                    let stats = DetailedRegularizationStatistics(
                        mappingCount: mappingCount,
                        totalUncuratedRecords: totalRecords,
                        makeModelCoverage: makeModelCoverage,
                        fuelTypeCoverage: fuelTypeCoverage,
                        vehicleTypeCoverage: vehicleTypeCoverage
                    )

                    print("✅ Detailed regularization statistics:")
                    print("   Mappings: \(mappingCount)")
                    print("   Total uncurated records: \(totalRecords)")
                    print("   Make/Model coverage: \(String(format: "%.1f", makeModelCoverage.coveragePercentage))%")
                    print("   Fuel Type coverage: \(String(format: "%.1f", fuelTypeCoverage.coveragePercentage))%")
                    print("   Vehicle Type coverage: \(String(format: "%.1f", vehicleTypeCoverage.coveragePercentage))%")

                    continuation.resume(returning: stats)
                } else {
                    // Return empty statistics if no results
                    let emptyFieldCoverage = DetailedRegularizationStatistics.FieldCoverage(
                        assignedCount: 0,
                        unassignedCount: 0,
                        totalRecords: 0
                    )
                    continuation.resume(returning: DetailedRegularizationStatistics(
                        mappingCount: 0,
                        totalUncuratedRecords: 0,
                        makeModelCoverage: emptyFieldCoverage,
                        fuelTypeCoverage: emptyFieldCoverage,
                        vehicleTypeCoverage: emptyFieldCoverage
                    ))
                }
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to get detailed statistics: \(error)"))
            }
        }
    }

    /// Gets regularization display info for filter dropdowns
    /// Returns a dictionary mapping (makeId, modelId) to (canonicalMakeName, canonicalModelName, recordCount)
    func getRegularizationDisplayInfo() async throws -> [String: (canonicalMake: String, canonicalModel: String, recordCount: Int)] {
        guard let db = db else { throw DatabaseError.notConnected }

        let sql = """
        SELECT
            r.uncurated_make_id,
            r.uncurated_model_id,
            canonical_make.name as canonical_make_name,
            canonical_model.name as canonical_model_name,
            r.record_count
        FROM make_model_regularization r
        JOIN make_enum canonical_make ON r.canonical_make_id = canonical_make.id
        JOIN model_enum canonical_model ON r.canonical_model_id = canonical_model.id;
        """

        return try await withCheckedThrowingContinuation { continuation in
            var results: [String: (String, String, Int)] = [:]
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let uncuratedMakeId = Int(sqlite3_column_int(stmt, 0))
                    let uncuratedModelId = Int(sqlite3_column_int(stmt, 1))
                    let canonicalMakeName = String(cString: sqlite3_column_text(stmt, 2))
                    let canonicalModelName = String(cString: sqlite3_column_text(stmt, 3))
                    let recordCount = Int(sqlite3_column_int(stmt, 4))

                    let key = "\(uncuratedMakeId)_\(uncuratedModelId)"
                    results[key] = (canonicalMakeName, canonicalModelName, recordCount)
                }
                continuation.resume(returning: results)
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to get regularization display info: \(error)"))
            }
        }
    }

    // MARK: - Query Translation

    /// Expands a set of make/model IDs to include all regularized variants
    /// When regularization is enabled, this works bidirectionally:
    /// - Canonical IDs → Include their uncurated variants
    /// - Uncurated IDs → Replace with canonical IDs (which may have other uncurated variants)
    /// - coupling parameter: When true, respects Make/Model relationships; when false, keeps them independent
    func expandMakeModelIDs(
        makeIds: [Int],
        modelIds: [Int],
        coupling: Bool = true
    ) async throws -> (makeIds: [Int], modelIds: [Int]) {
        guard let db = db else { throw DatabaseError.notConnected }
        guard !makeIds.isEmpty || !modelIds.isEmpty else {
            return (makeIds, modelIds)
        }

        // Start with original IDs
        var expandedMakeIds = Set(makeIds)
        var expandedModelIds = Set(modelIds)

        // STEP 1: If any input IDs are UNCURATED, find their CANONICAL equivalents
        let uncuratedToCanonicalSql = """
        SELECT DISTINCT uncurated_make_id, uncurated_model_id, canonical_make_id, canonical_model_id
        FROM make_model_regularization
        WHERE uncurated_make_id IN (\(makeIds.map { String($0) }.joined(separator: ",")))
           OR uncurated_model_id IN (\(modelIds.map { String($0) }.joined(separator: ",")));
        """

        var stmt1: OpaquePointer?
        defer { sqlite3_finalize(stmt1) }

        if sqlite3_prepare_v2(db, uncuratedToCanonicalSql, -1, &stmt1, nil) == SQLITE_OK {
            while sqlite3_step(stmt1) == SQLITE_ROW {
                let uncuratedMakeId = Int(sqlite3_column_int(stmt1, 0))
                let uncuratedModelId = Int(sqlite3_column_int(stmt1, 1))
                let canonicalMakeId = Int(sqlite3_column_int(stmt1, 2))
                let canonicalModelId = Int(sqlite3_column_int(stmt1, 3))

                // If user selected an uncurated ID, add its canonical equivalent
                if makeIds.contains(uncuratedMakeId) {
                    expandedMakeIds.insert(canonicalMakeId)
                    print("   🔄 Uncurated Make \(uncuratedMakeId) → Canonical \(canonicalMakeId)")
                }
                if modelIds.contains(uncuratedModelId) {
                    expandedModelIds.insert(canonicalModelId)
                    print("   🔄 Uncurated Model \(uncuratedModelId) → Canonical \(canonicalModelId)")
                }
            }
        }

        // STEP 2: For all IDs (including newly added canonical ones), find their uncurated variants
        let currentMakeIds = Array(expandedMakeIds)
        let currentModelIds = Array(expandedModelIds)

        let canonicalToUncuratedSql = """
        SELECT DISTINCT uncurated_make_id, uncurated_model_id
        FROM make_model_regularization
        WHERE canonical_make_id IN (\(currentMakeIds.map { String($0) }.joined(separator: ",")))
           OR canonical_model_id IN (\(currentModelIds.map { String($0) }.joined(separator: ",")));
        """

        return try await withCheckedThrowingContinuation { continuation in
            var stmt2: OpaquePointer?
            defer { sqlite3_finalize(stmt2) }

            if sqlite3_prepare_v2(db, canonicalToUncuratedSql, -1, &stmt2, nil) == SQLITE_OK {
                while sqlite3_step(stmt2) == SQLITE_ROW {
                    let uncuratedMakeId = Int(sqlite3_column_int(stmt2, 0))
                    let uncuratedModelId = Int(sqlite3_column_int(stmt2, 1))

                    // With coupling: Add both Make and Model IDs (respects relationships)
                    // Without coupling: Only add IDs for types that were originally filtered
                    if coupling {
                        expandedMakeIds.insert(uncuratedMakeId)
                        expandedModelIds.insert(uncuratedModelId)
                    } else {
                        // Only add Make IDs if Makes were part of the original filter
                        if !makeIds.isEmpty {
                            expandedMakeIds.insert(uncuratedMakeId)
                        }
                        // Only add Model IDs if Models were part of the original filter
                        if !modelIds.isEmpty {
                            expandedModelIds.insert(uncuratedModelId)
                        }
                    }
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

    /// Expands a set of make IDs to include all regularized variants (derived from Make/Model mappings)
    /// When regularization is enabled, this works bidirectionally:
    /// - Canonical Make IDs → Include their uncurated variants
    /// - Uncurated Make IDs → Replace with canonical IDs (which may have other uncurated variants)
    func expandMakeIDs(makeIds: [Int]) async throws -> [Int] {
        guard let db = db else { throw DatabaseError.notConnected }
        guard !makeIds.isEmpty else { return makeIds }

        // Start with original IDs
        var expandedMakeIds = Set(makeIds)

        // STEP 1: If any input IDs are UNCURATED Makes, find their CANONICAL equivalents
        let placeholders1 = makeIds.map { _ in "?" }.joined(separator: ",")
        let uncuratedToCanonicalSql = """
        SELECT DISTINCT uncurated_make_id, canonical_make_id
        FROM make_model_regularization
        WHERE uncurated_make_id IN (\(placeholders1));
        """

        var stmt1: OpaquePointer?
        defer { sqlite3_finalize(stmt1) }

        if sqlite3_prepare_v2(db, uncuratedToCanonicalSql, -1, &stmt1, nil) == SQLITE_OK {
            for (index, makeId) in makeIds.enumerated() {
                sqlite3_bind_int(stmt1, Int32(index + 1), Int32(makeId))
            }

            while sqlite3_step(stmt1) == SQLITE_ROW {
                let uncuratedMakeId = Int(sqlite3_column_int(stmt1, 0))
                let canonicalMakeId = Int(sqlite3_column_int(stmt1, 1))

                if makeIds.contains(uncuratedMakeId) {
                    expandedMakeIds.insert(canonicalMakeId)
                    print("   🔄 Uncurated Make \(uncuratedMakeId) → Canonical \(canonicalMakeId)")
                }
            }
        }

        // STEP 2: For all IDs (including newly added canonical ones), find their uncurated variants
        let currentMakeIds = Array(expandedMakeIds)
        let placeholders2 = currentMakeIds.map { _ in "?" }.joined(separator: ",")
        let canonicalToUncuratedSql = """
        SELECT DISTINCT uncurated_make_id
        FROM make_model_regularization
        WHERE canonical_make_id IN (\(placeholders2));
        """

        return try await withCheckedThrowingContinuation { continuation in
            var stmt2: OpaquePointer?
            defer { sqlite3_finalize(stmt2) }

            if sqlite3_prepare_v2(db, canonicalToUncuratedSql, -1, &stmt2, nil) == SQLITE_OK {
                for (index, makeId) in currentMakeIds.enumerated() {
                    sqlite3_bind_int(stmt2, Int32(index + 1), Int32(makeId))
                }

                while sqlite3_step(stmt2) == SQLITE_ROW {
                    let uncuratedMakeId = Int(sqlite3_column_int(stmt2, 0))
                    expandedMakeIds.insert(uncuratedMakeId)
                }

                let makeArray = Array(expandedMakeIds).sorted()

                if makeArray.count > makeIds.count {
                    print("🔄 Make regularization expanded \(makeIds.count) → \(makeArray.count) IDs")
                }

                continuation.resume(returning: makeArray)
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to expand Make IDs: \(error)"))
            }
        }
    }

    /// Gets Make regularization info derived from Make/Model mappings
    /// Returns dictionary mapping "uncuratedMakeId" → (canonicalMake, recordCount)
    func getMakeRegularizationDisplayInfo() async throws -> [String: (canonicalMake: String, recordCount: Int)] {
        guard let db = db else { throw DatabaseError.notConnected }

        // Group by uncurated_make_id and canonical_make_id, sum record counts
        let sql = """
        SELECT
            mmr.uncurated_make_id,
            me.name as canonical_make,
            SUM(mmr.record_count) as total_records
        FROM make_model_regularization mmr
        JOIN make_enum me ON mmr.canonical_make_id = me.id
        GROUP BY mmr.uncurated_make_id, mmr.canonical_make_id;
        """

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            var result: [String: (canonicalMake: String, recordCount: Int)] = [:]

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let uncuratedMakeId = Int(sqlite3_column_int(stmt, 0))
                    let canonicalMake = String(cString: sqlite3_column_text(stmt, 1))
                    let recordCount = Int(sqlite3_column_int(stmt, 2))

                    let key = String(uncuratedMakeId)
                    result[key] = (canonicalMake: canonicalMake, recordCount: recordCount)
                }

                if !result.isEmpty {
                    print("✅ Loaded derived Make regularization info for \(result.count) Makes")
                }

                continuation.resume(returning: result)
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to get Make regularization info: \(error)"))
            }
        }
    }

    /// Validates that a new Make/Model mapping doesn't conflict with existing Make regularization
    /// Returns nil if valid, or error message if conflicts exist
    func validateMakeConsistency(
        uncuratedMakeId: Int,
        canonicalMakeId: Int
    ) async throws -> String? {
        guard let db = db else { throw DatabaseError.notConnected }

        // Check if this uncurated_make_id already maps to a DIFFERENT canonical_make_id
        let sql = """
        SELECT DISTINCT canonical_make_id, me.name as canonical_make
        FROM make_model_regularization mmr
        JOIN make_enum me ON mmr.canonical_make_id = me.id
        WHERE uncurated_make_id = ? AND canonical_make_id != ?;
        """

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(uncuratedMakeId))
                sqlite3_bind_int(stmt, 2, Int32(canonicalMakeId))

                if sqlite3_step(stmt) == SQLITE_ROW {
                    let existingCanonicalMake = String(cString: sqlite3_column_text(stmt, 1))
                    let errorMessage = "This uncurated Make already maps to '\(existingCanonicalMake)'. All models from the same Make must map to the same canonical Make."
                    continuation.resume(returning: errorMessage)
                } else {
                    continuation.resume(returning: nil)
                }
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to validate Make consistency: \(error)"))
            }
        }
    }

    // MARK: - Vehicle Type Regularization

    /// Gets uncurated Make/Model IDs that should match a given vehicle type filter
    /// This allows uncurated records (with NULL vehicle_type_id) to be included when filtering by vehicle type
    func getUncuratedMakeModelIDsForVehicleType(vehicleTypeId: Int) async throws -> (makeIds: [Int], modelIds: [Int]) {
        guard let db = db else { throw DatabaseError.notConnected }

        // Query: Find uncurated Make/Model pairs that map to this vehicle type
        let sql = """
        SELECT DISTINCT
            r.uncurated_make_id,
            r.uncurated_model_id
        FROM make_model_regularization r
        WHERE r.vehicle_type_id = ?;
        """

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            var makeIds: Set<Int> = []
            var modelIds: Set<Int> = []

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(vehicleTypeId))

                while sqlite3_step(stmt) == SQLITE_ROW {
                    let makeId = Int(sqlite3_column_int(stmt, 0))
                    let modelId = Int(sqlite3_column_int(stmt, 1))
                    makeIds.insert(makeId)
                    modelIds.insert(modelId)
                }

                let makeArray = Array(makeIds).sorted()
                let modelArray = Array(modelIds).sorted()

                if !makeArray.isEmpty {
                    print("🔄 Vehicle Type regularization: Found \(makeArray.count) makes, \(modelArray.count) models for vehicle type ID \(vehicleTypeId)")
                }

                continuation.resume(returning: (makeIds: makeArray, modelIds: modelArray))
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to get Make/Model IDs for vehicle type: \(error)"))
            }
        }
    }

    // MARK: - Vehicle Type Filtering

    /// Gets all vehicle types from the vehicle_type_enum table
    func getAllVehicleTypes() async throws -> [MakeModelHierarchy.VehicleTypeInfo] {
        guard let db = db else { throw DatabaseError.notConnected }

        let sql = """
        SELECT id, code, description
        FROM vehicle_type_enum
        ORDER BY code;
        """

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            var vehicleTypes: [MakeModelHierarchy.VehicleTypeInfo] = []

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let code = String(cString: sqlite3_column_text(stmt, 1))
                    let description = String(cString: sqlite3_column_text(stmt, 2))

                    let vehicleType = MakeModelHierarchy.VehicleTypeInfo(
                        id: id,
                        code: code,
                        description: description,
                        recordCount: 0
                    )
                    vehicleTypes.append(vehicleType)
                }

                print("✅ Loaded \(vehicleTypes.count) vehicle types from schema")
                continuation.resume(returning: vehicleTypes)
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to get vehicle types: \(error)"))
            }
        }
    }

    /// Gets vehicle types that are present in regularization mappings (including Unknown)
    func getRegularizationVehicleTypes() async throws -> [MakeModelHierarchy.VehicleTypeInfo] {
        guard let db = db else { throw DatabaseError.notConnected }

        let sql = """
        SELECT DISTINCT
            vt.id,
            vt.code,
            vt.description,
            COUNT(r.id) as mapping_count
        FROM make_model_regularization r
        JOIN vehicle_type_enum vt ON r.vehicle_type_id = vt.id
        GROUP BY vt.id, vt.code, vt.description
        ORDER BY vt.code;
        """

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            var vehicleTypes: [MakeModelHierarchy.VehicleTypeInfo] = []

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let code = String(cString: sqlite3_column_text(stmt, 1))
                    let description = String(cString: sqlite3_column_text(stmt, 2))
                    let recordCount = Int(sqlite3_column_int(stmt, 3))

                    let vehicleType = MakeModelHierarchy.VehicleTypeInfo(
                        id: id,
                        code: code,
                        description: description,
                        recordCount: recordCount
                    )
                    vehicleTypes.append(vehicleType)
                }

                print("✅ Loaded \(vehicleTypes.count) vehicle types from regularization mappings")
                continuation.resume(returning: vehicleTypes)
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to get regularization vehicle types: \(error)"))
            }
        }
    }

    // MARK: - Helper Methods

    /// Calculates the number of records for an uncurated Make/Model(/ModelYear) in uncurated years
    private func calculateRecordCount(
        makeId: Int,
        modelId: Int,
        modelYearId: Int? = nil
    ) async throws -> Int {
        guard let db = db else { throw DatabaseError.notConnected }

        let uncuratedYearsList = Array(yearConfig.uncuratedYears).sorted()
        guard !uncuratedYearsList.isEmpty else {
            return 0
        }

        let uncuratedPlaceholders = uncuratedYearsList.map { _ in "?" }.joined(separator: ",")

        // Add model_year_id filter if specified
        let modelYearFilter = modelYearId != nil ? "AND v.model_year_id = ?" : ""

        let sql = """
        SELECT COUNT(*)
        FROM vehicles v
        JOIN year_enum y ON v.year_id = y.id
        WHERE v.make_id = ? AND v.model_id = ?
        \(modelYearFilter)
        AND y.year IN (\(uncuratedPlaceholders));
        """

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                var bindIndex: Int32 = 1
                sqlite3_bind_int(stmt, bindIndex, Int32(makeId))
                bindIndex += 1
                sqlite3_bind_int(stmt, bindIndex, Int32(modelId))
                bindIndex += 1

                // Bind model_year_id if specified
                if let myId = modelYearId {
                    sqlite3_bind_int(stmt, bindIndex, Int32(myId))
                    bindIndex += 1
                }

                // Bind uncurated years
                for year in uncuratedYearsList {
                    sqlite3_bind_int(stmt, bindIndex, Int32(year))
                    bindIndex += 1
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
