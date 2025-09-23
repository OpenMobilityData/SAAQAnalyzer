import Foundation
import SwiftUI
import Combine

// MARK: - Vehicle Registration Models

/// Represents a vehicle registration record from SAAQ data
struct VehicleRegistration: Codable {
    let year: Int                       // AN
    let vehicleSequence: String         // NOSEQ_VEH
    let classification: String          // CLAS (PAU, CMC, etc.)
    let vehicleType: String            // TYP_VEH_CATEG_USA
    let make: String                   // MARQ_VEH
    let model: String                  // MODEL_VEH
    let modelYear: Int?                // ANNEE_MOD
    let netMass: Double?               // MASSE_NETTE (kg)
    let cylinderCount: Int?            // NB_CYL
    let displacement: Double?          // CYL_VEH (cm³)
    let maxAxles: Int?                 // NB_ESIEU_MAX
    let originalColor: String?         // COUL_ORIG
    let fuelType: String?              // TYP_CARBU (2017+ only)
    let adminRegion: String            // REG_ADM
    let mrc: String                    // MRC
    let geoCode: String               // CG_FIXE
    
    /// Calculate vehicle age for a given year
    func age(in year: Int) -> Int? {
        guard let modelYear = modelYear else { return nil }
        return year - modelYear
    }
}

/// Vehicle classification types
enum VehicleClassification: String, CaseIterable {
    // Personal use
    case pau = "PAU"  // Automobile ou camion léger
    case pmc = "PMC"  // Motocyclette
    case pcy = "PCY"  // Cyclomoteur
    case phm = "PHM"  // Habitation motorisée
    
    // Commercial/institutional
    case cau = "CAU"  // Automobile ou camion léger (commercial)
    case cmc = "CMC"  // Motocyclette (commercial)
    case ccy = "CCY"  // Cyclomoteur (commercial)
    case chm = "CHM"  // Habitation motorisée (commercial)
    case tta = "TTA"  // Taxi
    case tab = "TAB"  // Autobus
    case tas = "TAS"  // Autobus scolaire
    case bca = "BCA"  // Camion ou tracteur routier
    case cvo = "CVO"  // Véhicule-outil
    case cot = "COT"  // Autres
    
    // Restricted use
    case rau = "RAU"  // Automobile ou camion léger (restreint)
    case rmc = "RMC"  // Motocyclette (restreint)
    case rcy = "RCY"  // Cyclomoteur (restreint)
    case rhm = "RHM"  // Habitation motorisée (restreint)
    case rab = "RAB"  // Autobus (restreint)
    case rca = "RCA"  // Camion ou tracteur routier (restreint)
    case rmn = "RMN"  // Motoneige
    case rot = "ROT"  // Autres (restreint)
    
    // Off-road use
    case hau = "HAU"  // Automobile ou camion léger (hors route)
    case hcy = "HCY"  // Cyclomoteur (hors route)
    
    // Additional classifications
    case hmn = "HMN"  // Unknown/Other classification
    
    var description: String {
        switch self {
        case .pau: return "Personal automobile/light truck"
        case .pmc: return "Personal motorcycle"
        case .pcy: return "Personal moped"
        case .phm: return "Personal motorhome"
        case .cau: return "Commercial automobile/light truck"
        case .cmc: return "Commercial motorcycle"
        case .ccy: return "Commercial moped"
        case .chm: return "Commercial motorhome"
        case .tta: return "Taxi"
        case .tab: return "Bus"
        case .tas: return "School bus"
        case .bca: return "Truck/road tractor"
        case .cvo: return "Tool vehicle"
        case .cot: return "Other commercial"
        case .rau: return "Restricted automobile/light truck"
        case .rmc: return "Restricted motorcycle"
        case .rcy: return "Restricted moped"
        case .rhm: return "Restricted motorhome"
        case .rab: return "Restricted bus"
        case .rca: return "Restricted truck"
        case .rmn: return "Snowmobile"
        case .rot: return "Other restricted"
        case .hau: return "Off-road automobile/light truck"
        case .hcy: return "Off-road moped"
        case .hmn: return "Other/Unknown classification"
        }
    }
}

