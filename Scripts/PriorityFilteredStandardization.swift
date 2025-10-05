#!/usr/bin/env swift
import Foundation
import SQLite3
import FoundationModels

// MARK: - Configuration
let SIMILARITY_THRESHOLD = 0.4
let PAU_CAU_CODES = ["PAU", "CAU"]  // Priority vehicle types

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
    let vehicleTypes: Set<String>  // Can be PAU, CAU, PMC, etc.
    let isPauCau: Bool  // Convenience flag
}

struct Candidate {
    let pair: CanonicalPair
    let similarity: Double
}

enum Priority: Int, Comparable {
    case canonicalPauCau = 1      // Highest
    case cvsNewPauCau = 2
    case canonicalSpecialty = 3
    case unknown = 4              // Lowest

    static func < (lhs: Priority, rhs: Priority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

struct ClassificationResult {
    let priority: Priority
    let reasoning: String
    let inCanonical: Bool
    let inCVS: Bool
    let canonicalTypes: Set<String>?
}

struct CVSValidationResult {
    let decision: String  // "SUPPORT" or "PREVENT" or "NEUTRAL"
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
    let shouldStandardize: Bool
    let reasoning: String
}

struct StandardizationDecision {
    let nonStdPair: MakeModelPair
    let canonicalPair: CanonicalPair?
    let priority: Priority
    let shouldStandardize: Bool
    let reasoning: String
    let similarity: Double
    let classification: ClassificationResult?
    let cvsValidation: CVSValidationResult?
    let temporalValidation: TemporalValidationResult?
    let aiAnalysis: AIAnalysisResult?
}

// MARK: - Database Helper
class DatabaseHelper {
    var db: OpaquePointer?

    init(path: String) throws {
        let result = sqlite3_open(path, &db)
        guard result == SQLITE_OK else {
            throw NSError(domain: "DatabaseError", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "Failed to open database at \(path)"])
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
            throw NSError(domain: "DatabaseError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare statement: \(errmsg)"])
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

// MARK: - String Similarity (Levenshtein Distance)
func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
    let s1 = Array(s1)
    let s2 = Array(s2)
    let m = s1.count
    let n = s2.count

    var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

    for i in 0...m {
        dp[i][0] = i
    }
    for j in 0...n {
        dp[0][j] = j
    }

    for i in 1...m {
        for j in 1...n {
            if s1[i-1] == s2[j-1] {
                dp[i][j] = dp[i-1][j-1]
            } else {
                dp[i][j] = min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1]) + 1
            }
        }
    }

    return dp[m][n]
}

func stringSimilarity(_ s1: String, _ s2: String) -> Double {
    let distance = levenshteinDistance(s1.uppercased(), s2.uppercased())
    let maxLength = max(s1.count, s2.count)
    guard maxLength > 0 else { return 1.0 }
    return 1.0 - (Double(distance) / Double(maxLength))
}

// MARK: - Hyphenation Awareness
func hyphenationBoost(nonStd: String, canonical: String) -> Double? {
    let model1 = nonStd.replacingOccurrences(of: "-", with: "")
    let model2 = canonical.replacingOccurrences(of: "-", with: "")

    // If models are identical after removing hyphens AND they're different originally → boost
    if model1 == model2 && nonStd != canonical {
        return 0.99
    }

    return nil
}

