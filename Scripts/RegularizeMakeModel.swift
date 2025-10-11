// RegularizeMakeModel.swift
import Foundation
import SQLite3
import FoundationModels

// MARK: - Configuration
enum Config {
    static let SIMILARITY_THRESHOLD_PAU = 0.75
    static let SIMILARITY_THRESHOLD_OTHER = 0.65
    static let MAKE_SIMILARITY_THRESHOLD = 0.85
    static let HIGH_CONFIDENCE_THRESHOLD = 0.90
    static let NUMERIC_DIFFERENCE_THRESHOLD = 0.15
    
    static let PASSENGER_VEHICLE_TYPES: Set<String> = ["PAU", "CAU", "VUS"]
    static let MOTORCYCLE_TYPES: Set<String> = ["MOTO", "CYC", "CYCL", "PMC", "CMC", "RMC"]
    static let SPECIALIZED_TYPES: Set<String> = ["MONE", "AGRI", "CONS", "TRAC", "HMN", "HVO", "HVT", "CVO", "RMN", "HOT", "ROT"]
    
    static let KNOWN_MAKE_VARIANTS: [String: String] = [
        "VOLV0": "VOLVO",
        "HOND": "HONDA",
        "TOYOT": "TOYOTA",
        "MERCE": "MERCEDES-BENZ",
        "CHEVR": "CHEVROLET",
        "VOLKSW": "VOLKSWAGEN",
        "MAZD": "MAZDA"
    ]
}

// MARK: - Data Models
struct MakeModelPair: Hashable {
    let make: String
    let model: String
    let minModelYear: Int?
    let maxModelYear: Int?
    let minRegistrationYear: Int?
    let maxRegistrationYear: Int?

    func hash(into hasher: inout Hasher) {
        hasher.combine(make)
        hasher.combine(model)
    }

    static func == (lhs: MakeModelPair, rhs: MakeModelPair) -> Bool {
        return lhs.make == rhs.make && lhs.model == rhs.model
    }
}

struct CanonicalPair {
    let pair: MakeModelPair
    let vehicleTypes: Set<String>
    
    var isPrimaryPassengerVehicle: Bool {
        !vehicleTypes.isDisjoint(with: Config.PASSENGER_VEHICLE_TYPES)
    }
    
    var isMotorcycle: Bool {
        !vehicleTypes.isDisjoint(with: Config.MOTORCYCLE_TYPES)
    }
    
    var isSpecialized: Bool {
        !vehicleTypes.isDisjoint(with: Config.SPECIALIZED_TYPES)
    }
    
    var primaryCategory: String {
        if isPrimaryPassengerVehicle { return "PAU/CAU" }
        if isMotorcycle { return "MOTORCYCLE" }
        if isSpecialized { return "SPECIALIZED" }
        return "MIXED"
    }
}

struct Candidate {
    let pair: CanonicalPair
    let similarity: Double
}

struct CVSValidationResult {
    let decision: String
    let confidence: Double
    let reasoning: String
}

struct TemporalValidationResult {
    let decision: String
    let confidence: Double
    let reasoning: String
}

struct AIAnalysisResult {
    let classification: String
    let confidence: Double
    let shouldRegularize: Bool
    let reasoning: String
}

struct RegularizationDecision {
    let nonStdPair: MakeModelPair
    let canonicalPair: CanonicalPair?
    let shouldRegularize: Bool
    let reasoning: String
    let similarity: Double
    let inferredType: String?
    let cvsValidation: CVSValidationResult?
    let temporalValidation: TemporalValidationResult?
    let aiAnalysis: AIAnalysisResult?
}

struct ClassifiedPair {
    let pair: MakeModelPair
    let inferredType: String
    let confidence: Double
}

// MARK: - Database Helper
class DatabaseHelper {
    var db: OpaquePointer?

    init(path: String) throws {
        let result = sqlite3_open(path, &db)
        guard result == SQLITE_OK else {
            throw NSError(domain: "DatabaseError", code: Int(result), 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to open database at \(path)"])
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func query(_ sql: String) throws -> [[String: String]] {
        var statement: OpaquePointer?
        var results: [[String: String]] = []

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "DatabaseError", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to prepare statement: \(errmsg)"])
        }

        defer { sqlite3_finalize(statement) }

        let columnCount = sqlite3_column_count(statement)

        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String] = [:]
            for i in 0..<columnCount {
                let columnName = String(cString: sqlite3_column_name(statement, i))
                if let columnText = sqlite3_column_text(statement, i) {
                    row[columnName] = String(cString: columnText)
                }
            }
            results.append(row)
        }

        return results
    }
}

// MARK: - String Similarity Functions

func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
    let s1Array = Array(s1)
    let s2Array = Array(s2)
    let m = s1Array.count
    let n = s2Array.count

    if m == 0 { return n }
    if n == 0 { return m }
    if s1 == s2 { return 0 }

    var previousRow = Array(0...n)

    for i in 1...m {
        var currentRow = [i]

        for j in 1...n {
            let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
            currentRow.append(min(
                previousRow[j] + 1,
                currentRow[j-1] + 1,
                previousRow[j-1] + cost
            ))
        }

        previousRow = currentRow
    }

    return previousRow[n]
}

