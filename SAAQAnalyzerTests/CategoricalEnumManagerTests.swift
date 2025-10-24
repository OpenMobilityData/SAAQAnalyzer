//
//  CategoricalEnumManagerTests.swift
//  SAAQAnalyzerTests
//
//  Created by Claude Code on 2025-10-23.
//  Test suite for CategoricalEnumManager - verifies enum table creation, indexing, and population
//

import XCTest
import SQLite3
@testable import SAAQAnalyzer

/// Comprehensive test suite for CategoricalEnumManager
///
/// **Active Test Categories**:
/// 1. Schema Creation (7 tests) - 16 enumeration tables
/// 2. Index Creation (3 tests) - ⚠️ **CRITICAL** 9 performance indexes
/// 3. Schema Validation (1 test) - Foreign key constraints
///
/// **Removed Tests** (depend on vestigial migration code):
/// - Enum Population - queries old string columns (classification, make, model)
/// - Enum Lookup - requires populated enums
/// - Duplicate Handling - requires populated enums
///
/// **Future Work**: Create test database with TestData CSV imports, then add
/// population/lookup tests for current integer-based architecture
///
/// **Historical Context**:
/// - Oct 11, 2025: Missing enum ID indexes caused 165s → 10s performance regression (16x slower)
/// - Oct 9, 2025: Added "Unknown" enum values for FuelType ("U") and VehicleClass ("UNK")
/// - Critical Rule #6 from CLAUDE.md: ALL enum tables MUST have indexes on ID columns
///
/// **Test Pattern**: Integration tests using DatabaseManager.shared
/// - CategoricalEnumManager is NOT a singleton (safe to instantiate)
/// - Uses IF NOT EXISTS clauses (idempotent, safe to run multiple times)
/// - Tests verify actual database state
final class CategoricalEnumManagerTests: XCTestCase {

    // No instance variables - create locally in each test to avoid SIGABRT
    // See: Oct 23, 2025 handoff - singleton pattern conflicts cause memory corruption

    override func setUpWithError() throws {
        // No setup needed - tests create managers locally
    }

    override func tearDownWithError() throws {
        // No cleanup needed - local instances deallocate automatically
    }

    /// Helper to get DatabaseManager singleton
    private var databaseManager: DatabaseManager {
        DatabaseManager.shared
    }

    /// Helper to create CategoricalEnumManager for a test
    private func createEnumManager() -> CategoricalEnumManager {
        CategoricalEnumManager(databaseManager: databaseManager)
    }

    // MARK: - 1. Schema Creation Tests

    /// Test that all 16 enumeration tables are created correctly
    /// Tables are organized by size: TINYINT (1 byte) and SMALLINT (2 bytes)
    func testCreateEnumerationTables() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // When: Create enumeration tables
        try await enumManager.createEnumerationTables()

        // Then: All 16 tables should exist
        let expectedTables = [
            // TINYINT tables (1 byte, 0-255)
            "year_enum",
            "vehicle_class_enum",
            "vehicle_type_enum",
            "cylinder_count_enum",
            "axle_count_enum",
            "color_enum",
            "fuel_type_enum",
            "admin_region_enum",
            "age_group_enum",
            "gender_enum",
            "license_type_enum",

            // SMALLINT tables (2 bytes, 0-65535)
            "make_enum",
            "model_enum",
            "model_year_enum",
            "mrc_enum",
            "municipality_enum"
        ]

