import Foundation
import SwiftUI
import Combine
import SQLite3

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
    case hab = "HAB"  // Autobus (hors route)
    case hca = "HCA"  // Camion ou tracteur routier (hors route)
    case hmn = "HMN"  // Motoneige (hors route)
    case hvt = "HVT"  // Véhicule tout-terrain (hors route)
    case hvo = "HVO"  // Véhicule-outil (hors route)
    case hot = "HOT"  // Autres (hors route)
    
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
        case .hab: return "Off-road bus"
        case .hca: return "Off-road truck/road tractor"
        case .hmn: return "Off-road snowmobile"
        case .hvt: return "Off-road all-terrain vehicle (ATV)"
        case .hvo: return "Off-road tool vehicle"
        case .hot: return "Other off-road"
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

// MARK: - Categorical Enumeration Models

/// Base protocol for categorical enumeration
protocol CategoricalEnum: Codable, Hashable {
    var id: Int { get }
    var displayValue: String { get }
}

/// Year enumeration (12 values)
struct YearEnum: CategoricalEnum {
    let id: Int  // TINYINT
    let year: Int

    var displayValue: String { String(year) }
}

/// Vehicle classification enumeration (30 values)
struct ClassificationEnum: CategoricalEnum {
    let id: Int  // TINYINT
    let code: String      // PAU, CMC, etc.
    let description: String

    var displayValue: String { code }
}

/// Vehicle make enumeration (418 values)
struct MakeEnum: CategoricalEnum {
    let id: Int  // SMALLINT
    let name: String

    var displayValue: String { name }
}

/// Vehicle model enumeration (9,923 values)
struct ModelEnum: CategoricalEnum {
    let id: Int  // SMALLINT
    let name: String
    let makeId: Int

    var displayValue: String { name }
}

/// Model year enumeration (120 values)
struct ModelYearEnum: CategoricalEnum {
    let id: Int  // SMALLINT
    let year: Int

    var displayValue: String { String(year) }
}

/// Cylinder count enumeration (9 values)
struct CylinderCountEnum: CategoricalEnum {
    let id: Int  // TINYINT
    let count: Int

    var displayValue: String { String(count) }
}

/// Axle count enumeration (6 values)
struct AxleCountEnum: CategoricalEnum {
    let id: Int  // TINYINT
    let count: Int

    var displayValue: String { String(count) }
}

/// Vehicle color enumeration (21 values)
struct ColorEnum: CategoricalEnum {
    let id: Int  // TINYINT
    let name: String

    var displayValue: String { name }
}

/// Fuel type enumeration (13 values)
struct FuelTypeEnum: CategoricalEnum {
    let id: Int  // TINYINT
    let code: String      // E, D, L, H, etc.
    let description: String

    var displayValue: String { description }
}

/// Administrative region enumeration (18/35 values)
struct AdminRegionEnum: CategoricalEnum {
    let id: Int  // TINYINT
    let code: String
    let name: String

    var displayValue: String { name }
}

/// MRC enumeration (106 values)
struct MRCEnum: CategoricalEnum {
    let id: Int  // SMALLINT
    let code: String
    let name: String

    var displayValue: String { name }
}

/// Municipality enumeration (129 values)
struct MunicipalityEnum: CategoricalEnum {
    let id: Int  // SMALLINT
    let code: String
    let name: String

    var displayValue: String { name }
}

/// Age group enumeration (8 values)
struct AgeGroupEnum: CategoricalEnum {
    let id: Int  // TINYINT
    let range: String     // "16-19", "20-24", etc.

    var displayValue: String { range }
}

/// Gender enumeration (2 values)
struct GenderEnum: CategoricalEnum {
    let id: Int  // TINYINT
    let code: String      // M, F
    let description: String

    var displayValue: String { description }
}

/// License type enumeration (3 values)
struct LicenseTypeEnum: CategoricalEnum {
    let id: Int  // TINYINT
    let typeName: String
    let description: String

    var displayValue: String { description }
}

/// Optimized vehicle registration with enumerated categorical data
struct OptimizedVehicleRegistration: Codable {
    // Core identifiers
    let yearId: Int                    // TINYINT → year enum
    let vehicleSequence: String        // Keep as-is for uniqueness constraint

