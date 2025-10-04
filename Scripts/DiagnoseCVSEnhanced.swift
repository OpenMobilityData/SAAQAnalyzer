#!/usr/bin/env swift

import Foundation
import SQLite3

print("🔍 CVS-Enhanced Script Diagnostic Test")
print(String(repeating: "=", count: 60))

// MARK: - Database Helper

func openDatabase(_ path: String) -> OpaquePointer? {
    print("\n📂 Opening database: \(path)")
    var db: OpaquePointer?
    let result = sqlite3_open(path, &db)

    if result != SQLITE_OK {
        print("❌ Failed to open database: \(String(cString: sqlite3_errmsg(db)))")
        return nil
    }

    print("✅ Database opened successfully")
    return db
}

// MARK: - Test Database Connections

let args = CommandLine.arguments
guard args.count == 3 else {
    print("\n❌ Usage: \(args[0]) <saaq_database_path> <cvs_database_path>")
    exit(1)
}

let saaqDBPath = args[1]
let cvsDBPath = args[2]

print("\n🎯 Testing SAAQ Database Connection...")
guard let saaqDB = openDatabase(saaqDBPath) else {
    print("❌ Cannot proceed without SAAQ database")
    exit(1)
}

print("\n🎯 Testing CVS Database Connection...")
guard let cvsDB = openDatabase(cvsDBPath) else {
    sqlite3_close(saaqDB)
    print("❌ Cannot proceed without CVS database")
    exit(1)
}

// MARK: - Test Query Execution

print("\n🎯 Testing SAAQ Query for Canonical Pairs...")
var stmt: OpaquePointer?
let canonicalQuery = """
SELECT DISTINCT make_clean, model_clean,
       MIN(model_year) as min_year,
       MAX(model_year) as max_year
FROM vehicles
WHERE model_year BETWEEN 2011 AND 2022
  AND make_clean IS NOT NULL
  AND model_clean IS NOT NULL
LIMIT 10
"""

if sqlite3_prepare_v2(saaqDB, canonicalQuery, -1, &stmt, nil) == SQLITE_OK {
    var count = 0
    while sqlite3_step(stmt) == SQLITE_ROW {
        let make = String(cString: sqlite3_column_text(stmt, 0))
        let model = String(cString: sqlite3_column_text(stmt, 1))
        let minYear = sqlite3_column_int(stmt, 2)
        let maxYear = sqlite3_column_int(stmt, 3)
        count += 1
        print("  \(count). \(make) \(model) (\(minYear)-\(maxYear))")
    }
    print("✅ Retrieved \(count) canonical pairs")
} else {
    print("❌ Failed to query canonical pairs: \(String(cString: sqlite3_errmsg(saaqDB)))")
}
sqlite3_finalize(stmt)

print("\n🎯 Testing SAAQ Query for Non-Standard Pairs...")
let nonStandardQuery = """
SELECT DISTINCT make_clean, model_clean,
       MIN(model_year) as min_year,
       MAX(model_year) as max_year
FROM vehicles
WHERE model_year BETWEEN 2023 AND 2024
  AND make_clean IS NOT NULL
  AND model_clean IS NOT NULL
LIMIT 10
"""

if sqlite3_prepare_v2(saaqDB, nonStandardQuery, -1, &stmt, nil) == SQLITE_OK {
    var count = 0
    while sqlite3_step(stmt) == SQLITE_ROW {
        let make = String(cString: sqlite3_column_text(stmt, 0))
        let model = String(cString: sqlite3_column_text(stmt, 1))
        let minYear = sqlite3_column_int(stmt, 2)
        let maxYear = sqlite3_column_int(stmt, 3)
        count += 1
        print("  \(count). \(make) \(model) (\(minYear)-\(maxYear))")
    }
    print("✅ Retrieved \(count) non-standard pairs")
} else {
    print("❌ Failed to query non-standard pairs: \(String(cString: sqlite3_errmsg(saaqDB)))")
}
sqlite3_finalize(stmt)

print("\n🎯 Testing CVS Database Query...")
let cvsQuery = """
SELECT DISTINCT make, model, model_year, body_type
FROM vehicles
LIMIT 10
"""

if sqlite3_prepare_v2(cvsDB, cvsQuery, -1, &stmt, nil) == SQLITE_OK {
    var count = 0
    while sqlite3_step(stmt) == SQLITE_ROW {
        let make = String(cString: sqlite3_column_text(stmt, 0))
        let model = String(cString: sqlite3_column_text(stmt, 1))
        let year = sqlite3_column_int(stmt, 2)
        let bodyType = String(cString: sqlite3_column_text(stmt, 3))
        count += 1
        print("  \(count). \(make) \(model) (\(year)) - \(bodyType)")
    }
    print("✅ Retrieved \(count) CVS records")
} else {
    print("❌ Failed to query CVS database: \(String(cString: sqlite3_errmsg(cvsDB)))")
}
sqlite3_finalize(stmt)

// MARK: - Test Foundation Models API

print("\n🎯 Testing Foundation Models API...")
print("⚠️  This requires async execution - testing basic import only")

import FoundationModels

print("✅ Foundation Models framework imported successfully")
print("⚠️  Full AI test requires async Task execution")

// MARK: - Cleanup

sqlite3_close(saaqDB)
sqlite3_close(cvsDB)

print("\n" + String(repeating: "=", count: 60))
print("✅ Diagnostic test completed")
print("\nIf all tests passed, the issue is likely in:")
print("  1. Async Task execution pattern")
print("  2. AI API calls timing out or failing")
print("  3. File write permissions for output report")
