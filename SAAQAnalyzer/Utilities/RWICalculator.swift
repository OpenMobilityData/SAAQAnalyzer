//
//  RWICalculator.swift
//  SAAQAnalyzer
//
//  Created on 2025-10-24.
//  Generates SQL for Road Wear Index calculations based on configuration
//

import Foundation
import OSLog

/// Generates SQL CASE expressions for RWI calculations
struct RWICalculator {
    let configManager = RWIConfigurationManager.shared

    private static var cachedSQL: String?
    private static var lastConfigHash: Int?

    /// Generate SQL CASE expression for RWI calculation
    /// Returns SQL string that can be embedded in queries
    /// Uses caching to avoid regenerating SQL on every call
    func generateSQLCalculation() -> String {
        let currentHash = configManager.configuration.hashValue

        // Return cached SQL if configuration hasn't changed
        if let cached = Self.cachedSQL, Self.lastConfigHash == currentHash {
            return cached
        }

        // Generate fresh SQL
        let sql = generateSQLInternal()
        Self.cachedSQL = sql
        Self.lastConfigHash = currentHash

        AppLogger.query.debug("Generated RWI SQL calculation (cache miss)")

        return sql
    }

    /// Internal SQL generation (no caching)
    private func generateSQLInternal() -> String {
        var cases: [String] = []

        // Axle-based cases (when max_axles is not NULL)
        // Sort by axle count for consistent SQL generation
        let sortedAxleConfigs = configManager.configuration.axleConfigurations
            .sorted { $0.key < $1.key }

        for (axleCount, config) in sortedAxleConfigs {
            let condition = axleCount == 6
                ? "v.max_axles >= 6"  // 6+ axles
                : "v.max_axles = \(axleCount)"

            cases.append("WHEN \(condition) THEN \(config.coefficient) * POWER(v.net_mass_int, 4)")
        }

        // Vehicle type fallbacks (when max_axles is NULL)
        // Sort by type code for consistent SQL generation, but skip wildcard
        let sortedFallbacks = configManager.configuration.vehicleTypeFallbacks
            .filter { $0.key != "*" }  // Wildcard goes in ELSE clause
            .sorted { $0.key < $1.key }

        for (typeCode, fallback) in sortedFallbacks {
            cases.append("""
                WHEN v.vehicle_type_id IN (SELECT id FROM vehicle_type_enum WHERE code = '\(typeCode)')
                THEN \(fallback.coefficient) * POWER(v.net_mass_int, 4)
                """)
        }

        // Default fallback (wildcard)
        let defaultCoef = configManager.configuration.vehicleTypeFallbacks["*"]?.coefficient ?? 0.125

        let sql = """
            CASE
                \(cases.joined(separator: "\n    "))
                ELSE \(defaultCoef) * POWER(v.net_mass_int, 4)
            END
            """

        return sql
    }

    /// Invalidate cached SQL (call when configuration changes)
    static func invalidateCache() {
        cachedSQL = nil
        lastConfigHash = nil
        AppLogger.query.debug("Invalidated RWI SQL cache")
    }

    /// Get a human-readable description of the current configuration
    func getConfigurationSummary() -> String {
        var summary = "RWI Configuration:\n"

        // Axle-based configurations
        summary += "\nAxle-Based Coefficients:\n"
        for (axleCount, config) in configManager.configuration.axleConfigurations.sorted(by: { $0.key < $1.key }) {
            let label = axleCount == 6 ? "6+ axles" : "\(axleCount) axles"
            summary += "  \(label): \(config.distributionDescription) → \(String(format: "%.4f", config.coefficient))\n"
        }

        // Vehicle type fallbacks
        summary += "\nVehicle Type Fallbacks:\n"
        for (typeCode, fallback) in configManager.configuration.vehicleTypeFallbacks.sorted(by: { $0.key < $1.key }) {
            summary += "  \(typeCode) (\(fallback.description)): \(fallback.assumedAxles) axles, \(fallback.distributionDescription) → \(String(format: "%.4f", fallback.coefficient))\n"
        }

        return summary
    }
}