    // Categorical enums (significant storage reduction)
    let classificationId: Int          // TINYINT → 30 classifications
    let makeId: Int                   // SMALLINT → 418 makes
    let modelId: Int                  // SMALLINT → 9,923 models
    let modelYearId: Int?             // SMALLINT → 120 model years
    let cylinderCountId: Int?         // TINYINT → 9 cylinder counts
    let axleCountId: Int?             // TINYINT → 6 axle counts
    let originalColorId: Int?         // TINYINT → 21 colors
    let fuelTypeId: Int?              // TINYINT → 13 fuel types
    let adminRegionId: Int            // TINYINT → 18/35 regions
    let mrcId: Int                    // SMALLINT → 106 MRCs
    let municipalityId: Int           // SMALLINT → 129 municipalities

    // Optimized numeric data
    let netMass: Int?                 // SMALLINT instead of REAL (kg)
    let displacement: Int?            // SMALLINT instead of REAL (cm³)

    /// Get actual year value
    func getYear(from yearEnum: YearEnum) -> Int {
        return yearEnum.year
    }

    /// Calculate vehicle age for a given year
    func age(in year: Int, modelYear: Int?) -> Int? {
        guard let modelYear = modelYear else { return nil }
        return year - modelYear
    }
}

/// Optimized driver license with enumerated categorical data
struct OptimizedDriverLicense: Codable {
    // Core identifiers
    let yearId: Int                    // TINYINT → year enum
    let licenseSequence: String        // Keep as-is for uniqueness constraint

    // Categorical enums
    let ageGroupId: Int               // TINYINT → 8 age groups
    let genderId: Int                 // TINYINT → 2 genders
    let mrcId: Int                    // SMALLINT → 106 MRCs
    let adminRegionId: Int            // TINYINT → 35 regions
    let licenseTypeId: Int            // TINYINT → license types

    // Boolean flags (remain as-is, very efficient)
    let hasLearnerPermit123: Bool
    let hasLearnerPermit5: Bool
    let hasLearnerPermit6A6R: Bool
    let hasDriverLicense1234: Bool
    let hasDriverLicense5: Bool
    let hasDriverLicense6ABCE: Bool
    let hasDriverLicense6D: Bool
    let hasDriverLicense8: Bool
    let isProbationary: Bool

    // Experience fields (could be enumerated if patterns emerge)
    let experience1234: String
    let experience5: String
    let experience6ABCE: String
    let experienceGlobal: String
}

/// Categorical lookup cache for UI performance
class CategoricalLookupCache: ObservableObject {
    // Cached enumerations for fast UI lookups (all O(1) access)
    private var years: [Int: YearEnum] = [:]
    private var classifications: [Int: ClassificationEnum] = [:]
    private var makes: [Int: MakeEnum] = [:]
    private var models: [Int: ModelEnum] = [:]
    private var modelYears: [Int: ModelYearEnum] = [:]
    internal var cylinderCounts: [Int: CylinderCountEnum] = [:]
    internal var axleCounts: [Int: AxleCountEnum] = [:]
    private var colors: [Int: ColorEnum] = [:]
    private var fuelTypes: [Int: FuelTypeEnum] = [:]
    private var adminRegions: [Int: AdminRegionEnum] = [:]
    private var mrcs: [Int: MRCEnum] = [:]
    private var municipalities: [Int: MunicipalityEnum] = [:]
    private var ageGroups: [Int: AgeGroupEnum] = [:]
    private var genders: [Int: GenderEnum] = [:]

    // Reverse lookups for string → ID conversion (critical for query optimization)
    internal var yearsByValue: [Int: Int] = [:]  // year → id
    private var classificationsByCode: [String: Int] = [:]  // code → id
    private var makesByName: [String: Int] = [:]  // name → id
    private var modelsByName: [String: Int] = [:]  // name → id (note: models may have duplicates across makes)
    private var fuelTypesByCode: [String: Int] = [:]  // code → id
    private var regionsByCode: [String: Int] = [:]  // code → id
    private var mrcsByCode: [String: Int] = [:]  // code → id
    private var municipalitiesByCode: [String: Int] = [:]  // code → id
    private var ageGroupsByRange: [String: Int] = [:]  // range → id
    private var gendersByCode: [String: Int] = [:]  // code → id

