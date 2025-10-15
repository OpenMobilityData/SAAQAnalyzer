//
//  AppVersion.swift
//  SAAQAnalyzer
//
//  Provides compile-time build information for version tracking
//

import Foundation

/// Compile-time build information
enum AppVersion {
    /// Build timestamp - captures when the app binary was created
    /// This uses the app bundle's creation date as a proxy for build time
    private static let buildTimestamp: Date = {
        if let bundlePath = Bundle.main.bundlePath as NSString?,
           let attributes = try? FileManager.default.attributesOfItem(atPath: bundlePath as String),
           let creationDate = attributes[.creationDate] as? Date {
            return creationDate
        }
        // Fallback: use executable modification date
        if let executableURL = Bundle.main.executableURL,
           let attributes = try? FileManager.default.attributesOfItem(atPath: executableURL.path),
           let modificationDate = attributes[.modificationDate] as? Date {
            return modificationDate
        }
        // Final fallback
        return Date()
    }()

    /// Build date in ISO 8601 format
    static let buildDate: String = {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: buildTimestamp)
    }()

    /// Human-readable build date
    static let buildDateFormatted: String = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: buildTimestamp)
    }()

    /// App version from bundle
    static let version: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }()

    /// Build number from bundle
    static let build: String = {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }()

    /// Full version string combining version, build, and build date
    static let fullVersion: String = {
        "Version \(version) (\(build)) - Built \(buildDateFormatted)"
    }()

    /// Compact version string for logging
    static let compact: String = {
        "\(version) (\(build))"
    }()
}
