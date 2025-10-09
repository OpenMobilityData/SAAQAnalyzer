import Foundation
import SQLite3

/// Manages categorical enumeration tables and provides efficient lookup operations
class CategoricalEnumManager {
    private weak var databaseManager: DatabaseManager?
    private var db: OpaquePointer? { databaseManager?.db }

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    // MARK: - Schema Creation

    /// Creates all enumeration tables with optimal integer sizes
    func createEnumerationTables() async throws {
        guard let db = db else { throw DatabaseError.notConnected }

        let enumerationTables = [
            // TINYINT tables (1 byte, 0-255)
            createYearEnumTable(),
            createClassificationEnumTable(),
            createCylinderCountEnumTable(),
            createAxleCountEnumTable(),
            createColorEnumTable(),
            createFuelTypeEnumTable(),
            createAdminRegionEnumTable(),
            createAgeGroupEnumTable(),
            createGenderEnumTable(),
            createLicenseTypeEnumTable(),

            // SMALLINT tables (2 bytes, 0-65535)
            createMakeEnumTable(),
            createModelEnumTable(),
            createModelYearEnumTable(),
            createMRCEnumTable(),
            createMunicipalityEnumTable()
        ]

        for tableSQL in enumerationTables {
            var errorMsg: UnsafeMutablePointer<CChar>?
            defer { sqlite3_free(errorMsg) }

            if sqlite3_exec(db, tableSQL, nil, nil, &errorMsg) != SQLITE_OK {
                let error = errorMsg != nil ? String(cString: errorMsg!) : "Unknown error"
                throw DatabaseError.queryFailed("Failed to create enumeration table: \(error)")
            }
        }

        print("✅ Created all categorical enumeration tables")
    }

    // MARK: - Table Creation SQL

    private func createYearEnumTable() -> String {
        """
        CREATE TABLE IF NOT EXISTS year_enum (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            year INTEGER UNIQUE NOT NULL
        );
        """
    }

    private func createClassificationEnumTable() -> String {
        """
        CREATE TABLE IF NOT EXISTS classification_enum (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT UNIQUE NOT NULL,
            description TEXT NOT NULL
        );
        """
    }

    private func createMakeEnumTable() -> String {
        """
        CREATE TABLE IF NOT EXISTS make_enum (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL
        );
        """
    }

    private func createModelEnumTable() -> String {
        """
        CREATE TABLE IF NOT EXISTS model_enum (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            make_id INTEGER NOT NULL REFERENCES make_enum(id),
            UNIQUE(name, make_id)
        );
        """
    }

    private func createModelYearEnumTable() -> String {
        """
        CREATE TABLE IF NOT EXISTS model_year_enum (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            year INTEGER UNIQUE NOT NULL
        );
        """
    }

    private func createCylinderCountEnumTable() -> String {
        """
        CREATE TABLE IF NOT EXISTS cylinder_count_enum (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            count INTEGER UNIQUE NOT NULL
        );
        """
    }

    private func createAxleCountEnumTable() -> String {
        """
        CREATE TABLE IF NOT EXISTS axle_count_enum (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            count INTEGER UNIQUE NOT NULL
        );
        """
    }

    private func createColorEnumTable() -> String {
        """
        CREATE TABLE IF NOT EXISTS color_enum (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL
        );
        """
    }

    private func createFuelTypeEnumTable() -> String {
        """
        CREATE TABLE IF NOT EXISTS fuel_type_enum (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT UNIQUE NOT NULL,
            description TEXT NOT NULL
        );
        """
    }

    private func createAdminRegionEnumTable() -> String {
        """
        CREATE TABLE IF NOT EXISTS admin_region_enum (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL
        );
        """
    }

    private func createMRCEnumTable() -> String {
        """
        CREATE TABLE IF NOT EXISTS mrc_enum (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL
        );
        """
    }

    private func createMunicipalityEnumTable() -> String {
        """
        CREATE TABLE IF NOT EXISTS municipality_enum (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL
        );
        """
    }

    private func createAgeGroupEnumTable() -> String {
        """
        CREATE TABLE IF NOT EXISTS age_group_enum (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            range_text TEXT UNIQUE NOT NULL
        );
        """
    }

    private func createGenderEnumTable() -> String {
        """
        CREATE TABLE IF NOT EXISTS gender_enum (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT UNIQUE NOT NULL,
            description TEXT NOT NULL
        );
        """
    }

    private func createLicenseTypeEnumTable() -> String {
        """
        CREATE TABLE IF NOT EXISTS license_type_enum (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type_name TEXT UNIQUE NOT NULL,
            description TEXT NOT NULL
        );
        """
    }