    @Published var isLoaded = false
    @Published var loadingProgress: Double = 0.0

    /// Initialize cache from database - critical for UI responsiveness
    func loadCache(from databaseManager: DatabaseManager) async throws {
        print("🔄 Loading categorical lookup cache...")

        await MainActor.run { loadingProgress = 0.0 }

        try await loadYears(from: databaseManager)
        await MainActor.run { loadingProgress = 0.1 }

        try await loadClassifications(from: databaseManager)
        await MainActor.run { loadingProgress = 0.2 }

        try await loadMakes(from: databaseManager)
        await MainActor.run { loadingProgress = 0.3 }

        try await loadModels(from: databaseManager)
        await MainActor.run { loadingProgress = 0.4 }

        try await loadModelYears(from: databaseManager)
        await MainActor.run { loadingProgress = 0.5 }

        try await loadCylinderCounts(from: databaseManager)
        await MainActor.run { loadingProgress = 0.6 }

        try await loadColors(from: databaseManager)
        await MainActor.run { loadingProgress = 0.7 }

        try await loadFuelTypes(from: databaseManager)
        await MainActor.run { loadingProgress = 0.8 }

        try await loadGeographicData(from: databaseManager)
        await MainActor.run { loadingProgress = 0.9 }

        try await loadLicenseData(from: databaseManager)
        await MainActor.run {
            loadingProgress = 1.0
            isLoaded = true
        }

        print("✅ Categorical lookup cache loaded with \(getTotalCacheSize()) entries")
    }

    // MARK: - Cache Loading Methods

