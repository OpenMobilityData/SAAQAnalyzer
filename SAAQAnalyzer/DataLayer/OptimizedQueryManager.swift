import Foundation
import SQLite3

/// Holds converted filter IDs for optimized queries
struct OptimizedFilterIds: Sendable {
    let yearIds: [Int]
    let regionIds: [Int]
    let mrcIds: [Int]
    let municipalityIds: [Int]
    let classificationIds: [Int]
    let vehicleTypeIds: [Int]
    let makeIds: [Int]
    let modelIds: [Int]
    let colorIds: [Int]
    let modelYearIds: [Int]
    let fuelTypeIds: [Int]
    let axleCounts: [Int]
    // License-specific
    let licenseTypeIds: [Int]
    let ageGroupIds: [Int]
    let genderIds: [Int]
    let experienceLevelIds: [Int]
}

/// Simplified high-performance query manager using categorical enumeration
class OptimizedQueryManager {
    private weak var databaseManager: DatabaseManager?
    private var db: OpaquePointer? { databaseManager?.db }
    private let enumManager: CategoricalEnumManager

    /// Flag to enable/disable regularization in queries
    var regularizationEnabled: Bool = false

    /// Flag to enable/disable Make/Model coupling in regularization
    /// When true (default): Regularization respects Make/Model relationships
    /// When false: Make and Model filters remain independent even with regularization
    var regularizationCoupling: Bool = true

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        self.enumManager = CategoricalEnumManager(databaseManager: databaseManager)
    }

    // MARK: - Optimized Vehicle Query Using Integer Enumerations

    /// High-performance vehicle data query using integer enumerations
    func queryOptimizedVehicleData(filters: FilterConfiguration) async throws -> FilteredDataSeries {
        print("🚀 Starting OPTIMIZED vehicle query with integer enumerations...")

        // Debug: Log the filters we received
        print("🔍 Received filters:")
        print("   Years: \(filters.years)")
        print("   Regions: \(filters.regions)")
        print("   MRCs: \(filters.mrcs)")
        print("   Municipalities: \(filters.municipalities)")
        print("   Vehicle Classifications: \(filters.vehicleClasses)")
        print("   Vehicle Types: \(filters.vehicleTypes)")
        print("   Vehicle Makes: \(filters.vehicleMakes)")
        print("   Vehicle Models: \(filters.vehicleModels)")
        print("   Vehicle Colors: \(filters.vehicleColors)")
        print("   Model Years: \(filters.modelYears)")
        print("   Fuel Types: \(filters.fuelTypes)")
        print("   Age Ranges: \(filters.ageRanges)")

        // First, convert filter strings to integer IDs
        let filterIds = try await convertFiltersToIds(filters: filters, isVehicle: true)

        // Run the optimized query using integer columns
        return try await queryVehicleDataWithIntegers(filters: filters, filterIds: filterIds)
    }

    /// Extract code from "Name (##)" formatted string
    private func extractCode(from displayString: String) -> String? {
        // Match content within parentheses at end of string: "Name (code)"
        let pattern = /\(([^)]+)\)\s*$/

        if let match = displayString.firstMatch(of: pattern) {
            let code = String(match.1).trimmingCharacters(in: .whitespaces)
            return code.isEmpty ? nil : code
        }
        return nil
    }

    /// Convert filter strings to enumeration IDs
    private func convertFiltersToIds(filters: FilterConfiguration, isVehicle: Bool) async throws -> OptimizedFilterIds {
        var yearIds: [Int] = []
        var regionIds: [Int] = []
        var mrcIds: [Int] = []
        var municipalityIds: [Int] = []
        var classificationIds: [Int] = []
        var vehicleTypeIds: [Int] = []
        var makeIds: [Int] = []
        var modelIds: [Int] = []
        var colorIds: [Int] = []
        var modelYearIds: [Int] = []
        var fuelTypeIds: [Int] = []
        var licenseTypeIds: [Int] = []
        var ageGroupIds: [Int] = []
        var genderIds: [Int] = []
        var experienceLevelIds: [Int] = []

        // Convert years to IDs
        // If limiting to curated years, intersect with curated years set
        var yearsToQuery = filters.years
        if filters.limitToCuratedYears {
            // Get curated years from RegularizationManager
            if let regManager = databaseManager?.regularizationManager {
                let yearConfig = regManager.getYearConfiguration()
                let curatedYears = yearConfig.curatedYears
                yearsToQuery = filters.years.intersection(curatedYears)
                print("🎯 Limiting to curated years: \(yearsToQuery.sorted())")
            }
        }

        for year in yearsToQuery {
            if let id = try await enumManager.getEnumId(table: "year_enum", column: "year", value: String(year)) {
                yearIds.append(id)
            }
        }

        // Convert regions to IDs (extract code from "Name (##)" format)
        for region in filters.regions {
            let regionCode = extractCode(from: region) ?? region
            if let id = try await enumManager.getEnumId(table: "admin_region_enum", column: "code", value: regionCode) {
                print("🔍 Region '\(region)' (code: '\(regionCode)') -> ID \(id)")
                regionIds.append(id)
            } else {
                print("⚠️ Region code '\(regionCode)' not found in admin_region_enum table")
            }
        }

        // Convert MRCs to IDs (extract code from "Name (##)" format)
        for mrc in filters.mrcs {
            let mrcCode = extractCode(from: mrc) ?? mrc
            if let id = try await enumManager.getEnumId(table: "mrc_enum", column: "code", value: mrcCode) {
                print("🔍 MRC '\(mrc)' (code: '\(mrcCode)') -> ID \(id)")
                mrcIds.append(id)
            } else {
                print("⚠️ MRC code '\(mrcCode)' not found in enum table")
            }
        }

        // Convert municipalities to IDs (extract code from "Name (##)" format)
        for municipality in filters.municipalities {
            let muniCode = extractCode(from: municipality) ?? municipality
            if let id = try await enumManager.getEnumId(table: "municipality_enum", column: "code", value: muniCode) {
                municipalityIds.append(id)
            }
        }

        // Convert vehicle-specific filters
        if isVehicle {
            // Classifications: UI shows descriptions, need to extract codes
            // e.g., "Personal automobile/light truck" -> lookup by description in DB
            for vehicleClass in filters.vehicleClasses {
                // Try direct lookup first (if user selected by code)
                if let id = try await enumManager.getEnumId(table: "vehicle_class_enum", column: "code", value: vehicleClass) {
                    print("🔍 Classification '\(vehicleClass)' -> ID \(id)")
                    classificationIds.append(id)
                } else if let id = try await enumManager.getEnumId(table: "vehicle_class_enum", column: "description", value: vehicleClass) {
                    print("🔍 Classification '\(vehicleClass)' (by description) -> ID \(id)")
                    classificationIds.append(id)
                } else {
                    print("⚠️ Classification '\(vehicleClass)' not found in enum table")
                }
            }

            // Vehicle Types: UI shows codes directly
            for vehicleType in filters.vehicleTypes {
                if let id = try await enumManager.getEnumId(table: "vehicle_type_enum", column: "code", value: vehicleType) {
                    print("🔍 Vehicle Type '\(vehicleType)' -> ID \(id)")
                    vehicleTypeIds.append(id)
                } else {
                    print("⚠️ Vehicle Type '\(vehicleType)' not found in enum table")
                }
            }

            // For makes, use FilterCacheManager to ensure correct ID lookup
            // (similar to models - though Make names are typically unique)
            for make in filters.vehicleMakes {
                if let filterCache = databaseManager?.filterCacheManager {
                    // Get all makes from cache
                    let allMakes = try await filterCache.getAvailableMakes(limitToCuratedYears: false)

                    // Find the FilterItem whose displayName matches our filter string
                    if let matchingMake = allMakes.first(where: { $0.displayName == make }) {
                        print("🔍 Make '\(make)' -> ID \(matchingMake.id) (via FilterCacheManager)")
                        makeIds.append(matchingMake.id)
                    } else {
                        print("⚠️ Make '\(make)' not found in FilterCacheManager")
                    }
                } else {
                    print("⚠️ FilterCacheManager not available")
                }
            }

            // For models, we MUST use FilterCacheManager to get the correct model_id
            // because model names are NOT unique (e.g., "ART" exists for multiple makes)
            // The FilterItem already has the correct model_id for the Make+Model combination
            for model in filters.vehicleModels {
                if let filterCache = databaseManager?.filterCacheManager {
                    // Get all models from cache
                    let allModels = try await filterCache.getAvailableModels(limitToCuratedYears: false, forMakeIds: nil)

                    // Find the FilterItem whose displayName matches our filter string
                    if let matchingModel = allModels.first(where: { $0.displayName == model }) {
                        print("🔍 Model '\(model)' -> ID \(matchingModel.id) (via FilterCacheManager)")
                        modelIds.append(matchingModel.id)
                    } else {
                        print("⚠️ Model '\(model)' not found in FilterCacheManager")
                    }
                } else {
                    print("⚠️ FilterCacheManager not available")
                }
            }

            // Apply regularization expansion if enabled
            // IMPORTANT: Only apply regularization when NOT limiting to curated years
            // Regularization is for uncurated data only (2023-2024)
            if regularizationEnabled && !filters.limitToCuratedYears {
                if let regManager = databaseManager?.regularizationManager {
                    // NOTE: We do NOT expand Make/Model IDs based on vehicle type filtering
                    // The EXISTS subquery in the WHERE clause handles NULL vehicle_type_id correctly
                    // Expanding IDs here causes over-matching (pulls in ALL makes with that vehicle type)

                    // Only expand Make/Model IDs when the user explicitly filters by Make or Model
                    // This ensures regularization only affects the specific makes/models selected

                    // Expand Make IDs (only if Make filter is active)
                    if !makeIds.isEmpty {
                        makeIds = try await regManager.expandMakeIDs(makeIds: makeIds)
                    }

                    // Expand Make/Model IDs together (only if Model filter is active)
                    if !modelIds.isEmpty {
                        let (expandedMakeIds, expandedModelIds) = try await regManager.expandMakeModelIDs(
                            makeIds: makeIds,
                            modelIds: modelIds,
                            coupling: regularizationCoupling
                        )
                        makeIds = expandedMakeIds
                        modelIds = expandedModelIds
                    }
                }
            }

            for color in filters.vehicleColors {
                if let id = try await enumManager.getEnumId(table: "color_enum", column: "name", value: color) {
                    print("🔍 Color '\(color)' -> ID \(id)")
                    colorIds.append(id)
                } else {
                    print("⚠️ Color '\(color)' not found in enum table")
                }
            }

            for modelYear in filters.modelYears {
                if let id = try await enumManager.getEnumId(table: "model_year_enum", column: "year", value: String(modelYear)) {
                    print("🔍 Model year '\(modelYear)' -> ID \(id)")
                    modelYearIds.append(id)
                } else {
                    print("⚠️ Model year '\(modelYear)' not found in enum table")
                }
            }

            // Fuel types: UI shows descriptions, need to lookup by description
            for fuelType in filters.fuelTypes {
                // Try code first (if user somehow selected by code)
                if let id = try await enumManager.getEnumId(table: "fuel_type_enum", column: "code", value: fuelType) {
                    print("🔍 Fuel type '\(fuelType)' -> ID \(id)")
                    fuelTypeIds.append(id)
                } else if let id = try await enumManager.getEnumId(table: "fuel_type_enum", column: "description", value: fuelType) {
                    print("🔍 Fuel type '\(fuelType)' (by description) -> ID \(id)")
                    fuelTypeIds.append(id)
                } else {
                    print("⚠️ Fuel type '\(fuelType)' not found in enum table")
                }
            }

            // Axle counts are already integers, no conversion needed
            // We'll use them directly in the WHERE clause
        } else {
            // License-specific filters
            for licenseType in filters.licenseTypes {
                if let id = try await enumManager.getEnumId(table: "license_type_enum", column: "type_name", value: licenseType) {
                    licenseTypeIds.append(id)
                }
            }

            for ageGroup in filters.ageGroups {
                if let id = try await enumManager.getEnumId(table: "age_group_enum", column: "range_text", value: ageGroup) {
                    ageGroupIds.append(id)
                }
            }

            for gender in filters.genders {
                if let id = try await enumManager.getEnumId(table: "gender_enum", column: "code", value: gender) {
                    genderIds.append(id)
                }
            }

            for experienceLevel in filters.experienceLevels {
                if let id = try await enumManager.getEnumId(table: "experience_level_enum", column: "level_text", value: experienceLevel) {
                    experienceLevelIds.append(id)
                }
            }
        }

        // Debug summary
        print("🔍 Filter ID conversion summary:")
        print("   Years: \(yearIds.count) -> \(yearIds)")
        print("   Regions: \(regionIds.count) -> \(regionIds)")
        print("   MRCs: \(mrcIds.count) -> \(mrcIds)")
        print("   Municipalities: \(municipalityIds.count) -> \(municipalityIds)")
        if isVehicle {
            print("   Classifications: \(classificationIds.count) -> \(classificationIds)")
            print("   Vehicle Types: \(vehicleTypeIds.count) -> \(vehicleTypeIds)")
            print("   Makes: \(makeIds.count) -> \(makeIds)")
            print("   Models: \(modelIds.count) -> \(modelIds)")
            print("   Colors: \(colorIds.count) -> \(colorIds)")
            print("   Model Years: \(modelYearIds.count) -> \(modelYearIds)")
            print("   Fuel Types: \(fuelTypeIds.count) -> \(fuelTypeIds)")
            print("   Axle Counts: \(filters.axleCounts.count) -> \(filters.axleCounts.sorted())")
        } else {
            print("   License Types: \(licenseTypeIds.count) -> \(licenseTypeIds)")
            print("   Age Groups: \(ageGroupIds.count) -> \(ageGroupIds)")
            print("   Genders: \(genderIds.count) -> \(genderIds)")
            print("   Experience Levels: \(experienceLevelIds.count) -> \(experienceLevelIds)")
        }

        return OptimizedFilterIds(
            yearIds: yearIds,
            regionIds: regionIds,
            mrcIds: mrcIds,
            municipalityIds: municipalityIds,
            classificationIds: classificationIds,
            vehicleTypeIds: vehicleTypeIds,
            makeIds: makeIds,
            modelIds: modelIds,
            colorIds: colorIds,
            modelYearIds: modelYearIds,
            fuelTypeIds: fuelTypeIds,
            axleCounts: Array(filters.axleCounts).sorted(),
            licenseTypeIds: licenseTypeIds,
            ageGroupIds: ageGroupIds,
            genderIds: genderIds,
            experienceLevelIds: experienceLevelIds
        )
    }

    /// Optimized vehicle query using integer columns
    private func queryVehicleDataWithIntegers(filters: FilterConfiguration, filterIds: OptimizedFilterIds) async throws -> FilteredDataSeries {
        let startTime = Date()

        // Capture MainActor-isolated properties and filter flags before entering the closure
        let allowPre2017FuelType = await MainActor.run { AppSettings.shared.regularizePre2017FuelType }
        let limitToCuratedYears = filters.limitToCuratedYears

        return try await withCheckedThrowingContinuation { continuation in
            databaseManager?.dbQueue.async {
                guard let db = self.databaseManager?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }

                // Build optimized query using integer columns
                var whereClause = "WHERE 1=1"
                var bindValues: [(Int32, Any)] = []
                var bindIndex: Int32 = 1

                // Year filter using year_id
                if !filterIds.yearIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: filterIds.yearIds.count).joined(separator: ",")
                    whereClause += " AND year_id IN (\(placeholders))"
                    for id in filterIds.yearIds {
                        bindValues.append((bindIndex, id))
                        bindIndex += 1
                    }
                }

                // Region filter using admin_region_id
                if !filterIds.regionIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: filterIds.regionIds.count).joined(separator: ",")
                    whereClause += " AND admin_region_id IN (\(placeholders))"
                    for id in filterIds.regionIds {
                        bindValues.append((bindIndex, id))
                        bindIndex += 1
                    }
                }

                // Classification filter using vehicle_class_id
                if !filterIds.classificationIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: filterIds.classificationIds.count).joined(separator: ",")
                    whereClause += " AND vehicle_class_id IN (\(placeholders))"
                    for id in filterIds.classificationIds {
                        bindValues.append((bindIndex, id))
                        bindIndex += 1
                    }
                }

                // Vehicle Type filter using vehicle_type_id
                // Special handling when regularization is enabled AND NOT limiting to curated years:
                // - Without regularization OR limiting to curated years: Filter by vehicle_type_id (excludes NULL)
                // - With regularization AND uncurated years: Include both vehicle_type_id matches AND NULL vehicle_type_id that have regularization mappings
                if !filterIds.vehicleTypeIds.isEmpty {
                    let vtPlaceholders = Array(repeating: "?", count: filterIds.vehicleTypeIds.count).joined(separator: ",")

                    if self.regularizationEnabled && !limitToCuratedYears {
                        // With regularization (uncurated years only): Include records that either:
                        // 1. Have matching vehicle_type_id (curated records), OR
                        // 2. Have NULL vehicle_type_id AND exist in regularization table for this vehicle type (uncurated records)
                        //    CRITICAL: Only match records from uncurated years (2023-2024)
                        whereClause += " AND ("
                        whereClause += "vehicle_type_id IN (\(vtPlaceholders))"
                        whereClause += " OR (vehicle_type_id IS NULL "
                        whereClause += "AND v.year_id IN (SELECT id FROM year_enum WHERE year IN (2023, 2024)) "
                        whereClause += "AND EXISTS ("
                        whereClause += "SELECT 1 FROM make_model_regularization r "
                        whereClause += "WHERE r.uncurated_make_id = v.make_id "
                        whereClause += "AND r.uncurated_model_id = v.model_id "
                        whereClause += "AND r.vehicle_type_id IN (\(vtPlaceholders))"
                        whereClause += "))"
                        whereClause += ")"

                        // Bind vehicle type IDs (first occurrence)
                        for id in filterIds.vehicleTypeIds {
                            bindValues.append((bindIndex, id))
                            bindIndex += 1
                        }
                        // Bind vehicle type IDs again (for EXISTS subquery)
                        for id in filterIds.vehicleTypeIds {
                            bindValues.append((bindIndex, id))
                            bindIndex += 1
                        }

                        print("🔄 Vehicle Type filter with regularization: Using EXISTS subquery to match regularization mappings")
                    } else {
                        // Without regularization OR limiting to curated years: Standard vehicle_type_id filter
                        whereClause += " AND vehicle_type_id IN (\(vtPlaceholders))"
                        for id in filterIds.vehicleTypeIds {
                            bindValues.append((bindIndex, id))
                            bindIndex += 1
                        }
                    }
                }

                // Make filter using make_id
                if !filterIds.makeIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: filterIds.makeIds.count).joined(separator: ",")
                    whereClause += " AND make_id IN (\(placeholders))"
                    for id in filterIds.makeIds {
                        bindValues.append((bindIndex, id))
                        bindIndex += 1
                    }
                }

                // MRC filter using mrc_id
                if !filterIds.mrcIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: filterIds.mrcIds.count).joined(separator: ",")
                    whereClause += " AND mrc_id IN (\(placeholders))"
                    for id in filterIds.mrcIds {
                        bindValues.append((bindIndex, id))
                        bindIndex += 1
                    }
                }

                // Municipality filter using municipality_id
                if !filterIds.municipalityIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: filterIds.municipalityIds.count).joined(separator: ",")
                    whereClause += " AND municipality_id IN (\(placeholders))"
                    for id in filterIds.municipalityIds {
                        bindValues.append((bindIndex, id))
                        bindIndex += 1
                    }
                }

                // Model filter using model_id
                if !filterIds.modelIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: filterIds.modelIds.count).joined(separator: ",")
                    whereClause += " AND model_id IN (\(placeholders))"
                    for id in filterIds.modelIds {
                        bindValues.append((bindIndex, id))
                        bindIndex += 1
                    }
                }

                // Color filter using original_color_id
                if !filterIds.colorIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: filterIds.colorIds.count).joined(separator: ",")
                    whereClause += " AND original_color_id IN (\(placeholders))"
                    for id in filterIds.colorIds {
                        bindValues.append((bindIndex, id))
                        bindIndex += 1
                    }
                }

                // Model year filter using model_year_id
                if !filterIds.modelYearIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: filterIds.modelYearIds.count).joined(separator: ",")
                    whereClause += " AND model_year_id IN (\(placeholders))"
                    for id in filterIds.modelYearIds {
                        bindValues.append((bindIndex, id))
                        bindIndex += 1
                    }
                }

                // Fuel type filter using fuel_type_id
                // Special handling when regularization is enabled AND NOT limiting to curated years:
                // - Without regularization OR limiting to curated years: Filter by fuel_type_id (excludes NULL)
                // - With regularization AND uncurated years: Include both fuel_type_id matches AND NULL fuel_type_id that have regularization mappings
                //   IMPORTANT: Fuel type mappings are TRIPLET-BASED (Make/Model/ModelYear → FuelType)
                //   Unlike vehicle type (wildcard mapping), fuel types require year-specific matching
                if !filterIds.fuelTypeIds.isEmpty {
                    let ftPlaceholders = Array(repeating: "?", count: filterIds.fuelTypeIds.count).joined(separator: ",")

                    if self.regularizationEnabled && !limitToCuratedYears {
                        // Check if pre-2017 regularization is enabled
                        let allowPre2017 = allowPre2017FuelType

                        // With regularization (uncurated years only): Include records that either:
                        // 1. Have matching fuel_type_id (curated records), OR
                        // 2. Have NULL fuel_type_id AND exist in regularization table with matching triplet (uncurated records)
                        //    Must match Make ID, Model ID, AND Model Year ID (triplet-based filtering)
                        whereClause += " AND ("
                        whereClause += "fuel_type_id IN (\(ftPlaceholders))"
                        whereClause += " OR (fuel_type_id IS NULL AND EXISTS ("
                        whereClause += "SELECT 1 FROM make_model_regularization r "
                        whereClause += "WHERE r.uncurated_make_id = v.make_id "
                        whereClause += "AND r.uncurated_model_id = v.model_id "
                        whereClause += "AND r.model_year_id = v.model_year_id "  // CRITICAL: Year-specific match

                        // Add year constraint if pre-2017 regularization is disabled
                        if !allowPre2017 {
                            whereClause += "AND v.year_id IN (SELECT id FROM year_enum WHERE year >= 2017) "
                        }

                        whereClause += "AND r.fuel_type_id IN (\(ftPlaceholders))"
                        whereClause += "))"
                        whereClause += ")"

                        // Bind fuel type IDs (first occurrence)
                        for id in filterIds.fuelTypeIds {
                            bindValues.append((bindIndex, id))
                            bindIndex += 1
                        }
                        // Bind fuel type IDs again (for EXISTS subquery)
                        for id in filterIds.fuelTypeIds {
                            bindValues.append((bindIndex, id))
                            bindIndex += 1
                        }

                        let pre2017Status = allowPre2017 ? "including pre-2017" : "2017+ only"
                        print("🔄 Fuel Type filter with regularization: Using EXISTS subquery with triplet matching (Make/Model/ModelYear, \(pre2017Status))")
                    } else {
                        // Without regularization OR limiting to curated years: Standard fuel_type_id filter
                        whereClause += " AND fuel_type_id IN (\(ftPlaceholders))"
                        for id in filterIds.fuelTypeIds {
                            bindValues.append((bindIndex, id))
                            bindIndex += 1
                        }
                    }
                }

                // Axle count filter using max_axles
                if !filterIds.axleCounts.isEmpty {
                    let placeholders = Array(repeating: "?", count: filterIds.axleCounts.count).joined(separator: ",")
                    whereClause += " AND v.max_axles IN (\(placeholders))"
                    for count in filterIds.axleCounts {
                        bindValues.append((bindIndex, count))
                        bindIndex += 1
                    }
                }

                // Build the query based on metric type
                var selectClause: String
                var additionalJoins = ""
                var additionalWhereConditions = ""
                var useMedianCTE = false
                var medianValueExpr = ""
                var useRWIMedianCTE = false
                var rwiCalculationExpr = ""

                // Build SELECT clause based on metric type
                switch filters.metricType {
                case .count:
                    selectClause = "COUNT(*) as value"

                case .sum:
                    if filters.metricField == .vehicleAge {
                        // Special case: sum of computed age using year_id
                        selectClause = "SUM(y.year - my.year) as value"
                        additionalJoins = " LEFT JOIN model_year_enum my ON v.model_year_id = my.id"
                        additionalWhereConditions = " AND v.model_year_id IS NOT NULL"
                    } else if let column = filters.metricField.databaseColumn {
                        // For integer columns like net_mass_int, displacement_int
                        let intColumn = column == "net_mass" ? "net_mass_int" :
                                       column == "displacement" ? "displacement_int" : column
                        selectClause = "SUM(v.\(intColumn)) as value"
                        additionalWhereConditions = " AND v.\(intColumn) IS NOT NULL"
                    } else {
                        selectClause = "COUNT(*) as value"
                    }

                case .average:
                    if filters.metricField == .vehicleAge {
                        selectClause = "AVG(y.year - my.year) as value"
                        additionalJoins = " LEFT JOIN model_year_enum my ON v.model_year_id = my.id"
                        additionalWhereConditions = " AND v.model_year_id IS NOT NULL"
                    } else if let column = filters.metricField.databaseColumn {
                        let intColumn = column == "net_mass" ? "net_mass_int" :
                                       column == "displacement" ? "displacement_int" : column
                        selectClause = "AVG(v.\(intColumn)) as value"
                        additionalWhereConditions = " AND v.\(intColumn) IS NOT NULL"
                    } else {
                        selectClause = "COUNT(*) as value"
                    }

                case .median:
                    // Median requires a CTE with window functions - handle specially
                    // We'll build the full query after the switch and skip the normal path
                    useMedianCTE = true
                    selectClause = ""  // Will be replaced with CTE query

                    // Set up the value expression and joins for median calculation
                    if filters.metricField == .vehicleAge {
                        medianValueExpr = "(y.year - my.year)"
                        additionalJoins = " LEFT JOIN model_year_enum my ON v.model_year_id = my.id"
                        additionalWhereConditions = " AND v.model_year_id IS NOT NULL"
                    } else if let column = filters.metricField.databaseColumn {
                        let intColumn = column == "net_mass" ? "net_mass_int" :
                                       column == "displacement" ? "displacement_int" : column
                        medianValueExpr = "v.\(intColumn)"
                        additionalWhereConditions = " AND v.\(intColumn) IS NOT NULL"
                    } else {
                        // Fallback to count
                        useMedianCTE = false
                        selectClause = "COUNT(*) as value"
                    }

                case .minimum:
                    if filters.metricField == .vehicleAge {
                        selectClause = "MIN(y.year - my.year) as value"
                        additionalJoins = " LEFT JOIN model_year_enum my ON v.model_year_id = my.id"
                        additionalWhereConditions = " AND v.model_year_id IS NOT NULL"
                    } else if let column = filters.metricField.databaseColumn {
                        let intColumn = column == "net_mass" ? "net_mass_int" :
                                       column == "displacement" ? "displacement_int" : column
                        selectClause = "MIN(v.\(intColumn)) as value"
                        additionalWhereConditions = " AND v.\(intColumn) IS NOT NULL"
                    } else {
                        selectClause = "COUNT(*) as value"
                    }

                case .maximum:
                    if filters.metricField == .vehicleAge {
                        selectClause = "MAX(y.year - my.year) as value"
                        additionalJoins = " LEFT JOIN model_year_enum my ON v.model_year_id = my.id"
                        additionalWhereConditions = " AND v.model_year_id IS NOT NULL"
                    } else if let column = filters.metricField.databaseColumn {
                        let intColumn = column == "net_mass" ? "net_mass_int" :
                                       column == "displacement" ? "displacement_int" : column
                        selectClause = "MAX(v.\(intColumn)) as value"
                        additionalWhereConditions = " AND v.\(intColumn) IS NOT NULL"
                    } else {
                        selectClause = "COUNT(*) as value"
                    }

                case .percentage:
                    // For percentage, we calculate count for numerator
                    selectClause = "COUNT(*) as value"

                case .coverage:
                    // For coverage, we can show either percentage or raw NULL count
                    if let coverageField = filters.coverageField {
                        let column = coverageField.databaseColumn
                        if filters.coverageAsPercentage {
                            // Percentage: (COUNT(field) / COUNT(*)) * 100
                            selectClause = "(CAST(COUNT(\(column)) AS REAL) / CAST(COUNT(*) AS REAL) * 100.0) as value"
                        } else {
                            // Raw NULL count: COUNT(*) - COUNT(field)
                            selectClause = "(COUNT(*) - COUNT(\(column))) as value"
                        }
                    } else {
                        // No field selected, fallback to count
                        selectClause = "COUNT(*) as value"
                    }

                case .roadWearIndex:
                    // Road Wear Index: 4th power law based on vehicle mass
                    // Uses actual axle count when available (max_axles), falls back to vehicle type
                    // Axle-based coefficients (Oct 2025):
                    // - 2 axles: 0.1325, 3 axles: 0.0234, 4 axles: 0.0156, 5 axles: 0.0080, 6+ axles: 0.0046
                    let rwiCalculation = """
                        CASE
                            -- Use actual axle data when available (BCA trucks)
                            WHEN v.max_axles = 2 THEN 0.1325 * POWER(v.net_mass_int, 4)
                            WHEN v.max_axles = 3 THEN 0.0234 * POWER(v.net_mass_int, 4)
                            WHEN v.max_axles = 4 THEN 0.0156 * POWER(v.net_mass_int, 4)
                            WHEN v.max_axles = 5 THEN 0.0080 * POWER(v.net_mass_int, 4)
                            WHEN v.max_axles >= 6 THEN 0.0046 * POWER(v.net_mass_int, 4)
                            -- Fallback: vehicle type assumptions when max_axles is NULL
                            WHEN v.vehicle_type_id IN (SELECT id FROM vehicle_type_enum WHERE code IN ('CA', 'VO'))
                            THEN 0.0234 * POWER(v.net_mass_int, 4)
                            WHEN v.vehicle_type_id IN (SELECT id FROM vehicle_type_enum WHERE code = 'AB')
                            THEN 0.1935 * POWER(v.net_mass_int, 4)
                            ELSE 0.125 * POWER(v.net_mass_int, 4)
                        END
                        """
                    if filters.roadWearIndexMode == .average {
                        selectClause = "AVG(\(rwiCalculation)) as value"
                        additionalWhereConditions = " AND v.net_mass_int IS NOT NULL"
                    } else if filters.roadWearIndexMode == .median {
                        // Median RWI requires CTE with window functions
                        useRWIMedianCTE = true
                        rwiCalculationExpr = rwiCalculation
                        selectClause = ""  // Will be replaced with CTE query
                        additionalWhereConditions = " AND v.net_mass_int IS NOT NULL"
                    } else {
                        selectClause = "SUM(\(rwiCalculation)) as value"
                        additionalWhereConditions = " AND v.net_mass_int IS NOT NULL"
                    }
                }

                // Age range filter (requires model_year join for age calculation)
                // This must come AFTER the metric type switch to avoid overwriting joins
                if !filters.ageRanges.isEmpty {
                    // Add model_year join if not already present
                    if !additionalJoins.contains("model_year_enum") {
                        additionalJoins += " LEFT JOIN model_year_enum my ON v.model_year_id = my.id"
                    }

                    var ageConditions: [String] = []
                    for ageRange in filters.ageRanges {
                        if let maxAge = ageRange.maxAge {
                            // Age range with both min and max: (year - model_year) BETWEEN minAge AND maxAge
                            ageConditions.append("(y.year - my.year BETWEEN ? AND ?)")
                            bindValues.append((bindIndex, ageRange.minAge))
                            bindIndex += 1
                            bindValues.append((bindIndex, maxAge))
                            bindIndex += 1
                        } else {
                            // Age range with only min: (year - model_year) >= minAge
                            ageConditions.append("(y.year - my.year >= ?)")
                            bindValues.append((bindIndex, ageRange.minAge))
                            bindIndex += 1
                        }
                    }

                    if !ageConditions.isEmpty {
                        // Append age conditions to existing WHERE conditions
                        if !additionalWhereConditions.contains("model_year_id IS NOT NULL") {
                            additionalWhereConditions += " AND v.model_year_id IS NOT NULL"
                        }
                        additionalWhereConditions += " AND (" + ageConditions.joined(separator: " OR ") + ")"
                    }
                }

                // Build query - use CTE for median or RWI median, simple GROUP BY for others
                let query: String
                if useMedianCTE {
                    // Median requires window functions with CTE
                    query = """
                        WITH ranked_values AS (
                            SELECT y.year,
                                   \(medianValueExpr) as value,
                                   ROW_NUMBER() OVER (PARTITION BY y.year ORDER BY \(medianValueExpr)) as row_num,
                                   COUNT(*) OVER (PARTITION BY y.year) as total_count
                            FROM vehicles v
                            JOIN year_enum y ON v.year_id = y.id
                            \(additionalJoins)
                            \(whereClause)\(additionalWhereConditions)
                        )
                        SELECT year,
                               AVG(value) as value
                        FROM ranked_values
                        WHERE row_num IN ((total_count + 1) / 2, (total_count + 2) / 2)
                        GROUP BY year
                        ORDER BY year
                        """
                } else if useRWIMedianCTE {
                    // RWI Median requires CTE to calculate RWI, then find median
                    query = """
                        WITH rwi_values AS (
                            SELECT y.year,
                                   \(rwiCalculationExpr) as value,
                                   ROW_NUMBER() OVER (PARTITION BY y.year ORDER BY \(rwiCalculationExpr)) as row_num,
                                   COUNT(*) OVER (PARTITION BY y.year) as total_count
                            FROM vehicles v
                            JOIN year_enum y ON v.year_id = y.id
                            \(additionalJoins)
                            \(whereClause)\(additionalWhereConditions)
                        )
                        SELECT year,
                               AVG(value) as value
                        FROM rwi_values
                        WHERE row_num IN ((total_count + 1) / 2, (total_count + 2) / 2)
                        GROUP BY year
                        ORDER BY year
                        """
                } else {
                    query = """
                        SELECT y.year, \(selectClause)
                        FROM vehicles v
                        JOIN year_enum y ON v.year_id = y.id
                        \(additionalJoins)
                        \(whereClause)\(additionalWhereConditions)
                        GROUP BY v.year_id, y.year
                        ORDER BY y.year
                        """
                }

                print("🔍 Optimized query: \(query)")
                print("🔍 Bind values: \(bindValues.map { "(\($0.0), \($0.1))" }.joined(separator: ", "))")

                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }

                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    // Bind parameters
                    for (index, value) in bindValues {
                        if let intValue = value as? Int {
                            sqlite3_bind_int(stmt, index, Int32(intValue))
                        }
                    }

                    var dataPoints: [TimeSeriesPoint] = []

                    while sqlite3_step(stmt) == SQLITE_ROW {
                        let year = Int(sqlite3_column_int(stmt, 0))
                        let value = sqlite3_column_double(stmt, 1)
                        dataPoints.append(TimeSeriesPoint(year: year, value: value, label: nil))
                    }

                    let duration = Date().timeIntervalSince(startTime)
                    print("✅ Optimized vehicle query completed in \(String(format: "%.3f", duration))s - \(dataPoints.count) data points")

                    // If we got empty results, this indicates an ID lookup issue
                    if dataPoints.isEmpty {
                        print("⚠️ Empty results - likely ID lookup problem or incompatible filter combination")
                    }

                    // Apply normalization if enabled (works with all metrics)
                    var transformedPoints = if filters.normalizeToFirstYear {
                        self.databaseManager?.normalizeToFirstYear(points: dataPoints) ?? dataPoints
                    } else {
                        dataPoints
                    }

                    // Apply cumulative sum if enabled
                    if filters.showCumulativeSum {
                        transformedPoints = self.databaseManager?.applyCumulativeSum(points: transformedPoints) ?? transformedPoints
                    }

                    let series = FilteredDataSeries(
                        name: "Vehicle Count by Year (Optimized)",
                        filters: filters,
                        points: transformedPoints
                    )

                    continuation.resume(returning: series)
                } else {
                    let error = String(cString: sqlite3_errmsg(db))
                    continuation.resume(throwing: DatabaseError.queryFailed("Optimized query failed: \(error)"))
                }
            }
        }
    }

    /// High-performance license data query using integer enumerations
    func queryOptimizedLicenseData(filters: FilterConfiguration) async throws -> FilteredDataSeries {
        print("🚀 Starting OPTIMIZED license query with integer enumerations...")

        // First, convert filter strings to integer IDs
        let filterIds = try await convertFiltersToIds(filters: filters, isVehicle: false)

        // Run the optimized query using integer columns
        return try await queryLicenseDataWithIntegers(filters: filters, filterIds: filterIds)
    }

    /// Optimized license query using integer columns
    private func queryLicenseDataWithIntegers(filters: FilterConfiguration, filterIds: OptimizedFilterIds) async throws -> FilteredDataSeries {
        let startTime = Date()

        return try await withCheckedThrowingContinuation { continuation in
            databaseManager?.dbQueue.async {
                guard let db = self.databaseManager?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }

                // Build optimized query using integer columns
                var whereClause = "WHERE 1=1"
                var bindValues: [(Int32, Any)] = []
                var bindIndex: Int32 = 1

                // Year filter using year_id
                if !filterIds.yearIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: filterIds.yearIds.count).joined(separator: ",")
                    whereClause += " AND year_id IN (\(placeholders))"
                    for id in filterIds.yearIds {
                        bindValues.append((bindIndex, id))
                        bindIndex += 1
                    }
                }

                // Region filter using admin_region_id
                if !filterIds.regionIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: filterIds.regionIds.count).joined(separator: ",")
                    whereClause += " AND admin_region_id IN (\(placeholders))"
                    for id in filterIds.regionIds {
                        bindValues.append((bindIndex, id))
                        bindIndex += 1
                    }
                }

                // MRC filter using mrc_id
                if !filterIds.mrcIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: filterIds.mrcIds.count).joined(separator: ",")
                    whereClause += " AND mrc_id IN (\(placeholders))"
                    for id in filterIds.mrcIds {
                        bindValues.append((bindIndex, id))
                        bindIndex += 1
                    }
                }

                // License type filter using license_type_id
                if !filterIds.licenseTypeIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: filterIds.licenseTypeIds.count).joined(separator: ",")
                    whereClause += " AND license_type_id IN (\(placeholders))"
                    for id in filterIds.licenseTypeIds {
                        bindValues.append((bindIndex, id))
                        bindIndex += 1
                    }
                }

                // Age group filter using age_group_id
                if !filterIds.ageGroupIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: filterIds.ageGroupIds.count).joined(separator: ",")
                    whereClause += " AND age_group_id IN (\(placeholders))"
                    for id in filterIds.ageGroupIds {
                        bindValues.append((bindIndex, id))
                        bindIndex += 1
                    }
                }

                // Gender filter using gender_id
                if !filterIds.genderIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: filterIds.genderIds.count).joined(separator: ",")
                    whereClause += " AND gender_id IN (\(placeholders))"
                    for id in filterIds.genderIds {
                        bindValues.append((bindIndex, id))
                        bindIndex += 1
                    }
                }

                // Experience level filter - check ALL 4 experience columns (one per license class)
                // A person can have different experience levels for different license classes
                if !filterIds.experienceLevelIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: filterIds.experienceLevelIds.count).joined(separator: ",")
                    // Match if ANY of the 4 experience columns contains one of the selected experience levels
                    whereClause += " AND (experience_1234_id IN (\(placeholders)) OR experience_5_id IN (\(placeholders)) OR experience_6abce_id IN (\(placeholders)) OR experience_global_id IN (\(placeholders)))"
                    // Bind the same IDs 4 times (once for each column)
                    for _ in 0..<4 {
                        for id in filterIds.experienceLevelIds {
                            bindValues.append((bindIndex, id))
                            bindIndex += 1
                        }
                    }
                }

                // License class filter using boolean columns (has_driver_license_*, has_learner_permit_*, is_probationary)
                // A person can hold multiple license classes simultaneously, so use OR logic across boolean flags
                if !filters.licenseClasses.isEmpty {
                    var classConditions: [String] = []

                    for licenseClass in filters.licenseClasses {
                        if let column = self.databaseManager?.getDatabaseColumn(for: licenseClass) {
                            classConditions.append("l.\(column) = 1")
                        } else {
                            print("⚠️ Warning: Unmapped license class filter '\(licenseClass)'")
                        }
                    }

                    if !classConditions.isEmpty {
                        whereClause += " AND (\(classConditions.joined(separator: " OR ")))"
                    }
                }

                let query = """
                    SELECT y.year, COUNT(*) as value
                    FROM licenses l
                    JOIN year_enum y ON l.year_id = y.id
                    \(whereClause)
                    GROUP BY l.year_id, y.year
                    ORDER BY y.year
                """

                print("🔍 Optimized license query: \(query)")
                print("🔍 Bind values: \(bindValues.map { "(\($0.0), \($0.1))" }.joined(separator: ", "))")

                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }

                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    // Bind parameters
                    for (index, value) in bindValues {
                        if let intValue = value as? Int {
                            sqlite3_bind_int(stmt, index, Int32(intValue))
                        }
                    }

                    var dataPoints: [TimeSeriesPoint] = []

                    while sqlite3_step(stmt) == SQLITE_ROW {
                        let year = Int(sqlite3_column_int(stmt, 0))
                        let value = sqlite3_column_double(stmt, 1)
                        dataPoints.append(TimeSeriesPoint(year: year, value: value, label: nil))
                    }

                    let duration = Date().timeIntervalSince(startTime)
                    print("✅ Optimized license query completed in \(String(format: "%.3f", duration))s - \(dataPoints.count) data points")

                    // Apply normalization if enabled (works with all metrics)
                    var transformedPoints = if filters.normalizeToFirstYear {
                        self.databaseManager?.normalizeToFirstYear(points: dataPoints) ?? dataPoints
                    } else {
                        dataPoints
                    }

                    // Apply cumulative sum if enabled (applied after normalization)
                    if filters.showCumulativeSum {
                        transformedPoints = self.databaseManager?.applyCumulativeSum(points: transformedPoints) ?? transformedPoints
                    }

                    let series = FilteredDataSeries(
                        name: "License Count by Year (Optimized)",
                        filters: filters,
                        points: transformedPoints
                    )

                    continuation.resume(returning: series)
                } else {
                    let error = String(cString: sqlite3_errmsg(db))
                    continuation.resume(throwing: DatabaseError.queryFailed("Optimized license query failed: \(error)"))
                }
            }
        }
    }

    /// Basic license query that will work with current schema
    private func queryBasicLicenseData(filters: FilterConfiguration) async throws -> FilteredDataSeries {
        return try await withCheckedThrowingContinuation { continuation in
            databaseManager?.dbQueue.async {
                guard let db = self.databaseManager?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }

                // Simple count query by year for licenses
                let query = "SELECT year, COUNT(*) as value FROM licenses WHERE 1=1 GROUP BY year ORDER BY year"

                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }

                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    var dataPoints: [TimeSeriesPoint] = []

                    while sqlite3_step(stmt) == SQLITE_ROW {
                        let year = Int(sqlite3_column_int(stmt, 0))
                        let value = sqlite3_column_double(stmt, 1)
                        dataPoints.append(TimeSeriesPoint(year: year, value: value, label: nil))
                    }

                    let series = FilteredDataSeries(
                        name: "License Count by Year",
                        filters: filters,
                        points: dataPoints
                    )

                    continuation.resume(returning: series)
                } else {
                    let error = String(cString: sqlite3_errmsg(db))
                    continuation.resume(throwing: DatabaseError.queryFailed("Basic license query failed: \(error)"))
                }
            }
        }
    }

    // MARK: - Performance Analysis

    /// Analyzes query performance improvements from enumeration
    func analyzePerformanceImprovement(filters: FilterConfiguration) async throws -> PerformanceComparison {
        print("🔬 Starting performance comparison test...")

        // Test optimized integer-based query
        let optimizedStart = Date()
        let optimizedSeries = try await queryOptimizedVehicleData(filters: filters)
        let optimizedTime = Date().timeIntervalSince(optimizedStart)
        let optimizedCount = optimizedSeries.points.count

        // Test string-based query for comparison
        let stringStart = Date()
        let stringSeries = try await queryStringBasedComparison(filters: filters)
        let stringTime = Date().timeIntervalSince(stringStart)
        let stringCount = stringSeries.points.count

        // Validate that both queries return the same results
        if optimizedCount != stringCount {
            print("⚠️ Warning: Result counts differ - Optimized: \(optimizedCount), String: \(stringCount)")
        }

        let improvementFactor = stringTime / optimizedTime
        print("📊 Performance Results:")
        print("   - String-based query: \(String(format: "%.3f", stringTime))s")
        print("   - Integer-based query: \(String(format: "%.3f", optimizedTime))s")
        print("   - Improvement: \(String(format: "%.1f", improvementFactor))x faster")

        return PerformanceComparison(
            optimizedTime: optimizedTime,
            estimatedStringTime: stringTime,
            improvementFactor: improvementFactor,
            memoryReduction: 0.65 // Estimated 65% memory reduction based on integer vs string storage
        )
    }

    /// String-based query for performance comparison
    private func queryStringBasedComparison(filters: FilterConfiguration) async throws -> FilteredDataSeries {
        print("🔍 Running string-based comparison query...")

        return try await withCheckedThrowingContinuation { continuation in
            databaseManager?.dbQueue.async {
                guard let db = self.databaseManager?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }

                // Build traditional string-based query
                var whereClause = "WHERE 1=1"
                var bindValues: [(Int32, Any)] = []
                var bindIndex: Int32 = 1

                // Year filter using string column
                if !filters.years.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.years.count).joined(separator: ",")
                    whereClause += " AND year IN (\(placeholders))"
                    for year in filters.years {
                        bindValues.append((bindIndex, year))
                        bindIndex += 1
                    }
                }

                // Region filter using string column
                if !filters.regions.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.regions.count).joined(separator: ",")
                    whereClause += " AND admin_region IN (\(placeholders))"
                    for region in filters.regions {
                        bindValues.append((bindIndex, region))
                        bindIndex += 1
                    }
                }

                // Classification filter using string column
                if !filters.vehicleClasses.isEmpty {
                    let placeholders = Array(repeating: "?", count: filters.vehicleClasses.count).joined(separator: ",")
                    whereClause += " AND vehicle_class_id IN (\(placeholders))"
                    for vehicleClass in filters.vehicleClasses {
                        bindValues.append((bindIndex, vehicleClass))
                        bindIndex += 1
                    }
                }

                let query = """
                    SELECT year, COUNT(*) as value
                    FROM vehicles
                    \(whereClause)
                    GROUP BY year
                    ORDER BY year
                """

                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }

                if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                    // Bind parameters
                    for (index, value) in bindValues {
                        if let intValue = value as? Int {
                            sqlite3_bind_int(stmt, index, Int32(intValue))
                        } else if let stringValue = value as? String {
                            sqlite3_bind_text(stmt, index, stringValue, -1, nil)
                        }
                    }

                    var dataPoints: [TimeSeriesPoint] = []

                    while sqlite3_step(stmt) == SQLITE_ROW {
                        let year = Int(sqlite3_column_int(stmt, 0))
                        let value = sqlite3_column_double(stmt, 1)
                        dataPoints.append(TimeSeriesPoint(year: year, value: value, label: nil))
                    }

                    let series = FilteredDataSeries(
                        name: "Vehicle Count by Year (String-based)",
                        filters: filters,
                        points: dataPoints
                    )

                    continuation.resume(returning: series)
                } else {
                    let error = String(cString: sqlite3_errmsg(db))
                    continuation.resume(throwing: DatabaseError.queryFailed("String comparison query failed: \(error)"))
                }
            }
        }
    }

    // MARK: - Debug Helpers

    /// Debug helper to show available regions in enum table
    private func debugPrintAvailableRegions() async {
        guard let db = self.db else { return }

        print("🔍 Available regions in admin_region_enum table:")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = "SELECT id, code, name FROM admin_region_enum ORDER BY code LIMIT 10"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let code = String(cString: sqlite3_column_text(stmt, 1))
                    let name = String(cString: sqlite3_column_text(stmt, 2))
                    print("   ID \(id): code='\(code)', name='\(name)'")
                }
            } else {
                print("   Failed to query admin_region_enum table")
            }
            continuation.resume()
        }
    }
}

/// Performance comparison results
struct PerformanceComparison: Sendable {
    let optimizedTime: TimeInterval
    let estimatedStringTime: TimeInterval
    let improvementFactor: Double
    let memoryReduction: Double

    var description: String {
        return """
        Performance Analysis:
        - Integer-based query: \(String(format: "%.3f", optimizedTime))s
        - String-based query: \(String(format: "%.3f", estimatedStringTime))s
        - Speed improvement: \(String(format: "%.1f", improvementFactor))x faster
        - Memory reduction: \(String(format: "%.0f", memoryReduction * 100))%

        Note: These are actual measured times, not estimates!
        The integer-based query uses indexed integer columns for filtering,
        while the string-based query requires string comparisons.
        """
    }
}