func stringSimilarity(_ s1: String, _ s2: String) -> Double {
    let distance = levenshteinDistance(s1.uppercased(), s2.uppercased())
    let maxLength = max(s1.count, s2.count)
    guard maxLength > 0 else { return 1.0 }
    return 1.0 - (Double(distance) / Double(maxLength))
}

func jaroWinklerSimilarity(_ s1: String, _ s2: String) -> Double {
    let s1Upper = s1.uppercased()
    let s2Upper = s2.uppercased()
    
    let s1Array = Array(s1Upper)
    let s2Array = Array(s2Upper)
    
    let m = s1Array.count
    let n = s2Array.count
    
    if m == 0 && n == 0 { return 1.0 }
    if m == 0 || n == 0 { return 0.0 }
    if s1Upper == s2Upper { return 1.0 }
    
    let matchWindow = max(0, (max(m, n) / 2) - 1)
    
    if matchWindow == 0 {
        return s1Upper == s2Upper ? 1.0 : 0.0
    }
    
    var s1Matches = Array(repeating: false, count: m)
    var s2Matches = Array(repeating: false, count: n)
    
    var matches = 0
    
    for i in 0..<m {
        let start = max(0, i - matchWindow)
        let end = min(n - 1, i + matchWindow)
        
        guard start <= end else { continue }
        
        for j in start...end {
            if s2Matches[j] || s1Array[i] != s2Array[j] { continue }
            s1Matches[i] = true
            s2Matches[j] = true
            matches += 1
            break
        }
    }
    
    if matches == 0 { return 0.0 }
    
    var transpositions = 0
    var k = 0
    for i in 0..<m where s1Matches[i] {
        while k < n && !s2Matches[k] { k += 1 }
        if k >= n { break }
        if s1Array[i] != s2Array[k] { transpositions += 1 }
        k += 1
    }
    
    let t = Double(transpositions) / 2.0
    let jaro = (Double(matches) / Double(m) + 
                Double(matches) / Double(n) + 
                (Double(matches) - t) / Double(matches)) / 3.0
    
    let prefixLength = min(4, s1Upper.commonPrefix(with: s2Upper).count)
    let p: Double = 0.1
    
    return jaro + (Double(prefixLength) * p * (1.0 - jaro))
}

func combinedStringSimilarity(_ s1: String, _ s2: String) -> Double {
    let lev = stringSimilarity(s1, s2)
    let jw = jaroWinklerSimilarity(s1, s2)
    return (lev * 0.4) + (jw * 0.6)
}

// MARK: - Hyphenation Awareness
func hyphenationBoost(nonStd: String, canonical: String) -> Double? {
    let model1 = nonStd.replacingOccurrences(of: "-", with: "")
    let model2 = canonical.replacingOccurrences(of: "-", with: "")

    if model1 == model2 && nonStd != canonical {
        return 0.99
    }

    return nil
}

// MARK: - Numeric Difference Detection
func hasSignificantNumericDifference(_ model1: String, _ model2: String) -> Bool {
    let nums1 = model1.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
    let nums2 = model2.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
    
    guard let n1 = Int(nums1), let n2 = Int(nums2), n1 > 0, n2 > 0 else { return false }
    
    let difference = abs(n1 - n2)
    let smaller = min(n1, n2)
    
    let percentDiff = Double(difference) / Double(smaller)
    return percentDiff > Config.NUMERIC_DIFFERENCE_THRESHOLD
}

// MARK: - Pattern Detection
func looksLikeMotorcycleModel(_ model: String) -> Bool {
    let upper = model.uppercased()
    
    let motorcyclePatterns = [
        "CBR", "GSX", "NINJA", "R1250", "R1200", "FZ", "MT-", 
        "YZF", "ZX", "VFR", "HAYABUSA", "SUPER", "STREET"
    ]
    
    for pattern in motorcyclePatterns {
        if upper.contains(pattern) { return true }
    }
    
    if upper.range(of: "^[A-Z]{2,4}[0-9]{3,4}$", options: .regularExpression) != nil {
        return true
    }
    
    return false
}

func isPassengerModelPattern(_ model: String) -> Bool {
    let upper = model.uppercased()
    
    if upper.range(of: "^[A-Z]{3,8}$", options: .regularExpression) != nil {
        return true
    }
    
    if upper.range(of: "^[A-Z]{1,2}-?[0-9]{1,3}[A-Z]{0,2}$", options: .regularExpression) != nil {
        return true
    }
    
    return false
}

func normalizeMake(_ make: String) -> String {
    let upper = make.uppercased()
    return Config.KNOWN_MAKE_VARIANTS[upper] ?? upper
}

