#!/usr/bin/env swift

import Foundation
import FoundationModels
import SQLite3

/// AI-powered make/model standardization using macOS 26 Foundation Models
/// Generates human-reviewable mapping reports with AI reasoning
/// Usage: swift AIStandardizeMakeModel.swift <database_path> <output_report.md>

// MARK: - AI Classification Structures

@Generable
enum DecisionType: String {
    case spellingVariant    // Typo or misspelling (e.g., CIIVIC → CIVIC)
    case newModel          // New 2023+ model, should be preserved
    case truncationVariant // Full name vs truncated (e.g., MODELY → MODEL for schema)
    case uncertain         // Requires human review
}

@Generable
struct VehicleModelAnalysis {
    var decision: DecisionType
    var shouldCorrect: Bool
    var canonicalForm: String?  // If shouldCorrect=true, what to correct to
    var confidence: Double      // 0.0-1.0
    var reasoning: String       // Explanation for human review
}

// MARK: - Data Structures

struct MakeModelPair: Hashable {
    let make: String
    let model: String
    let minModelYear: Int?         // Earliest model year seen for this pair
    let maxModelYear: Int?         // Latest model year seen for this pair
    let minRegistrationYear: Int?  // First year this pair appeared in registration data
    let maxRegistrationYear: Int?  // Last year this pair appeared in registration data

    // Hash and equality based only on make/model for Set operations
    func hash(into hasher: inout Hasher) {
        hasher.combine(make)
        hasher.combine(model)
    }

    static func == (lhs: MakeModelPair, rhs: MakeModelPair) -> Bool {
        return lhs.make == rhs.make && lhs.model == rhs.model
    }
}

struct MakeModelMapping {
    let nonStandard: MakeModelPair
    let canonical: MakeModelPair
    let analysis: VehicleModelAnalysis
    let stringSimilarity: Double
}

// MARK: - Database Operations

func openDatabase(_ path: String) -> OpaquePointer? {
    var db: OpaquePointer?
    if sqlite3_open(path, &db) != SQLITE_OK {
        print("❌ Failed to open database at: \(path)")
        return nil
    }
    return db
}

/// Extract canonical pairs from 2011-2022 with model year ranges
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
    print("✓ Found \(pairs.count) canonical pairs with model year ranges")
    return pairs
}

