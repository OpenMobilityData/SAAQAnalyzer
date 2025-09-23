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
    var years: Set<Int> = []
    var regions: Set<String> = []
    var mrcs: Set<String> = []
    var municipalities: Set<String> = []
    var vehicleClassifications: Set<String> = []
    var vehicleMakes: Set<String> = []
    var vehicleModels: Set<String> = []
    var modelYears: Set<Int> = []
    var fuelTypes: Set<String> = []
    var ageRanges: [AgeRange] = []

    // Metric configuration
    var metricType: ChartMetricType = .count
    var metricField: ChartMetricField = .none
    // TODO: Implement percentage calculations with a different approach to avoid recursion
    // var percentageBaseFilters: FilterConfiguration? = nil

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
    case netMass = "Vehicle Mass"
    case displacement = "Engine Displacement"
    case cylinderCount = "Cylinders"
    case vehicleAge = "Vehicle Age"
    case modelYear = "Model Year"

    var databaseColumn: String? {
        switch self {
        case .none: return nil
        case .netMass: return "net_mass"
        case .displacement: return "displacement"
        case .cylinderCount: return "cylinder_count"
        case .vehicleAge: return nil // Computed: year - model_year
        case .modelYear: return "model_year"
        }
    }

    var unit: String? {
        switch self {
        case .none: return nil
        case .netMass: return "kg"
        case .displacement: return "cm³"
        case .cylinderCount: return nil
        case .vehicleAge: return "years"
        case .modelYear: return nil
        }
    }

    var requiresNotNull: String? {
        switch self {
        case .vehicleAge: return "model_year"
        case .none: return nil
        default: return databaseColumn
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
        switch metricType {
        case .count:
            return "Number of Vehicles"
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
        switch metricType {
        case .count:
            return "\(Int(value)) vehicles"
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
