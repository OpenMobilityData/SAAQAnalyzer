import Foundation
import SQLite3
import Combine
import OSLog

/// Manages SQLite database operations for SAAQ data
class DatabaseManager: ObservableObject {
    /// Singleton instance
    static let shared = DatabaseManager()
    
    /// Database file URL
    @Published var databaseURL: URL?

    /// Triggers UI refresh when data changes - using database file timestamp for persistence
    @Published var dataVersion = 0

    /// Test database cleanup decision (for SwiftUI alert)
    @Published var testDatabaseCleanupNeeded: URL?

    /// Legacy filter cache (only used for clearing UserDefaults in test mode)
    private let filterCache = FilterCache()

    /// Filter cache manager (enumeration table-based)
    private(set) var filterCacheManager: FilterCacheManager?

    /// Schema migration manager
    private(set) var schemaManager: SchemaManager?

    /// Optimized query manager
    private(set) var optimizedQueryManager: OptimizedQueryManager?

    /// Regularization manager
    private(set) var regularizationManager: RegularizationManager?

    /// Flag to enable optimized integer-based queries
    private var useOptimizedQueries = true  // Default to optimized after migration

    /// Toggle between optimized and traditional queries for testing
    func setOptimizedQueriesEnabled(_ enabled: Bool) {
        useOptimizedQueries = enabled
        print(enabled ? "🚀 Optimized integer-based queries ENABLED" : "📊 Traditional string-based queries ENABLED")
    }

    /// SQLite database handle
    internal var db: OpaquePointer?
    
    /// Queue for database operations
    internal let dbQueue = DispatchQueue(label: "com.saaqanalyzer.database", qos: .userInitiated)

    /// Flag to prevent concurrent cache refreshes
    private var isRefreshingCache = false
    private let refreshLock = NSLock()

    private init() {
        setupDefaultDatabase()
    }
    
    deinit {
        closeDatabase()
    }
    
    /// Sets up default database location
    /// Supports SAAQ_TEST_MODE environment variable for testing package imports
    /// on a "fresh installation" without affecting production data (set in Xcode Scheme editor)
    private func setupDefaultDatabase() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let testDBPath = documentsPath.appendingPathComponent("saaq_data_test.sqlite")
        let isTestMode = ProcessInfo.processInfo.environment["SAAQ_TEST_MODE"] != nil