    // MARK: - Data Population

    /// Populates enumeration tables from existing string data in main tables
    func populateEnumerationsFromExistingData() async throws {
        guard self.db != nil else { throw DatabaseError.notConnected }

        print("🔄 Populating categorical enumerations from existing data...")

        // Populate in dependency order (referenced tables first)
        try await populateYearEnum()
        try await populateClassificationEnum()
        try await populateMakeEnum()
        try await populateModelEnum()  // Depends on make_enum
        try await populateModelYearEnum()
        try await populateCylinderCountEnum()
        try await populateAxleCountEnum()
        try await populateColorEnum()
        try await populateFuelTypeEnum()
        try await populateAdminRegionEnum()
        try await populateMRCEnum()
        try await populateMunicipalityEnum()
        try await populateAgeGroupEnum()
        try await populateGenderEnum()
        try await populateLicenseTypeEnum()

        print("✅ All categorical enumerations populated")
    }

    private func populateYearEnum() async throws {
        let sql = """
        INSERT OR IGNORE INTO year_enum (year)
        SELECT DISTINCT year FROM vehicles
        UNION
        SELECT DISTINCT year FROM licenses
        ORDER BY year;
        """
        try await executeSQL(sql, description: "year enum")
    }

    private func populateClassificationEnum() async throws {
        // Use hardcoded mappings for vehicle classifications to ensure consistent descriptions
        let classifications = [
            // Personal Use
            ("PAU", "Personal automobile/light truck"),
            ("PMC", "Personal motorcycle"),
            ("PCY", "Personal moped"),
            ("PHM", "Personal motorhome"),
            // Commercial Use
            ("CAU", "Commercial automobile/light truck"),
            ("CMC", "Commercial motorcycle"),
            ("CCY", "Commercial moped"),
            ("CHM", "Commercial motorhome"),
            ("TTA", "Taxi"),
            ("TAB", "Bus"),
            ("TAS", "School bus"),
            ("BCA", "Truck/road tractor"),
            ("CVO", "Tool vehicle"),
            ("COT", "Other commercial"),
            // Restricted Circulation
            ("RAU", "Restricted automobile/light truck"),
            ("RMC", "Restricted motorcycle"),
            ("RCY", "Restricted moped"),
            ("RHM", "Restricted motorhome"),
            ("RAB", "Restricted bus"),
            ("RCA", "Restricted truck"),
            ("RMN", "Restricted snowmobile"),
            ("ROT", "Other restricted"),
            // Off-Road Use
            ("HAU", "Off-road automobile/light truck"),
            ("HCY", "Off-road moped"),
            ("HAB", "Off-road bus"),
            ("HCA", "Off-road truck/road tractor"),
            ("HMN", "Off-road snowmobile"),
            ("HVT", "Off-road all-terrain vehicle"),
            ("HVO", "Off-road tool vehicle"),
            ("HOT", "Other off-road"),
            // Special value for regularization
            ("UNK", "Unknown")
        ]

        for (code, description) in classifications {
            let sql = "INSERT OR IGNORE INTO classification_enum (code, description) VALUES (?, ?);"
            try await executeSQL(sql, parameters: [code, description], description: "classification enum")
        }

        // Also populate any classifications found in data that aren't in our hardcoded list
        let sql = """
        INSERT OR IGNORE INTO classification_enum (code, description)
        SELECT DISTINCT classification, classification
        FROM vehicles
        WHERE classification NOT IN (SELECT code FROM classification_enum);
        """
        try await executeSQL(sql, description: "additional classifications")
    }

    private func populateMakeEnum() async throws {
        let sql = """
        INSERT OR IGNORE INTO make_enum (name)
        SELECT DISTINCT make
        FROM vehicles
        WHERE make IS NOT NULL AND make != ''
        ORDER BY make;
        """
        try await executeSQL(sql, description: "make enum")
    }

    private func populateModelEnum() async throws {
        let sql = """
        INSERT OR IGNORE INTO model_enum (name, make_id)
        SELECT DISTINCT v.model, m.id
        FROM vehicles v
        INNER JOIN make_enum m ON v.make = m.name
        WHERE v.model IS NOT NULL AND v.model != ''
        ORDER BY v.model;
        """
        try await executeSQL(sql, description: "model enum")
    }

    private func populateModelYearEnum() async throws {
        let sql = """
        INSERT OR IGNORE INTO model_year_enum (year)
        SELECT DISTINCT model_year
        FROM vehicles
        WHERE model_year IS NOT NULL
        ORDER BY model_year;
        """
        try await executeSQL(sql, description: "model year enum")
    }

