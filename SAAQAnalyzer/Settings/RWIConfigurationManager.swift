//
//  RWIConfigurationManager.swift
//  SAAQAnalyzer
//
//  Created on 2025-10-24.
//  Manages RWI configuration storage and persistence
//

import Foundation
import OSLog

/// Manager for RWI configuration with persistence via UserDefaults
@Observable
class RWIConfigurationManager {
    static let shared = RWIConfigurationManager()

    private let storageKey = "rwiConfiguration"
    private(set) var configuration: RWIConfigurationData

    /// Initialize manager, loading from UserDefaults or using defaults
    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(RWIConfigurationData.self, from: data) {
            self.configuration = decoded
            AppLogger.app.info("Loaded RWI configuration from UserDefaults")
        } else {
            self.configuration = .defaultConfiguration
            AppLogger.app.info("Using default RWI configuration")
        }
    }

    /// Save current configuration to UserDefaults
    func save() {
        guard configuration.isValid else {
            AppLogger.app.error("Attempted to save invalid RWI configuration")
            return
        }

        do {
            let encoded = try JSONEncoder().encode(configuration)
            UserDefaults.standard.set(encoded, forKey: storageKey)
            AppLogger.app.info("Saved RWI configuration to UserDefaults")
        } catch {
            AppLogger.app.error("Failed to encode RWI configuration: \(error.localizedDescription)")
        }
    }

    /// Reset configuration to factory defaults
    func resetToDefaults() {
        configuration = .defaultConfiguration
        save()
        AppLogger.app.notice("Reset RWI configuration to defaults")
    }

    /// Export configuration to JSON file
    func exportConfiguration(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(configuration)
        try data.write(to: url, options: .atomic)

        AppLogger.app.info("Exported RWI configuration to \(url.path, privacy: .public)")
    }

    /// Import configuration from JSON file
    func importConfiguration(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()

        let imported = try decoder.decode(RWIConfigurationData.self, from: data)

        // Validate before applying
        guard imported.isValid else {
            throw ConfigurationError.invalidConfiguration
        }

        configuration = imported
        save()

        AppLogger.app.info("Imported RWI configuration from \(url.path, privacy: .public)")
    }

    /// Get coefficient for a specific axle count
    /// Returns coefficient from configuration, or default if not found
    func coefficient(forAxles axles: Int) -> Double {
        // For 6+ axles, use the 6-axle configuration
        let key = axles >= 6 ? 6 : axles

        if let config = configuration.axleConfigurations[key] {
            return config.coefficient
        }

        // Fallback to 2-axle default (50/50 split)
        AppLogger.app.warning("No coefficient configured for \(axles) axles, using default 0.125")
        return 0.125
    }

    /// Get coefficient for a vehicle type (fallback when max_axles is NULL)
    /// Returns coefficient from configuration, or wildcard default if not found
    func coefficient(forVehicleType typeCode: String) -> Double {
        if let fallback = configuration.vehicleTypeFallbacks[typeCode] {
            return fallback.coefficient
        }

        // Fallback to wildcard configuration
        if let wildcard = configuration.vehicleTypeFallbacks["*"] {
            return wildcard.coefficient
        }

        // Ultimate fallback (should never happen with valid default config)
        AppLogger.app.warning("No coefficient configured for vehicle type '\(typeCode, privacy: .public)', using default 0.125")
        return 0.125
    }

    /// Update a specific axle configuration
    func updateAxleConfiguration(_ config: AxleConfiguration) {
        guard config.isValid else {
            AppLogger.app.error("Attempted to update with invalid axle configuration")
            return
        }

        configuration.axleConfigurations[config.axleCount] = config
        save()
    }

    /// Update a specific vehicle type fallback
    func updateVehicleTypeFallback(_ fallback: VehicleTypeFallback) {
        guard fallback.isValid else {
            AppLogger.app.error("Attempted to update with invalid vehicle type fallback")
            return
        }

        configuration.vehicleTypeFallbacks[fallback.typeCode] = fallback
        save()
    }
}

/// Configuration-related errors
enum ConfigurationError: LocalizedError {
    case invalidConfiguration
    case fileNotFound
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "The configuration file contains invalid data. Please check that all weight distributions sum to 100%."
        case .fileNotFound:
            return "The configuration file could not be found."
        case .decodingFailed(let message):
            return "Failed to read configuration file: \(message)"
        }
    }
}
