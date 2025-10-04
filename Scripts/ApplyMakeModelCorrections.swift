#!/usr/bin/env swift

import Foundation

/// Applies make/model standardization corrections to CSV files
/// Usage: swift ApplyMakeModelCorrections.swift <mapping_report.md> <input.csv> <output.csv> [min_confidence]

// MARK: - CSV Parsing

/// Parse CSV line respecting quoted fields with delimiters inside
func parseCSVLine(_ line: String, delimiter: Character = ",") -> [String] {
    var fields: [String] = []
    var currentField = ""
    var inQuotes = false

    for char in line {
        if char == "\"" {
            inQuotes.toggle()
        } else if char == delimiter && !inQuotes {
            fields.append(currentField.trimmingCharacters(in: .whitespaces))
            currentField = ""
        } else {
            currentField.append(char)
        }
    }

    // Add final field
    fields.append(currentField.trimmingCharacters(in: .whitespaces))

    return fields
}

// MARK: - Mapping Extraction

struct MakeModelCorrection {
    let nonStandardMake: String
    let nonStandardModel: String
    let canonicalMake: String
    let canonicalModel: String
    let confidence: Double
}

/// Extract corrections from markdown report
func extractCorrections(from reportPath: String, minConfidence: Double) -> [MakeModelCorrection] {
    guard let content = try? String(contentsOfFile: reportPath, encoding: .utf8) else {
        print("❌ Failed to read report file: \(reportPath)")
        return []
    }

    var corrections: [MakeModelCorrection] = []
    let lines = content.components(separatedBy: .newlines)

    for line in lines {
        // Look for table rows with corrections
        // Format: | NonStd Make | NonStd Model | → | Canon Make | Canon Model | 95.0% |
        guard line.hasPrefix("|"), line.contains("→") else { continue }

        let parts = line.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }

        // Split removes empty strings, so we get: [Make, Model, →, CanonMake, CanonModel, Score]
        guard parts.count >= 6 else { continue }

        let nonStdMake = parts[0]
        let nonStdModel = parts[1]
        // parts[2] is the arrow "→"
        let canonMake = parts[3]
        let canonModel = parts[4]
        let scoreText = parts[5].replacingOccurrences(of: "%", with: "")

        guard let score = Double(scoreText) else { continue }
        let confidence = score / 100.0

        // Only include if meets minimum confidence
        if confidence >= minConfidence {
            corrections.append(MakeModelCorrection(
                nonStandardMake: nonStdMake,
                nonStandardModel: nonStdModel,
                canonicalMake: canonMake,
                canonicalModel: canonModel,
                confidence: confidence
            ))
        }
    }

    print("📋 Loaded \(corrections.count) corrections (min confidence: \(Int(minConfidence * 100))%)")
    return corrections
}

// MARK: - CSV Processing

/// Apply corrections to CSV file
func applyCorrectionToCSV(inputPath: String, outputPath: String, corrections: [MakeModelCorrection]) {
    // Read input file
    guard let inputContent = try? String(contentsOfFile: inputPath, encoding: .utf8) else {
        print("❌ Failed to read input CSV: \(inputPath)")
        return
    }

    let lines = inputContent.components(separatedBy: .newlines)
    guard !lines.isEmpty else {
        print("❌ Input CSV is empty")
        return
    }

    // Parse header to find MARQ_VEH and MODEL_VEH columns
    let headerLine = lines[0]
    let headers = parseCSVLine(headerLine)

    guard let makeIndex = headers.firstIndex(where: { $0.uppercased().contains("MARQ") }),
          let modelIndex = headers.firstIndex(where: { $0.uppercased().contains("MODEL") }) else {
        print("❌ Could not find MARQ_VEH and MODEL_VEH columns in header")
        print("   Headers found: \(headers.joined(separator: ", "))")
        return
    }

    print("✓ Found columns: MARQ_VEH at index \(makeIndex), MODEL_VEH at index \(modelIndex)")

    // Build lookup dictionary for fast corrections (make+model → canonical pair)
    var correctionLookup: [String: (String, String)] = [:]
    for correction in corrections {
        let key = "\(correction.nonStandardMake)|\(correction.nonStandardModel)".uppercased()
        correctionLookup[key] = (correction.canonicalMake, correction.canonicalModel)
    }

    // Process data rows
    var outputLines = [headerLine]
    var correctedCount = 0
    var totalRecords = 0

    for (index, line) in lines.dropFirst().enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }

        var fields = parseCSVLine(trimmed)
        guard fields.count == headers.count else {
            print("⚠️  Line \(index + 2): field count mismatch (\(fields.count) vs \(headers.count))")
            continue
        }

        totalRecords += 1

        // Check if this make/model needs correction
        let currentMake = fields[makeIndex].replacingOccurrences(of: "\"", with: "")
        let currentModel = fields[modelIndex].replacingOccurrences(of: "\"", with: "")
        let lookupKey = "\(currentMake)|\(currentModel)".uppercased()

        if let (canonicalMake, canonicalModel) = correctionLookup[lookupKey] {
            // Apply correction
            fields[makeIndex] = "\"\(canonicalMake)\""
            fields[modelIndex] = "\"\(canonicalModel)\""
            correctedCount += 1
        }

        // Rebuild line
        outputLines.append(fields.joined(separator: ","))

        if (index + 1) % 100000 == 0 {
            print("   Processed \(index + 1) records, corrected \(correctedCount)...")
        }
    }

    // Write output
    let outputContent = outputLines.joined(separator: "\n")
    do {
        try outputContent.write(toFile: outputPath, atomically: true, encoding: .utf8)
        print("")
        print("✅ Corrections applied!")
        print("   Total records: \(totalRecords)")
        print("   Corrected: \(correctedCount)")
        print("   Output: \(outputPath)")
    } catch {
        print("❌ Failed to write output: \(error)")
    }
}

// MARK: - Main Script

func main() {
    let args = CommandLine.arguments

    guard args.count >= 4 else {
        print("Usage: swift ApplyMakeModelCorrections.swift <mapping_report.md> <input.csv> <output.csv> [min_confidence]")
        print("")
        print("Applies make/model standardization corrections from a report to a CSV file.")
        print("")
        print("Arguments:")
        print("  mapping_report.md  - Report generated by StandardizeMakeModel script")
        print("  input.csv          - CSV file to correct (normalized 2023/2024 data)")
        print("  output.csv         - Output path for corrected CSV")
        print("  min_confidence     - Minimum confidence (0.0-1.0, default: 0.90)")
        print("")
        print("Example:")
        print("  swift ApplyMakeModelCorrections.swift \\")
        print("    MakeModelStandardization-Report.md \\")
        print("    Vehicule_En_Circulation_2023.csv \\")
        print("    Vehicule_En_Circulation_2023_corrected.csv \\")
        print("    0.90")
        exit(1)
    }

    let reportPath = args[1]
    let inputPath = args[2]
    let outputPath = args[3]
    let minConfidence = args.count > 4 ? Double(args[4]) ?? 0.90 : 0.90

    print("🔧 Make/Model Correction Tool")
    print("   Report: \(reportPath)")
    print("   Input CSV: \(inputPath)")
    print("   Output CSV: \(outputPath)")
    print("   Min confidence: \(Int(minConfidence * 100))%")
    print("")

    // Extract corrections from report
    let corrections = extractCorrections(from: reportPath, minConfidence: minConfidence)

    guard !corrections.isEmpty else {
        print("❌ No corrections found in report")
        exit(1)
    }

    // Apply corrections to CSV
    applyCorrectionToCSV(inputPath: inputPath, outputPath: outputPath, corrections: corrections)
}

// Run the script
main()
