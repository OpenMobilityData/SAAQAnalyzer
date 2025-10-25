//
//  RWIConfiguration.swift
//  SAAQAnalyzer
//
//  Created on 2025-10-24.
//  Road Wear Index configuration data models
//

import Foundation

/// Configuration for a specific axle count's weight distribution
struct AxleConfiguration: Codable, Equatable, Hashable, Identifiable {
    var id: Int { axleCount }  // Use axle count as identifier
    let axleCount: Int  // 2, 3, 4, 5, or 6+
    var weightDistribution: [Double]  // Percentages (must sum to 100)
    var coefficient: Double  // Calculated from distribution using 4th power law

    /// Validate that weight distribution is valid
    var isValid: Bool {
        let sum = weightDistribution.reduce(0, +)
        return abs(sum - 100.0) < 0.01 &&
               weightDistribution.count == numberOfAxles &&
               weightDistribution.allSatisfy { $0 > 0 && $0 <= 100 }
    }

    /// Number of axles this configuration applies to
    /// For 6+, this is still the actual count in weightDistribution
    var numberOfAxles: Int {
        weightDistribution.count
    }

    /// Recalculate coefficient from current weight distribution
    /// Coefficient = Σ(weight_fraction⁴)
    mutating func recalculateCoefficient() {
        coefficient = weightDistribution
            .map { pow($0 / 100.0, 4) }
            .reduce(0, +)
    }

    /// Human-readable description of weight distribution
    var distributionDescription: String {
        let percentages = weightDistribution.map { String(format: "%.0f%%", $0) }
        if axleCount == 2 {
            return "\(percentages[0]) F, \(percentages[1]) R"
        } else if axleCount == 3 {
            return "\(percentages[0]) F, \(percentages[1]) R1, \(percentages[2]) R2"
        } else {
            return percentages.enumerated().map { "\(percentages[$0.offset])" }.joined(separator: ", ")
        }
    }
}

/// Fallback configuration for vehicle types when max_axles is NULL
struct VehicleTypeFallback: Codable, Equatable, Hashable, Identifiable {
    let id = UUID()
    let typeCode: String  // "CA", "VO", "AB", "AU", "*" (wildcard)
    let description: String  // "Truck", "Bus", etc.
    var assumedAxles: Int  // 2-6+
    var weightDistribution: [Double]  // Percentages (must sum to 100)
    var coefficient: Double  // Calculated from distribution

    /// Validate that configuration is valid
    var isValid: Bool {
        let sum = weightDistribution.reduce(0, +)
        return abs(sum - 100.0) < 0.01 &&
               weightDistribution.count == assumedAxles &&
               weightDistribution.allSatisfy { $0 > 0 && $0 <= 100 } &&
               assumedAxles >= 2 && assumedAxles <= 6
    }

    /// Recalculate coefficient from current weight distribution
    mutating func recalculateCoefficient() {
        coefficient = weightDistribution
            .map { pow($0 / 100.0, 4) }
            .reduce(0, +)
    }

    /// Human-readable description of weight distribution
    var distributionDescription: String {
        weightDistribution.map { String(format: "%.0f%%", $0) }.joined(separator: "/")
    }

    // Custom coding keys to handle UUID
    enum CodingKeys: String, CodingKey {
        case typeCode, description, assumedAxles, weightDistribution, coefficient
    }

    // Custom Hashable conformance (exclude id for consistency with Codable)
    func hash(into hasher: inout Hasher) {
        hasher.combine(typeCode)
        hasher.combine(description)
        hasher.combine(assumedAxles)
        hasher.combine(weightDistribution)
        hasher.combine(coefficient)
    }

    // Custom Equatable conformance (exclude id for consistency with Codable)
    static func == (lhs: VehicleTypeFallback, rhs: VehicleTypeFallback) -> Bool {
        lhs.typeCode == rhs.typeCode &&
        lhs.description == rhs.description &&
        lhs.assumedAxles == rhs.assumedAxles &&
        lhs.weightDistribution == rhs.weightDistribution &&
        lhs.coefficient == rhs.coefficient
    }
}

/// Root configuration object for RWI calculations
struct RWIConfigurationData: Codable, Equatable, Hashable {
    var axleConfigurations: [Int: AxleConfiguration]  // Key = axle count (2-6)
    var vehicleTypeFallbacks: [String: VehicleTypeFallback]  // Key = type code
    var schemaVersion: Int = 1  // For future migrations