/// Fuel type codes (available from 2017+)
enum FuelType: String, CaseIterable {
    case electric = "L"      // Électricité
    case gasoline = "E"      // Essence
    case diesel = "D"        // Diesel
    case hybrid = "H"        // Hybride
    case hydrogen = "C"      // Hydrogène
    case propane = "P"       // Propane
    case naturalGas = "N"    // Gaz naturel
    case methanol = "M"      // Méthanol
    case ethanol = "T"       // Éthanol
    case hybridPlugin = "W"  // Hybride branchable
    case other = "A"         // Autre
    case nonPowered = "S"    // Non-propulsé
    
    var description: String {
        switch self {
        case .electric: return "Electric"
        case .gasoline: return "Gasoline"
        case .diesel: return "Diesel"
        case .hybrid: return "Hybrid"
        case .hydrogen: return "Hydrogen"
        case .propane: return "Propane"
        case .naturalGas: return "Natural Gas"
        case .methanol: return "Methanol"
        case .ethanol: return "Ethanol"
        case .hybridPlugin: return "Plug-in Hybrid"
        case .other: return "Other"
        case .nonPowered: return "Non-powered"
        }
    }
}

// MARK: - Driver's License Models

/// Represents a driver's license record from SAAQ data
struct DriverLicense: Codable {
    let year: Int                           // AN
    let licenseSequence: String             // NOSEQ_TITUL
    let ageGroup: String                    // AGE_1ER_JUIN
    let gender: String                      // SEXE
    let mrc: String                         // MRC
    let adminRegion: String                 // REG_ADM
    let licenseType: String                 // TYPE_PERMIS
    let hasLearnerPermit123: Bool           // IND_PERMISAPPRENTI_123
    let hasLearnerPermit5: Bool             // IND_PERMISAPPRENTI_5
    let hasLearnerPermit6A6R: Bool          // IND_PERMISAPPRENTI_6A6R
    let hasDriverLicense1234: Bool          // IND_PERMISCONDUIRE_1234
    let hasDriverLicense5: Bool             // IND_PERMISCONDUIRE_5
    let hasDriverLicense6ABCE: Bool         // IND_PERMISCONDUIRE_6ABCE
    let hasDriverLicense6D: Bool            // IND_PERMISCONDUIRE_6D
    let hasDriverLicense8: Bool             // IND_PERMISCONDUIRE_8
    let isProbationary: Bool                // IND_PROBATOIRE
    let experience1234: String              // EXPERIENCE_1234
    let experience5: String                 // EXPERIENCE_5
    let experience6ABCE: String             // EXPERIENCE_6ABCE
    let experienceGlobal: String            // EXPERIENCE_GLOBALE
}

/// Driver's license types
enum LicenseType: String, CaseIterable {
    case learner = "APPRENTI"       // Learner's permit
    case probationary = "PROBATOIRE" // Probationary license
    case regular = "RÉGULIER"       // Regular license

    var description: String {
        switch self {
        case .learner: return "Learner's Permit"
        case .probationary: return "Probationary License"
        case .regular: return "Regular License"
        }
    }
}

/// Age groups for license holders
enum AgeGroup: String, CaseIterable {
    case age16_19 = "16-19"
    case age20_24 = "20-24"
    case age25_34 = "25-34"
    case age35_44 = "35-44"
    case age45_54 = "45-54"
    case age55_64 = "55-64"
    case age65_74 = "65-74"
    case age75Plus = "75+"

    var description: String {
        switch self {
        case .age16_19: return "16-19 years"
        case .age20_24: return "20-24 years"
        case .age25_34: return "25-34 years"
        case .age35_44: return "35-44 years"
        case .age45_54: return "45-54 years"
        case .age55_64: return "55-64 years"
        case .age65_74: return "65-74 years"
        case .age75Plus: return "75+ years"
        }
    }
}

/// Gender classification
enum Gender: String, CaseIterable {
    case female = "F"
    case male = "M"

    var description: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        }
    }
}

/// Driving experience levels
enum ExperienceLevel: String, CaseIterable {
    case absent = "Absente"
    case under2Years = "Moins de 2 ans"
    case years2to5 = "2 à 5 ans"
    case years6to9 = "6 à 9 ans"
    case years10Plus = "10 ans ou plus"

    var description: String {
        switch self {
        case .absent: return "No Experience"
        case .under2Years: return "Less than 2 years"
        case .years2to5: return "2 to 5 years"
        case .years6to9: return "6 to 9 years"
        case .years10Plus: return "10+ years"
        }
    }
}

// MARK: - Data Entity Type and Shared Protocol

/// Type of data entity being analyzed
enum DataEntityType: String, CaseIterable {
    case vehicle = "Vehicle"
    case license = "License"