    private func loadYears(from databaseManager: DatabaseManager) async throws {
        guard let db = databaseManager.db else { throw DatabaseError.notConnected }

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            let sql = "SELECT id, year FROM year_enum ORDER BY year;"

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let year = Int(sqlite3_column_int(stmt, 1))

                    let yearEnum = YearEnum(id: id, year: year)
                    years[id] = yearEnum
                    yearsByValue[year] = id
                }
                continuation.resume()
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to load years: \(error)"))
            }
        }
    }

    private func loadClassifications(from databaseManager: DatabaseManager) async throws {
        guard let db = databaseManager.db else { throw DatabaseError.notConnected }

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            let sql = "SELECT id, code, description FROM classification_enum ORDER BY code;"

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let code = String(cString: sqlite3_column_text(stmt, 1))
                    let description = String(cString: sqlite3_column_text(stmt, 2))

                    let classificationEnum = ClassificationEnum(id: id, code: code, description: description)
                    classifications[id] = classificationEnum
                    classificationsByCode[code] = id
                }
                continuation.resume()
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to load classifications: \(error)"))
            }
        }
    }

    private func loadMakes(from databaseManager: DatabaseManager) async throws {
        guard let db = databaseManager.db else { throw DatabaseError.notConnected }

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            let sql = "SELECT id, name FROM make_enum ORDER BY name;"

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let name = String(cString: sqlite3_column_text(stmt, 1))

                    let makeEnum = MakeEnum(id: id, name: name)
                    makes[id] = makeEnum
                    makesByName[name] = id
                }
                continuation.resume()
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to load makes: \(error)"))
            }
        }
    }

    private func loadModels(from databaseManager: DatabaseManager) async throws {
        guard let db = databaseManager.db else { throw DatabaseError.notConnected }

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            let sql = "SELECT id, name, make_id FROM model_enum ORDER BY name;"

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let name = String(cString: sqlite3_column_text(stmt, 1))
                    let makeId = Int(sqlite3_column_int(stmt, 2))

                    let modelEnum = ModelEnum(id: id, name: name, makeId: makeId)
                    models[id] = modelEnum
                    // Note: models can have duplicates across makes, so we store by make+model
                    if let make = makes[makeId] {
                        modelsByName["\(make.name)|\(name)"] = id
                    }
                }
                continuation.resume()
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to load models: \(error)"))
            }
        }
    }

    private func loadModelYears(from databaseManager: DatabaseManager) async throws {
        guard let db = databaseManager.db else { throw DatabaseError.notConnected }

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            let sql = "SELECT id, year FROM model_year_enum ORDER BY year;"

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let year = Int(sqlite3_column_int(stmt, 1))

                    let modelYearEnum = ModelYearEnum(id: id, year: year)
                    modelYears[id] = modelYearEnum
                }
                continuation.resume()
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to load model years: \(error)"))
            }
        }
    }

    private func loadCylinderCounts(from databaseManager: DatabaseManager) async throws {
        guard let db = databaseManager.db else { throw DatabaseError.notConnected }

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            let sql = "SELECT id, count FROM cylinder_count_enum ORDER BY count;"

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let count = Int(sqlite3_column_int(stmt, 1))

                    let cylinderEnum = CylinderCountEnum(id: id, count: count)
                    cylinderCounts[id] = cylinderEnum
                }
                continuation.resume()
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to load cylinder counts: \(error)"))
            }
        }
    }

    private func loadColors(from databaseManager: DatabaseManager) async throws {
        guard let db = databaseManager.db else { throw DatabaseError.notConnected }

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            let sql = "SELECT id, name FROM color_enum ORDER BY name;"

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let name = String(cString: sqlite3_column_text(stmt, 1))

                    let colorEnum = ColorEnum(id: id, name: name)
                    colors[id] = colorEnum
                }
                continuation.resume()
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to load colors: \(error)"))
            }
        }
    }

    private func loadFuelTypes(from databaseManager: DatabaseManager) async throws {
        guard let db = databaseManager.db else { throw DatabaseError.notConnected }

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            let sql = "SELECT id, code, description FROM fuel_type_enum ORDER BY code;"

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let code = String(cString: sqlite3_column_text(stmt, 1))
                    let description = String(cString: sqlite3_column_text(stmt, 2))

                    let fuelTypeEnum = FuelTypeEnum(id: id, code: code, description: description)
                    fuelTypes[id] = fuelTypeEnum
                    fuelTypesByCode[code] = id
                }
                continuation.resume()
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to load fuel types: \(error)"))
            }
        }
    }

    private func loadGeographicData(from databaseManager: DatabaseManager) async throws {
        // Load admin regions
        guard let db = databaseManager.db else { throw DatabaseError.notConnected }

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            // Load admin regions
            let regionSQL = "SELECT id, code, name FROM admin_region_enum ORDER BY name;"
            if sqlite3_prepare_v2(db, regionSQL, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let code = String(cString: sqlite3_column_text(stmt, 1))
                    let name = String(cString: sqlite3_column_text(stmt, 2))

                    let regionEnum = AdminRegionEnum(id: id, code: code, name: name)
                    adminRegions[id] = regionEnum
                    regionsByCode[code] = id
                }
            }
            sqlite3_finalize(stmt)
            stmt = nil

            // Load MRCs
            let mrcSQL = "SELECT id, code, name FROM mrc_enum ORDER BY name;"
            if sqlite3_prepare_v2(db, mrcSQL, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let code = String(cString: sqlite3_column_text(stmt, 1))
                    let name = String(cString: sqlite3_column_text(stmt, 2))

                    let mrcEnum = MRCEnum(id: id, code: code, name: name)
                    mrcs[id] = mrcEnum
                    mrcsByCode[code] = id
                }
            }
            sqlite3_finalize(stmt)
            stmt = nil

            // Load municipalities
            let municipalitySQL = "SELECT id, code, name FROM municipality_enum ORDER BY name;"
            if sqlite3_prepare_v2(db, municipalitySQL, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let code = String(cString: sqlite3_column_text(stmt, 1))
                    let name = String(cString: sqlite3_column_text(stmt, 2))

                    let municipalityEnum = MunicipalityEnum(id: id, code: code, name: name)
                    municipalities[id] = municipalityEnum
                    municipalitiesByCode[code] = id
                }
            }

            continuation.resume()
        }
    }

    private func loadLicenseData(from databaseManager: DatabaseManager) async throws {
        guard let db = databaseManager.db else { throw DatabaseError.notConnected }

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            // Load age groups
            let ageSQL = "SELECT id, range_text FROM age_group_enum ORDER BY id;"
            if sqlite3_prepare_v2(db, ageSQL, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let range = String(cString: sqlite3_column_text(stmt, 1))

                    let ageGroupEnum = AgeGroupEnum(id: id, range: range)
                    ageGroups[id] = ageGroupEnum
                    ageGroupsByRange[range] = id
                }
            }
            sqlite3_finalize(stmt)
            stmt = nil

            // Load genders
            let genderSQL = "SELECT id, code, description FROM gender_enum ORDER BY code;"
            if sqlite3_prepare_v2(db, genderSQL, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let code = String(cString: sqlite3_column_text(stmt, 1))
                    let description = String(cString: sqlite3_column_text(stmt, 2))

                    let genderEnum = GenderEnum(id: id, code: code, description: description)
                    genders[id] = genderEnum
                    gendersByCode[code] = id
                }
            }

            continuation.resume()
        }
    }

    // MARK: - Lookup Methods

    /// Get display value for any categorical enum ID
    func getDisplayValue(for id: Int, type: any CategoricalEnum.Type) -> String? {
        switch type {
        case is YearEnum.Type:
            return years[id]?.displayValue
        case is ClassificationEnum.Type:
            return classifications[id]?.displayValue
        case is MakeEnum.Type:
            return makes[id]?.displayValue
        case is ModelEnum.Type:
            return models[id]?.displayValue
        case is FuelTypeEnum.Type:
            return fuelTypes[id]?.displayValue
        case is AdminRegionEnum.Type:
            return adminRegions[id]?.displayValue
        case is MRCEnum.Type:
            return mrcs[id]?.displayValue
        case is MunicipalityEnum.Type:
            return municipalities[id]?.displayValue
        case is AgeGroupEnum.Type:
            return ageGroups[id]?.displayValue
        case is GenderEnum.Type:
            return genders[id]?.displayValue
        default:
            return nil
        }
    }

    /// Get enumeration ID for string value (critical for query performance)
    func getEnumId(for value: String, type: any CategoricalEnum.Type) -> Int? {
        switch type {
        case is ClassificationEnum.Type:
            return classificationsByCode[value]
        case is MakeEnum.Type:
            return makesByName[value]
        case is FuelTypeEnum.Type:
            return fuelTypesByCode[value]
        case is AdminRegionEnum.Type:
            return regionsByCode[value]
        case is MRCEnum.Type:
            return mrcsByCode[value]
        case is MunicipalityEnum.Type:
            return municipalitiesByCode[value]
        case is AgeGroupEnum.Type:
            return ageGroupsByRange[value]
        case is GenderEnum.Type:
            return gendersByCode[value]
        default:
            return nil
        }
    }

    /// Get year enum ID (special case for frequently used lookups)
    func getYearId(for year: Int) -> Int? {
        return yearsByValue[year]
    }

    /// Get model ID for make+model combination
    func getModelId(for model: String, make: String) -> Int? {
        return modelsByName["\(make)|\(model)"]
    }

    // MARK: - Cache Statistics

    func getTotalCacheSize() -> Int {
        return years.count + classifications.count + makes.count + models.count +
               modelYears.count + cylinderCounts.count + colors.count + fuelTypes.count +
               adminRegions.count + mrcs.count + municipalities.count + ageGroups.count + genders.count
    }

    func getCacheStatistics() -> String {
        return """
        Categorical Cache Statistics:
        - Years: \(years.count)
        - Classifications: \(classifications.count)
        - Makes: \(makes.count)
        - Models: \(models.count)
        - Model Years: \(modelYears.count)
        - Fuel Types: \(fuelTypes.count)
        - Regions: \(adminRegions.count)
        - MRCs: \(mrcs.count)
        - Municipalities: \(municipalities.count)
        - Age Groups: \(ageGroups.count)
        - Genders: \(genders.count)
        Total: \(getTotalCacheSize()) cached entries
        """
    }
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
// MARK: - Filter Item with ID and Display Name
struct FilterItem: Equatable, Identifiable {
    let id: Int
    let displayName: String
}

