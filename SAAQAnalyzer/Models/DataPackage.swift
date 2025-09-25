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
struct DataPackageInfo: Codable {
    let packageVersion: String
    let vehicleRecordCount: Int
    let driverRecordCount: Int
    let dataYearRange: String
    let exportDate: Date
    let sourceHardware: String
    let databaseVersion: String
    let cacheVersion: String

    /// Package file size information
    struct FileSizeInfo: Codable {
        let databaseSizeBytes: Int64
        let vehicleCacheSizeBytes: Int64
        let driverCacheSizeBytes: Int64
        let totalPackageSizeBytes: Int64
    }

    let fileSizes: FileSizeInfo
}

/// Statistics for vehicle data within the package
struct PackagedVehicleStats: Codable {
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
struct PackagedDriverStats: Codable {
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
struct PackagedDataStats: Codable {
    let vehicleStats: PackagedVehicleStats
    let driverStats: PackagedDriverStats
    let totalRecords: Int
    let exportDate: Date
    let dataVersion: String
}

/// Options for what to include in data package export
struct DataPackageExportOptions {
    let includeVehicleData: Bool
    let includeDriverData: Bool
    let includeVehicleCache: Bool
    let includeDriverCache: Bool
    let compressionLevel: CompressionLevel

    enum CompressionLevel {
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

/// Validation result for data package import
enum DataPackageValidationResult {
    case valid
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
}

/// Error types for data package operations
enum DataPackageError: LocalizedError {
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