    /// Default configuration matching current hardcoded implementation
    static var defaultConfiguration: RWIConfigurationData {
        var config = RWIConfigurationData(
            axleConfigurations: [:],
            vehicleTypeFallbacks: [:],
            schemaVersion: 1
        )

        // Axle-based configurations (from QueryManager.swift:692-726)
        // 2 axles: 45% front, 55% rear → coefficient 0.1325
        var config2 = AxleConfiguration(
            axleCount: 2,
            weightDistribution: [45.0, 55.0],
            coefficient: 0.1325
        )
        config2.recalculateCoefficient()
        config.axleConfigurations[2] = config2

        // 3 axles: 30% F, 35% R1, 35% R2 → coefficient 0.0234
        var config3 = AxleConfiguration(
            axleCount: 3,
            weightDistribution: [30.0, 35.0, 35.0],
            coefficient: 0.0234
        )
        config3.recalculateCoefficient()
        config.axleConfigurations[3] = config3

        // 4 axles: 25% each → coefficient 0.0156
        var config4 = AxleConfiguration(
            axleCount: 4,
            weightDistribution: [25.0, 25.0, 25.0, 25.0],
            coefficient: 0.0156
        )
        config4.recalculateCoefficient()
        config.axleConfigurations[4] = config4

        // 5 axles: 20% each → coefficient 0.0080
        var config5 = AxleConfiguration(
            axleCount: 5,
            weightDistribution: [20.0, 20.0, 20.0, 20.0, 20.0],
            coefficient: 0.0080
        )
        config5.recalculateCoefficient()
        config.axleConfigurations[5] = config5

        // 6+ axles: 16.67% each (6 axles) → coefficient 0.0046
        var config6 = AxleConfiguration(
            axleCount: 6,
            weightDistribution: [16.67, 16.67, 16.67, 16.67, 16.67, 16.66],
            coefficient: 0.0046
        )
        config6.recalculateCoefficient()
        config.axleConfigurations[6] = config6

        // Vehicle type fallbacks (when max_axles is NULL)
        // CA (Truck) / VO (Tool): Assume 3 axles
        var fallbackCA = VehicleTypeFallback(
            typeCode: "CA",
            description: "Truck",
            assumedAxles: 3,
            weightDistribution: [30.0, 35.0, 35.0],
            coefficient: 0.0234
        )
        fallbackCA.recalculateCoefficient()
        config.vehicleTypeFallbacks["CA"] = fallbackCA

        var fallbackVO = VehicleTypeFallback(
            typeCode: "VO",
            description: "Tool Vehicle",
            assumedAxles: 3,
            weightDistribution: [30.0, 35.0, 35.0],
            coefficient: 0.0234
        )
        fallbackVO.recalculateCoefficient()
        config.vehicleTypeFallbacks["VO"] = fallbackVO

        // AB (Bus): Assume 2 axles (35/65 split)
        var fallbackAB = VehicleTypeFallback(
            typeCode: "AB",
            description: "Bus",
            assumedAxles: 2,
            weightDistribution: [35.0, 65.0],
            coefficient: 0.1935
        )
        fallbackAB.recalculateCoefficient()
        config.vehicleTypeFallbacks["AB"] = fallbackAB

        // AU (Car): Assume 2 axles (50/50 split)
        var fallbackAU = VehicleTypeFallback(
            typeCode: "AU",
            description: "Car",
            assumedAxles: 2,
            weightDistribution: [50.0, 50.0],
            coefficient: 0.125
        )
        fallbackAU.recalculateCoefficient()
        config.vehicleTypeFallbacks["AU"] = fallbackAU

        // * (Wildcard/Other): Assume 2 axles (50/50 split)
        var fallbackWildcard = VehicleTypeFallback(
            typeCode: "*",
            description: "Other",
            assumedAxles: 2,
            weightDistribution: [50.0, 50.0],
            coefficient: 0.125
        )
        fallbackWildcard.recalculateCoefficient()
        config.vehicleTypeFallbacks["*"] = fallbackWildcard

        return config
    }

    /// Validate entire configuration
    var isValid: Bool {
        axleConfigurations.values.allSatisfy { $0.isValid } &&
        vehicleTypeFallbacks.values.allSatisfy { $0.isValid }
    }
}
