#!/usr/bin/env swift

import Foundation

/// Normalizes SAAQ CSV files from 2023-2024 format to standard 2011-2022 format
/// Usage: swift NormalizeCSV.swift input.csv output.csv [year] [d001_path]

// MARK: - Geographic Lookup

/// Geographic entity with hierarchical relationships
struct GeographicEntity {
    let code: String
    let name: String
    let regionCode: String
    let mrcCode: String
}

/// Loads geographic lookup data from d001 file
func loadGeographicLookup(from d001Path: String) -> [String: GeographicEntity] {
    guard let content = try? String(contentsOfFile: d001Path, encoding: .isoLatin1) else {
        print("⚠️  Could not load d001 file from: \(d001Path)")
        return [:]
    }

    var lookup: [String: GeographicEntity] = [:]
    let lines = content.components(separatedBy: .newlines)

    for line in lines {
        // Skip header and empty lines
        guard !line.isEmpty, line.count >= 900, !line.hasPrefix("0") else { continue }

        // Extract municipality code (positions 2-6)
        let codeStart = line.index(line.startIndex, offsetBy: 1)
        let codeEnd = line.index(line.startIndex, offsetBy: 6)
        let code = String(line[codeStart..<codeEnd]).trimmingCharacters(in: .whitespaces)

        // Extract municipality name (positions 9-66)
        let nameStart = line.index(line.startIndex, offsetBy: 8)
        let nameEnd = line.index(line.startIndex, offsetBy: 66)
        let name = String(line[nameStart..<nameEnd]).trimmingCharacters(in: .whitespaces)

        // Extract region code (positions 305-306 based on d001 spec)
        let regionStart = line.index(line.startIndex, offsetBy: 304)
        let regionEnd = line.index(line.startIndex, offsetBy: 306)
        let regionCode = String(line[regionStart..<regionEnd]).trimmingCharacters(in: .whitespaces)

        // Extract MRC code (positions 245-247 based on d001 spec)
        let mrcStart = line.index(line.startIndex, offsetBy: 244)
        let mrcEnd = line.index(line.startIndex, offsetBy: 247)
        let mrcCode = String(line[mrcStart..<mrcEnd]).trimmingCharacters(in: .whitespaces)

        // Skip invalid entries
        guard !code.isEmpty, !name.isEmpty else { continue }

        // Normalize the name for lookup
        let normalizedName = normalizeMunicipalityName(name)

        lookup[normalizedName] = GeographicEntity(
            code: code,
            name: name,
            regionCode: regionCode,
            mrcCode: mrcCode
        )
    }

    print("📍 Loaded \(lookup.count) municipalities from d001 file")
    return lookup
}