// MARK: - Classification Logic
func classifyPair(nonStdPair: MakeModelPair, saaqDBPath: String, cvsDBPath: String) -> ClassificationResult {
    // Check canonical SAAQ (2011-2022)
    guard let saaqDB = try? DatabaseHelper(path: saaqDBPath) else {
        return ClassificationResult(
            priority: .unknown,
            reasoning: "SAAQ database unavailable",
            inCanonical: false,
            inCVS: false,
            canonicalTypes: nil
        )
    }

    let canonicalSQL = """
    SELECT DISTINCT classification_enum.code
    FROM vehicles
    JOIN make_enum ON vehicles.make_id = make_enum.id
    JOIN model_enum ON vehicles.model_id = model_enum.id
    JOIN classification_enum ON vehicles.classification_id = classification_enum.id
    WHERE make_enum.name = '\(nonStdPair.make)'
      AND model_enum.name = '\(nonStdPair.model)'
      AND year BETWEEN 2011 AND 2022;
    """

    let canonicalTypes: Set<String>
    if let results = try? saaqDB.query(canonicalSQL), !results.isEmpty {
        canonicalTypes = Set(results.compactMap { $0["code"] })
    } else {
        canonicalTypes = []
    }

    // Check CVS
    guard let cvsDB = try? DatabaseHelper(path: cvsDBPath) else {
        if !canonicalTypes.isEmpty {
            let isPauCau = !canonicalTypes.isDisjoint(with: PAU_CAU_CODES)
            return ClassificationResult(
                priority: isPauCau ? .canonicalPauCau : .canonicalSpecialty,
                reasoning: isPauCau ? "Found in canonical as PAU/CAU" : "Found in canonical as specialty vehicle",
                inCanonical: true,
                inCVS: false,
                canonicalTypes: canonicalTypes
            )
        }

        return ClassificationResult(
            priority: .unknown,
            reasoning: "CVS database unavailable, not in canonical",
            inCanonical: false,
            inCVS: false,
            canonicalTypes: nil
        )
    }

    let cvsSQL = """
    SELECT DISTINCT saaq_make, saaq_model, vehicle_type
    FROM cvs_data
    WHERE saaq_make = '\(nonStdPair.make)' AND saaq_model = '\(nonStdPair.model)'
    LIMIT 1;
    """

    let inCVS = (try? cvsDB.query(cvsSQL).isEmpty == false) ?? false

    // Priority decision
    if !canonicalTypes.isEmpty {
        let isPauCau = !canonicalTypes.isDisjoint(with: PAU_CAU_CODES)
        return ClassificationResult(
            priority: isPauCau ? .canonicalPauCau : .canonicalSpecialty,
            reasoning: isPauCau ? "Found in canonical as PAU/CAU (\(canonicalTypes.joined(separator: ",")))" : "Found in canonical as specialty vehicle (\(canonicalTypes.joined(separator: ",")))",
            inCanonical: true,
            inCVS: inCVS,
            canonicalTypes: canonicalTypes
        )
    } else if inCVS {
        return ClassificationResult(
            priority: .cvsNewPauCau,
            reasoning: "Not in canonical, found in CVS (likely new PAU/CAU model)",
            inCanonical: false,
            inCVS: true,
            canonicalTypes: nil
        )
    } else {
        return ClassificationResult(
            priority: .unknown,
            reasoning: "Not in canonical, not in CVS (unknown origin)",
            inCanonical: false,
            inCVS: false,
            canonicalTypes: nil
        )
    }
}

// MARK: - CVS Validation
func queryCVS(cvsDBPath: String, make: String, model: String) -> [String: Any]? {
    guard let cvsDB = try? DatabaseHelper(path: cvsDBPath) else { return nil }

    // Try direct match first
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

    // Try hyphenation variant
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

func validateWithCVS(nonStdPair: MakeModelPair, canonicalPair: MakeModelPair, cvsDBPath: String) -> CVSValidationResult {
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
                confidence: 0.9,
                reasoning: "Both found in CVS as same vehicle type (\(canonicalType))"
            )
        } else {
            return CVSValidationResult(
                decision: "PREVENT",
                confidence: 0.9,
                reasoning: "Both found in CVS but different types (\(nonStdType) vs \(canonicalType))"
            )
        }
    } else if nonStdFound && !canonicalFound {
        return CVSValidationResult(
            decision: "PREVENT",
            confidence: 0.9,
            reasoning: "Non-standard found in CVS, canonical not found - likely different vehicles"
        )
    } else if !nonStdFound && canonicalFound {
        return CVSValidationResult(
            decision: "SUPPORT",
            confidence: 0.8,
            reasoning: "Canonical found in CVS, non-standard not found - likely truncation/typo"
        )
    } else {
        return CVSValidationResult(
            decision: "NEUTRAL",
            confidence: 0.5,
            reasoning: "Neither found in CVS (specialty vehicle or discontinued)"
        )
    }
}