/// Extract non-standard pairs from 2023-2024 with model year ranges
func extractNonStandardPairs(db: OpaquePointer) -> Set<MakeModelPair> {
    print("\n🔍 Extracting make/model pairs from 2023-2024...")

    let query = """
    SELECT make_enum.name, model_enum.name,
           MIN(vehicles.model_year), MAX(vehicles.model_year),
           MIN(vehicles.year), MAX(vehicles.year)
    FROM vehicles
    JOIN make_enum ON vehicles.make_id = make_enum.id
    JOIN model_enum ON vehicles.model_id = model_enum.id
    WHERE vehicles.year IN (2023, 2024)
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
    print("✓ Found \(pairs.count) unique pairs with model year ranges")
    return pairs
}

// MARK: - String Similarity

func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
    let s1Array = Array(s1)
    let s2Array = Array(s2)
    let m = s1Array.count
    let n = s2Array.count

    var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

    for i in 0...m { matrix[i][0] = i }
    for j in 0...n { matrix[0][j] = j }

    for i in 1...m {
        for j in 1...n {
            let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
            matrix[i][j] = min(
                matrix[i-1][j] + 1,
                matrix[i][j-1] + 1,
                matrix[i-1][j-1] + cost
            )
        }
    }

    return matrix[m][n]
}

func similarityScore(_ s1: String, _ s2: String) -> Double {
    let normalized1 = s1.uppercased()
    let normalized2 = s2.uppercased()

    if normalized1 == normalized2 { return 1.0 }

    let distance = levenshteinDistance(normalized1, normalized2)
    let maxLength = max(normalized1.count, normalized2.count)

    guard maxLength > 0 else { return 0.0 }
    return 1.0 - (Double(distance) / Double(maxLength))
}

// MARK: - Response Parsing

/// Parse AI text response into structured analysis
func parseAIResponse(_ text: String, nonStandard: MakeModelPair, canonical: MakeModelPair, similarity: Double) -> VehicleModelAnalysis {
    // Parse the AI response to extract decision, confidence, and reasoning
    let lowerText = text.lowercased()

    var decision: DecisionType = .uncertain
    var shouldCorrect = false
    var confidence = 0.7  // Default fallback

    // Detect decision type from response
    // Check for classification field first (more reliable)
    if lowerText.contains("classification:") {
        // Look for explicit classification after "classification:" keyword
        if lowerText.contains("spellingvariant") || (lowerText.contains("classification:") && lowerText.range(of: "classification:.*spelling.*variant", options: .regularExpression) != nil) {
            decision = .spellingVariant
            shouldCorrect = true
        } else if lowerText.contains("truncationvariant") || (lowerText.contains("classification:") && lowerText.range(of: "classification:.*truncation", options: .regularExpression) != nil) {
            decision = .truncationVariant
            shouldCorrect = true
        } else if lowerText.contains("newmodel") || (lowerText.contains("classification:") && lowerText.range(of: "classification:.*new.*model", options: .regularExpression) != nil) {
            decision = .newModel
            shouldCorrect = false
        } else if lowerText.contains("classification:") && lowerText.range(of: "classification:.*uncertain", options: .regularExpression) != nil {
            decision = .uncertain
            shouldCorrect = false
        }
    } else {
        // Fallback to keyword search if no explicit classification field
        // Prioritize "new model" checks first (most specific)
        if lowerText.contains("new model") || lowerText.contains("genuinely new") || lowerText.contains("genuinely different") {
            decision = .newModel
            shouldCorrect = false
        } else if lowerText.contains("spelling") && lowerText.contains("variant") {
            decision = .spellingVariant
            shouldCorrect = true
        } else if lowerText.contains("truncation") || lowerText.contains("schema") {
            decision = .truncationVariant
            shouldCorrect = true
        } else if lowerText.contains("uncertain") {
            decision = .uncertain
            shouldCorrect = false
        }
    }

    // Extract confidence from AI response
    // Look for patterns like "Confidence: 0.3", "confidence (0-1)", "Confidence: 1"
    if let confidenceRange = text.range(of: "confidence:?\\s*([0-9]*\\.?[0-9]+)", options: [.regularExpression, .caseInsensitive]) {
        let confidenceText = String(text[confidenceRange])
        // Extract just the number
        if let numberRange = confidenceText.range(of: "[0-9]*\\.?[0-9]+", options: .regularExpression) {
            let numberStr = String(confidenceText[numberRange])
            if let extractedConfidence = Double(numberStr) {
                // Handle both 0.0-1.0 and 0-100 formats
                confidence = extractedConfidence > 1.0 ? extractedConfidence / 100.0 : extractedConfidence
            }
        }
    }

    // Extract reasoning (use the full response as reasoning for now)
    let reasoning = text.trimmingCharacters(in: .whitespacesAndNewlines)

    return VehicleModelAnalysis(
        decision: decision,
        shouldCorrect: shouldCorrect,
        canonicalForm: shouldCorrect ? canonical.model : nil,
        confidence: confidence,
        reasoning: reasoning
    )
}

// MARK: - AI Analysis

/// Find candidate canonical matches based on string similarity
func findCandidateMatches(for pair: MakeModelPair, in canonical: Set<MakeModelPair>) -> [(MakeModelPair, Double)] {
    var candidates: [(MakeModelPair, Double)] = []

    // First filter by make similarity (>= 70%)
    let candidateMakes = canonical.filter { canonical in
        similarityScore(pair.make, canonical.make) >= 0.7
    }

    // Then find best model matches
    for canonicalPair in candidateMakes {
        let makeScore = similarityScore(pair.make, canonicalPair.make)
        let modelScore = similarityScore(pair.model, canonicalPair.model)
        let combinedScore = (makeScore * 0.7) + (modelScore * 0.3)

        // Include if reasonably similar (>= 70%)
        if combinedScore >= 0.70 {
            candidates.append((canonicalPair, combinedScore))
        }
    }

    // Sort by score descending
    return candidates.sorted { $0.1 > $1.1 }
}

/// Use AI to analyze whether a match should be applied
@MainActor
func analyzeWithAI(
    nonStandard: MakeModelPair,
    canonical: MakeModelPair,
    similarity: Double,
    session: LanguageModelSession
) async throws -> VehicleModelAnalysis {

    // Create fresh session for each query to avoid context accumulation
    let freshSession = LanguageModelSession(instructions: "You are analyzing vehicle registration database records for data quality.")

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

    // Use respond API with guided generation
    let response = try await freshSession.respond(to: prompt)

    // For now, parse the text response into our structure
    // In the future, we can use @Generable with guided generation
    return parseAIResponse(response.content, nonStandard: nonStandard, canonical: canonical, similarity: similarity)
}

// MARK: - Batch Processing

func processMappingsWithAI(
    nonStandard: Set<MakeModelPair>,
    canonical: Set<MakeModelPair>,
    session: LanguageModelSession
) async throws -> [MakeModelMapping] {

    print("\n🤖 Analyzing with AI (Foundation Models)...\n")

    // Filter to only pairs needing analysis
    let pairsToAnalyze = Array(nonStandard.filter { !canonical.contains($0) })
    print("   Pairs requiring analysis: \(pairsToAnalyze.count)")
    print("   Skipped (exact matches): \(nonStandard.count - pairsToAnalyze.count)")
    print("   Using 32 parallel sessions for Neural Engine cores...\n")

    let startTime = Date()
    let concurrentSessions = 32  // Match M3 Ultra Neural Engine core count

    // Process with concurrent task group - launch ALL tasks at once
    let mappings = try await withThrowingTaskGroup(of: MakeModelMapping?.self) { group in
        var results: [MakeModelMapping] = []
        var processedCount = 0

        // Submit ALL tasks concurrently (Swift runtime limits actual concurrency)
        for pair in pairsToAnalyze {
            group.addTask {
                // Find candidate matches
                let candidates = findCandidateMatches(for: pair, in: canonical)

                guard let (bestCanonical, bestScore) = candidates.first else {
                    return nil
                }

                // Ask AI to analyze this potential correction
                // Each task creates its own session (thread-safe)
                let analysis = try await analyzeWithAI(
                    nonStandard: pair,
                    canonical: bestCanonical,
                    similarity: bestScore,
                    session: session  // Not used, creates fresh session internally
                )

                // Only return if AI recommends correction
                if analysis.shouldCorrect {
                    return MakeModelMapping(
                        nonStandard: pair,
                        canonical: bestCanonical,
                        analysis: analysis,
                        stringSimilarity: bestScore
                    )
                }
                return nil
            }
        }

        // Collect results as they complete
        for try await mapping in group {
            processedCount += 1

            // Progress update every 10 items (more frequent for parallel)
            if processedCount % 10 == 0 || processedCount == pairsToAnalyze.count {
                let percentage = Double(processedCount) / Double(pairsToAnalyze.count) * 100.0
                let elapsed = Date().timeIntervalSince(startTime)
                let rate = Double(processedCount) / elapsed
                let remaining = Double(pairsToAnalyze.count - processedCount) / rate

                let mins = Int(remaining) / 60
                let secs = Int(remaining) % 60

                print(String(format: "   Progress: %d/%d (%.1f%%) - %.1f pairs/sec - ETA: %dm %ds",
                    processedCount, pairsToAnalyze.count, percentage, rate, mins, secs))
            }

            if let mapping = mapping {
                results.append(mapping)
            }
        }

        return results
    }

    print("\n✅ AI analysis complete!")
    print("   Total pairs analyzed: \(pairsToAnalyze.count)")
    print("   Corrections recommended: \(mappings.count)")

    return mappings
}

// MARK: - Report Generation

func generateMarkdownReport(_ mappings: [MakeModelMapping], to path: String) {
    var lines: [String] = []

    lines.append("# AI-Powered Make/Model Standardization Report")
    lines.append("")
    lines.append("Generated: \(Date())")
    lines.append("Analysis method: Foundation Models (macOS 26)")
    lines.append("Total corrections recommended: \(mappings.count)")
    lines.append("")

    // Group by decision type
    let byDecision = Dictionary(grouping: mappings) { $0.analysis.decision }

    lines.append("## Summary by Decision Type")
    lines.append("")
    lines.append("| Decision Type | Count | Description |")
    lines.append("|---------------|-------|-------------|")

    let spellingCount = byDecision[.spellingVariant]?.count ?? 0
    let truncationCount = byDecision[.truncationVariant]?.count ?? 0
    let uncertainCount = byDecision[.uncertain]?.count ?? 0

    lines.append("| Spelling Variant | \(spellingCount) | Typos and misspellings |")
    lines.append("| Truncation Variant | \(truncationCount) | Full names vs. 5-char schema |")
    lines.append("| Uncertain | \(uncertainCount) | Requires human review |")
    lines.append("")

    // Spelling Variants section
    lines.append("## Spelling Variants (High Confidence Typos)")
    lines.append("")
    lines.append("These appear to be clear typos or misspellings that should be corrected.")
    lines.append("")
    lines.append("| Non-Standard Make | Non-Standard Model | → | Canonical Make | Canonical Model | Similarity | AI Confidence | Reasoning |")
    lines.append("|-------------------|-------------------|---|----------------|----------------|------------|---------------|-----------|")

    let spellingVariants = byDecision[.spellingVariant] ?? []
    for mapping in spellingVariants.sorted(by: { $0.analysis.confidence > $1.analysis.confidence }) {
        lines.append("| \(mapping.nonStandard.make) | \(mapping.nonStandard.model) | → | \(mapping.canonical.make) | \(mapping.canonical.model) | \(String(format: "%.1f%%", mapping.stringSimilarity * 100)) | \(String(format: "%.0f%%", mapping.analysis.confidence * 100)) | \(mapping.analysis.reasoning) |")
    }

    // Truncation Variants section
    lines.append("")
    lines.append("## Truncation Variants (Schema Compliance)")
    lines.append("")
    lines.append("These are full model names being standardized to 5-character SAAQ schema format.")
    lines.append("")
    lines.append("| Non-Standard Make | Non-Standard Model | → | Canonical Make | Canonical Model | Similarity | AI Confidence | Reasoning |")
    lines.append("|-------------------|-------------------|---|----------------|----------------|------------|---------------|-----------|")

    let truncationVariants = byDecision[.truncationVariant] ?? []
    for mapping in truncationVariants.sorted(by: { $0.analysis.confidence > $1.analysis.confidence }) {
        lines.append("| \(mapping.nonStandard.make) | \(mapping.nonStandard.model) | → | \(mapping.canonical.make) | \(mapping.canonical.model) | \(String(format: "%.1f%%", mapping.stringSimilarity * 100)) | \(String(format: "%.0f%%", mapping.analysis.confidence * 100)) | \(mapping.analysis.reasoning) |")
    }

    // Uncertain cases section
    lines.append("")
    lines.append("## Uncertain Cases - HUMAN REVIEW REQUIRED ⚠️")
    lines.append("")
    lines.append("These cases require manual review before applying corrections.")
    lines.append("")
    lines.append("| Non-Standard Make | Non-Standard Model | → | Canonical Make | Canonical Model | Similarity | AI Confidence | Reasoning |")
    lines.append("|-------------------|-------------------|---|----------------|----------------|------------|---------------|-----------|")

    let uncertainCases = byDecision[.uncertain] ?? []
    for mapping in uncertainCases.sorted(by: { $0.stringSimilarity > $1.stringSimilarity }) {
        lines.append("| \(mapping.nonStandard.make) | \(mapping.nonStandard.model) | → | \(mapping.canonical.make) | \(mapping.canonical.model) | \(String(format: "%.1f%%", mapping.stringSimilarity * 100)) | \(String(format: "%.0f%%", mapping.analysis.confidence * 100)) | \(mapping.analysis.reasoning) |")
    }

    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## Next Steps")
    lines.append("")
    lines.append("1. **Review this report** - Especially the Uncertain Cases section")
    lines.append("2. **Verify new models** - Check that genuinely new 2023+ models were NOT corrected")
    lines.append("3. **Apply corrections** - Use `ApplyMakeModelCorrections.swift` with this report")
    lines.append("4. **Test import** - Import corrected CSV into clean database")
    lines.append("")

    let content = lines.joined(separator: "\n")

    do {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        print("\n📄 Report written to: \(path)")
    } catch {
        print("❌ Failed to write report: \(error)")
    }
}

// MARK: - Main Script

@MainActor
func main() async {
    let args = CommandLine.arguments

    guard args.count >= 3 else {
        print("Usage: swift AIStandardizeMakeModel.swift <database_path> <output_report.md>")
        print("")
        print("AI-powered make/model standardization using macOS 26 Foundation Models.")
        print("Generates human-reviewable mapping report with AI reasoning.")
        print("")
        print("Requirements:")
        print("  - macOS 26.0+ (Tahoe)")
        print("  - Apple Silicon (M1/M2/M3)")
        print("")
        print("Example:")
        print("  swift AIStandardizeMakeModel.swift \\")
        print("    ~/Library/Containers/.../saaq_data.sqlite \\")
        print("    ~/Desktop/AI-MakeModel-Report.md")
        exit(1)
    }

    let dbPath = args[1]
    let reportPath = args[2]

    print("🤖 AI-Powered Make/Model Standardization")
    print("   Database: \(dbPath)")
    print("   Report: \(reportPath)")
    print("")

    // Open database
    guard let db = openDatabase(dbPath) else {
        exit(1)
    }
    defer { sqlite3_close(db) }

    // Extract data
    let canonical = extractCanonicalPairs(db: db)
    let nonStandard = extractNonStandardPairs(db: db)

    // Check Foundation Model availability
    print("\n🧠 Checking Foundation Model availability...")
    let systemModel = SystemLanguageModel.default

    guard case .available = systemModel.availability else {
        print("❌ Foundation Model not available")
        switch systemModel.availability {
        case .unavailable(.deviceNotEligible):
            print("   Device does not support Apple Intelligence")
        case .unavailable(.appleIntelligenceNotEnabled):
            print("   Apple Intelligence is not enabled in Settings")
        case .unavailable(.modelNotReady):
            print("   Model is downloading or not ready yet")
        default:
            print("   Unknown availability issue")
        }
        exit(1)
    }

    print("✓ Foundation Model available")

    // Create session with minimal instructions
    let instructions = "Classify vehicle make/model variants. Be conservative."

    let session = LanguageModelSession(instructions: instructions)
    print("✓ Session created")

    do {
        // Process with AI
        let mappings = try await processMappingsWithAI(
            nonStandard: nonStandard,
            canonical: canonical,
            session: session
        )

        // Generate report
        generateMarkdownReport(mappings, to: reportPath)

        print("\n✅ Complete! Review the report before applying corrections.")

    } catch {
        print("❌ AI analysis failed: \(error)")
        exit(1)
    }
}

// Run
await main()