// MARK: - Build Dynamic Make Lists from Canonical Data
func buildMakeClassifications(from canonicalPairs: [CanonicalPair]) -> (
    passengerMakes: Set<String>,
    motorcycleMakes: Set<String>,
    specializedMakes: Set<String>
) {
    var passengerMakes: Set<String> = []
    var motorcycleMakes: Set<String> = []
    var specializedMakes: Set<String> = []
    
    for canonical in canonicalPairs {
        let make = canonical.pair.make.uppercased()
        
        if canonical.isPrimaryPassengerVehicle {
            passengerMakes.insert(make)
        }
        
        if canonical.isMotorcycle {
            motorcycleMakes.insert(make)
        }
        
        if canonical.isSpecialized {
            specializedMakes.insert(make)
        }
    }
    
    return (passengerMakes, motorcycleMakes, specializedMakes)
}

// MARK: - Vehicle Type Classification (Data-Driven)
func classifyVehicleType(
    make: String,
    model: String,
    cvsDBPath: String,
    canonicalPairs: [CanonicalPair],
    passengerMakes: Set<String>,
    motorcycleMakes: Set<String>,
    specializedMakes: Set<String>
) -> (type: String, confidence: Double) {
    
    if let cvsData = queryCVS(cvsDBPath: cvsDBPath, make: make, model: model),
       let vehicleType = cvsData["vehicle_type"] as? String {
        
        if Config.PASSENGER_VEHICLE_TYPES.contains(vehicleType) {
            return ("PAU/CAU", 0.95)
        } else if Config.MOTORCYCLE_TYPES.contains(vehicleType) {
            return ("MOTORCYCLE", 0.95)
        } else if Config.SPECIALIZED_TYPES.contains(vehicleType) {
            return ("SPECIALIZED", 0.95)
        }
    }
    
    let makeUpper = make.uppercased()
    
    if passengerMakes.contains(makeUpper) {
        let alsoMakesMoto = motorcycleMakes.contains(makeUpper)
        
        if alsoMakesMoto && looksLikeMotorcycleModel(model) {
            return ("MOTORCYCLE", 0.80)
        }
        
        if isPassengerModelPattern(model) {
            return ("PAU/CAU", 0.85)
        }
        
        return ("PAU/CAU", 0.70)
    }
    
    if motorcycleMakes.contains(makeUpper) && !passengerMakes.contains(makeUpper) {
        return ("MOTORCYCLE", 0.85)
    }
    
    if specializedMakes.contains(makeUpper) && !passengerMakes.contains(makeUpper) {
        return ("SPECIALIZED", 0.85)
    }
    
    if looksLikeMotorcycleModel(model) {
        return ("MOTORCYCLE", 0.70)
    }
    
    if isPassengerModelPattern(model) {
        return ("PAU/CAU", 0.60)
    }
    
    return ("UNKNOWN", 0.30)
}

// MARK: - CVS Validation
func queryCVS(cvsDBPath: String, make: String, model: String) -> [String: Any]? {
    guard let cvsDB = try? DatabaseHelper(path: cvsDBPath) else { return nil }

    var sql = """
    SELECT saaq_make, saaq_model, vehicle_type, myr
    FROM cvs_data
    WHERE saaq_make = '\(make)' AND saaq_model = '\(model)'
    LIMIT 1;
    """

    if let results = try? cvsDB.query(sql), let first = results.first {
        return [
            "make": first["saaq_make"] ?? "",
            "model": first["saaq_model"] ?? "",
            "vehicle_type": first["vehicle_type"] ?? "",
            "myr": first["myr"] ?? ""
        ]
    }

    var letters = ""
    var rest = ""
    var foundDigit = false

    for char in model {
        if char.isLetter && !foundDigit {
            letters.append(char)
        } else {
            foundDigit = true
            rest.append(char)
        }
    }

    if !letters.isEmpty && !rest.isEmpty && rest.first?.isNumber == true {
        let hyphenated = "\(letters)-\(rest)"
        sql = """
        SELECT saaq_make, saaq_model, vehicle_type, myr
        FROM cvs_data
        WHERE saaq_make = '\(make)' AND saaq_model = '\(hyphenated)'
        LIMIT 1;
        """

        if let results = try? cvsDB.query(sql), let first = results.first {
            return [
                "make": first["saaq_make"] ?? "",
                "model": first["saaq_model"] ?? "",
                "vehicle_type": first["vehicle_type"] ?? "",
                "myr": first["myr"] ?? ""
            ]
        }
    }

    return nil
}