// MARK: - Current Filter Configuration (String-based, will migrate to integer-based)
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
    var licenseClasses: Set<String> = []

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

// MARK: - Future Integer-based Filter Configuration
struct IntegerFilterConfiguration: Equatable {
    // Data type selection
    var dataEntityType: DataEntityType = .vehicle

    // Shared filters (available for both vehicles and licenses)
    var years: Set<Int> = []  // Years can remain as integers
    var regions: Set<Int> = []  // Now uses admin_region_enum IDs
    var mrcs: Set<Int> = []  // Now uses mrc_enum IDs
    var municipalities: Set<Int> = []  // Now uses municipality_enum IDs

    // Vehicle-specific filters
    var vehicleClassifications: Set<Int> = []  // Now uses classification_enum IDs
    var vehicleMakes: Set<Int> = []  // Now uses make_enum IDs
    var vehicleModels: Set<Int> = []  // Now uses model_enum IDs
    var vehicleColors: Set<Int> = []  // Now uses color_enum IDs
    var modelYears: Set<Int> = []  // Model years can remain as integers
    var fuelTypes: Set<Int> = []  // Now uses fuel_type_enum IDs
    var ageRanges: [FilterConfiguration.AgeRange] = []  // Keep as-is for numeric ranges

    // License-specific filters
    var licenseTypes: Set<Int> = []  // Now uses license_type_enum IDs
    var ageGroups: Set<Int> = []  // Now uses age_group_enum IDs
    var genders: Set<Int> = []  // Now uses gender_enum IDs
    var experienceLevels: Set<String> = []  // Keep as strings for now
    var licenseClasses: Set<String> = []  // Keep as strings for now

