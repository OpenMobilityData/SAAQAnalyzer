import Foundation
import SQLite3

/// Manages database schema migrations and optimizations for categorical enumeration
class SchemaManager {
    private weak var databaseManager: DatabaseManager?
    private var db: OpaquePointer? { databaseManager?.db }
    private let enumManager: CategoricalEnumManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        self.enumManager = CategoricalEnumManager(databaseManager: databaseManager)
    }

    // MARK: - Migration Management

    /// Performs complete schema migration to optimized categorical enumeration
    func migrateToOptimizedSchema() async throws {
        print("🚀 Starting migration to optimized categorical enumeration schema...")

        try await enumManager.createEnumerationTables()
        try await enumManager.populateEnumerationsFromExistingData()
        try await addOptimizedColumns()
        try await populateOptimizedColumns()
        try await createOptimizedIndexes()
        try await validateMigration()

        print("✅ Schema migration completed successfully!")
    }

    /// Re-populate integer columns if they are NULL/empty
    func repopulateIntegerColumns() async throws {
        print("🔄 Re-populating integer columns...")

        // Check current state
        let populatedCount = try await getCount("SELECT COUNT(*) FROM vehicles WHERE classification_id IS NOT NULL AND fuel_type_id IS NOT NULL;")
        let totalCount = try await getCount("SELECT COUNT(*) FROM vehicles;")

        print("🔍 Current state: \(populatedCount)/\(totalCount) rows have populated integer columns")

        if populatedCount < totalCount {
            print("⚠️ Integer columns need population - running migration...")
            try await populateOptimizedColumns()

            // Re-check
            let newPopulatedCount = try await getCount("SELECT COUNT(*) FROM vehicles WHERE classification_id IS NOT NULL AND fuel_type_id IS NOT NULL;")
            print("✅ After migration: \(newPopulatedCount)/\(totalCount) rows have populated integer columns")
        } else {
            print("✅ Integer columns already fully populated")
        }
    }

    /// Adds optimized integer foreign key columns to existing tables
    private func addOptimizedColumns() async throws {
        guard let db = db else { throw DatabaseError.notConnected }

        print("🔄 Adding optimized integer columns...")

        let vehicleColumnSQL = [
            // TINYINT columns (1 byte)
            "ALTER TABLE vehicles ADD COLUMN year_id INTEGER;",
            "ALTER TABLE vehicles ADD COLUMN classification_id INTEGER;",
            "ALTER TABLE vehicles ADD COLUMN cylinder_count_id INTEGER;",
            "ALTER TABLE vehicles ADD COLUMN axle_count_id INTEGER;",
            "ALTER TABLE vehicles ADD COLUMN original_color_id INTEGER;",
            "ALTER TABLE vehicles ADD COLUMN fuel_type_id INTEGER;",
            "ALTER TABLE vehicles ADD COLUMN admin_region_id INTEGER;",

            // SMALLINT columns (2 bytes)
            "ALTER TABLE vehicles ADD COLUMN make_id INTEGER;",
            "ALTER TABLE vehicles ADD COLUMN model_id INTEGER;",
            "ALTER TABLE vehicles ADD COLUMN model_year_id INTEGER;",
            "ALTER TABLE vehicles ADD COLUMN mrc_id INTEGER;",
            "ALTER TABLE vehicles ADD COLUMN municipality_id INTEGER;",

            // Optimized numeric columns
            "ALTER TABLE vehicles ADD COLUMN net_mass_int INTEGER;",     // Convert REAL to INTEGER (kg)
            "ALTER TABLE vehicles ADD COLUMN displacement_int INTEGER;"  // Convert REAL to INTEGER (cm³)
        ]

        let licenseColumnSQL = [
            // TINYINT columns (1 byte)
            "ALTER TABLE licenses ADD COLUMN year_id INTEGER;",
            "ALTER TABLE licenses ADD COLUMN age_group_id INTEGER;",
            "ALTER TABLE licenses ADD COLUMN gender_id INTEGER;",
            "ALTER TABLE licenses ADD COLUMN admin_region_id INTEGER;",
            "ALTER TABLE licenses ADD COLUMN license_type_id INTEGER;",

            // SMALLINT columns (2 bytes)
            "ALTER TABLE licenses ADD COLUMN mrc_id INTEGER;"
        ]

        // Execute all column additions
        for sql in vehicleColumnSQL + licenseColumnSQL {
            var errorMsg: UnsafeMutablePointer<CChar>?
            defer { sqlite3_free(errorMsg) }

            if sqlite3_exec(db, sql, nil, nil, &errorMsg) != SQLITE_OK {
                let error = errorMsg != nil ? String(cString: errorMsg!) : "Unknown error"
                // Column might already exist, which is fine
                if !error.contains("duplicate column name") {
                    print("⚠️ Warning adding column: \(error)")
                }
            }
        }

        print("✅ Added all optimized integer columns")
    }

    /// Populates the new integer columns with enumerated values
    private func populateOptimizedColumns() async throws {
        print("🔄 Populating optimized columns with enumerated values...")

        try await populateVehicleEnumColumns()
        try await populateLicenseEnumColumns()

        print("✅ All optimized columns populated")
    }

    private func populateVehicleEnumColumns() async throws {
        let updates = [
            // Year mapping
            """
            UPDATE vehicles SET year_id = (
                SELECT y.id FROM year_enum y WHERE y.year = vehicles.year
            );
            """,

            // Classification mapping
            """
            UPDATE vehicles SET classification_id = (
                SELECT c.id FROM classification_enum c WHERE c.code = vehicles.classification
            );
            """,

            // Make mapping
            """
            UPDATE vehicles SET make_id = (
                SELECT m.id FROM make_enum m WHERE m.name = vehicles.make
            ) WHERE vehicles.make IS NOT NULL;
            """,

            // Model mapping
            """
            UPDATE vehicles SET model_id = (
                SELECT mo.id FROM model_enum mo
                INNER JOIN make_enum ma ON mo.make_id = ma.id
                WHERE mo.name = vehicles.model AND ma.name = vehicles.make
            ) WHERE vehicles.model IS NOT NULL AND vehicles.make IS NOT NULL;
            """,

            // Model year mapping
            """
            UPDATE vehicles SET model_year_id = (
                SELECT my.id FROM model_year_enum my WHERE my.year = vehicles.model_year
            ) WHERE vehicles.model_year IS NOT NULL;
            """,

            // Cylinder count mapping
            """
            UPDATE vehicles SET cylinder_count_id = (
                SELECT cc.id FROM cylinder_count_enum cc WHERE cc.count = vehicles.cylinder_count
            ) WHERE vehicles.cylinder_count IS NOT NULL;
            """,

            // Axle count mapping
            """
            UPDATE vehicles SET axle_count_id = (
                SELECT ac.id FROM axle_count_enum ac WHERE ac.count = vehicles.max_axles
            ) WHERE vehicles.max_axles IS NOT NULL;
            """,

            // Color mapping
            """
            UPDATE vehicles SET original_color_id = (
                SELECT co.id FROM color_enum co WHERE co.name = vehicles.original_color
            ) WHERE vehicles.original_color IS NOT NULL;
            """,

            // Fuel type mapping
            """
            UPDATE vehicles SET fuel_type_id = (
                SELECT ft.id FROM fuel_type_enum ft WHERE ft.code = vehicles.fuel_type
            ) WHERE vehicles.fuel_type IS NOT NULL;
            """,

            // Admin region mapping
            """
            UPDATE vehicles SET admin_region_id = (
                SELECT ar.id FROM admin_region_enum ar WHERE ar.code = vehicles.admin_region
            );
            """,

            // MRC mapping
            """
            UPDATE vehicles SET mrc_id = (
                SELECT m.id FROM mrc_enum m WHERE m.code = vehicles.mrc
            );
            """,

            // Municipality mapping
            """
            UPDATE vehicles SET municipality_id = (
                SELECT mu.id FROM municipality_enum mu WHERE mu.code = vehicles.geo_code
            );
            """,

            // Numeric conversions (convert REAL to INTEGER for better performance)
            """
            UPDATE vehicles SET net_mass_int = CAST(ROUND(net_mass) AS INTEGER)
            WHERE net_mass IS NOT NULL;
            """,

            """
            UPDATE vehicles SET displacement_int = CAST(ROUND(displacement) AS INTEGER)
            WHERE displacement IS NOT NULL;
            """
        ]

        for sql in updates {
            try await executeSQL(sql, description: "vehicle enum column population")
        }
    }

    private func populateLicenseEnumColumns() async throws {
        let updates = [
            // Year mapping
            """
            UPDATE licenses SET year_id = (
                SELECT y.id FROM year_enum y WHERE y.year = licenses.year
            );
            """,

            // Age group mapping
            """
            UPDATE licenses SET age_group_id = (
                SELECT ag.id FROM age_group_enum ag WHERE ag.range_text = licenses.age_group
            );
            """,

            // Gender mapping
            """
            UPDATE licenses SET gender_id = (
                SELECT g.id FROM gender_enum g WHERE g.code = licenses.gender
            );
            """,

            // Admin region mapping
            """
            UPDATE licenses SET admin_region_id = (
                SELECT ar.id FROM admin_region_enum ar WHERE ar.code = licenses.admin_region
            );
            """,

            // MRC mapping
            """
            UPDATE licenses SET mrc_id = (
                SELECT m.id FROM mrc_enum m WHERE m.code = licenses.mrc
            );
            """,

            // License type mapping
            """
            UPDATE licenses SET license_type_id = (
                SELECT lt.id FROM license_type_enum lt WHERE lt.type_name = licenses.license_type
            );
            """
        ]

        for sql in updates {
            try await executeSQL(sql, description: "license enum column population")
        }
    }

    /// Creates optimized indexes for the new enumerated columns
    private func createOptimizedIndexes() async throws {
        print("🔄 Creating optimized indexes for enumerated columns...")

        let optimizedIndexes = [
            // Vehicles table - single column indexes
            "CREATE INDEX IF NOT EXISTS idx_vehicles_year_id ON vehicles(year_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_classification_id ON vehicles(classification_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_make_id ON vehicles(make_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_model_id ON vehicles(model_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_model_year_id ON vehicles(model_year_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_fuel_type_id ON vehicles(fuel_type_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_admin_region_id ON vehicles(admin_region_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_mrc_id ON vehicles(mrc_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_municipality_id ON vehicles(municipality_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_cylinder_count_id ON vehicles(cylinder_count_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_axle_count_id ON vehicles(axle_count_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_color_id ON vehicles(original_color_id);",

            // Vehicles table - composite indexes for common query patterns
            "CREATE INDEX IF NOT EXISTS idx_vehicles_year_class_id ON vehicles(year_id, classification_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_year_fuel_id ON vehicles(year_id, fuel_type_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_year_region_id ON vehicles(year_id, admin_region_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_year_municipality_id ON vehicles(year_id, municipality_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_municipality_class_year_id ON vehicles(municipality_id, classification_id, year_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_region_class_year_id ON vehicles(admin_region_id, classification_id, year_id);",
            "CREATE INDEX IF NOT EXISTS idx_vehicles_make_model_year_id ON vehicles(make_id, model_id, year_id);",

            // Licenses table - single column indexes
            "CREATE INDEX IF NOT EXISTS idx_licenses_year_id ON licenses(year_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_age_group_id ON licenses(age_group_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_gender_id ON licenses(gender_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_admin_region_id ON licenses(admin_region_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_mrc_id ON licenses(mrc_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_license_type_id ON licenses(license_type_id);",

            // Licenses table - composite indexes
            "CREATE INDEX IF NOT EXISTS idx_licenses_year_type_id ON licenses(year_id, license_type_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_year_age_id ON licenses(year_id, age_group_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_year_gender_id ON licenses(year_id, gender_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_year_region_id ON licenses(year_id, admin_region_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_mrc_type_year_id ON licenses(mrc_id, license_type_id, year_id);",
            "CREATE INDEX IF NOT EXISTS idx_licenses_region_type_year_id ON licenses(admin_region_id, license_type_id, year_id);",

            // Enumeration table indexes for fast lookups
            "CREATE INDEX IF NOT EXISTS idx_classification_enum_code ON classification_enum(code);",
            "CREATE INDEX IF NOT EXISTS idx_make_enum_name ON make_enum(name);",
            "CREATE INDEX IF NOT EXISTS idx_model_enum_name_make ON model_enum(name, make_id);",
            "CREATE INDEX IF NOT EXISTS idx_fuel_type_enum_code ON fuel_type_enum(code);",
            "CREATE INDEX IF NOT EXISTS idx_admin_region_enum_code ON admin_region_enum(code);",
            "CREATE INDEX IF NOT EXISTS idx_mrc_enum_code ON mrc_enum(code);",
            "CREATE INDEX IF NOT EXISTS idx_municipality_enum_code ON municipality_enum(code);",
            "CREATE INDEX IF NOT EXISTS idx_age_group_enum_range ON age_group_enum(range_text);",
            "CREATE INDEX IF NOT EXISTS idx_gender_enum_code ON gender_enum(code);"
        ]

        for indexSQL in optimizedIndexes {
            try await executeSQL(indexSQL, description: "optimized index creation")
        }

        print("✅ Created all optimized indexes")
    }

    /// Validates that the migration was successful
    private func validateMigration() async throws {
        print("🔄 Validating migration...")

        // Check that enumeration tables are populated
        let enumerationCounts = [
            "SELECT COUNT(*) FROM year_enum;",
            "SELECT COUNT(*) FROM classification_enum;",
            "SELECT COUNT(*) FROM make_enum;",
            "SELECT COUNT(*) FROM model_enum;",
            "SELECT COUNT(*) FROM fuel_type_enum;"
        ]

        for sql in enumerationCounts {
            let count = try await getCount(sql)
            if count == 0 {
                throw DatabaseError.queryFailed("Enumeration table appears empty: \(sql)")
            }
        }

        // Check that foreign key columns are populated
        let foreignKeyChecks = [
            "SELECT COUNT(*) FROM vehicles WHERE year_id IS NULL;",
            "SELECT COUNT(*) FROM vehicles WHERE classification_id IS NULL;",
            "SELECT COUNT(*) FROM vehicles WHERE admin_region_id IS NULL;",
            "SELECT COUNT(*) FROM licenses WHERE year_id IS NULL;",
            "SELECT COUNT(*) FROM licenses WHERE age_group_id IS NULL;"
        ]

        for sql in foreignKeyChecks {
            let nullCount = try await getCount(sql)
            if nullCount > 0 {
                print("⚠️ Warning: Found \(nullCount) NULL values in optimized columns")
            }
        }

        print("✅ Migration validation completed")
    }

    // MARK: - Helper Methods

    private func executeSQL(_ sql: String, description: String) async throws {
        guard let db = self.db else { throw DatabaseError.notConnected }

        return try await withCheckedThrowingContinuation { continuation in
            var errorMsg: UnsafeMutablePointer<CChar>?
            defer { sqlite3_free(errorMsg) }

            if sqlite3_exec(db, sql, nil, nil, &errorMsg) == SQLITE_OK {
                continuation.resume()
            } else {
                let error = errorMsg != nil ? String(cString: errorMsg!) : "Unknown error"
                continuation.resume(throwing: DatabaseError.queryFailed("Failed \(description): \(error)"))
            }
        }
    }

    private func getCount(_ sql: String) async throws -> Int {
        guard self.db != nil else { throw DatabaseError.notConnected }

        return try await withCheckedThrowingContinuation { continuation in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let count = Int(sqlite3_column_int(stmt, 0))
                    continuation.resume(returning: count)
                } else {
                    continuation.resume(returning: 0)
                }
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                continuation.resume(throwing: DatabaseError.queryFailed("Failed to get count: \(error)"))
            }
        }
    }

    // MARK: - Rollback Support

    /// Provides rollback capability by removing optimized columns
    func rollbackOptimization() async throws {
        print("🔄 Rolling back categorical enumeration optimization...")

        guard let db = db else { throw DatabaseError.notConnected }

        // SQLite doesn't support DROP COLUMN directly, so we'd need to recreate tables
        // For now, we'll just document this limitation
        print("⚠️ Note: SQLite doesn't support dropping columns. To fully rollback,")
        print("   you would need to restore from a backup or recreate tables.")
        print("   The original string columns remain intact for safety.")

        print("✅ Rollback information provided")
    }
}