func validateWithCVS(nonStdPair: MakeModelPair, canonicalPair: MakeModelPair, canonicalTypes: Set<String>, cvsDBPath: String) -> CVSValidationResult {
    let nonStdData = queryCVS(cvsDBPath: cvsDBPath, make: nonStdPair.make, model: nonStdPair.model)
    let canonicalData = queryCVS(cvsDBPath: cvsDBPath, make: canonicalPair.make, model: canonicalPair.model)

    let nonStdFound = nonStdData != nil
    let canonicalFound = canonicalData != nil

    if nonStdFound && canonicalFound {
        let nonStdType = (nonStdData?["vehicle_type"] as? String) ?? ""
        let canonicalType = (canonicalData?["vehicle_type"] as? String) ?? ""

        if nonStdType == canonicalType {
            return CVSValidationResult(
                decision: "SUPPORT",
                confidence: 0.95,
                reasoning: "Both found in CVS as same type (\(canonicalType))"
            )
        }
        
        let nonStdIsPassenger = Config.PASSENGER_VEHICLE_TYPES.contains(nonStdType)
        let canonicalIsPassenger = Config.PASSENGER_VEHICLE_TYPES.contains(canonicalType)
        
        if nonStdIsPassenger && canonicalIsPassenger {
            return CVSValidationResult(
                decision: "SUPPORT",
                confidence: 0.85,
                reasoning: "Both passenger vehicles in CVS (\(nonStdType), \(canonicalType))"
            )
        }
        
        let nonStdIsMoto = Config.MOTORCYCLE_TYPES.contains(nonStdType)
        let canonicalIsMoto = Config.MOTORCYCLE_TYPES.contains(canonicalType)
        
        if (nonStdIsPassenger && canonicalIsMoto) || (nonStdIsMoto && canonicalIsPassenger) {
            return CVSValidationResult(
                decision: "PREVENT",
                confidence: 0.99,
                reasoning: "Category mismatch: \(nonStdType) vs \(canonicalType) (passenger/motorcycle conflict)"
            )
        }
        
        return CVSValidationResult(
            decision: "PREVENT",
            confidence: 0.85,
            reasoning: "Different types in CVS: \(nonStdType) vs \(canonicalType)"
        )
    } else if nonStdFound && !canonicalFound {
        let nonStdType = (nonStdData?["vehicle_type"] as? String) ?? ""
        
        if canonicalTypes.contains(nonStdType) {
            return CVSValidationResult(
                decision: "NEUTRAL",
                confidence: 0.6,
                reasoning: "Non-std in CVS as \(nonStdType), canonical not in CVS but has same type"
            )
        } else {
            return CVSValidationResult(
                decision: "PREVENT",
                confidence: 0.75,
                reasoning: "Non-std in CVS as \(nonStdType), canonical not in CVS and type mismatch"
            )
        }
    } else if !nonStdFound && canonicalFound {
        let canonicalType = (canonicalData?["vehicle_type"] as? String) ?? ""
        return CVSValidationResult(
            decision: "SUPPORT",
            confidence: 0.65,
            reasoning: "Canonical in CVS as \(canonicalType), non-std not found - possible typo/truncation"
        )
    } else {
        return CVSValidationResult(
            decision: "NEUTRAL",
            confidence: 0.0,
            reasoning: "Neither found in CVS - no CVS evidence available"
        )
    }
}

// MARK: - Temporal Validation
func validateWithTemporal(nonStdPair: MakeModelPair, canonicalPair: MakeModelPair) -> TemporalValidationResult {
    guard let nonStdMin = nonStdPair.minRegistrationYear,
          let nonStdMax = nonStdPair.maxRegistrationYear,
          let canonicalMin = canonicalPair.minRegistrationYear,
          let canonicalMax = canonicalPair.maxRegistrationYear else {
        return TemporalValidationResult(
            decision: "NEUTRAL",
            confidence: 0.0,
            reasoning: "Year range data unavailable"
        )
    }

    let hasOverlap = !(nonStdMax < canonicalMin || canonicalMax < nonStdMin)
    let isOnlyRecent = nonStdMin >= 2023
    let canonicalEndedBeforeRecent = canonicalMax <= 2022

    if hasOverlap {
        return TemporalValidationResult(
            decision: "SUPPORT",
            confidence: 0.90,
            reasoning: "Registration years overlap (\(nonStdMin)-\(nonStdMax) vs \(canonicalMin)-\(canonicalMax))"
        )
    } else if isOnlyRecent && canonicalEndedBeforeRecent {
        return TemporalValidationResult(
            decision: "NEUTRAL",
            confidence: 0.70,
            reasoning: "Non-std only in 2023+ (\(nonStdMin)-\(nonStdMax)), canonical ended 2022 - possible new model or refresh"
        )
    } else if nonStdMin > canonicalMax + 2 {
        return TemporalValidationResult(
            decision: "PREVENT",
            confidence: 0.80,
            reasoning: "Large gap: non-std starts \(nonStdMin)+, canonical ended \(canonicalMax) - likely new model"
        )
    } else {
        return TemporalValidationResult(
            decision: "PREVENT",
            confidence: 0.75,
            reasoning: "No overlap: \(nonStdMin)-\(nonStdMax) vs \(canonicalMin)-\(canonicalMax)"
        )
    }
}