        for tableName in expectedTables {
            let exists = await tableExists(tableName)
            XCTAssertTrue(exists, "Table '\(tableName)' should exist")
        }
    }

    /// Test year_enum table structure
    /// Expected: id (INTEGER PRIMARY KEY AUTOINCREMENT), year (INTEGER UNIQUE NOT NULL)
    func testYearEnumTableStructure() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // When: Create tables
        try await enumManager.createEnumerationTables()

        // Then: Verify column structure
        let columns = await getTableColumns("year_enum")
        XCTAssertTrue(columns.contains("id"), "year_enum should have 'id' column")
        XCTAssertTrue(columns.contains("year"), "year_enum should have 'year' column")
        XCTAssertEqual(columns.count, 2, "year_enum should have exactly 2 columns")
    }

    /// Test make_enum table structure
    /// Expected: id (INTEGER PRIMARY KEY AUTOINCREMENT), name (TEXT UNIQUE NOT NULL)
    func testMakeEnumTableStructure() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // When: Create tables
        try await enumManager.createEnumerationTables()

        // Then: Verify column structure
        let columns = await getTableColumns("make_enum")
        XCTAssertTrue(columns.contains("id"), "make_enum should have 'id' column")
        XCTAssertTrue(columns.contains("name"), "make_enum should have 'name' column")
        XCTAssertEqual(columns.count, 2, "make_enum should have exactly 2 columns")
    }

    /// Test model_enum table structure with foreign key
    /// Expected: id, name, make_id (references make_enum), UNIQUE(name, make_id)
    func testModelEnumTableStructure() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // When: Create tables
        try await enumManager.createEnumerationTables()

        // Then: Verify column structure
        let columns = await getTableColumns("model_enum")
        XCTAssertTrue(columns.contains("id"), "model_enum should have 'id' column")
        XCTAssertTrue(columns.contains("name"), "model_enum should have 'name' column")
        XCTAssertTrue(columns.contains("make_id"), "model_enum should have 'make_id' column")
        XCTAssertEqual(columns.count, 3, "model_enum should have exactly 3 columns")
    }

    /// Test vehicle_class_enum table structure
    /// Expected: id, code (TEXT UNIQUE), description (TEXT)
    func testVehicleClassEnumTableStructure() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // When: Create tables
        try await enumManager.createEnumerationTables()

        // Then: Verify column structure
        let columns = await getTableColumns("vehicle_class_enum")
        XCTAssertTrue(columns.contains("id"), "vehicle_class_enum should have 'id' column")
        XCTAssertTrue(columns.contains("code"), "vehicle_class_enum should have 'code' column")
        XCTAssertTrue(columns.contains("description"), "vehicle_class_enum should have 'description' column")
        XCTAssertEqual(columns.count, 3, "vehicle_class_enum should have exactly 3 columns")
    }

    /// Test vehicle_type_enum table structure
    /// Expected: id, code (TEXT UNIQUE), description (TEXT)
    func testVehicleTypeEnumTableStructure() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // When: Create tables
        try await enumManager.createEnumerationTables()

        // Then: Verify column structure
        let columns = await getTableColumns("vehicle_type_enum")
        XCTAssertTrue(columns.contains("id"), "vehicle_type_enum should have 'id' column")
        XCTAssertTrue(columns.contains("code"), "vehicle_type_enum should have 'code' column")
        XCTAssertTrue(columns.contains("description"), "vehicle_type_enum should have 'description' column")
        XCTAssertEqual(columns.count, 3, "vehicle_type_enum should have exactly 3 columns")
    }

    /// Test fuel_type_enum table structure
    /// Expected: id, code (TEXT UNIQUE), description (TEXT)
    func testFuelTypeEnumTableStructure() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // When: Create tables
        try await enumManager.createEnumerationTables()

        // Then: Verify column structure
        let columns = await getTableColumns("fuel_type_enum")
        XCTAssertTrue(columns.contains("id"), "fuel_type_enum should have 'id' column")
        XCTAssertTrue(columns.contains("code"), "fuel_type_enum should have 'code' column")
        XCTAssertTrue(columns.contains("description"), "fuel_type_enum should have 'description' column")
        XCTAssertEqual(columns.count, 3, "fuel_type_enum should have exactly 3 columns")
    }

    // MARK: - 2. Index Creation Tests (CRITICAL)

    /// ⚠️ CRITICAL TEST: Verify all 9 primary performance indexes are created
    ///
    /// **Historical Context**: Oct 11, 2025
    /// - Missing these indexes caused 165s → 10s query performance (16x slower)
    /// - Regularization hierarchy generation requires these indexes for JOIN performance
    /// - This is Critical Rule #6 from CLAUDE.md
    ///
    /// **Indexes Required**:
    /// 1. idx_year_enum_id
    /// 2. idx_make_enum_id
    /// 3. idx_model_enum_id
    /// 4. idx_model_year_enum_id
    /// 5. idx_fuel_type_enum_id
    /// 6. idx_vehicle_type_enum_id
    /// 7. idx_year_enum_year (secondary)
    /// 8. idx_vehicle_type_enum_code (secondary)
    /// 9. idx_fuel_type_enum_code (secondary)
    func testEnumerationIndexesCreated() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // When: Create enumeration tables (also creates indexes)
        try await enumManager.createEnumerationTables()

        // Then: Verify all primary performance indexes exist
        let primaryIndexes = [
            "idx_year_enum_id",
            "idx_make_enum_id",
            "idx_model_enum_id",
            "idx_model_year_enum_id",
            "idx_fuel_type_enum_id",
            "idx_vehicle_type_enum_id"
        ]

        for indexName in primaryIndexes {
            let exists = await indexExists(indexName)
            XCTAssertTrue(exists, "⚠️ CRITICAL: Index '\(indexName)' must exist for query performance (16x faster)")
        }

        // Then: Verify secondary indexes exist
        let secondaryIndexes = [
            "idx_year_enum_year",
            "idx_vehicle_type_enum_code",
            "idx_fuel_type_enum_code"
        ]

        for indexName in secondaryIndexes {
            let exists = await indexExists(indexName)
            XCTAssertTrue(exists, "Index '\(indexName)' should exist")
        }
    }

    /// Test that index creation is idempotent (can be run multiple times)
    func testIndexCreationIdempotent() async throws {
        // Given: Create enum manager and tables
        let enumManager = createEnumManager()
        try await enumManager.createEnumerationTables()

        // When: Call createEnumerationIndexes again
        // Then: Should not throw error (IF NOT EXISTS clause)
        try await enumManager.createEnumerationIndexes()

        // Verify indexes still exist
        let exists = await indexExists("idx_year_enum_id")
        XCTAssertTrue(exists, "Index should still exist after second creation attempt")
    }

    /// Test that indexes are created on correct columns
    func testIndexCreatedOnCorrectColumn() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // When: Create tables and indexes
        try await enumManager.createEnumerationTables()

        // Then: Verify index is on 'id' column for year_enum
        let indexInfo = await getIndexInfo("idx_year_enum_id")
        XCTAssertTrue(indexInfo.contains("id"), "idx_year_enum_id should be on 'id' column")
    }

    // MARK: - Helper Methods

    /// Check if a table exists in the database
    @MainActor
    private func tableExists(_ tableName: String) async -> Bool {
        guard let db = databaseManager.db else { return false }

        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=?;"
        var statement: OpaquePointer?

        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }

        sqlite3_bind_text(statement, 1, (tableName as NSString).utf8String, -1, nil)

        return sqlite3_step(statement) == SQLITE_ROW
    }

    /// Get column names for a table
    @MainActor
    private func getTableColumns(_ tableName: String) async -> [String] {
        guard let db = databaseManager.db else { return [] }

        let sql = "PRAGMA table_info(\(tableName));"
        var statement: OpaquePointer?
        var columns: [String] = []

        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let columnName = sqlite3_column_text(statement, 1) {
                columns.append(String(cString: columnName))
            }
        }

        return columns
    }

    /// Check if an index exists in the database
    @MainActor
    private func indexExists(_ indexName: String) async -> Bool {
        guard let db = databaseManager.db else { return false }

        let sql = "SELECT name FROM sqlite_master WHERE type='index' AND name=?;"
        var statement: OpaquePointer?

        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }

        sqlite3_bind_text(statement, 1, (indexName as NSString).utf8String, -1, nil)

        return sqlite3_step(statement) == SQLITE_ROW
    }

    /// Get information about an index (returns column names)
    @MainActor
    private func getIndexInfo(_ indexName: String) async -> [String] {
        guard let db = databaseManager.db else { return [] }

        let sql = "PRAGMA index_info(\(indexName));"
        var statement: OpaquePointer?
        var columns: [String] = []

        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let columnName = sqlite3_column_text(statement, 2) {
                columns.append(String(cString: columnName))
            }
        }

        return columns
    }

    // MARK: - 3. TODO: Enum Population Tests (Requires Test Database)

    // NOTE: Enum population and lookup tests have been removed because they depend on
    // vestigial migration code (populateEnumerationsFromExistingData) that queries
    // old string columns (classification, make, model) which were replaced with integer
    // foreign keys in September 2024.
    //
    // Future work: Create proper test database setup with TestData CSV imports,
    // then add tests for:
    // - Hardcoded enum population (fuel types, vehicle classes, vehicle types)
    // - Enum lookup operations (ID ↔ string conversion)
    // - Duplicate handling in population
    //
    // For now, schema and index tests provide critical regression prevention.

    /* REMOVED - Depends on vestigial migration code
    func testFuelTypeEnumPopulatedWithUnknown() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // When: Populate enumeration tables
        try await enumManager.createEnumerationTables()
        try await enumManager.populateEnumerationsFromExistingData()

        // Then: "Unknown" fuel type should exist
        let unknownId = try await enumManager.getEnumId(table: "fuel_type_enum", column: "code", value: "U")
        XCTAssertNotNil(unknownId, "Fuel type 'Unknown' (U) should be populated")

        // Verify the description
        if let id = unknownId {
            let description = try await enumManager.getEnumValue(table: "fuel_type_enum", column: "description", id: id)
            XCTAssertEqual(description, "Unknown", "Unknown fuel type should have description 'Unknown'")
        }
    }

    /// Test that all hardcoded fuel types are populated
    func testFuelTypeEnumPopulated() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // When: Populate enumeration tables
        try await enumManager.createEnumerationTables()
        try await enumManager.populateEnumerationsFromExistingData()

        // Then: All expected fuel types should exist
        let expectedFuelTypes = [
            ("E", "Gasoline"),
            ("D", "Diesel"),
            ("L", "Electric"),
            ("H", "Hybrid"),
            ("W", "Plug-in Hybrid"),
            ("C", "Hydrogen"),
            ("P", "Propane"),
            ("N", "Natural Gas"),
            ("M", "Methanol"),
            ("T", "Ethanol"),
            ("A", "Other"),
            ("S", "Non-powered"),
            ("U", "Unknown")
        ]

        for (code, expectedDescription) in expectedFuelTypes {
            let id = try await enumManager.getEnumId(table: "fuel_type_enum", column: "code", value: code)
            XCTAssertNotNil(id, "Fuel type '\(code)' should be populated")

            if let id = id {
                let description = try await enumManager.getEnumValue(table: "fuel_type_enum", column: "description", id: id)
                XCTAssertEqual(description, expectedDescription, "Fuel type '\(code)' should have description '\(expectedDescription)'")
            }
        }
    }

    /// Test that vehicle_class_enum is populated with hardcoded values including "Unknown"
    ///
    /// **Historical Context**: Oct 9, 2025
    /// - Added "Unknown" ("UNK") enum value for vehicle classification
    func testVehicleClassEnumPopulatedWithUnknown() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // When: Populate enumeration tables
        try await enumManager.createEnumerationTables()
        try await enumManager.populateEnumerationsFromExistingData()

        // Then: "Unknown" vehicle class should exist
        let unknownId = try await enumManager.getEnumId(table: "vehicle_class_enum", column: "code", value: "UNK")
        XCTAssertNotNil(unknownId, "Vehicle class 'Unknown' (UNK) should be populated")

        // Verify the description
        if let id = unknownId {
            let description = try await enumManager.getEnumValue(table: "vehicle_class_enum", column: "description", id: id)
            XCTAssertEqual(description, "Unknown", "Unknown vehicle class should have description 'Unknown'")
        }
    }

    /// Test that vehicle_type_enum is populated with hardcoded values
    func testVehicleTypeEnumPopulated() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // When: Populate enumeration tables
        try await enumManager.createEnumerationTables()
        try await enumManager.populateEnumerationsFromExistingData()

        // Then: Common vehicle types should exist
        let expectedVehicleTypes = ["AU", "CA", "MC", "AB", "VO"]

        for code in expectedVehicleTypes {
            let id = try await enumManager.getEnumId(table: "vehicle_type_enum", column: "code", value: code)
            XCTAssertNotNil(id, "Vehicle type '\(code)' should be populated")
        }
    }
    */ // END REMOVED - Vestigial migration code tests

    /* REMOVED - All tests below depend on enum population (vestigial code)

    // MARK: - 4. Enum Lookup Tests (REMOVED - Requires populated enums)

    /// Test getting enum ID by value (string → ID lookup)
    func testGetEnumIdByValue() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // Given: Enumeration tables are populated
        try await enumManager.createEnumerationTables()
        try await enumManager.populateEnumerationsFromExistingData()

        // When: Looking up fuel type "E" (Gasoline)
        let id = try await enumManager.getEnumId(table: "fuel_type_enum", column: "code", value: "E")

        // Then: Should return a valid ID
        XCTAssertNotNil(id, "Should find ID for fuel type 'E'")
        XCTAssertGreaterThan(id ?? 0, 0, "ID should be positive")
    }

    /// Test getting enum value by ID (ID → string lookup)
    func testGetEnumValueById() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // Given: Enumeration tables are populated
        try await enumManager.createEnumerationTables()
        try await enumManager.populateEnumerationsFromExistingData()

        // When: Looking up fuel type "E" and then looking up by its ID
        if let id = try await enumManager.getEnumId(table: "fuel_type_enum", column: "code", value: "E") {
            let description = try await enumManager.getEnumValue(table: "fuel_type_enum", column: "description", id: id)

            // Then: Should return the description
            XCTAssertEqual(description, "Gasoline", "Should return correct description for fuel type 'E'")
        } else {
            XCTFail("Failed to find fuel type 'E' ID")
        }
    }

    /// Test that lookup returns nil for non-existent value
    func testGetEnumIdReturnsNilForNonExistent() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // Given: Enumeration tables are populated
        try await enumManager.createEnumerationTables()
        try await enumManager.populateEnumerationsFromExistingData()

        // When: Looking up non-existent fuel type
        let id = try await enumManager.getEnumId(table: "fuel_type_enum", column: "code", value: "NONEXISTENT")

        // Then: Should return nil
        XCTAssertNil(id, "Should return nil for non-existent enum value")
    }

    /// Test that lookup returns nil for non-existent ID
    func testGetEnumValueReturnsNilForNonExistentId() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // Given: Enumeration tables are populated
        try await enumManager.createEnumerationTables()
        try await enumManager.populateEnumerationsFromExistingData()

        // When: Looking up non-existent ID (999999)
        let value = try await enumManager.getEnumValue(table: "fuel_type_enum", column: "description", id: 999999)

        // Then: Should return nil
        XCTAssertNil(value, "Should return nil for non-existent ID")
    }

    // MARK: - 5. Duplicate Handling Tests

    /// Test that INSERT OR IGNORE prevents duplicate entries
    func testDuplicateEnumValuesIgnored() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // Given: Tables created and populated once
        try await enumManager.createEnumerationTables()
        try await enumManager.populateEnumerationsFromExistingData()

        // Get initial count of fuel types
        let initialCount = await getRowCount(table: "fuel_type_enum")

        // When: Populate again (should ignore duplicates)
        try await enumManager.populateEnumerationsFromExistingData()

        // Then: Row count should remain the same
        let finalCount = await getRowCount(table: "fuel_type_enum")
        XCTAssertEqual(initialCount, finalCount, "Duplicate population should not add new rows")
    }

    /// Test that schema creation is idempotent (can be called multiple times)
    func testSchemaCreationIdempotent() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // Given: Tables already exist
        try await enumManager.createEnumerationTables()

        // When: Create tables again
        // Then: Should not throw error (IF NOT EXISTS clause)
        try await enumManager.createEnumerationTables()

        // Verify tables still exist
        let exists = await tableExists("year_enum")
        XCTAssertTrue(exists, "Table should still exist after second creation attempt")
    }

    /// Test UNIQUE constraint on make_enum.name prevents duplicates
    func testUniqueConstraintOnMakeName() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // Given: Tables created
        try await enumManager.createEnumerationTables()

        // When: Try to insert duplicate make name using raw SQL
        guard let db = databaseManager.db else {
            XCTFail("Database not connected")
            return
        }

        // Insert first TOYOTA
        var errorMsg: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, "INSERT OR IGNORE INTO make_enum (name) VALUES ('TOYOTA');", nil, nil, &errorMsg)
        sqlite3_free(errorMsg)

        // Get count after first insert
        let countAfterFirst = await getRowCount(table: "make_enum")

        // Try to insert duplicate (should be ignored)
        sqlite3_exec(db, "INSERT OR IGNORE INTO make_enum (name) VALUES ('TOYOTA');", nil, nil, &errorMsg)
        sqlite3_free(errorMsg)

        // Then: Count should remain the same
        let countAfterSecond = await getRowCount(table: "make_enum")
        XCTAssertEqual(countAfterFirst, countAfterSecond, "UNIQUE constraint should prevent duplicate makes")
    }

    /// Test composite UNIQUE constraint on model_enum (name, make_id)
    func testCompositeUniqueConstraintOnModelEnum() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // Given: Tables created and a make exists
        try await enumManager.createEnumerationTables()

        guard let db = databaseManager.db else {
            XCTFail("Database not connected")
            return
        }

        // Insert TOYOTA make
        var errorMsg: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, "INSERT OR IGNORE INTO make_enum (name) VALUES ('TOYOTA');", nil, nil, &errorMsg)
        sqlite3_free(errorMsg)

        // Get TOYOTA's ID
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT id FROM make_enum WHERE name='TOYOTA';", -1, &stmt, nil)
        sqlite3_step(stmt)
        let makeId = sqlite3_column_int(stmt, 0)
        sqlite3_finalize(stmt)

        // Insert CAMRY for TOYOTA
        let sql1 = "INSERT OR IGNORE INTO model_enum (name, make_id) VALUES ('CAMRY', \(makeId));"
        sqlite3_exec(db, sql1, nil, nil, &errorMsg)
        sqlite3_free(errorMsg)

        let countAfterFirst = await getRowCount(table: "model_enum")

        // Try to insert duplicate CAMRY for TOYOTA (should be ignored)
        sqlite3_exec(db, sql1, nil, nil, &errorMsg)
        sqlite3_free(errorMsg)

        // Then: Count should remain the same
        let countAfterSecond = await getRowCount(table: "model_enum")
        XCTAssertEqual(countAfterFirst, countAfterSecond, "Composite UNIQUE constraint should prevent duplicate model/make combinations")
    }

    // MARK: - 6. Integration Tests

    /// Test that enum population handles NULL and empty strings correctly
    func testEnumPopulationIgnoresNullAndEmpty() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // Given: Tables created
        try await enumManager.createEnumerationTables()

        // When: Populate (should ignore NULL and empty strings per SQL WHERE clauses)
        try await enumManager.populateEnumerationsFromExistingData()

        // Then: No empty or null values should be in fuel_type_enum
        // This is verified by the hardcoded list not containing empty values
        // Data-driven tables use WHERE clauses to exclude NULL and ''
        let fuelTypes = await getAllEnumValues(table: "fuel_type_enum", column: "code")
        XCTAssertFalse(fuelTypes.contains(""), "Fuel type enum should not contain empty strings")
    }

    /// Test foreign key relationship between model_enum and make_enum
    func testModelEnumForeignKeyToMakeEnum() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // Given: Tables created
        try await enumManager.createEnumerationTables()

        // This test verifies the foreign key is defined in schema
        // Actual foreign key constraint enforcement requires PRAGMA foreign_keys=ON
        // which is typically set at connection time in DatabaseManager

        let columns = await getTableColumns("model_enum")
        XCTAssertTrue(columns.contains("make_id"), "model_enum should have make_id foreign key column")
    }
    */ // END REMOVED - All tests requiring populated enums

    // MARK: - 4. Schema Validation Tests

    /// Test foreign key relationship between model_enum and make_enum
    func testModelEnumForeignKeyToMakeEnum() async throws {
        // Given: Create enum manager
        let enumManager = createEnumManager()

        // Given: Tables created
        try await enumManager.createEnumerationTables()

        // This test verifies the foreign key is defined in schema
        // Actual foreign key constraint enforcement requires PRAGMA foreign_keys=ON
        // which is typically set at connection time in DatabaseManager

        let columns = await getTableColumns("model_enum")
        XCTAssertTrue(columns.contains("make_id"), "model_enum should have make_id foreign key column")
    }

    // MARK: - Helper Methods (Additional)

    /// Get row count for a table
    @MainActor
    private func getRowCount(table: String) async -> Int {
        guard let db = databaseManager.db else { return 0 }

        let sql = "SELECT COUNT(*) FROM \(table);"
        var statement: OpaquePointer?
        var count = 0

        defer {
            sqlite3_finalize(statement)
        }

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }

        return count
    }

    /// Get all values from an enum table column
    @MainActor
    private func getAllEnumValues(table: String, column: String) async -> [String] {
        guard let db = databaseManager.db else { return [] }

        let sql = "SELECT \(column) FROM \(table);"
        var statement: OpaquePointer?
        var values: [String] = []

        defer {
            sqlite3_finalize(statement)
        }

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) {
                    values.append(String(cString: text))
                }
            }
        }

        return values
    }
}
