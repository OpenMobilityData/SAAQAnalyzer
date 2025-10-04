#!/usr/bin/env swift

import Foundation
import FoundationModels
import SQLite3

/// CVS-Enhanced AI make/model standardization
/// Adds authoritative CVS database validation + vehicle type checking + temporal validation
/// Usage: swift AIStandardizeMakeModel-Enhanced.swift <saaq_db> <cvs_db> <output_report.md>

// MARK: - AI Classification Structures

@Generable
enum DecisionType: String {
    case spellingVariant    // Typo or misspelling
    case newModel          // New 2023+ model
    case truncationVariant // Truncation variant
    case uncertain         // Requires human review
}

@Generable
struct VehicleModelAnalysis {
    var decision: DecisionType
    var shouldCorrect: Bool
    var canonicalForm: String?
    var confidence: Double
    var reasoning: String
}

// MARK: - Data Structures

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

struct AnalysisResult {
    let nonStandard: MakeModelPair
    let canonical: MakeModelPair?
    let analysis: VehicleModelAnalysis?
    let stringSimilarity: Double
    let cvsValidation: ValidationResult?
    let temporalValidation: ValidationResult?
}

struct CVSEntry {
    let make: String
    let model: String
    let saaqMake: String
    let saaqModel: String
    let vehicleType: String?
    let myr: Int
}

struct ValidationResult {
    let isValid: Bool
    let confidence: Double
    let reason: String
}

// MARK: - CVS Database Operations

func queryCVS(db: OpaquePointer, saaqMake: String, saaqModel: String) -> [CVSEntry] {
    let query = """
    SELECT make, model, saaq_make, saaq_model, vehicle_type, myr
    FROM cvs_data
    WHERE saaq_make = ? AND saaq_model = ?
    """

    var allEntries: [CVSEntry] = []

    // Generate hyphenation variants to handle inconsistencies (CX3 vs CX-3, HRV vs HR-V, etc.)
    var modelVariants = [saaqModel]  // Start with original

    // If model contains hyphen, try without it
    if saaqModel.contains("-") {
        modelVariants.append(saaqModel.replacingOccurrences(of: "-", with: ""))
    }
    // If model doesn't contain hyphen, try adding one between letters and numbers
    else {
        // Pattern: Insert hyphen between letter and number (CX3 → CX-3, HR350 → HR-350)
        // Use simple string scanning instead of regex for compatibility
        var letters = ""
        var rest = ""
        var foundDigit = false

        for char in saaqModel {
            if char.isLetter && !foundDigit {
                letters.append(char)
            } else {
                foundDigit = true
                rest.append(char)
            }
        }

        if !letters.isEmpty && !rest.isEmpty && rest.first?.isNumber == true {
            let withHyphen = "\(letters)-\(rest)"
            modelVariants.append(withHyphen)
        }
    }

    // Try each variant
    for variant in modelVariants {
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (saaqMake as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (variant as NSString).utf8String, -1, nil)

            while sqlite3_step(statement) == SQLITE_ROW {
                let make = String(cString: sqlite3_column_text(statement, 0))
                let model = String(cString: sqlite3_column_text(statement, 1))
                let saaqMake = String(cString: sqlite3_column_text(statement, 2))
                let saaqModel = String(cString: sqlite3_column_text(statement, 3))

                var vehicleType: String? = nil
                if let typePtr = sqlite3_column_text(statement, 4) {
                    vehicleType = String(cString: typePtr)
                }

                let myr = Int(sqlite3_column_int(statement, 5))

                allEntries.append(CVSEntry(
                    make: make,
                    model: model,
                    saaqMake: saaqMake,
                    saaqModel: saaqModel,
                    vehicleType: vehicleType,
                    myr: myr
                ))
            }
        }
        sqlite3_finalize(statement)

        // If we found matches with this variant, no need to try others
        if !allEntries.isEmpty {
            break
        }
    }

    return allEntries
}

// MARK: - SAAQ Database Operations

func openDatabase(_ path: String) -> OpaquePointer? {
    var db: OpaquePointer?
    if sqlite3_open(path, &db) != SQLITE_OK {
        print("❌ Failed to open database at: \(path)")
        return nil
    }
    return db
}

