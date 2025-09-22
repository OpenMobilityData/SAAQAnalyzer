import Foundation
import SQLite3
import Combine

/// Manages SQLite database operations for SAAQ data
class DatabaseManager: ObservableObject {
    /// Singleton instance
    static let shared = DatabaseManager()
    
    /// Database file URL
    @Published var databaseURL: URL?
    
    /// Triggers UI refresh when data changes
    @Published var dataVersion = 0
    
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
                
                let tables = ["vehicles", "geographic_entities", "import_log"]
                
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
            "CREATE INDEX IF NOT EXISTS idx_vehicles_year ON vehicles(year);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_classification ON vehicles(classification);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_geo ON vehicles(admin_region, mrc, geo_code);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_fuel ON vehicles(fuel_type);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_model_year ON vehicles(model_year);",
            "CREATE INDEX IF NOT EXISTS idx_geographic_type ON geographic_entities(type);",
            "CREATE INDEX IF NOT EXISTS idx_geographic_parent ON geographic_entities(parent_code);"
        ]
        
        dbQueue.async { [weak self] in
            guard let db = self?.db else { return }
            
            // Create tables
            for query in [createVehiclesTable, createGeographicTable, createImportLogTable] {
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
    
    /// Queries vehicle data based on filters
    func queryVehicleData(filters: FilterConfiguration) async throws -> FilteredDataSeries {
        return try await withCheckedThrowingContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }
                
                // Build dynamic query based on filters
                var query = """
                    SELECT year, COUNT(*) as count
                    FROM vehicles
                    WHERE 1=1
                    """
                
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
                    let count = Double(sqlite3_column_int(stmt, 1))
                    points.append(TimeSeriesPoint(year: year, value: count, label: nil))
                }
                
                // Create series name based on filters
                let seriesName = self?.generateSeriesName(from: filters) ?? "Vehicle Data"
                let series = FilteredDataSeries(name: seriesName, filters: filters, points: points)
                
                continuation.resume(returning: series)
            }
        }
    }
    
    /// Generates a descriptive name for a data series based on filters
    private func generateSeriesName(from filters: FilterConfiguration) -> String {
        var components: [String] = []
        
        if !filters.vehicleClassifications.isEmpty {
            let classifications = filters.vehicleClassifications
                .compactMap { VehicleClassification(rawValue: $0)?.description }
                .joined(separator: ", ")
            if !classifications.isEmpty {
                components.append(classifications)
            }
        }
        
        if !filters.fuelTypes.isEmpty {
            let fuels = filters.fuelTypes
                .compactMap { FuelType(rawValue: $0)?.description }
                .joined(separator: ", ")
            if !fuels.isEmpty {
                components.append(fuels)
            }
        }
        
        if !filters.regions.isEmpty {
            components.append("Region: \(filters.regions.joined(separator: ", "))")
        } else if !filters.mrcs.isEmpty {
            components.append("MRC: \(filters.mrcs.joined(separator: ", "))")
        } else if !filters.municipalities.isEmpty {
            components.append("Municipality: \(filters.municipalities.joined(separator: ", "))")
        }
        
        return components.isEmpty ? "All Vehicles" : components.joined(separator: " - ")
    }
    
    /// Gets available years in the database
    func getAvailableYears() async -> [Int] {
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
                        years.append(Int(sqlite3_column_int(stmt, 0)))
                    }
                }
                
                continuation.resume(returning: years)
            }
        }
    }
    
    /// Gets available regions from the database
    func getAvailableRegions() async -> [String] {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }
                
                let query = "SELECT DISTINCT admin_region FROM vehicles ORDER BY admin_region"
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
                            let region = String(cString: regionPtr)
                            regions.append(region)
                        }
                    }
                }
                
                continuation.resume(returning: regions)
            }
        }
    }
    
    /// Gets available MRCs from the database
    func getAvailableMRCs() async -> [String] {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }
                
                let query = "SELECT DISTINCT mrc FROM vehicles ORDER BY mrc"
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
                            let mrc = String(cString: mrcPtr)
                            mrcs.append(mrc)
                        }
                    }
                }
                
                continuation.resume(returning: mrcs)
            }
        }
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
                
                // Trigger UI refresh for filter options
                DispatchQueue.main.async { [weak self] in
                    self?.dataVersion += 1
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
    
    /// Gets available vehicle classifications from the database
    func getAvailableClassifications() async -> [String] {
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
                            let classification = String(cString: classPtr)
                            classifications.append(classification)
                        }
                    }
                }
                
                continuation.resume(returning: classifications)
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
