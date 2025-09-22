import Foundation
import SQLite3

/// Handles importing Quebec geographic codes from d001 and d002 files
class GeographicDataImporter {
    private let databaseManager: DatabaseManager
    
    init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }
    
    /// Imports the d001 municipality data file
    func importD001File(at url: URL) async throws {
        let content = try String(contentsOf: url, encoding: .isoLatin1)
        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
        
        var municipalities: [Municipality] = []
        
        for line in lines {
            // Skip header line (type 0)
            if line.hasPrefix("0") {
                continue
            }
            
            // Process municipality records (type 1)
            if line.hasPrefix("1") {
                if let municipality = parseD001Municipality(line) {
                    municipalities.append(municipality)
                }
            }
            
            // Skip supplementary records (types 2-H) for now
            // These contain additional territorial divisions
        }
        
        // Import to database
        try await importMunicipalitiesToDatabase(municipalities)
    }
    
    /// Parses a type 1 municipality record from d001
    private func parseD001Municipality(_ line: String) -> Municipality? {
        // Fixed-width field parsing based on the documentation
        guard line.count >= 537 else { return nil }
        
        let recordType = substring(line, from: 0, to: 1)
        guard recordType == "1" else { return nil }
        
        // Extract fields according to the documented positions
        let geoCode = substring(line, from: 1, to: 6).trimmingCharacters(in: .whitespaces)
        let status = substring(line, from: 6, to: 8).trimmingCharacters(in: .whitespaces)
        let name = substring(line, from: 8, to: 66).trimmingCharacters(in: .whitespaces)
        let urbanRural = substring(line, from: 66, to: 67).trimmingCharacters(in: .whitespaces)
        
        // Administrative region
        let regionCode = substring(line, from: 164, to: 166).trimmingCharacters(in: .whitespaces)
        let regionName = substring(line, from: 166, to: 196).trimmingCharacters(in: .whitespaces)
        
        // MRC
        let mrcCode = substring(line, from: 362, to: 365).trimmingCharacters(in: .whitespaces)
        let mrcName = substring(line, from: 365, to: 395).trimmingCharacters(in: .whitespaces)
        
        // Population (if available)
        let populationStr = substring(line, from: 494, to: 502).trimmingCharacters(in: .whitespaces)
        let population = Int(populationStr)
        
        // Geographic coordinates
        let latitudeStr = substring(line, from: 624, to: 628).trimmingCharacters(in: .whitespaces)
        let longitudeStr = substring(line, from: 628, to: 632).trimmingCharacters(in: .whitespaces)
        
        // Area
        let landAreaStr = substring(line, from: 632, to: 642).trimmingCharacters(in: .whitespaces)
        let totalAreaStr = substring(line, from: 642, to: 652).trimmingCharacters(in: .whitespaces)
        
        return Municipality(
            geoCode: geoCode,
            name: cleanMunicipalityName(name),
            status: status,
            urbanRural: urbanRural,
            regionCode: regionCode,
            regionName: cleanMunicipalityName(regionName),
            mrcCode: mrcCode,
            mrcName: cleanMunicipalityName(mrcName),
            population: population,
            latitude: parseCoordinate(latitudeStr),
            longitude: parseCoordinate(longitudeStr),
            landArea: parseArea(landAreaStr),
            totalArea: parseArea(totalAreaStr)
        )
    }
    
    /// Helper to extract substring from fixed-width fields
    private func substring(_ string: String, from: Int, to: Int) -> String {
        let startIndex = string.index(string.startIndex, offsetBy: from)
        let endIndex = string.index(string.startIndex, offsetBy: min(to, string.count))
        return String(string[startIndex..<endIndex])
    }
    
    /// Cleans municipality names with encoding fixes
    private func cleanMunicipalityName(_ name: String) -> String {
        var cleaned = name
        
        // Fix common encoding issues
        let replacements = [
            "MontrÃ©al": "Montréal",
            "QuÃ©bec": "Québec",
            "LÃ©vis": "Lévis",
            "Saint-JÃ©rÃ´me": "Saint-Jérôme",
            "TrÃ¨s-Saint-RÃ©dempteur": "Très-Saint-Rédempteur",
            "RiviÃ¨re": "Rivière",
            "Ã®les": "Îles",
            "Ã‰": "É",
            "Ã¨": "è",
            "Ã©": "é",
            "Ã ": "à",
            "Ã´": "ô",
            "Ã¢": "â",
            "Ã®": "î"
        ]
        
        for (corrupted, correct) in replacements {
            cleaned = cleaned.replacingOccurrences(of: corrupted, with: correct)
        }
        
        return cleaned
    }
    
    /// Parses coordinate from degrees/minutes format
    private func parseCoordinate(_ coord: String) -> Double? {
        guard coord.count == 4 else { return nil }
        
        let degrees = Double(substring(coord, from: 0, to: 2)) ?? 0
        let minutes = Double(substring(coord, from: 2, to: 4)) ?? 0
        
        return degrees + (minutes / 60.0)
    }
    
    /// Parses area with decimal places
    private func parseArea(_ area: String) -> Double? {
        guard area.count == 10 else { return nil }
        
        let integerPart = substring(area, from: 0, to: 7)
        let decimalPart = substring(area, from: 7, to: 10)
        
        let areaStr = "\(integerPart).\(decimalPart)"
        return Double(areaStr)
    }
    
    /// Imports municipalities to the database
    private func importMunicipalitiesToDatabase(_ municipalities: [Municipality]) async throws {
        // First, insert regions
        let regionPairs = municipalities.map { RegionPair(code: $0.regionCode, name: $0.regionName) }
        let uniqueRegions = Array(Set(regionPairs))
        
        for region in uniqueRegions {
            try await databaseManager.insertGeographicEntity(
                code: region.code,
                name: region.name,
                type: "adminRegion",
                parentCode: nil
            )
        }
        
        // Then, insert MRCs
        let mrcs = Array(Set(municipalities.map { MRCTriple(code: $0.mrcCode, name: $0.mrcName, regionCode: $0.regionCode) }))
        
        for mrc in mrcs {
            try await databaseManager.insertGeographicEntity(
                code: mrc.code,
                name: mrc.name,
                type: "mrc",
                parentCode: mrc.regionCode
            )
        }
        
        // Finally, insert municipalities
        for municipality in municipalities {
            try await databaseManager.insertGeographicEntity(
                code: municipality.geoCode,
                name: municipality.name,
                type: "municipality",
                parentCode: municipality.mrcCode,
                latitude: municipality.latitude,
                longitude: municipality.longitude,
                areaTotal: municipality.totalArea,
                areaLand: municipality.landArea
            )
        }
        
        print("Imported \(municipalities.count) municipalities")
    }
    
    /// Load geographic entities from database for UI
    func loadGeographicHierarchy() async throws -> GeographicHierarchy {
        let regions = try await loadEntities(type: "adminRegion")
        let mrcs = try await loadEntities(type: "mrc")
        let municipalities = try await loadEntities(type: "municipality")
        
        return GeographicHierarchy(
            regions: regions,
            mrcs: mrcs,
            municipalities: municipalities
        )
    }
    
    /// Loads entities of a specific type from database
    private func loadEntities(type: String) async throws -> [GeographicEntity] {
        return try await databaseManager.loadGeographicEntities(type: type)
    }
}

