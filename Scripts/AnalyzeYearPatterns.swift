#!/usr/bin/env swift
import Foundation
import SQLite3

// MARK: - Database Query Helper
func queryDatabase(dbPath: String, query: String) -> [[String: String]] {
    var db: OpaquePointer?
    var results: [[String: String]] = []

    guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
        print("❌ Failed to open database")
        return []
    }
    defer { sqlite3_close(db) }

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
        if let errmsg = sqlite3_errmsg(db) {
            print("❌ Failed to prepare statement: \(String(cString: errmsg))")
        }
        return []
    }
    defer { sqlite3_finalize(statement) }

    let columnCount = sqlite3_column_count(statement)

    while sqlite3_step(statement) == SQLITE_ROW {
        var row: [String: String] = [:]
        for i in 0..<columnCount {
            let columnName = String(cString: sqlite3_column_name(statement, i))
            if let value = sqlite3_column_text(statement, i) {
                row[columnName] = String(cString: value)
            } else {
                row[columnName] = ""
            }
        }
        results.append(row)
    }

    return results
}

// MARK: - Main Analysis
let dbPath = "\(NSHomeDirectory())/Library/Containers/com.endoquant.SAAQAnalyzer/Data/Documents/saaq_data.sqlite"

print("📅 Analyzing Year Patterns in Canonical 2011-2022 Data...\n")

// 1. Model Year vs Registration Year Distribution
print("=== Model Year vs Registration Year Relationship ===")
let yearDistQuery = """
SELECT
    year as registration_year,
    model_year,
    COUNT(*) as count
FROM vehicles
WHERE year BETWEEN 2011 AND 2022
  AND model_year IS NOT NULL
GROUP BY year, model_year
HAVING COUNT(*) > 100
ORDER BY year, model_year
LIMIT 30
"""

let yearDist = queryDatabase(dbPath: dbPath, query: yearDistQuery)
print("\nReg Year | Model Year | Count")
print(String(repeating: "-", count: 40))
for row in yearDist {
    let regYear = row["registration_year"] ?? "?"
    let modelYear = row["model_year"] ?? "?"
    let count = row["count"] ?? "?"
    print("\(regYear.padding(toLength: 8, withPad: " ", startingAt: 0)) | \(modelYear.padding(toLength: 10, withPad: " ", startingAt: 0)) | \(count)")
}

// 2. Model Year Range Analysis per Make/Model
print("\n\n=== Model Year Ranges for Specific Models ===")
let modelYearRangeQuery = """
SELECT
    make_enum.name as make,
    model_enum.name as model,
    MIN(model_year) as min_model_year,
    MAX(model_year) as max_model_year,
    MIN(year) as min_reg_year,
    MAX(year) as max_reg_year,
    COUNT(DISTINCT model_year) as year_variants,
    COUNT(*) as total_records
FROM vehicles
LEFT JOIN make_enum ON vehicles.make_id = make_enum.id
LEFT JOIN model_enum ON vehicles.model_id = model_enum.id
WHERE vehicles.year BETWEEN 2011 AND 2022
  AND model_year IS NOT NULL
  AND make_enum.name = 'KIA'
  AND model_enum.name IN ('SEDON', 'CADEN', 'RIO', 'FORTE')
GROUP BY make_enum.name, model_enum.name
ORDER BY model_enum.name
"""

let modelYearRanges = queryDatabase(dbPath: dbPath, query: modelYearRangeQuery)
for row in modelYearRanges {
    print("\n\(row["make"] ?? "?") \(row["model"] ?? "?")")
    print("  Model Years: \(row["min_model_year"] ?? "?")-\(row["max_model_year"] ?? "?") (\(row["year_variants"] ?? "?") variants)")
    print("  Registration Years: \(row["min_reg_year"] ?? "?")-\(row["max_reg_year"] ?? "?")")
    print("  Total Records: \(row["total_records"] ?? "?")")
}

// 3. Year Lag Analysis (how old are registered vehicles?)
print("\n\n=== Vehicle Age at Registration (Year - Model_Year) ===")
let ageLagQuery = """
SELECT
    (year - model_year) as age_at_registration,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM vehicles WHERE year BETWEEN 2011 AND 2022 AND model_year IS NOT NULL), 2) as percentage
FROM vehicles
WHERE year BETWEEN 2011 AND 2022
  AND model_year IS NOT NULL
  AND (year - model_year) BETWEEN -1 AND 10
GROUP BY (year - model_year)
ORDER BY (year - model_year)
"""