func extractCanonicalPairs(db: OpaquePointer) -> Set<MakeModelPair> {
    print("📋 Extracting canonical make/model pairs from 2011-2022...")

    let query = """
    SELECT make_enum.name, model_enum.name,
           MIN(vehicles.model_year), MAX(vehicles.model_year),
           MIN(vehicles.year), MAX(vehicles.year)
    FROM vehicles
    JOIN make_enum ON vehicles.make_id = make_enum.id
    JOIN model_enum ON vehicles.model_id = model_enum.id
    WHERE vehicles.year BETWEEN 2011 AND 2022
      AND vehicles.make_id IS NOT NULL
      AND vehicles.model_id IS NOT NULL
      AND vehicles.model_year IS NOT NULL
    GROUP BY make_enum.name, model_enum.name
    """

    var statement: OpaquePointer?
    var pairs = Set<MakeModelPair>()

    if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
        while sqlite3_step(statement) == SQLITE_ROW {
            let make = String(cString: sqlite3_column_text(statement, 0))
            let model = String(cString: sqlite3_column_text(statement, 1))
            let minModelYear = Int(sqlite3_column_int(statement, 2))
            let maxModelYear = Int(sqlite3_column_int(statement, 3))
            let minRegYear = Int(sqlite3_column_int(statement, 4))
            let maxRegYear = Int(sqlite3_column_int(statement, 5))

            if !make.isEmpty && !model.isEmpty {
                pairs.insert(MakeModelPair(
                    make: make,
                    model: model,
                    minModelYear: minModelYear,
                    maxModelYear: maxModelYear,
                    minRegistrationYear: minRegYear,
                    maxRegistrationYear: maxRegYear
                ))
            }
        }
    }
    sqlite3_finalize(statement)

    print("✓ Found \(pairs.count) canonical make/model pairs")
    return pairs
}

func extractNonStandardPairs(db: OpaquePointer) -> Set<MakeModelPair> {
    print("🔍 Extracting non-standard pairs from 2023-2024...")

    let query = """
    SELECT make_enum.name, model_enum.name,
           MIN(vehicles.model_year), MAX(vehicles.model_year),
           MIN(vehicles.year), MAX(vehicles.year)
    FROM vehicles
    JOIN make_enum ON vehicles.make_id = make_enum.id
    JOIN model_enum ON vehicles.model_id = model_enum.id
    WHERE vehicles.year >= 2023
      AND vehicles.make_id IS NOT NULL
      AND vehicles.model_id IS NOT NULL
    GROUP BY make_enum.name, model_enum.name
    """

    var statement: OpaquePointer?
    var pairs = Set<MakeModelPair>()

    if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
        while sqlite3_step(statement) == SQLITE_ROW {
            let make = String(cString: sqlite3_column_text(statement, 0))
            let model = String(cString: sqlite3_column_text(statement, 1))

            var minModelYear: Int? = nil
            var maxModelYear: Int? = nil
            if sqlite3_column_type(statement, 2) != SQLITE_NULL {
                minModelYear = Int(sqlite3_column_int(statement, 2))
            }
            if sqlite3_column_type(statement, 3) != SQLITE_NULL {
                maxModelYear = Int(sqlite3_column_int(statement, 3))
            }

            let minRegYear = Int(sqlite3_column_int(statement, 4))
            let maxRegYear = Int(sqlite3_column_int(statement, 5))

            if !make.isEmpty && !model.isEmpty {
                pairs.insert(MakeModelPair(
                    make: make,
                    model: model,
                    minModelYear: minModelYear,
                    maxModelYear: maxModelYear,
                    minRegistrationYear: minRegYear,
                    maxRegistrationYear: maxRegYear
                ))
            }
        }
    }
    sqlite3_finalize(statement)

    print("✓ Found \(pairs.count) non-standard pairs")
    return pairs
}

// MARK: - Validation Logic

