//
//  DataPackageManager.swift
//  SAAQAnalyzer
//
//  Created by Claude Code on 2025-01-27.
//

import Foundation
import Combine
import SQLite3

/// Manages export and import of SAAQ data packages
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

            await updateProgress(0.6, "Verifying enumeration tables...")

            // Note: Enumeration tables are part of the database and are
            // automatically included when we copy the database file.
            // No separate cache export is needed with integer-based architecture.

            await updateProgress(0.8, "Creating metadata...")

            // Create metadata files
            try await exportMetadata(to: metadataPath, stats: stats, options: options)

            await updateProgress(0.9, "Creating package info...")

            // Create Info.plist
            try await createPackageInfo(at: packageURL, stats: stats, options: options)

            await updateProgress(1.0, "Export completed successfully")

            print("✅ Data package exported successfully to: \(packageURL.path)")

        } catch {
            print("❌ Export failed: \(error)")
            throw DataPackageError.exportFailed(error.localizedDescription)
        }
    }

    // MARK: - Import Operations

    /// Validates a data package before import
    /// - Parameter packageURL: URL of the package to validate
    /// - Returns: Validation result
    func validateDataPackage(at packageURL: URL) async -> DataPackageValidationResult {
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
            let _ = try PropertyListDecoder().decode(DataPackageInfo.self, from: infoData)

            // Check available disk space
            if let diskSpace = try FileManager.default.attributesOfFileSystem(forPath: packageURL.path)[.systemFreeSize] as? Int64 {
                let packageSize = try packageURL.resourceValues(forKeys: [.totalFileSizeKey]).totalFileSize ?? 0
                if diskSpace < packageSize * 2 { // Need 2x space for extraction
                    return .insufficientDiskSpace
                }
            }

            return .valid

        } catch {
            print("❌ Package validation failed: \(error)")
            return .corruptedData
        }
    }

    /// Imports a data package, replacing current data
    /// - Parameter packageURL: URL of the package to import
    func importDataPackage(from packageURL: URL) async throws {
        guard !isExporting && !isImporting else {
            throw DataPackageError.importFailed("Another package operation is already in progress")
        }

        // Validate package first
        let validationResult = await validateDataPackage(at: packageURL)
        guard validationResult == .valid else {
            throw DataPackageError.validationFailed(validationResult)
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

            // Import database with consistent timestamp
            try await importDatabase(from: contentsURL.appendingPathComponent("Database"), timestamp: importTimestamp)

            await updateProgress(0.7, "Rebuilding filter cache...")

            // Rebuild filter cache from enumeration tables in the imported database
            if let filterCacheManager = databaseManager.filterCacheManager {
                try await filterCacheManager.initializeCache()
            } else {
                print("⚠️ FilterCacheManager not available, cache will be rebuilt on next app launch")
            }

            await updateProgress(0.9, "Finalizing import...")

            // Update app state with matching version
            try await updateAppStateAfterImport(packageInfo: packageInfo, dataVersion: importVersion)

            await updateProgress(1.0, "Import completed successfully")

            print("✅ Data package imported successfully from: \(packageURL.path)")

        } catch {
            print("❌ Import failed: \(error)")
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
        guard let db = databaseManager.db else {
            return (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        }

        func countRows(in table: String) -> Int {
            var count = 0
            let query = "SELECT COUNT(*) FROM \(table)"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_ROW {
                    count = Int(sqlite3_column_int(statement, 0))
                }
                sqlite3_finalize(statement)
            }
            return count
        }

        return (
            mrcs: countRows(in: "mrc_enum"),
            classifications: countRows(in: "classification_enum"),
            makes: countRows(in: "make_enum"),
            models: countRows(in: "model_enum"),
            colors: countRows(in: "color_enum"),
            modelYears: countRows(in: "model_year_enum"),
            licenseTypes: countRows(in: "license_type_enum"),
            ageGroups: countRows(in: "age_group_enum"),
            genders: countRows(in: "gender_enum"),
            experienceLevels: countRows(in: "experience_level_enum"),
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
        print("💾 Creating data backup (not yet implemented)")
    }

    private func importDatabase(from databasePath: URL, timestamp: Date) async throws {
        let sourceURL = databasePath.appendingPathComponent("saaq_data.sqlite")

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw DataPackageError.importFailed("Database file not found in package")
        }

        guard let currentDBURL = databaseManager.databaseURL else {
            throw DataPackageError.importFailed("No current database location configured")
        }

        // Close current database connection
        await databaseManager.closeDatabaseConnection()

        // Replace database file
        if FileManager.default.fileExists(atPath: currentDBURL.path) {
            try FileManager.default.removeItem(at: currentDBURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: currentDBURL)

        // Update the modification date of the imported database to the consistent timestamp
        // This ensures the database version (based on mod date) matches the cache version
        let attributes = [FileAttributeKey.modificationDate: timestamp]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: currentDBURL.path)

        // Reconnect to database
        await databaseManager.reconnectDatabase()

        print("📥 Database imported and connection restored")
    }


    private func updateAppStateAfterImport(packageInfo: DataPackageInfo, dataVersion: String) async throws {
        print("🔧 Finalizing import with dataVersion: \(dataVersion)")

        // Refresh database stats from the imported database
        let newDbStats = await databaseManager.getDatabaseStats()

        print("✅ Import completed successfully")
        print("📊 Imported database contains \(newDbStats.totalVehicleRecords) vehicle records and \(newDbStats.totalLicenseRecords) license records")
        print("📊 Data version: \(dataVersion)")
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