    private func populateCylinderCountEnum() async throws {
        let sql = """
        INSERT OR IGNORE INTO cylinder_count_enum (count)
        SELECT DISTINCT cylinder_count
        FROM vehicles
        WHERE cylinder_count IS NOT NULL
        ORDER BY cylinder_count;
        """
        try await executeSQL(sql, description: "cylinder count enum")
    }

    private func populateAxleCountEnum() async throws {
        let sql = """
        INSERT OR IGNORE INTO axle_count_enum (count)
        SELECT DISTINCT max_axles
        FROM vehicles
        WHERE max_axles IS NOT NULL
        ORDER BY max_axles;
        """
        try await executeSQL(sql, description: "axle count enum")
    }

    private func populateColorEnum() async throws {
        let sql = """
        INSERT OR IGNORE INTO color_enum (name)
        SELECT DISTINCT original_color
        FROM vehicles
        WHERE original_color IS NOT NULL AND original_color != ''
        ORDER BY original_color;
        """
        try await executeSQL(sql, description: "color enum")
    }

    private func populateFuelTypeEnum() async throws {
        // Use hardcoded mappings for fuel types
        let fuelTypes = [
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

        for (code, description) in fuelTypes {
            let sql = "INSERT OR IGNORE INTO fuel_type_enum (code, description) VALUES (?, ?);"
            try await executeSQL(sql, parameters: [code, description], description: "fuel type enum")
        }
    }

    private func populateAdminRegionEnum() async throws {
        let sql = """
        INSERT OR IGNORE INTO admin_region_enum (code, name)
        SELECT DISTINCT admin_region, admin_region
        FROM vehicles
        WHERE admin_region IS NOT NULL AND admin_region != ''
        UNION
        SELECT DISTINCT admin_region, admin_region
        FROM licenses
        WHERE admin_region IS NOT NULL AND admin_region != ''
        ORDER BY admin_region;
        """
        try await executeSQL(sql, description: "admin region enum")
    }

    private func populateMRCEnum() async throws {
        let sql = """
        INSERT OR IGNORE INTO mrc_enum (code, name)
        SELECT DISTINCT mrc, mrc
        FROM vehicles
        WHERE mrc IS NOT NULL AND mrc != ''
        UNION
        SELECT DISTINCT mrc, mrc
        FROM licenses
        WHERE mrc IS NOT NULL AND mrc != ''
        ORDER BY mrc;
        """
        try await executeSQL(sql, description: "MRC enum")
    }

    private func populateMunicipalityEnum() async throws {
        let sql = """
        INSERT OR IGNORE INTO municipality_enum (code, name)
        SELECT DISTINCT v.geo_code, COALESCE(g.name, v.geo_code) as name
        FROM vehicles v
        LEFT JOIN geographic_entities g ON v.geo_code = g.code AND g.type = 'municipality'
        WHERE v.geo_code IS NOT NULL AND v.geo_code != ''
        ORDER BY v.geo_code;
        """
        try await executeSQL(sql, description: "municipality enum")
    }

    private func populateAgeGroupEnum() async throws {
        let ageGroups = [
            "16-19", "20-24", "25-34", "35-44",
            "45-54", "55-64", "65-74", "75+"
        ]

        for ageGroup in ageGroups {
            let sql = "INSERT OR IGNORE INTO age_group_enum (range_text) VALUES (?);"
            try await executeSQL(sql, parameters: [ageGroup], description: "age group enum")
        }
    }

    private func populateGenderEnum() async throws {
        let genders = [
            ("M", "Male"),
            ("F", "Female")
        ]

        for (code, description) in genders {
            let sql = "INSERT OR IGNORE INTO gender_enum (code, description) VALUES (?, ?);"
            try await executeSQL(sql, parameters: [code, description], description: "gender enum")
        }
    }

    private func populateLicenseTypeEnum() async throws {
        let licenseTypes = [
            ("APPRENTI", "Learner's Permit"),
            ("PROBATOIRE", "Probationary License"),
            ("RÉGULIER", "Regular License")
        ]

        for (type, description) in licenseTypes {
            let sql = "INSERT OR IGNORE INTO license_type_enum (type_name, description) VALUES (?, ?);"
            try await executeSQL(sql, parameters: [type, description], description: "license type enum")
        }
    }

    // MARK: - Helper Methods

    private func executeSQL(_ sql: String, parameters: [Any] = [], description: String) async throws {
        guard let db = self.db else { throw DatabaseError.notConnected }

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                // Bind parameters
                for (index, parameter) in parameters.enumerated() {
                    let bindIndex = Int32(index + 1)

                    if let stringParam = parameter as? String {
                        sqlite3_bind_text(stmt, bindIndex, stringParam, -1, nil)
                    } else if let intParam = parameter as? Int {
                        sqlite3_bind_int(stmt, bindIndex, Int32(intParam))
                    }
                }

                if sqlite3_step(stmt) == SQLITE_DONE {
                    print("✅ Populated \(description)")
                    continuation.resume()
                } else {
                    let error = String(cString: sqlite3_errmsg(db))
                    continuation.resume(throwing: DatabaseError.queryFailed("Failed to populate \(description): \(error)"))
                }
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to prepare \(description): \(error)"))
            }
        }
    }

    // MARK: - Lookup Methods

    /// Get enumeration ID for a string value
    func getEnumId(table: String, column: String, value: String) async throws -> Int? {
        guard let db = self.db else { throw DatabaseError.notConnected }

        let sql = "SELECT id FROM \(table) WHERE \(column) = ? LIMIT 1;"

        // Debug the lookup
        print("🔍 Searching \(table).\(column) for value: '\(value)'")

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                sqlite3_bind_text(stmt, 1, value, -1, SQLITE_TRANSIENT)

                if sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    print("✅ Found match: '\(value)' -> ID \(id)")
                    continuation.resume(returning: id)
                } else {
                    print("❌ No match found for '\(value)' in \(table).\(column)")

                    // Debug: Show what's actually in the table to compare
                    print("🔍 Checking what values exist in \(table).\(column)...")
                    let debugSQL = "SELECT id, \(column) FROM \(table) LIMIT 5;"
                    var debugStmt: OpaquePointer?
                    defer { sqlite3_finalize(debugStmt) }

                    if sqlite3_prepare_v2(db, debugSQL, -1, &debugStmt, nil) == SQLITE_OK {
                        while sqlite3_step(debugStmt) == SQLITE_ROW {
                            let id = Int(sqlite3_column_int(debugStmt, 0))
                            let actualValue = String(cString: sqlite3_column_text(debugStmt, 1))
                            print("   ID \(id): \(column)='\(actualValue)'")

                            // Compare byte-by-byte with the search value
                            if actualValue == value {
                                print("   ✅ String equality check passes for ID \(id)")
                                print("   💡 Using this ID since Swift string equality works!")
                                continuation.resume(returning: id)
                                return
                            } else {
                                print("   ❌ String equality fails:")
                                print("     Search: \(value.debugDescription) (count: \(value.count))")
                                print("     Stored: \(actualValue.debugDescription) (count: \(actualValue.count))")

                                // Check if they're visually similar but different
                                if actualValue.trimmingCharacters(in: .whitespacesAndNewlines) == value.trimmingCharacters(in: .whitespacesAndNewlines) {
                                    print("     💡 Match after trimming whitespace - using ID \(id)")
                                    continuation.resume(returning: id)
                                    return
                                }
                            }
                        }
                    }

                    // Try a fuzzy match using LIKE to handle encoding issues
                    print("🔍 Trying fuzzy match with LIKE...")
                    let fuzzySQL = "SELECT id, \(column) FROM \(table) WHERE \(column) LIKE ? LIMIT 1;"
                    var fuzzyStmt: OpaquePointer?
                    defer { sqlite3_finalize(fuzzyStmt) }

                    if sqlite3_prepare_v2(db, fuzzySQL, -1, &fuzzyStmt, nil) == SQLITE_OK {
                        let likePattern = "%\(value)%"
                        sqlite3_bind_text(fuzzyStmt, 1, likePattern, -1, nil)

                        if sqlite3_step(fuzzyStmt) == SQLITE_ROW {
                            let fuzzyId = Int(sqlite3_column_int(fuzzyStmt, 0))
                            let actualValue = String(cString: sqlite3_column_text(fuzzyStmt, 1))
                            print("✅ Fuzzy match found: '\(actualValue)' -> ID \(fuzzyId)")
                            continuation.resume(returning: fuzzyId)
                        } else {
                            print("❌ No fuzzy match found either")
                            continuation.resume(returning: nil)
                        }
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                print("❌ SQL error in getEnumId: \(error)")
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to lookup enum: \(error)"))
            }
        }
    }

    /// Get string value for an enumeration ID
    func getEnumValue(table: String, column: String, id: Int) async throws -> String? {
        guard let db = self.db else { throw DatabaseError.notConnected }

        let sql = "SELECT \(column) FROM \(table) WHERE id = ? LIMIT 1;"

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(id))

                if sqlite3_step(stmt) == SQLITE_ROW {
                    let value = String(cString: sqlite3_column_text(stmt, 0))
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(returning: nil)
                }
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to lookup enum value: \(error)"))
            }
        }
    }
}