    var description: String {
        switch self {
        case .vehicle: return "Vehicle Registration"
        case .license: return "Driver's License"
        }
    }

    var pluralDescription: String {
        switch self {
        case .vehicle: return "Vehicle Registrations"
        case .license: return "Driver's Licenses"
        }
    }
}

/// Protocol for shared fields between vehicles and licenses
protocol SAAQDataRecord {
    var year: Int { get }
    var adminRegion: String { get }
    var mrc: String { get }
}

extension VehicleRegistration: SAAQDataRecord {}
extension DriverLicense: SAAQDataRecord {}

// MARK: - Geographic Models

/// Represents a geographic entity (municipality, MRC, region)
struct GeographicEntity: Codable, Hashable {
    let code: String
    let name: String
    let type: GeographicLevel
    let parentCode: String?
    
    enum GeographicLevel: String, Codable {
        case municipality
        case mrc
        case adminRegion
    }
}

/// Administrative regions in Quebec
enum AdministrativeRegion: String, CaseIterable {
    case basStLaurent = "01"
    case saguenayLacStJean = "02"
    case capitaleNationale = "03"
    case mauricie = "04"
    case estrie = "05"
    case montreal = "06"
    case outaouais = "07"
    case abitibiTemiscamingue = "08"
    case coteNord = "09"
    case nordDuQuebec = "10"
    case gaspesieIlesMadeleine = "11"
    case chaudiereAppalaches = "12"
    case laval = "13"
    case lanaudiere = "14"
    case laurentides = "15"
    case monteregie = "16"
    case centreDuQuebec = "17"
    
    var name: String {
        switch self {
        case .basStLaurent: return "Bas-Saint-Laurent"
        case .saguenayLacStJean: return "Saguenay–Lac-Saint-Jean"
        case .capitaleNationale: return "Capitale-Nationale"
        case .mauricie: return "Mauricie"
        case .estrie: return "Estrie"
        case .montreal: return "Montréal"
        case .outaouais: return "Outaouais"
        case .abitibiTemiscamingue: return "Abitibi-Témiscamingue"
        case .coteNord: return "Côte-Nord"
        case .nordDuQuebec: return "Nord-du-Québec"
        case .gaspesieIlesMadeleine: return "Gaspésie–Îles-de-la-Madeleine"
        case .chaudiereAppalaches: return "Chaudière-Appalaches"
        case .laval: return "Laval"
        case .lanaudiere: return "Lanaudière"
        case .laurentides: return "Laurentides"
        case .monteregie: return "Montérégie"
        case .centreDuQuebec: return "Centre-du-Québec"
        }
    }
}

// MARK: - Filter Configuration

/// Configuration for filtering data
struct FilterConfiguration: Equatable {
    // Data type selection
    var dataEntityType: DataEntityType = .vehicle

    // Shared filters (available for both vehicles and licenses)
    var years: Set<Int> = []
    var regions: Set<String> = []
    var mrcs: Set<String> = []
    var municipalities: Set<String> = []

    // Vehicle-specific filters
    var vehicleClassifications: Set<String> = []
    var vehicleMakes: Set<String> = []
    var vehicleModels: Set<String> = []
    var vehicleColors: Set<String> = []
    var modelYears: Set<Int> = []
    var fuelTypes: Set<String> = []
    var ageRanges: [AgeRange] = []

    // License-specific filters
    var licenseTypes: Set<String> = []
    var ageGroups: Set<String> = []
    var genders: Set<String> = []
    var experienceLevels: Set<String> = []
    var licenseClasses: Set<String> = []  // For various license class indicators

    // Metric configuration
    var metricType: ChartMetricType = .count
    var metricField: ChartMetricField = .none
    var percentageBaseFilters: PercentageBaseFilters? = nil

    struct AgeRange: Equatable {
        let minAge: Int
        let maxAge: Int?  // nil means no upper limit

        func contains(age: Int) -> Bool {
            if let max = maxAge {
                return age >= minAge && age <= max
            }
            return age >= minAge
        }
    }
}

// MARK: - Percentage Base Configuration

/// Simplified filter configuration for percentage baseline calculations
/// Avoids recursion by not including metric configuration
struct PercentageBaseFilters: Equatable {
    // Data type selection
    var dataEntityType: DataEntityType = .vehicle