// MARK: - AI Analysis (Simplified for PAU/CAU)
func analyzePassengerVehicle(
    nonStdPair: MakeModelPair,
    canonicalPair: CanonicalPair,
    similarity: Double
) async -> AIAnalysisResult {
    
    let prompt = """
    Passenger car/light truck matching task.
    
    A: \(nonStdPair.make) / \(nonStdPair.model)
    B: \(canonicalPair.pair.make) / \(canonicalPair.pair.model)
    
    Same vehicle with typo/format variant? Answer in this EXACT format:
    
    SHOULD_REGULARIZE: YES or NO
    CONFIDENCE: 0.0 to 1.0
    REASON: one sentence
    
    YES only if: typo (HOND→HONDA) or format (CX5→CX-5)
    NO if: different models (328≠228, X3≠X4, CIVIC≠ACCORD)
    """
    
    do {
        let session = LanguageModelSession(instructions: "Answer in the exact format requested.")
        let response = try await session.respond(to: prompt)
        let content = response.content.uppercased()
        
        let shouldReg = content.contains("SHOULD_REGULARIZE: YES")
        
        var confidence = 0.5
        if let range = content.range(of: "CONFIDENCE: [0-9.]+", options: .regularExpression) {
            let confStr = String(content[range]).replacingOccurrences(of: "CONFIDENCE: ", with: "")
            confidence = Double(confStr) ?? 0.5
        }
        
        return AIAnalysisResult(
            classification: shouldReg ? "spellingVariant" : "newModel",
            confidence: confidence,
            shouldRegularize: shouldReg,
            reasoning: response.content
        )
    } catch {
        return AIAnalysisResult(
            classification: "uncertain",
            confidence: 0.5,
            shouldRegularize: false,
            reasoning: "AI error: \(error.localizedDescription)"
        )
    }
}

// MARK: - Helper Functions
func formatYearRange(_ minYear: Int?, _ maxYear: Int?) -> String {
    guard let min = minYear, let max = maxYear else { return "years unknown" }
    if min == max {
        return "\(min)"
    } else {
        return "\(min)-\(max)"
    }
}

