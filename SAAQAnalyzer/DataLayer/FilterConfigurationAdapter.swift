import Foundation

/// Adapter to help transition from string-based to integer-based FilterConfiguration
/// Provides conversion methods between the old and new systems
class FilterConfigurationAdapter {
    private let enumManager: CategoricalEnumManager

    init(enumManager: CategoricalEnumManager) {
        self.enumManager = enumManager
    }

    // MARK: - String to Integer Conversion

    /// Convert string-based FilterConfiguration to integer-based
    func convertToIntegerBased(_ config: FilterConfiguration) async throws -> IntegerFilterConfiguration {
        var integerConfig = IntegerFilterConfiguration()
        integerConfig.dataEntityType = config.dataEntityType
        integerConfig.years = config.years
        integerConfig.modelYears = config.modelYears
        integerConfig.ageRanges = config.ageRanges
        integerConfig.metricType = config.metricType
        integerConfig.metricField = config.metricField

        // Convert string sets to integer sets
        integerConfig.regions = try await convertStringsToIds(config.regions, table: "admin_region_enum", column: "code")
        integerConfig.mrcs = try await convertStringsToIds(config.mrcs, table: "mrc_enum", column: "code")
        integerConfig.municipalities = try await convertStringsToIds(config.municipalities, table: "municipality_enum", column: "code")

        // Vehicle-specific conversions
        integerConfig.vehicleClassifications = try await convertStringsToIds(config.vehicleClassifications, table: "classification_enum", column: "code")
        integerConfig.vehicleMakes = try await convertStringsToIds(config.vehicleMakes, table: "make_enum", column: "name")
        integerConfig.vehicleModels = try await convertStringsToIds(config.vehicleModels, table: "model_enum", column: "name")
        integerConfig.vehicleColors = try await convertStringsToIds(config.vehicleColors, table: "color_enum", column: "name")
        integerConfig.fuelTypes = try await convertStringsToIds(config.fuelTypes, table: "fuel_type_enum", column: "code")

        // License-specific conversions
        integerConfig.licenseTypes = try await convertStringsToIds(config.licenseTypes, table: "license_type_enum", column: "type_name")
        integerConfig.ageGroups = try await convertStringsToIds(config.ageGroups, table: "age_group_enum", column: "range_text")
        integerConfig.genders = try await convertStringsToIds(config.genders, table: "gender_enum", column: "code")

        // Keep string-based fields as-is for now
        integerConfig.experienceLevels = config.experienceLevels
        integerConfig.licenseClasses = config.licenseClasses

        return integerConfig
    }

    /// Convert integer-based FilterConfiguration to string-based
    func convertToStringBased(_ integerConfig: IntegerFilterConfiguration) async throws -> FilterConfiguration {
        var config = FilterConfiguration()
        config.dataEntityType = integerConfig.dataEntityType
        config.years = integerConfig.years
        config.modelYears = integerConfig.modelYears
        config.ageRanges = integerConfig.ageRanges
        config.metricType = integerConfig.metricType
        config.metricField = integerConfig.metricField

        // Convert integer sets to string sets
        config.regions = try await convertIdsToStrings(integerConfig.regions, table: "admin_region_enum", column: "code")
        config.mrcs = try await convertIdsToStrings(integerConfig.mrcs, table: "mrc_enum", column: "code")
        config.municipalities = try await convertIdsToStrings(integerConfig.municipalities, table: "municipality_enum", column: "code")

        // Vehicle-specific conversions
        config.vehicleClassifications = try await convertIdsToStrings(integerConfig.vehicleClassifications, table: "classification_enum", column: "code")
        config.vehicleMakes = try await convertIdsToStrings(integerConfig.vehicleMakes, table: "make_enum", column: "name")
        config.vehicleModels = try await convertIdsToStrings(integerConfig.vehicleModels, table: "model_enum", column: "name")
        config.vehicleColors = try await convertIdsToStrings(integerConfig.vehicleColors, table: "color_enum", column: "name")
        config.fuelTypes = try await convertIdsToStrings(integerConfig.fuelTypes, table: "fuel_type_enum", column: "code")

        // License-specific conversions
        config.licenseTypes = try await convertIdsToStrings(integerConfig.licenseTypes, table: "license_type_enum", column: "type_name")
        config.ageGroups = try await convertIdsToStrings(integerConfig.ageGroups, table: "age_group_enum", column: "range_text")
        config.genders = try await convertIdsToStrings(integerConfig.genders, table: "gender_enum", column: "code")

        // Keep string-based fields as-is
        config.experienceLevels = integerConfig.experienceLevels
        config.licenseClasses = integerConfig.licenseClasses

        return config
    }

    // MARK: - Helper Methods

    private func convertStringsToIds(_ strings: Set<String>, table: String, column: String) async throws -> Set<Int> {
        var ids = Set<Int>()

        for string in strings {
            if let id = try await enumManager.getEnumId(table: table, column: column, value: string) {
                ids.insert(id)
            } else {
                print("⚠️ Warning: Could not find ID for '\(string)' in \(table).\(column)")
            }
        }

        return ids
    }

    private func convertIdsToStrings(_ ids: Set<Int>, table: String, column: String) async throws -> Set<String> {
        var strings = Set<String>()

        for id in ids {
            if let string = try await enumManager.getEnumValue(table: table, column: column, id: id) {
                strings.insert(string)
            } else {
                print("⚠️ Warning: Could not find string for ID \(id) in \(table).\(column)")
            }
        }

        return strings
    }
}