#!/usr/bin/env swift

import Foundation
import SQLite3

/// Standardizes vehicle make/model values in 2023-2024 data using canonical values from 2011-2022
/// Usage: swift StandardizeMakeModel.swift <database_path> [--analyze-only]

// MARK: - String Distance Algorithm

/// Calculate Levenshtein distance between two strings
func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
    let s1Array = Array(s1)
    let s2Array = Array(s2)
    let m = s1Array.count
    let n = s2Array.count

    var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

    for i in 0...m {
        matrix[i][0] = i
    }
    for j in 0...n {
        matrix[0][j] = j
    }

    for i in 1...m {
        for j in 1...n {
            let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
            matrix[i][j] = min(
                matrix[i-1][j] + 1,      // deletion
                matrix[i][j-1] + 1,      // insertion
                matrix[i-1][j-1] + cost  // substitution
            )
        }
    }

    return matrix[m][n]
}

/// Calculate normalized similarity score (0.0 = no match, 1.0 = exact match)
func similarityScore(_ s1: String, _ s2: String) -> Double {
    let normalized1 = s1.uppercased()
    let normalized2 = s2.uppercased()

    if normalized1 == normalized2 {
        return 1.0
    }

    let distance = levenshteinDistance(normalized1, normalized2)
    let maxLength = max(normalized1.count, normalized2.count)

    guard maxLength > 0 else { return 0.0 }

    return 1.0 - (Double(distance) / Double(maxLength))
}

// MARK: - Database Operations

struct MakeModelPair: Hashable {
    let make: String
    let model: String
}

/// Open SQLite database connection
func openDatabase(_ path: String) -> OpaquePointer? {
    var db: OpaquePointer?

    if sqlite3_open(path, &db) != SQLITE_OK {
        print("❌ Failed to open database at: \(path)")
        return nil
    }

    return db
}

/// Extract all unique make/model pairs from 2011-2022 (canonical set)
func extractCanonicalPairs(db: OpaquePointer) -> Set<MakeModelPair> {
    print("   Querying 2011-2022 data...")

    // Use a simpler query without DISTINCT in the main query for better performance
    let query = """
    SELECT make_enum.name, model_enum.name
    FROM vehicles
    JOIN make_enum ON vehicles.make_id = make_enum.id
    JOIN model_enum ON vehicles.model_id = model_enum.id
    WHERE vehicles.year BETWEEN 2011 AND 2022
      AND vehicles.make_id IS NOT NULL
      AND vehicles.model_id IS NOT NULL
    """

    var statement: OpaquePointer?
    var pairs = Set<MakeModelPair>()
    var count = 0

    if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
        while sqlite3_step(statement) == SQLITE_ROW {
            let make = String(cString: sqlite3_column_text(statement, 0))
            let model = String(cString: sqlite3_column_text(statement, 1))

            if !make.isEmpty && !model.isEmpty {
                pairs.insert(MakeModelPair(make: make, model: model))
            }

            count += 1
            if count % 1000000 == 0 {
                print("   Processed \(count/1000000)M records, found \(pairs.count) unique pairs...")
            }
        }
    }

    sqlite3_finalize(statement)

    print("📋 Extracted \(pairs.count) canonical make/model pairs from 2011-2022 (\(count) total records)")
    return pairs
}

/// Extract all unique make/model pairs from 2023-2024 (needs standardization)
func extractNonStandardPairs(db: OpaquePointer) -> Set<MakeModelPair> {
    print("   Querying 2023-2024 data...")

    let query = """
    SELECT make_enum.name, model_enum.name
    FROM vehicles
    JOIN make_enum ON vehicles.make_id = make_enum.id
    JOIN model_enum ON vehicles.model_id = model_enum.id
    WHERE vehicles.year IN (2023, 2024)
      AND vehicles.make_id IS NOT NULL
      AND vehicles.model_id IS NOT NULL
    """

    var statement: OpaquePointer?
    var pairs = Set<MakeModelPair>()
    var count = 0

    if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
        while sqlite3_step(statement) == SQLITE_ROW {
            let make = String(cString: sqlite3_column_text(statement, 0))
            let model = String(cString: sqlite3_column_text(statement, 1))

            if !make.isEmpty && !model.isEmpty {
                pairs.insert(MakeModelPair(make: make, model: model))
            }

            count += 1
            if count % 100000 == 0 {
                print("   Processed \(count/1000)k records, found \(pairs.count) unique pairs...")
            }
        }
    }

    sqlite3_finalize(statement)

    print("🔍 Found \(pairs.count) unique make/model pairs in 2023-2024 (\(count) total records)")
    return pairs
}

// MARK: - Matching Algorithm

struct MakeModelMatch {
    let nonStandard: MakeModelPair
    let canonical: MakeModelPair
    let makeScore: Double
    let modelScore: Double
    let combinedScore: Double
    let isExactMatch: Bool
}