    // Shared filters
    var years: Set<Int> = []
    var regions: Set<String> = []
    var mrcs: Set<String> = []
    var municipalities: Set<String> = []

    // Vehicle-specific filters
    var vehicleClassifications: Set<String> = []
    var vehicleMakes: Set<String> = []
    var vehicleModels: Set<String> = []
    var vehicleColors: Set<String> = []
    var modelYears: Set<Int> = []
    var fuelTypes: Set<String> = []
    var ageRanges: [FilterConfiguration.AgeRange] = []

    // License-specific filters
    var licenseTypes: Set<String> = []
    var ageGroups: Set<String> = []
    var genders: Set<String> = []
    var experienceLevels: Set<String> = []
    var licenseClasses: Set<String> = []

    /// Convert to full FilterConfiguration for database queries
    func toFilterConfiguration() -> FilterConfiguration {
        var config = FilterConfiguration()
        config.dataEntityType = dataEntityType
        config.years = years
        config.regions = regions
        config.mrcs = mrcs
        config.municipalities = municipalities
        config.vehicleClassifications = vehicleClassifications
        config.vehicleMakes = vehicleMakes
        config.vehicleModels = vehicleModels
        config.vehicleColors = vehicleColors
        config.modelYears = modelYears
        config.fuelTypes = fuelTypes
        config.ageRanges = ageRanges
        config.licenseTypes = licenseTypes
        config.ageGroups = ageGroups
        config.genders = genders
        config.experienceLevels = experienceLevels
        config.licenseClasses = licenseClasses
        config.metricType = .count  // Always count for baseline
        return config
    }

    /// Create from existing FilterConfiguration
    static func from(_ config: FilterConfiguration) -> PercentageBaseFilters {
        var base = PercentageBaseFilters()
        base.dataEntityType = config.dataEntityType
        base.years = config.years
        base.regions = config.regions
        base.mrcs = config.mrcs
        base.municipalities = config.municipalities
        base.vehicleClassifications = config.vehicleClassifications
        base.vehicleMakes = config.vehicleMakes
        base.vehicleModels = config.vehicleModels
        base.vehicleColors = config.vehicleColors
        base.modelYears = config.modelYears
        base.fuelTypes = config.fuelTypes
        base.ageRanges = config.ageRanges
        base.licenseTypes = config.licenseTypes
        base.ageGroups = config.ageGroups
        base.genders = config.genders
        base.experienceLevels = config.experienceLevels
        base.licenseClasses = config.licenseClasses
        return base
    }
}

// MARK: - Chart Metrics

/// Types of metrics that can be displayed on the Y-axis
enum ChartMetricType: String, CaseIterable {
    case count = "Count"
    case sum = "Sum"
    case average = "Average"
    case percentage = "Percentage"

    var description: String {
        switch self {
        case .count: return "Record Count"
        case .sum: return "Sum of Values"
        case .average: return "Average Value"
        case .percentage: return "Percentage of Category"
        }
    }

    var shortLabel: String {
        switch self {
        case .count: return "Count"
        case .sum: return "Sum"
        case .average: return "Avg"
        case .percentage: return "%"
        }
    }
}

/// Fields that can be used for sum/average calculations
enum ChartMetricField: String, CaseIterable {
    case none = "None"

    // Vehicle-specific fields
    case netMass = "Vehicle Mass"
    case displacement = "Engine Displacement"
    case cylinderCount = "Cylinders"
    case vehicleAge = "Vehicle Age"
    case modelYear = "Model Year"

    // License-specific fields
    case licenseHolderCount = "License Holder Count"
    case licenseClassCount = "License Class Count"

    var databaseColumn: String? {
        switch self {
        case .none: return nil
        // Vehicle fields
        case .netMass: return "net_mass"
        case .displacement: return "displacement"
        case .cylinderCount: return "cylinder_count"
        case .vehicleAge: return nil // Computed: year - model_year
        case .modelYear: return "model_year"
        // License fields
        case .licenseHolderCount: return nil // Count of records
        case .licenseClassCount: return nil  // Count of license classes held
        }
    }

    var unit: String? {
        switch self {
        case .none: return nil
        // Vehicle fields
        case .netMass: return "kg"
        case .displacement: return "cm³"
        case .cylinderCount: return nil
        case .vehicleAge: return "Y"
        case .modelYear: return nil
        // License fields
        case .licenseHolderCount: return nil
        case .licenseClassCount: return nil
        }
    }

