#!/usr/bin/env swift
import Foundation
import SQLite3

// MARK: - CVS Record Structure
struct CVSRecord {
    let make: String
    let model: String
    let myr: Int
    let ol: Double?
    let ow: Double?
    let oh: Double?
    let wb: Double?
    let cw: Double?
    let a: Double?
    let b: Double?
    let c: Double?
    let d: Double?
    let e: Double?
    let f: Double?
    let g: Double?
    let twf: Double?
    let twr: Double?
    let wd: String?

    // Derived fields
    var saaqMake: String {
        String(make.prefix(5)).uppercased()
    }

    var saaqModel: String {
        let firstWord = model.components(separatedBy: " ").first ?? model
        return String(firstWord.prefix(5)).uppercased()
    }

    var vehicleType: String? {
        let upper = model.uppercased()
        if upper.contains("SEDAN") { return "SEDAN" }
        if upper.contains("MINIVAN") || upper.contains("VAN") { return "MINIVAN" }
        if upper.contains("SUV") { return "SUV" }
        if upper.contains("HATCH") || upper.contains("HATCHBACK") { return "HATCHBACK" }
        if upper.contains("WAGON") { return "WAGON" }
        if upper.contains("COUPE") { return "COUPE" }
        if upper.contains("PICKUP") || upper.contains("TRUCK") { return "PICKUP" }
        if upper.contains("CONVERTIBLE") { return "CONVERTIBLE" }
        return nil
    }
}

// MARK: - Database Creation
func createDatabase(path: String) -> OpaquePointer? {
    var db: OpaquePointer?

    guard sqlite3_open(path, &db) == SQLITE_OK else {
        print("❌ Failed to create database at \(path)")
        return nil
    }

    let createTableSQL = """
    CREATE TABLE IF NOT EXISTS cvs_data (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        make TEXT NOT NULL,
        model TEXT NOT NULL,
        myr INTEGER NOT NULL,
        saaq_make TEXT NOT NULL,
        saaq_model TEXT NOT NULL,
        vehicle_type TEXT,
        ol REAL,
        ow REAL,
        oh REAL,
        wb REAL,
        cw REAL,
        a REAL,
        b REAL,
        c REAL,
        d REAL,
        e REAL,
        f REAL,
        g REAL,
        twf REAL,
        twr REAL,
        wd TEXT,
        UNIQUE(make, model, myr)
    );

    CREATE INDEX IF NOT EXISTS idx_cvs_saaq_make ON cvs_data(saaq_make);
    CREATE INDEX IF NOT EXISTS idx_cvs_saaq_model ON cvs_data(saaq_model);
    CREATE INDEX IF NOT EXISTS idx_cvs_saaq_make_model ON cvs_data(saaq_make, saaq_model);
    CREATE INDEX IF NOT EXISTS idx_cvs_myr ON cvs_data(myr);
    CREATE INDEX IF NOT EXISTS idx_cvs_vehicle_type ON cvs_data(vehicle_type);
    """

    if sqlite3_exec(db, createTableSQL, nil, nil, nil) != SQLITE_OK {
        let errmsg = String(cString: sqlite3_errmsg(db)!)
        print("❌ Failed to create table: \(errmsg)")
        sqlite3_close(db)
        return nil
    }

    return db
}

// MARK: - CSV Parsing
func parseCSVLine(_ line: String) -> CVSRecord? {
    let parts = line.components(separatedBy: ",")
    guard parts.count >= 18 else { return nil }

    let make = parts[0].trimmingCharacters(in: .whitespaces)
    let model = parts[1].trimmingCharacters(in: .whitespaces)
    guard let myr = Int(parts[2]) else { return nil }

    func parseDouble(_ str: String) -> Double? {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Double(trimmed)
    }

    return CVSRecord(
        make: make,
        model: model,
        myr: myr,
        ol: parseDouble(parts[3]),
        ow: parseDouble(parts[4]),
        oh: parseDouble(parts[5]),
        wb: parseDouble(parts[6]),
        cw: parseDouble(parts[7]),
        a: parseDouble(parts[8]),
        b: parseDouble(parts[9]),
        c: parseDouble(parts[10]),
        d: parseDouble(parts[11]),
        e: parseDouble(parts[12]),
        f: parseDouble(parts[13]),
        g: parseDouble(parts[14]),
        twf: parseDouble(parts[15]),
        twr: parseDouble(parts[16]),
        wd: parts.count > 17 ? parts[17].trimmingCharacters(in: .whitespaces) : nil
    )
}