// MARK: - Temporal Validation
func validateWithTemporal(nonStdPair: MakeModelPair, canonicalPair: MakeModelPair, saaqDBPath: String) -> TemporalValidationResult {
    guard let saaqDB = try? DatabaseHelper(path: saaqDBPath) else {
        return TemporalValidationResult(
            decision: "NEUTRAL",
            confidence: 0.5,
            reasoning: "SAAQ database unavailable"
        )
    }

    let nonStdSQL = """
    SELECT MIN(vehicles.year) as min_year, MAX(vehicles.year) as max_year
    FROM vehicles
    JOIN make_enum ON vehicles.make_id = make_enum.id
    JOIN model_enum ON vehicles.model_id = model_enum.id
    WHERE make_enum.name = '\(nonStdPair.make)' AND model_enum.name = '\(nonStdPair.model)';
    """

    let canonicalSQL = """
    SELECT MIN(vehicles.year) as min_year, MAX(vehicles.year) as max_year
    FROM vehicles
    JOIN make_enum ON vehicles.make_id = make_enum.id
    JOIN model_enum ON vehicles.model_id = model_enum.id
    WHERE make_enum.name = '\(canonicalPair.make)' AND model_enum.name = '\(canonicalPair.model)';
    """

    guard let nonStdResults = try? saaqDB.query(nonStdSQL),
          let canonicalResults = try? saaqDB.query(canonicalSQL),
          let nonStdRow = nonStdResults.first,
          let canonicalRow = canonicalResults.first,
          let nonStdMin = Int(nonStdRow["min_year"] ?? ""),
          let nonStdMax = Int(nonStdRow["max_year"] ?? ""),
          let canonicalMin = Int(canonicalRow["min_year"] ?? ""),
          let canonicalMax = Int(canonicalRow["max_year"] ?? "") else {
        return TemporalValidationResult(
            decision: "NEUTRAL",
            confidence: 0.5,
            reasoning: "Could not determine year ranges"
        )
    }

    let hasOverlap = !(nonStdMax < canonicalMin || canonicalMax < nonStdMin)

    if hasOverlap {
        return TemporalValidationResult(
            decision: "SUPPORT",
            confidence: 0.9,
            reasoning: "Year ranges overlap (\(nonStdMin)-\(nonStdMax) vs \(canonicalMin)-\(canonicalMax))"
        )
    } else if nonStdMin > canonicalMax {
        return TemporalValidationResult(
            decision: "PREVENT",
            confidence: 0.7,
            reasoning: "Non-standard appears after canonical ended (possible new model)"
        )
    } else {
        return TemporalValidationResult(
            decision: "PREVENT",
            confidence: 0.8,
            reasoning: "No year overlap (\(nonStdMin)-\(nonStdMax) vs \(canonicalMin)-\(canonicalMax))"
        )
    }
}

// MARK: - AI Analysis
func analyzeWithAI(nonStdPair: MakeModelPair, canonicalPair: MakeModelPair) async -> AIAnalysisResult {
    let prompt = """
    Vehicle data quality task: Compare two vehicle make/model codes from government database.

    Record A (2023-2024 data): \(nonStdPair.make) / \(nonStdPair.model)
    Record B (2011-2022 data): \(canonicalPair.make) / \(canonicalPair.model)

    Are these the same vehicle with spelling variation (spellingVariant), truncated text (truncationVariant), genuinely different models (newModel), or uncertain?

    Respond with: classification | should_standardize (yes/no) | confidence (0-1) | brief_reason
    """

    do {
        let freshSession = LanguageModelSession(instructions: "You are analyzing vehicle registration database records for data quality.")
        let response = try await freshSession.respond(to: prompt)
        let content = response.content.lowercased()

        var classification = "uncertain"
        var shouldStandardize = false
        var confidence = 0.5
        var reasoning = content

        // Parse response (handle both pipe-delimited and newline formats)
        if content.contains("spellingvariant") || content.contains("spelling variation") {
            classification = "spellingVariant"
        } else if content.contains("truncationvariant") || content.contains("truncation") {
            classification = "truncationVariant"
        } else if content.contains("newmodel") || content.contains("new model") || content.contains("genuinely different") {
            classification = "newModel"
        }

        // Check for yes/no (must not be part of "yes/no" phrase)
        if content.contains("should_standardize: yes") || content.contains("should standardize: yes") || (content.contains("yes") && !content.contains("yes/no")) {
            shouldStandardize = true
        } else if content.contains("should_standardize: no") || content.contains("should standardize: no") || content.contains(": no") {
            shouldStandardize = false
        }

        // Extract confidence - try pipe-delimited format first
        let components = content.components(separatedBy: "|")
        if components.count >= 3 {
            if let conf = Double(components[2].trimmingCharacters(in: .whitespaces)) {
                confidence = conf
            }
        } else {
            // Try colon format: "confidence: 0.9" or "confidence (0-1): 0.9"
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("confidence") {
                    // Extract number after colon or after last space
                    let parts = line.components(separatedBy: ":")
                    if parts.count >= 2 {
                        let numStr = parts[1].trimmingCharacters(in: .whitespaces)
                        if let conf = Double(numStr) {
                            confidence = conf
                            break
                        }
                        // Try extracting just digits and decimal
                        let filtered = numStr.components(separatedBy: .whitespaces).first ?? numStr
                        if let conf = Double(filtered) {
                            confidence = conf
                            break
                        }
                    }
                }
            }
        }

        // Return result based on AI decision
        if shouldStandardize && confidence >= 0.7 {
            return AIAnalysisResult(
                classification: classification,
                confidence: confidence,
                shouldStandardize: true,
                reasoning: reasoning
            )
        } else {
            return AIAnalysisResult(
                classification: classification,
                confidence: confidence,
                shouldStandardize: false,
                reasoning: reasoning
            )
        }
    } catch {
        return AIAnalysisResult(
            classification: "uncertain",
            confidence: 0.5,
            shouldStandardize: false,
            reasoning: "AI analysis error: \(error.localizedDescription)"
        )
    }
}

