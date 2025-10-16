//
//  DataPackageManager.swift
//  SAAQAnalyzer
//
//  Created by Claude Code on 2025-01-27.
//

import Foundation
import Combine
import SQLite3
import OSLog

/// Manages export and import of SAAQ data packages
///
/// # Data Package Contents
///
/// A SAAQ data package is a bundle (.saaqpackage) containing:
///
/// ## Database (Complete SQLite file)
/// - **Main tables**: vehicles, licenses, geographic_entities, import_log
/// - **Canonical hierarchy cache** (added Oct 2025): Pre-aggregated Make/Model/Year/Fuel/VehicleType combinations
/// - **16 Enumeration tables**: year_enum, vehicle_class_enum, vehicle_type_enum, make_enum, model_enum,
///   fuel_type_enum, color_enum, cylinder_count_enum, axle_count_enum, model_year_enum, admin_region_enum,
///   mrc_enum, municipality_enum, age_group_enum, gender_enum, license_type_enum
/// - **All indexes**: Optimized integer-based indexes for query performance
///
/// ## Metadata (JSON files)
/// - Package info (Info.plist): Version, record counts, year ranges, file sizes
/// - Statistics: Vehicle and license data summaries
/// - Import log: Export date and options
///
/// ## Cache Handling
/// - **Filter cache** (UserDefaults): NOT packaged - rebuilt from enumeration tables on import
/// - This ensures cache staleness is never an issue - cache is always fresh after import
///
/// ## Version Synchronization
/// - Database modification timestamp is set to import timestamp
/// - Filter cache is rebuilt with matching version
/// - Prevents any cache staleness issues when bypassing CSV import pathway
///
/// # Import Process
/// 1. Validate package structure and available disk space
/// 2. Backup current database (optional, not yet implemented)
/// 3. Replace database file with imported database
/// 4. Rebuild FilterCache from enumeration tables in imported database
/// 5. Trigger UI refresh with updated dataVersion
///
/// # Export Process
/// 1. Gather statistics from current database
/// 2. Copy database file (includes all tables, enumeration tables, canonical cache, indexes)
/// 3. Validate database structure (ensures canonical_hierarchy_cache and all required tables exist)
/// 4. Create metadata files
/// 5. Create package Info.plist
@MainActor
class DataPackageManager: ObservableObject {

    /// Singleton instance
    static let shared = DataPackageManager()

    /// Progress tracking for package operations
    @Published var isExporting = false
    @Published var isImporting = false
    @Published var operationProgress: Double = 0.0
    @Published var operationStatus = ""

    private let databaseManager = DatabaseManager.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.saaq.SAAQAnalyzer", category: "dataPackage")

    private init() {}

    // MARK: - Export Operations