// MARK: - PAU/CAU Processing
func processPassengerVehicles(
    _ pauCauPairs: [ClassifiedPair],
    canonicalPairs: [CanonicalPair],
    cvsDBPath: String
) async -> [RegularizationDecision] {
    
    print("\n=== Processing PAU/CAU Vehicles (High Priority) ===")
    
    let pauCauCanonical = canonicalPairs.filter { $0.isPrimaryPassengerVehicle }
    var pauIndex: [String: [CanonicalPair]] = [:]
    
    for canonical in pauCauCanonical {
        let normMake = normalizeMake(canonical.pair.make)
        pauIndex[normMake, default: []].append(canonical)
    }
    
    print("  Canonical PAU/CAU pairs: \(pauCauCanonical.count)")
    
    var decisions: [RegularizationDecision] = []
    
    for classified in pauCauPairs {
        let nonStdPair = classified.pair
        let nonStdYears = formatYearRange(nonStdPair.minRegistrationYear, nonStdPair.maxRegistrationYear)
        print("\n\(nonStdPair.make) \(nonStdPair.model) [\(nonStdYears)] [PAU/CAU]")
        
        var candidates: [Candidate] = []
        let normalizedMake = normalizeMake(nonStdPair.make)
        
        if let pauMatches = pauIndex[normalizedMake] {
            for canonical in pauMatches {
                let modelSim = combinedStringSimilarity(nonStdPair.model, canonical.pair.model)
                
                var finalSim = modelSim
                if let boost = hyphenationBoost(nonStd: nonStdPair.model, canonical: canonical.pair.model) {
                    finalSim = boost
                }
                
                if finalSim >= Config.SIMILARITY_THRESHOLD_PAU {
                    candidates.append(Candidate(pair: canonical, similarity: finalSim))
                }
            }
        }
        
        candidates.sort { $0.similarity > $1.similarity }
        
        guard let topCandidate = candidates.first else {
            print("  → No PAU/CAU match - NEW MODEL")
            decisions.append(RegularizationDecision(
                nonStdPair: nonStdPair,
                canonicalPair: nil,
                shouldRegularize: false,
                reasoning: "New PAU/CAU model",
                similarity: 0.0,
                inferredType: "PAU/CAU",
                cvsValidation: nil,
                temporalValidation: nil,
                aiAnalysis: nil
            ))
            continue
        }
        
        let canonicalYears = formatYearRange(topCandidate.pair.pair.minRegistrationYear, topCandidate.pair.pair.maxRegistrationYear)
        print("  → Match: \(topCandidate.pair.pair.make) \(topCandidate.pair.pair.model) [\(canonicalYears)] (sim: \(String(format: "%.2f", topCandidate.similarity)))")
        
        let numericDiff = hasSignificantNumericDifference(nonStdPair.model, topCandidate.pair.pair.model)
        
        if numericDiff {
            print("  ⚠️  NUMERIC DIFFERENCE - likely different model")
            decisions.append(RegularizationDecision(
                nonStdPair: nonStdPair,
                canonicalPair: topCandidate.pair,
                shouldRegularize: false,
                reasoning: "Numeric difference in model code - likely different PAU/CAU model",
                similarity: topCandidate.similarity,
                inferredType: "PAU/CAU",
                cvsValidation: nil,
                temporalValidation: nil,
                aiAnalysis: nil
            ))
            print("  ✗ PRESERVE")
            continue
        }
        
        if topCandidate.similarity >= 0.99 {
            decisions.append(RegularizationDecision(
                nonStdPair: nonStdPair,
                canonicalPair: topCandidate.pair,
                shouldRegularize: true,
                reasoning: "Perfect hyphenation variant (PAU/CAU)",
                similarity: topCandidate.similarity,
                inferredType: "PAU/CAU",
                cvsValidation: nil,
                temporalValidation: nil,
                aiAnalysis: nil
            ))
            print("  ✓ REGULARIZE (hyphenation)")
            continue
        }
        
        let cvsValidation = validateWithCVS(
            nonStdPair: nonStdPair,
            canonicalPair: topCandidate.pair.pair,
            canonicalTypes: topCandidate.pair.vehicleTypes,
            cvsDBPath: cvsDBPath
        )
        
        if cvsValidation.confidence >= 0.95 && cvsValidation.decision == "PREVENT" {
            decisions.append(RegularizationDecision(
                nonStdPair: nonStdPair,
                canonicalPair: topCandidate.pair,
                shouldRegularize: false,
                reasoning: "CVS prevention: \(cvsValidation.reasoning)",
                similarity: topCandidate.similarity,
                inferredType: "PAU/CAU",
                cvsValidation: cvsValidation,
                temporalValidation: nil,
                aiAnalysis: nil
            ))
            print("  ✗ PRESERVE (CVS)")
            continue
        }
        
        let temporalValidation = validateWithTemporal(
            nonStdPair: nonStdPair,
            canonicalPair: topCandidate.pair.pair
        )
        
        if temporalValidation.confidence >= 0.85 && temporalValidation.decision == "PREVENT" {
            decisions.append(RegularizationDecision(
                nonStdPair: nonStdPair,
                canonicalPair: topCandidate.pair,
                shouldRegularize: false,
                reasoning: "Temporal prevention: \(temporalValidation.reasoning)",
                similarity: topCandidate.similarity,
                inferredType: "PAU/CAU",
                cvsValidation: cvsValidation,
                temporalValidation: temporalValidation,
                aiAnalysis: nil
            ))
            print("  ✗ PRESERVE (Temporal)")
            continue
        }
        
        if topCandidate.similarity >= Config.HIGH_CONFIDENCE_THRESHOLD &&
           (cvsValidation.decision == "SUPPORT" || cvsValidation.confidence < 0.5) &&
           (temporalValidation.decision == "SUPPORT" || temporalValidation.confidence < 0.5) {
            decisions.append(RegularizationDecision(
                nonStdPair: nonStdPair,
                canonicalPair: topCandidate.pair,
                shouldRegularize: true,
                reasoning: "High confidence PAU/CAU match",
                similarity: topCandidate.similarity,
                inferredType: "PAU/CAU",
                cvsValidation: cvsValidation,
                temporalValidation: temporalValidation,
                aiAnalysis: nil
            ))
            print("  ✓ REGULARIZE (high confidence)")
            continue
        }
        
        print("    → AI analysis...")
        let aiAnalysis = await analyzePassengerVehicle(
            nonStdPair: nonStdPair,
            canonicalPair: topCandidate.pair,
            similarity: topCandidate.similarity
        )
        
        var shouldRegularize = aiAnalysis.shouldRegularize && aiAnalysis.confidence >= 0.85
        var reasoning = aiAnalysis.reasoning
        
        if cvsValidation.confidence >= 0.90 && cvsValidation.decision == "PREVENT" {
            shouldRegularize = false
            reasoning = "CVS override: \(cvsValidation.reasoning)"
        } else if temporalValidation.confidence >= 0.85 && temporalValidation.decision == "PREVENT" {
            shouldRegularize = false
            reasoning = "Temporal override: \(temporalValidation.reasoning)"
        }
        
        decisions.append(RegularizationDecision(
            nonStdPair: nonStdPair,
            canonicalPair: topCandidate.pair,
            shouldRegularize: shouldRegularize,
            reasoning: reasoning,
            similarity: topCandidate.similarity,
            inferredType: "PAU/CAU",
            cvsValidation: cvsValidation,
            temporalValidation: temporalValidation,
            aiAnalysis: aiAnalysis
        ))
        
        print(shouldRegularize ? "  ✓ REGULARIZE" : "  ✗ PRESERVE")
    }
    
    return decisions
}