func validateWithCVS(
    nonStandard: MakeModelPair,
    canonical: MakeModelPair,
    cvsDBPath: String
) -> ValidationResult {
    // Open thread-local CVS database connection for this task
    guard let cvsDB = openDatabase(cvsDBPath) else {
        return ValidationResult(
            isValid: true,
            confidence: 0.5,
            reason: "CVS database unavailable"
        )
    }
    defer { sqlite3_close(cvsDB) }

    // Query CVS for both non-standard and canonical
    let nonStdCVS = queryCVS(db: cvsDB, saaqMake: nonStandard.make, saaqModel: nonStandard.model)
    let canonCVS = queryCVS(db: cvsDB, saaqMake: canonical.make, saaqModel: canonical.model)

    // If neither in CVS, can't validate (likely specialty vehicle)
    if nonStdCVS.isEmpty && canonCVS.isEmpty {
        return ValidationResult(
            isValid: true,
            confidence: 0.5,
            reason: "Neither model in CVS (specialty vehicle?). Relying on AI judgment."
        )
    }

    // CASE 1: Both found in CVS - likely same vehicle, different SAAQ formatting
    // (e.g., SAAQ 2011-2022 uses "CX-3", 2023-2024 uses "CX3", CVS has both pointing to same vehicle)
    // This SUPPORTS standardization to match 2011-2022 canonical format
    if !nonStdCVS.isEmpty && !canonCVS.isEmpty {
        // Check if they point to the same underlying CVS vehicle
        let nonStdVehicles = Set(nonStdCVS.map { "\($0.make)|\($0.model)|\($0.vehicleType ?? "")" })
        let canonVehicles = Set(canonCVS.map { "\($0.make)|\($0.model)|\($0.vehicleType ?? "")" })

        if !nonStdVehicles.isDisjoint(with: canonVehicles) {
            // Same vehicle in CVS - standardization is correct (formatting normalization)
            return ValidationResult(
                isValid: true,
                confidence: 0.9,
                reason: "Both found in CVS as same vehicle - standardization normalizes SAAQ formatting to match 2011-2022."
            )
        }
    }

    // CASE 2: Only non-standard found in CVS, canonical NOT found
    // This means non-standard might be a genuinely NEW model not in 2011-2022 data
    if !nonStdCVS.isEmpty && canonCVS.isEmpty {
        let types = Set(nonStdCVS.compactMap { $0.vehicleType })
        return ValidationResult(
            isValid: false,
            confidence: 0.9,
            reason: "NON-STANDARD found in CVS as \(types.joined(separator: "/")), but canonical NOT in CVS - likely genuine new model!"
        )
    }

    // CASE 3: Only canonical found in CVS
    if nonStdCVS.isEmpty && !canonCVS.isEmpty {
        let canonTypes = Set(canonCVS.compactMap { $0.vehicleType })
        if canonTypes.count > 0 {
            let typeStr = canonTypes.joined(separator: "/")
            return ValidationResult(
                isValid: true,
                confidence: 0.8,
                reason: "Canonical in CVS as \(typeStr). Mapping appears valid."
            )
        }
    }

    return ValidationResult(isValid: true, confidence: 0.6, reason: "Partial CVS match")
}

func validateTemporalLogic(
    nonStandard: MakeModelPair,
    canonical: MakeModelPair
) -> ValidationResult {
    // Check model year range compatibility
    guard let nsMinMY = nonStandard.minModelYear,
          let nsMaxMY = nonStandard.maxModelYear,
          let canMinMY = canonical.minModelYear,
          let canMaxMY = canonical.maxModelYear else {
        return ValidationResult(
            isValid: true,
            confidence: 0.5,
            reason: "Insufficient model year data for temporal validation"
        )
    }

    // Check if model year ranges overlap or are adjacent
    let nsRange = nsMinMY...nsMaxMY
    let canRange = canMinMY...canMaxMY

    if nsRange.overlaps(canRange) {
        return ValidationResult(
            isValid: true,
            confidence: 0.9,
            reason: "Model year ranges overlap (\(nsMinMY)-\(nsMaxMY) vs \(canMinMY)-\(canMaxMY))"
        )
    }

    // Check if non-standard is newer (expected for model evolution)
    if nsMinMY > canMaxMY && nsMinMY - canMaxMY <= 2 {
        return ValidationResult(
            isValid: true,
            confidence: 0.7,
            reason: "Non-standard appears to be successor model (MY \(nsMinMY)-\(nsMaxMY) after \(canMinMY)-\(canMaxMY))"
        )
    }

    // Significant gap or incompatible ranges
    return ValidationResult(
        isValid: false,
        confidence: 0.8,
        reason: "Model year ranges incompatible: \(nsMinMY)-\(nsMaxMY) vs \(canMinMY)-\(canMaxMY). Likely different models!"
    )
}