/// Find best canonical match for a non-standard make/model pair
func findBestMatch(for pair: MakeModelPair, in canonicalSet: Set<MakeModelPair>) -> MakeModelMatch? {
    var bestMatch: MakeModelMatch?
    var bestScore = 0.0

    // First pass: look for makes that match closely
    let candidateMakes = canonicalSet.filter { canonical in
        similarityScore(pair.make, canonical.make) >= 0.7
    }

    // Second pass: for each candidate make, find best model match
    for canonical in candidateMakes {
        let makeScore = similarityScore(pair.make, canonical.make)
        let modelScore = similarityScore(pair.model, canonical.model)

        // Weight make more heavily (70%) than model (30%) since make is usually more reliable
        let combinedScore = (makeScore * 0.7) + (modelScore * 0.3)

        if combinedScore > bestScore {
            bestScore = combinedScore
            let isExact = (pair.make.uppercased() == canonical.make.uppercased() &&
                          pair.model.uppercased() == canonical.model.uppercased())
            bestMatch = MakeModelMatch(
                nonStandard: pair,
                canonical: canonical,
                makeScore: makeScore,
                modelScore: modelScore,
                combinedScore: combinedScore,
                isExactMatch: isExact
            )
        }
    }

    return bestMatch
}

// MARK: - Analysis and Mapping

/// Generate mapping from non-standard to canonical pairs
func generateMapping(nonStandard: Set<MakeModelPair>, canonical: Set<MakeModelPair>) -> [MakeModelMatch] {
    var matches: [MakeModelMatch] = []
    var unmatchedCount = 0

    print("\n🔄 Generating mappings...")

    for (index, pair) in nonStandard.enumerated() {
        if (index + 1) % 100 == 0 {
            print("   Processed \(index + 1)/\(nonStandard.count)...")
        }

        if let match = findBestMatch(for: pair, in: canonical) {
            // Only include if similarity is reasonable (>= 70%)
            if match.combinedScore >= 0.70 {
                matches.append(match)
            } else {
                unmatchedCount += 1
            }
        } else {
            unmatchedCount += 1
        }
    }

    print("✅ Generated \(matches.count) mappings")
    if unmatchedCount > 0 {
        print("⚠️  \(unmatchedCount) pairs could not be matched with confidence")
    }

    return matches
}

/// Write mapping report to file
func writeReport(_ matches: [MakeModelMatch], to path: String) {
    var lines: [String] = []

    lines.append("# Vehicle Make/Model Standardization Report")
    lines.append("")
    lines.append("Generated: \(Date())")
    lines.append("Total mappings: \(matches.count)")
    lines.append("")

    // Group by match quality
    let exactMatches = matches.filter { $0.isExactMatch }
    let highConfidence = matches.filter { !$0.isExactMatch && $0.combinedScore >= 0.90 }
    let mediumConfidence = matches.filter { $0.combinedScore >= 0.75 && $0.combinedScore < 0.90 }
    let lowConfidence = matches.filter { $0.combinedScore >= 0.70 && $0.combinedScore < 0.75 }

    lines.append("## Summary")
    lines.append("")
    lines.append("- Exact matches: \(exactMatches.count)")
    lines.append("- High confidence (90%+): \(highConfidence.count)")
    lines.append("- Medium confidence (75-89%): \(mediumConfidence.count)")
    lines.append("- Low confidence (70-74%): \(lowConfidence.count)")
    lines.append("")

    // Write non-exact matches for review
    lines.append("## High Confidence Mappings (90%+)")
    lines.append("")
    lines.append("| Non-Standard Make | Non-Standard Model | → | Canonical Make | Canonical Model | Score |")
    lines.append("|-------------------|-------------------|---|----------------|----------------|-------|")

    for match in highConfidence.sorted(by: { $0.combinedScore > $1.combinedScore }) {
        lines.append("| \(match.nonStandard.make) | \(match.nonStandard.model) | → | \(match.canonical.make) | \(match.canonical.model) | \(String(format: "%.1f%%", match.combinedScore * 100)) |")
    }

    lines.append("")
    lines.append("## Medium Confidence Mappings (75-89%)")
    lines.append("")
    lines.append("| Non-Standard Make | Non-Standard Model | → | Canonical Make | Canonical Model | Score |")
    lines.append("|-------------------|-------------------|---|----------------|----------------|-------|")

    for match in mediumConfidence.sorted(by: { $0.combinedScore > $1.combinedScore }) {
        lines.append("| \(match.nonStandard.make) | \(match.nonStandard.model) | → | \(match.canonical.make) | \(match.canonical.model) | \(String(format: "%.1f%%", match.combinedScore * 100)) |")
    }

    lines.append("")
    lines.append("## Low Confidence Mappings (70-74%) - REVIEW REQUIRED")
    lines.append("")
    lines.append("| Non-Standard Make | Non-Standard Model | → | Canonical Make | Canonical Model | Score |")
    lines.append("|-------------------|-------------------|---|----------------|----------------|-------|")

    for match in lowConfidence.sorted(by: { $0.combinedScore > $1.combinedScore }) {
        lines.append("| \(match.nonStandard.make) | \(match.nonStandard.model) | → | \(match.canonical.make) | \(match.canonical.model) | \(String(format: "%.1f%%", match.combinedScore * 100)) |")
    }

    let content = lines.joined(separator: "\n")

    do {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        print("📄 Report written to: \(path)")
    } catch {
        print("❌ Failed to write report: \(error)")
    }
}