// MARK: - Main Logic
@MainActor
func main() async throws {
    print("=== Priority-Filtered Make/Model Standardization ===\n")

    guard CommandLine.arguments.count == 4 else {
        print("Usage: PriorityFilteredStandardization <saaq_db_path> <cvs_db_path> <output_report_path>")
        return
    }

    let saaqDBPath = CommandLine.arguments[1]
    let cvsDBPath = CommandLine.arguments[2]
    let reportPath = CommandLine.arguments[3]

    print("Opening databases...")
    let saaqDB = try DatabaseHelper(path: saaqDBPath)

    // Load canonical Make/Model pairs with vehicle types (2011-2022)
    print("Loading canonical Make/Model pairs with vehicle types...")
    let canonicalSQL = """
    SELECT
        make_enum.name as make,
        model_enum.name as model,
        GROUP_CONCAT(DISTINCT classification_enum.code) as types
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
        let isPauCau = !types.isDisjoint(with: PAU_CAU_CODES)

        canonicalPairs.append(CanonicalPair(
            pair: MakeModelPair(make: make, model: model, minModelYear: nil, maxModelYear: nil, minRegistrationYear: nil, maxRegistrationYear: nil),
            vehicleTypes: types,
            isPauCau: isPauCau
        ))
    }

    print("  Found \(canonicalPairs.count) canonical Make/Model pairs")
    print("  PAU/CAU pairs: \(canonicalPairs.filter { $0.isPauCau }.count)")
    print("  Specialty pairs: \(canonicalPairs.filter { !$0.isPauCau }.count)")

    // Load non-standard pairs (2023-2024)
    print("\nLoading non-standard pairs (2023-2024)...")
    let nonStdSQL = """
    SELECT DISTINCT
        make_enum.name as make,
        model_enum.name as model
    FROM vehicles
    JOIN make_enum ON vehicles.make_id = make_enum.id
    JOIN model_enum ON vehicles.model_id = model_enum.id
    WHERE year IN (2023, 2024);
    """

    let nonStdResults = try saaqDB.query(nonStdSQL)
    let allNonStdPairs = Set(nonStdResults.compactMap { row -> MakeModelPair? in
        guard let make = row["make"], let model = row["model"] else { return nil }
        return MakeModelPair(make: make, model: model, minModelYear: nil, maxModelYear: nil, minRegistrationYear: nil, maxRegistrationYear: nil)
    })

    // Filter to only non-canonical pairs
    let canonicalPairSet = Set(canonicalPairs.map { $0.pair })
    let nonStdPairs = allNonStdPairs.subtracting(canonicalPairSet)

    print("  Found \(allNonStdPairs.count) total pairs, \(nonStdPairs.count) are non-standard")

    // Classify all non-standard pairs by priority
    print("\n=== Classifying Non-Standard Pairs by Priority ===")
    var classified: [(pair: MakeModelPair, classification: ClassificationResult)] = []

    for pair in nonStdPairs {
        let classification = classifyPair(nonStdPair: pair, saaqDBPath: saaqDBPath, cvsDBPath: cvsDBPath)
        classified.append((pair: pair, classification: classification))
    }

    // Sort by priority
    classified.sort { $0.classification.priority < $1.classification.priority }

    // Print distribution
    let priorityCounts = Dictionary(grouping: classified, by: { $0.classification.priority })
    for priority in [Priority.canonicalPauCau, .cvsNewPauCau, .canonicalSpecialty, .unknown] {
        let count = priorityCounts[priority]?.count ?? 0
        print("  Priority \(priority.rawValue): \(count) pairs")
    }

    print("\n=== Processing Pairs (Priority Order) ===")
    var decisions: [StandardizationDecision] = []

    // Process in priority order
    for (nonStdPair, classification) in classified {
        print("\n[\(classification.priority.rawValue)] \(nonStdPair.make) \(nonStdPair.model) - \(classification.reasoning)")

        // Filter canonical candidates by vehicle type
        var candidatePool = canonicalPairs

        if classification.priority == .canonicalPauCau || classification.priority == .cvsNewPauCau {
            // Only match against PAU/CAU pairs
            candidatePool = canonicalPairs.filter { $0.isPauCau }
            print("  → Filtering to \(candidatePool.count) PAU/CAU canonical pairs only")
        } else if classification.priority == .canonicalSpecialty, let types = classification.canonicalTypes {
            // Match against same specialty type
            candidatePool = canonicalPairs.filter { canonical in
                !canonical.vehicleTypes.isDisjoint(with: types)
            }
            print("  → Filtering to \(candidatePool.count) canonical pairs with types \(types.joined(separator: ","))")
        }

        // Find best candidate
        var candidates: [Candidate] = []

        for canonical in candidatePool {
            var similarity = stringSimilarity(
                nonStdPair.make + nonStdPair.model,
                canonical.pair.make + canonical.pair.model
            )

            // Hyphenation boost
            if let boost = hyphenationBoost(nonStd: nonStdPair.model, canonical: canonical.pair.model) {
                similarity = boost
            }

            if similarity >= SIMILARITY_THRESHOLD {
                candidates.append(Candidate(pair: canonical, similarity: similarity))
            }
        }

        candidates.sort { $0.similarity > $1.similarity }

        if let topCandidate = candidates.first {
            print("  → Best match: \(topCandidate.pair.pair.make) \(topCandidate.pair.pair.model) (similarity: \(String(format: "%.2f", topCandidate.similarity)))")

            // Validate with CVS, Temporal, AI
            let cvsValidation = validateWithCVS(
                nonStdPair: nonStdPair,
                canonicalPair: topCandidate.pair.pair,
                cvsDBPath: cvsDBPath
            )

            let temporalValidation = validateWithTemporal(
                nonStdPair: nonStdPair,
                canonicalPair: topCandidate.pair.pair,
                saaqDBPath: saaqDBPath
            )

            let aiAnalysis = await analyzeWithAI(
                nonStdPair: nonStdPair,
                canonicalPair: topCandidate.pair.pair
            )

            // Override logic
            var shouldStandardize = aiAnalysis.shouldStandardize
            var reasoning = aiAnalysis.reasoning

            if cvsValidation.confidence >= 0.9 && cvsValidation.decision == "PREVENT" {
                shouldStandardize = false
                reasoning = "CVS override: \(cvsValidation.reasoning)"
            }

            if temporalValidation.confidence >= 0.8 && temporalValidation.decision == "PREVENT" {
                shouldStandardize = false
                reasoning = "Temporal override: \(temporalValidation.reasoning)"
            }

            decisions.append(StandardizationDecision(
                nonStdPair: nonStdPair,
                canonicalPair: topCandidate.pair,
                priority: classification.priority,
                shouldStandardize: shouldStandardize,
                reasoning: reasoning,
                similarity: topCandidate.similarity,
                classification: classification,
                cvsValidation: cvsValidation,
                temporalValidation: temporalValidation,
                aiAnalysis: aiAnalysis
            ))

            print("  → Decision: \(shouldStandardize ? "STANDARDIZE" : "PRESERVE")")
        } else {
            print("  → No candidates found")

            decisions.append(StandardizationDecision(
                nonStdPair: nonStdPair,
                canonicalPair: nil,
                priority: classification.priority,
                shouldStandardize: false,
                reasoning: "No similar canonical pair found",
                similarity: 0.0,
                classification: classification,
                cvsValidation: nil,
                temporalValidation: nil,
                aiAnalysis: nil
            ))
        }
    }

    // Generate report
    print("\n=== Generating Report ===")

    let standardizations = decisions.filter { $0.shouldStandardize }
    let preservations = decisions.filter { !$0.shouldStandardize }

    var report = """
    # Priority-Filtered Make/Model Standardization Report

    **Date:** \(Date())
    **Database:** \(saaqDBPath)
    **CVS Database:** \(cvsDBPath)

    ## Summary

    - **Canonical pairs (2011-2022):** \(canonicalPairs.count)
      - PAU/CAU: \(canonicalPairs.filter { $0.isPauCau }.count)
      - Specialty: \(canonicalPairs.filter { !$0.isPauCau }.count)
    - **Non-standard pairs (2023-2024):** \(nonStdPairs.count)
    - **Standardizations recommended:** \(standardizations.count)
    - **Preservations recommended:** \(preservations.count)

    ## Priority Distribution

    """

    for priority in [Priority.canonicalPauCau, .cvsNewPauCau, .canonicalSpecialty, .unknown] {
        let count = priorityCounts[priority]?.count ?? 0
        let std = standardizations.filter { $0.priority == priority }.count
        let pres = preservations.filter { $0.priority == priority }.count
        report += "- **Priority \(priority.rawValue)**: \(count) pairs (\(std) standardizations, \(pres) preservations)\n"
    }

    report += "\n---\n\n## Standardizations (\(standardizations.count))\n\n"

    for decision in standardizations.sorted(by: { $0.priority < $1.priority }) {
        report += """
        ### [\(decision.priority.rawValue)] \(decision.nonStdPair.make) \(decision.nonStdPair.model) → \(decision.canonicalPair?.pair.make ?? "N/A") \(decision.canonicalPair?.pair.model ?? "N/A")

        - **Classification:** \(decision.classification?.reasoning ?? "N/A")
        - **Canonical Types:** \(decision.canonicalPair?.vehicleTypes.joined(separator: ", ") ?? "N/A")
        - **Similarity:** \(String(format: "%.2f", decision.similarity))
        - **AI:** \(decision.aiAnalysis?.classification ?? "N/A") (\(String(format: "%.2f", decision.aiAnalysis?.confidence ?? 0.0)))
        - **CVS:** \(decision.cvsValidation?.decision ?? "N/A") (\(String(format: "%.2f", decision.cvsValidation?.confidence ?? 0.0)))
        - **Temporal:** \(decision.temporalValidation?.decision ?? "N/A") (\(String(format: "%.2f", decision.temporalValidation?.confidence ?? 0.0)))
        - **Reasoning:** \(decision.reasoning)


        """
    }

    report += "---\n\n## Preservations (\(preservations.count))\n\n"

    for decision in preservations.sorted(by: { $0.priority < $1.priority }).prefix(50) {
        report += """
        ### [\(decision.priority.rawValue)] \(decision.nonStdPair.make) \(decision.nonStdPair.model) (preserved)

        - **Classification:** \(decision.classification?.reasoning ?? "N/A")
        - **Best candidate:** \(decision.canonicalPair?.pair.make ?? "N/A") \(decision.canonicalPair?.pair.model ?? "N/A")
        - **Similarity:** \(String(format: "%.2f", decision.similarity))
        - **Reasoning:** \(decision.reasoning)


        """
    }

    try report.write(toFile: reportPath, atomically: true, encoding: .utf8)
    print("  Report written to: \(reportPath)")

    print("\n✅ Standardization complete!")
    print("   Priority 1 (PAU/CAU canonical): \(priorityCounts[.canonicalPauCau]?.count ?? 0)")
    print("   Priority 2 (CVS new PAU/CAU): \(priorityCounts[.cvsNewPauCau]?.count ?? 0)")
    print("   Priority 3 (Specialty canonical): \(priorityCounts[.canonicalSpecialty]?.count ?? 0)")
    print("   Priority 4 (Unknown): \(priorityCounts[.unknown]?.count ?? 0)")
    print("   Standardizations: \(standardizations.count)")
    print("   Preservations: \(preservations.count)")
}

// Run
try await main()