        // Check for test mode (simulates fresh installation for import testing)
        if isTestMode {
            // In test mode: check if database exists and prompt if needed
            // Do NOT open database yet - wait for user decision
            handleTestModeStartup(testDBPath: testDBPath)
        } else {
            // In normal mode: silently clean up any leftover test databases
            cleanupTestDatabase(testDBPath: testDBPath)

            // Use normal production path
            let dbPath = documentsPath.appendingPathComponent("saaq_data.sqlite")
            setDatabaseLocation(dbPath)
        }
    }

    /// Handles test mode startup, prompting user about existing test database
    private func handleTestModeStartup(testDBPath: URL) {
        print("⚠️ SAAQ_TEST_MODE environment variable detected")
        print("📍 Using test database: saaq_data_test.sqlite")
        print("🔒 Production database (saaq_data.sqlite) will not be modified")

        // Clear legacy UserDefaults-based filter cache to simulate fresh installation
        filterCache.clearCache()
        print("🗑️ Cleared legacy filter cache from UserDefaults")

        // Check if test database already exists
        if FileManager.default.fileExists(atPath: testDBPath.path) {
            DispatchQueue.main.async {
                // Trigger SwiftUI alert via published property
                // Database will be opened after user makes decision
                self.testDatabaseCleanupNeeded = testDBPath
            }
        } else {
            print("💡 Starting with fresh test database")
            // No existing database, safe to open immediately
            setDatabaseLocation(testDBPath)
        }
    }

    /// Called by UI when user makes test database cleanup decision
    func handleTestDatabaseCleanupDecision(shouldDelete: Bool, testDBPath: URL) {
        if shouldDelete {
            cleanupTestDatabase(testDBPath: testDBPath)
            print("🗑️ Test database deleted - starting fresh")
        } else {
            print("♻️ Continuing with existing test database")
        }

        // Clear the alert trigger
        testDatabaseCleanupNeeded = nil

        // Now open the database (either fresh or existing, depending on user's choice)
        setDatabaseLocation(testDBPath)
    }

    /// Removes test database files (main db, shm, wal)
    private func cleanupTestDatabase(testDBPath: URL) {
        let fileManager = FileManager.default
        let testFiles = [
            testDBPath.path,
            testDBPath.path + "-shm",
            testDBPath.path + "-wal"
        ]

        for filePath in testFiles {
            if fileManager.fileExists(atPath: filePath) {
                try? fileManager.removeItem(atPath: filePath)
            }
        }
    }

    /// Gets a persistent data version based on the integer dataVersion counter
    private func getPersistentDataVersion() -> String {
        // Use the integer dataVersion counter instead of file modification time
        // This ensures version only changes when data actually changes, not on every app launch
        return String(dataVersion)
    }
    
    /// Changes database location
    func setDatabaseLocation(_ url: URL) {
        dbQueue.async { [weak self] in
            self?.closeDatabase()

            // Update @Published property on main thread, then open database
            DispatchQueue.main.async {
                self?.databaseURL = url

                // Open database on background thread after URL is set
                self?.dbQueue.async {
                    self?.openDatabase()
                    // Note: createTablesIfNeeded() is now called INSIDE openDatabase() after page_size is set
                }
            }
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
                    SELECT year, class, admin_region, mrc, COUNT(*) as count
                    FROM vehicles
                    GROUP BY year, class, admin_region, mrc
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
                
                // Check available regions from enumeration table
                let regionQuery = "SELECT name FROM admin_region_enum ORDER BY code"
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

            // Check if database is empty (newly created)
            var stmt: OpaquePointer?
            let isEmpty = sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM sqlite_master WHERE type='table'", -1, &stmt, nil) == SQLITE_OK &&
                          sqlite3_step(stmt) == SQLITE_ROW &&
                          sqlite3_column_int(stmt, 0) == 0
            sqlite3_finalize(stmt)

            // Set page size ONLY on new/empty databases (before any tables exist)
            if isEmpty {
                print("📄 New database detected - setting page_size to 32KB for optimal performance")
                sqlite3_exec(db, "PRAGMA page_size = 32768", nil, nil, nil)
                sqlite3_exec(db, "PRAGMA auto_vacuum = INCREMENTAL", nil, nil, nil)
            } else {
                print("📄 Existing database detected - preserving current page_size")
            }

            // Enable AGGRESSIVE performance optimizations for M3 Ultra (96GB RAM, 27GB database)
            sqlite3_exec(db, "PRAGMA journal_mode = WAL", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA synchronous = NORMAL", nil, nil, nil)

            // Use 8GB cache for large database on 96GB system
            // Negative value = size in KB, so -8000000 = 8GB
            sqlite3_exec(db, "PRAGMA cache_size = -8000000", nil, nil, nil)  // 8GB cache

            // Map 32GB of database into memory (1/3 of available RAM)
            sqlite3_exec(db, "PRAGMA mmap_size = 34359738368", nil, nil, nil)  // 32GB mmap

            // Keep temp tables in memory
            sqlite3_exec(db, "PRAGMA temp_store = MEMORY", nil, nil, nil)

            // Use all available cores for sorting (M3 Ultra has many)
            sqlite3_exec(db, "PRAGMA threads = 16", nil, nil, nil)  // 16 threads

            // WAL checkpoint threshold - less frequent for performance
            sqlite3_exec(db, "PRAGMA wal_autocheckpoint = 10000", nil, nil, nil)  // 10K pages

            // Optimize query planner
            sqlite3_exec(db, "PRAGMA optimize", nil, nil, nil)

            // Conditionally update statistics based on user preference
            if AppSettings.shared.updateDatabaseStatisticsOnLaunch {
                print("🔄 Updating database statistics (ANALYZE) - this may take a few minutes...")
                let startTime = Date()
                sqlite3_exec(db, "ANALYZE", nil, nil, nil)
                let duration = Date().timeIntervalSince(startTime)
                print("✅ Database statistics updated in \(String(format: "%.1f", duration))s")
            }

            print("✅ Database AGGRESSIVELY optimized for M3 Ultra: 8GB cache, 32GB mmap, 16 threads")

            // Initialize schema and optimization managers
            schemaManager = SchemaManager(databaseManager: self)
            optimizedQueryManager = OptimizedQueryManager(databaseManager: self)
            filterCacheManager = FilterCacheManager(databaseManager: self)
            regularizationManager = RegularizationManager(databaseManager: self)

            // Create tables AFTER page_size is set
            createTablesIfNeeded()
        } else {
            print("Unable to open database at: \(dbPath)")
            if let errorMessage = sqlite3_errmsg(db) {
                print("Error: \(String(cString: errorMessage))")
            }
        }
    }
    
    /// Analyze query execution plan to determine index usage
    private func analyzeQueryPlan(for query: String, bindValues: [(Int32, Any)]) -> String? {
        guard let db = db else { return nil }

        let explainQuery = "EXPLAIN QUERY PLAN \(query)"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, explainQuery, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }

        // Bind the same values as the original query
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

        var indexUsed: String?
        var hasScan = false
        var planDetails: [String] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let detailPtr = sqlite3_column_text(stmt, 3) {
                let detail = String(cString: detailPtr)
                planDetails.append(detail)

                // Look for problematic patterns that indicate slow performance
                if detail.contains("SCAN") || detail.contains("USE TEMP B-TREE") || detail.contains("SEARCH TABLE") {
                    hasScan = true
                }

                // Look for index usage patterns in the query plan
                // Match "USING INDEX index_name" or "USING COVERING INDEX index_name"
                let indexPattern = /USING (?:COVERING )?INDEX (\w+)/

                if let match = detail.firstMatch(of: indexPattern) {
                    indexUsed = String(match.1)
                }
            }
        }

        // Debug output for the full execution plan
        print("🔍 Execution plan details:")
        for (i, detail) in planDetails.enumerated() {
            print("   \(i): \(detail)")
        }

        // If we detect scans or expensive operations, this is likely to be slow
        // even if an index is nominally "used"
        if hasScan {
            print("🔍 Warning: Query plan contains SCAN/SEARCH operations - likely slow")
            return nil // Report as no effective index
        }

        return indexUsed
    }

    /// Get performance classification for query time
    private func getPerformanceClassification(time: TimeInterval) -> (emoji: String, description: String) {
        switch time {
        case 0..<1.0:
            return ("⚡", "Excellent")
        case 1.0..<5.0:
            return ("🚀", "Very Good")
        case 5.0..<20.0:
            return ("✅", "Good")
        case 20.0..<60.0:
            return ("⏳", "Acceptable")
        default:
            return ("🐌", "Slow")
        }
    }

    /// Normalize time series points so first year = 1.0
    /// Used for Road Wear Index to show relative changes over time
    func normalizeToFirstYear(points: [TimeSeriesPoint]) -> [TimeSeriesPoint] {
        guard let firstValue = points.first?.value, firstValue > 0 else {
            // Handle edge cases: empty array or zero/negative first value
            if points.isEmpty {
                AppLogger.query.debug("Cannot normalize: points array is empty")
            } else {
                AppLogger.query.warning("Cannot normalize: first year value is \(points.first?.value ?? 0)")
            }
            return points
        }

        AppLogger.query.debug("Normalizing \(points.count) points to first year value: \(firstValue)")

        return points.map { point in
            TimeSeriesPoint(
                year: point.year,
                value: point.value / firstValue,
                label: point.label
            )
        }
    }

    /// Enhanced query output with index usage and performance classification
    private func printEnhancedQueryResult(
        queryType: String,
        executionTime: TimeInterval,
        dataPoints: Int,
        query: String,
        bindValues: [(Int32, Any)]
    ) {
        // Get performance classification
        let performance = getPerformanceClassification(time: executionTime)

        // Analyze query plan for index usage
        let indexUsed = analyzeQueryPlan(for: query, bindValues: bindValues)

        // Print enhanced output
        print("\(performance.emoji) \(queryType) query completed in \(String(format: "%.3f", executionTime))s - \(dataPoints) data points")

        if let index = indexUsed {
            print("   └─ Used index: \(index) ✓")
        } else {
            print("   └─ No index used (table scan)")
        }

        print("   └─ Performance: \(performance.description)")
    }

    /// Analyzes if a query will use an index without executing it
    func analyzeQueryIndexUsage(filters: FilterConfiguration) async -> Bool {
        // When using optimized queries, indexes are always used (by design)
        if useOptimizedQueries {
            print("🔍 Index analysis - Using optimized integer-based queries (indexes guaranteed)")
            return true
        }

        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let self = self, let _ = self.db else {
                    continuation.resume(returning: false)
                    return
                }

                // Build the same query that would be executed
                let (query, bindValues) = self.buildQueryForFilters(filters)

                print("🔍 Index analysis - Query: \(query)")
                print("🔍 Index analysis - Bind values: \(bindValues)")

                // Analyze if it will use an index
                let indexUsed = self.analyzeQueryPlan(for: query, bindValues: bindValues)

                if let index = indexUsed {
                    print("🔍 Index analysis - Found index: \(index)")
                } else {
                    print("🔍 Index analysis - No index found (table scan)")
                }

                continuation.resume(returning: indexUsed != nil)
            }
        }
    }

    /// Builds query and bind values for given filters (used for analysis)
    private func buildQueryForFilters(_ filters: FilterConfiguration) -> (String, [(Int32, Any)]) {
        var query = ""
        var bindValues: [(Int32, Any)] = []
        var bindIndex: Int32 = 1

        switch filters.dataEntityType {
        case .vehicle:
            query = "SELECT year, COUNT(*) as value FROM vehicles WHERE 1=1"
        case .license:
            query = "SELECT year, COUNT(*) as value FROM licenses WHERE 1=1"
        }

        // Add filter conditions (simplified version of the actual query building logic)
        if !filters.years.isEmpty {
            let placeholders = filters.years.map { _ in "?" }.joined(separator: ", ")
            query += " AND year IN (\(placeholders))"
            for year in filters.years {
                bindValues.append((bindIndex, year))
                bindIndex += 1
            }
        }

        if !filters.regions.isEmpty {
            let placeholders = Array(repeating: "?", count: filters.regions.count).joined(separator: ",")
            query += " AND region IN (\(placeholders))"
            for region in filters.regions.sorted() {
                bindValues.append((bindIndex, region))
                bindIndex += 1
            }
        }

        if !filters.mrcs.isEmpty {
            let placeholders = Array(repeating: "?", count: filters.mrcs.count).joined(separator: ",")
            query += " AND mrc IN (\(placeholders))"
            for mrc in filters.mrcs.sorted() {
                bindValues.append((bindIndex, mrc))
                bindIndex += 1
            }
        }

        if !filters.vehicleClasses.isEmpty && filters.dataEntityType == .vehicle {
            let placeholders = Array(repeating: "?", count: filters.vehicleClasses.count).joined(separator: ",")
            query += " AND vehicle_class IN (\(placeholders))"
            for vehicle_class in filters.vehicleClasses.sorted() {
                bindValues.append((bindIndex, vehicle_class))
                bindIndex += 1
            }
        }

        query += " GROUP BY year ORDER BY year"
        return (query, bindValues)
    }

    /// Manually update database statistics (ANALYZE command)
    func updateDatabaseStatistics() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }

                print("🔄 Updating database statistics (ANALYZE) - this may take several minutes...")
                let startTime = Date()

                let result = sqlite3_exec(db, "ANALYZE", nil, nil, nil)
                let duration = Date().timeIntervalSince(startTime)

                if result == SQLITE_OK {
                    print("✅ Database statistics updated successfully in \(String(format: "%.1f", duration))s")
                    continuation.resume()
                } else {
                    if let errorMessage = sqlite3_errmsg(db) {
                        let error = DatabaseError.queryFailed(String(cString: errorMessage))
                        print("❌ Failed to update database statistics: \(error)")
                        continuation.resume(throwing: error)
                    } else {
                        let error = DatabaseError.queryFailed("Unknown error during ANALYZE")
                        print("❌ Failed to update database statistics: \(error)")
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// Re-populate integer columns for optimized queries
    func repopulateIntegerColumns() async throws {
        print("🔧 Re-populating integer columns from DatabaseManager...")
        let schemaManager = SchemaManager(databaseManager: self)
        try await schemaManager.repopulateIntegerColumns()
        print("✅ Integer column population completed from DatabaseManager")
    }

    // MARK: - Enumeration-based Filter Data

    /// Get available regions as FilterItems (ID + display name)
    func getAvailableRegionItems() async throws -> [FilterItem] {
        guard let filterCacheManager = filterCacheManager else {
            throw DatabaseError.notConnected
        }
        return try await filterCacheManager.getAvailableRegions()
    }

    /// Get available MRCs as FilterItems (ID + display name)
    func getAvailableMRCItems() async throws -> [FilterItem] {
        guard let filterCacheManager = filterCacheManager else {
            throw DatabaseError.notConnected
        }
        return try await filterCacheManager.getAvailableMRCs()
    }

    /// Get available municipalities as FilterItems (ID + display name)
    func getAvailableMunicipalityItems() async throws -> [FilterItem] {
        guard let filterCacheManager = filterCacheManager else {
            throw DatabaseError.notConnected
        }
        return try await filterCacheManager.getAvailableMunicipalities()
    }

    /// Get available classes as FilterItems (ID + display name)
    func getAvailableClassItems() async throws -> [FilterItem] {
        guard let filterCacheManager = filterCacheManager else {
            throw DatabaseError.notConnected
        }
        return try await filterCacheManager.getAvailableVehicleClasses()
    }

    /// Get available fuel types as FilterItems (ID + display name)
    func getAvailableFuelTypeItems() async throws -> [FilterItem] {
        guard let filterCacheManager = filterCacheManager else {
            throw DatabaseError.notConnected
        }
        return try await filterCacheManager.getAvailableFuelTypes()
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

    // MARK: - Database Connection Management

    /// Closes the database connection for import/export operations
    func closeDatabaseConnection() async {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                self?.closeDatabase()
                print("🔒 Database connection closed for import/export")
                continuation.resume()
            }
        }
    }

    /// Reconnects to the database after import/export operations
    func reconnectDatabase() async {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                self?.openDatabase()
                self?.createTablesIfNeeded()
                print("🔓 Database connection reopened after import/export")
                continuation.resume()
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

                -- Numeric data columns (not categorical)
                model_year INTEGER,
                net_mass REAL,
                cylinder_count INTEGER,
                displacement REAL,
                max_axles INTEGER,

                -- Integer foreign key columns (TINYINT 1-byte)
                year_id INTEGER,
                vehicle_class_id INTEGER,
                vehicle_type_id INTEGER,
                cylinder_count_id INTEGER,
                axle_count_id INTEGER,
                original_color_id INTEGER,
                fuel_type_id INTEGER,
                admin_region_id INTEGER,

                -- Integer foreign key columns (SMALLINT 2-byte)
                make_id INTEGER,
                model_id INTEGER,
                model_year_id INTEGER,
                mrc_id INTEGER,
                municipality_id INTEGER,

                -- Optimized numeric columns (stored as integers)
                net_mass_int INTEGER,
                displacement_int INTEGER,

                UNIQUE(year, vehicle_sequence)
            );
            """
        
        let createLicensesTable = """
            CREATE TABLE IF NOT EXISTS licenses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                year INTEGER NOT NULL,
                license_sequence TEXT NOT NULL,

                -- License class boolean columns
                has_learner_permit_123 INTEGER NOT NULL DEFAULT 0,
                has_learner_permit_5 INTEGER NOT NULL DEFAULT 0,
                has_learner_permit_6a6r INTEGER NOT NULL DEFAULT 0,
                has_driver_license_1234 INTEGER NOT NULL DEFAULT 0,
                has_driver_license_5 INTEGER NOT NULL DEFAULT 0,
                has_driver_license_6abce INTEGER NOT NULL DEFAULT 0,
                has_driver_license_6d INTEGER NOT NULL DEFAULT 0,
                has_driver_license_8 INTEGER NOT NULL DEFAULT 0,
                is_probationary INTEGER NOT NULL DEFAULT 0,

                -- Experience columns
                experience_1234 TEXT,
                experience_5 TEXT,
                experience_6abce TEXT,
                experience_global TEXT,

                -- Integer foreign key columns (TINYINT 1-byte)
                year_id INTEGER,
                age_group_id INTEGER,
                gender_id INTEGER,
                admin_region_id INTEGER,
                license_type_id INTEGER,

                -- Integer foreign key columns (SMALLINT 2-byte)
                mrc_id INTEGER,

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

        let createCanonicalHierarchyCacheTable = """
            CREATE TABLE IF NOT EXISTS canonical_hierarchy_cache (
                make_id INTEGER NOT NULL,
                make_name TEXT NOT NULL,
                model_id INTEGER NOT NULL,
                model_name TEXT NOT NULL,
                model_year_id INTEGER,
                model_year INTEGER,
                fuel_type_id INTEGER,
                fuel_type_code TEXT,
                fuel_type_description TEXT,
                vehicle_type_id INTEGER,
                vehicle_type_code TEXT,
                vehicle_type_description TEXT,
                record_count INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (make_id, model_id, model_year_id, fuel_type_id, vehicle_type_id),
                FOREIGN KEY (make_id) REFERENCES make_enum(id),
                FOREIGN KEY (model_id) REFERENCES model_enum(id),
                FOREIGN KEY (model_year_id) REFERENCES model_year_enum(id),
                FOREIGN KEY (fuel_type_id) REFERENCES fuel_type_enum(id),
                FOREIGN KEY (vehicle_type_id) REFERENCES vehicle_type_enum(id)
            );
            """
        
        // Create indexes for better query performance
        let createIndexes = [
            // Vehicle indexes - non-categorical columns only
            "CREATE INDEX IF NOT EXISTS idx_vehicles_year ON vehicles(year);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_model_year ON vehicles(model_year);",

            // License indexes - non-categorical columns only
            "CREATE INDEX IF NOT EXISTS idx_licenses_year ON licenses(year);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_probationary ON licenses(is_probationary);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_experience_distinct ON licenses(experience_global);",

            // Geographic indexes
            "CREATE INDEX IF NOT EXISTS idx_geographic_type ON geographic_entities(type);",
            "CREATE INDEX IF NOT EXISTS idx_geographic_parent ON geographic_entities(parent_code);",

            // ===== OPTIMIZED INTEGER-BASED INDEXES =====
            // These indexes on integer foreign key columns provide 5.6x+ performance improvement

            // Vehicles table - single column integer indexes
            "CREATE INDEX IF NOT EXISTS idx_vehicles_year_id ON vehicles(year_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_class_id ON vehicles(vehicle_class_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_type_id ON vehicles(vehicle_type_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_make_id ON vehicles(make_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_model_id ON vehicles(model_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_model_year_id ON vehicles(model_year_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_fuel_type_id ON vehicles(fuel_type_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_admin_region_id ON vehicles(admin_region_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_mrc_id ON vehicles(mrc_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_municipality_id ON vehicles(municipality_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_cylinder_count_id ON vehicles(cylinder_count_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_axle_count_id ON vehicles(axle_count_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_color_id ON vehicles(original_color_id);",

            // Vehicles table - composite integer indexes for common query patterns
            "CREATE INDEX IF NOT EXISTS idx_vehicles_year_class_id ON vehicles(year_id, vehicle_class_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_year_type_id ON vehicles(year_id, vehicle_type_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_year_fuel_id ON vehicles(year_id, fuel_type_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_year_region_id ON vehicles(year_id, admin_region_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_year_municipality_id ON vehicles(year_id, municipality_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_municipality_class_year_id ON vehicles(municipality_id, vehicle_class_id, year_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_region_class_year_id ON vehicles(admin_region_id, vehicle_class_id, year_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_make_model_year_id ON vehicles(make_id, model_id, year_id);",

            // Licenses table - single column integer indexes
            "CREATE INDEX IF NOT EXISTS idx_licenses_year_id ON licenses(year_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_age_group_id ON licenses(age_group_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_gender_id ON licenses(gender_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_admin_region_id ON licenses(admin_region_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_mrc_id ON licenses(mrc_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_license_type_id ON licenses(license_type_id);",

            // Licenses table - composite integer indexes
            "CREATE INDEX IF NOT EXISTS idx_licenses_year_type_id ON licenses(year_id, license_type_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_year_age_id ON licenses(year_id, age_group_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_year_gender_id ON licenses(year_id, gender_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_year_region_id ON licenses(year_id, admin_region_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_mrc_type_year_id ON licenses(mrc_id, license_type_id, year_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_region_type_year_id ON licenses(admin_region_id, license_type_id, year_id);",

            // Enumeration table indexes for fast reverse lookups
            "CREATE INDEX IF NOT EXISTS idx_year_enum_year ON year_enum(year);",
            "CREATE INDEX IF NOT EXISTS idx_class_enum_code ON vehicle_class_enum(code);",
            "CREATE INDEX IF NOT EXISTS idx_type_enum_code ON vehicle_type_enum(code);",
            "CREATE INDEX IF NOT EXISTS idx_make_enum_name ON make_enum(name);",
            "CREATE INDEX IF NOT EXISTS idx_model_enum_name_make ON model_enum(name, make_id);",
            "CREATE INDEX IF NOT EXISTS idx_fuel_type_enum_code ON fuel_type_enum(code);",
            "CREATE INDEX IF NOT EXISTS idx_admin_region_enum_code ON admin_region_enum(code);",
            "CREATE INDEX IF NOT EXISTS idx_mrc_enum_code ON mrc_enum(code);",
            "CREATE INDEX IF NOT EXISTS idx_municipality_enum_code ON municipality_enum(code);",
            "CREATE INDEX IF NOT EXISTS idx_age_group_enum_range ON age_group_enum(range_text);",
            "CREATE INDEX IF NOT EXISTS idx_gender_enum_code ON gender_enum(code);",

            // Canonical hierarchy cache indexes for fast queries
            "CREATE INDEX IF NOT EXISTS idx_cache_make_id ON canonical_hierarchy_cache(make_id);",
            "CREATE INDEX IF NOT EXISTS idx_cache_model_id ON canonical_hierarchy_cache(model_id);",
            "CREATE INDEX IF NOT EXISTS idx_cache_make_model ON canonical_hierarchy_cache(make_id, model_id);"
        ]
        
        // Create tables and indexes SYNCHRONOUSLY to ensure they exist before cache operations
        // Create main tables
        for query in [createVehiclesTable, createLicensesTable, createGeographicTable, createImportLogTable, createCanonicalHierarchyCacheTable] {
            if sqlite3_exec(db, query, nil, nil, nil) != SQLITE_OK {
                if let errorMessage = sqlite3_errmsg(db) {
                    print("Error creating table: \(String(cString: errorMessage))")
                }
            }
        }

        // Create enumeration tables
        print("🔧 Creating enumeration tables...")
        let enumTables = [
            // Year enumeration
            "CREATE TABLE IF NOT EXISTS year_enum (id INTEGER PRIMARY KEY AUTOINCREMENT, year INTEGER UNIQUE NOT NULL);",
            // Class enumeration (CLAS field - usage-based classification)
            "CREATE TABLE IF NOT EXISTS vehicle_class_enum (id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE NOT NULL, description TEXT);",
            // Vehicle Type enumeration (TYP_VEH_CATEG_USA field - physical vehicle type)
            "CREATE TABLE IF NOT EXISTS vehicle_type_enum (id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE NOT NULL, description TEXT);",
            // Cylinder count enumeration
            "CREATE TABLE IF NOT EXISTS cylinder_count_enum (id INTEGER PRIMARY KEY AUTOINCREMENT, count INTEGER UNIQUE NOT NULL);",
            // Axle count enumeration
            "CREATE TABLE IF NOT EXISTS axle_count_enum (id INTEGER PRIMARY KEY AUTOINCREMENT, count INTEGER UNIQUE NOT NULL);",
            // Color enumeration
            "CREATE TABLE IF NOT EXISTS color_enum (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL);",
            // Fuel type enumeration
            "CREATE TABLE IF NOT EXISTS fuel_type_enum (id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE NOT NULL, description TEXT);",
            // Admin region enumeration
            "CREATE TABLE IF NOT EXISTS admin_region_enum (id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE NOT NULL, name TEXT NOT NULL);",
            // Age group enumeration
            "CREATE TABLE IF NOT EXISTS age_group_enum (id INTEGER PRIMARY KEY AUTOINCREMENT, range_text TEXT UNIQUE NOT NULL);",
            // Gender enumeration
            "CREATE TABLE IF NOT EXISTS gender_enum (id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE NOT NULL, description TEXT);",
            // License type enumeration
            "CREATE TABLE IF NOT EXISTS license_type_enum (id INTEGER PRIMARY KEY AUTOINCREMENT, type_name TEXT UNIQUE NOT NULL, description TEXT);",
            // Make enumeration
            "CREATE TABLE IF NOT EXISTS make_enum (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL);",
            // Model enumeration (requires make_id foreign key)
            "CREATE TABLE IF NOT EXISTS model_enum (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, make_id INTEGER NOT NULL REFERENCES make_enum(id), UNIQUE(name, make_id));",
            // Model year enumeration
            "CREATE TABLE IF NOT EXISTS model_year_enum (id INTEGER PRIMARY KEY AUTOINCREMENT, year INTEGER UNIQUE NOT NULL);",
            // MRC enumeration
            "CREATE TABLE IF NOT EXISTS mrc_enum (id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE NOT NULL, name TEXT NOT NULL);",
            // Municipality enumeration
            "CREATE TABLE IF NOT EXISTS municipality_enum (id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE NOT NULL, name TEXT NOT NULL);"
        ]

        for enumTableSQL in enumTables {
            if sqlite3_exec(db, enumTableSQL, nil, nil, nil) != SQLITE_OK {
                if let errorMessage = sqlite3_errmsg(db) {
                    print("Error creating enumeration table: \(String(cString: errorMessage))")
                }
            }
        }
        print("✅ Created \(enumTables.count) enumeration tables")

        // Insert special "Unknown" values for regularization system
        // These values never appear in CSV data but are needed for user-driven regularization
        print("🔧 Inserting special 'Unknown' enum values for regularization...")
        let unknownInserts = [
            "INSERT OR IGNORE INTO fuel_type_enum (code, description) VALUES ('U', 'Unknown');",
            "INSERT OR IGNORE INTO vehicle_class_enum (code, description) VALUES ('UNK', 'Unknown');",
            "INSERT OR IGNORE INTO vehicle_type_enum (code, description) VALUES ('UK', 'Unknown');"
        ]

        for insertSQL in unknownInserts {
            if sqlite3_exec(db, insertSQL, nil, nil, nil) != SQLITE_OK {
                if let errorMessage = sqlite3_errmsg(db) {
                    print("⚠️ Warning: Failed to insert Unknown enum value: \(String(cString: errorMessage))")
                }
            }
        }
        print("✅ Inserted Unknown enum values for regularization system")

        // Create indexes SYNCHRONOUSLY to prevent cache rebuild performance issues
        print("🔧 Creating database indexes for optimal performance...")
        let indexStartTime = Date()
        for (index, indexSQL) in createIndexes.enumerated() {
            if sqlite3_exec(db, indexSQL, nil, nil, nil) != SQLITE_OK {
                if let errorMessage = sqlite3_errmsg(db) {
                    print("⚠️ Warning: Failed to create index \(index + 1): \(String(cString: errorMessage))")
                }
            }
        }
        let indexDuration = Date().timeIntervalSince(indexStartTime)
        print("✅ Created \(createIndexes.count) database indexes in \(String(format: "%.1f", indexDuration))s")
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
        print("🔍 queryData() called with metricType: \(filters.metricType)")

        // Use optimized parallel query for percentage calculations
        if filters.metricType == .percentage {
            print("✅ Routing to calculatePercentagePointsParallel()")
            return try await calculatePercentagePointsParallel(filters: filters)
        }

        // Regular query for other metric types
        print("➡️ Routing to regular query for metricType: \(filters.metricType)")
        switch filters.dataEntityType {
        case .vehicle:
            return try await queryVehicleData(filters: filters)
        case .license:
            return try await queryLicenseData(filters: filters)
        }
    }

    /// Queries vehicle data based on filters
    func queryVehicleData(filters: FilterConfiguration) async throws -> FilteredDataSeries {
        // Use optimized query manager if available and enabled
        if useOptimizedQueries, let optimizedManager = optimizedQueryManager {
            print("🚀 Using optimized integer-based queries for vehicles")
            let optimizedSeries = try await optimizedManager.queryOptimizedVehicleData(filters: filters)

            // Update the series name to match the expected format
            let seriesName = await generateSeriesNameAsync(from: filters)
            optimizedSeries.name = seriesName

            return optimizedSeries
        }

        // Fall back to string-based queries
        print("📊 Using traditional string-based queries for vehicles")
        let startTime = Date()

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

                case .minimum:
                    if filters.metricField == .vehicleAge {
                        query = "SELECT year, MIN(year - model_year) as value FROM vehicles WHERE model_year IS NOT NULL AND 1=1"
                    } else if let column = filters.metricField.databaseColumn {
                        query = "SELECT year, MIN(\(column)) as value FROM vehicles WHERE \(column) IS NOT NULL AND 1=1"
                    } else {
                        query = "SELECT year, COUNT(*) as value FROM vehicles WHERE 1=1"
                    }

                case .maximum:
                    if filters.metricField == .vehicleAge {
                        query = "SELECT year, MAX(year - model_year) as value FROM vehicles WHERE model_year IS NOT NULL AND 1=1"
                    } else if let column = filters.metricField.databaseColumn {
                        query = "SELECT year, MAX(\(column)) as value FROM vehicles WHERE \(column) IS NOT NULL AND 1=1"
                    } else {
                        query = "SELECT year, COUNT(*) as value FROM vehicles WHERE 1=1"
                    }

                case .percentage:
                    // For percentage, we need to do dual queries - this is handled separately
                    query = "SELECT year, COUNT(*) as value FROM vehicles WHERE 1=1"

                case .coverage:
                    // For coverage, show either percentage or raw NULL count
                    if let coverageField = filters.coverageField {
                        let column = coverageField.databaseColumn
                        if filters.coverageAsPercentage {
                            query = "SELECT year, (CAST(COUNT(\(column)) AS REAL) / CAST(COUNT(*) AS REAL) * 100.0) as value FROM vehicles WHERE 1=1"
                        } else {
                            query = "SELECT year, (COUNT(*) - COUNT(\(column))) as value FROM vehicles WHERE 1=1"
                        }
                    } else {
                        // Fallback to count if no field selected
                        query = "SELECT year, COUNT(*) as value FROM vehicles WHERE 1=1"
                    }

                case .roadWearIndex:
                    // Road Wear Index: 4th power law based on vehicle mass
                    // Weight distribution varies by vehicle type:
                    // - Trucks (CA) & Tool vehicles (VO): 3 axles (30% front, 35% rear1, 35% rear2)
                    //   RWI = (0.30^4 + 0.35^4 + 0.35^4) × mass^4 = 0.0234 × mass^4
                    // - Buses (AB): 2 axles (35% front, 65% rear)
                    //   RWI = (0.35^4 + 0.65^4) × mass^4 = 0.1935 × mass^4
                    // - Cars (AU) & others: 2 axles (50% front, 50% rear)
                    //   RWI = (0.50^4 + 0.50^4) × mass^4 = 0.125 × mass^4
                    let rwiCalculation = """
                        CASE
                            WHEN vehicle_type_id IN (SELECT id FROM vehicle_type_enum WHERE code IN ('CA', 'VO'))
                            THEN 0.0234 * POWER(net_mass, 4)
                            WHEN vehicle_type_id IN (SELECT id FROM vehicle_type_enum WHERE code = 'AB')
                            THEN 0.1935 * POWER(net_mass, 4)
                            ELSE 0.125 * POWER(net_mass, 4)
                        END
                        """
                    if filters.roadWearIndexMode == .average {
                        query = "SELECT year, AVG(\(rwiCalculation)) as value FROM vehicles WHERE net_mass IS NOT NULL AND 1=1"
                    } else {
                        query = "SELECT year, SUM(\(rwiCalculation)) as value FROM vehicles WHERE net_mass IS NOT NULL AND 1=1"
                    }
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

                // Add vehicle class filter
                if !filters.vehicleClasses.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.vehicleClasses.count).joined(separator: ",")
                    query += " AND vehicle_class IN (\(placeholders))"
                    for vehicle_class in filters.vehicleClasses.sorted() {
                        bindValues.append((Int32(bindIndex), vehicle_class))
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
                    query += " AND fuel_type IN (\(placeholders))"

                    // Smart year filtering: Only apply year >= 2017 if no specific years selected
                    if filters.years.isEmpty {
                        query += " AND year >= 2017"
                    }

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
                    // Apply normalization for Road Wear Index if enabled
                    let normalizedPoints = if filters.metricType == .roadWearIndex && filters.normalizeRoadWearIndex {
                        self?.normalizeToFirstYear(points: points) ?? points
                    } else {
                        points
                    }

                    // Create series with the proper name (already resolved)
                    let series = FilteredDataSeries(name: seriesName, filters: filters, points: normalizedPoints)
                    let duration = Date().timeIntervalSince(startTime)

                    // Use simplified output for main query (raw query provides detailed info)
                    let performance = self?.getPerformanceClassification(time: duration) ?? ("📊", "Unknown")
                    print("\(performance.0) Vehicle query completed in \(String(format: "%.3f", duration))s - \(points.count) data points")

                    continuation.resume(returning: series)
                }
            }
        }
    }

    /// Queries license data based on filters
    func queryLicenseData(filters: FilterConfiguration) async throws -> FilteredDataSeries {
        // Use optimized query manager if available and enabled
        if useOptimizedQueries, let optimizedManager = optimizedQueryManager {
            print("🚀 Using optimized integer-based queries for licenses")
            let optimizedSeries = try await optimizedManager.queryOptimizedLicenseData(filters: filters)

            // Update the series name to match the expected format
            let seriesName = await generateSeriesNameAsync(from: filters)
            optimizedSeries.name = seriesName

            return optimizedSeries
        }

        // Fall back to string-based queries
        print("📊 Using traditional string-based queries for licenses")
        let startTime = Date()

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

                case .minimum, .maximum:
                    // Min/Max not meaningful for license data - fallback to count
                    query = "SELECT year, COUNT(*) as value FROM licenses WHERE 1=1"

                case .percentage:
                    // For percentage, we need to do dual queries - this is handled separately
                    query = "SELECT year, COUNT(*) as value FROM licenses WHERE 1=1"

                case .coverage:
                    // Coverage not yet implemented for licenses (awaiting integer enumeration)
                    // Fallback to count
                    query = "SELECT year, COUNT(*) as value FROM licenses WHERE 1=1"

                case .roadWearIndex:
                    // Road Wear Index not applicable to license data - fallback to count
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

                // Add license class filter using centralized mapping
                if !filters.licenseClasses.isEmpty {
                    var classConditions: [String] = []
                    let licenseMapping = self?.getLicenseClassMapping() ?? []

                    for licenseClass in filters.licenseClasses {
                        if let column = self?.getDatabaseColumn(for: licenseClass) {
                            classConditions.append("\(column) = 1")
                        } else {
                            // Log unmapped filter values to help debug issues
                            print("⚠️ Warning: Unmapped license class filter '\(licenseClass)'. Available mappings:")
                            for (col, name) in licenseMapping {
                                print("   '\(name)' → \(col)")
                            }
                        }
                    }

                    if !classConditions.isEmpty {
                        query += " AND (\(classConditions.joined(separator: " OR ")))"
                    } else if !filters.licenseClasses.isEmpty {
                        print("⚠️ Warning: No valid license class filters applied. All requested filters were unmapped.")
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
                    let duration = Date().timeIntervalSince(startTime)

                    // Use simplified output for main query (raw query provides detailed info)
                    let performance = self?.getPerformanceClassification(time: duration) ?? ("📊", "Unknown")
                    print("\(performance.0) License query completed in \(String(format: "%.3f", duration))s - \(points.count) data points")

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

    /// Optimized parallel calculation of percentage points - queries both numerator and baseline concurrently
    private func calculatePercentagePointsParallel(
        filters: FilterConfiguration
    ) async throws -> FilteredDataSeries {
        print("🔢 calculatePercentagePointsParallel() called")

        guard filters.metricType == .percentage,
              let baselineFilters = filters.percentageBaseFilters else {
            throw DatabaseError.queryFailed("Invalid percentage configuration")
        }

        print("🔢 Starting parallel percentage queries...")
        print("🔢 Numerator filters: \(filters)")
        print("🔢 Baseline filters: \(baselineFilters)")

        let startTime = Date()

        // Execute numerator and baseline queries in parallel using async let
        async let numeratorTask = queryDataRaw(filters: filters)
        async let baselineTask = queryDataRaw(filters: baselineFilters.toFilterConfiguration())

        // Wait for both queries to complete concurrently
        let (numeratorPoints, baselinePoints) = try await (numeratorTask, baselineTask)

        let queryTime = Date().timeIntervalSince(startTime)
        print("⚡ Parallel percentage queries completed in \(String(format: "%.3f", queryTime))s")
        print("📊 Numerator points: \(numeratorPoints.count), Baseline points: \(baselinePoints.count)")

        // Create baseline lookup dictionary
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
                print("📊 Year \(year): numerator=\(String(format: "%.0f", numerator)), baseline=\(String(format: "%.0f", baseline)), percentage=\(String(format: "%.2f", percentage))%")
                percentagePoints.append(
                    TimeSeriesPoint(year: year, value: percentage, label: numeratorPoint.label)
                )
            } else {
                // No baseline data for this year, or baseline is zero
                print("⚠️ Year \(year): No baseline data or baseline is zero")
                percentagePoints.append(
                    TimeSeriesPoint(year: year, value: 0.0, label: numeratorPoint.label)
                )
            }
        }

        // Generate series name
        let seriesName = await generateSeriesNameAsync(from: filters)

        return FilteredDataSeries(name: seriesName, filters: filters, points: percentagePoints)
    }

    /// Raw query method that returns just the data points without creating a FilteredDataSeries
    private func queryDataRaw(filters: FilterConfiguration) async throws -> [TimeSeriesPoint] {
        switch filters.dataEntityType {
        case .vehicle:
            return try await queryVehicleDataRaw(filters: filters)
        case .license:
            return try await queryLicenseDataRaw(filters: filters)
        }
    }

    /// Raw vehicle data query that returns just points without series wrapper
    private func queryVehicleDataRaw(filters: FilterConfiguration) async throws -> [TimeSeriesPoint] {
        // Use optimized query manager if available (for integer-based queries)
        if useOptimizedQueries, let optimizedManager = optimizedQueryManager {
            let series = try await optimizedManager.queryOptimizedVehicleData(filters: filters)
            return series.points
        }

        // Fallback to legacy string-based queries
        let startTime = Date()

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
                case .count, .percentage:  // Percentage uses count for numerator
                    query = "SELECT year, COUNT(*) as value FROM vehicles WHERE 1=1"

                case .sum:
                    if filters.metricField == .vehicleAge {
                        query = "SELECT year, SUM(year - model_year) as value FROM vehicles WHERE model_year IS NOT NULL AND 1=1"
                    } else if let column = filters.metricField.databaseColumn {
                        query = "SELECT year, SUM(\(column)) as value FROM vehicles WHERE \(column) IS NOT NULL AND 1=1"
                    } else {
                        query = "SELECT year, COUNT(*) as value FROM vehicles WHERE 1=1"
                    }

                case .average:
                    if filters.metricField == .vehicleAge {
                        query = "SELECT year, AVG(year - model_year) as value FROM vehicles WHERE model_year IS NOT NULL AND 1=1"
                    } else if let column = filters.metricField.databaseColumn {
                        query = "SELECT year, AVG(\(column)) as value FROM vehicles WHERE \(column) IS NOT NULL AND 1=1"
                    } else {
                        query = "SELECT year, COUNT(*) as value FROM vehicles WHERE 1=1"
                    }

                case .minimum:
                    if filters.metricField == .vehicleAge {
                        query = "SELECT year, MIN(year - model_year) as value FROM vehicles WHERE model_year IS NOT NULL AND 1=1"
                    } else if let column = filters.metricField.databaseColumn {
                        query = "SELECT year, MIN(\(column)) as value FROM vehicles WHERE \(column) IS NOT NULL AND 1=1"
                    } else {
                        query = "SELECT year, COUNT(*) as value FROM vehicles WHERE 1=1"
                    }

                case .maximum:
                    if filters.metricField == .vehicleAge {
                        query = "SELECT year, MAX(year - model_year) as value FROM vehicles WHERE model_year IS NOT NULL AND 1=1"
                    } else if let column = filters.metricField.databaseColumn {
                        query = "SELECT year, MAX(\(column)) as value FROM vehicles WHERE \(column) IS NOT NULL AND 1=1"
                    } else {
                        query = "SELECT year, COUNT(*) as value FROM vehicles WHERE 1=1"
                    }

                case .coverage:
                    // For coverage, show either percentage or raw NULL count
                    if let coverageField = filters.coverageField {
                        let column = coverageField.databaseColumn
                        if filters.coverageAsPercentage {
                            query = "SELECT year, (CAST(COUNT(\(column)) AS REAL) / CAST(COUNT(*) AS REAL) * 100.0) as value FROM vehicles WHERE 1=1"
                        } else {
                            query = "SELECT year, (COUNT(*) - COUNT(\(column))) as value FROM vehicles WHERE 1=1"
                        }
                    } else {
                        // Fallback to count if no field selected
                        query = "SELECT year, COUNT(*) as value FROM vehicles WHERE 1=1"
                    }

                case .roadWearIndex:
                    // Road Wear Index: 4th power law based on vehicle mass
                    // Weight distribution varies by vehicle type:
                    // - Trucks (CA) & Tool vehicles (VO): 3 axles (30% front, 35% rear1, 35% rear2)
                    //   RWI = (0.30^4 + 0.35^4 + 0.35^4) × mass^4 = 0.0234 × mass^4
                    // - Buses (AB): 2 axles (35% front, 65% rear)
                    //   RWI = (0.35^4 + 0.65^4) × mass^4 = 0.1935 × mass^4
                    // - Cars (AU) & others: 2 axles (50% front, 50% rear)
                    //   RWI = (0.50^4 + 0.50^4) × mass^4 = 0.125 × mass^4
                    let rwiCalculation = """
                        CASE
                            WHEN vehicle_type_id IN (SELECT id FROM vehicle_type_enum WHERE code IN ('CA', 'VO'))
                            THEN 0.0234 * POWER(net_mass, 4)
                            WHEN vehicle_type_id IN (SELECT id FROM vehicle_type_enum WHERE code = 'AB')
                            THEN 0.1935 * POWER(net_mass, 4)
                            ELSE 0.125 * POWER(net_mass, 4)
                        END
                        """
                    if filters.roadWearIndexMode == .average {
                        query = "SELECT year, AVG(\(rwiCalculation)) as value FROM vehicles WHERE net_mass IS NOT NULL AND 1=1"
                    } else {
                        query = "SELECT year, SUM(\(rwiCalculation)) as value FROM vehicles WHERE net_mass IS NOT NULL AND 1=1"
                    }
                }

                // Build WHERE clause from filters
                var bindIndex = 1
                var bindValues: [(Int32, Any)] = []

                // Add all filter conditions (years, regions, classes, etc.)
                query += self?.buildVehicleWhereClause(filters: filters, bindIndex: &bindIndex, bindValues: &bindValues) ?? ""

                // Add GROUP BY and ORDER BY
                query += " GROUP BY year ORDER BY year"

                // Prepare and execute statement
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }

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
                    let value = sqlite3_column_double(stmt, 1)
                    points.append(TimeSeriesPoint(year: year, value: value, label: nil))
                }

                let duration = Date().timeIntervalSince(startTime)
                self?.printEnhancedQueryResult(
                    queryType: "Vehicle",
                    executionTime: duration,
                    dataPoints: points.count,
                    query: query,
                    bindValues: bindValues
                )
                continuation.resume(returning: points)
            }
        }
    }

    /// Raw license data query that returns just points without series wrapper
    private func queryLicenseDataRaw(filters: FilterConfiguration) async throws -> [TimeSeriesPoint] {
        let startTime = Date()

        return try await withCheckedThrowingContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }

                // Build dynamic query - simpler for licenses (count only for now)
                var query = "SELECT year, COUNT(*) as value FROM licenses WHERE 1=1"

                // Build WHERE clause from filters
                var bindIndex = 1
                var bindValues: [(Int32, Any)] = []

                query += self?.buildLicenseWhereClause(filters: filters, bindIndex: &bindIndex, bindValues: &bindValues) ?? ""

                // Add GROUP BY and ORDER BY
                query += " GROUP BY year ORDER BY year"

                // Prepare and execute statement
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }

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
                    let value = sqlite3_column_double(stmt, 1)
                    points.append(TimeSeriesPoint(year: year, value: value, label: nil))
                }

                let duration = Date().timeIntervalSince(startTime)
                self?.printEnhancedQueryResult(
                    queryType: "License",
                    executionTime: duration,
                    dataPoints: points.count,
                    query: query,
                    bindValues: bindValues
                )
                continuation.resume(returning: points)
            }
        }
    }

    /// Helper method to build WHERE clause for vehicle queries
    private func buildVehicleWhereClause(filters: FilterConfiguration, bindIndex: inout Int, bindValues: inout [(Int32, Any)]) -> String {
        var whereClause = ""

        // Add year filter
        if !filters.years.isEmpty {
            let placeholders = Array(repeating: "?", count: filters.years.count).joined(separator: ",")
            whereClause += " AND year IN (\(placeholders))"
            for year in filters.years.sorted() {
                bindValues.append((Int32(bindIndex), year))
                bindIndex += 1
            }
        }

        // Add region filter
        if !filters.regions.isEmpty {
            let placeholders = Array(repeating: "?", count: filters.regions.count).joined(separator: ",")
            whereClause += " AND admin_region IN (\(placeholders))"
            for region in filters.regions.sorted() {
                bindValues.append((Int32(bindIndex), region))
                bindIndex += 1
            }
        }

        // Add MRC filter
        if !filters.mrcs.isEmpty {
            let placeholders = Array(repeating: "?", count: filters.mrcs.count).joined(separator: ",")
            whereClause += " AND mrc IN (\(placeholders))"
            for mrc in filters.mrcs.sorted() {
                bindValues.append((Int32(bindIndex), mrc))
                bindIndex += 1
            }
        }

        // Add municipality filter
        if !filters.municipalities.isEmpty {
            let placeholders = Array(repeating: "?", count: filters.municipalities.count).joined(separator: ",")
            whereClause += " AND geo_code IN (\(placeholders))"
            for municipality in filters.municipalities.sorted() {
                bindValues.append((Int32(bindIndex), municipality))
                bindIndex += 1
            }
        }

        // Add vehicle class filter
        if !filters.vehicleClasses.isEmpty {
            let placeholders = Array(repeating: "?", count: filters.vehicleClasses.count).joined(separator: ",")
            whereClause += " AND vehicle_class IN (\(placeholders))"
            for vehicle_class in filters.vehicleClasses.sorted() {
                bindValues.append((Int32(bindIndex), vehicle_class))
                bindIndex += 1
            }
        }

        // Add fuel type filter (only for years 2017+)
        if !filters.fuelTypes.isEmpty {
            let placeholders = Array(repeating: "?", count: filters.fuelTypes.count).joined(separator: ",")
            whereClause += " AND fuel_type IN (\(placeholders))"

            // Smart year filtering: Only apply year >= 2017 if no specific years selected
            if filters.years.isEmpty {
                whereClause += " AND year >= 2017"
            }

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
                whereClause += " AND (\(ageConditions.joined(separator: " OR ")))"
            }
        }

        // Add vehicle make filter
        if !filters.vehicleMakes.isEmpty {
            let placeholders = Array(repeating: "?", count: filters.vehicleMakes.count).joined(separator: ",")
            whereClause += " AND make IN (\(placeholders))"
            for make in filters.vehicleMakes.sorted() {
                bindValues.append((Int32(bindIndex), make))
                bindIndex += 1
            }
        }

        // Add vehicle model filter
        if !filters.vehicleModels.isEmpty {
            let placeholders = Array(repeating: "?", count: filters.vehicleModels.count).joined(separator: ",")
            whereClause += " AND model IN (\(placeholders))"
            for model in filters.vehicleModels.sorted() {
                bindValues.append((Int32(bindIndex), model))
                bindIndex += 1
            }
        }

        // Add vehicle color filter
        if !filters.vehicleColors.isEmpty {
            let placeholders = Array(repeating: "?", count: filters.vehicleColors.count).joined(separator: ",")
            whereClause += " AND original_color IN (\(placeholders))"
            for color in filters.vehicleColors.sorted() {
                bindValues.append((Int32(bindIndex), color))
                bindIndex += 1
            }
        }

        // Add model year filter
        if !filters.modelYears.isEmpty {
            let placeholders = Array(repeating: "?", count: filters.modelYears.count).joined(separator: ",")
            whereClause += " AND model_year IN (\(placeholders))"
            for year in filters.modelYears.sorted() {
                bindValues.append((Int32(bindIndex), year))
                bindIndex += 1
            }
        }

        return whereClause
    }

    /// Helper method to build WHERE clause for license queries
    private func buildLicenseWhereClause(filters: FilterConfiguration, bindIndex: inout Int, bindValues: inout [(Int32, Any)]) -> String {
        var whereClause = ""

        // Add year filter
        if !filters.years.isEmpty {
            let placeholders = Array(repeating: "?", count: filters.years.count).joined(separator: ",")
            whereClause += " AND year IN (\(placeholders))"
            for year in filters.years.sorted() {
                bindValues.append((Int32(bindIndex), year))
                bindIndex += 1
            }
        }

        // Add region filter
        if !filters.regions.isEmpty {
            let placeholders = Array(repeating: "?", count: filters.regions.count).joined(separator: ",")
            whereClause += " AND admin_region IN (\(placeholders))"
            for region in filters.regions.sorted() {
                bindValues.append((Int32(bindIndex), region))
                bindIndex += 1
            }
        }

        // Add MRC filter
        if !filters.mrcs.isEmpty {
            let placeholders = Array(repeating: "?", count: filters.mrcs.count).joined(separator: ",")
            whereClause += " AND mrc IN (\(placeholders))"
            for mrc in filters.mrcs.sorted() {
                bindValues.append((Int32(bindIndex), mrc))
                bindIndex += 1
            }
        }

        // Add license-specific filters
        if !filters.licenseTypes.isEmpty {
            let placeholders = Array(repeating: "?", count: filters.licenseTypes.count).joined(separator: ",")
            whereClause += " AND license_type IN (\(placeholders))"
            for licenseType in filters.licenseTypes.sorted() {
                bindValues.append((Int32(bindIndex), licenseType))
                bindIndex += 1
            }
        }

        if !filters.ageGroups.isEmpty {
            let placeholders = Array(repeating: "?", count: filters.ageGroups.count).joined(separator: ",")
            whereClause += " AND age_group IN (\(placeholders))"
            for ageGroup in filters.ageGroups.sorted() {
                bindValues.append((Int32(bindIndex), ageGroup))
                bindIndex += 1
            }
        }

        if !filters.genders.isEmpty {
            let placeholders = Array(repeating: "?", count: filters.genders.count).joined(separator: ",")
            whereClause += " AND gender IN (\(placeholders))"
            for gender in filters.genders.sorted() {
                bindValues.append((Int32(bindIndex), gender))
                bindIndex += 1
            }
        }

        // Note: experienceLevels and licenseClasses use multiple boolean columns in database
        // These are handled by specialized query logic elsewhere, not simple WHERE clauses
        // The database has columns like has_driver_license_1234, experience_1234, etc.
        // that get transformed by app logic into single filter categories

        return whereClause
    }

    /// Generates a descriptive name for a data series based on filters (async version with municipality name lookup)
    private func generateSeriesNameAsync(from filters: FilterConfiguration) async -> String {
        var components: [String] = []

        // Add metric information if not count
        if filters.metricType != .count {
            if filters.metricType == .sum || filters.metricType == .average || filters.metricType == .minimum || filters.metricType == .maximum {
                // For aggregate functions, build filter description and use "metric field in [filters]" format
                var filterComponents: [String] = []

                // Collect all active filters
                if !filters.vehicleClasses.isEmpty {
                    let vehicle_classes = filters.vehicleClasses
                        .compactMap { VehicleClass(rawValue: $0)?.description }
                        .joined(separator: " OR ")
                    if !vehicle_classes.isEmpty {
                        filterComponents.append("[\(vehicle_classes)]")
                    }
                }

                if !filters.vehicleTypes.isEmpty {
                    let types = Array(filters.vehicleTypes).sorted().map { code in
                        getVehicleTypeDisplayName(for: code)
                    }.joined(separator: " OR ")
                    filterComponents.append("[Type: \(types)]")
                }

                // Add other filters inline below
                if !filters.vehicleMakes.isEmpty {
                    let makes = Array(filters.vehicleMakes).sorted().joined(separator: " OR ")
                    filterComponents.append("[Make: \(makes)]")
                }

                if !filters.vehicleModels.isEmpty {
                    let models = Array(filters.vehicleModels).sorted().joined(separator: " OR ")
                    filterComponents.append("[Model: \(models)]")
                }

                if !filters.vehicleColors.isEmpty {
                    let colors = Array(filters.vehicleColors).sorted().joined(separator: " OR ")
                    filterComponents.append("[Color: \(colors)]")
                }

                if !filters.modelYears.isEmpty {
                    let years = Array(filters.modelYears).sorted(by: >).map { String($0) }.joined(separator: " OR ")
                    filterComponents.append("[Model Year: \(years)]")
                }

                if !filters.fuelTypes.isEmpty {
                    let fuels = filters.fuelTypes
                        .compactMap { FuelType(rawValue: $0)?.description }
                        .joined(separator: " OR ")
                    if !fuels.isEmpty {
                        filterComponents.append("[\(fuels)]")
                    }
                }

                if !filters.regions.isEmpty {
                    filterComponents.append("[Region: \(filters.regions.joined(separator: " OR "))]")
                } else if !filters.mrcs.isEmpty {
                    filterComponents.append("[MRC: \(filters.mrcs.joined(separator: " OR "))]")
                } else if !filters.municipalities.isEmpty {
                    let codeToName = await getMunicipalityCodeToNameMapping()
                    let municipalityNames = filters.municipalities.compactMap { code in
                        codeToName[code] ?? code
                    }
                    filterComponents.append("[Municipality: \(municipalityNames.joined(separator: " OR "))]")
                }

                if !filters.ageRanges.isEmpty {
                    let ageDescriptions = filters.ageRanges.map { ageRange in
                        if let maxAge = ageRange.maxAge {
                            return "\(ageRange.minAge)-\(maxAge) years"
                        } else {
                            return "\(ageRange.minAge)+ years"
                        }
                    }
                    filterComponents.append("[Age: \(ageDescriptions.joined(separator: " OR "))]")
                }

                // Build metric label with field
                var metricLabel = filters.metricType.shortLabel + " \(filters.metricField.rawValue)"
                if let unit = filters.metricField.unit {
                    metricLabel += " (\(unit))"
                }

                // Return in "metric field in [filters]" format
                if !filterComponents.isEmpty {
                    return "\(metricLabel) in [\(filterComponents.joined(separator: " AND "))]"
                } else {
                    return "\(metricLabel) (All Vehicles)"
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
            } else if filters.metricType == .coverage {
                // For coverage, describe the field being analyzed and the mode (percentage or count)
                if let coverageField = filters.coverageField {
                    let modePrefix = filters.coverageAsPercentage ? "% Non-NULL" : "NULL Count"

                    // Build filter context
                    var filterComponents: [String] = []

                    if !filters.vehicleClasses.isEmpty {
                        let vehicle_classes = filters.vehicleClasses
                            .compactMap { VehicleClass(rawValue: $0)?.description }
                            .joined(separator: " OR ")
                        if !vehicle_classes.isEmpty {
                            filterComponents.append("[\(vehicle_classes)]")
                        }
                    }

                    if !filters.vehicleTypes.isEmpty {
                        let types = Array(filters.vehicleTypes).sorted().map { code in
                            getVehicleTypeDisplayName(for: code)
                        }.joined(separator: " OR ")
                        filterComponents.append("[Type: \(types)]")
                    }

                    if !filters.regions.isEmpty {
                        filterComponents.append("[Region: \(filters.regions.joined(separator: " OR "))]")
                    } else if !filters.mrcs.isEmpty {
                        filterComponents.append("[MRC: \(filters.mrcs.joined(separator: " OR "))]")
                    } else if !filters.municipalities.isEmpty {
                        let codeToName = await getMunicipalityCodeToNameMapping()
                        let municipalityNames = filters.municipalities.compactMap { code in
                            codeToName[code] ?? code
                        }
                        filterComponents.append("[Municipality: \(municipalityNames.joined(separator: " OR "))]")
                    }

                    // Return coverage description
                    if !filterComponents.isEmpty {
                        return "\(modePrefix) [\(coverageField.rawValue)] in [\(filterComponents.joined(separator: " AND "))]"
                    } else {
                        return "\(modePrefix) [\(coverageField.rawValue)] in [All \(filters.dataEntityType == .vehicle ? "Vehicles" : "License Holders")]"
                    }
                } else {
                    return "Coverage (No Field Selected)"
                }
            } else if filters.metricType == .roadWearIndex {
                // For Road Wear Index, describe the mode (average or sum) and filters
                let modePrefix = filters.roadWearIndexMode == .average ? "Avg RWI" : "Total RWI"

                // Build filter context
                var filterComponents: [String] = []

                if !filters.vehicleClasses.isEmpty {
                    let vehicle_classes = filters.vehicleClasses
                        .compactMap { VehicleClass(rawValue: $0)?.description }
                        .joined(separator: " OR ")
                    if !vehicle_classes.isEmpty {
                        filterComponents.append("[\(vehicle_classes)]")
                    }
                }

                if !filters.vehicleTypes.isEmpty {
                    let types = Array(filters.vehicleTypes).sorted().map { code in
                        getVehicleTypeDisplayName(for: code)
                    }.joined(separator: " OR ")
                    filterComponents.append("[Type: \(types)]")
                }

                if !filters.vehicleMakes.isEmpty {
                    let makes = Array(filters.vehicleMakes).sorted().joined(separator: " OR ")
                    filterComponents.append("[Make: \(makes)]")
                }

                if !filters.vehicleModels.isEmpty {
                    let models = Array(filters.vehicleModels).sorted().joined(separator: " OR ")
                    filterComponents.append("[Model: \(models)]")
                }

                if !filters.regions.isEmpty {
                    filterComponents.append("[Region: \(filters.regions.joined(separator: " OR "))]")
                } else if !filters.mrcs.isEmpty {
                    filterComponents.append("[MRC: \(filters.mrcs.joined(separator: " OR "))]")
                } else if !filters.municipalities.isEmpty {
                    let codeToName = await getMunicipalityCodeToNameMapping()
                    let municipalityNames = filters.municipalities.compactMap { code in
                        codeToName[code] ?? code
                    }
                    filterComponents.append("[Municipality: \(municipalityNames.joined(separator: " OR "))]")
                }

                // Return Road Wear Index description
                if !filterComponents.isEmpty {
                    return "\(modePrefix) in [\(filterComponents.joined(separator: " AND "))]"
                } else {
                    return "\(modePrefix) (All Vehicles)"
                }
            }
        }

        if !filters.vehicleClasses.isEmpty {
            let vehicle_classes = filters.vehicleClasses
                .compactMap { VehicleClass(rawValue: $0)?.description }
                .joined(separator: " OR ")
            if !vehicle_classes.isEmpty {
                components.append("[\(vehicle_classes)]")
            }
        }

        if !filters.vehicleTypes.isEmpty {
            let types = Array(filters.vehicleTypes).sorted().map { code in
                getVehicleTypeDisplayName(for: code)
            }.joined(separator: " OR ")
            components.append("[Type: \(types)]")
        }

        if !filters.vehicleMakes.isEmpty {
            let makes = Array(filters.vehicleMakes).sorted().joined(separator: " OR ")
            components.append("[Make: \(makes)]")
        }

        if !filters.vehicleModels.isEmpty {
            let models = Array(filters.vehicleModels).sorted().joined(separator: " OR ")
            components.append("[Model: \(models)]")
        }

        if !filters.vehicleColors.isEmpty {
            let colors = Array(filters.vehicleColors).sorted().joined(separator: " OR ")
            components.append("[Color: \(colors)]")
        }

        if !filters.modelYears.isEmpty {
            let years = Array(filters.modelYears).sorted(by: >).map { String($0) }.joined(separator: " OR ")
            components.append("[Model Year: \(years)]")
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

        // Vehicle age ranges
        if !filters.ageRanges.isEmpty {
            let ageDescriptions = filters.ageRanges.map { ageRange in
                if let maxAge = ageRange.maxAge {
                    return "\(ageRange.minAge)-\(maxAge) years"
                } else {
                    return "\(ageRange.minAge)+ years"
                }
            }
            components.append("[Age: \(ageDescriptions.joined(separator: " OR "))]")
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

        if !baseFilters.vehicleClasses.isEmpty {
            let classifications = baseFilters.vehicleClasses
                .compactMap { VehicleClass(rawValue: $0)?.description }
                .joined(separator: " OR ")
            if !classifications.isEmpty {
                baseComponents.append("[\(classifications)]")
            }
        }

        if !baseFilters.vehicleTypes.isEmpty {
            let types = Array(baseFilters.vehicleTypes).sorted().joined(separator: " OR ")
            baseComponents.append("[Type: \(types)]")
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
        } else if !baseFilters.mrcs.isEmpty {
            baseComponents.append("[MRC: \(baseFilters.mrcs.joined(separator: " OR "))]")
        } else if !baseFilters.municipalities.isEmpty {
            // Convert municipality codes to names for display
            let codeToName = await getMunicipalityCodeToNameMapping()
            let municipalityNames = baseFilters.municipalities.compactMap { code in
                codeToName[code] ?? code  // Fallback to code if name not found
            }
            baseComponents.append("[Municipality: \(municipalityNames.joined(separator: " OR "))]")
        }

        if !baseFilters.vehicleMakes.isEmpty {
            let makes = Array(baseFilters.vehicleMakes).sorted().joined(separator: " OR ")
            baseComponents.append("[Make: \(makes)]")
        }

        if !baseFilters.vehicleModels.isEmpty {
            let models = Array(baseFilters.vehicleModels).sorted().joined(separator: " OR ")
            baseComponents.append("[Model: \(models)]")
        }

        if !baseFilters.vehicleColors.isEmpty {
            let colors = Array(baseFilters.vehicleColors).sorted().joined(separator: " OR ")
            baseComponents.append("[Color: \(colors)]")
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

    /// Get display name for vehicle type code (e.g., "AU" -> "Automobile or Light Truck")
    /// Returns only the descriptive text for consistency with Vehicle Class display
    private func getVehicleTypeDisplayName(for code: String) -> String {
        // Handle special cases
        if code.isEmpty || code.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Not Specified"
        }

        if code.uppercased() == "UK" {
            return "Unknown"
        }

        // Map vehicle type codes to descriptions
        switch code.uppercased() {
        case "AB": return "Bus"
        case "AT": return "Dealer Plates"
        case "AU": return "Automobile or Light Truck"
        case "CA": return "Truck or Road Tractor"
        case "CY": return "Moped"
        case "HM": return "Motorhome"
        case "MC": return "Motorcycle"
        case "MN": return "Snowmobile"
        case "NV": return "Other Off-Road Vehicle"
        case "SN": return "Snow Blower"
        case "VO": return "Tool Vehicle"
        case "VT": return "All-Terrain Vehicle"
        default: return code  // Return code as-is if not recognized
        }
    }

    /// Determine which filter category was dropped when creating percentage baseline
    private func determineDifference(original: FilterConfiguration, baseline: PercentageBaseFilters) -> String? {
        if !original.fuelTypes.isEmpty && baseline.fuelTypes.isEmpty {
            return "fuel types"
        }
        if !original.vehicleClasses.isEmpty && baseline.vehicleClasses.isEmpty {
            return "vehicle classes"
        }
        if !original.vehicleTypes.isEmpty && baseline.vehicleTypes.isEmpty {
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
        case "vehicle classes":
            if filters.vehicleClasses.count == 1, let classification = filters.vehicleClasses.first {
                return VehicleClass(rawValue: classification)?.description ?? classification
            } else if !filters.vehicleClasses.isEmpty {
                let classifications = filters.vehicleClasses.compactMap { VehicleClass(rawValue: $0)?.description }.joined(separator: " & ")
                return classifications.isEmpty ? nil : classifications
            }
        case "vehicle types":
            if filters.vehicleTypes.count == 1 {
                return filters.vehicleTypes.first!
            } else if !filters.vehicleTypes.isEmpty {
                return filters.vehicleTypes.joined(separator: " & ")
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
                let years = Array(filters.modelYears).sorted().map(String.init).joined(separator: " & ")
                return "\(years) Model Years"
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
                let classes = Array(filters.licenseClasses).sorted().joined(separator: " & ")
                return "License Classes \(classes)"
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
            } else if filters.metricType == .coverage {
                // For coverage, show the mode and field being analyzed
                if let coverageField = filters.coverageField {
                    let modePrefix = filters.coverageAsPercentage ? "% Non-NULL" : "NULL Count"
                    metricLabel = "\(modePrefix) [\(coverageField.rawValue)]"
                } else {
                    metricLabel = "Coverage (No Field)"
                }
            }
            components.append(metricLabel)
        }

        if !filters.vehicleClasses.isEmpty {
            let classifications = filters.vehicleClasses
                .compactMap { VehicleClass(rawValue: $0)?.description }
                .joined(separator: " OR ")
            if !classifications.isEmpty {
                components.append("[\(classifications)]")
            }
        }

        if !filters.vehicleMakes.isEmpty {
            let makes = Array(filters.vehicleMakes).sorted().joined(separator: " OR ")
            components.append("[Make: \(makes)]")
        }

        if !filters.vehicleModels.isEmpty {
            let models = Array(filters.vehicleModels).sorted().joined(separator: " OR ")
            components.append("[Model: \(models)]")
        }

        if !filters.vehicleColors.isEmpty {
            let colors = Array(filters.vehicleColors).sorted().joined(separator: " OR ")
            components.append("[Color: \(colors)]")
        }

        if !filters.modelYears.isEmpty {
            let years = Array(filters.modelYears).sorted(by: >).map { String($0) }.joined(separator: " OR ")
            components.append("[Model Year: \(years)]")
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
        // Use enumeration-based data
        if useOptimizedQueries, let filterCacheManager = filterCacheManager {
            do {
                let years = try await filterCacheManager.getAvailableYears()
                print("✅ Using enumeration-based years (\(years.count) items)")
                return years
            } catch {
                print("⚠️ Failed to load enumeration years, falling back to database query: \(error)")
            }
        }

        // Fall back to database query
        print("📊 Querying years from database...")
        return await getYearsFromDatabase()
    }

    /// Gets available years for a specific data entity type
    func getAvailableYears(for dataType: DataEntityType) async -> [Int] {
        print("🔍 getAvailableYears(for: \(dataType)) - Data-type-aware query")

        // Use enumeration-based data
        if useOptimizedQueries, let filterCacheManager = filterCacheManager {
            do {
                let years = try await filterCacheManager.getAvailableYears()
                print("✅ Using enumeration-based years (\(years.count) items) for \(dataType)")
                return years
            } catch {
                print("⚠️ Failed to load enumeration years, falling back to database query: \(error)")
            }
        }

        // Fall back to database query
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
    
    /// Gets available regions - uses enumeration tables
    func getAvailableRegions(for dataEntityType: DataEntityType = .vehicle) async -> [String] {
        // Use enumeration-based data
        if useOptimizedQueries, let filterCacheManager = filterCacheManager {
            do {
                let filterItems = try await filterCacheManager.getAvailableRegions()
                print("✅ Using enumeration-based regions (\(filterItems.count) items)")
                return filterItems.map { $0.displayName }
            } catch {
                print("⚠️ Failed to load enumeration regions, falling back to database query: \(error)")
            }
        }

        // Fall back to database query
        return await getRegionsFromDatabase(for: dataEntityType)
    }
    
    /// Gets available MRCs - uses enumeration tables
    func getAvailableMRCs(for dataEntityType: DataEntityType = .vehicle) async -> [String] {
        // Use enumeration-based data
        if useOptimizedQueries, let filterCacheManager = filterCacheManager {
            do {
                let filterItems = try await filterCacheManager.getAvailableMRCs()
                print("✅ Using enumeration-based MRCs (\(filterItems.count) items)")
                return filterItems.map { $0.displayName }
            } catch {
                print("⚠️ Failed to load enumeration MRCs, falling back to database query: \(error)")
            }
        }

        // Fall back to database query
        return await getMRCsFromDatabase(for: dataEntityType)
    }
    
    /// Prepares database for bulk import session
    func beginBulkImport() async {
        // Create enumeration tables if they don't exist (first import)
        print("🔧 Ensuring enumeration tables exist...")
        do {
            let enumManager = CategoricalEnumManager(databaseManager: self)
            try await enumManager.createEnumerationTables()
        } catch {
            print("⚠️ Note: Enumeration tables may already exist or creation failed: \(error)")
        }

        // Create regularization table if it doesn't exist
        print("🔧 Ensuring regularization table exists...")
        do {
            if let regManager = regularizationManager {
                try await regManager.createRegularizationTable()
            }
        } catch {
            print("⚠️ Note: Regularization table may already exist or creation failed: \(error)")
        }

        // Load bundled geographic data if not already loaded
        let geoCount = await getGeographicEntityCount()
        if geoCount == 0 {
            print("📍 Loading bundled geographic data...")
            do {
                let geoImporter = GeographicDataImporter(databaseManager: self)
                try await geoImporter.importBundledGeographicData()
            } catch {
                print("⚠️ Failed to load geographic data: \(error)")
            }
        } else {
            print("✅ Geographic data already loaded (\(geoCount) entities)")
        }

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
                    // Temporarily disable non-categorical indexes for faster inserts
                    sqlite3_exec(db, "DROP INDEX IF EXISTS idx_vehicles_year", nil, nil, nil)
                    sqlite3_exec(db, "DROP INDEX IF EXISTS idx_vehicles_model_year", nil, nil, nil)
                    sqlite3_exec(db, "DROP INDEX IF EXISTS idx_licenses_year", nil, nil, nil)
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
    /// - Parameter skipCacheRefresh: If true, skips cache refresh (for batch imports that refresh once at end)
    func endBulkImport(progressManager: ImportProgressManager? = nil, skipCacheRefresh: Bool = false) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume()
                    return
                }
                
                let totalRecords = self?.getTotalRecordCount() ?? 0
                let indexStartTime = Date()
                
                if totalRecords < 50_000_000 {
                    print("🔧 Updating query planner statistics...")

                    // Update query planner statistics (integer indexes already exist from createTablesIfNeeded)
                    sqlite3_exec(db, "ANALYZE vehicles", nil, nil, nil)
                    sqlite3_exec(db, "ANALYZE licenses", nil, nil, nil)
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

                continuation.resume()
            }
        }

        // Skip full cache refresh if this is part of a batch import
        // But still invalidate cache and trigger UI refresh for incremental updates
        guard !skipCacheRefresh else {
            print("⏭️ Skipping full cache refresh (batch import in progress)")

            // Invalidate cache so next access reloads from updated enum tables
            filterCacheManager?.invalidateCache()

            // Trigger UI refresh so filter sections update incrementally
            await Task { @MainActor in
                self.dataVersion += 1
                print("🔔 UI notified of incremental data update (dataVersion: \(self.dataVersion))")
            }.value
            return
        }

        // Refresh filter caches after indexes are rebuilt (outside dbQueue to avoid blocking)
        print("🔄 Refreshing filter caches...")
        await Task { @MainActor in
            progressManager?.updateIndexingOperation("Refreshing filter cache...")
        }.value

        // Invalidate and reload enumeration-based cache
        filterCacheManager?.invalidateCache()
        do {
            try await filterCacheManager?.initializeCache()
            print("✅ Enumeration-based filter cache refreshed")
        } catch {
            print("⚠️ Failed to refresh enumeration cache: \(error)")
        }

        // Refresh legacy string-based cache
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task {
                await self.refreshFilterCache()
                continuation.resume()
            }
        }

        // Trigger UI refresh AFTER cache is fully loaded
        await Task { @MainActor in
            self.dataVersion += 1
            print("🔔 UI notified of data update (dataVersion: \(self.dataVersion))")
        }.value
    }

    /// Refreshes all caches after a batch import completes
    func refreshAllCachesAfterBatchImport() async {
        print("🔄 Refreshing filter caches after batch import...")

        // Invalidate and reload enumeration-based cache
        filterCacheManager?.invalidateCache()
        do {
            try await filterCacheManager?.initializeCache()
            print("✅ Enumeration-based filter cache refreshed")
        } catch {
            print("⚠️ Failed to refresh enumeration cache: \(error)")
        }

        // Refresh legacy string-based cache
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task {
                await self.refreshFilterCache()
                continuation.resume()
            }
        }

        // Trigger UI refresh AFTER cache is fully loaded
        await Task { @MainActor in
            self.dataVersion += 1
            print("🔔 UI notified of data update after batch import (dataVersion: \(self.dataVersion))")
        }.value
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

    /// Gets count of geographic entities
    private func getGeographicEntityCount() async -> Int {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: 0)
                    return
                }

                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }

                let sql = "SELECT COUNT(*) FROM geographic_entities"
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: 0)
                    return
                }

                if sqlite3_step(stmt) == SQLITE_ROW {
                    continuation.resume(returning: Int(sqlite3_column_int64(stmt, 0)))
                } else {
                    continuation.resume(returning: 0)
                }
            }
        }
    }

    /// Gets available vehicle classes - uses enumeration tables
    func getAvailableVehicleClasses() async -> [String] {
        // Use enumeration-based data
        if useOptimizedQueries, let filterCacheManager = filterCacheManager {
            do {
                let filterItems = try await filterCacheManager.getAvailableVehicleClasses()
                print("✅ Using enumeration-based vehicle classes (\(filterItems.count) items)")
                return filterItems.map { $0.displayName }
            } catch {
                print("⚠️ Failed to load enumeration vehicle classes, falling back to database query: \(error)")
            }
        }

        // Fall back to database query
        return await getClassesFromDatabase()
    }

    /// Gets available vehicle types - uses enumeration tables
    func getAvailableVehicleTypes() async -> [String] {
        // Use enumeration-based data
        if useOptimizedQueries, let filterCacheManager = filterCacheManager {
            do {
                let filterItems = try await filterCacheManager.getAvailableVehicleTypes()
                print("✅ Using enumeration-based vehicle types (\(filterItems.count) items)")
                return filterItems.map { $0.displayName }
            } catch {
                print("⚠️ Failed to load enumeration vehicle types, falling back to database query: \(error)")
            }
        }

        // Fall back to database query
        return await getVehicleTypesFromDatabase()
    }

    /// Gets available vehicle makes - uses enumeration cache with badges
    func getAvailableVehicleMakes() async -> [String] {
        if useOptimizedQueries, let filterCacheManager = filterCacheManager {
            do {
                let filterItems = try await filterCacheManager.getAvailableMakes()
                print("✅ Using enumeration-based makes (\(filterItems.count) items)")
                return filterItems.map { $0.displayName }
            } catch {
                print("⚠️ Failed to load enumeration makes, falling back to database query: \(error)")
            }
        }

        // Fall back to database query
        return await getVehicleMakesFromDatabase()
    }

    /// Gets available vehicle models - uses enumeration cache with badges
    func getAvailableVehicleModels() async -> [String] {
        if useOptimizedQueries, let filterCacheManager = filterCacheManager {
            do {
                let filterItems = try await filterCacheManager.getAvailableModels()
                print("✅ Using enumeration-based models (\(filterItems.count) items with badges)")
                return filterItems.map { $0.displayName }
            } catch {
                print("⚠️ Failed to load enumeration models, falling back to database query: \(error)")
            }
        }

        // Fall back to database query
        return await getVehicleModelsFromDatabase()
    }

    /// Gets available model years - queries database directly
    func getAvailableModelYears() async -> [Int] {
        return await getModelYearsFromDatabase()
    }

    /// Gets available vehicle colors - queries database directly
    func getAvailableVehicleColors() async -> [String] {
        return await getVehicleColorsFromDatabase()
    }

    // MARK: - License Data Methods

    /// Gets available license types from database
    func getAvailableLicenseTypes() async -> [String] {
        print("⚠️ License types cache miss, falling back to database query")

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

    /// Gets available age groups from database
    func getAvailableAgeGroups() async -> [String] {
        print("⚠️ Age groups cache miss, falling back to database query")

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

    /// Gets available genders from database
    func getAvailableGenders() async -> [String] {
        print("⚠️ Genders cache miss, falling back to database query")

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

    /// Gets available experience levels from database
    func getAvailableExperienceLevels() async -> [String] {
        print("⚠️ Experience levels cache miss, falling back to database query")

        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                var levels: [String] = []
                let query = "SELECT DISTINCT experience_global FROM licenses WHERE experience_global IS NOT NULL AND experience_global != '' ORDER BY experience_global"
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

    /// Gets available license classes from database
    func getAvailableLicenseClasses() async -> [String] {
        print("⚠️ License classes cache miss, falling back to database query")

        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                var classes: Set<String> = []

                // Use centralized mapping for consistent display names
                let licenseMapping = self?.getLicenseClassMapping() ?? []

                for (column, displayName) in licenseMapping {
                    let query = "SELECT COUNT(*) FROM licenses WHERE \(column) = 1"
                    var stmt: OpaquePointer?

                    if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                        if sqlite3_step(stmt) == SQLITE_ROW {
                            let count = sqlite3_column_int(stmt, 0)
                            if count > 0 {
                                classes.insert(displayName)
                            }
                        }
                    }
                    sqlite3_finalize(stmt)
                }
                continuation.resume(returning: Array(classes).sorted())
            }
        }
    }

    // MARK: - License Class Mapping

    /// Centralized mapping between UI display names and database columns for license classes
    private func getLicenseClassMapping() -> [(column: String, displayName: String)] {
        return [
            // Driver license classes
            ("has_driver_license_1234", "1-2-3-4"),
            ("has_driver_license_5", "5"),
            ("has_driver_license_6abce", "6A-6B-6C-6E"),
            ("has_driver_license_6d", "6D"),
            ("has_driver_license_8", "8"),
            // Learner permit classes
            ("has_learner_permit_123", "Learner 1-2-3"),
            ("has_learner_permit_5", "Learner 5"),
            ("has_learner_permit_6a6r", "Learner 6A-6R"),
            // Probationary indicator
            ("is_probationary", "Probationary")
        ]
    }

    /// Maps UI display name to database column name
    private func getDatabaseColumn(for displayName: String) -> String? {
        return getLicenseClassMapping().first { $0.displayName == displayName }?.column
    }

    // MARK: - Filter Cache Management

    /// Refreshes the filter cache with current database values
    func refreshFilterCache() async {
        // Prevent concurrent refreshes
        refreshLock.lock()
        if isRefreshingCache {
            refreshLock.unlock()
            print("⏳ Cache refresh already in progress, skipping...")
            return
        }
        isRefreshingCache = true
        refreshLock.unlock()

        defer {
            refreshLock.lock()
            isRefreshingCache = false
            refreshLock.unlock()
        }

        print("🔄 Refreshing filter cache from enumeration tables...")

        // Invalidate and reload enumeration-based cache
        filterCacheManager?.invalidateCache()
        print("✅ Filter cache refresh completed (enumeration tables reloaded)")
    }
    
    /// Clears the filter cache (useful for troubleshooting)
    func clearFilterCache() {
        filterCacheManager?.invalidateCache()
        print("🗑️ Filter cache cleared (enumeration-based)")
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

    /// Gets database page size from PRAGMA
    func getDatabasePageSize() async -> Int {
        return await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: 0)
                    return
                }

                var pageSize = 0
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, "PRAGMA page_size", -1, &stmt, nil) == SQLITE_OK {
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        pageSize = Int(sqlite3_column_int(stmt, 0))
                    }
                    sqlite3_finalize(stmt)
                }
                continuation.resume(returning: pageSize)
            }
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
        let pageSize = await getDatabasePageSize()

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
            pageSizeBytes: pageSize,
            lastUpdated: Date()
        )
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

                // Query enumeration table for admin regions
                let query = "SELECT name FROM admin_region_enum ORDER BY code"
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

                // Query admin regions from enumeration table (same for both vehicles and licenses)
                let query = "SELECT name FROM admin_region_enum ORDER BY code"
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
    
    /// Internal method to query classes directly from database
    private func getClassesFromDatabase() async -> [String] {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                let query = "SELECT DISTINCT class FROM vehicles ORDER BY class"
                var stmt: OpaquePointer?

                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                var vehicle_classes: [String] = []
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let classPtr = sqlite3_column_text(stmt, 0) {
                            vehicle_classes.append(String(cString: classPtr))
                        }
                    }
                }

                continuation.resume(returning: vehicle_classes)
            }
        }
    }

    private func getVehicleTypesFromDatabase() async -> [String] {
        await withCheckedContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(returning: [])
                    return
                }

                let query = "SELECT DISTINCT code FROM vehicle_type_enum ORDER BY code"
                var stmt: OpaquePointer?

                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }

                var vehicle_types: [String] = []
                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let typePtr = sqlite3_column_text(stmt, 0) {
                            vehicle_types.append(String(cString: typePtr))
                        }
                    }
                }

                continuation.resume(returning: vehicle_types)
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

                let query = "SELECT DISTINCT name FROM make_enum ORDER BY name"
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

                let query = "SELECT DISTINCT name FROM model_enum ORDER BY name"
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

                let query = "SELECT DISTINCT name FROM color_enum ORDER BY name"
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

    /// Gets available municipalities for vehicle data only - uses cache when possible
    /// Note: Municipalities are only available for vehicle data, not license data
    func getAvailableMunicipalities(for dataType: DataEntityType = .vehicle) async -> [String] {
        // Municipalities only exist for vehicle data
        guard dataType == .vehicle else {
            return []
        }

        // Use enumeration-based data
        if useOptimizedQueries, let filterCacheManager = filterCacheManager {
            do {
                let filterItems = try await filterCacheManager.getAvailableMunicipalities()
                print("✅ Using enumeration-based municipalities (\(filterItems.count) items)")
                return filterItems.map { $0.displayName }
            } catch {
                print("⚠️ Failed to load enumeration municipalities, falling back to database query: \(error)")
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

    /// Gets municipality code-to-name mapping for UI display
    func getMunicipalityCodeToNameMapping() async -> [String: String] {
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
                        year, vehicle_sequence, model_year, net_mass, cylinder_count,
                        displacement, max_axles,
                        year_id, vehicle_class_id, vehicle_type_id, make_id, model_id, model_year_id,
                        cylinder_count_id, axle_count_id, original_color_id, fuel_type_id,
                        admin_region_id, mrc_id, municipality_id,
                        net_mass_int, displacement_int
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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

                // Build enumeration lookup caches for fast in-memory lookups (preserves performance)
                print("🔄 Building enumeration caches for batch...")
                var yearEnumCache: [Int: Int] = [:]
                var classEnumCache: [String: Int] = [:]
                var vehicleTypeEnumCache: [String: Int] = [:]
                var makeEnumCache: [String: Int] = [:]
                var modelEnumCache: [String: Int] = [:]  // Key: "make|model"
                var modelYearEnumCache: [Int: Int] = [:]
                var cylinderCountEnumCache: [Int: Int] = [:]
                var axleCountEnumCache: [Int: Int] = [:]
                var colorEnumCache: [String: Int] = [:]
                var fuelTypeEnumCache: [String: Int] = [:]
                var adminRegionEnumCache: [String: Int] = [:]
                var mrcEnumCache: [String: Int] = [:]
                var municipalityEnumCache: [String: Int] = [:]

                // Helper to load string enum cache
                func loadEnumCache(table: String, keyColumn: String, cache: inout [String: Int]) {
                    let sql = "SELECT id, \(keyColumn) FROM \(table);"
                    var cacheStmt: OpaquePointer?
                    defer { sqlite3_finalize(cacheStmt) }
                    if sqlite3_prepare_v2(db, sql, -1, &cacheStmt, nil) == SQLITE_OK {
                        while sqlite3_step(cacheStmt) == SQLITE_ROW {
                            let id = Int(sqlite3_column_int(cacheStmt, 0))
                            if let keyPtr = sqlite3_column_text(cacheStmt, 1) {
                                cache[String(cString: keyPtr)] = id
                            }
                        }
                    }
                }

                // Helper to load integer enum cache
                func loadIntEnumCache(table: String, keyColumn: String, cache: inout [Int: Int]) {
                    let sql = "SELECT id, \(keyColumn) FROM \(table);"
                    var cacheStmt: OpaquePointer?
                    defer { sqlite3_finalize(cacheStmt) }
                    if sqlite3_prepare_v2(db, sql, -1, &cacheStmt, nil) == SQLITE_OK {
                        while sqlite3_step(cacheStmt) == SQLITE_ROW {
                            cache[Int(sqlite3_column_int(cacheStmt, 1))] = Int(sqlite3_column_int(cacheStmt, 0))
                        }
                    }
                }

                // Load all enum caches
                loadIntEnumCache(table: "year_enum", keyColumn: "year", cache: &yearEnumCache)
                loadEnumCache(table: "vehicle_class_enum", keyColumn: "code", cache: &classEnumCache)
                loadEnumCache(table: "vehicle_type_enum", keyColumn: "code", cache: &vehicleTypeEnumCache)
                loadEnumCache(table: "make_enum", keyColumn: "name", cache: &makeEnumCache)
                loadIntEnumCache(table: "model_year_enum", keyColumn: "year", cache: &modelYearEnumCache)
                loadIntEnumCache(table: "cylinder_count_enum", keyColumn: "count", cache: &cylinderCountEnumCache)
                loadIntEnumCache(table: "axle_count_enum", keyColumn: "count", cache: &axleCountEnumCache)
                loadEnumCache(table: "color_enum", keyColumn: "name", cache: &colorEnumCache)
                loadEnumCache(table: "fuel_type_enum", keyColumn: "code", cache: &fuelTypeEnumCache)
                loadEnumCache(table: "admin_region_enum", keyColumn: "code", cache: &adminRegionEnumCache)
                loadEnumCache(table: "mrc_enum", keyColumn: "code", cache: &mrcEnumCache)
                loadEnumCache(table: "municipality_enum", keyColumn: "code", cache: &municipalityEnumCache)

                // Load model enum with composite key (make|model)
                do {
                    let sql = "SELECT mo.id, mo.name, ma.name FROM model_enum mo INNER JOIN make_enum ma ON mo.make_id = ma.id;"
                    var modelStmt: OpaquePointer?
                    defer { sqlite3_finalize(modelStmt) }
                    if sqlite3_prepare_v2(db, sql, -1, &modelStmt, nil) == SQLITE_OK {
                        while sqlite3_step(modelStmt) == SQLITE_ROW {
                            if let modelPtr = sqlite3_column_text(modelStmt, 1), let makePtr = sqlite3_column_text(modelStmt, 2) {
                                let key = "\(String(cString: makePtr))|\(String(cString: modelPtr))"
                                modelEnumCache[key] = Int(sqlite3_column_int(modelStmt, 0))
                            }
                        }
                    }
                }

                // Helper to get or create string enum ID
                func getOrCreateEnumId(table: String, column: String, value: String, cache: inout [String: Int]) -> Int? {
                    if let id = cache[value] { return id }

                    // Try INSERT
                    let insertSql = "INSERT OR IGNORE INTO \(table) (\(column)) VALUES (?);"
                    var insertStmt: OpaquePointer?
                    defer { sqlite3_finalize(insertStmt) }
                    if sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(insertStmt, 1, value, -1, SQLITE_TRANSIENT)
                        let insertResult = sqlite3_step(insertStmt)
                        if insertResult != SQLITE_DONE {
                            if let errorMsg = sqlite3_errmsg(db) {
                                print("⚠️ Insert failed for \(table).\(column)='\(value)': \(String(cString: errorMsg))")
                            }
                        }
                    } else {
                        if let errorMsg = sqlite3_errmsg(db) {
                            print("⚠️ Prepare INSERT failed for \(table): \(String(cString: errorMsg))")
                        }
                        return nil
                    }

                    // Try SELECT
                    let selectSql = "SELECT id FROM \(table) WHERE \(column) = ?;"
                    var selectStmt: OpaquePointer?
                    defer { sqlite3_finalize(selectStmt) }
                    if sqlite3_prepare_v2(db, selectSql, -1, &selectStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(selectStmt, 1, value, -1, SQLITE_TRANSIENT)
                        if sqlite3_step(selectStmt) == SQLITE_ROW {
                            let id = Int(sqlite3_column_int(selectStmt, 0))
                            cache[value] = id
                            return id
                        } else {
                            print("⚠️ SELECT returned no rows for \(table).\(column)='\(value)'")
                        }
                    } else {
                        if let errorMsg = sqlite3_errmsg(db) {
                            print("⚠️ Prepare SELECT failed for \(table): \(String(cString: errorMsg))")
                        }
                    }
                    return nil
                }

                // Helper to get or create geographic enum ID (requires both code and name)
                func getOrCreateGeoEnumId(table: String, name: String, code: String, cache: inout [String: Int]) -> Int? {
                    if let id = cache[code] { return id }

                    // Try INSERT with both code and name
                    let insertSql = "INSERT OR IGNORE INTO \(table) (code, name) VALUES (?, ?);"
                    var insertStmt: OpaquePointer?
                    defer { sqlite3_finalize(insertStmt) }
                    if sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(insertStmt, 1, code, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 2, name, -1, SQLITE_TRANSIENT)
                        sqlite3_step(insertStmt)
                    } else {
                        return nil
                    }

                    // Try SELECT
                    let selectSql = "SELECT id FROM \(table) WHERE code = ?;"
                    var selectStmt: OpaquePointer?
                    defer { sqlite3_finalize(selectStmt) }
                    if sqlite3_prepare_v2(db, selectSql, -1, &selectStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(selectStmt, 1, code, -1, SQLITE_TRANSIENT)
                        if sqlite3_step(selectStmt) == SQLITE_ROW {
                            let id = Int(sqlite3_column_int(selectStmt, 0))
                            cache[code] = id
                            return id
                        }
                    }
                    return nil
                }

                // Helper to get or create class enum ID (requires code and description)
                func getOrCreateClassEnumId(code: String, description: String, cache: inout [String: Int]) -> Int? {
                    if let id = cache[code] { return id }

                    // Try INSERT with both code and description
                    let insertSql = "INSERT OR IGNORE INTO vehicle_class_enum (code, description) VALUES (?, ?);"
                    var insertStmt: OpaquePointer?
                    defer { sqlite3_finalize(insertStmt) }
                    if sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(insertStmt, 1, code, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 2, description, -1, SQLITE_TRANSIENT)
                        sqlite3_step(insertStmt)
                    } else {
                        return nil
                    }

                    // Try SELECT
                    let selectSql = "SELECT id FROM vehicle_class_enum WHERE code = ?;"
                    var selectStmt: OpaquePointer?
                    defer { sqlite3_finalize(selectStmt) }
                    if sqlite3_prepare_v2(db, selectSql, -1, &selectStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(selectStmt, 1, code, -1, SQLITE_TRANSIENT)
                        if sqlite3_step(selectStmt) == SQLITE_ROW {
                            let id = Int(sqlite3_column_int(selectStmt, 0))
                            cache[code] = id
                            return id
                        }
                    }
                    return nil
                }

                // Helper to get or create vehicle type enum ID (requires code and description)
                func getOrCreateVehicleTypeEnumId(code: String, description: String, cache: inout [String: Int]) -> Int? {
                    if let id = cache[code] { return id }

                    // Try INSERT with both code and description
                    let insertSql = "INSERT OR IGNORE INTO vehicle_type_enum (code, description) VALUES (?, ?);"
                    var insertStmt: OpaquePointer?
                    defer { sqlite3_finalize(insertStmt) }
                    if sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(insertStmt, 1, code, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 2, description, -1, SQLITE_TRANSIENT)
                        sqlite3_step(insertStmt)
                    }

                    // Then SELECT to get ID
                    let selectSql = "SELECT id FROM vehicle_type_enum WHERE code = ?;"
                    var selectStmt: OpaquePointer?
                    defer { sqlite3_finalize(selectStmt) }
                    if sqlite3_prepare_v2(db, selectSql, -1, &selectStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(selectStmt, 1, code, -1, SQLITE_TRANSIENT)
                        if sqlite3_step(selectStmt) == SQLITE_ROW {
                            let id = Int(sqlite3_column_int(selectStmt, 0))
                            cache[code] = id
                            return id
                        }
                    }
                    return nil
                }

                // Helper to get or create fuel type enum ID (requires code and description)
                func getOrCreateFuelTypeEnumId(code: String, description: String, cache: inout [String: Int]) -> Int? {
                    if let id = cache[code] { return id }

                    // Try INSERT with both code and description
                    let insertSql = "INSERT OR IGNORE INTO fuel_type_enum (code, description) VALUES (?, ?);"
                    var insertStmt: OpaquePointer?
                    defer { sqlite3_finalize(insertStmt) }
                    if sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(insertStmt, 1, code, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 2, description, -1, SQLITE_TRANSIENT)
                        sqlite3_step(insertStmt)
                    } else {
                        return nil
                    }

                    // Try SELECT
                    let selectSql = "SELECT id FROM fuel_type_enum WHERE code = ?;"
                    var selectStmt: OpaquePointer?
                    defer { sqlite3_finalize(selectStmt) }
                    if sqlite3_prepare_v2(db, selectSql, -1, &selectStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(selectStmt, 1, code, -1, SQLITE_TRANSIENT)
                        if sqlite3_step(selectStmt) == SQLITE_ROW {
                            let id = Int(sqlite3_column_int(selectStmt, 0))
                            cache[code] = id
                            return id
                        }
                    }
                    return nil
                }

                // Helper to get or create integer enum ID
                func getOrCreateIntEnumId(table: String, column: String, value: Int, cache: inout [Int: Int]) -> Int? {
                    if let id = cache[value] { return id }
                    let insertSql = "INSERT OR IGNORE INTO \(table) (\(column)) VALUES (?);"
                    var insertStmt: OpaquePointer?
                    defer { sqlite3_finalize(insertStmt) }
                    if sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK {
                        sqlite3_bind_int(insertStmt, 1, Int32(value))
                        sqlite3_step(insertStmt)
                    }
                    let selectSql = "SELECT id FROM \(table) WHERE \(column) = ?;"
                    var selectStmt: OpaquePointer?
                    defer { sqlite3_finalize(selectStmt) }
                    if sqlite3_prepare_v2(db, selectSql, -1, &selectStmt, nil) == SQLITE_OK {
                        sqlite3_bind_int(selectStmt, 1, Int32(value))
                        if sqlite3_step(selectStmt) == SQLITE_ROW {
                            let id = Int(sqlite3_column_int(selectStmt, 0))
                            cache[value] = id
                            return id
                        }
                    }
                    return nil
                }

                // Helper to extract name and code from geographic strings (e.g., "Montréal (06)" → ("Montréal", "06"))
                func extractNameAndCode(from string: String) -> (name: String, code: String)? {
                    if let startIdx = string.firstIndex(of: "("),
                       let endIdx = string.firstIndex(of: ")") {
                        let name = string[..<startIdx].trimmingCharacters(in: .whitespaces)
                        let code = string[string.index(after: startIdx)..<endIdx].trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty && !code.isEmpty {
                            return (name, code)
                        }
                    }
                    return nil
                }

                // Build municipality code-to-name lookup from geographic_entities
                var municipalityNameCache: [String: String] = [:]
                let geoLookupSql = "SELECT code, name FROM geographic_entities;"
                var geoStmt: OpaquePointer?
                defer { sqlite3_finalize(geoStmt) }
                if sqlite3_prepare_v2(db, geoLookupSql, -1, &geoStmt, nil) == SQLITE_OK {
                    while sqlite3_step(geoStmt) == SQLITE_ROW {
                        if let codePtr = sqlite3_column_text(geoStmt, 0),
                           let namePtr = sqlite3_column_text(geoStmt, 1) {
                            municipalityNameCache[String(cString: codePtr)] = String(cString: namePtr)
                        }
                    }
                }

                print("✅ Caches built: \(classEnumCache.count) classes, \(vehicleTypeEnumCache.count) types, \(makeEnumCache.count) makes, \(fuelTypeEnumCache.count) fuel types, \(municipalityNameCache.count) municipalities")
                print("Starting batch import: \(records.count) records for year \(year)")

                for record in records {
                    // Extract values from CSV (keep for enum population)
                    let vehicle_class = record["CLAS"] ?? "UNK"
                    let vehicle_type = record["TYP_VEH_CATEG_USA"]
                    let make = record["MARQ_VEH"]
                    let model = record["MODEL_VEH"]
                    let color = record["COUL_ORIG"]
                    let fuelType = record["TYP_CARBU"]
                    let adminRegion = record["REG_ADM"] ?? "Unknown Region"
                    let mrc = record["MRC"] ?? "Unknown MRC"
                    let geoCode = record["CG_FIXE"] ?? "00000"
                    let cylinderCount = record["NB_CYL"]
                    let maxAxles = record["NB_ESIEU_MAX"]
                    let netMass = record["MASSE_NETTE"]
                    let displacement = record["CYL_VEH"]

                    // Bind non-categorical columns (positions 1-7)
                    sqlite3_bind_int(stmt, 1, Int32(year))
                    importer.bindRequiredTextToStatement(stmt, 2, record["NOSEQ_VEH"], defaultValue: "\(year)_UNKNOWN")

                    let modelYear: Int32?
                    if let modelYearStr = record["ANNEE_MOD"], let year = Int32(modelYearStr) {
                        sqlite3_bind_int(stmt, 3, year)
                        modelYear = year
                    } else {
                        sqlite3_bind_null(stmt, 3)
                        modelYear = nil
                    }

                    importer.bindDoubleToStatement(stmt, 4, netMass)
                    importer.bindIntToStatement(stmt, 5, cylinderCount)
                    importer.bindDoubleToStatement(stmt, 6, displacement)
                    importer.bindIntToStatement(stmt, 7, maxAxles)

                    // Bind integer ID columns (positions 8-21)
                    // year_id
                    if let yearId = getOrCreateIntEnumId(table: "year_enum", column: "year", value: year, cache: &yearEnumCache) {
                        sqlite3_bind_int(stmt, 8, Int32(yearId))
                    } else { sqlite3_bind_null(stmt, 8) }

                    // vehicle_class_id (lookup human-readable description from VehicleClass enum)
                    let classDescription = VehicleClass(rawValue: vehicle_class)?.description ?? vehicle_class
                    if let classId = getOrCreateClassEnumId(code: vehicle_class, description: classDescription, cache: &classEnumCache) {
                        sqlite3_bind_int(stmt, 9, Int32(classId))
                    } else { sqlite3_bind_null(stmt, 9) }

                    // vehicle_type_id (TYP_VEH_CATEG_USA field)
                    if let vehicleTypeStr = vehicle_type, !vehicleTypeStr.isEmpty {
                        // Look up description from hardcoded list or use code as description
                        let typeDescription: String
                        switch vehicleTypeStr {
                        case "AB": typeDescription = "Bus"
                        case "AT": typeDescription = "Dealer Plates"
                        case "AU": typeDescription = "Automobile or Light Truck"
                        case "CA": typeDescription = "Truck or Road Tractor"
                        case "CY": typeDescription = "Moped"
                        case "HM": typeDescription = "Motorhome"
                        case "MC": typeDescription = "Motorcycle"
                        case "MN": typeDescription = "Snowmobile"
                        case "NV": typeDescription = "Other Off-Road Vehicle"
                        case "SN": typeDescription = "Snow Blower"
                        case "VO": typeDescription = "Tool Vehicle"
                        case "VT": typeDescription = "All-Terrain Vehicle"
                        default: typeDescription = vehicleTypeStr
                        }

                        if let typeId = getOrCreateVehicleTypeEnumId(code: vehicleTypeStr, description: typeDescription, cache: &vehicleTypeEnumCache) {
                            sqlite3_bind_int(stmt, 10, Int32(typeId))
                        } else { sqlite3_bind_null(stmt, 10) }
                    } else {
                        sqlite3_bind_null(stmt, 10)
                    }

                    // make_id
                    if let makeStr = make, !makeStr.isEmpty, let makeId = getOrCreateEnumId(table: "make_enum", column: "name", value: makeStr, cache: &makeEnumCache) {
                        sqlite3_bind_int(stmt, 11, Int32(makeId))
                    } else { sqlite3_bind_null(stmt, 11) }

                    // model_id (requires make_id)
                    if let makeStr = make, !makeStr.isEmpty, let modelStr = model, !modelStr.isEmpty,
                       let makeId = makeEnumCache[makeStr] {
                        let modelKey = "\(makeStr)|\(modelStr)"
                        if let modelId = modelEnumCache[modelKey] {
                            sqlite3_bind_int(stmt, 12, Int32(modelId))
                        } else {
                            // Create model enum entry
                            let insertModelSql = "INSERT OR IGNORE INTO model_enum (name, make_id) VALUES (?, ?);"
                            var modelInsertStmt: OpaquePointer?
                            defer { sqlite3_finalize(modelInsertStmt) }
                            if sqlite3_prepare_v2(db, insertModelSql, -1, &modelInsertStmt, nil) == SQLITE_OK {
                                sqlite3_bind_text(modelInsertStmt, 1, modelStr, -1, SQLITE_TRANSIENT)
                                sqlite3_bind_int(modelInsertStmt, 2, Int32(makeId))
                                sqlite3_step(modelInsertStmt)
                            }
                            let selectModelSql = "SELECT id FROM model_enum WHERE name = ? AND make_id = ?;"
                            var modelSelectStmt: OpaquePointer?
                            defer { sqlite3_finalize(modelSelectStmt) }
                            if sqlite3_prepare_v2(db, selectModelSql, -1, &modelSelectStmt, nil) == SQLITE_OK {
                                sqlite3_bind_text(modelSelectStmt, 1, modelStr, -1, SQLITE_TRANSIENT)
                                sqlite3_bind_int(modelSelectStmt, 2, Int32(makeId))
                                if sqlite3_step(modelSelectStmt) == SQLITE_ROW {
                                    let modelId = Int(sqlite3_column_int(modelSelectStmt, 0))
                                    modelEnumCache[modelKey] = modelId
                                    sqlite3_bind_int(stmt, 12, Int32(modelId))
                                } else {
                                    sqlite3_bind_null(stmt, 12)
                                }
                            } else {
                                sqlite3_bind_null(stmt, 12)
                            }
                        }
                    } else { sqlite3_bind_null(stmt, 12) }

                    // model_year_id
                    if let myear = modelYear, let modelYearId = getOrCreateIntEnumId(table: "model_year_enum", column: "year", value: Int(myear), cache: &modelYearEnumCache) {
                        sqlite3_bind_int(stmt, 13, Int32(modelYearId))
                    } else { sqlite3_bind_null(stmt, 13) }

                    // cylinder_count_id
                    if let cylStr = cylinderCount, let cylInt = Int(cylStr), let cylId = getOrCreateIntEnumId(table: "cylinder_count_enum", column: "count", value: cylInt, cache: &cylinderCountEnumCache) {
                        sqlite3_bind_int(stmt, 14, Int32(cylId))
                    } else { sqlite3_bind_null(stmt, 14) }

                    // axle_count_id
                    if let axleStr = maxAxles, let axleInt = Int(axleStr), let axleId = getOrCreateIntEnumId(table: "axle_count_enum", column: "count", value: axleInt, cache: &axleCountEnumCache) {
                        sqlite3_bind_int(stmt, 15, Int32(axleId))
                    } else { sqlite3_bind_null(stmt, 15) }

                    // original_color_id
                    if let colorStr = color, !colorStr.isEmpty, let colorId = getOrCreateEnumId(table: "color_enum", column: "name", value: colorStr, cache: &colorEnumCache) {
                        sqlite3_bind_int(stmt, 16, Int32(colorId))
                    } else { sqlite3_bind_null(stmt, 16) }

                    // fuel_type_id (lookup human-readable description from FuelType enum)
                    if let fuelStr = fuelType, !fuelStr.isEmpty {
                        let fuelDescription = FuelType(rawValue: fuelStr)?.description ?? fuelStr
                        if let fuelId = getOrCreateFuelTypeEnumId(code: fuelStr, description: fuelDescription, cache: &fuelTypeEnumCache) {
                            sqlite3_bind_int(stmt, 17, Int32(fuelId))
                        } else {
                            sqlite3_bind_null(stmt, 17)
                        }
                    } else { sqlite3_bind_null(stmt, 17) }

                    // admin_region_id - extract name and code from "Region Name (08)" → ("Region Name", "08")
                    if let (regionName, regionCode) = extractNameAndCode(from: adminRegion),
                       let regionId = getOrCreateGeoEnumId(table: "admin_region_enum", name: regionName, code: regionCode, cache: &adminRegionEnumCache) {
                        sqlite3_bind_int(stmt, 18, Int32(regionId))
                    } else { sqlite3_bind_null(stmt, 18) }

                    // mrc_id - extract name and code from "MRC Name (66 )" → ("MRC Name", "66")
                    if let (mrcName, mrcCode) = extractNameAndCode(from: mrc),
                       let mrcId = getOrCreateGeoEnumId(table: "mrc_enum", name: mrcName, code: mrcCode, cache: &mrcEnumCache) {
                        sqlite3_bind_int(stmt, 19, Int32(mrcId))
                    } else { sqlite3_bind_null(stmt, 19) }

                    // municipality_id - lookup name from geographic_entities, fallback to code
                    let muniName = municipalityNameCache[geoCode] ?? geoCode
                    if let muniId = getOrCreateGeoEnumId(table: "municipality_enum", name: muniName, code: geoCode, cache: &municipalityEnumCache) {
                        sqlite3_bind_int(stmt, 20, Int32(muniId))
                    } else { sqlite3_bind_null(stmt, 20) }

                    // net_mass_int (convert REAL to INTEGER)
                    if let massStr = netMass, let massDouble = Double(massStr) {
                        sqlite3_bind_int(stmt, 21, Int32(round(massDouble)))
                    } else { sqlite3_bind_null(stmt, 21) }

                    // displacement_int (convert REAL to INTEGER)
                    if let dispStr = displacement, let dispDouble = Double(dispStr) {
                        sqlite3_bind_int(stmt, 22, Int32(round(dispDouble)))
                    } else { sqlite3_bind_null(stmt, 22) }

                    if sqlite3_step(stmt) == SQLITE_DONE {
                        successCount += 1
                    } else {
                        errorCount += 1
                        if let errorMessage = sqlite3_errmsg(db) {
                            if errorCount <= 5 {
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

    // MARK: - Canonical Hierarchy Cache

    /// Checks if canonical hierarchy cache needs to be populated
    func isCanonicalHierarchyCacheEmpty() async -> Bool {
        guard let db = db else { return true }

        return await withCheckedContinuation { continuation in
            dbQueue.async { [db] in
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }

                let sql = "SELECT COUNT(*) FROM canonical_hierarchy_cache;"

                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        let count = sqlite3_column_int(stmt, 0)
                        continuation.resume(returning: count == 0)
                    } else {
                        continuation.resume(returning: true)
                    }
                } else {
                    continuation.resume(returning: true)
                }
            }
        }
    }

    /// Populates the canonical hierarchy cache from curated years
    func populateCanonicalHierarchyCache(curatedYears: [Int]) async throws {
        guard let db = db else { throw DatabaseError.notConnected }

        let startTime = CFAbsoluteTimeGetCurrent()
        AppLogger.database.info("Populating canonical hierarchy cache from curated years: \(curatedYears)")

        let yearPlaceholders = curatedYears.map { _ in "?" }.joined(separator: ",")

        // First, clear existing cache
        let clearSQL = "DELETE FROM canonical_hierarchy_cache;"
        var errorMsg: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorMsg) }

        if sqlite3_exec(db, clearSQL, nil, nil, &errorMsg) != SQLITE_OK {
            let error = errorMsg != nil ? String(cString: errorMsg!) : "Unknown error"
            throw DatabaseError.queryFailed("Failed to clear cache: \(error)")
        }

        // Insert aggregated data into cache
        let insertSQL = """
        INSERT INTO canonical_hierarchy_cache (
            make_id, make_name, model_id, model_name,
            model_year_id, model_year,
            fuel_type_id, fuel_type_code, fuel_type_description,
            vehicle_type_id, vehicle_type_code, vehicle_type_description,
            record_count
        )
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
        GROUP BY mk.id, md.id, my.id, ft.id, vt.id;
        """

        return try await withCheckedThrowingContinuation { continuation in
            dbQueue.async { [db] in
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }

                if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
                    // Bind curated years
                    for (index, year) in curatedYears.enumerated() {
                        sqlite3_bind_int(stmt, Int32(index + 1), Int32(year))
                    }

                    if sqlite3_step(stmt) == SQLITE_DONE {
                        let duration = CFAbsoluteTimeGetCurrent() - startTime
                        let rowCount = sqlite3_changes(db)
                        AppLogger.database.notice("Canonical hierarchy cache populated: \(rowCount) entries in \(String(format: "%.3f", duration))s")
                        continuation.resume()
                    } else {
                        let error = String(cString: sqlite3_errmsg(db))
                        continuation.resume(throwing: DatabaseError.queryFailed("Failed to populate cache: \(error)"))
                    }
                } else {
                    let error = String(cString: sqlite3_errmsg(db))
                    continuation.resume(throwing: DatabaseError.queryFailed("Failed to prepare cache population: \(error)"))
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