// MARK: - String Similarity

func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
    let s1 = Array(s1)
    let s2 = Array(s2)
    var dist = [[Int]](repeating: [Int](repeating: 0, count: s2.count + 1), count: s1.count + 1)

    for i in 0...s1.count { dist[i][0] = i }
    for j in 0...s2.count { dist[0][j] = j }

    for i in 1...s1.count {
        for j in 1...s2.count {
            if s1[i-1] == s2[j-1] {
                dist[i][j] = dist[i-1][j-1]
            } else {
                dist[i][j] = min(dist[i-1][j], dist[i][j-1], dist[i-1][j-1]) + 1
            }
        }
    }

    return dist[s1.count][s2.count]
}

func stringSimilarity(_ s1: String, _ s2: String) -> Double {
    let maxLen = max(s1.count, s2.count)
    if maxLen == 0 { return 1.0 }
    let distance = levenshteinDistance(s1, s2)
    return 1.0 - Double(distance) / Double(maxLen)
}

// MARK: - AI Analysis

func analyzeWithAI(
    nonStandard: MakeModelPair,
    canonical: MakeModelPair,
    cvsValidation: ValidationResult,
    temporalValidation: ValidationResult
) async throws -> VehicleModelAnalysis {
    let prompt = """
    Vehicle data quality task: Compare two vehicle make/model codes from government database.

    Record A (2023-2024 data): \(nonStandard.make) / \(nonStandard.model)
      Model years: \(nonStandard.minModelYear ?? 0)-\(nonStandard.maxModelYear ?? 0)
      Registered: \(nonStandard.minRegistrationYear ?? 0)-\(nonStandard.maxRegistrationYear ?? 0)

    Record B (2011-2022 data): \(canonical.make) / \(canonical.model)
      Model years: \(canonical.minModelYear ?? 0)-\(canonical.maxModelYear ?? 0)
      Registered: \(canonical.minRegistrationYear ?? 0)-\(canonical.maxRegistrationYear ?? 0)

    Are these the same vehicle with spelling variation (spellingVariant), truncated text (truncationVariant), genuinely different models (newModel), or uncertain?

    Respond with: classification | should_standardize (yes/no) | confidence (0-1) | brief_reason
    """

    // Call Foundation Models API
    let freshSession = LanguageModelSession(instructions: "You are analyzing vehicle registration database records for data quality.")
    let response = try await freshSession.respond(to: prompt)

    // Parse AI response, then layer in CVS/temporal validation confidence adjustments
    let lowerText = response.content.lowercased()
    var shouldCorrect = true
    var confidence = 0.7
    var decision: DecisionType = .spellingVariant

    // Parse AI decision
    if lowerText.contains("newmodel") || lowerText.contains("new model") || lowerText.contains("genuinely different") {
        decision = .newModel
        shouldCorrect = false
    } else if lowerText.contains("spellingvariant") || (lowerText.contains("spelling") && lowerText.contains("variation")) {
        decision = .spellingVariant
        shouldCorrect = true
    } else if lowerText.contains("truncation") {
        decision = .truncationVariant
        shouldCorrect = true
    } else if lowerText.contains("uncertain") {
        decision = .uncertain
        shouldCorrect = false
    }

    // Extract confidence from AI response
    if let confidenceRange = response.content.range(of: "confidence:?\\s*([0-9]*\\.?[0-9]+)", options: [.regularExpression, .caseInsensitive]) {
        let confidenceText = String(response.content[confidenceRange])
        if let numberRange = confidenceText.range(of: "[0-9]*\\.?[0-9]+", options: .regularExpression) {
            let numberStr = String(confidenceText[numberRange])
            if let extractedConfidence = Double(numberStr) {
                confidence = extractedConfidence > 1.0 ? extractedConfidence / 100.0 : extractedConfidence
            }
        }
    }

    // CVS/Temporal validation overrides (applied after AI analysis)
    var reasoning = response.content

    // If CVS says non-standard IS in CVS database, it's likely legitimate - override AI
    if !cvsValidation.isValid && cvsValidation.confidence >= 0.9 {
        shouldCorrect = false
        decision = .newModel
        confidence = cvsValidation.confidence
        reasoning += "\n\n[CVS Override: Found in Transport Canada database - \(cvsValidation.reason)]"
    }

    // If temporal validation shows incompatibility, override AI to prevent false mapping
    if !temporalValidation.isValid && temporalValidation.confidence >= 0.8 {
        shouldCorrect = false
        decision = .newModel
        confidence = max(confidence, temporalValidation.confidence)
        reasoning += "\n\n[Temporal Override: Model year incompatibility - \(temporalValidation.reason)]"
    }

    return VehicleModelAnalysis(
        decision: decision,
        shouldCorrect: shouldCorrect,
        canonicalForm: shouldCorrect ? canonical.model : nil,
        confidence: confidence,
        reasoning: reasoning
    )
}