    // Metric configuration
    var metricType: ChartMetricType = .count
    var metricField: ChartMetricField = .none
    var percentageBaseFilters: IntegerPercentageBaseFilters? = nil
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
    case minimum = "Minimum"
    case maximum = "Maximum"
    case percentage = "Percentage"

    var description: String {
        switch self {
        case .count: return "Record Count"
        case .sum: return "Sum of Values"
        case .average: return "Average Value"
        case .minimum: return "Minimum Value"
        case .maximum: return "Maximum Value"
        case .percentage: return "Percentage in Superset"
        }
    }

    var shortLabel: String {
        switch self {
        case .count: return "Count"
        case .sum: return "Sum"
        case .average: return "Avg"
        case .minimum: return "Min"
        case .maximum: return "Max"
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
        case .minimum:
            if let unit = metricField.unit {
                return "Minimum \(metricField.rawValue) (\(unit))"
            } else {
                return "Minimum \(metricField.rawValue)"
            }
        case .maximum:
            if let unit = metricField.unit {
                return "Maximum \(metricField.rawValue) (\(unit))"
            } else {
                return "Maximum \(metricField.rawValue)"
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
        case .average, .minimum, .maximum:
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

// MARK: - Integer-based Percentage Base Configuration
struct IntegerPercentageBaseFilters: Equatable {
    // Data type selection
    var dataEntityType: DataEntityType = .vehicle

    // Shared filters
    var years: Set<Int> = []
    var regions: Set<Int> = []
    var mrcs: Set<Int> = []
    var municipalities: Set<Int> = []

    // Vehicle-specific filters
    var vehicleClassifications: Set<Int> = []
    var vehicleMakes: Set<Int> = []
    var vehicleModels: Set<Int> = []
    var vehicleColors: Set<Int> = []
    var modelYears: Set<Int> = []
    var fuelTypes: Set<Int> = []
    var ageRanges: [FilterConfiguration.AgeRange] = []

    // License-specific filters
    var licenseTypes: Set<Int> = []
    var ageGroups: Set<Int> = []
    var genders: Set<Int> = []
    var experienceLevels: Set<String> = []
    var licenseClasses: Set<String> = []

    /// Convert to full IntegerFilterConfiguration for database queries
    func toIntegerFilterConfiguration() -> IntegerFilterConfiguration {
        var config = IntegerFilterConfiguration()
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
