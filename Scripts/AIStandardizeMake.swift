#!/usr/bin/env swift
import Foundation
import SQLite3
import FoundationModels

// MARK: - Configuration
let SIMILARITY_THRESHOLD = 0.4
let AI_BATCH_SIZE = 245

// MARK: - Data Models
struct MakePair: Hashable {
    let make: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(make)
    }

    static func == (lhs: MakePair, rhs: MakePair) -> Bool {
        lhs.make == rhs.make
    }
}

struct MakeCandidate {
    let pair: MakePair
    let similarity: Double
}

struct CVSValidationResult {
    let decision: String  // "SUPPORT" or "PREVENT" or "NEUTRAL"
    let confidence: Double
    let reasoning: String
}

struct TemporalValidationResult {
    let decision: String  // "SUPPORT" or "PREVENT" or "NEUTRAL"
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
    let nonStdMake: MakePair
    let canonicalMake: MakePair?
    let shouldStandardize: Bool
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

// MARK: - CVS Validation
func queryCVSForMake(cvsDB: DatabaseHelper, saaqMake: String) throws -> [String: Any]? {
    let sql = """
    SELECT DISTINCT saaq_make, vehicle_type, myr
    FROM cvs_data
    WHERE saaq_make = '\(saaqMake)'
    LIMIT 1;
    """

    let results = try cvsDB.query(sql)
    guard let first = results.first else { return nil }

    return [
        "saaq_make": first["saaq_make"] ?? "",
        "vehicle_type": first["vehicle_type"] ?? "",
        "myr": first["myr"] ?? ""
    ]
}

func validateWithCVS(nonStdMake: MakePair, canonicalMake: MakePair, cvsDBPath: String) -> CVSValidationResult {
    // Open thread-local CVS database connection
    guard let cvsDB = try? DatabaseHelper(path: cvsDBPath) else {
        return CVSValidationResult(
            decision: "NEUTRAL",
            confidence: 0.5,
            reasoning: "CVS database unavailable"
        )
    }

    do {
        let nonStdData = try queryCVSForMake(cvsDB: cvsDB, saaqMake: nonStdMake.make)
        let canonicalData = try queryCVSForMake(cvsDB: cvsDB, saaqMake: canonicalMake.make)

        let nonStdFound = nonStdData != nil
        let canonicalFound = canonicalData != nil

        if nonStdFound && canonicalFound {
            // Both found - check if they're the same manufacturer
            let nonStdType = (nonStdData?["vehicle_type"] as? String) ?? ""
            let canonicalType = (canonicalData?["vehicle_type"] as? String) ?? ""

            if nonStdType == canonicalType {
                return CVSValidationResult(
                    decision: "SUPPORT",
                    confidence: 0.9,
                    reasoning: "Both makes found in CVS as same vehicle type (\(canonicalType))"
                )
            } else {
                return CVSValidationResult(
                    decision: "PREVENT",
                    confidence: 0.9,
                    reasoning: "Both found in CVS but different vehicle types (\(nonStdType) vs \(canonicalType))"
                )
            }
        } else if nonStdFound && !canonicalFound {
            return CVSValidationResult(
                decision: "PREVENT",
                confidence: 0.9,
                reasoning: "Non-standard make found in CVS, canonical not found - likely different manufacturer"
            )
        } else if !nonStdFound && canonicalFound {
            return CVSValidationResult(
                decision: "SUPPORT",
                confidence: 0.8,
                reasoning: "Canonical make found in CVS, non-standard not found - likely truncation/typo"
            )
        } else {
            return CVSValidationResult(
                decision: "NEUTRAL",
                confidence: 0.5,
                reasoning: "Neither make found in CVS (specialty vehicle or discontinued)"
            )
        }
    } catch {
        return CVSValidationResult(
            decision: "NEUTRAL",
            confidence: 0.5,
            reasoning: "CVS query error: \(error.localizedDescription)"
        )
    }
}

// MARK: - Temporal Validation
func validateWithTemporal(nonStdMake: MakePair, canonicalMake: MakePair, saaqDBPath: String) -> TemporalValidationResult {
    // Open thread-local SAAQ database connection
    guard let saaqDB = try? DatabaseHelper(path: saaqDBPath) else {
        return TemporalValidationResult(
            decision: "NEUTRAL",
            confidence: 0.5,
            reasoning: "SAAQ database unavailable"
        )
    }

    do {
        // Get year range for non-standard make
        let nonStdSQL = """
        SELECT MIN(v.year) as min_year, MAX(v.year) as max_year
        FROM vehicles v
        JOIN make_enum me ON v.make_id = me.id
        WHERE me.name = '\(nonStdMake.make)';
        """
        let nonStdResults = try saaqDB.query(nonStdSQL)

        // Get year range for canonical make
        let canonicalSQL = """
        SELECT MIN(v.year) as min_year, MAX(v.year) as max_year
        FROM vehicles v
        JOIN make_enum me ON v.make_id = me.id
        WHERE me.name = '\(canonicalMake.make)';
        """
        let canonicalResults = try saaqDB.query(canonicalSQL)

        guard let nonStdRow = nonStdResults.first,
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

        // Check for overlap
        let hasOverlap = !(nonStdMax < canonicalMin || canonicalMax < nonStdMin)

        if hasOverlap {
            return TemporalValidationResult(
                decision: "SUPPORT",
                confidence: 0.9,
                reasoning: "Year ranges overlap (\(nonStdMin)-\(nonStdMax) vs \(canonicalMin)-\(canonicalMax))"
            )
        } else {
            // Check for successor pattern (non-standard is newer)
            if nonStdMin > canonicalMax {
                return TemporalValidationResult(
                    decision: "PREVENT",
                    confidence: 0.7,
                    reasoning: "Non-standard appears after canonical ended (possible new manufacturer)"
                )
            } else {
                return TemporalValidationResult(
                    decision: "PREVENT",
                    confidence: 0.8,
                    reasoning: "No year overlap (\(nonStdMin)-\(nonStdMax) vs \(canonicalMin)-\(canonicalMax))"
                )
            }
        }
    } catch {
        return TemporalValidationResult(
            decision: "NEUTRAL",
            confidence: 0.5,
            reasoning: "Temporal query error: \(error.localizedDescription)"
        )
    }
}

// MARK: - AI Analysis
func analyzeWithAI(nonStdMake: MakePair, canonicalMake: MakePair) async -> AIAnalysisResult {
    let prompt = """
    You are analyzing vehicle manufacturer names to determine if they refer to the same manufacturer.

    Non-standard make: \(nonStdMake.make)
    Canonical make: \(canonicalMake.make)

    Common patterns:
    - Truncation: TOYOTA → TOYOT, CHEVROLET → CHEVR (5 characters)
    - Typos: HONDA → HOND, MERCEDES → MERCE
    - Abbreviations: VOLKSWAGEN → VOLKS

    Task: Determine if these are the same manufacturer, or different manufacturers.

    Respond in this exact format:
    CLASSIFICATION: [sameManufacturer|differentManufacturer|uncertain]
    CONFIDENCE: [0.0-1.0]
    REASONING: [brief explanation]
    """

    do {
        // Create fresh session for this task (thread-safe)
        let freshSession = LanguageModelSession(instructions: "You are a precise data analyst specializing in vehicle manufacturer identification.")
        let response = try await freshSession.respond(to: prompt)
        let content = response.content

        // Parse response
        var classification = "uncertain"
        var confidence = 0.5
        var reasoning = "Failed to parse AI response"

        let lines = content.split(separator: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("CLASSIFICATION:") {
                let value = trimmed.replacingOccurrences(of: "CLASSIFICATION:", with: "").trimmingCharacters(in: .whitespaces)
                classification = value.lowercased()
            } else if trimmed.hasPrefix("CONFIDENCE:") {
                let value = trimmed.replacingOccurrences(of: "CONFIDENCE:", with: "").trimmingCharacters(in: .whitespaces)
                confidence = Double(value) ?? 0.5
            } else if trimmed.hasPrefix("REASONING:") {
                reasoning = trimmed.replacingOccurrences(of: "REASONING:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        let shouldStandardize = classification == "samemanufacturer" && confidence >= 0.7

        return AIAnalysisResult(
            classification: classification,
            confidence: confidence,
            shouldStandardize: shouldStandardize,
            reasoning: reasoning
        )
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
    print("=== AI Make Standardization (Pass 1 of Two-Pass Architecture) ===\n")

    // Parse arguments
    guard CommandLine.arguments.count == 4 else {
        print("Usage: AIStandardizeMake <saaq_db_path> <cvs_db_path> <output_report_path>")
        return
    }

    let saaqDBPath = CommandLine.arguments[1]
    let cvsDBPath = CommandLine.arguments[2]
    let reportPath = CommandLine.arguments[3]

    // Open database for initial queries (thread-local connections opened per task later)
    print("Opening database...")
    let saaqDB = try DatabaseHelper(path: saaqDBPath)

    // Get canonical makes (2011-2022)
    print("Loading canonical makes (2011-2022)...")
    let canonicalSQL = """
    SELECT DISTINCT me.name
    FROM vehicles v
    JOIN make_enum me ON v.make_id = me.id
    WHERE v.year BETWEEN 2011 AND 2022;
    """
    let canonicalResults = try saaqDB.query(canonicalSQL)
    let canonicalMakes = Set(canonicalResults.compactMap { MakePair(make: $0["name"] ?? "") })
    print("  Found \(canonicalMakes.count) canonical makes")

    // Get non-standard makes (2023-2024)
    print("Loading non-standard makes (2023-2024)...")
    let nonStdSQL = """
    SELECT DISTINCT me.name
    FROM vehicles v
    JOIN make_enum me ON v.make_id = me.id
    WHERE v.year IN (2023, 2024);
    """
    let nonStdResults = try saaqDB.query(nonStdSQL)
    let allNonStdMakes = Set(nonStdResults.compactMap { MakePair(make: $0["name"] ?? "") })

    // Filter to only those NOT in canonical set
    let nonStdMakes = allNonStdMakes.subtracting(canonicalMakes)
    print("  Found \(allNonStdMakes.count) total makes, \(nonStdMakes.count) are non-standard")

    // STEP 1: Find candidates for each non-standard make
    print("\n=== STEP 1: Candidate Selection ===")
    var candidateMap: [MakePair: [MakeCandidate]] = [:]

    for nonStdMake in nonStdMakes.sorted(by: { $0.make < $1.make }) {
        var candidates: [MakeCandidate] = []

        for canonicalMake in canonicalMakes {
            let similarity = stringSimilarity(nonStdMake.make, canonicalMake.make)

            if similarity >= SIMILARITY_THRESHOLD {
                candidates.append(MakeCandidate(
                    pair: canonicalMake,
                    similarity: similarity
                ))
            }
        }

        // Sort by similarity (highest first)
        candidates.sort { $0.similarity > $1.similarity }

        if !candidates.isEmpty {
            candidateMap[nonStdMake] = candidates
            print("  \(nonStdMake.make): \(candidates.count) candidates (best: \(candidates[0].pair.make) @ \(String(format: "%.2f", candidates[0].similarity)))")
        } else {
            print("  \(nonStdMake.make): No candidates found")
        }
    }

    print("\n  Total non-standard makes with candidates: \(candidateMap.count)")

    // STEP 2: Validate with CVS, Temporal, and AI
    print("\n=== STEP 2: Validation & AI Analysis ===")
    var decisions: [StandardizationDecision] = []

    let makesWithCandidates = Array(candidateMap.keys).sorted { $0.make < $1.make }

    // Process in batches
    for i in stride(from: 0, to: makesWithCandidates.count, by: AI_BATCH_SIZE) {
        let batch = Array(makesWithCandidates[i..<min(i + AI_BATCH_SIZE, makesWithCandidates.count)])

        print("\nProcessing batch \(i/AI_BATCH_SIZE + 1) (\(batch.count) makes)...")

        await withTaskGroup(of: StandardizationDecision.self) { group in
            for nonStdMake in batch {
                guard let candidates = candidateMap[nonStdMake],
                      let topCandidate = candidates.first else { continue }

                group.addTask {
                    let cvsValidation = validateWithCVS(
                        nonStdMake: nonStdMake,
                        canonicalMake: topCandidate.pair,
                        cvsDBPath: cvsDBPath
                    )

                    let temporalValidation = validateWithTemporal(
                        nonStdMake: nonStdMake,
                        canonicalMake: topCandidate.pair,
                        saaqDBPath: saaqDBPath
                    )

                    let aiAnalysis = await analyzeWithAI(
                        nonStdMake: nonStdMake,
                        canonicalMake: topCandidate.pair
                    )

                    // Override logic
                    var shouldStandardize = aiAnalysis.shouldStandardize
                    var reasoning = aiAnalysis.reasoning

                    // CVS override (highest priority)
                    if cvsValidation.confidence >= 0.9 && cvsValidation.decision == "PREVENT" {
                        shouldStandardize = false
                        reasoning = "CVS override: \(cvsValidation.reasoning)"
                    }

                    // Temporal override
                    if temporalValidation.confidence >= 0.8 && temporalValidation.decision == "PREVENT" {
                        shouldStandardize = false
                        reasoning = "Temporal override: \(temporalValidation.reasoning)"
                    }

                    return StandardizationDecision(
                        nonStdMake: nonStdMake,
                        canonicalMake: topCandidate.pair,
                        shouldStandardize: shouldStandardize,
                        reasoning: reasoning,
                        similarity: topCandidate.similarity,
                        cvsValidation: cvsValidation,
                        temporalValidation: temporalValidation,
                        aiAnalysis: aiAnalysis
                    )
                }
            }

            for await decision in group {
                decisions.append(decision)
                let symbol = decision.shouldStandardize ? "✓" : "✗"
                print("  \(symbol) \(decision.nonStdMake.make) → \(decision.canonicalMake?.make ?? "N/A") (\(String(format: "%.2f", decision.similarity)))")
            }
        }
    }

    // STEP 3: Generate report
    print("\n=== STEP 3: Generating Report ===")

    let standardizations = decisions.filter { $0.shouldStandardize }
    let preservations = decisions.filter { !$0.shouldStandardize }

    var report = """
    # AI Make Standardization Report (Pass 1)

    **Date:** \(Date())
    **Database:** \(saaqDBPath)
    **CVS Database:** \(cvsDBPath)

    ## Summary

    - **Canonical makes (2011-2022):** \(canonicalMakes.count)
    - **Non-standard makes (2023-2024):** \(nonStdMakes.count)
    - **Makes with candidates:** \(candidateMap.count)
    - **Standardizations recommended:** \(standardizations.count)
    - **Preservations recommended:** \(preservations.count)
    - **Preservation rate:** \(String(format: "%.1f", Double(preservations.count) / Double(decisions.count) * 100))%

    ---

    ## Standardizations (\(standardizations.count))

    """

    for decision in standardizations.sorted(by: { $0.nonStdMake.make < $1.nonStdMake.make }) {
        report += """
        ### \(decision.nonStdMake.make) → \(decision.canonicalMake?.make ?? "N/A")

        - **Similarity:** \(String(format: "%.2f", decision.similarity))
        - **AI Classification:** \(decision.aiAnalysis?.classification ?? "N/A")
        - **AI Confidence:** \(String(format: "%.2f", decision.aiAnalysis?.confidence ?? 0.0))
        - **AI Reasoning:** \(decision.aiAnalysis?.reasoning ?? "N/A")
        - **CVS Decision:** \(decision.cvsValidation?.decision ?? "N/A") (\(String(format: "%.2f", decision.cvsValidation?.confidence ?? 0.0)))
        - **CVS Reasoning:** \(decision.cvsValidation?.reasoning ?? "N/A")
        - **Temporal Decision:** \(decision.temporalValidation?.decision ?? "N/A") (\(String(format: "%.2f", decision.temporalValidation?.confidence ?? 0.0)))
        - **Temporal Reasoning:** \(decision.temporalValidation?.reasoning ?? "N/A")
        - **Final Reasoning:** \(decision.reasoning)


        """
    }

    report += """
    ---

    ## Preservations (\(preservations.count))

    """

    for decision in preservations.sorted(by: { $0.nonStdMake.make < $1.nonStdMake.make }) {
        report += """
        ### \(decision.nonStdMake.make) (preserved)

        - **Best candidate:** \(decision.canonicalMake?.make ?? "N/A")
        - **Similarity:** \(String(format: "%.2f", decision.similarity))
        - **AI Classification:** \(decision.aiAnalysis?.classification ?? "N/A")
        - **AI Confidence:** \(String(format: "%.2f", decision.aiAnalysis?.confidence ?? 0.0))
        - **AI Reasoning:** \(decision.aiAnalysis?.reasoning ?? "N/A")
        - **CVS Decision:** \(decision.cvsValidation?.decision ?? "N/A") (\(String(format: "%.2f", decision.cvsValidation?.confidence ?? 0.0)))
        - **CVS Reasoning:** \(decision.cvsValidation?.reasoning ?? "N/A")
        - **Temporal Decision:** \(decision.temporalValidation?.decision ?? "N/A") (\(String(format: "%.2f", decision.temporalValidation?.confidence ?? 0.0)))
        - **Temporal Reasoning:** \(decision.temporalValidation?.reasoning ?? "N/A")
        - **Final Reasoning:** \(decision.reasoning)


        """
    }

    // Write report
    try report.write(toFile: reportPath, atomically: true, encoding: .utf8)
    print("  Report written to: \(reportPath)")

    print("\n✅ Make standardization complete!")
    print("   Standardizations: \(standardizations.count)")
    print("   Preservations: \(preservations.count)")
}

// Run
try await main()