let ageLag = queryDatabase(dbPath: dbPath, query: ageLagQuery)
print("\nAge (Years) | Count      | Percentage")
print(String(repeating: "-", count: 45))
for row in ageLag {
    let age = row["age_at_registration"] ?? "?"
    let count = row["count"] ?? "?"
    let pct = row["percentage"] ?? "?"
    print("\(age.padding(toLength: 11, withPad: " ", startingAt: 0)) | \(count.padding(toLength: 10, withPad: " ", startingAt: 0)) | \(pct)%")
}

// 4. Case Study: KIA SEDONA/CARNIVAL Transition
print("\n\n=== Case Study: KIA SEDON Model Year Evolution ===")
let sedonEvolutionQuery = """
SELECT
    year as registration_year,
    model_year,
    COUNT(*) as count
FROM vehicles
LEFT JOIN make_enum ON vehicles.make_id = make_enum.id
LEFT JOIN model_enum ON vehicles.model_id = model_enum.id
WHERE vehicles.year BETWEEN 2011 AND 2022
  AND make_enum.name = 'KIA'
  AND model_enum.name = 'SEDON'
  AND model_year IS NOT NULL
GROUP BY year, model_year
ORDER BY year, model_year
"""

let sedonEvolution = queryDatabase(dbPath: dbPath, query: sedonEvolutionQuery)
print("\nRegistration Year | Model Year | Count")
print(String(repeating: "-", count: 45))
for row in sedonEvolution {
    let regYear = row["registration_year"] ?? "?"
    let modelYear = row["model_year"] ?? "?"
    let count = row["count"] ?? "?"
    print("\(regYear.padding(toLength: 17, withPad: " ", startingAt: 0)) | \(modelYear.padding(toLength: 10, withPad: " ", startingAt: 0)) | \(count)")
}

// 5. Model Name Changes Over Time (same vehicle, different names)
print("\n\n=== Potential Model Name Changes (Temporal Patterns) ===")
let nameChangeQuery = """
SELECT
    make_enum.name as make,
    model_enum.name as model,
    MIN(year) as first_seen,
    MAX(year) as last_seen,
    COUNT(DISTINCT model_year) as model_year_count,
    COUNT(*) as records
FROM vehicles
LEFT JOIN make_enum ON vehicles.make_id = make_enum.id
LEFT JOIN model_enum ON vehicles.model_id = model_enum.id
WHERE vehicles.year BETWEEN 2011 AND 2022
  AND make_enum.name = 'KIA'
GROUP BY make_enum.name, model_enum.name
HAVING records > 50
ORDER BY first_seen, model_enum.name
"""

let nameChanges = queryDatabase(dbPath: dbPath, query: nameChangeQuery)
print("\nModel       | First Seen | Last Seen | Records")
print(String(repeating: "-", count: 55))
for row in nameChanges {
    let model = row["model"] ?? "?"
    let first = row["first_seen"] ?? "?"
    let last = row["last_seen"] ?? "?"
    let records = row["records"] ?? "?"
    print("\(model.padding(toLength: 11, withPad: " ", startingAt: 0)) | \(first.padding(toLength: 10, withPad: " ", startingAt: 0)) | \(last.padding(toLength: 9, withPad: " ", startingAt: 0)) | \(records)")
}

// 6. Future Model Years (model_year > registration_year)
print("\n\n=== Future Model Years Analysis ===")
let futureModelsQuery = """
SELECT
    year as registration_year,
    model_year,
    COUNT(*) as count
FROM vehicles
WHERE year BETWEEN 2011 AND 2022
  AND model_year IS NOT NULL
  AND model_year > year
GROUP BY year, model_year
ORDER BY year, model_year
LIMIT 20
"""

let futureModels = queryDatabase(dbPath: dbPath, query: futureModelsQuery)
print("\nReg Year | Model Year | Count | Note")
print(String(repeating: "-", count: 60))
for row in futureModels {
    let regYear = row["registration_year"] ?? "?"
    let modelYear = row["model_year"] ?? "?"
    let count = row["count"] ?? "?"
    print("\(regYear.padding(toLength: 8, withPad: " ", startingAt: 0)) | \(modelYear.padding(toLength: 10, withPad: " ", startingAt: 0)) | \(count.padding(toLength: 5, withPad: " ", startingAt: 0)) | Next year's model")
}

print("\n\n✅ Analysis Complete")