// MARK: - Database Insertion
func insertRecord(db: OpaquePointer, record: CVSRecord) -> Bool {
    let insertSQL = """
    INSERT OR REPLACE INTO cvs_data
    (make, model, myr, saaq_make, saaq_model, vehicle_type,
     ol, ow, oh, wb, cw, a, b, c, d, e, f, g, twf, twr, wd)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
        return false
    }
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_text(statement, 1, (record.make as NSString).utf8String, -1, nil)
    sqlite3_bind_text(statement, 2, (record.model as NSString).utf8String, -1, nil)
    sqlite3_bind_int(statement, 3, Int32(record.myr))
    sqlite3_bind_text(statement, 4, (record.saaqMake as NSString).utf8String, -1, nil)
    sqlite3_bind_text(statement, 5, (record.saaqModel as NSString).utf8String, -1, nil)

    if let vType = record.vehicleType {
        sqlite3_bind_text(statement, 6, (vType as NSString).utf8String, -1, nil)
    } else {
        sqlite3_bind_null(statement, 6)
    }

    func bindDouble(_ value: Double?, at index: Int32) {
        if let val = value {
            sqlite3_bind_double(statement, index, val)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    bindDouble(record.ol, at: 7)
    bindDouble(record.ow, at: 8)
    bindDouble(record.oh, at: 9)
    bindDouble(record.wb, at: 10)
    bindDouble(record.cw, at: 11)
    bindDouble(record.a, at: 12)
    bindDouble(record.b, at: 13)
    bindDouble(record.c, at: 14)
    bindDouble(record.d, at: 15)
    bindDouble(record.e, at: 16)
    bindDouble(record.f, at: 17)
    bindDouble(record.g, at: 18)
    bindDouble(record.twf, at: 19)
    bindDouble(record.twr, at: 20)

    if let wd = record.wd {
        sqlite3_bind_text(statement, 21, (wd as NSString).utf8String, -1, nil)
    } else {
        sqlite3_bind_null(statement, 21)
    }

    return sqlite3_step(statement) == SQLITE_DONE
}

// MARK: - Main Processing
let cvsDirectory = "/Users/rhoge/Downloads/CVS20252"
let outputDB = "\(NSHomeDirectory())/Desktop/cvs_complete.sqlite"

print("🚗 Building comprehensive CVS database...")
print("Source: \(cvsDirectory)")
print("Output: \(outputDB)\n")

// Create database
guard let db = createDatabase(path: outputDB) else {
    exit(1)
}
defer { sqlite3_close(db) }

// Get all CSV files
let fileManager = FileManager.default
guard let files = try? fileManager.contentsOfDirectory(atPath: cvsDirectory) else {
    print("❌ Failed to read directory")
    exit(1)
}

let csvFiles = files.filter { $0.hasSuffix(".csv") }.sorted()
print("Found \(csvFiles.count) CSV files\n")

var totalRecords = 0
var totalFiles = 0

// Begin transaction for performance
sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)

for csvFile in csvFiles {
    let filePath = "\(cvsDirectory)/\(csvFile)"

    guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
        print("⚠️  Failed to read \(csvFile)")
        continue
    }

    let lines = content.components(separatedBy: .newlines)
    var fileRecords = 0

    for (index, line) in lines.enumerated() {
        guard index > 0, !line.isEmpty else { continue } // Skip header

        if let record = parseCSVLine(line) {
            if insertRecord(db: db, record: record) {
                fileRecords += 1
                totalRecords += 1
            }
        }
    }

    if fileRecords > 0 {
        print("✓ \(csvFile): \(fileRecords) records")
        totalFiles += 1
    }
}

// Commit transaction
sqlite3_exec(db, "COMMIT", nil, nil, nil)

print("\n✅ Complete!")
print("Processed \(totalFiles) files")
print("Total records: \(totalRecords)")
print("\nDatabase saved to: \(outputDB)")

// Print some statistics
let statsSQL = """
SELECT
    COUNT(DISTINCT saaq_make) as makes,
    COUNT(DISTINCT saaq_model) as models,
    COUNT(DISTINCT vehicle_type) as types,
    MIN(myr) as min_year,
    MAX(myr) as max_year
FROM cvs_data
"""

var statement: OpaquePointer?
if sqlite3_prepare_v2(db, statsSQL, -1, &statement, nil) == SQLITE_OK,
   sqlite3_step(statement) == SQLITE_ROW {
    let makes = sqlite3_column_int(statement, 0)
    let models = sqlite3_column_int(statement, 1)
    let types = sqlite3_column_int(statement, 2)
    let minYear = sqlite3_column_int(statement, 3)
    let maxYear = sqlite3_column_int(statement, 4)

    print("\n📊 Statistics:")
    print("  Unique SAAQ makes: \(makes)")
    print("  Unique SAAQ models: \(models)")
    print("  Vehicle types: \(types)")
    print("  Year range: \(minYear) - \(maxYear)")
}
sqlite3_finalize(statement)
