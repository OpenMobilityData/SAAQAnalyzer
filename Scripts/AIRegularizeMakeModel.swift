#!/usr/bin/env swift
import Foundation
import SQLite3
import FoundationModels

// MARK: - Configuration
let SIMILARITY_THRESHOLD = 0.4

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
}

struct Candidate {
    let pair: CanonicalPair
    let similarity: Double
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
    let shouldRegularize: Bool
    let reasoning: String
}

struct RegularizationDecision {
    let nonStdPair: MakeModelPair
    let canonicalPair: CanonicalPair?
    let shouldRegularize: Bool
    let reasoning: String
    let similarity: Double
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
func validateWithTemporal(nonStdPair: MakeModelPair, canonicalPair: MakeModelPair) -> TemporalValidationResult {
    // Use pre-loaded registration year ranges
    guard let nonStdMin = nonStdPair.minRegistrationYear,
          let nonStdMax = nonStdPair.maxRegistrationYear,
          let canonicalMin = canonicalPair.minRegistrationYear,
          let canonicalMax = canonicalPair.maxRegistrationYear else {
        return TemporalValidationResult(
            decision: "NEUTRAL",
            confidence: 0.5,
            reasoning: "Year range data unavailable"
        )
    }

    let hasOverlap = !(nonStdMax < canonicalMin || canonicalMax < nonStdMin)

    if hasOverlap {
        return TemporalValidationResult(
            decision: "SUPPORT",
            confidence: 0.9,
            reasoning: "Registration years overlap (\(nonStdMin)-\(nonStdMax) vs \(canonicalMin)-\(canonicalMax))"
        )
    } else if nonStdMin > canonicalMax {
        return TemporalValidationResult(
            decision: "PREVENT",
            confidence: 0.7,
            reasoning: "Non-standard appears after canonical ended (\(nonStdMin)+ vs \(canonicalMin)-\(canonicalMax)) - likely new model"
        )
    } else {
        return TemporalValidationResult(
            decision: "PREVENT",
            confidence: 0.8,
            reasoning: "No registration year overlap (\(nonStdMin)-\(nonStdMax) vs \(canonicalMin)-\(canonicalMax))"
        )
    }
}

// MARK: - AI Analysis
func analyzeWithAI(nonStdPair: MakeModelPair, canonicalPair: MakeModelPair) async -> AIAnalysisResult {
    // Format year information for prompt
    let nonStdYears = formatYearRange(nonStdPair.minRegistrationYear, nonStdPair.maxRegistrationYear)
    let canonicalYears = formatYearRange(canonicalPair.minRegistrationYear, canonicalPair.maxRegistrationYear)

    let prompt = """
    You are the third validation layer in a vehicle database regularization pipeline.

    CONTEXT:
    - Record A (2023-2024) contains typos, truncations, and genuinely new models mixed together
    - Record B (2011-2022) is cleaned, quality-assured canonical reference data
    - These records were matched with 40%+ string similarity as potential variants
    - CVS and temporal validators run before you and can override your decision

    YOUR TASK:
    Determine if Record A is a VARIANT of Record B (same vehicle, different spelling/format).

    Record A: \(nonStdPair.make) / \(nonStdPair.model) [registered: \(nonStdYears)]
    Record B: \(canonicalPair.make) / \(canonicalPair.model) [registered: \(canonicalYears)]

    ANSWER "yes" (should_regularize: yes) ONLY if this is the SAME vehicle with:
    1. spellingVariant - Typo or misspelling (VOLV0→VOLVO, HOND→HONDA, SUSUK→SUZUKI)
    2. truncationVariant - Format difference (CX3→CX-3, HRV→HR-V, C300→C-CLASS)

    ANSWER "no" (should_regularize: no) if:
    3. newModel - Different models even if similar names (X4≠X3, UX≠GX, CARNI≠CADEN, C300≠B200, CBR≠CR-V)
    4. uncertain - Insufficient information to confidently determine

    CRITICAL EXAMPLES:
    ✓ VOLV0 / XC90 vs VOLVO / XC90 → spellingVariant | yes | 1.0 | typo: zero instead of letter O
    ✓ MAZDA / CX3 vs MAZDA / CX-3 → truncationVariant | yes | 0.99 | hyphen formatting variant
    ✓ HOND / CIVIC vs HONDA / CIVIC → spellingVariant | yes | 0.95 | missing final A
    ✗ BMW / X4 vs BMW / X3 → newModel | no | 1.0 | X4 is different SUV model (larger than X3)
    ✗ LEXUS / UX vs LEXUS / GX → newModel | no | 1.0 | UX and GX are completely different model lines
    ✗ MERCE / C300 vs MERCE / B200 → newModel | no | 1.0 | C-Class and B-Class are different vehicle series
    ✗ KIA / CARNI vs KIA / CADEN → newModel | no | 0.9 | CARNIVAL and CADENZA are different models
    ✗ HONDA / CBR vs HONDA / CR-V → newModel | no | 1.0 | CBR is motorcycle, CR-V is SUV

    IMPORTANT: If you classify as "newModel", you MUST answer "no" for should_regularize.

    Respond with: classification | should_regularize (yes/no) | confidence (0-1) | brief_reason
    """

    do {
        let freshSession = LanguageModelSession(instructions: "You are analyzing vehicle registration database records for data quality.")
        let response = try await freshSession.respond(to: prompt)
        let content = response.content.lowercased()

        var classification = "uncertain"
        var shouldRegularize = false
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
        if content.contains("should_regularize: yes") || content.contains("should regularize: yes") || (content.contains("yes") && !content.contains("yes/no")) {
            shouldRegularize = true
        } else if content.contains("should_regularize: no") || content.contains("should regularize: no") || content.contains(": no") {
            shouldRegularize = false
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
        if shouldRegularize && confidence >= 0.7 {
            return AIAnalysisResult(
                classification: classification,
                confidence: confidence,
                shouldRegularize: true,
                reasoning: reasoning
            )
        } else {
            return AIAnalysisResult(
                classification: classification,
                confidence: confidence,
                shouldRegularize: false,
                reasoning: reasoning
            )
        }
    } catch {
        return AIAnalysisResult(
            classification: "uncertain",
            confidence: 0.5,
            shouldRegularize: false,
            reasoning: "AI analysis error: \(error.localizedDescription)"
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

// MARK: - Main Logic
@MainActor
func main() async throws {
    print("=== AI-Validated Make/Model Regularization ===\n")

    guard CommandLine.arguments.count == 4 else {
        print("Usage: AIRegularizeMakeModel <saaq_db_path> <cvs_db_path> <output_report_path>")
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
            pair: MakeModelPair(make: make, model: model, minModelYear: nil, maxModelYear: nil, minRegistrationYear: minRegYear, maxRegistrationYear: maxRegYear),
            vehicleTypes: types
        ))
    }

    print("  Found \(canonicalPairs.count) canonical Make/Model pairs from 2011-2022")

    // Load non-standard pairs (2023-2024)
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
        return MakeModelPair(make: make, model: model, minModelYear: nil, maxModelYear: nil, minRegistrationYear: minRegYear, maxRegistrationYear: maxRegYear)
    })

    // Filter to only non-canonical pairs
    let canonicalPairSet = Set(canonicalPairs.map { $0.pair })
    let nonStdPairs = allNonStdPairs.subtracting(canonicalPairSet)

    print("  Found \(allNonStdPairs.count) total pairs, \(nonStdPairs.count) are non-standard")

    print("\n=== Processing Non-Standard Pairs ===")
    var decisions: [RegularizationDecision] = []

    // Process all non-standard pairs against all canonical pairs
    for nonStdPair in nonStdPairs {
        // Format year range for display
        let nonStdYears = formatYearRange(nonStdPair.minRegistrationYear, nonStdPair.maxRegistrationYear)
        print("\n\(nonStdPair.make) \(nonStdPair.model) [\(nonStdYears)]")

        // Find best candidate from ALL canonical pairs
        var candidates: [Candidate] = []

        for canonical in canonicalPairs {
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
            let canonicalYears = formatYearRange(topCandidate.pair.pair.minRegistrationYear, topCandidate.pair.pair.maxRegistrationYear)
            print("  → Evaluating closest match: \(topCandidate.pair.pair.make) \(topCandidate.pair.pair.model) [\(canonicalYears)] (similarity: \(String(format: "%.2f", topCandidate.similarity)))")

            // Validate with CVS, Temporal, AI
            let cvsValidation = validateWithCVS(
                nonStdPair: nonStdPair,
                canonicalPair: topCandidate.pair.pair,
                cvsDBPath: cvsDBPath
            )

            let temporalValidation = validateWithTemporal(
                nonStdPair: nonStdPair,
                canonicalPair: topCandidate.pair.pair
            )

            let aiAnalysis = await analyzeWithAI(
                nonStdPair: nonStdPair,
                canonicalPair: topCandidate.pair.pair
            )

            // Override logic
            var shouldRegularize = aiAnalysis.shouldRegularize
            var reasoning = aiAnalysis.reasoning

            if cvsValidation.confidence >= 0.9 && cvsValidation.decision == "PREVENT" {
                shouldRegularize = false
                reasoning = "CVS override: \(cvsValidation.reasoning)"
            }

            if temporalValidation.confidence >= 0.8 && temporalValidation.decision == "PREVENT" {
                shouldRegularize = false
                reasoning = "Temporal override: \(temporalValidation.reasoning)"
            }

            decisions.append(RegularizationDecision(
                nonStdPair: nonStdPair,
                canonicalPair: topCandidate.pair,
                shouldRegularize: shouldRegularize,
                reasoning: reasoning,
                similarity: topCandidate.similarity,
                cvsValidation: cvsValidation,
                temporalValidation: temporalValidation,
                aiAnalysis: aiAnalysis
            ))

            if shouldRegularize {
                print("  ✓ Decision: REGULARIZE → \(topCandidate.pair.pair.make) \(topCandidate.pair.pair.model)")
            } else {
                print("  ✗ Decision: PRESERVE (keep as \(nonStdPair.make) \(nonStdPair.model))")
            }
        } else {
            print("  → No candidates found")

            decisions.append(RegularizationDecision(
                nonStdPair: nonStdPair,
                canonicalPair: nil,
                shouldRegularize: false,
                reasoning: "No similar canonical pair found",
                similarity: 0.0,
                cvsValidation: nil,
                temporalValidation: nil,
                aiAnalysis: nil
            ))
        }
    }

    // Generate report
    print("\n=== Generating Report ===")

    let regularizations = decisions.filter { $0.shouldRegularize }
    let preservations = decisions.filter { !$0.shouldRegularize }

    var report = """
    # Make/Model Regularization Report

    **Date:** \(Date())
    **Database:** \(saaqDBPath)
    **CVS Database:** \(cvsDBPath)

    ## Summary

    - **Canonical pairs (2011-2022):** \(canonicalPairs.count)
    - **Non-standard pairs (2023-2024):** \(nonStdPairs.count)
    - **Regularizations recommended:** \(regularizations.count)
    - **Preservations recommended:** \(preservations.count)

    ---

    ## Regularizations (\(regularizations.count))

    """

    for decision in regularizations {
        report += """
        ### \(decision.nonStdPair.make) \(decision.nonStdPair.model) → \(decision.canonicalPair?.pair.make ?? "N/A") \(decision.canonicalPair?.pair.model ?? "N/A")

        - **Canonical Types:** \(decision.canonicalPair?.vehicleTypes.joined(separator: ", ") ?? "N/A")
        - **Similarity:** \(String(format: "%.2f", decision.similarity))
        - **AI:** \(decision.aiAnalysis?.classification ?? "N/A") (\(String(format: "%.2f", decision.aiAnalysis?.confidence ?? 0.0)))
        - **CVS:** \(decision.cvsValidation?.decision ?? "N/A") (\(String(format: "%.2f", decision.cvsValidation?.confidence ?? 0.0)))
        - **Temporal:** \(decision.temporalValidation?.decision ?? "N/A") (\(String(format: "%.2f", decision.temporalValidation?.confidence ?? 0.0)))
        - **Reasoning:** \(decision.reasoning)


        """
    }

    report += "---\n\n## Preservations (\(preservations.count))\n\n"
    report += "*Showing first 50 preservations*\n\n"

    for decision in preservations.prefix(50) {
        report += """
        ### \(decision.nonStdPair.make) \(decision.nonStdPair.model) (preserved)

        - **Best candidate:** \(decision.canonicalPair?.pair.make ?? "none") \(decision.canonicalPair?.pair.model ?? "")
        - **Similarity:** \(String(format: "%.2f", decision.similarity))
        - **Reasoning:** \(decision.reasoning)


        """
    }

    try report.write(toFile: reportPath, atomically: true, encoding: .utf8)
    print("  Report written to: \(reportPath)")

    print("\n✅ Regularization complete!")
    print("   Regularizations: \(regularizations.count)")
    print("   Preservations: \(preservations.count)")
}

// Run
try await main()
