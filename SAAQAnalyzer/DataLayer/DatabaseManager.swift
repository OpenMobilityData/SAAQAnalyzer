import Foundation
import SQLite3
import Combine

/// Manages SQLite database operations for SAAQ data
class DatabaseManager: ObservableObject {
    /// Singleton instance
    static let shared = DatabaseManager()
    
    /// Database file URL
    @Published var databaseURL: URL?
    
    /// Triggers UI refresh when data changes - using database file timestamp for persistence
    @Published var dataVersion = 0
    
    /// Filter cache manager
    private let filterCache = FilterCache()
    
    /// SQLite database handle
    internal var db: OpaquePointer?
    
    /// Queue for database operations
    internal let dbQueue = DispatchQueue(label: "com.saaqanalyzer.database", qos: .userInitiated)
    
    private init() {
        setupDefaultDatabase()
    }
    
    deinit {
        closeDatabase()
    }
    
    /// Sets up default database location
    private func setupDefaultDatabase() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbPath = documentsPath.appendingPathComponent("saaq_data.sqlite")
        setDatabaseLocation(dbPath)
    }

    /// Gets a persistent data version based on database file modification time
    private func getPersistentDataVersion() -> String {
        guard let dbURL = databaseURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: dbURL.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return "0"
        }
        // Use timestamp as version identifier
        return String(Int(modificationDate.timeIntervalSince1970))
    }
    
    /// Changes database location
    func setDatabaseLocation(_ url: URL) {
        dbQueue.async { [weak self] in
            self?.closeDatabase()
            self?.databaseURL = url
            self?.openDatabase()
            self?.createTablesIfNeeded()
        }
    }
    
    /// Debug method to show database contents
    func debugShowContents() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    print("Debug: No database connection")
                    continuation.resume()
                    return
                }
                
                // Check vehicles table
                let countQuery = "SELECT COUNT(*) FROM vehicles"
                var stmt: OpaquePointer?
                
                if sqlite3_prepare_v2(db, countQuery, -1, &stmt, nil) == SQLITE_OK {
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        let count = sqlite3_column_int(stmt, 0)
                        print("\nDebug: Total vehicles in database: \(count)")
                    }
                }
                sqlite3_finalize(stmt)
                
                // Show sample of data
                let sampleQuery = """
                    SELECT year, classification, admin_region, mrc, COUNT(*) as count
                    FROM vehicles
                    GROUP BY year, classification, admin_region, mrc
                    LIMIT 10
                    """
                
                if sqlite3_prepare_v2(db, sampleQuery, -1, &stmt, nil) == SQLITE_OK {
                    print("\nDebug: Sample data (first 10 groups):")
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        let year = sqlite3_column_int(stmt, 0)
                        
                        let clas: String
                        if let clasPtr = sqlite3_column_text(stmt, 1) {
                            clas = String(cString: clasPtr)
                        } else {
                            clas = ""
                        }
                        
                        let region: String
                        if let regionPtr = sqlite3_column_text(stmt, 2) {
                            region = String(cString: regionPtr)
                        } else {
                            region = ""
                        }
                        
                        let mrc: String
                        if let mrcPtr = sqlite3_column_text(stmt, 3) {
                            mrc = String(cString: mrcPtr)
                        } else {
                            mrc = ""
                        }
                        
                        let count = sqlite3_column_int(stmt, 4)
                        print("  Year: \(year), Class: \(clas), Region: \(region), MRC: \(mrc), Count: \(count)")
                    }
                }
                sqlite3_finalize(stmt)
                
                // Check available regions
                let regionQuery = "SELECT DISTINCT admin_region FROM vehicles ORDER BY admin_region"
                if sqlite3_prepare_v2(db, regionQuery, -1, &stmt, nil) == SQLITE_OK {
                    print("\nDebug: Available regions:")
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let regionPtr = sqlite3_column_text(stmt, 0) {
                            let region = String(cString: regionPtr)
                            print("  - \(region)")
                        }
                    }
                }
                sqlite3_finalize(stmt)
                
                continuation.resume()
            }
        }
    }
    
    /// Opens SQLite database connection
    private func openDatabase() {
        guard let dbPath = databaseURL?.path else { return }
        
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK {
            print("Successfully opened database at: \(dbPath)")
            
            // Enable performance optimizations
            sqlite3_exec(db, "PRAGMA journal_mode = WAL", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA synchronous = NORMAL", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA cache_size = -64000", nil, nil, nil)  // 64MB cache
            sqlite3_exec(db, "PRAGMA temp_store = MEMORY", nil, nil, nil)
        } else {
            print("Unable to open database at: \(dbPath)")
            if let errorMessage = sqlite3_errmsg(db) {
                print("Error: \(String(cString: errorMessage))")
            }
        }
    }
    
    /// Clears all data from the database
    func clearAllData() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }
                
                let tables = ["vehicles", "licenses", "geographic_entities", "import_log"]
                
                do {
                    for table in tables {
                        let sql = "DELETE FROM \(table)"
                        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                            throw DatabaseError.queryFailed("Failed to clear table: \(table)")
                        }
                    }
                    
                    // VACUUM to reclaim space
                    sqlite3_exec(db, "VACUUM", nil, nil, nil)
                    
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Clears data for a specific year from the database
    func clearYearData(_ year: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }
                
                do {
                    // Delete vehicle records for the specific year
                    let deleteVehiclesSQL = "DELETE FROM vehicles WHERE year = ?"
                    var deleteStmt: OpaquePointer?

                    if sqlite3_prepare_v2(db, deleteVehiclesSQL, -1, &deleteStmt, nil) == SQLITE_OK {
                        sqlite3_bind_int(deleteStmt, 1, Int32(year))

                        if sqlite3_step(deleteStmt) != SQLITE_DONE {
                            sqlite3_finalize(deleteStmt)
                            throw DatabaseError.queryFailed("Failed to delete vehicle records for year \(year)")
                        }
                        sqlite3_finalize(deleteStmt)
                    } else {
                        throw DatabaseError.queryFailed("Failed to prepare delete statement for year \(year)")
                    }

                    // Delete license records for the specific year
                    let deleteLicensesSQL = "DELETE FROM licenses WHERE year = ?"
                    var deleteLicenseStmt: OpaquePointer?

                    if sqlite3_prepare_v2(db, deleteLicensesSQL, -1, &deleteLicenseStmt, nil) == SQLITE_OK {
                        sqlite3_bind_int(deleteLicenseStmt, 1, Int32(year))

                        if sqlite3_step(deleteLicenseStmt) != SQLITE_DONE {
                            sqlite3_finalize(deleteLicenseStmt)
                            throw DatabaseError.queryFailed("Failed to delete license records for year \(year)")
                        }
                        sqlite3_finalize(deleteLicenseStmt)
                    } else {
                        throw DatabaseError.queryFailed("Failed to prepare delete license statement for year \(year)")
                    }
                    
                    // Delete import log entries for the specific year
                    let deleteLogSQL = "DELETE FROM import_log WHERE year = ?"
                    var logStmt: OpaquePointer?
                    
                    if sqlite3_prepare_v2(db, deleteLogSQL, -1, &logStmt, nil) == SQLITE_OK {
                        sqlite3_bind_int(logStmt, 1, Int32(year))
                        
                        if sqlite3_step(logStmt) != SQLITE_DONE {
                            sqlite3_finalize(logStmt)
                            throw DatabaseError.queryFailed("Failed to delete import log for year \(year)")
                        }
                        sqlite3_finalize(logStmt)
                    } else {
                        throw DatabaseError.queryFailed("Failed to prepare delete log statement for year \(year)")
                    }
                    
                    print("✅ Successfully deleted all data for year \(year)")
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }


    /// Closes database connection
    private func closeDatabase() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }
    
    /// Creates required tables if they don't exist
    private func createTablesIfNeeded() {
        let createVehiclesTable = """
            CREATE TABLE IF NOT EXISTS vehicles (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                year INTEGER NOT NULL,
                vehicle_sequence TEXT NOT NULL,
                classification TEXT NOT NULL,
                vehicle_type TEXT,
                make TEXT,
                model TEXT,
                model_year INTEGER,
                net_mass REAL,
                cylinder_count INTEGER,
                displacement REAL,
                max_axles INTEGER,
                original_color TEXT,
                fuel_type TEXT,
                admin_region TEXT NOT NULL,
                mrc TEXT NOT NULL,
                geo_code TEXT NOT NULL,
                UNIQUE(year, vehicle_sequence)
            );
            """
        
        let createLicensesTable = """
            CREATE TABLE IF NOT EXISTS licenses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                year INTEGER NOT NULL,
                license_sequence TEXT NOT NULL,
                age_group TEXT NOT NULL,
                gender TEXT NOT NULL,
                mrc TEXT NOT NULL,
                admin_region TEXT NOT NULL,
                license_type TEXT NOT NULL,
                has_learner_permit_123 INTEGER NOT NULL DEFAULT 0,
                has_learner_permit_5 INTEGER NOT NULL DEFAULT 0,
                has_learner_permit_6a6r INTEGER NOT NULL DEFAULT 0,
                has_driver_license_1234 INTEGER NOT NULL DEFAULT 0,
                has_driver_license_5 INTEGER NOT NULL DEFAULT 0,
                has_driver_license_6abce INTEGER NOT NULL DEFAULT 0,
                has_driver_license_6d INTEGER NOT NULL DEFAULT 0,
                has_driver_license_8 INTEGER NOT NULL DEFAULT 0,
                is_probationary INTEGER NOT NULL DEFAULT 0,
                experience_1234 TEXT,
                experience_5 TEXT,
                experience_6abce TEXT,
                experience_global TEXT,
                UNIQUE(year, license_sequence)
            );
            """

        let createGeographicTable = """
            CREATE TABLE IF NOT EXISTS geographic_entities (
                code TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                type TEXT NOT NULL,
                parent_code TEXT,
                latitude REAL,
                longitude REAL,
                area_total REAL,
                area_land REAL
            );
            """
        
        let createImportLogTable = """
            CREATE TABLE IF NOT EXISTS import_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_name TEXT NOT NULL,
                year INTEGER NOT NULL,
                record_count INTEGER NOT NULL,
                import_date TEXT NOT NULL,
                status TEXT NOT NULL
            );
            """
        
        // Create indexes for better query performance
        let createIndexes = [
            // Vehicle indexes
            "CREATE INDEX IF NOT EXISTS idx_vehicles_year ON vehicles(year);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_classification ON vehicles(classification);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_geo ON vehicles(admin_region, mrc, geo_code);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_fuel ON vehicles(fuel_type);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_model_year ON vehicles(model_year);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_make ON vehicles(make);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_model ON vehicles(model);",
            // License indexes
            "CREATE INDEX IF NOT EXISTS idx_licenses_year ON licenses(year);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_geo ON licenses(admin_region, mrc);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_type ON licenses(license_type);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_age_group ON licenses(age_group);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_gender ON licenses(gender);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_probationary ON licenses(is_probationary);",
            // Geographic indexes
            "CREATE INDEX IF NOT EXISTS idx_geographic_type ON geographic_entities(type);",
            "CREATE INDEX IF NOT EXISTS idx_geographic_parent ON geographic_entities(parent_code);"
        ]
        
        dbQueue.async { [weak self] in
            guard let db = self?.db else { return }
            
            // Create tables
            for query in [createVehiclesTable, createLicensesTable, createGeographicTable, createImportLogTable] {
                if sqlite3_exec(db, query, nil, nil, nil) != SQLITE_OK {
                    if let errorMessage = sqlite3_errmsg(db) {
                        print("Error creating table: \(String(cString: errorMessage))")
                    }
                }
            }
            
            // Create indexes
            for index in createIndexes {
                sqlite3_exec(db, index, nil, nil, nil)
            }
        }
    }
    
    /// Checks if data for a specific year is already imported
    func isYearImported(_ year: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: false)
                    return
                }
                
                // Check if actual vehicle records exist for this year
                // This is more reliable than checking import_log which might be incomplete
                let query = "SELECT COUNT(*) FROM vehicles WHERE year = ? LIMIT 1"
                var stmt: OpaquePointer?
                
                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }
                
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_int(stmt, 1, Int32(year))
                    
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        let count = sqlite3_column_int(stmt, 0)
                        continuation.resume(returning: count > 0)
                    } else {
                        continuation.resume(returning: false)
                    }
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Check if license year is already imported
    func isLicenseYearImported(_ year: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: false)
                    return
                }

                // Check if actual license records exist for this year
                let query = "SELECT COUNT(*) FROM licenses WHERE year = ? LIMIT 1"
                var stmt: OpaquePointer?

                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_int(stmt, 1, Int32(year))

                    if sqlite3_step(stmt) == SQLITE_ROW {
                        let count = sqlite3_column_int(stmt, 0)
                        continuation.resume(returning: count > 0)
                    } else {
                        continuation.resume(returning: false)
                    }
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Generic query method that routes to appropriate data type handler
    func queryData(filters: FilterConfiguration) async throws -> FilteredDataSeries {
        switch filters.dataEntityType {
        case .vehicle:
            return try await queryVehicleData(filters: filters)
        case .license:
            return try await queryLicenseData(filters: filters)
        }
    }

    /// Queries vehicle data based on filters
    func queryVehicleData(filters: FilterConfiguration) async throws -> FilteredDataSeries {
        // First, generate the proper series name with municipality name resolution
        let seriesName = await generateSeriesNameAsync(from: filters)

        return try await withCheckedThrowingContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }

                // Build dynamic query based on filters and metric type
                var query: String

                // Build SELECT clause based on metric type
                switch filters.metricType {
                case .count:
                    query = "SELECT year, COUNT(*) as value FROM vehicles WHERE 1=1"

                case .sum:
                    if filters.metricField == .vehicleAge {
                        // Special case: sum of computed age
                        query = "SELECT year, SUM(year - model_year) as value FROM vehicles WHERE model_year IS NOT NULL AND 1=1"
                    } else if let column = filters.metricField.databaseColumn {
                        query = "SELECT year, SUM(\(column)) as value FROM vehicles WHERE \(column) IS NOT NULL AND 1=1"
                    } else {
                        // Fallback to count if no valid field
                        query = "SELECT year, COUNT(*) as value FROM vehicles WHERE 1=1"
                    }

                case .average:
                    if filters.metricField == .vehicleAge {
                        // Special case: average of computed age
                        query = "SELECT year, AVG(year - model_year) as value FROM vehicles WHERE model_year IS NOT NULL AND 1=1"
                    } else if let column = filters.metricField.databaseColumn {
                        query = "SELECT year, AVG(\(column)) as value FROM vehicles WHERE \(column) IS NOT NULL AND 1=1"
                    } else {
                        // Fallback to count if no valid field
                        query = "SELECT year, COUNT(*) as value FROM vehicles WHERE 1=1"
                    }

                case .percentage:
                    // For percentage, we need to do dual queries - this is handled separately
                    query = "SELECT year, COUNT(*) as value FROM vehicles WHERE 1=1"
                }

                var bindIndex = 1
                var bindValues: [(Int32, Any)] = []

                // Add year filter
                if !filters.years.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.years.count).joined(separator: ",")
                    query += " AND year IN (\(placeholders))"
                    for year in filters.years.sorted() {
                        bindValues.append((Int32(bindIndex), year))
                        bindIndex += 1
                    }
                }

                // Add region filter
                if !filters.regions.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.regions.count).joined(separator: ",")
                    query += " AND admin_region IN (\(placeholders))"
                    for region in filters.regions.sorted() {
                        bindValues.append((Int32(bindIndex), region))
                        bindIndex += 1
                    }
                }

                // Add MRC filter
                if !filters.mrcs.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.mrcs.count).joined(separator: ",")
                    query += " AND mrc IN (\(placeholders))"
                    for mrc in filters.mrcs.sorted() {
                        bindValues.append((Int32(bindIndex), mrc))
                        bindIndex += 1
                    }
                }

                // Add municipality filter
                if !filters.municipalities.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.municipalities.count).joined(separator: ",")
                    query += " AND geo_code IN (\(placeholders))"
                    for municipality in filters.municipalities.sorted() {
                        bindValues.append((Int32(bindIndex), municipality))
                        bindIndex += 1
                    }
                }

                // Add vehicle classification filter
                if !filters.vehicleClassifications.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.vehicleClassifications.count).joined(separator: ",")
                    query += " AND classification IN (\(placeholders))"
                    for classification in filters.vehicleClassifications.sorted() {
                        bindValues.append((Int32(bindIndex), classification))
                        bindIndex += 1
                    }
                }

                // Add vehicle make filter
                if !filters.vehicleMakes.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.vehicleMakes.count).joined(separator: ",")
                    query += " AND make IN (\(placeholders))"
                    for make in filters.vehicleMakes.sorted() {
                        bindValues.append((Int32(bindIndex), make))
                        bindIndex += 1
                    }
                }

                // Add vehicle model filter
                if !filters.vehicleModels.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.vehicleModels.count).joined(separator: ",")
                    query += " AND model IN (\(placeholders))"
                    for model in filters.vehicleModels.sorted() {
                        bindValues.append((Int32(bindIndex), model))
                        bindIndex += 1
                    }
                }

                // Add vehicle color filter
                if !filters.vehicleColors.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.vehicleColors.count).joined(separator: ",")
                    query += " AND original_color IN (\(placeholders))"
                    for color in filters.vehicleColors.sorted() {
                        bindValues.append((Int32(bindIndex), color))
                        bindIndex += 1
                    }
                }

                // Add model year filter
                if !filters.modelYears.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.modelYears.count).joined(separator: ",")
                    query += " AND model_year IN (\(placeholders))"
                    for modelYear in filters.modelYears.sorted() {
                        bindValues.append((Int32(bindIndex), modelYear))
                        bindIndex += 1
                    }
                }

                // Add fuel type filter (only for years 2017+)
                if !filters.fuelTypes.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.fuelTypes.count).joined(separator: ",")
                    query += " AND fuel_type IN (\(placeholders)) AND year >= 2017"
                    for fuelType in filters.fuelTypes.sorted() {
                        bindValues.append((Int32(bindIndex), fuelType))
                        bindIndex += 1
                    }
                }

                // Add age range filter
                if !filters.ageRanges.isEmpty {
                    var ageConditions: [String] = []
                    for ageRange in filters.ageRanges {
                        if let maxAge = ageRange.maxAge {
                            // Age range with both min and max
                            ageConditions.append("(year - model_year >= ? AND year - model_year <= ?)")
                            bindValues.append((Int32(bindIndex), ageRange.minAge))
                            bindIndex += 1
                            bindValues.append((Int32(bindIndex), maxAge))
                            bindIndex += 1
                        } else {
                            // Age range with only minimum (no upper limit)
                            ageConditions.append("(year - model_year >= ?)")
                            bindValues.append((Int32(bindIndex), ageRange.minAge))
                            bindIndex += 1
                        }
                    }

                    if !ageConditions.isEmpty {
                        // Only include vehicles where model_year is not null
                        query += " AND model_year IS NOT NULL AND (\(ageConditions.joined(separator: " OR ")))"
                    }
                }

                // Group by year and order
                query += " GROUP BY year ORDER BY year"

                // Debug output
                print("Query: \(query)")
                print("Bind values: \(bindValues)")

                var stmt: OpaquePointer?
                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
                    if let errorMessage = sqlite3_errmsg(db) {
                        continuation.resume(throwing: DatabaseError.queryFailed(String(cString: errorMessage)))
                    } else {
                        continuation.resume(throwing: DatabaseError.queryFailed("Unknown error"))
                    }
                    return
                }

                // Bind values
                for (index, value) in bindValues {
                    switch value {
                    case let intValue as Int:
                        sqlite3_bind_int(stmt, index, Int32(intValue))
                    case let stringValue as String:
                        sqlite3_bind_text(stmt, index, stringValue, -1, SQLITE_TRANSIENT)
                    default:
                        break
                    }
                }

                // Execute query and collect results
                var points: [TimeSeriesPoint] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let year = Int(sqlite3_column_int(stmt, 0))
                    let value = sqlite3_column_double(stmt, 1)  // Use double for averages
                    points.append(TimeSeriesPoint(year: year, value: value, label: nil))
                }

                // Handle percentage calculations with dual queries
                if filters.metricType == .percentage {
                    // Points now contain the numerator counts, we need to get baseline counts
                    Task {
                        do {
                            let percentagePoints = try await self?.calculatePercentagePoints(
                                numeratorPoints: points,
                                baselineFilters: filters.percentageBaseFilters,
                                db: db
                            ) ?? []

                            let series = await MainActor.run {
                                FilteredDataSeries(name: seriesName, filters: filters, points: percentagePoints)
                            }
                            continuation.resume(returning: series)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                } else {
                    // Create series with the proper name (already resolved)
                    let series = FilteredDataSeries(name: seriesName, filters: filters, points: points)
                    continuation.resume(returning: series)
                }
            }
        }
    }

    /// Queries license data based on filters
    func queryLicenseData(filters: FilterConfiguration) async throws -> FilteredDataSeries {
        // First, generate the proper series name
        let seriesName = await generateSeriesNameAsync(from: filters)

        return try await withCheckedThrowingContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }

                // Build dynamic query based on filters and metric type
                var query: String

                // Build SELECT clause based on metric type
                switch filters.metricType {
                case .count:
                    query = "SELECT year, COUNT(*) as value FROM licenses WHERE 1=1"

                case .sum:
                    // For licenses, sum operations are typically counts of license classes
                    if filters.metricField == .licenseClassCount {
                        // Count total license classes held by each person
                        query = """
                            SELECT year, SUM(
                                has_learner_permit_123 + has_learner_permit_5 + has_learner_permit_6a6r +
                                has_driver_license_1234 + has_driver_license_5 + has_driver_license_6abce +
                                has_driver_license_6d + has_driver_license_8
                            ) as value FROM licenses WHERE 1=1
                            """
                    } else {
                        // Fallback to count
                        query = "SELECT year, COUNT(*) as value FROM licenses WHERE 1=1"
                    }

                case .average:
                    // For licenses, average operations are typically average license classes per person
                    if filters.metricField == .licenseClassCount {
                        query = """
                            SELECT year, AVG(
                                has_learner_permit_123 + has_learner_permit_5 + has_learner_permit_6a6r +
                                has_driver_license_1234 + has_driver_license_5 + has_driver_license_6abce +
                                has_driver_license_6d + has_driver_license_8
                            ) as value FROM licenses WHERE 1=1
                            """
                    } else {
                        // Fallback to count
                        query = "SELECT year, COUNT(*) as value FROM licenses WHERE 1=1"
                    }

                case .percentage:
                    // For percentage, we need to do dual queries - this is handled separately
                    query = "SELECT year, COUNT(*) as value FROM licenses WHERE 1=1"
                }

                var bindIndex = 1
                var bindValues: [(Int32, Any)] = []

                // Add year filter
                if !filters.years.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.years.count).joined(separator: ",")
                    query += " AND year IN (\(placeholders))"
                    for year in filters.years.sorted() {
                        bindValues.append((Int32(bindIndex), year))
                        bindIndex += 1
                    }
                }

                // Add region filter
                if !filters.regions.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.regions.count).joined(separator: ",")
                    query += " AND admin_region IN (\(placeholders))"
                    for region in filters.regions.sorted() {
                        bindValues.append((Int32(bindIndex), region))
                        bindIndex += 1
                    }
                }

                // Add MRC filter
                if !filters.mrcs.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.mrcs.count).joined(separator: ",")
                    query += " AND mrc IN (\(placeholders))"
                    for mrc in filters.mrcs.sorted() {
                        bindValues.append((Int32(bindIndex), mrc))
                        bindIndex += 1
                    }
                }

                // Add license type filter
                if !filters.licenseTypes.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.licenseTypes.count).joined(separator: ",")
                    query += " AND license_type IN (\(placeholders))"
                    for licenseType in filters.licenseTypes.sorted() {
                        bindValues.append((Int32(bindIndex), licenseType))
                        bindIndex += 1
                    }
                }

                // Add age group filter
                if !filters.ageGroups.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.ageGroups.count).joined(separator: ",")
                    query += " AND age_group IN (\(placeholders))"
                    for ageGroup in filters.ageGroups.sorted() {
                        bindValues.append((Int32(bindIndex), ageGroup))
                        bindIndex += 1
                    }
                }

                // Add gender filter
                if !filters.genders.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.genders.count).joined(separator: ",")
                    query += " AND gender IN (\(placeholders))"
                    for gender in filters.genders.sorted() {
                        bindValues.append((Int32(bindIndex), gender))
                        bindIndex += 1
                    }
                }

                // Add experience level filter
                if !filters.experienceLevels.isEmpty {
                    var expConditions: [String] = []
                    for experience in filters.experienceLevels {
                        // Check all experience fields for the given level
                        expConditions.append("(experience_1234 = ? OR experience_5 = ? OR experience_6abce = ? OR experience_global = ?)")
                        for _ in 0..<4 {
                            bindValues.append((Int32(bindIndex), experience))
                            bindIndex += 1
                        }
                    }
                    if !expConditions.isEmpty {
                        query += " AND (\(expConditions.joined(separator: " OR ")))"
                    }
                }

                // Add license class filter (this is complex since it involves multiple boolean columns)
                if !filters.licenseClasses.isEmpty {
                    var classConditions: [String] = []
                    for licenseClass in filters.licenseClasses {
                        switch licenseClass {
                        case "learner_123":
                            classConditions.append("has_learner_permit_123 = 1")
                        case "learner_5":
                            classConditions.append("has_learner_permit_5 = 1")
                        case "learner_6a6r":
                            classConditions.append("has_learner_permit_6a6r = 1")
                        case "license_1234":
                            classConditions.append("has_driver_license_1234 = 1")
                        case "license_5":
                            classConditions.append("has_driver_license_5 = 1")
                        case "license_6abce":
                            classConditions.append("has_driver_license_6abce = 1")
                        case "license_6d":
                            classConditions.append("has_driver_license_6d = 1")
                        case "license_8":
                            classConditions.append("has_driver_license_8 = 1")
                        case "probationary":
                            classConditions.append("is_probationary = 1")
                        default:
                            break
                        }
                    }
                    if !classConditions.isEmpty {
                        query += " AND (\(classConditions.joined(separator: " OR ")))"
                    }
                }

                // Group by year and order
                query += " GROUP BY year ORDER BY year"

                // Debug output
                print("License Query: \(query)")
                print("Bind values: \(bindValues)")


                var stmt: OpaquePointer?
                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
                    if let errorMessage = sqlite3_errmsg(db) {
                        continuation.resume(throwing: DatabaseError.queryFailed(String(cString: errorMessage)))
                    } else {
                        continuation.resume(throwing: DatabaseError.queryFailed("Unknown error"))
                    }
                    return
                }

                // Bind values
                for (index, value) in bindValues {
                    switch value {
                    case let intValue as Int:
                        sqlite3_bind_int(stmt, index, Int32(intValue))
                    case let stringValue as String:
                        sqlite3_bind_text(stmt, index, stringValue, -1, SQLITE_TRANSIENT)
                    default:
                        break
                    }
                }

                // Execute query and collect results
                var points: [TimeSeriesPoint] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let year = Int(sqlite3_column_int(stmt, 0))
                    let value = sqlite3_column_double(stmt, 1)  // Use double for averages
                    points.append(TimeSeriesPoint(year: year, value: value, label: nil))
                }

                // Handle percentage calculations with dual queries
                if filters.metricType == .percentage {
                    // Points now contain the numerator counts, we need to get baseline counts
                    Task {
                        do {
                            let percentagePoints = try await self?.calculatePercentagePoints(
                                numeratorPoints: points,
                                baselineFilters: filters.percentageBaseFilters,
                                db: db
                            ) ?? []

                            let series = await MainActor.run {
                                FilteredDataSeries(name: seriesName, filters: filters, points: percentagePoints)
                            }
                            continuation.resume(returning: series)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                } else {
                    // Create series with the proper name (already resolved)
                    let series = FilteredDataSeries(name: seriesName, filters: filters, points: points)
                    continuation.resume(returning: series)
                }
            }
        }
    }

    /// Calculate percentage points by comparing numerator and baseline counts
    private func calculatePercentagePoints(
        numeratorPoints: [TimeSeriesPoint],
        baselineFilters: PercentageBaseFilters?,
        db: OpaquePointer
    ) async throws -> [TimeSeriesPoint] {
        guard let baselineFilters = baselineFilters else {
            // If no baseline specified, return 100% for all points
            return numeratorPoints.map { point in
                TimeSeriesPoint(year: point.year, value: 100.0, label: point.label)
            }
        }

        // Query baseline counts for the same years using the appropriate data type
        let baselineConfig = baselineFilters.toFilterConfiguration()
        let baselineSeries = try await queryData(filters: baselineConfig)
        let baselinePoints = baselineSeries.points

        // Create a dictionary for quick lookup of baseline values by year
        let baselineLookup = Dictionary(
            uniqueKeysWithValues: baselinePoints.map { ($0.year, $0.value) }
        )

        // Calculate percentages
        var percentagePoints: [TimeSeriesPoint] = []
        for numeratorPoint in numeratorPoints {
            let year = numeratorPoint.year
            let numerator = numeratorPoint.value

            if let baseline = baselineLookup[year], baseline > 0 {
                let percentage = (numerator / baseline) * 100.0
                percentagePoints.append(
                    TimeSeriesPoint(year: year, value: percentage, label: numeratorPoint.label)
                )
            } else {
                // No baseline data for this year, or baseline is zero
                percentagePoints.append(
                    TimeSeriesPoint(year: year, value: 0.0, label: numeratorPoint.label)
                )
            }
        }

        return percentagePoints
    }

    /// Generates a descriptive name for a data series based on filters (async version with municipality name lookup)
    private func generateSeriesNameAsync(from filters: FilterConfiguration) async -> String {
        var components: [String] = []

        // Add metric information if not count
        if filters.metricType != .count {
            var metricLabel = filters.metricType.shortLabel
            if filters.metricType == .sum || filters.metricType == .average {
                metricLabel += " \(filters.metricField.rawValue)"
                if let unit = filters.metricField.unit {
                    metricLabel += " (\(unit))"
                }
            } else if filters.metricType == .percentage {
                // For percentage, put the specific category first, then "in" baseline
                if let baseFilters = filters.percentageBaseFilters {
                    let droppedCategory = determineDifference(original: filters, baseline: baseFilters)
                    let specificValue = getSpecificCategoryValue(filters: filters, droppedCategory: droppedCategory)
                    let baselineDesc = await generateBaselineDescription(baseFilters: baseFilters, originalFilters: filters)

                    if let specific = specificValue {
                        // Return complete percentage description - no need to add other components
                        return "% [\(specific)] in [\(baselineDesc)]"
                    } else {
                        return "% of [\(baselineDesc)]"
                    }
                } else {
                    return "% of All Vehicles"
                }
            }
            components.append(metricLabel)
        }

        if !filters.vehicleClassifications.isEmpty {
            let classifications = filters.vehicleClassifications
                .compactMap { VehicleClassification(rawValue: $0)?.description }
                .joined(separator: " OR ")
            if !classifications.isEmpty {
                components.append("[\(classifications)]")
            }
        }

        if !filters.vehicleMakes.isEmpty {
            let makes = Array(filters.vehicleMakes).sorted().prefix(3).joined(separator: " OR ")
            let suffix = filters.vehicleMakes.count > 3 ? " (+\(filters.vehicleMakes.count - 3))" : ""
            components.append("[Make: \(makes)\(suffix)]")
        }

        if !filters.vehicleModels.isEmpty {
            let models = Array(filters.vehicleModels).sorted().prefix(3).joined(separator: " OR ")
            let suffix = filters.vehicleModels.count > 3 ? " (+\(filters.vehicleModels.count - 3))" : ""
            components.append("[Model: \(models)\(suffix)]")
        }

        if !filters.vehicleColors.isEmpty {
            let colors = Array(filters.vehicleColors).sorted().prefix(3).joined(separator: " OR ")
            let suffix = filters.vehicleColors.count > 3 ? " (+\(filters.vehicleColors.count - 3))" : ""
            components.append("[Color: \(colors)\(suffix)]")
        }

        if !filters.modelYears.isEmpty {
            let years = Array(filters.modelYears).sorted(by: >).prefix(3).map { String($0) }.joined(separator: " OR ")
            let suffix = filters.modelYears.count > 3 ? " (+\(filters.modelYears.count - 3))" : ""
            components.append("[Model Year: \(years)\(suffix)]")
        }

        if !filters.fuelTypes.isEmpty {
            let fuels = filters.fuelTypes
                .compactMap { FuelType(rawValue: $0)?.description }
                .joined(separator: " OR ")
            if !fuels.isEmpty {
                components.append("[\(fuels)]")
            }
        }

        if !filters.regions.isEmpty {
            components.append("[Region: \(filters.regions.joined(separator: " OR "))]")
        } else if !filters.mrcs.isEmpty {
            components.append("[MRC: \(filters.mrcs.joined(separator: " OR "))]")
        } else if !filters.municipalities.isEmpty {
            // Convert municipality codes to names for display
            let codeToName = await getMunicipalityCodeToNameMapping()
            let municipalityNames = filters.municipalities.compactMap { code in
                codeToName[code] ?? code  // Fallback to code if name not found
            }
            components.append("[Municipality: \(municipalityNames.joined(separator: " OR "))]")
        }

        // License-specific filters
        if !filters.licenseTypes.isEmpty {
            let types = filters.licenseTypes
                .compactMap { LicenseType(rawValue: $0)?.description }
                .joined(separator: " OR ")
            if !types.isEmpty {
                components.append("[License Type: \(types)]")
            } else {
                // Fallback to raw values if enum lookup fails
                components.append("[License Type: \(Array(filters.licenseTypes).sorted().joined(separator: " OR "))]")
            }
        }

        if !filters.ageGroups.isEmpty {
            let groups = filters.ageGroups
                .compactMap { AgeGroup(rawValue: $0)?.description }
                .joined(separator: " OR ")
            if !groups.isEmpty {
                components.append("[Age Group: \(groups)]")
            } else {
                // Fallback to raw values if enum lookup fails
                components.append("[Age Group: \(Array(filters.ageGroups).sorted().joined(separator: " OR "))]")
            }
        }

        if !filters.genders.isEmpty {
            let genders = filters.genders
                .compactMap { Gender(rawValue: $0)?.description }
                .joined(separator: " OR ")
            if !genders.isEmpty {
                components.append("[Gender: \(genders)]")
            } else {
                // Fallback to raw values if enum lookup fails
                components.append("[Gender: \(Array(filters.genders).sorted().joined(separator: " OR "))]")
            }
        }

        if !filters.experienceLevels.isEmpty {
            let levels = filters.experienceLevels
                .compactMap { ExperienceLevel(rawValue: $0)?.description }
                .joined(separator: " OR ")
            if !levels.isEmpty {
                components.append("[Experience: \(levels)]")
            } else {
                // Fallback to raw values if enum lookup fails
                components.append("[Experience: \(Array(filters.experienceLevels).sorted().joined(separator: " OR "))]")
            }
        }

        if !filters.licenseClasses.isEmpty {
            let classes = Array(filters.licenseClasses).sorted().joined(separator: " OR ")
            components.append("[License Classes: \(classes)]")
        }

        // Return appropriate default based on data entity type
        if components.isEmpty {
            return filters.dataEntityType == .license ? "All License Holders" : "All Vehicles"
        } else {
            return components.joined(separator: " AND ")
        }
    }

    /// Generate a description of what the percentage baseline represents
    private func generateBaselineDescription(baseFilters: PercentageBaseFilters, originalFilters: FilterConfiguration) async -> String {
        var baseComponents: [String] = []

        // Determine which category was dropped by comparing baseline with original
        let _ = determineDifference(original: originalFilters, baseline: baseFilters)

        if !baseFilters.vehicleClassifications.isEmpty {
            let classifications = baseFilters.vehicleClassifications
                .compactMap { VehicleClassification(rawValue: $0)?.description }
                .joined(separator: " OR ")
            if !classifications.isEmpty {
                baseComponents.append("[\(classifications)]")
            }
        }

        if !baseFilters.fuelTypes.isEmpty {
            let fuels = baseFilters.fuelTypes
                .compactMap { FuelType(rawValue: $0)?.description }
                .joined(separator: " OR ")
            if !fuels.isEmpty {
                baseComponents.append("[\(fuels)]")
            }
        }

        if !baseFilters.regions.isEmpty {
            baseComponents.append("[Region: \(baseFilters.regions.joined(separator: " OR "))]")
        }

        if !baseFilters.vehicleMakes.isEmpty {
            let makes = Array(baseFilters.vehicleMakes).sorted().prefix(3).joined(separator: " OR ")
            let suffix = baseFilters.vehicleMakes.count > 3 ? " (+\(baseFilters.vehicleMakes.count - 3))" : ""
            baseComponents.append("[Make: \(makes)\(suffix)]")
        }

        if !baseFilters.vehicleModels.isEmpty {
            let models = Array(baseFilters.vehicleModels).sorted().prefix(3).joined(separator: " OR ")
            let suffix = baseFilters.vehicleModels.count > 3 ? " (+\(baseFilters.vehicleModels.count - 3))" : ""
            baseComponents.append("[Model: \(models)\(suffix)]")
        }

        if !baseFilters.vehicleColors.isEmpty {
            let colors = Array(baseFilters.vehicleColors).sorted().prefix(3).joined(separator: " OR ")
            let suffix = baseFilters.vehicleColors.count > 3 ? " (+\(baseFilters.vehicleColors.count - 3))" : ""
            baseComponents.append("[Color: \(colors)\(suffix)]")
        }

        // License-specific filters for baseline description
        if !baseFilters.licenseTypes.isEmpty {
            let types = baseFilters.licenseTypes
                .compactMap { LicenseType(rawValue: $0)?.description }
                .joined(separator: " OR ")
            if !types.isEmpty {
                baseComponents.append("[License Type: \(types)]")
            } else {
                // Fallback to raw values if enum lookup fails
                baseComponents.append("[License Type: \(Array(baseFilters.licenseTypes).sorted().joined(separator: " OR "))]")
            }
        }

        if !baseFilters.ageGroups.isEmpty {
            let groups = baseFilters.ageGroups
                .compactMap { AgeGroup(rawValue: $0)?.description }
                .joined(separator: " OR ")
            if !groups.isEmpty {
                baseComponents.append("[Age Group: \(groups)]")
            } else {
                // Fallback to raw values if enum lookup fails
                baseComponents.append("[Age Group: \(Array(baseFilters.ageGroups).sorted().joined(separator: " OR "))]")
            }
        }

        if !baseFilters.genders.isEmpty {
            let genders = baseFilters.genders
                .compactMap { Gender(rawValue: $0)?.description }
                .joined(separator: " OR ")
            if !genders.isEmpty {
                baseComponents.append("[Gender: \(genders)]")
            } else {
                // Fallback to raw values if enum lookup fails
                baseComponents.append("[Gender: \(Array(baseFilters.genders).sorted().joined(separator: " OR "))]")
            }
        }

        if !baseFilters.experienceLevels.isEmpty {
            let levels = baseFilters.experienceLevels
                .compactMap { ExperienceLevel(rawValue: $0)?.description }
                .joined(separator: " OR ")
            if !levels.isEmpty {
                baseComponents.append("[Experience: \(levels)]")
            } else {
                // Fallback to raw values if enum lookup fails
                baseComponents.append("[Experience: \(Array(baseFilters.experienceLevels).sorted().joined(separator: " OR "))]")
            }
        }

        if !baseFilters.licenseClasses.isEmpty {
            let classes = Array(baseFilters.licenseClasses).sorted().joined(separator: " OR ")
            baseComponents.append("[License Classes: \(classes)]")
        }

        // Return appropriate default based on data entity type
        let baseDescription = if baseComponents.isEmpty {
            baseFilters.dataEntityType == .license ? "All License Holders" : "All Vehicles"
        } else {
            baseComponents.joined(separator: " AND ")
        }
        return baseDescription
    }

    /// Determine which filter category was dropped when creating percentage baseline
    private func determineDifference(original: FilterConfiguration, baseline: PercentageBaseFilters) -> String? {
        if !original.fuelTypes.isEmpty && baseline.fuelTypes.isEmpty {
            return "fuel types"
        }
        if !original.vehicleClassifications.isEmpty && baseline.vehicleClassifications.isEmpty {
            return "vehicle types"
        }
        if !original.regions.isEmpty && baseline.regions.isEmpty {
            return "regions"
        }
        if !original.vehicleMakes.isEmpty && baseline.vehicleMakes.isEmpty {
            return "makes"
        }
        if !original.vehicleModels.isEmpty && baseline.vehicleModels.isEmpty {
            return "models"
        }
        if !original.vehicleColors.isEmpty && baseline.vehicleColors.isEmpty {
            return "colors"
        }
        if !original.modelYears.isEmpty && baseline.modelYears.isEmpty {
            return "model years"
        }
        if !original.mrcs.isEmpty && baseline.mrcs.isEmpty {
            return "MRCs"
        }
        if !original.municipalities.isEmpty && baseline.municipalities.isEmpty {
            return "municipalities"
        }
        if !original.ageRanges.isEmpty && baseline.ageRanges.isEmpty {
            return "age ranges"
        }
        // License-specific filter differences
        if !original.licenseTypes.isEmpty && baseline.licenseTypes.isEmpty {
            return "license types"
        }
        if !original.ageGroups.isEmpty && baseline.ageGroups.isEmpty {
            return "age groups"
        }
        if !original.genders.isEmpty && baseline.genders.isEmpty {
            return "genders"
        }
        if !original.experienceLevels.isEmpty && baseline.experienceLevels.isEmpty {
            return "experience levels"
        }
        if !original.licenseClasses.isEmpty && baseline.licenseClasses.isEmpty {
            return "license classes"
        }
        return nil
    }

    /// Get the specific value for the category that was dropped for percentage calculation
    private func getSpecificCategoryValue(filters: FilterConfiguration, droppedCategory: String?) -> String? {
        guard let dropped = droppedCategory else { return nil }

        switch dropped {
        case "fuel types":
            if filters.fuelTypes.count == 1, let fuelType = filters.fuelTypes.first {
                return FuelType(rawValue: fuelType)?.description ?? fuelType
            } else if !filters.fuelTypes.isEmpty {
                let fuels = filters.fuelTypes.compactMap { FuelType(rawValue: $0)?.description }.joined(separator: " & ")
                return fuels.isEmpty ? nil : fuels
            }
        case "vehicle types":
            if filters.vehicleClassifications.count == 1, let classification = filters.vehicleClassifications.first {
                return VehicleClassification(rawValue: classification)?.description ?? classification
            } else if !filters.vehicleClassifications.isEmpty {
                let classifications = filters.vehicleClassifications.compactMap { VehicleClassification(rawValue: $0)?.description }.joined(separator: " & ")
                return classifications.isEmpty ? nil : classifications
            }
        case "regions":
            if filters.regions.count == 1 {
                return "Region \(filters.regions.first!)"
            } else if !filters.regions.isEmpty {
                return "Regions \(filters.regions.joined(separator: " & "))"
            }
        case "makes":
            if filters.vehicleMakes.count == 1 {
                return filters.vehicleMakes.first!
            } else if !filters.vehicleMakes.isEmpty {
                let makes = Array(filters.vehicleMakes).sorted().prefix(2).joined(separator: " & ")
                let suffix = filters.vehicleMakes.count > 2 ? " & Others" : ""
                return "\(makes)\(suffix)"
            }
        case "models":
            if filters.vehicleModels.count == 1 {
                return filters.vehicleModels.first!
            } else if !filters.vehicleModels.isEmpty {
                let models = Array(filters.vehicleModels).sorted().prefix(2).joined(separator: " & ")
                let suffix = filters.vehicleModels.count > 2 ? " & Others" : ""
                return "\(models)\(suffix)"
            }
        case "colors":
            if filters.vehicleColors.count == 1 {
                return filters.vehicleColors.first!
            } else if !filters.vehicleColors.isEmpty {
                let colors = Array(filters.vehicleColors).sorted().prefix(2).joined(separator: " & ")
                let suffix = filters.vehicleColors.count > 2 ? " & Others" : ""
                return "\(colors)\(suffix)"
            }
        case "model years":
            if filters.modelYears.count == 1 {
                return "\(filters.modelYears.first!) Model Year"
            } else if !filters.modelYears.isEmpty {
                let years = Array(filters.modelYears).sorted().prefix(3).map(String.init).joined(separator: " & ")
                let suffix = filters.modelYears.count > 3 ? " & Others" : ""
                return "\(years)\(suffix) Model Years"
            }
        case "license types":
            if filters.licenseTypes.count == 1, let licenseType = filters.licenseTypes.first {
                return LicenseType(rawValue: licenseType)?.description ?? licenseType
            } else if !filters.licenseTypes.isEmpty {
                let types = filters.licenseTypes.compactMap { LicenseType(rawValue: $0)?.description }.joined(separator: " & ")
                return types.isEmpty ? nil : types
            }
        case "age groups":
            if filters.ageGroups.count == 1, let ageGroup = filters.ageGroups.first {
                return AgeGroup(rawValue: ageGroup)?.description ?? ageGroup
            } else if !filters.ageGroups.isEmpty {
                let groups = filters.ageGroups.compactMap { AgeGroup(rawValue: $0)?.description }.joined(separator: " & ")
                return groups.isEmpty ? nil : groups
            }
        case "genders":
            if filters.genders.count == 1, let gender = filters.genders.first {
                return Gender(rawValue: gender)?.description ?? gender
            } else if !filters.genders.isEmpty {
                let genders = filters.genders.compactMap { Gender(rawValue: $0)?.description }.joined(separator: " & ")
                return genders.isEmpty ? nil : genders
            }
        case "experience levels":
            if filters.experienceLevels.count == 1, let experience = filters.experienceLevels.first {
                return ExperienceLevel(rawValue: experience)?.description ?? experience
            } else if !filters.experienceLevels.isEmpty {
                let levels = filters.experienceLevels.compactMap { ExperienceLevel(rawValue: $0)?.description }.joined(separator: " & ")
                return levels.isEmpty ? nil : levels
            }
        case "license classes":
            if filters.licenseClasses.count == 1 {
                return "License Class \(filters.licenseClasses.first!)"
            } else if !filters.licenseClasses.isEmpty {
                let classes = Array(filters.licenseClasses).sorted().prefix(3).joined(separator: " & ")
                let suffix = filters.licenseClasses.count > 3 ? " & Others" : ""
                return "License Classes \(classes)\(suffix)"
            }
        default:
            break
        }

        return nil
    }

    /// Generates a descriptive name for a data series based on filters (legacy synchronous version)
    private func generateSeriesName(from filters: FilterConfiguration) -> String {
        var components: [String] = []

        // Add metric information if not count
        if filters.metricType != .count {
            var metricLabel = filters.metricType.shortLabel
            if filters.metricType == .sum || filters.metricType == .average {
                metricLabel += " \(filters.metricField.rawValue)"
                if let unit = filters.metricField.unit {
                    metricLabel += " (\(unit))"
                }
            }
            components.append(metricLabel)
        }

        if !filters.vehicleClassifications.isEmpty {
            let classifications = filters.vehicleClassifications
                .compactMap { VehicleClassification(rawValue: $0)?.description }
                .joined(separator: " OR ")
            if !classifications.isEmpty {
                components.append("[\(classifications)]")
            }
        }

        if !filters.vehicleMakes.isEmpty {
            let makes = Array(filters.vehicleMakes).sorted().prefix(3).joined(separator: " OR ")
            let suffix = filters.vehicleMakes.count > 3 ? " (+\(filters.vehicleMakes.count - 3))" : ""
            components.append("[Make: \(makes)\(suffix)]")
        }

        if !filters.vehicleModels.isEmpty {
            let models = Array(filters.vehicleModels).sorted().prefix(3).joined(separator: " OR ")
            let suffix = filters.vehicleModels.count > 3 ? " (+\(filters.vehicleModels.count - 3))" : ""
            components.append("[Model: \(models)\(suffix)]")
        }

        if !filters.vehicleColors.isEmpty {
            let colors = Array(filters.vehicleColors).sorted().prefix(3).joined(separator: " OR ")
            let suffix = filters.vehicleColors.count > 3 ? " (+\(filters.vehicleColors.count - 3))" : ""
            components.append("[Color: \(colors)\(suffix)]")
        }

        if !filters.modelYears.isEmpty {
            let years = Array(filters.modelYears).sorted(by: >).prefix(3).map { String($0) }.joined(separator: " OR ")
            let suffix = filters.modelYears.count > 3 ? " (+\(filters.modelYears.count - 3))" : ""
            components.append("[Model Year: \(years)\(suffix)]")
        }

        if !filters.fuelTypes.isEmpty {
            let fuels = filters.fuelTypes
                .compactMap { FuelType(rawValue: $0)?.description }
                .joined(separator: " OR ")
            if !fuels.isEmpty {
                components.append("[\(fuels)]")
            }
        }

        if !filters.regions.isEmpty {
            components.append("[Region: \(filters.regions.joined(separator: " OR "))]")
        } else if !filters.mrcs.isEmpty {
            components.append("[MRC: \(filters.mrcs.joined(separator: " OR "))]")
        } else if !filters.municipalities.isEmpty {
            // Use codes in series name (fallback for synchronous version)
            components.append("[Municipality: \(filters.municipalities.joined(separator: " OR "))]")
        }

        return components.isEmpty ? "All Vehicles" : components.joined(separator: " AND ")
    }
    
    /// Gets available years - uses cache when possible
    func getAvailableYears() async -> [Int] {
        print("🔍 getAvailableYears() - Cache status: \(filterCache.hasCachedData)")

        // Check cache first
        if filterCache.hasCachedData && !filterCache.needsRefresh(currentDataVersion: getPersistentDataVersion()) {
            let cached = filterCache.getCachedYears()
            if !cached.isEmpty {
                print("✅ Using cached years: \(cached.count) items")
                return cached
            }
        }

        // Fall back to database query
        print("📊 Querying years from database...")
        return await getYearsFromDatabase()
    }

    /// Gets available years for a specific data entity type
    func getAvailableYears(for dataType: DataEntityType) async -> [Int] {
        print("🔍 getAvailableYears(for: \(dataType)) - Data-type-aware query")

        // Check cache first
        if filterCache.hasCachedData(for: dataType) && !filterCache.needsRefresh(currentDataVersion: getPersistentDataVersion()) {
            let cached = filterCache.getCachedYears(for: dataType)
            if !cached.isEmpty {
                print("✅ Using cached years (\(cached.count) items) for \(dataType)")
                return cached
            }
        }

        switch dataType {
        case .vehicle:
            return await getVehicleYearsFromDatabase()
        case .license:
            return await getLicenseYearsFromDatabase()
        }
    }
    
    /// Internal method to query years directly from database
    private func getYearsFromDatabase() async -> [Int] {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                // Query both vehicles and licenses tables, then merge unique values
                let query = """
                    SELECT DISTINCT year FROM (
                        SELECT year FROM vehicles
                        UNION
                        SELECT year FROM licenses
                    ) ORDER BY year
                    """
                var stmt: OpaquePointer?

                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                var years: [Int] = []
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        years.append(Int(sqlite3_column_int(stmt, 0)))
                    }
                }

                continuation.resume(returning: years)
            }
        }
    }
    
    /// Gets available regions - uses cache when possible
    func getAvailableRegions(for dataEntityType: DataEntityType = .vehicle) async -> [String] {
        print("🔍 getAvailableRegions() - Cache status: \(filterCache.hasCachedData(for: dataEntityType))")

        // Check cache first
        if filterCache.hasCachedData(for: dataEntityType) && !filterCache.needsRefresh(currentDataVersion: getPersistentDataVersion()) {
            let cached = filterCache.getCachedRegions(for: dataEntityType)
            if !cached.isEmpty {
                print("✅ Using cached regions (\(cached.count) items) for \(dataEntityType)")
                return cached
            }
        }

        // Fall back to database query
        print("📊 Querying regions from database for \(dataEntityType)...")
        return await getRegionsFromDatabase(for: dataEntityType)
    }
    
    /// Gets available MRCs - uses cache when possible
    func getAvailableMRCs(for dataEntityType: DataEntityType = .vehicle) async -> [String] {
        // Check cache first
        if filterCache.hasCachedData(for: dataEntityType) && !filterCache.needsRefresh(currentDataVersion: getPersistentDataVersion()) {
            let cached = filterCache.getCachedMRCs(for: dataEntityType)
            if !cached.isEmpty {
                print("✅ Using cached MRCs (\(cached.count) items) for \(dataEntityType)")
                return cached
            }
        }

        // Fall back to database query
        return await getMRCsFromDatabase(for: dataEntityType)
    }
    
    /// Prepares database for bulk import session
    func beginBulkImport() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume()
                    return
                }
                
                print("Preparing database for bulk import...")
                
                // Use smart indexing strategy based on database size
                let totalRecords = self?.getTotalRecordCount() ?? 0
                
                if totalRecords < 50_000_000 { // Less than 50M records - use current approach
                    print("Using traditional index management (database size: \(totalRecords.formatted()) records)")
                    // Temporarily disable indexes for faster inserts
                    sqlite3_exec(db, "DROP INDEX IF EXISTS idx_vehicles_year", nil, nil, nil)
                    sqlite3_exec(db, "DROP INDEX IF EXISTS idx_vehicles_classification", nil, nil, nil) 
                    sqlite3_exec(db, "DROP INDEX IF EXISTS idx_vehicles_geo", nil, nil, nil)
                    sqlite3_exec(db, "DROP INDEX IF EXISTS idx_vehicles_fuel", nil, nil, nil)
                    sqlite3_exec(db, "DROP INDEX IF EXISTS idx_vehicles_model_year", nil, nil, nil)
                } else {
                    print("Using incremental index management (database size: \(totalRecords.formatted()) records)")
                    // For large databases, keep indexes and use incremental approach
                    // Indexes will remain active, slightly slower inserts but much faster at the end
                }
                
                continuation.resume()
            }
        }
    }
    
    /// Completes bulk import session and rebuilds indexes
    func endBulkImport(progressManager: ImportProgressManager? = nil) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume()
                    return
                }
                
                let totalRecords = self?.getTotalRecordCount() ?? 0
                let indexStartTime = Date()
                
                if totalRecords < 50_000_000 {
                    print("🔧 Rebuilding indexes after bulk import...")
                    
                    // Rebuild indexes for query performance
                    sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_vehicles_year ON vehicles(year)", nil, nil, nil)
                    sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_vehicles_classification ON vehicles(classification)", nil, nil, nil)
                    sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_vehicles_geo ON vehicles(admin_region, mrc, geo_code)", nil, nil, nil)
                    sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_vehicles_fuel ON vehicles(fuel_type)", nil, nil, nil)
                    sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_vehicles_model_year ON vehicles(model_year)", nil, nil, nil)
                } else {
                    print("🔧 Optimizing indexes (incremental mode)...")
                    
                    // Update progress for incremental mode
                    Task { @MainActor in
                        progressManager?.updateIncrementalIndexing()
                    }
                    
                    // For large databases, just update statistics - indexes were never dropped
                    // This is much faster than rebuilding entire indexes
                }
                
                // Update statistics for query optimizer
                sqlite3_exec(db, "ANALYZE", nil, nil, nil)
                
                let indexTime = Date().timeIntervalSince(indexStartTime)
                print("✅ Database optimization complete (\(String(format: "%.1f", indexTime))s)")
                
                // Trigger UI refresh for filter options and refresh cache
                DispatchQueue.main.async { [weak self] in
                    self?.dataVersion += 1
                }
                
                // Refresh filter cache after data import
                Task { [weak self] in
                    await self?.refreshFilterCache()
                }
                
                continuation.resume()
            }
        }
    }
    
    /// Gets total record count for index management decisions
    private func getTotalRecordCount() -> Int {
        guard let db = db else { return 0 }
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        let sql = "SELECT COUNT(*) FROM vehicles"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        
        return 0
    }
    
    /// Gets available classifications - uses cache when possible
    func getAvailableClassifications() async -> [String] {
        // Check cache first
        if filterCache.hasCachedData && !filterCache.needsRefresh(currentDataVersion: getPersistentDataVersion()) {
            let cached = filterCache.getCachedClassifications()
            if !cached.isEmpty {
                return cached
            }
        }

        // Fall back to database query
        return await getClassificationsFromDatabase()
    }

    /// Gets available vehicle makes - uses cache when possible
    func getAvailableVehicleMakes() async -> [String] {
        // Check cache first
        if filterCache.hasCachedData && !filterCache.needsRefresh(currentDataVersion: getPersistentDataVersion()) {
            let cached = filterCache.getCachedVehicleMakes()
            if !cached.isEmpty {
                return cached
            }
        }

        // Fall back to database query
        return await getVehicleMakesFromDatabase()
    }

    /// Gets available vehicle models - uses cache when possible
    func getAvailableVehicleModels() async -> [String] {
        // Check cache first
        if filterCache.hasCachedData && !filterCache.needsRefresh(currentDataVersion: getPersistentDataVersion()) {
            let cached = filterCache.getCachedVehicleModels()
            if !cached.isEmpty {
                return cached
            }
        }

        // Fall back to database query
        return await getVehicleModelsFromDatabase()
    }

    /// Gets available model years - uses cache when possible
    func getAvailableModelYears() async -> [Int] {
        // Check cache first
        if filterCache.hasCachedData && !filterCache.needsRefresh(currentDataVersion: getPersistentDataVersion()) {
            let cached = filterCache.getCachedModelYears()
            if !cached.isEmpty {
                return cached
            }
        }

        // Fall back to database query
        return await getModelYearsFromDatabase()
    }

    /// Gets available vehicle colors - uses cache when possible
    func getAvailableVehicleColors() async -> [String] {
        // Check cache first
        if filterCache.hasCachedData && !filterCache.needsRefresh(currentDataVersion: getPersistentDataVersion()) {
            let cached = filterCache.getCachedVehicleColors()
            if !cached.isEmpty {
                return cached
            }
        }

        // Fall back to database query
        return await getVehicleColorsFromDatabase()
    }

    // MARK: - License Data Methods

    /// Gets available license types from database (cache-aware)
    func getAvailableLicenseTypes() async -> [String] {
        // Check cache first (only if license data is cached)
        if filterCache.hasCachedData && filterCache.hasLicenseDataCached && !filterCache.needsRefresh(currentDataVersion: getPersistentDataVersion()) {
            let cached = filterCache.getCachedLicenseTypes()
            if !cached.isEmpty {
                return cached
            }
        }

        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                var types: [String] = []
                let query = "SELECT DISTINCT license_type FROM licenses ORDER BY license_type"
                var stmt: OpaquePointer?

                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let typePtr = sqlite3_column_text(stmt, 0) {
                            types.append(String(cString: typePtr))
                        }
                    }
                }
                sqlite3_finalize(stmt)
                continuation.resume(returning: types)
            }
        }
    }

    /// Gets available age groups from database (cache-aware)
    func getAvailableAgeGroups() async -> [String] {
        // Check cache first (only if license data is cached)
        if filterCache.hasCachedData && filterCache.hasLicenseDataCached && !filterCache.needsRefresh(currentDataVersion: getPersistentDataVersion()) {
            let cached = filterCache.getCachedAgeGroups()
            if !cached.isEmpty {
                return cached
            }
        }

        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                var groups: [String] = []
                let query = "SELECT DISTINCT age_group FROM licenses ORDER BY age_group"
                var stmt: OpaquePointer?

                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let groupPtr = sqlite3_column_text(stmt, 0) {
                            groups.append(String(cString: groupPtr))
                        }
                    }
                }
                sqlite3_finalize(stmt)
                continuation.resume(returning: groups)
            }
        }
    }

    /// Gets available genders from database (cache-aware)
    func getAvailableGenders() async -> [String] {
        // Check cache first (only if license data is cached)
        if filterCache.hasCachedData && filterCache.hasLicenseDataCached && !filterCache.needsRefresh(currentDataVersion: getPersistentDataVersion()) {
            let cached = filterCache.getCachedGenders()
            if !cached.isEmpty {
                return cached
            }
        }

        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                var genders: [String] = []
                let query = "SELECT DISTINCT gender FROM licenses ORDER BY gender"
                var stmt: OpaquePointer?

                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let genderPtr = sqlite3_column_text(stmt, 0) {
                            genders.append(String(cString: genderPtr))
                        }
                    }
                }
                sqlite3_finalize(stmt)
                continuation.resume(returning: genders)
            }
        }
    }

    /// Gets available experience levels from database (cache-aware)
    func getAvailableExperienceLevels() async -> [String] {
        // Check cache first (only if license data is cached)
        if filterCache.hasCachedData && filterCache.hasLicenseDataCached && !filterCache.needsRefresh(currentDataVersion: getPersistentDataVersion()) {
            let cached = filterCache.getCachedExperienceLevels()
            if !cached.isEmpty {
                return cached
            }
        }

        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                var levels: [String] = []
                let query = "SELECT DISTINCT experience_level FROM licenses ORDER BY experience_level"
                var stmt: OpaquePointer?

                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let levelPtr = sqlite3_column_text(stmt, 0) {
                            levels.append(String(cString: levelPtr))
                        }
                    }
                }
                sqlite3_finalize(stmt)
                continuation.resume(returning: levels)
            }
        }
    }

    /// Gets available license classes from database (cache-aware)
    func getAvailableLicenseClasses() async -> [String] {
        // Check cache first (only if license data is cached)
        if filterCache.hasCachedData && filterCache.hasLicenseDataCached && !filterCache.needsRefresh(currentDataVersion: getPersistentDataVersion()) {
            let cached = filterCache.getCachedLicenseClasses()
            if !cached.isEmpty {
                return cached
            }
        }

        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                var classes: [String] = []
                let query = "SELECT DISTINCT license_class FROM licenses ORDER BY license_class"
                var stmt: OpaquePointer?

                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let classPtr = sqlite3_column_text(stmt, 0) {
                            classes.append(String(cString: classPtr))
                        }
                    }
                }
                sqlite3_finalize(stmt)
                continuation.resume(returning: classes)
            }
        }
    }

    // MARK: - Filter Cache Management
    
    /// Refreshes the filter cache with current database values
    func refreshFilterCache() async {
        print("🔄 Refreshing filter cache...")
        let startTime = Date()

        // Query all filter values from database in parallel
        async let years = getYearsFromDatabase()
        async let regions = getRegionsFromBothTables()  // For backward compatibility
        async let mrcs = getMRCsFromBothTables()  // For backward compatibility
        async let vehicleRegions = getRegionsFromDatabase(for: .vehicle)
        async let vehicleMRCs = getMRCsFromDatabase(for: .vehicle)
        async let licenseRegions = getRegionsFromDatabase(for: .license)
        async let licenseMRCs = getMRCsFromDatabase(for: .license)
        async let municipalities = getMunicipalitiesFromDatabase()
        async let municipalityMapping = getMunicipalityCodeToNameMappingFromDatabase()
        async let classifications = getClassificationsFromDatabase()
        async let vehicleMakes = getVehicleMakesFromDatabase()
        async let vehicleModels = getVehicleModelsFromDatabase()
        async let vehicleColors = getVehicleColorsFromDatabase()
        async let modelYears = getModelYearsFromDatabase()
        async let licenseTypes = getAvailableLicenseTypes()
        async let ageGroups = getAvailableAgeGroups()
        async let genders = getAvailableGenders()
        async let experienceLevels = getAvailableExperienceLevels()
        async let licenseClasses = getAvailableLicenseClasses()
        async let databaseStats = getDatabaseStats()

        // Wait for all queries to complete
        let (yearsList, regionsList, mrcsList, vehicleRegionsList, vehicleMRCsList, licenseRegionsList, licenseMRCsList,
             municipalitiesList, municipalityMappingData, classificationsList, makesList, modelsList, colorsList,
             modelYearsList, licenseTypesList, ageGroupsList, gendersList, experienceLevelsList, licenseClassesList, dbStats) =
            await (years, regions, mrcs, vehicleRegions, vehicleMRCs, licenseRegions, licenseMRCs,
                   municipalities, municipalityMapping, classifications, vehicleMakes, vehicleModels, vehicleColors,
                   modelYears, licenseTypes, ageGroups, genders, experienceLevels, licenseClasses, databaseStats)

        let duration = Date().timeIntervalSince(startTime)
        print("🔄 Database queries completed in \(String(format: "%.2f", duration))s")
        print("🔄 Found: \(yearsList.count) years, \(regionsList.count) regions, \(mrcsList.count) MRCs, \(municipalitiesList.count) municipalities, \(classificationsList.count) classifications, \(makesList.count) makes, \(modelsList.count) models, \(colorsList.count) colors, \(modelYearsList.count) model years, \(licenseTypesList.count) license types, \(ageGroupsList.count) age groups, \(gendersList.count) genders, \(experienceLevelsList.count) experience levels, \(licenseClassesList.count) license classes")

        // Update separate caches
        filterCache.updateVehicleCache(
            years: yearsList,
            regions: vehicleRegionsList,
            mrcs: vehicleMRCsList,
            municipalities: municipalitiesList, // Use combined for now since municipalities are shared
            classifications: classificationsList,
            vehicleMakes: makesList,
            vehicleModels: modelsList,
            vehicleColors: colorsList,
            modelYears: modelYearsList
        )

        filterCache.updateLicenseCache(
            years: yearsList,
            regions: licenseRegionsList,
            mrcs: licenseMRCsList,
            municipalities: municipalitiesList, // Use combined for now since municipalities are shared
            licenseTypes: licenseTypesList,
            ageGroups: ageGroupsList,
            genders: gendersList,
            experienceLevels: experienceLevelsList,
            licenseClasses: licenseClassesList
        )

        filterCache.finalizeCacheUpdate(
            municipalityCodeToName: municipalityMappingData,
            databaseStats: dbStats,
            dataVersion: getPersistentDataVersion()
        )

        print("✅ Filter cache refresh completed")
    }
    
    /// Clears the filter cache (useful for troubleshooting)
    func clearFilterCache() {
        filterCache.clearCache()
    }
    
    /// Gets cache status information
    var filterCacheInfo: (hasCache: Bool, lastUpdated: Date?, itemCounts: (years: Int, regions: Int, mrcs: Int, classifications: Int, vehicleMakes: Int, vehicleModels: Int, vehicleColors: Int, modelYears: Int)) {
        return (
            hasCache: filterCache.hasCachedData,
            lastUpdated: filterCache.lastUpdated,
            itemCounts: (
                years: filterCache.getCachedYears().count,
                regions: filterCache.getCachedRegions().count,
                mrcs: filterCache.getCachedMRCs().count,
                classifications: filterCache.getCachedClassifications().count,
                vehicleMakes: filterCache.getCachedVehicleMakes().count,
                vehicleModels: filterCache.getCachedVehicleModels().count,
                vehicleColors: filterCache.getCachedVehicleColors().count,
                modelYears: filterCache.getCachedModelYears().count
            )
        )
    }

    /// Gets total vehicle count from database
    func getTotalVehicleCount() async -> Int {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: 0)
                    return
                }

                let query = "SELECT COUNT(*) FROM vehicles"
                var stmt: OpaquePointer?

                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                var count = 0
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        count = Int(sqlite3_column_int(stmt, 0))
                    }
                }

                continuation.resume(returning: count)
            }
        }
    }

    /// Gets total license count across all years
    private func getTotalLicenseCount() async -> Int {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: 0)
                    return
                }
                let query = "SELECT COUNT(*) FROM licenses"
                var stmt: OpaquePointer?
                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }
                var count = 0
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        count = Int(sqlite3_column_int(stmt, 0))
                    }
                }
                continuation.resume(returning: count)
            }
        }
    }

    /// Gets all years available in the license table
    private func getLicenseYearsFromDatabase() async -> [Int] {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }
                let query = "SELECT DISTINCT year FROM licenses ORDER BY year"
                var stmt: OpaquePointer?
                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }
                var years: [Int] = []
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        let year = Int(sqlite3_column_int(stmt, 0))
                        years.append(year)
                    }
                }
                continuation.resume(returning: years)
            }
        }
    }

    /// Gets all years available in the vehicles table
    private func getVehicleYearsFromDatabase() async -> [Int] {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }
                let query = "SELECT DISTINCT year FROM vehicles ORDER BY year"
                var stmt: OpaquePointer?
                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }
                var years: [Int] = []
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        let year = Int(sqlite3_column_int(stmt, 0))
                        years.append(year)
                    }
                }
                continuation.resume(returning: years)
            }
        }
    }

    /// Gets database file size in bytes
    func getDatabaseFileSize() async -> Int64 {
        guard let dbURL = databaseURL else { return 0 }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: dbURL.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            print("Error getting database file size: \(error)")
            return 0
        }
    }

    /// Gets database summary statistics
    func getDatabaseStats() async -> CachedDatabaseStats {
        // Vehicle statistics
        let totalVehicleRecords = await getTotalVehicleCount()
        let vehicleYears = await getYearsFromDatabase()
        let vehicleYearRange = vehicleYears.isEmpty ? "No data" : "\(vehicleYears.min()!) - \(vehicleYears.max()!)"

        // License statistics
        let totalLicenseRecords = await getTotalLicenseCount()
        let licenseYears = await getLicenseYearsFromDatabase()
        let licenseYearRange = licenseYears.isEmpty ? "No data" : "\(licenseYears.min()!) - \(licenseYears.max()!)"

        // Shared statistics
        let municipalities = await getMunicipalitiesFromDatabase()
        let regions = await getRegionsFromDatabase()
        let fileSize = await getDatabaseFileSize()

        return CachedDatabaseStats(
            totalVehicleRecords: totalVehicleRecords,
            vehicleYearRange: vehicleYearRange,
            availableVehicleYearsCount: vehicleYears.count,
            totalLicenseRecords: totalLicenseRecords,
            licenseYearRange: licenseYearRange,
            availableLicenseYearsCount: licenseYears.count,
            municipalities: municipalities.count,
            regions: regions.count,
            fileSizeBytes: fileSize,
            lastUpdated: Date()
        )
    }


    // MARK: - Cache Filtering Methods (Private)

    /// Filters cached regions to only include those present in the specified data entity type
    private func filterCachedRegionsByDataType(regions: [String], dataEntityType: DataEntityType) async -> [String] {
        // Use data-type-specific cached data if available
        let cachedRegions = filterCache.getCachedRegions(for: dataEntityType)
        return cachedRegions.isEmpty ? regions : cachedRegions
    }

    /// Filters cached MRCs to only include those present in the specified data entity type
    private func filterCachedMRCsByDataType(mrcs: [String], dataEntityType: DataEntityType) async -> [String] {
        // Use data-type-specific cached data if available
        let cachedMRCs = filterCache.getCachedMRCs(for: dataEntityType)
        return cachedMRCs.isEmpty ? mrcs : cachedMRCs
    }

    // MARK: - Database Query Methods (Private)

    /// Internal method to query regions from both tables (for cache refresh)
    private func getRegionsFromBothTables() async -> [String] {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                // Query both vehicles and licenses tables, then merge unique values
                let query = """
                    SELECT DISTINCT admin_region FROM (
                        SELECT admin_region FROM vehicles
                        UNION
                        SELECT admin_region FROM licenses
                    ) ORDER BY admin_region
                    """
                var stmt: OpaquePointer?

                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                var regions: [String] = []
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let regionPtr = sqlite3_column_text(stmt, 0) {
                            regions.append(String(cString: regionPtr))
                        }
                    }
                }

                continuation.resume(returning: regions)
            }
        }
    }

    /// Internal method to query MRCs from both tables (for cache refresh)
    private func getMRCsFromBothTables() async -> [String] {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                // Query both vehicles and licenses tables, then merge unique values
                let query = """
                    SELECT DISTINCT mrc FROM (
                        SELECT mrc FROM vehicles
                        UNION
                        SELECT mrc FROM licenses
                    ) ORDER BY mrc
                    """
                var stmt: OpaquePointer?

                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                var mrcs: [String] = []
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let mrcPtr = sqlite3_column_text(stmt, 0) {
                            mrcs.append(String(cString: mrcPtr))
                        }
                    }
                }

                continuation.resume(returning: mrcs)
            }
        }
    }
    
    /// Internal method to query regions directly from database
    private func getRegionsFromDatabase(for dataEntityType: DataEntityType = .vehicle) async -> [String] {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                // Query the appropriate table based on data entity type
                let tableName = dataEntityType == .license ? "licenses" : "vehicles"
                let query = "SELECT DISTINCT admin_region FROM \(tableName) ORDER BY admin_region"
                var stmt: OpaquePointer?

                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                var regions: [String] = []
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let regionPtr = sqlite3_column_text(stmt, 0) {
                            regions.append(String(cString: regionPtr))
                        }
                    }
                }

                continuation.resume(returning: regions)
            }
        }
    }
    
    /// Internal method to query MRCs directly from database
    private func getMRCsFromDatabase(for dataEntityType: DataEntityType = .vehicle) async -> [String] {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                // Query the appropriate table based on data entity type
                let tableName = dataEntityType == .license ? "licenses" : "vehicles"
                let query = "SELECT DISTINCT mrc FROM \(tableName) ORDER BY mrc"
                var stmt: OpaquePointer?

                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                var mrcs: [String] = []
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let mrcPtr = sqlite3_column_text(stmt, 0) {
                            mrcs.append(String(cString: mrcPtr))
                        }
                    }
                }

                continuation.resume(returning: mrcs)
            }
        }
    }
    
    /// Internal method to query classifications directly from database
    private func getClassificationsFromDatabase() async -> [String] {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }
                
                let query = "SELECT DISTINCT classification FROM vehicles ORDER BY classification"
                var stmt: OpaquePointer?
                
                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }
                
                var classifications: [String] = []
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let classPtr = sqlite3_column_text(stmt, 0) {
                            classifications.append(String(cString: classPtr))
                        }
                    }
                }
                
                continuation.resume(returning: classifications)
            }
        }
    }

    /// Query distinct vehicle makes from database
    private func getVehicleMakesFromDatabase() async -> [String] {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                let query = "SELECT DISTINCT make FROM vehicles WHERE make IS NOT NULL AND make != '' ORDER BY make"
                var stmt: OpaquePointer?

                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                var vehicleMakes: [String] = []
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let makePtr = sqlite3_column_text(stmt, 0) {
                            let make = String(cString: makePtr)
                            if !make.isEmpty {
                                vehicleMakes.append(make)
                            }
                        }
                    }
                }

                continuation.resume(returning: vehicleMakes)
            }
        }
    }

    /// Query distinct vehicle models from database
    private func getVehicleModelsFromDatabase() async -> [String] {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                let query = "SELECT DISTINCT model FROM vehicles WHERE model IS NOT NULL AND model != '' ORDER BY model"
                var stmt: OpaquePointer?

                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                var vehicleModels: [String] = []
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let modelPtr = sqlite3_column_text(stmt, 0) {
                            let model = String(cString: modelPtr)
                            if !model.isEmpty {
                                vehicleModels.append(model)
                            }
                        }
                    }
                }

                continuation.resume(returning: vehicleModels)
            }
        }
    }

    /// Query distinct model years from database
    private func getModelYearsFromDatabase() async -> [Int] {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                let query = "SELECT DISTINCT model_year FROM vehicles WHERE model_year IS NOT NULL ORDER BY model_year DESC"
                var stmt: OpaquePointer?

                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                var modelYears: [Int] = []
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        let year = Int(sqlite3_column_int(stmt, 0))
                        if year > 0 {  // Only include valid years
                            modelYears.append(year)
                        }
                    }
                }

                continuation.resume(returning: modelYears)
            }
        }
    }

    /// Query distinct vehicle colors from database
    private func getVehicleColorsFromDatabase() async -> [String] {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                let query = "SELECT DISTINCT original_color FROM vehicles WHERE original_color IS NOT NULL AND original_color != '' ORDER BY original_color"
                var stmt: OpaquePointer?

                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                var vehicleColors: [String] = []
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let colorPtr = sqlite3_column_text(stmt, 0) {
                            let color = String(cString: colorPtr)
                            if !color.isEmpty {
                                vehicleColors.append(color)
                            }
                        }
                    }
                }

                continuation.resume(returning: vehicleColors)
            }
        }
    }

    /// Gets available municipalities - uses cache when possible
    func getAvailableMunicipalities() async -> [String] {
        // Check cache first
        if filterCache.hasCachedData && !filterCache.needsRefresh(currentDataVersion: getPersistentDataVersion()) {
            let cached = filterCache.getCachedMunicipalities()
            if !cached.isEmpty {
                return cached
            }
        }
        
        // Fall back to database query
        return await getMunicipalitiesFromDatabase()
    }
    
    /// Internal method to query municipalities from database
    /// Returns geo_codes for filtering, but maintains name->code mapping for UI
    private func getMunicipalitiesFromDatabase() async -> [String] {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                // First try getting municipalities from geographic_entities table (code and name)
                var query = """
                    SELECT code, name
                    FROM geographic_entities
                    WHERE type = 'municipality'
                    ORDER BY name
                    """
                var stmt: OpaquePointer?

                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                var municipalities: [String] = []

                // Try geographic_entities first - return codes for filtering
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let codePtr = sqlite3_column_text(stmt, 0) {
                            municipalities.append(String(cString: codePtr))
                        }
                    }

                    // If we found municipalities in geographic_entities, use those codes
                    if !municipalities.isEmpty {
                        continuation.resume(returning: municipalities)
                        return
                    }
                }

                // Fall back to raw geo_code values from vehicles table
                sqlite3_finalize(stmt)
                stmt = nil

                query = "SELECT DISTINCT geo_code FROM vehicles ORDER BY geo_code"

                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let codePtr = sqlite3_column_text(stmt, 0) {
                            municipalities.append(String(cString: codePtr))
                        }
                    }
                }

                continuation.resume(returning: municipalities)
            }
        }
    }

    /// Gets municipality name-to-code mapping for UI display
    func getMunicipalityNameToCodeMapping() async -> [String: String] {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [:])
                    return
                }

                let query = """
                    SELECT code, name
                    FROM geographic_entities
                    WHERE type = 'municipality'
                    ORDER BY name
                    """
                var stmt: OpaquePointer?

                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                var mapping: [String: String] = [:]

                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let codePtr = sqlite3_column_text(stmt, 0),
                           let namePtr = sqlite3_column_text(stmt, 1) {
                            let code = String(cString: codePtr)
                            let name = String(cString: namePtr)
                            mapping[name] = code
                        }
                    }
                }

                continuation.resume(returning: mapping)
            }
        }
    }

    /// Gets municipality code-to-name mapping for UI display (cache-aware)
    func getMunicipalityCodeToNameMapping() async -> [String: String] {
        // Check cache first
        if filterCache.hasCachedData && !filterCache.needsRefresh(currentDataVersion: getPersistentDataVersion()) {
            let cached = filterCache.getCachedMunicipalityCodeToName()
            if !cached.isEmpty {
                return cached
            }
        }

        return await getMunicipalityCodeToNameMappingFromDatabase()
    }

    /// Gets municipality code-to-name mapping directly from database (for cache refresh)
    private func getMunicipalityCodeToNameMappingFromDatabase() async -> [String: String] {
        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [:])
                    return
                }

                let query = """
                    SELECT code, name
                    FROM geographic_entities
                    WHERE type = 'municipality'
                    ORDER BY name
                    """
                var stmt: OpaquePointer?

                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                var mapping: [String: String] = [:]

                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let codePtr = sqlite3_column_text(stmt, 0),
                           let namePtr = sqlite3_column_text(stmt, 1) {
                            let code = String(cString: codePtr)
                            let name = String(cString: namePtr)
                            mapping[code] = name
                        }
                    }
                }

                continuation.resume(returning: mapping)
            }
        }
    }
    
    /// Imports vehicle records in batch with transaction optimization
    func importVehicleBatch(_ records: [[String: String]], year: Int, importer: CSVImporter) async throws -> (success: Int, errors: Int) {
        return try await withCheckedThrowingContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }
                
                // Apply temporary performance optimizations for bulk import
                sqlite3_exec(db, "PRAGMA synchronous = OFF", nil, nil, nil)  // Risky but fast
                sqlite3_exec(db, "PRAGMA journal_mode = MEMORY", nil, nil, nil)  // Keep journal in memory
                sqlite3_exec(db, "PRAGMA cache_size = -2000000", nil, nil, nil)  // 2GB cache
                sqlite3_exec(db, "PRAGMA temp_store = MEMORY", nil, nil, nil)  // Temp tables in memory
                sqlite3_exec(db, "PRAGMA locking_mode = EXCLUSIVE", nil, nil, nil)  // Exclusive lock
                
                // Start transaction for massive performance improvement
                if sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) != SQLITE_OK {
                    if let errorMessage = sqlite3_errmsg(db) {
                        continuation.resume(throwing: DatabaseError.queryFailed("Failed to begin transaction: \(String(cString: errorMessage))"))
                    } else {
                        continuation.resume(throwing: DatabaseError.queryFailed("Failed to begin transaction"))
                    }
                    return
                }
                
                let insertSQL = """
                    INSERT OR REPLACE INTO vehicles (
                        year, vehicle_sequence, classification, vehicle_type, 
                        make, model, model_year, net_mass, cylinder_count, 
                        displacement, max_axles, original_color, fuel_type,
                        admin_region, mrc, geo_code
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """
                
                var stmt: OpaquePointer?
                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }
                
                guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
                    sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                    if let errorMessage = sqlite3_errmsg(db) {
                        continuation.resume(throwing: DatabaseError.queryFailed(String(cString: errorMessage)))
                    } else {
                        continuation.resume(throwing: DatabaseError.queryFailed("Failed to prepare statement"))
                    }
                    return
                }
                
                var successCount = 0
                var errorCount = 0
                
                // Debug: Log first record only
                if records.count > 0 && successCount == 0 {
                    print("Starting batch import: \(records.count) records for year \(year)")
                }
                
                for record in records {
                    // Map CSV fields to database columns
                    sqlite3_bind_int(stmt, 1, Int32(year))
                    importer.bindRequiredTextToStatement(stmt, 2, record["NOSEQ_VEH"], defaultValue: "\(year)_UNKNOWN")
                    importer.bindRequiredTextToStatement(stmt, 3, record["CLAS"], defaultValue: "UNK")
                    importer.bindTextToStatement(stmt, 4, record["TYP_VEH_CATEG_USA"])
                    importer.bindTextToStatement(stmt, 5, record["MARQ_VEH"])
                    importer.bindTextToStatement(stmt, 6, record["MODEL_VEH"])
                    
                    if let modelYear = record["ANNEE_MOD"], let year = Int32(modelYear) {
                        sqlite3_bind_int(stmt, 7, year)
                    } else {
                        sqlite3_bind_null(stmt, 7)
                    }
                    
                    importer.bindDoubleToStatement(stmt, 8, record["MASSE_NETTE"])
                    importer.bindIntToStatement(stmt, 9, record["NB_CYL"])
                    importer.bindDoubleToStatement(stmt, 10, record["CYL_VEH"])
                    importer.bindIntToStatement(stmt, 11, record["NB_ESIEU_MAX"])
                    importer.bindTextToStatement(stmt, 12, record["COUL_ORIG"])
                    importer.bindTextToStatement(stmt, 13, record["TYP_CARBU"])
                    importer.bindRequiredTextToStatement(stmt, 14, record["REG_ADM"], defaultValue: "Unknown Region")
                    importer.bindRequiredTextToStatement(stmt, 15, record["MRC"], defaultValue: "Unknown MRC") 
                    importer.bindRequiredTextToStatement(stmt, 16, record["CG_FIXE"], defaultValue: "00000")
                    
                    if sqlite3_step(stmt) == SQLITE_DONE {
                        successCount += 1
                    } else {
                        errorCount += 1
                        // On error, log it but continue
                        if let errorMessage = sqlite3_errmsg(db) {
                            if errorCount <= 5 { // Only log first 5 errors
                                print("Insert error: \(String(cString: errorMessage))")
                            }
                        }
                    }
                    
                    sqlite3_reset(stmt)
                }
                
                // Commit transaction
                if sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK {
                    // Restore safe settings after bulk import
                    sqlite3_exec(db, "PRAGMA synchronous = NORMAL", nil, nil, nil)
                    sqlite3_exec(db, "PRAGMA journal_mode = WAL", nil, nil, nil)
                    sqlite3_exec(db, "PRAGMA locking_mode = NORMAL", nil, nil, nil)
                    
                    continuation.resume(returning: (success: successCount, errors: errorCount))
                } else {
                    sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                    // Restore safe settings even on failure
                    sqlite3_exec(db, "PRAGMA synchronous = NORMAL", nil, nil, nil)
                    sqlite3_exec(db, "PRAGMA journal_mode = WAL", nil, nil, nil)
                    sqlite3_exec(db, "PRAGMA locking_mode = NORMAL", nil, nil, nil)
                    
                    if let errorMessage = sqlite3_errmsg(db) {
                        continuation.resume(throwing: DatabaseError.queryFailed("Failed to commit: \(String(cString: errorMessage))"))
                    } else {
                        continuation.resume(throwing: DatabaseError.queryFailed("Failed to commit transaction"))
                    }
                }
            }
        }
    }
    
    /// Executes import log statement
    func executeImportLog(_ sql: String, fileName: String, year: Int, recordCount: Int, status: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }
                
                var stmt: OpaquePointer?
                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }
                
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    if let errorMessage = sqlite3_errmsg(db) {
                        continuation.resume(throwing: DatabaseError.queryFailed(String(cString: errorMessage)))
                    } else {
                        continuation.resume(throwing: DatabaseError.queryFailed("Failed to prepare statement"))
                    }
                    return
                }
                
                sqlite3_bind_text(stmt, 1, fileName, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 2, Int32(year))
                sqlite3_bind_int(stmt, 3, Int32(recordCount))
                sqlite3_bind_text(stmt, 4, status, -1, SQLITE_TRANSIENT)
                
                if sqlite3_step(stmt) == SQLITE_DONE {
                    continuation.resume(returning: ())
                } else {
                    if let errorMessage = sqlite3_errmsg(db) {
                        continuation.resume(throwing: DatabaseError.queryFailed(String(cString: errorMessage)))
                    } else {
                        continuation.resume(throwing: DatabaseError.queryFailed("Failed to execute statement"))
                    }
                }
            }
        }
    }
    
    /// Inserts a geographic entity
    func insertGeographicEntity(code: String, name: String, type: String, parentCode: String?,
                               latitude: Double? = nil, longitude: Double? = nil,
                               areaTotal: Double? = nil, areaLand: Double? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }
                
                let sql = """
                    INSERT OR REPLACE INTO geographic_entities (
                        code, name, type, parent_code,
                        latitude, longitude, area_total, area_land
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """
                
                var stmt: OpaquePointer?
                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }
                
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    if let errorMessage = sqlite3_errmsg(db) {
                        continuation.resume(throwing: DatabaseError.queryFailed(String(cString: errorMessage)))
                    } else {
                        continuation.resume(throwing: DatabaseError.queryFailed("Failed to prepare statement"))
                    }
                    return
                }
                
                sqlite3_bind_text(stmt, 1, code, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, type, -1, SQLITE_TRANSIENT)
                
                if let parentCode = parentCode {
                    sqlite3_bind_text(stmt, 4, parentCode, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 4)
                }
                
                if let latitude = latitude {
                    sqlite3_bind_double(stmt, 5, latitude)
                } else {
                    sqlite3_bind_null(stmt, 5)
                }
                
                if let longitude = longitude {
                    sqlite3_bind_double(stmt, 6, longitude)
                } else {
                    sqlite3_bind_null(stmt, 6)
                }
                
                if let areaTotal = areaTotal {
                    sqlite3_bind_double(stmt, 7, areaTotal)
                } else {
                    sqlite3_bind_null(stmt, 7)
                }
                
                if let areaLand = areaLand {
                    sqlite3_bind_double(stmt, 8, areaLand)
                } else {
                    sqlite3_bind_null(stmt, 8)
                }
                
                if sqlite3_step(stmt) == SQLITE_DONE {
                    continuation.resume(returning: ())
                } else {
                    if let errorMessage = sqlite3_errmsg(db) {
                        continuation.resume(throwing: DatabaseError.queryFailed(String(cString: errorMessage)))
                    } else {
                        continuation.resume(throwing: DatabaseError.queryFailed("Failed to execute statement"))
                    }
                }
            }
        }
    }
}

/// Database-related errors
enum DatabaseError: LocalizedError {
    case notConnected
    case queryFailed(String)
    case importFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Database is not connected"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .importFailed(let message):
            return "Import failed: \(message)"
        }
    }
}

// MARK: - SQLite Helpers

/// Transient pointer for SQLite bindings
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