// MARK: - Main Processing

// MARK: - Main Execution

@MainActor
func main() async throws {
    print("🔧 DEBUG: Main started at \(Date())")
    fflush(stdout)

    let args = CommandLine.arguments
    print("🔧 DEBUG: Got \(args.count) arguments")
    fflush(stdout)

    guard args.count == 4 else {
        print("Usage: \(args[0]) <saaq_database_path> <cvs_database_path> <output_report.md>")
        exit(1)
    }

    let saaqDBPath = args[1]
    let cvsDBPath = args[2]
    let outputPath = args[3]

    print("🚗 CVS-Enhanced AI Make/Model Standardization")
    print("SAAQ Database: \(saaqDBPath)")
    print("CVS Database: \(cvsDBPath)")
    print("Output: \(outputPath)\n")
    print("🔧 DEBUG: About to open databases...")
    fflush(stdout)

    guard let saaqDB = openDatabase(saaqDBPath),
          let cvsDB = openDatabase(cvsDBPath) else {
        print("🔧 DEBUG: Failed to open databases")
        fflush(stdout)
        exit(1)
    }
    defer {
        sqlite3_close(saaqDB)
        sqlite3_close(cvsDB)
    }

    print("🔧 DEBUG: Databases opened successfully")
    fflush(stdout)

    let canonical = extractCanonicalPairs(db: saaqDB)
    print("🔧 DEBUG: Extracted canonical pairs")
    fflush(stdout)

    let nonStandard = extractNonStandardPairs(db: saaqDB)
    print("🔧 DEBUG: Extracted non-standard pairs")
    fflush(stdout)

    let newPairs = nonStandard.subtracting(canonical)
    print("🔧 DEBUG: Calculated new pairs")
    fflush(stdout)

    print("\n📊 Analysis:")
    print("  Canonical pairs (2011-2022): \(canonical.count)")
    print("  Non-standard pairs (2023-2024): \(nonStandard.count)")
    print("  New/different pairs: \(newPairs.count)\n")

    var report = """
    # AI Make/Model Standardization Report (CVS-Enhanced)

    **Generated:** \(Date())

    ## Summary
    - Canonical pairs (2011-2022): \(canonical.count)
    - Non-standard pairs (2023-2024): \(nonStandard.count)
    - New/different pairs requiring analysis: \(newPairs.count)

    ## Methodology
    1. **CVS Database Lookup**: Check Transport Canada's authoritative vehicle database
    2. **Vehicle Type Validation**: Ensure minivan→sedan errors are caught
    3. **Temporal Validation**: Check model year range compatibility
    4. **AI Analysis**: LLM evaluates evidence and makes recommendation

    ## Mappings

    """

    let sortedPairs = Array(newPairs).sorted(by: { $0.make + $0.model < $1.make + $1.model })

    // PRE-FILTER: Separate pairs into fast-path (no match) vs AI-analysis path
    print("🔍 Pre-filtering pairs...")
    var noMatchPairs: [AnalysisResult] = []
    var aiPairs: [(nonStd: MakeModelPair, canonical: MakeModelPair, similarity: Double)] = []

    for nonStdPair in sortedPairs {
        let candidates = canonical.filter { $0.make == nonStdPair.make }
            .map { (pair: $0, similarity: stringSimilarity(nonStdPair.model, $0.model)) }
            .map { candidate -> (pair: MakeModelPair, similarity: Double) in
                // Boost similarity for hyphenation variants (e.g., CX3 vs CX-3)
                var boostedSimilarity = candidate.similarity

                // Check if models are hyphenation variants of each other
                let model1 = nonStdPair.model.replacingOccurrences(of: "-", with: "")
                let model2 = candidate.pair.model.replacingOccurrences(of: "-", with: "")

                if model1 == model2 && nonStdPair.model != candidate.pair.model {
                    // They're identical except for hyphenation - give massive boost
                    // Example: CX3 vs CX-3 (both become "CX3" after hyphen removal, but originals differ)
                    boostedSimilarity = 0.99  // Near-perfect match
                }

                return (pair: candidate.pair, similarity: boostedSimilarity)
            }
            .sorted { $0.similarity > $1.similarity }

        if let bestCandidate = candidates.first, bestCandidate.similarity > 0.4 {
            aiPairs.append((nonStd: nonStdPair, canonical: bestCandidate.pair, similarity: bestCandidate.similarity))
        } else {
            noMatchPairs.append(AnalysisResult(
                nonStandard: nonStdPair,
                canonical: nil,
                analysis: nil,
                stringSimilarity: 0.0,
                cvsValidation: nil,
                temporalValidation: nil
            ))
        }
    }

    print("   No-match pairs (fast path): \(noMatchPairs.count)")
    print("   AI-analysis pairs: \(aiPairs.count)\n")

    print("🚀 Launching \(aiPairs.count) parallel AI analysis tasks...")
    print("   (Swift runtime will manage concurrency automatically)")
    let startTime = Date()
    fflush(stdout)

    // Process ONLY AI pairs in parallel - ALL tasks will call AI
    let aiResults = try await withThrowingTaskGroup(of: AnalysisResult?.self) { group in
        var processedResults: [AnalysisResult] = []
        var processedCount = 0

        // Submit ALL AI tasks concurrently
        for (nonStdPair, canonicalPair, similarity) in aiPairs {
            group.addTask {

                // Validate with CVS (opens its own connection - thread-safe)
                let cvsValidation = validateWithCVS(
                    nonStandard: nonStdPair,
                    canonical: canonicalPair,
                    cvsDBPath: cvsDBPath
                )

                // Validate temporal logic
                let temporalValidation = validateTemporalLogic(
                    nonStandard: nonStdPair,
                    canonical: canonicalPair
                )

                // Get AI analysis
                let analysis = try await analyzeWithAI(
                    nonStandard: nonStdPair,
                    canonical: canonicalPair,
                    cvsValidation: cvsValidation,
                    temporalValidation: temporalValidation
                )

                return AnalysisResult(
                    nonStandard: nonStdPair,
                    canonical: canonicalPair,
                    analysis: analysis,
                    stringSimilarity: similarity,
                    cvsValidation: cvsValidation,
                    temporalValidation: temporalValidation
                )
            }
        }

        print("✓ All \(aiPairs.count) AI tasks launched, waiting for completions...\n")
        fflush(stdout)

        // Collect AI results as they complete
        for try await result in group {
            if let result = result {
                processedResults.append(result)
                processedCount += 1

                // Progress with ETA every 10 pairs
                if processedCount % 10 == 0 || processedCount == aiPairs.count {
                    let elapsed = Date().timeIntervalSince(startTime)
                    let rate = Double(processedCount) / elapsed
                    let remaining = Double(aiPairs.count - processedCount) / rate
                    let mins = Int(remaining) / 60
                    let secs = Int(remaining) % 60
                    print(String(format: "  ✓ AI Completed: %d/%d (%.1f%%) - %.1f pairs/sec - ETA: %dm %ds",
                        processedCount, aiPairs.count,
                        Double(processedCount) / Double(aiPairs.count) * 100.0,
                        rate, mins, secs))
                    fflush(stdout)
                }
            }
        }

        return processedResults
    }

    // Combine no-match pairs + AI results
    let allResults = noMatchPairs + aiResults

    // Sort combined results by make/model for consistent output
    let sortedResults = allResults.sorted { r1, r2 in
        r1.nonStandard.make + r1.nonStandard.model < r2.nonStandard.make + r2.nonStandard.model
    }

    print("\n📊 Processing complete:")
    print("   No-match pairs: \(noMatchPairs.count)")
    print("   AI-analyzed pairs: \(aiResults.count)")
    print("   Total: \(sortedResults.count)\n")

    // Generate report from results
    for result in sortedResults {
        let nonStdPair = result.nonStandard

        // Case 1: No similar canonical found
        guard let canonical = result.canonical, let analysis = result.analysis else {
            report += """
            ### \(nonStdPair.make) \(nonStdPair.model) → **KEEP AS NEW MODEL**
            - **Action:** Keep '\(nonStdPair.model)' unchanged (no similar canonical form found)
            - **Model Years:** \(nonStdPair.minModelYear ?? 0)-\(nonStdPair.maxModelYear ?? 0)


            """
            continue
        }

        // Case 2: AI analysis completed
        let cvsValidation = result.cvsValidation!
        let temporalValidation = result.temporalValidation!

        if analysis.shouldCorrect {
            // STANDARDIZE - replace with canonical
            let canonicalModel = analysis.canonicalForm ?? canonical.model
            report += """
            ### \(nonStdPair.make) \(nonStdPair.model) → **STANDARDIZE TO '\(canonicalModel)'**
            - **Action:** Replace '\(nonStdPair.model)' with canonical '\(canonicalModel)'
            - **Closest canonical form:** \(canonical.model)
            - **AI confidence in standardization:** \(String(format: "%.0f%%", analysis.confidence * 100))
            - **String similarity to canonical:** \(String(format: "%.0f%%", result.stringSimilarity * 100))
            - **CVS validation (authority check):** \(cvsValidation.reason) (conf: \(String(format: "%.0f%%", cvsValidation.confidence * 100)))
            - **Temporal validation (year compatibility):** \(temporalValidation.reason) (conf: \(String(format: "%.0f%%", temporalValidation.confidence * 100)))
            - **AI reasoning:** \(analysis.reasoning)


            """
        } else {
            // KEEP ORIGINAL - preserve as-is
            report += """
            ### \(nonStdPair.make) \(nonStdPair.model) → **KEEP ORIGINAL**
            - **Action:** Keep '\(nonStdPair.model)' unchanged (legitimate variant or new model)
            - **Closest canonical form:** \(canonical.model)
            - **AI confidence in preservation:** \(String(format: "%.0f%%", analysis.confidence * 100))
            - **String similarity to canonical:** \(String(format: "%.0f%%", result.stringSimilarity * 100))
            - **CVS validation (authority check):** \(cvsValidation.reason) (conf: \(String(format: "%.0f%%", cvsValidation.confidence * 100)))
            - **Temporal validation (year compatibility):** \(temporalValidation.reason) (conf: \(String(format: "%.0f%%", temporalValidation.confidence * 100)))
            - **AI reasoning:** \(analysis.reasoning)


            """
        }
    }

    print("🔧 DEBUG: Writing report...")
    fflush(stdout)

    do {
        try report.write(toFile: outputPath, atomically: true, encoding: .utf8)
        print("\n✅ Report written to: \(outputPath)")
        print("🔧 DEBUG: Script completed successfully at \(Date())")
        fflush(stdout)
    } catch {
        print("❌ Failed to write report: \(error)")
        fflush(stdout)
        exit(1)
    }
}

// Run
try await main()
