//
//  DataPackage.swift
//  SAAQAnalyzer
//
//  Created by Claude Code on 2025-01-27.
//

import Foundation
import UniformTypeIdentifiers

/// UTType for SAAQ data packages
extension UTType {
    static let saaqPackage = UTType(exportedAs: "com.endoquant.saaqanalyzer.package")
}

/// Represents the contents of a SAAQ data package
struct DataPackageInfo: Codable, Sendable {
    let packageVersion: String
    let vehicleRecordCount: Int
    let driverRecordCount: Int
    let dataYearRange: String
    let exportDate: Date
    let sourceHardware: String
    let databaseVersion: String
    let cacheVersion: String

    /// Package file size information
    struct FileSizeInfo: Codable, Sendable {
        let databaseSizeBytes: Int64
        let vehicleCacheSizeBytes: Int64
        let driverCacheSizeBytes: Int64
        let totalPackageSizeBytes: Int64
    }

    let fileSizes: FileSizeInfo
}

/// Statistics for vehicle data within the package
struct PackagedVehicleStats: Codable, Sendable {
    let totalRecords: Int
    let yearRange: String
    let availableYearsCount: Int
    let regions: Int
    let mrcs: Int
    let municipalities: Int
    let classifications: Int
    let makes: Int
    let models: Int
    let colors: Int
    let modelYears: Int
    let lastUpdated: Date
}

/// Statistics for driver data within the package
struct PackagedDriverStats: Codable, Sendable {
    let totalRecords: Int
    let yearRange: String
    let availableYearsCount: Int
    let regions: Int
    let mrcs: Int
    let licenseTypes: Int
    let ageGroups: Int
    let genders: Int
    let experienceLevels: Int
    let licenseClasses: Int
    let lastUpdated: Date
}

/// Combined statistics for the entire package
struct PackagedDataStats: Codable, Sendable {
    let vehicleStats: PackagedVehicleStats
    let driverStats: PackagedDriverStats
    let totalRecords: Int
    let exportDate: Date
    let dataVersion: String
}

/// Options for what to include in data package export
struct DataPackageExportOptions: Sendable {
    let includeVehicleData: Bool
    let includeDriverData: Bool
    let includeVehicleCache: Bool
    let includeDriverCache: Bool
    let compressionLevel: CompressionLevel

    enum CompressionLevel: Sendable {
        case none
        case fast
        case balanced
        case maximum
    }

    static let complete = DataPackageExportOptions(
        includeVehicleData: true,
        includeDriverData: true,
        includeVehicleCache: true,
        includeDriverCache: true,
        compressionLevel: .balanced
    )

    static let vehicleOnly = DataPackageExportOptions(
        includeVehicleData: true,
        includeDriverData: false,
        includeVehicleCache: true,
        includeDriverCache: false,
        compressionLevel: .balanced
    )

    static let driverOnly = DataPackageExportOptions(
        includeVehicleData: false,
        includeDriverData: true,
        includeVehicleCache: false,
        includeDriverCache: true,
        compressionLevel: .balanced
    )

    static let cacheOnly = DataPackageExportOptions(
        includeVehicleData: false,
        includeDriverData: false,
        includeVehicleCache: true,
        includeDriverCache: true,
        compressionLevel: .fast
    )
}

/// Import mode for data packages
enum DataPackageImportMode: String, CaseIterable, Sendable {
    case replace = "Replace Database"
    case merge = "Merge Non-Overlapping Data"

    var description: String {
        switch self {
        case .replace:
            return "Replace entire database with package contents (fast - use for full backups)"
        case .merge:
            return "Merge only non-overlapping data types (e.g., add licenses to vehicle-only database)"
        }
    }

    /// Detailed explanation shown in UI
    var detailedExplanation: String {
        switch self {
        case .replace:
            return """
            Replaces your entire database with the package contents.
            • Fast file copy operation
            • Use for restoring full backups
            • All existing data will be replaced
            """
        case .merge:
            return """
            Merges data only when types don't overlap.

            ✓ Safe merges:
            • Import licenses into vehicle-only database
            • Import vehicles into license-only database

            ✗ Blocked merges (use Replace instead):
            • Import vehicles when database already has vehicles
            • Import licenses when database already has licenses
            • Import packages containing both types

            This prevents accidental data loss from overlapping records.
            """
        }
    }
}

/// Package content description - what data is included
struct DataPackageContent: Sendable {
    let hasVehicleData: Bool
    let hasLicenseData: Bool
    let vehicleRecordCount: Int
    let licenseRecordCount: Int

    var isEmpty: Bool {
        return !hasVehicleData && !hasLicenseData
    }

    var description: String {
        if hasVehicleData && hasLicenseData {
            return "Vehicle and License data"
        } else if hasVehicleData {
            return "Vehicle data only"
        } else if hasLicenseData {
            return "License data only"
        } else {
            return "No data"
        }
    }

    var detailedDescription: String {
        var parts: [String] = []
        if hasVehicleData {
            parts.append("\(vehicleRecordCount.formatted()) vehicle records")
        }
        if hasLicenseData {
            parts.append("\(licenseRecordCount.formatted()) license records")
        }
        return parts.isEmpty ? "No data" : parts.joined(separator: " + ")
    }
}

/// Validation result for data package import
enum DataPackageValidationResult: Sendable {
    case valid(DataPackageContent)
    case invalidFormat
    case incompatibleVersion
    case corruptedData
    case missingFiles
    case insufficientDiskSpace

    var errorMessage: String {
        switch self {
        case .valid:
            return ""
        case .invalidFormat:
            return "Invalid package format. This does not appear to be a valid SAAQ data package."
        case .incompatibleVersion:
            return "Incompatible package version. This package was created with a newer version of SAAQAnalyzer."
        case .corruptedData:
            return "Package data appears to be corrupted. Please try re-exporting the package."
        case .missingFiles:
            return "Package is missing required files. The package may be incomplete."
        case .insufficientDiskSpace:
            return "Insufficient disk space to import this package. Please free up disk space and try again."
        }
    }

    var isValid: Bool {
        if case .valid = self {
            return true
        }
        return false
    }

    var content: DataPackageContent? {
        if case .valid(let content) = self {
            return content
        }
        return nil
    }
}

/// Error types for data package operations
enum DataPackageError: LocalizedError, Sendable {
    case exportFailed(String)
    case importFailed(String)
    case validationFailed(DataPackageValidationResult)
    case fileSystemError(String)

    var errorDescription: String? {
        switch self {
        case .exportFailed(let message):
            return "Export failed: \(message)"
        case .importFailed(let message):
            return "Import failed: \(message)"
        case .validationFailed(let result):
            return result.errorMessage
        case .fileSystemError(let message):
            return "File system error: \(message)"
        }
    }
}