// MARK: - Supporting Types

/// Helper struct for region pairs (Hashable)
private struct RegionPair: Hashable {
    let code: String
    let name: String
}

/// Helper struct for MRC triples (Hashable)
private struct MRCTriple: Hashable {
    let code: String
    let name: String
    let regionCode: String
}

/// Municipality data from d001 file
struct Municipality {
    let geoCode: String
    let name: String
    let status: String
    let urbanRural: String
    let regionCode: String
    let regionName: String
    let mrcCode: String
    let mrcName: String
    let population: Int?
    let latitude: Double?
    let longitude: Double?
    let landArea: Double?
    let totalArea: Double?
}

/// Hierarchical geographic data structure
struct GeographicHierarchy {
    let regions: [GeographicEntity]
    let mrcs: [GeographicEntity]
    let municipalities: [GeographicEntity]
    
    /// Get MRCs for a specific region
    func mrcs(forRegion regionCode: String) -> [GeographicEntity] {
        mrcs.filter { $0.parentCode == regionCode }
    }
    
    /// Get municipalities for a specific MRC
    func municipalities(forMRC mrcCode: String) -> [GeographicEntity] {
        municipalities.filter { $0.parentCode == mrcCode }
    }
}

// MARK: - Database Manager Extension

extension DatabaseManager {
    /// Loads entities of a specific type from database (for GeographicDataImporter)
    func loadGeographicEntities(type: String) async throws -> [GeographicEntity] {
        return try await withCheckedThrowingContinuation { continuation in
            self.dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }
                
                let query = """
                    SELECT code, name, type, parent_code
                    FROM geographic_entities
                    WHERE type = ?
                    ORDER BY name
                    """
                
                var stmt: OpaquePointer?
                defer {
                    if stmt != nil {
                        sqlite3_finalize(stmt)
                    }
                }
                
                guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(throwing: DatabaseError.queryFailed("Failed to prepare query"))
                    return
                }
                
                sqlite3_bind_text(stmt, 1, type, -1, SQLITE_TRANSIENT)
                
                var entities: [GeographicEntity] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let code = String(cString: sqlite3_column_text(stmt, 0))
                    let name = String(cString: sqlite3_column_text(stmt, 1))
                    let typeStr = String(cString: sqlite3_column_text(stmt, 2))
                    let parentCode = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil :
                                    String(cString: sqlite3_column_text(stmt, 3))
                    
                    if let geoType = GeographicEntity.GeographicLevel(rawValue: typeStr) {
                        entities.append(GeographicEntity(
                            code: code,
                            name: name,
                            type: geoType,
                            parentCode: parentCode
                        ))
                    }
                }
                
                continuation.resume(returning: entities)
            }
        }
    }
}

/// Transient pointer for SQLite bindings
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