// MARK: - Other Vehicle Processing
func processOtherVehicles(_ otherPairs: [ClassifiedPair]) -> [RegularizationDecision] {
    
    print("\n=== Processing Other Vehicle Types (Type Classification Only) ===")
    
    var decisions: [RegularizationDecision] = []
    
    for classified in otherPairs {
        decisions.append(RegularizationDecision(
            nonStdPair: classified.pair,
            canonicalPair: nil,
            shouldRegularize: false,
            reasoning: "Type: \(classified.inferredType) (confidence: \(String(format: "%.2f", classified.confidence)))",
            similarity: 0.0,
            inferredType: classified.inferredType,
            cvsValidation: nil,
            temporalValidation: nil,
            aiAnalysis: nil
        ))
    }
    
    print("  Classified \(otherPairs.count) non-PAU/CAU vehicles")
    
    return decisions
}

// MARK: - Main Entry Point
@main
struct RegularizeMakeModelApp {
    static func main() async {
        do {
            try await mainFunction()
        } catch {
            print("ERROR: \(error)")
            Foundation.exit(1)
        }
    }
}

func mainFunction() async throws {
    print("=== AI-Validated Make/Model Regularization ===")
    print("Priority: PAU/CAU passenger vehicles and light trucks\n")

    guard CommandLine.arguments.count == 4 else {
        print("Usage: RegularizeMakeModel <saaq_db_path> <cvs_db_path> <output_report_path>")
        return
    }

    let saaqDBPath = CommandLine.arguments[1]
    let cvsDBPath = CommandLine.arguments[2]
    let reportPath = CommandLine.arguments[3]

    print("Opening databases...")
    let saaqDB = try DatabaseHelper(path: saaqDBPath)

    print("Loading canonical Make/Model pairs...")
    let canonicalSQL = """
    SELECT
        make_enum.name as make,
        model_enum.name as model,
        GROUP_CONCAT(DISTINCT classification_enum.code) as types,
        MIN(year) as min_reg_year,
        MAX(year) as max_reg_year
    FROM vehicles
    JOIN make_enum ON vehicles.make_id = make_enum.id
    JOIN model_enum ON vehicles.model_id = model_enum.id
    JOIN classification_enum ON vehicles.classification_id = classification_enum.id
    WHERE year BETWEEN 2011 AND 2022
    GROUP BY make_enum.name, model_enum.name;
    """

    let canonicalResults = try saaqDB.query(canonicalSQL)
    var canonicalPairs: [CanonicalPair] = []

    for row in canonicalResults {
        guard let make = row["make"], let model = row["model"], let typesStr = row["types"] else { continue }

        let types = Set(typesStr.split(separator: ",").map { String($0) })
        let minRegYear = row["min_reg_year"].flatMap { Int($0) }
        let maxRegYear = row["max_reg_year"].flatMap { Int($0) }

        canonicalPairs.append(CanonicalPair(
            pair: MakeModelPair(make: make, model: model, minModelYear: nil, maxModelYear: nil, 
                               minRegistrationYear: minRegYear, maxRegistrationYear: maxRegYear),
            vehicleTypes: types
        ))
    }

    print("  Found \(canonicalPairs.count) canonical pairs")
    
    print("  Building make classifications from canonical data...")
    let (passengerMakes, motorcycleMakes, specializedMakes) = buildMakeClassifications(from: canonicalPairs)
    
    print("    Passenger makes: \(passengerMakes.count)")
    print("    Motorcycle makes: \(motorcycleMakes.count)")
    print("    Specialized makes: \(specializedMakes.count)")
    
    let pauCauCount = canonicalPairs.filter { $0.isPrimaryPassengerVehicle }.count
    print("  PAU/CAU canonical: \(pauCauCount)")

    print("\nLoading non-standard pairs (2023-2024)...")
    let nonStdSQL = """
    SELECT
        make_enum.name as make,
        model_enum.name as model,
        MIN(year) as min_reg_year,
        MAX(year) as max_reg_year
    FROM vehicles
    JOIN make_enum ON vehicles.make_id = make_enum.id
    JOIN model_enum ON vehicles.model_id = model_enum.id
    WHERE year IN (2023, 2024)
    GROUP BY make_enum.name, model_enum.name;
    """

    let nonStdResults = try saaqDB.query(nonStdSQL)
    let allNonStdPairs = Set(nonStdResults.compactMap { row -> MakeModelPair? in
        guard let make = row["make"], let model = row["model"] else { return nil }
        let minRegYear = row["min_reg_year"].flatMap { Int($0) }
        let maxRegYear = row["max_reg_year"].flatMap { Int($0) }
        return MakeModelPair(make: make, model: model, minModelYear: nil, maxModelYear: nil, 
                           minRegistrationYear: minRegYear, maxRegistrationYear: maxRegYear)
    })

    let canonicalPairSet = Set(canonicalPairs.map { $0.pair })
    let nonStdPairs = allNonStdPairs.subtracting(canonicalPairSet)

    print("  Found \(allNonStdPairs.count) total pairs, \(nonStdPairs.count) are non-standard")

    print("\n=== Classifying Vehicle Types ===")
    var classifiedPairs: [ClassifiedPair] = []

    for nonStdPair in nonStdPairs {
        let (type, confidence) = classifyVehicleType(
            make: nonStdPair.make, 
            model: nonStdPair.model,
            cvsDBPath: cvsDBPath,
            canonicalPairs: canonicalPairs,
            passengerMakes: passengerMakes,
            motorcycleMakes: motorcycleMakes,
            specializedMakes: specializedMakes
        )
        
        classifiedPairs.append(ClassifiedPair(
            pair: nonStdPair,
            inferredType: type,
            confidence: confidence
        ))
    }

    let pauCauPairs = classifiedPairs.filter { $0.inferredType == "PAU/CAU" }
    let otherPairs = classifiedPairs.filter { $0.inferredType != "PAU/CAU" }

    print("  PAU/CAU candidates: \(pauCauPairs.count)")
    print("  Other types: \(otherPairs.count)")
    
    let pauDecisions = await processPassengerVehicles(
        pauCauPairs,
        canonicalPairs: canonicalPairs,
        cvsDBPath: cvsDBPath
    )
    
    let otherDecisions = processOtherVehicles(otherPairs)

    print("\n=== Generating Report ===")

    let pauRegularizations = pauDecisions.filter { $0.shouldRegularize }
    let pauPreservations = pauDecisions.filter { !$0.shouldRegularize }
    let pauNewModels = pauPreservations.filter { $0.canonicalPair == nil }

    var report = """
    # Make/Model Regularization Report (PAU/CAU Priority)

    **Date:** \(Date())
    **Database:** \(saaqDBPath)
    **CVS Database:** \(cvsDBPath)

    ## Summary

    - **Canonical pairs (2011-2022):** \(canonicalPairs.count) (PAU/CAU: \(pauCauCount))
    - **Non-standard pairs (2023-2024):** \(nonStdPairs.count)
    
    ### PAU/CAU Results (Priority)
    - **PAU/CAU candidates identified:** \(pauCauPairs.count)
    - **Regularizations recommended:** \(pauRegularizations.count)
    - **Preserved (existing models):** \(pauPreservations.count - pauNewModels.count)
    - **New PAU/CAU models:** \(pauNewModels.count)
    
    ### Other Vehicle Types
    - **Other vehicles classified:** \(otherPairs.count)
    - **Motorcycles:** \(otherPairs.filter { $0.inferredType == "MOTORCYCLE" }.count)
    - **Specialized:** \(otherPairs.filter { $0.inferredType == "SPECIALIZED" }.count)
    - **Unknown:** \(otherPairs.filter { $0.inferredType == "UNKNOWN" }.count)

    ---

    ## PAU/CAU Regularizations (\(pauRegularizations.count))

    """

    for decision in pauRegularizations {
        report += """
        ### \(decision.nonStdPair.make) \(decision.nonStdPair.model) → \(decision.canonicalPair?.pair.make ?? "N/A") \(decision.canonicalPair?.pair.model ?? "N/A")

        - **Similarity:** \(String(format: "%.2f", decision.similarity))
        - **AI Confidence:** \(decision.aiAnalysis != nil ? String(format: "%.2f", decision.aiAnalysis!.confidence) : "N/A")
        - **CVS:** \(decision.cvsValidation?.decision ?? "N/A")
        - **Temporal:** \(decision.temporalValidation?.decision ?? "N/A")
        - **Reasoning:** \(decision.reasoning)

        """
    }

    report += "---\n\n## PAU/CAU Preservations (\(pauPreservations.count))\n\n"

    for decision in pauPreservations.prefix(50) {
        let matchInfo = decision.canonicalPair != nil ? 
            "\(decision.canonicalPair!.pair.make) \(decision.canonicalPair!.pair.model)" : "No match"
        report += """
        ### \(decision.nonStdPair.make) \(decision.nonStdPair.model) (preserved)

        - **Best candidate:** \(matchInfo)
        - **Similarity:** \(String(format: "%.2f", decision.similarity))
        - **Reasoning:** \(decision.reasoning)

        """
    }

    report += "\n---\n\n## Other Vehicle Type Classifications\n\n"
    
    let typeGroups = Dictionary(grouping: otherDecisions) { $0.inferredType ?? "UNKNOWN" }
    for (type, decisions) in typeGroups.sorted(by: { $0.key < $1.key }) {
        report += "### \(type): \(decisions.count) vehicles\n\n"
    }

    try report.write(toFile: reportPath, atomically: true, encoding: .utf8)
    print("  Report written to: \(reportPath)")

    print("\n✅ Regularization complete!")
    print("   PAU/CAU regularizations: \(pauRegularizations.count)")
    print("   PAU/CAU preservations: \(pauPreservations.count)")
    print("   PAU/CAU new models: \(pauNewModels.count)")
    print("   Other types classified: \(otherPairs.count)")
}