/// Write SQL update script
func writeSQLScript(_ matches: [MakeModelMatch], to path: String, minConfidence: Double = 0.90) {
    var lines: [String] = []

    lines.append("-- Vehicle Make/Model Standardization SQL")
    lines.append("-- Generated: \(Date())")
    lines.append("-- Minimum confidence: \(String(format: "%.0f%%", minConfidence * 100))")
    lines.append("")
    lines.append("-- NOTE: This script updates the enumeration tables to consolidate variants.")
    lines.append("-- The integer-based schema means we update enum IDs, not individual vehicle records.")
    lines.append("")
    lines.append("BEGIN TRANSACTION;")
    lines.append("")

    let highConfidenceMatches = matches.filter { $0.combinedScore >= minConfidence && !$0.isExactMatch }

    for match in highConfidenceMatches {
        let escapedNonStdMake = match.nonStandard.make.replacingOccurrences(of: "'", with: "''")
        let escapedNonStdModel = match.nonStandard.model.replacingOccurrences(of: "'", with: "''")
        let escapedCanonicalMake = match.canonical.make.replacingOccurrences(of: "'", with: "''")
        let escapedCanonicalModel = match.canonical.model.replacingOccurrences(of: "'", with: "''")

        lines.append("-- \(match.nonStandard.make) / \(match.nonStandard.model) → \(match.canonical.make) / \(match.canonical.model) (\(String(format: "%.1f%%", match.combinedScore * 100)))")
        lines.append("-- Update vehicles to use canonical make/model IDs")
        lines.append("UPDATE vehicles")
        lines.append("SET make_id = (SELECT id FROM make_enum WHERE name = '\(escapedCanonicalMake)'),")
        lines.append("    model_id = (SELECT id FROM model_enum WHERE name = '\(escapedCanonicalModel)')")
        lines.append("WHERE make_id = (SELECT id FROM make_enum WHERE name = '\(escapedNonStdMake)')")
        lines.append("  AND model_id = (SELECT id FROM model_enum WHERE name = '\(escapedNonStdModel)')")
        lines.append("  AND year IN (2023, 2024);")
        lines.append("")
        lines.append("-- Delete the now-unused variant entries from enumeration tables")
        lines.append("DELETE FROM make_enum WHERE name = '\(escapedNonStdMake)' AND id NOT IN (SELECT DISTINCT make_id FROM vehicles);")
        lines.append("DELETE FROM model_enum WHERE name = '\(escapedNonStdModel)' AND id NOT IN (SELECT DISTINCT model_id FROM vehicles);")
        lines.append("")
    }

    lines.append("COMMIT;")
    lines.append("")
    lines.append("-- Total make/model pair updates: \(highConfidenceMatches.count)")

    let content = lines.joined(separator: "\n")

    do {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        print("📝 SQL script written to: \(path)")
        print("   Contains \(highConfidenceMatches.count) make/model pair updates")
    } catch {
        print("❌ Failed to write SQL script: \(error)")
    }
}

// MARK: - Main Script

func main() {
    let args = CommandLine.arguments

    guard args.count >= 2 else {
        print("Usage: swift StandardizeMakeModel.swift <database_path> [--analyze-only]")
        print("")
        print("Standardizes vehicle make/model values in 2023-2024 data.")
        print("")
        print("Options:")
        print("  --analyze-only    Generate reports only, do not create SQL script")
        exit(1)
    }

    let dbPath = args[1]
    let analyzeOnly = args.contains("--analyze-only")

    print("🚗 Vehicle Make/Model Standardization Tool")
    print("   Database: \(dbPath)")
    print("")

    // Open database
    guard let db = openDatabase(dbPath) else {
        exit(1)
    }
    defer { sqlite3_close(db) }

    // Extract canonical pairs from 2011-2022
    let canonical = extractCanonicalPairs(db: db)

    // Extract non-standard pairs from 2023-2024
    let nonStandard = extractNonStandardPairs(db: db)

    // Generate mappings
    let matches = generateMapping(nonStandard: nonStandard, canonical: canonical)

    // Write report
    let reportPath = (dbPath as NSString).deletingLastPathComponent + "/MakeModelStandardization-Report.md"
    writeReport(matches, to: reportPath)

    // Write SQL script (only high-confidence matches >= 90%)
    if !analyzeOnly {
        let sqlPath = (dbPath as NSString).deletingLastPathComponent + "/MakeModelStandardization-Updates.sql"
        writeSQLScript(matches, to: sqlPath, minConfidence: 0.90)

        print("")
        print("✅ Complete!")
        print("")
        print("Next steps:")
        print("1. Review the report: \(reportPath)")
        print("2. Review the SQL script: \(sqlPath)")
        print("3. Back up your database")
        print("4. Execute the SQL script: sqlite3 <database> < \(sqlPath)")
    } else {
        print("")
        print("✅ Analysis complete!")
        print("")
        print("Review the report: \(reportPath)")
    }
}

// Run the script
main()
