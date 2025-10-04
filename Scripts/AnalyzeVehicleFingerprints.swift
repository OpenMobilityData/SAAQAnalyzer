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
        } else {
            print("❌ Failed to prepare statement")
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

print("Analyzing vehicle fingerprint parameters for canonical 2011-2022 data...\n")

// 1. Check data availability for fingerprint fields
print("=== Field Availability Analysis ===")
let availabilityQuery = """
SELECT
    COUNT(*) as total_records,
    COUNT(DISTINCT make_id) as unique_makes,
    COUNT(DISTINCT model_id) as unique_models,
    COUNT(DISTINCT classification_id) as has_classification,
    SUM(CASE WHEN net_mass IS NOT NULL AND net_mass > 0 THEN 1 ELSE 0 END) as has_mass,
    SUM(CASE WHEN cylinder_count IS NOT NULL AND cylinder_count > 0 THEN 1 ELSE 0 END) as has_cylinders,
    SUM(CASE WHEN displacement IS NOT NULL AND displacement > 0 THEN 1 ELSE 0 END) as has_displacement,
    COUNT(DISTINCT fuel_type_id) as unique_fuel_types
FROM vehicles
WHERE year BETWEEN 2011 AND 2022
"""

let availability = queryDatabase(dbPath: dbPath, query: availabilityQuery)
if let row = availability.first {
    print("Total canonical records: \(row["total_records"] ?? "?")")
    print("Unique makes: \(row["unique_makes"] ?? "?")")
    print("Unique models: \(row["unique_models"] ?? "?")")
    print("Records with classification: \(row["has_classification"] ?? "?")")
    print("Records with mass data: \(row["has_mass"] ?? "?")")
    print("Records with cylinder count: \(row["has_cylinders"] ?? "?")")
    print("Records with displacement: \(row["has_displacement"] ?? "?")")
    print("Unique fuel types: \(row["unique_fuel_types"] ?? "?")")
}

// 2. Analyze parameter patterns for problematic cases
print("\n=== Case Study: KIA Models (CARNI vs CADEN) ===")
let kiaQuery = """
SELECT
    make_enum.name as make,
    model_enum.name as model,
    class_enum.code as classification,
    AVG(net_mass) as avg_mass,
    AVG(cylinder_count) as avg_cylinders,
    AVG(displacement) as avg_displacement,
    fuel_enum.code as fuel_type,
    COUNT(*) as record_count,
    MIN(model_year) as min_year,
    MAX(model_year) as max_year
FROM vehicles
LEFT JOIN make_enum ON vehicles.make_id = make_enum.id
LEFT JOIN model_enum ON vehicles.model_id = model_enum.id
LEFT JOIN classification_enum class_enum ON vehicles.classification_id = class_enum.id
LEFT JOIN fuel_type_enum fuel_enum ON vehicles.fuel_type_id = fuel_enum.id
WHERE vehicles.year BETWEEN 2011 AND 2022
  AND make_enum.name = 'KIA'
  AND (model_enum.name LIKE '%CARN%' OR model_enum.name LIKE '%CADE%')
GROUP BY make_enum.name, model_enum.name, class_enum.code, fuel_enum.code
ORDER BY model_enum.name, record_count DESC
"""

let kiaResults = queryDatabase(dbPath: dbPath, query: kiaQuery)
for row in kiaResults {
    print("\nModel: \(row["model"] ?? "?")")
    print("  Classification: \(row["classification"] ?? "N/A")")
    print("  Avg Mass: \(row["avg_mass"] ?? "N/A") kg")
    print("  Avg Cylinders: \(row["avg_cylinders"] ?? "N/A")")
    print("  Avg Displacement: \(row["avg_displacement"] ?? "N/A") cc")
    print("  Fuel Type: \(row["fuel_type"] ?? "N/A")")
    print("  Years: \(row["min_year"] ?? "?")-\(row["max_year"] ?? "?")")
    print("  Records: \(row["record_count"] ?? "?")")
}

// 3. Analyze model name patterns by vehicle class
print("\n=== Model Name Patterns by Classification ===")
let patternQuery = """
SELECT
    class_enum.code as classification,
    COUNT(*) as total_records,
    COUNT(DISTINCT model_enum.name) as unique_models,
    SUM(CASE WHEN model_enum.name GLOB '*[0-9]*' THEN 1 ELSE 0 END) as alphanumeric_models,
    SUM(CASE WHEN model_enum.name NOT GLOB '*[0-9]*' THEN 1 ELSE 0 END) as alpha_only_models
FROM vehicles
LEFT JOIN model_enum ON vehicles.model_id = model_enum.id
LEFT JOIN classification_enum class_enum ON vehicles.classification_id = class_enum.id
WHERE vehicles.year BETWEEN 2011 AND 2022
  AND class_enum.code IS NOT NULL
GROUP BY class_enum.code
ORDER BY total_records DESC
LIMIT 15
"""

let patternResults = queryDatabase(dbPath: dbPath, query: patternQuery)
print("\nClassification | Records | Unique Models | Alphanumeric | Alpha-only")
print(String(repeating: "-", count: 75))
for row in patternResults {
    let classification = row["classification"] ?? "?"
    let records = row["total_records"] ?? "?"
    let unique = row["unique_models"] ?? "?"
    let alphanumeric = row["alphanumeric_models"] ?? "?"
    let alphaOnly = row["alpha_only_models"] ?? "?"
    print("\(classification.padding(toLength: 20, withPad: " ", startingAt: 0)) | \(records.padding(toLength: 7, withPad: " ", startingAt: 0)) | \(unique.padding(toLength: 13, withPad: " ", startingAt: 0)) | \(alphanumeric.padding(toLength: 12, withPad: " ", startingAt: 0)) | \(alphaOnly)")
}

// 4. Sample distinctive fingerprints
print("\n=== Sample Make/Model Fingerprints ===")
let fingerprintQuery = """
SELECT
    make_enum.name as make,
    model_enum.name as model,
    class_enum.code as classification,
    ROUND(AVG(net_mass), 0) as avg_mass,
    ROUND(AVG(cylinder_count), 1) as avg_cylinders,
    ROUND(AVG(displacement), 0) as avg_displacement,
    fuel_enum.code as fuel_type,
    COUNT(*) as records
FROM vehicles
LEFT JOIN make_enum ON vehicles.make_id = make_enum.id
LEFT JOIN model_enum ON vehicles.model_id = model_enum.id
LEFT JOIN classification_enum class_enum ON vehicles.classification_id = class_enum.id
LEFT JOIN fuel_type_enum fuel_enum ON vehicles.fuel_type_id = fuel_enum.id
WHERE vehicles.year BETWEEN 2011 AND 2022
  AND make_enum.name IN ('MAZDA', 'TOYOT', 'KUBOTA', 'KIA')
GROUP BY make_enum.name, model_enum.name, class_enum.code, fuel_enum.code
HAVING COUNT(*) > 50
ORDER BY make_enum.name, model_enum.name
LIMIT 20
"""

let fingerprintResults = queryDatabase(dbPath: dbPath, query: fingerprintQuery)
for row in fingerprintResults {
    print("\n\(row["make"] ?? "?") \(row["model"] ?? "?")")
    print("  Class: \(row["classification"] ?? "N/A")")
    print("  Mass: \(row["avg_mass"] ?? "?")kg | Cyl: \(row["avg_cylinders"] ?? "?") | Disp: \(row["avg_displacement"] ?? "?")cc | Fuel: \(row["fuel_type"] ?? "?")")
    print("  \(row["records"] ?? "?") records")
}

print("\n✅ Analysis complete")