/// Normalize municipality name for consistent lookups
func normalizeMunicipalityName(_ name: String) -> String {
    var normalized = name.lowercased()

    // Remove common prefixes/suffixes that might vary
    normalized = normalized.replacingOccurrences(of: "municipalité de ", with: "")
    normalized = normalized.replacingOccurrences(of: "ville de ", with: "")

    // Strip accents and convert to ASCII for robust matching
    normalized = stripAccents(normalized)

    return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Strip accents from French characters to pure ASCII
func stripAccents(_ text: String) -> String {
    // Map accented characters to ASCII equivalents
    let accentMap: [String: String] = [
        "à": "a", "á": "a", "â": "a", "ã": "a", "ä": "a", "å": "a",
        "è": "e", "é": "e", "ê": "e", "ë": "e",
        "ì": "i", "í": "i", "î": "i", "ï": "i",
        "ò": "o", "ó": "o", "ô": "o", "õ": "o", "ö": "o",
        "ù": "u", "ú": "u", "û": "u", "ü": "u",
        "ç": "c",
        "ñ": "n",
        "ÿ": "y",
        "æ": "ae",
        "œ": "oe"
    ]

    var result = text
    for (accented, plain) in accentMap {
        result = result.replacingOccurrences(of: accented, with: plain)
    }

    return result
}

// MARK: - Region Mapping

/// Maps region codes to standard "Region Name (Code)" format
let regionMapping: [String: String] = [
    "1": "Bas-Saint-Laurent (01)",
    "01": "Bas-Saint-Laurent (01)",
    "2": "Saguenay–Lac-Saint-Jean (02)",
    "02": "Saguenay–Lac-Saint-Jean (02)",
    "3": "Capitale-Nationale (03)",
    "03": "Capitale-Nationale (03)",
    "4": "Mauricie (04)",
    "04": "Mauricie (04)",
    "5": "Estrie (05)",
    "05": "Estrie (05)",
    "6": "Montréal (06)",
    "06": "Montréal (06)",
    "7": "Outaouais (07)",
    "07": "Outaouais (07)",
    "8": "Abitibi-Témiscamingue (08)",
    "08": "Abitibi-Témiscamingue (08)",
    "9": "Côte-Nord (09)",
    "09": "Côte-Nord (09)",
    "10": "Nord-du-Québec (10)",
    "11": "Gaspésie–Îles-de-la-Madeleine (11)",
    "12": "Chaudière-Appalaches (12)",
    "13": "Laval (13)",
    "14": "Lanaudière (14)",
    "15": "Laurentides (15)",
    "16": "Montérégie (16)",
    "17": "Centre-du-Québec (17)"
]

// MARK: - Encoding Fixes

/// Fix common French character encoding issues (UTF-8 bytes read as ISO-8859-1)
func fixEncoding(_ text: String) -> String {
    let replacements = [
        // Header corruption
        "È": "é",
        "Ë": "è",
        "AnnÈe": "Année",
        "vÈhicule": "véhicule",
        "ModËle": "Modèle",
        "MunicipalitÈ": "Municipalité",
        "RÈgion": "Région",
        // Data corruption (UTF-8 bytes misinterpreted as ISO-8859-1)
        "Ã©": "é",   // é
        "Ã¨": "è",   // è
        "Ã": "à",   // à
        "Ã´": "ô",   // ô
        "Ã®": "î",   // î
        "Ã»": "û",   // û
        "Ã§": "ç",   // ç
        "Ã«": "ë"    // ë
    ]

    var fixed = text
    for (corrupted, correct) in replacements {
        fixed = fixed.replacingOccurrences(of: corrupted, with: correct)
    }
    return fixed
}

// MARK: - Year Extraction

/// Extract year from "YYYYMM" or "YYYY" format
func extractYear(_ yearString: String) -> String? {
    // Match 4-digit year at start: YYYY or YYYYMM
    guard let regex = try? NSRegularExpression(pattern: "^(\\d{4})") else {
        return nil
    }

    let range = NSRange(yearString.startIndex..., in: yearString)
    if let match = regex.firstMatch(in: yearString, range: range),
       let yearRange = Range(match.range(at: 1), in: yearString) {
        return String(yearString[yearRange])
    }
    return nil
}

// MARK: - CSV Parsing

/// Parse CSV line respecting quoted fields with delimiters inside
func parseCSVLine(_ line: String, delimiter: Character) -> [String] {
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

/// Detect delimiter (semicolon for 2023/2024, comma for standard)
func detectDelimiter(_ line: String) -> Character {
    // Count semicolons vs commas outside quotes
    var inQuotes = false
    var semicolons = 0
    var commas = 0

    for char in line {
        if char == "\"" {
            inQuotes.toggle()
        } else if !inQuotes {
            if char == ";" { semicolons += 1 }
            if char == "," { commas += 1 }
        }
    }

    return semicolons > commas ? ";" : ","
}

// MARK: - Field Normalization

struct CSVNormalizer {
    let inputDelimiter: Character
    let headers: [String]
    let explicitYear: String?
    let geoLookup: [String: GeographicEntity]

    /// Detect format and create appropriate normalizer
    static func detect(from headerLine: String, explicitYear: String?, geoLookup: [String: GeographicEntity]) -> CSVNormalizer? {
        let delimiter = detectDelimiter(headerLine)
        let fixedHeader = fixEncoding(headerLine)
        let headers = parseCSVLine(fixedHeader, delimiter: delimiter)

        print("📋 Detected \(headers.count) columns with delimiter '\(delimiter)'")
        print("   Headers: \(headers.joined(separator: ", "))")

        return CSVNormalizer(inputDelimiter: delimiter, headers: headers, explicitYear: explicitYear, geoLookup: geoLookup)
    }

    /// Normalize a data row to standard format
    func normalize(_ line: String, recordNumber: Int) -> String? {
        // Fix encoding issues in the line first
        let fixedLine = fixEncoding(line)

        let fields = parseCSVLine(fixedLine, delimiter: inputDelimiter)

        guard fields.count == headers.count else {
            print("⚠️  Field count mismatch: expected \(headers.count), got \(fields.count)")
            return nil
        }

        // Create field mapping
        var fieldMap: [String: String] = [:]
        for (index, header) in headers.enumerated() {
            fieldMap[header] = fields[index]
        }

        // Extract year
        var year = explicitYear
        if year == nil {
            // Try to extract from "Année civile" or "Année civile / mois"
            if let yearField = fieldMap["Année civile"] ?? fieldMap["Année civile / mois"] {
                year = extractYear(yearField)
            }
        }

        guard let finalYear = year else {
            print("⚠️  Could not determine year for record")
            return nil
        }

        // Look up municipality code from name
        let municipalityName = fieldMap["Municipalité (description)"] ?? fieldMap["Municipalité"] ?? ""
        let municipalityCode = lookupMunicipality(municipalityName)?.code ?? ""

        // Map fields to standard format (16 fields for 2017+)
        let standardFields: [String] = [
            finalYear,                                                          // AN
            "\(finalYear)_\(String(format: "%010d", recordNumber))",           // NOSEQ_VEH (unique sequence)
            "",                                                                 // CLAS (missing)
            "",                                                                 // TYP_VEH_CATEG_USA (missing)
            fieldMap["Marque du véhicule (fabricant)"] ?? fieldMap["Marque"] ?? "",  // MARQ_VEH
            fieldMap["Modèle du véhicule"] ?? fieldMap["Modèle"] ?? "",              // MODEL_VEH
            fieldMap["Année du modèle du véhicule"] ?? fieldMap["Année de fabrication"] ?? "",  // ANNEE_MOD
            "",                                                                 // MASSE_NETTE (missing)
            "",                                                                 // NB_CYL (missing)
            "",                                                                 // CYL_VEH (missing)
            "",                                                                 // NB_ESIEU_MAX (missing)
            "",                                                                 // COUL_ORIG (missing)
            "",                                                                 // TYP_CARBU (missing)
            normalizeRegion(fieldMap["Région admin (code)"] ?? ""),            // REG_ADM
            "",                                                                 // MRC (not in source data)
            municipalityCode                                                    // CG_FIXE (municipality code)
        ]

        // Format as CSV with proper quoting
        let quotedFields = standardFields.map { field in
            let needsQuotes = field.contains(",") || field.contains("\"") || field.contains("\n")
            if needsQuotes {
                return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
            } else {
                return "\"\(field)\""
            }
        }

        return quotedFields.joined(separator: ",")
    }

    /// Look up municipality by name
    private func lookupMunicipality(_ name: String) -> GeographicEntity? {
        let normalized = normalizeMunicipalityName(name)
        return geoLookup[normalized]
    }

    /// Normalize region code to standard format
    private func normalizeRegion(_ regionCode: String) -> String {
        let trimmed = regionCode.trimmingCharacters(in: .whitespaces)
        return regionMapping[trimmed] ?? ""
    }
}

// MARK: - Main Script

func main() {
    let args = CommandLine.arguments

    guard args.count >= 3 else {
        print("Usage: swift NormalizeCSV.swift <input.csv> <output.csv> [year] [d001_path]")
        print("")
        print("Normalizes SAAQ CSV files from 2023-2024 format to standard format.")
        print("If year is not provided, it will be extracted from the data.")
        print("If d001_path is not provided, geographic lookups will be skipped.")
        exit(1)
    }

    let inputPath = args[1]
    let outputPath = args[2]
    let explicitYear = args.count > 3 ? args[3] : nil
    let d001Path = args.count > 4 ? args[4] : nil

    print("🔄 Normalizing CSV file...")
    print("   Input:  \(inputPath)")
    print("   Output: \(outputPath)")
    if let year = explicitYear {
        print("   Year:   \(year)")
    }
    if let d001 = d001Path {
        print("   d001:   \(d001)")
    }
    print("")

    // Load geographic lookup if d001 path provided
    let geoLookup = d001Path != nil ? loadGeographicLookup(from: d001Path!) : [:]

    // Read input file - try UTF-8 first (most 2023-2024 files), then fallback to ISO Latin-1
    var inputContent: String?

    // First try UTF-8
    if let content = try? String(contentsOfFile: inputPath, encoding: .utf8),
       !content.contains("\u{FFFD}") {  // Check for replacement characters indicating wrong encoding
        inputContent = content
        print("✓ Read file with encoding: UTF-8")
    }
    // Fallback to ISO Latin-1
    else if let content = try? String(contentsOfFile: inputPath, encoding: .isoLatin1) {
        inputContent = content
        print("✓ Read file with encoding: ISO Latin-1")
    }
    // Last resort: Windows CP1252
    else if let content = try? String(contentsOfFile: inputPath, encoding: .windowsCP1252) {
        inputContent = content
        print("✓ Read file with encoding: Windows CP1252")
    }

    guard let inputContent = inputContent else {
        print("❌ Failed to read input file with any supported encoding")
        exit(1)
    }

    let lines = inputContent.components(separatedBy: .newlines)
    guard !lines.isEmpty else {
        print("❌ Input file is empty")
        exit(1)
    }

    // Detect format from header
    guard let normalizer = CSVNormalizer.detect(from: lines[0], explicitYear: explicitYear, geoLookup: geoLookup) else {
        print("❌ Failed to detect CSV format")
        exit(1)
    }

    // Create standard header
    let standardHeader = "\"AN\",\"NOSEQ_VEH\",\"CLAS\",\"TYP_VEH_CATEG_USA\",\"MARQ_VEH\",\"MODEL_VEH\",\"ANNEE_MOD\",\"MASSE_NETTE\",\"NB_CYL\",\"CYL_VEH\",\"NB_ESIEU_MAX\",\"COUL_ORIG\",\"TYP_CARBU\",\"REG_ADM\",\"MRC\",\"CG_FIXE\""

    var outputLines = [standardHeader]
    var processedCount = 0
    var errorCount = 0

    // Process data rows
    for (index, line) in lines.dropFirst().enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }

        let recordNumber = index + 1  // Start from 1
        if let normalized = normalizer.normalize(trimmed, recordNumber: recordNumber) {
            outputLines.append(normalized)
            processedCount += 1

            if (index + 1) % 10000 == 0 {
                print("   Processed \(processedCount) records...")
            }
        } else {
            errorCount += 1
        }
    }

    // Write output
    let outputContent = outputLines.joined(separator: "\n")
    do {
        try outputContent.write(toFile: outputPath, atomically: true, encoding: .utf8)
        print("")
        print("✅ Normalization complete!")
        print("   Total records: \(processedCount)")
        if errorCount > 0 {
            print("   Errors: \(errorCount)")
        }
        print("   Output written to: \(outputPath)")
    } catch {
        print("❌ Failed to write output file: \(error)")
        exit(1)
    }
}

// Run the script
main()