    var requiresNotNull: String? {
        switch self {
        case .vehicleAge: return "model_year"
        case .none, .licenseHolderCount, .licenseClassCount: return nil
        default: return databaseColumn
        }
    }

    /// Returns true if this field is applicable to the given data entity type
    func isApplicable(to entityType: DataEntityType) -> Bool {
        switch self {
        case .none:
            return true
        case .netMass, .displacement, .cylinderCount, .vehicleAge, .modelYear:
            return entityType == .vehicle
        case .licenseHolderCount, .licenseClassCount:
            return entityType == .license
        }
    }
}

// MARK: - Time Series Data

/// Represents a time series data point
struct TimeSeriesPoint: Identifiable {
    let id = UUID()
    let year: Int
    let value: Double
    let label: String?
}

/// Filtered data series for charting
class FilteredDataSeries: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String
    let filters: FilterConfiguration
    @Published var points: [TimeSeriesPoint] = []
    @Published var color: Color = .blue
    @Published var isVisible: Bool = true

    // Metric configuration
    var metricType: ChartMetricType {
        filters.metricType
    }
    var metricField: ChartMetricField {
        filters.metricField
    }

    init(name: String, filters: FilterConfiguration, points: [TimeSeriesPoint] = []) {
        self.name = name
        self.filters = filters
        self.points = points
    }

    /// Get formatted Y-axis label for this series
    var yAxisLabel: String {
        let entityType = filters.dataEntityType
        switch metricType {
        case .count:
            switch entityType {
            case .vehicle:
                return "Number of Vehicles"
            case .license:
                return "Number of License Holders"
            }
        case .sum:
            if let unit = metricField.unit {
                return "Total \(metricField.rawValue) (\(unit))"
            } else {
                return "Total \(metricField.rawValue)"
            }
        case .average:
            if let unit = metricField.unit {
                return "Average \(metricField.rawValue) (\(unit))"
            } else {
                return "Average \(metricField.rawValue)"
            }
        case .percentage:
            return "Percentage (%)"
        }
    }

    /// Format a value for display (tooltips, labels, etc.)
    func formatValue(_ value: Double) -> String {
        let entityType = filters.dataEntityType
        switch metricType {
        case .count:
            switch entityType {
            case .vehicle:
                return "\(Int(value)) vehicles"
            case .license:
                return "\(Int(value)) license holders"
            }
        case .sum:
            if metricField == .netMass {
                // Convert kg to tonnes for large values
                if value > 10000 {
                    return String(format: "%.1f tonnes", value / 1000)
                } else {
                    return String(format: "%.0f kg", value)
                }
            } else {
                return String(format: "%.0f", value)
            }
        case .average:
            if metricField == .vehicleAge || metricField == .displacement {
                return String(format: "%.1f", value)
            } else {
                return String(format: "%.0f", value)
            }
        case .percentage:
            return String(format: "%.1f%%", value)
        }
    }
}

// MARK: - Import Schemas

/// Schema configuration for different years of data
struct DataSchema {
    let year: Int
    let hasFieldCount: Int
    let hasFuelType: Bool
    
    static func schema(for year: Int) -> DataSchema {
        if year >= 2017 {
            return DataSchema(year: year, hasFieldCount: 16, hasFuelType: true)
        } else {
            return DataSchema(year: year, hasFieldCount: 15, hasFuelType: false)
        }
    }
}

// MARK: - Export Models

/// Configuration for exporting data
struct ExportConfiguration {
    enum Format {
        case csv
        case png
        case pdf
        case geojson
    }
    
    let format: Format
    let includeMetadata: Bool
    let dpi: Int  // For image exports
}

// MARK: - Analysis Results

/// Results from custom analysis calculations
protocol AnalysisResult {
    var name: String { get }
    var description: String { get }
    var timeSeries: [TimeSeriesPoint] { get }
}

/// Standard analysis result implementation
struct StandardAnalysisResult: AnalysisResult {
    let name: String
    let description: String
    let timeSeries: [TimeSeriesPoint]
}

// MARK: - Color Extensions for Charts

extension Color {
    /// Predefined colors for data series
    static let seriesColors: [Color] = [
        .blue, .green, .orange, .red, .purple,
        .pink, .yellow, .cyan, .indigo, .mint
    ]
    
    /// Get a color for series index
    static func forSeriesIndex(_ index: Int) -> Color {
        seriesColors[index % seriesColors.count]
    }
}