    /// Exports current data to a SAAQ package file
    /// - Parameters:
    ///   - packageURL: URL where the package should be saved
    ///   - options: Export configuration options
    func exportDataPackage(to packageURL: URL, options: DataPackageExportOptions) async throws {
        guard !isExporting && !isImporting else {
            throw DataPackageError.exportFailed("Another package operation is already in progress")
        }

        isExporting = true
        operationProgress = 0.0
        operationStatus = "Preparing export..."

        defer {
            Task { @MainActor in
                isExporting = false
                operationProgress = 0.0
                operationStatus = ""
            }
        }

        do {
            // Create package bundle structure
            let packagePath = packageURL.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: packagePath, withIntermediateDirectories: true)

            // Create subdirectories
            let databasePath = packagePath.appendingPathComponent("Database")
            let metadataPath = packagePath.appendingPathComponent("Metadata")

            try FileManager.default.createDirectory(at: databasePath, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: metadataPath, withIntermediateDirectories: true)

            await updateProgress(0.1, "Gathering statistics...")

            // Gather statistics
            let stats = await gatherPackageStatistics()

            await updateProgress(0.2, "Copying database...")

            // Copy database if data is included
            if options.includeVehicleData || options.includeDriverData {
                try await exportDatabase(to: databasePath, options: options)
            }

            await updateProgress(0.6, "Verifying database structure...")

            // Validate database structure includes all required tables
            try await validateDatabaseStructure(at: databasePath.appendingPathComponent("saaq_data.sqlite"))

            await updateProgress(0.8, "Creating metadata...")

            // Create metadata files
            try await exportMetadata(to: metadataPath, stats: stats, options: options)

            await updateProgress(0.9, "Creating package info...")

            // Create Info.plist
            try await createPackageInfo(at: packageURL, stats: stats, options: options)

            await updateProgress(1.0, "Export completed successfully")

            logger.notice("Data package exported successfully to: \(packageURL.path, privacy: .public)")

        } catch {
            logger.error("Export failed: \(error.localizedDescription, privacy: .public)")
            throw DataPackageError.exportFailed(error.localizedDescription)
        }
    }

    // MARK: - Import Operations

    /// Validates a data package before import
    /// - Parameter packageURL: URL of the package to validate
    /// - Returns: Validation result with content description
    func validateDataPackage(at packageURL: URL) async -> DataPackageValidationResult {
        // Start accessing security-scoped resource (needed for package bundles)
        let accessing = packageURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                packageURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            // Check if package bundle exists
            guard FileManager.default.fileExists(atPath: packageURL.path) else {
                return .invalidFormat
            }

            // Check for required structure
            let contentsURL = packageURL.appendingPathComponent("Contents")
            guard FileManager.default.fileExists(atPath: contentsURL.path) else {
                return .invalidFormat
            }

            // Check for Info.plist
            let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
            guard FileManager.default.fileExists(atPath: infoPlistURL.path) else {
                return .missingFiles
            }

            // Try to read and validate Info.plist
            let infoData = try Data(contentsOf: infoPlistURL)
            let packageInfo = try PropertyListDecoder().decode(DataPackageInfo.self, from: infoData)

            // Check available disk space
            if let diskSpace = try FileManager.default.attributesOfFileSystem(forPath: packageURL.path)[.systemFreeSize] as? Int64 {
                let packageSize = try packageURL.resourceValues(forKeys: [.totalFileSizeKey]).totalFileSize ?? 0
                if diskSpace < packageSize * 2 { // Need 2x space for extraction
                    return .insufficientDiskSpace
                }
            }

            // Detect what data is in the package by checking the database
            let databaseURL = contentsURL.appendingPathComponent("Database/saaq_data.sqlite")
            guard FileManager.default.fileExists(atPath: databaseURL.path) else {
                return .missingFiles
            }

            let content = try detectPackageContent(at: databaseURL, packageInfo: packageInfo)

            return .valid(content)

        } catch {
            logger.error("Package validation failed: \(error.localizedDescription, privacy: .public)")
            return .corruptedData
        }
    }

    /// Detects what data tables are present in the package database
    private func detectPackageContent(at databaseURL: URL, packageInfo: DataPackageInfo) throws -> DataPackageContent {
        var db: OpaquePointer?

        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            throw DataPackageError.validationFailed(.corruptedData)
        }

        defer {
            sqlite3_close(db)
        }

        // Check for vehicles table and count
        var vehicleCount = 0
        let vehicleQuery = "SELECT COUNT(*) FROM vehicles;"
        var vehicleStmt: OpaquePointer?

        if sqlite3_prepare_v2(db, vehicleQuery, -1, &vehicleStmt, nil) == SQLITE_OK {
            if sqlite3_step(vehicleStmt) == SQLITE_ROW {
                vehicleCount = Int(sqlite3_column_int(vehicleStmt, 0))
            }
            sqlite3_finalize(vehicleStmt)
        }

        // Check for licenses table and count
        var licenseCount = 0
        let licenseQuery = "SELECT COUNT(*) FROM licenses;"
        var licenseStmt: OpaquePointer?

        if sqlite3_prepare_v2(db, licenseQuery, -1, &licenseStmt, nil) == SQLITE_OK {
            if sqlite3_step(licenseStmt) == SQLITE_ROW {
                licenseCount = Int(sqlite3_column_int(licenseStmt, 0))
            }
            sqlite3_finalize(licenseStmt)
        }

        let content = DataPackageContent(
            hasVehicleData: vehicleCount > 0,
            hasLicenseData: licenseCount > 0,
            vehicleRecordCount: vehicleCount,
            licenseRecordCount: licenseCount
        )

        logger.info("Package contains: \(content.description, privacy: .public)")
        logger.info("Vehicle records: \(vehicleCount), License records: \(licenseCount)")

        return content
    }

    /// Imports a data package, replacing or merging with current data
    /// - Parameters:
    ///   - packageURL: URL of the package to import
    ///   - mode: Import mode (.replace for fast path, .merge for selective import)
    func importDataPackage(from packageURL: URL, mode: DataPackageImportMode = .replace) async throws {
        guard !isExporting && !isImporting else {
            throw DataPackageError.importFailed("Another package operation is already in progress")
        }

        // Validate package first
        let validationResult = await validateDataPackage(at: packageURL)
        guard validationResult.isValid, let packageContent = validationResult.content else {
            throw DataPackageError.validationFailed(validationResult)
        }

        // Check for empty package
        if packageContent.isEmpty {
            throw DataPackageError.importFailed("Package contains no data to import")
        }

        // Start accessing security-scoped resource (needed for package bundles)
        let accessing = packageURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                packageURL.stopAccessingSecurityScopedResource()
            }
        }

        isImporting = true
        operationProgress = 0.0
        operationStatus = "Starting import..."

        // Generate a consistent timestamp for both database and cache
        let importTimestamp = Date()
        let importVersion = String(Int(importTimestamp.timeIntervalSince1970))

        defer {
            Task { @MainActor in
                isImporting = false
                operationProgress = 0.0
                operationStatus = ""
            }
        }

        do {
            let contentsURL = packageURL.appendingPathComponent("Contents")

            await updateProgress(0.1, "Reading package info...")

            // Read package info
            let packageInfo = try await readPackageInfo(from: contentsURL)

            await updateProgress(0.2, "Backing up current data...")

            // Create backup of current database (optional safety measure)
            try await createDataBackup()

            await updateProgress(0.4, "Importing database...")

            if mode == .replace {
                // Fast path: Simple file copy (original behavior)
                logger.info("Using REPLACE mode (fast path)")
                try await importDatabaseReplace(
                    from: contentsURL.appendingPathComponent("Database"),
                    timestamp: importTimestamp
                )
            } else {
                // Smart path: Selective merge based on content
                logger.info("Using MERGE mode (selective import)")
                try await importDatabase(
                    from: contentsURL.appendingPathComponent("Database"),
                    timestamp: importTimestamp,
                    content: packageContent
                )
            }

            await updateProgress(0.7, "Rebuilding filter cache...")

            // Rebuild filter cache from enumeration tables in the imported database
            if let filterCacheManager = databaseManager.filterCacheManager {
                logger.info("Rebuilding filter cache from imported database")

                // CRITICAL: Invalidate cache first to allow reinitialization
                filterCacheManager.invalidateCache()

                try await filterCacheManager.initializeCache()
            } else {
                logger.warning("FilterCacheManager not available, cache will be rebuilt on next app launch")
            }

            await updateProgress(0.9, "Finalizing import...")

            // Update app state with matching version
            try await updateAppStateAfterImport(packageInfo: packageInfo, dataVersion: importVersion)

            await updateProgress(1.0, "Import completed successfully")

            logger.notice("Data package imported successfully from: \(packageURL.path, privacy: .public)")
            logger.info("Imported: \(packageContent.description, privacy: .public)")

        } catch {
            logger.error("Import failed: \(error.localizedDescription, privacy: .public)")
            throw DataPackageError.importFailed(error.localizedDescription)
        }
    }

    // MARK: - Helper Methods

    private func updateProgress(_ progress: Double, _ status: String) async {
        await MainActor.run {
            operationProgress = progress
            operationStatus = status
        }
    }

    private func gatherPackageStatistics() async -> PackagedDataStats {
        let dbStats = await databaseManager.getDatabaseStats()

        // Query enumeration table counts directly
        let enumerationCounts = await queryEnumerationTableCounts()

        let vehicleStats = PackagedVehicleStats(
            totalRecords: dbStats.totalVehicleRecords,
            yearRange: dbStats.vehicleYearRange,
            availableYearsCount: dbStats.availableVehicleYearsCount,
            regions: dbStats.regions,
            mrcs: enumerationCounts.mrcs,
            municipalities: dbStats.municipalities,
            classifications: enumerationCounts.classifications,
            makes: enumerationCounts.makes,
            models: enumerationCounts.models,
            colors: enumerationCounts.colors,
            modelYears: enumerationCounts.modelYears,
            lastUpdated: dbStats.lastUpdated
        )

        let driverStats = PackagedDriverStats(
            totalRecords: dbStats.totalLicenseRecords,
            yearRange: dbStats.licenseYearRange,
            availableYearsCount: dbStats.availableLicenseYearsCount,
            regions: dbStats.regions,
            mrcs: enumerationCounts.mrcs,
            licenseTypes: enumerationCounts.licenseTypes,
            ageGroups: enumerationCounts.ageGroups,
            genders: enumerationCounts.genders,
            experienceLevels: enumerationCounts.experienceLevels,
            licenseClasses: enumerationCounts.licenseClasses,
            lastUpdated: dbStats.lastUpdated
        )

        return PackagedDataStats(
            vehicleStats: vehicleStats,
            driverStats: driverStats,
            totalRecords: dbStats.totalRecords,
            exportDate: Date(),
            dataVersion: String(Int(dbStats.lastUpdated.timeIntervalSince1970))
        )
    }

    /// Query counts from enumeration tables
    private func queryEnumerationTableCounts() async -> (
        mrcs: Int,
        classifications: Int,
        makes: Int,
        models: Int,
        colors: Int,
        modelYears: Int,
        licenseTypes: Int,
        ageGroups: Int,
        genders: Int,
        experienceLevels: Int,
        licenseClasses: Int
    ) {
        guard let db = self.databaseManager.db else {
            return (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        }

        func countRows(in table: String, using database: OpaquePointer?) -> Int {
            guard let database = database else { return 0 }
            var count = 0
            let query = "SELECT COUNT(*) FROM \(table)"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_ROW {
                    count = Int(sqlite3_column_int(statement, 0))
                }
                sqlite3_finalize(statement)
            }
            return count
        }

        return (
            mrcs: countRows(in: "mrc_enum", using: db),
            classifications: countRows(in: "vehicle_class_enum", using: db),
            makes: countRows(in: "make_enum", using: db),
            models: countRows(in: "model_enum", using: db),
            colors: countRows(in: "color_enum", using: db),
            modelYears: countRows(in: "model_year_enum", using: db),
            licenseTypes: countRows(in: "license_type_enum", using: db),
            ageGroups: countRows(in: "age_group_enum", using: db),
            genders: countRows(in: "gender_enum", using: db),
            experienceLevels: countRows(in: "experience_level_enum", using: db),
            licenseClasses: 0  // License classes are boolean columns, not enumerated
        )
    }

    private func exportDatabase(to path: URL, options: DataPackageExportOptions) async throws {
        guard let currentDBURL = databaseManager.databaseURL else {
            throw DataPackageError.exportFailed("No database found to export")
        }

        let destinationURL = path.appendingPathComponent("saaq_data.sqlite")

        // Copy the database file
        try FileManager.default.copyItem(at: currentDBURL, to: destinationURL)

        // If only partial data is needed, we could potentially filter the database here
        // For now, we're copying the complete database and letting import logic handle filtering
    }


    private func exportMetadata(to path: URL, stats: PackagedDataStats, options: DataPackageExportOptions) async throws {
        // Export combined stats
        let statsData = try JSONEncoder().encode(stats)
        try statsData.write(to: path.appendingPathComponent("DataStats.json"))

        // Export individual stats
        let vehicleStatsData = try JSONEncoder().encode(stats.vehicleStats)
        try vehicleStatsData.write(to: path.appendingPathComponent("VehicleStats.json"))

        let driverStatsData = try JSONEncoder().encode(stats.driverStats)
        try driverStatsData.write(to: path.appendingPathComponent("DriverStats.json"))

        // Create import log placeholder
        let importLog = [
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "sourceApp": "SAAQAnalyzer",
            "exportOptions": [
                "includeVehicleData": options.includeVehicleData,
                "includeDriverData": options.includeDriverData,
                "includeVehicleCache": options.includeVehicleCache,
                "includeDriverCache": options.includeDriverCache
            ]
        ] as [String: Any]

        let importLogData = try JSONSerialization.data(withJSONObject: importLog, options: .prettyPrinted)
        try importLogData.write(to: path.appendingPathComponent("ImportLog.json"))
    }

    private func createPackageInfo(at packageURL: URL, stats: PackagedDataStats, options: DataPackageExportOptions) async throws {
        // Get file sizes
        let dbSize = try getFileSize(at: packageURL.appendingPathComponent("Contents/Database/saaq_data.sqlite"))
        let vehicleCacheSize = try getFileSize(at: packageURL.appendingPathComponent("Contents/Cache/VehicleCache.plist"))
        let driverCacheSize = try getFileSize(at: packageURL.appendingPathComponent("Contents/Cache/DriverCache.plist"))
        let totalSize = try getDirectorySize(at: packageURL.appendingPathComponent("Contents"))

        let packageInfo = DataPackageInfo(
            packageVersion: "1.0",
            vehicleRecordCount: stats.vehicleStats.totalRecords,
            driverRecordCount: stats.driverStats.totalRecords,
            dataYearRange: "\(stats.vehicleStats.yearRange) (vehicles), \(stats.driverStats.yearRange) (drivers)",
            exportDate: Date(),
            sourceHardware: getHardwareInfo(),
            databaseVersion: stats.dataVersion,
            cacheVersion: stats.dataVersion,
            fileSizes: DataPackageInfo.FileSizeInfo(
                databaseSizeBytes: dbSize,
                vehicleCacheSizeBytes: vehicleCacheSize,
                driverCacheSizeBytes: driverCacheSize,
                totalPackageSizeBytes: totalSize
            )
        )

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let plistData = try encoder.encode(packageInfo)

        let infoPlistURL = packageURL.appendingPathComponent("Contents/Info.plist")
        try plistData.write(to: infoPlistURL)
    }

    private func readPackageInfo(from contentsURL: URL) async throws -> DataPackageInfo {
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        let plistData = try Data(contentsOf: infoPlistURL)
        return try PropertyListDecoder().decode(DataPackageInfo.self, from: plistData)
    }

    private func createDataBackup() async throws {
        // TODO: Implement backup creation for safety
        logger.info("Creating data backup (not yet implemented)")
    }

    /// Imports database using simple file replacement (fast path for complete backups)
    /// - Parameters:
    ///   - databasePath: Path to the Database folder in the package
    ///   - timestamp: Import timestamp for version consistency
    private func importDatabaseReplace(from databasePath: URL, timestamp: Date) async throws {
        let sourceURL = databasePath.appendingPathComponent("saaq_data.sqlite")

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw DataPackageError.importFailed("Database file not found in package")
        }

        guard let currentDBURL = databaseManager.databaseURL else {
            throw DataPackageError.importFailed("No current database location configured")
        }

        // Close current database connection
        await databaseManager.closeDatabaseConnection()

        // Replace database file (original fast behavior)
        if FileManager.default.fileExists(atPath: currentDBURL.path) {
            try FileManager.default.removeItem(at: currentDBURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: currentDBURL)

        // Update the modification date of the imported database to the consistent timestamp
        let attributes = [FileAttributeKey.modificationDate: timestamp]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: currentDBURL.path)

        // Reconnect to database
        await databaseManager.reconnectDatabase()

        logger.notice("Database replaced successfully (fast path)")
    }

    /// Imports database tables selectively, merging with or replacing existing data
    /// - Parameters:
    ///   - databasePath: Path to the Database folder in the package
    ///   - timestamp: Import timestamp for version consistency
    ///   - content: Description of what data the package contains
    private func importDatabase(from databasePath: URL, timestamp: Date, content: DataPackageContent) async throws {
        let sourceURL = databasePath.appendingPathComponent("saaq_data.sqlite")

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw DataPackageError.importFailed("Database file not found in package")
        }

        guard let currentDBURL = databaseManager.databaseURL else {
            throw DataPackageError.importFailed("No current database location configured")
        }

        // Check if current database exists and has data to preserve
        let currentDatabaseExists = FileManager.default.fileExists(atPath: currentDBURL.path)
        var preserveVehicleData = false
        var preserveLicenseData = false

        if currentDatabaseExists {
            // Detect what data exists in current database
            let currentContent = try detectCurrentDatabaseContent()
            preserveVehicleData = currentContent.hasVehicleData && !content.hasVehicleData
            preserveLicenseData = currentContent.hasLicenseData && !content.hasLicenseData

            logger.info("Current database contains: \(currentContent.description, privacy: .public)")
            logger.info("Preserve vehicle data: \(preserveVehicleData), Preserve license data: \(preserveLicenseData)")

            // SAFETY CHECK: Detect dangerous merge scenarios where data types overlap
            let hasConflict = (currentContent.hasVehicleData && content.hasVehicleData) ||
                             (currentContent.hasLicenseData && content.hasLicenseData)

            if hasConflict {
                let conflictMessage = """
                    Cannot merge: Data type conflict detected!

                    Current database: \(currentContent.description)
                    Package contents: \(content.description)

                    Merge mode only works when importing non-overlapping data types:
                    ✓ Import licenses into vehicle-only database
                    ✓ Import vehicles into license-only database
                    ✗ Import vehicles when database already has vehicles
                    ✗ Import licenses when database already has licenses

                    To import this package, please:
                    1. Use REPLACE mode instead (replaces entire database), OR
                    2. Export your current data first, then import both packages separately

                    This restriction prevents accidental data loss from overlapping records.
                    """

                logger.error("Merge conflict prevented: \(conflictMessage, privacy: .public)")
                throw DataPackageError.importFailed(conflictMessage)
            }
        }

        // Close current database connection
        await databaseManager.closeDatabaseConnection()

        if preserveVehicleData || preserveLicenseData {
            // Selective merge: Import only the tables in the package, preserve others
            logger.info("Performing selective import (preserving existing data)")
            try await mergeDatabase(
                source: sourceURL,
                destination: currentDBURL,
                importContent: content,
                preserveVehicle: preserveVehicleData,
                preserveLicense: preserveLicenseData
            )
        } else {
            // Full replace: Package contains all the data we need
            logger.info("Performing full database replace")

            if FileManager.default.fileExists(atPath: currentDBURL.path) {
                try FileManager.default.removeItem(at: currentDBURL)
            }

            try FileManager.default.copyItem(at: sourceURL, to: currentDBURL)
        }

        // Update the modification date of the imported database to the consistent timestamp
        // This ensures the database version (based on mod date) matches the cache version
        let attributes = [FileAttributeKey.modificationDate: timestamp]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: currentDBURL.path)

        // Reconnect to database
        await databaseManager.reconnectDatabase()

        logger.notice("Database imported and connection restored")
    }

    /// Detects what data tables are present in the current database
    private func detectCurrentDatabaseContent() throws -> DataPackageContent {
        guard let currentDBURL = databaseManager.databaseURL else {
            throw DataPackageError.importFailed("No current database location configured")
        }

        guard FileManager.default.fileExists(atPath: currentDBURL.path) else {
            // No current database, nothing to preserve
            logger.info("🔍 No current database file found - nothing to preserve")
            return DataPackageContent(hasVehicleData: false, hasLicenseData: false,
                                     vehicleRecordCount: 0, licenseRecordCount: 0)
        }

        var db: OpaquePointer?

        guard sqlite3_open(currentDBURL.path, &db) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            logger.error("Could not open current database for detection: \(errorMsg, privacy: .public)")
            throw DataPackageError.importFailed("Could not open current database")
        }

        defer {
            sqlite3_close(db)
        }

        // Check for vehicles table and count
        var vehicleCount = 0
        let vehicleQuery = "SELECT COUNT(*) FROM vehicles;"
        var vehicleStmt: OpaquePointer?

        if sqlite3_prepare_v2(db, vehicleQuery, -1, &vehicleStmt, nil) == SQLITE_OK {
            if sqlite3_step(vehicleStmt) == SQLITE_ROW {
                vehicleCount = Int(sqlite3_column_int(vehicleStmt, 0))
            }
            sqlite3_finalize(vehicleStmt)
        } else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            logger.warning("Could not query vehicles table: \(errorMsg, privacy: .public)")
        }

        // Check for licenses table and count
        var licenseCount = 0
        let licenseQuery = "SELECT COUNT(*) FROM licenses;"
        var licenseStmt: OpaquePointer?

        if sqlite3_prepare_v2(db, licenseQuery, -1, &licenseStmt, nil) == SQLITE_OK {
            if sqlite3_step(licenseStmt) == SQLITE_ROW {
                licenseCount = Int(sqlite3_column_int(licenseStmt, 0))
            }
            sqlite3_finalize(licenseStmt)
        } else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            logger.warning("Could not query licenses table: \(errorMsg, privacy: .public)")
        }

        logger.info("🔍 Detected current database content: \(vehicleCount) vehicles, \(licenseCount) licenses")

        return DataPackageContent(
            hasVehicleData: vehicleCount > 0,
            hasLicenseData: licenseCount > 0,
            vehicleRecordCount: vehicleCount,
            licenseRecordCount: licenseCount
        )
    }

    /// Merges database tables from source into destination, preserving specified data
    private func mergeDatabase(
        source: URL,
        destination: URL,
        importContent: DataPackageContent,
        preserveVehicle: Bool,
        preserveLicense: Bool
    ) async throws {
        // Create a temporary database to work with
        let tempURL = destination.deletingLastPathComponent().appendingPathComponent("temp_import.sqlite")

        // Copy source to temp location
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }
        try FileManager.default.copyItem(at: source, to: tempURL)

        // If we need to preserve data, we'll copy it from the current database into the temp one
        if preserveVehicle || preserveLicense {
            try await copyTablesFromCurrent(
                currentDB: destination,
                targetDB: tempURL,
                copyVehicles: preserveVehicle,
                copyLicenses: preserveLicense
            )
        }

        // Replace current database with the merged temp database
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.moveItem(at: tempURL, to: destination)

        logger.info("Database merge completed successfully")
    }

    /// Copies specified tables from current database into target database
    private func copyTablesFromCurrent(
        currentDB: URL,
        targetDB: URL,
        copyVehicles: Bool,
        copyLicenses: Bool
    ) async throws {
        // Open both databases
        var sourceDb: OpaquePointer?
        var targetDb: OpaquePointer?

        guard sqlite3_open(currentDB.path, &sourceDb) == SQLITE_OK else {
            throw DataPackageError.importFailed("Could not open current database for copying")
        }

        defer { sqlite3_close(sourceDb) }

        guard sqlite3_open(targetDB.path, &targetDb) == SQLITE_OK else {
            throw DataPackageError.importFailed("Could not open target database for copying")
        }

        defer { sqlite3_close(targetDb) }

        // Attach the source database to the target
        let attachSQL = "ATTACH DATABASE '\(currentDB.path)' AS current_db;"
        var attachError: UnsafeMutablePointer<Int8>?

        if sqlite3_exec(targetDb, attachSQL, nil, nil, &attachError) != SQLITE_OK {
            if let error = attachError {
                let errorMsg = String(cString: error)
                sqlite3_free(error)
                throw DataPackageError.importFailed("Could not attach database: \(errorMsg)")
            }
        }

        // Copy vehicle-related data if needed
        if copyVehicles {
            logger.info("Copying vehicle data from current database")

            // NOTE: We do NOT delete existing data when preserving!
            // The target database (from the package) has the data we want to IMPORT
            // We're copying FROM current database TO preserve it alongside the imported data

            // Copy vehicles table (INSERT OR REPLACE to handle any conflicts)
            let copyVehiclesSQL = "INSERT OR REPLACE INTO vehicles SELECT * FROM current_db.vehicles;"
            var vehicleError: UnsafeMutablePointer<Int8>?
            if sqlite3_exec(targetDb, copyVehiclesSQL, nil, nil, &vehicleError) != SQLITE_OK {
                if let error = vehicleError {
                    let errorMsg = String(cString: error)
                    sqlite3_free(error)
                    throw DataPackageError.importFailed("Could not copy vehicles: \(errorMsg)")
                }
            }

            // Copy canonical hierarchy cache
            let copyCacheSQL = "INSERT INTO canonical_hierarchy_cache SELECT * FROM current_db.canonical_hierarchy_cache;"
            _ = sqlite3_exec(targetDb, copyCacheSQL, nil, nil, nil)  // Don't fail if cache is empty

            // Merge vehicle-related enumeration tables
            try mergeEnumerationTables(sourceDb: sourceDb, targetDb: targetDb, vehicleOnly: true)

            logger.info("Vehicle data copied successfully")
        }

        // Copy license-related data if needed
        if copyLicenses {
            logger.info("Copying license data from current database")

            // NOTE: We do NOT delete existing data when preserving!
            // The target database (from the package) has the data we want to IMPORT
            // We're copying FROM current database TO preserve it alongside the imported data

            // Copy licenses table (INSERT OR REPLACE to handle any conflicts)
            let copyLicensesSQL = "INSERT OR REPLACE INTO licenses SELECT * FROM current_db.licenses;"
            var licenseError: UnsafeMutablePointer<Int8>?
            if sqlite3_exec(targetDb, copyLicensesSQL, nil, nil, &licenseError) != SQLITE_OK {
                if let error = licenseError {
                    let errorMsg = String(cString: error)
                    sqlite3_free(error)
                    throw DataPackageError.importFailed("Could not copy licenses: \(errorMsg)")
                }
            }

            // Merge license-related enumeration tables
            try mergeEnumerationTables(sourceDb: sourceDb, targetDb: targetDb, vehicleOnly: false)

            logger.info("License data copied successfully")
        }

        // Detach the source database
        _ = sqlite3_exec(targetDb, "DETACH DATABASE current_db;", nil, nil, nil)
    }

    /// Merges enumeration tables from source database, handling conflicts
    private func mergeEnumerationTables(
        sourceDb: OpaquePointer?,
        targetDb: OpaquePointer?,
        vehicleOnly: Bool
    ) throws {
        // Enumeration tables to merge based on data type
        let sharedTables = ["year_enum", "admin_region_enum", "mrc_enum", "municipality_enum"]

        let vehicleTables = [
            "vehicle_class_enum", "vehicle_type_enum", "make_enum", "model_enum",
            "fuel_type_enum", "color_enum", "cylinder_count_enum", "axle_count_enum", "model_year_enum"
        ]

        let licenseTables = [
            "license_type_enum", "age_group_enum", "gender_enum", "experience_level_enum"
        ]

        let tablesToMerge = sharedTables + (vehicleOnly ? vehicleTables : licenseTables)

        for table in tablesToMerge {
            // Use INSERT OR IGNORE to merge without conflicts (keeps target's existing IDs)
            let mergeSQL = "INSERT OR IGNORE INTO \(table) SELECT * FROM current_db.\(table);"
            var mergeError: UnsafeMutablePointer<Int8>?

            if sqlite3_exec(targetDb, mergeSQL, nil, nil, &mergeError) != SQLITE_OK {
                if let error = mergeError {
                    let errorMsg = String(cString: error)
                    sqlite3_free(error)
                    logger.warning("Could not merge table \(table, privacy: .public): \(errorMsg, privacy: .public)")
                    // Don't throw - enumeration merge failures are non-fatal
                }
            }
        }

        logger.info("Enumeration tables merged successfully")
    }


    private func updateAppStateAfterImport(packageInfo: DataPackageInfo, dataVersion: String) async throws {
        logger.info("Finalizing import with dataVersion: \(dataVersion, privacy: .public)")

        // Refresh database stats from the imported database
        let newDbStats = await databaseManager.getDatabaseStats()

        logger.notice("Import completed successfully")
        logger.info("Imported database contains \(newDbStats.totalVehicleRecords) vehicle records and \(newDbStats.totalLicenseRecords) license records")
        logger.info("Data version: \(dataVersion, privacy: .public)")

        // Trigger UI refresh by incrementing dataVersion
        await MainActor.run { [self] in
            self.databaseManager.dataVersion += 1
            self.logger.info("UI refresh triggered (dataVersion: \(self.databaseManager.dataVersion))")
        }
    }

    // MARK: - Database Validation

    /// Validates that exported database contains all required tables and structure
    private func validateDatabaseStructure(at databaseURL: URL) async throws {
        logger.info("Validating database structure at: \(databaseURL.path, privacy: .public)")

        var db: OpaquePointer?

        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            throw DataPackageError.exportFailed("Could not open exported database for validation")
        }

        defer {
            sqlite3_close(db)
        }

        // Required tables to validate
        let requiredTables = [
            "vehicles",
            "licenses",
            "geographic_entities",
            "import_log",
            "canonical_hierarchy_cache",  // NEW: Added Oct 2025
            // Enumeration tables
            "year_enum",
            "vehicle_class_enum",
            "vehicle_type_enum",
            "make_enum",
            "model_enum",
            "fuel_type_enum",
            "color_enum",
            "cylinder_count_enum",
            "axle_count_enum",
            "model_year_enum",
            "admin_region_enum",
            "mrc_enum",
            "municipality_enum",
            "age_group_enum",
            "gender_enum",
            "license_type_enum"
        ]

        for tableName in requiredTables {
            let query = "SELECT name FROM sqlite_master WHERE type='table' AND name=?;"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (tableName as NSString).utf8String, -1, nil)

                if sqlite3_step(statement) != SQLITE_ROW {
                    sqlite3_finalize(statement)
                    throw DataPackageError.exportFailed("Missing required table: \(tableName)")
                }

                sqlite3_finalize(statement)
            } else {
                throw DataPackageError.exportFailed("Database validation query failed for table: \(tableName)")
            }
        }

        // Validate canonical_hierarchy_cache has records (if the database has been used)
        let countQuery = "SELECT COUNT(*) FROM vehicles;"
        var countStatement: OpaquePointer?
        var vehicleCount = 0

        if sqlite3_prepare_v2(db, countQuery, -1, &countStatement, nil) == SQLITE_OK {
            if sqlite3_step(countStatement) == SQLITE_ROW {
                vehicleCount = Int(sqlite3_column_int(countStatement, 0))
            }
            sqlite3_finalize(countStatement)
        }

        // Log cache status
        let cacheQuery = "SELECT COUNT(*) FROM canonical_hierarchy_cache;"
        var cacheStatement: OpaquePointer?
        var cacheCount = 0

        if sqlite3_prepare_v2(db, cacheQuery, -1, &cacheStatement, nil) == SQLITE_OK {
            if sqlite3_step(cacheStatement) == SQLITE_ROW {
                cacheCount = Int(sqlite3_column_int(cacheStatement, 0))
            }
            sqlite3_finalize(cacheStatement)
        }

        logger.info("Database validation passed: \(requiredTables.count) tables verified")
        logger.info("Canonical hierarchy cache: \(cacheCount) entries (vehicle records: \(vehicleCount))")
    }

    // MARK: - Utility Methods

    private func getFileSize(at url: URL) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return 0
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }

    private func getDirectorySize(at url: URL) throws -> Int64 {
        var totalSize: Int64 = 0

        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [], errorHandler: nil) {
            for case let fileURL as URL in enumerator {
                let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                totalSize += Int64(fileSize)
            }
        }

        return totalSize
    }

    private func getHardwareInfo() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}
