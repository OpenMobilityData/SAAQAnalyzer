import Foundation
import UniformTypeIdentifiers
import SQLite3
import AppKit

/// Transient pointer for SQLite bindings
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thread-safe progress tracker for real-time progress updates
actor ProgressTracker {
    private var processedCount: Int = 0
    
    func increment() {
        processedCount += 1
    }
    
    func getProgress() -> Int {
        return processedCount
    }
    
    func reset() {
        processedCount = 0
    }
}

/// Handles importing SAAQ CSV data files into the database
class CSVImporter {
    private let databaseManager: DatabaseManager
    private var progressManager: ImportProgressManager?
    
    init(databaseManager: DatabaseManager = .shared, progressManager: ImportProgressManager? = nil) {
        self.databaseManager = databaseManager
        self.progressManager = progressManager
    }
    
    /// Imports a vehicle registration CSV file for a specific year
    func importVehicleFile(at url: URL, year: Int, skipDuplicateCheck: Bool = false) async throws -> ImportResult {
        let overallStartTime = Date()
        print("🚀 Starting import of \(url.lastPathComponent) for year \(year)")
        
        // Start progress tracking (only if not already started by UI)
        if !skipDuplicateCheck {
            await progressManager?.startImport()
        }
        
        // Check if year is already imported (unless skipped for SwiftUI handling)
        if !skipDuplicateCheck {
            let yearExists = await databaseManager.isYearImported(year)
            if yearExists {
                let shouldReplace = await requestUserConfirmationForDuplicateYear(year)
                if shouldReplace {
                    print("🗑️ Deleting existing data for year \(year)...")
                    try await databaseManager.clearYearData(year)
                    print("✅ Existing data for year \(year) deleted successfully")
                } else {
                    throw ImportError.importCancelled
                }
            }
        }
        
        // Update to reading stage
        await progressManager?.updateToReading()
        
        // Determine schema based on year
        let schema = DataSchema.schema(for: year)
        
        // Read and parse CSV file
        let parseStartTime = Date()
        print("📖 Reading and parsing CSV file...")
        let records = try await parseCSVFile(at: url, schema: schema)
        let parseTime = Date().timeIntervalSince(parseStartTime)
        print("✅ CSV parsing completed in \(String(format: "%.1f", parseTime)) seconds")
        
        // Import records to database
        print("💾 Starting database import...")
        let importStartTime = Date()
        let result = try await importVehicleRecords(records, year: year, fileName: url.lastPathComponent)
        let importTime = Date().timeIntervalSince(importStartTime)
        
        let totalTime = Date().timeIntervalSince(overallStartTime)
        print("🎉 Import completed successfully!")
        print("📊 Performance Summary:")
        print("   • CSV Parsing: \(String(format: "%.1f", parseTime))s (\(String(format: "%.1f", parseTime/totalTime*100))%)")
        print("   • Database Import: \(String(format: "%.1f", importTime))s (\(String(format: "%.1f", importTime/totalTime*100))%)")
        print("   • Total Time: \(String(format: "%.1f", totalTime))s")
        print("   • Records/second: \(String(format: "%.0f", Double(result.totalRecords)/totalTime))")
        
        // Complete progress tracking
        await progressManager?.completeImport(recordsImported: result.successCount)
        
        return result
    }
    
    /// Parses a CSV file with proper character encoding handling
    private func parseCSVFile(at url: URL, schema: DataSchema) async throws -> [[String: String]] {
        // Try different encodings to handle French characters properly
        let encodings: [String.Encoding] = [
            .utf8,
            .isoLatin1,  // ISO-8859-1 for French characters
            .windowsCP1252  // Windows encoding sometimes used
        ]
        
        var fileContent: String?
        
        for encoding in encodings {
            if let content = try? String(contentsOf: url, encoding: encoding) {
                // Quick check for common French characters
                if content.contains("é") || content.contains("è") || content.contains("à") {
                    fileContent = content
                    break
                }
            }
        }
        
        guard let content = fileContent else {
            throw ImportError.encodingError("Unable to read file with proper character encoding")
        }
        
        // Parse CSV content
        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
        
        guard lines.count > 1 else {
            throw ImportError.emptyFile
        }
        
        // Get headers from first line
        let headers = parseCSVLine(lines[0])
        
        // Validate expected columns based on schema
        let expectedColumns = schema.hasFuelType ? 16 : 15
        guard headers.count == expectedColumns else {
            throw ImportError.invalidSchema(
                "Expected \(expectedColumns) columns but found \(headers.count) for year \(schema.year)"
            )
        }
        
        let dataLines = Array(lines[1...]).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        print("🚀 Parsing \(dataLines.count) records using parallel processing...")
        
        // Determine optimal thread count using settings
        let settings = AppSettings.shared
        let workerCount = await MainActor.run {
            settings.getOptimalThreadCount(for: dataLines.count)
        }
        let chunkSize = min(50_000, max(10_000, dataLines.count / workerCount)) // Between 10K-50K records per chunk for better progress updates
        
        let threadMode = await MainActor.run {
            settings.useAdaptiveThreadCount ? "adaptive" : "manual"
        }
        print("   • Using \(workerCount) parallel workers (\(threadMode) mode)")
        print("   • Chunk size: \(chunkSize) records per worker")
        
        // Update to parsing stage
        await progressManager?.updateToParsing(totalRecords: dataLines.count, workerCount: workerCount)
        
        // Split data into chunks for parallel processing
        var chunks: [ArraySlice<String>] = []
        for i in stride(from: 0, to: dataLines.count, by: chunkSize) {
            let endIndex = min(i + chunkSize, dataLines.count)
            chunks.append(dataLines[i..<endIndex])
        }
        
        print("   • Processing \(chunks.count) chunks in parallel...")
        
        let startTime = Date()
        
        // Thread-safe progress tracker for real-time progress tracking
        let progressTracker = ProgressTracker()
        
        // Start a background task to update progress periodically
        let progressUpdateTask = Task {
            while !Task.isCancelled {
                let currentProcessed = await progressTracker.getProgress()
                await progressManager?.updateParsingProgress(processedRecords: currentProcessed, workerCount: workerCount)
                
                // Update every 0.1 seconds for smooth progress
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        
        // Process chunks in parallel using TaskGroup with real-time progress
        let results = await withTaskGroup(of: (Int, [[String: String]]).self) { group in
            // Add tasks for each chunk
            for (index, chunk) in chunks.enumerated() {
                group.addTask {
                    let chunkResults = await self.parseChunk(Array(chunk), headers: headers, chunkIndex: index, progressTracker: progressTracker)
                    return (index, chunkResults)
                }
            }
            
            // Collect results maintaining order
            var chunkResults: [Int: [[String: String]]] = [:]
            var completedChunks = 0
            let totalChunks = chunks.count
            
            for await (index, records) in group {
                chunkResults[index] = records
                completedChunks += 1
                
                // Debug output to console
                let progressPercent = Int(Double(completedChunks) / Double(totalChunks) * 100)
                print("   • Chunk \(completedChunks)/\(totalChunks) completed (\(progressPercent)%) - \(records.count) records in this chunk")
            }
            
            return chunkResults
        }
        
        // Cancel the progress update task
        progressUpdateTask.cancel()
        
        // Combine results in correct order
        var allRecords: [[String: String]] = []
        for i in 0..<chunks.count {
            if let chunkRecords = results[i] {
                allRecords.append(contentsOf: chunkRecords)
            }
        }
        
        let parseTime = Date().timeIntervalSince(startTime)
        print("✅ Parallel parsing completed in \(String(format: "%.1f", parseTime))s")
        print("   • Processed \(allRecords.count) records")
        print("   • Rate: \(String(format: "%.0f", Double(allRecords.count)/parseTime)) records/second")
        
        return allRecords
    }
    
    /// Parses a chunk of CSV lines (worker function)
    private nonisolated func parseChunk(_ lines: [String], headers: [String], chunkIndex: Int, progressTracker: ProgressTracker) async -> [[String: String]] {
        var records: [[String: String]] = []
        records.reserveCapacity(lines.count)
        
        for line in lines {
            if let record = parseDataLine(line, headers: headers) {
                records.append(record)
                // Increment the shared progress counter for real-time tracking
                await progressTracker.increment()
            }
        }
        
        return records
    }
    
    /// Parses a single CSV line handling quoted values
    private nonisolated func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var inQuotes = false
        
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
            } else {
                currentField.append(char)
            }
        }
        
        // Don't forget the last field
        fields.append(currentField.trimmingCharacters(in: .whitespaces))
        
        return fields
    }
    
    /// Parses a data line into a dictionary
    private nonisolated func parseDataLine(_ line: String, headers: [String]) -> [String: String]? {
        let values = parseCSVLine(line)
        
        guard values.count == headers.count else {
            print("Warning: Skipping line with incorrect number of fields")
            return nil
        }
        
        var record: [String: String] = [:]
        for (index, header) in headers.enumerated() {
            let rawValue = values[index].trimmingCharacters(in: .whitespaces)
            
            // Only apply encoding fixes to non-empty string fields that likely need it
            let cleanValue: String
            if rawValue.isEmpty {
                cleanValue = rawValue  // Keep empty as empty
            } else if rawValue.contains("Ã") || rawValue.contains("Â") {
                cleanValue = cleanEncodingIssues(rawValue)  // Only fix when needed
            } else {
                cleanValue = rawValue  // Skip encoding fixes for clean values
            }
            
            record[header] = cleanValue
        }
        
        return record
    }
    
    /// Fixes common character encoding issues in SAAQ data
    private nonisolated func cleanEncodingIssues(_ value: String) -> String {
        var cleaned = value
        
        // Common encoding fixes for French characters
        let replacements = [
            "MontrÃ©al": "Montréal",
            "QuÃ©bec": "Québec",
            "LÃ©vis": "Lévis",
            "GaspÃ©": "Gaspé",
            "ChaudiÃ¨re": "Chaudière",
            "MontÃ©rÃ©gie": "Montérégie",
            "TÃ©miscamingue": "Témiscamingue",
            "Ã®les": "Îles",
            "RÃ‰GULIER": "RÉGULIER",
            "Ã‰": "É",
            "Ã¨": "è",
            "Ã©": "é",
            "Ã ": "à",
            "Ã´": "ô"
        ]
        
        for (corrupted, correct) in replacements {
            cleaned = cleaned.replacingOccurrences(of: corrupted, with: correct)
        }
        
        return cleaned
    }
    
    /// Imports vehicle records into the database
    private func importVehicleRecords(_ records: [[String: String]], year: Int, fileName: String) async throws -> ImportResult {
        let startTime = Date()
        var successCount = 0
        var errorCount = 0
        
        // Prepare database for bulk import
        await databaseManager.beginBulkImport()
        
        // Process records in larger batches for efficiency (optimized for M3 Ultra with 96GB RAM)
        // With transactions, larger batches are much more efficient
        let batchSize = 50000  // Increased from 1000 to 50000 for 50x fewer transactions
        
        print("Starting import of \(records.count) records in batches of \(batchSize)...")
        
        // Calculate total batches and update progress
        let totalBatches = Int(ceil(Double(records.count) / Double(batchSize)))
        await progressManager?.updateToImporting(totalBatches: totalBatches)
        
        for batchStart in stride(from: 0, to: records.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, records.count)
            let batch = Array(records[batchStart..<batchEnd])
            
            do {
                let result = try await databaseManager.importVehicleBatch(batch, year: year, importer: self)
                successCount += result.success
                errorCount += result.errors
            } catch {
                print("Error importing batch: \(error)")
                errorCount += batch.count
            }
            
            // Update progress
            let currentBatchNumber = batchStart/batchSize + 1
            await progressManager?.updateImportingProgress(currentBatch: currentBatchNumber, recordsProcessed: batchEnd)
            
            print("Completed batch \(currentBatchNumber)/\(totalBatches): \(Int(Double(batchEnd)/Double(records.count) * 100))%")
        }
        
        // Complete bulk import and rebuild indexes
        await progressManager?.updateToIndexing()
        await databaseManager.endBulkImport(progressManager: progressManager)
        
        // Log import completion
        let duration = Date().timeIntervalSince(startTime)
        try await logImport(
            fileName: fileName,
            year: year,
            recordCount: successCount,
            status: errorCount == 0 ? "success" : "partial"
        )
        
        return ImportResult(
            totalRecords: records.count,
            successCount: successCount,
            errorCount: errorCount,
            duration: duration
        )
    }
    
    /// Helper to bind text values to SQLite statement
    internal func bindTextToStatement(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value = value, !value.isEmpty {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
    
    /// Helper to bind required text values (provides default if empty)
    internal func bindRequiredTextToStatement(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?, defaultValue: String = "Unknown") {
        if let value = value, !value.isEmpty {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_text(stmt, index, defaultValue, -1, SQLITE_TRANSIENT)
        }
    }
    
    /// Helper to bind integer values
    internal func bindIntToStatement(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value = value, let intValue = Int32(value) {
            sqlite3_bind_int(stmt, index, intValue)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
    
    /// Helper to bind double values
    internal func bindDoubleToStatement(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value = value, let doubleValue = Double(value) {
            sqlite3_bind_double(stmt, index, doubleValue)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
    
    
    /// Logs import to database
    private func logImport(fileName: String, year: Int, recordCount: Int, status: String) async throws {
        let sql = """
            INSERT INTO import_log (file_name, year, record_count, import_date, status)
            VALUES (?, ?, ?, datetime('now'), ?)
            """
        
        try await databaseManager.executeImportLog(sql, fileName: fileName, year: year, recordCount: recordCount, status: status)
    }
    
    /// Requests user confirmation for replacing existing year data
    @MainActor
    private func requestUserConfirmationForDuplicateYear(_ year: Int) async -> Bool {
        return await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Year \(year) Already Exists"
            alert.informativeText = "Data for year \(year) has already been imported. Do you want to replace the existing data with the new import?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Replace Existing Data")
            alert.addButton(withTitle: "Cancel Import")
            
            // Set the default button to Cancel for safety
            alert.buttons[1].keyEquivalent = "\r"
            
            let response = alert.runModal()
            continuation.resume(returning: response == .alertFirstButtonReturn)
        }
    }
}

// MARK: - Import Types

/// Result of an import operation
struct ImportResult {
    let totalRecords: Int
    let successCount: Int
    let errorCount: Int
    let duration: TimeInterval
    
    var successRate: Double {
        Double(successCount) / Double(totalRecords)
    }
}

/// Import-related errors
enum ImportError: LocalizedError {
    case yearAlreadyImported(Int)
    case encodingError(String)
    case emptyFile
    case invalidSchema(String)
    case databaseError(String)
    case importCancelled
    
    var errorDescription: String? {
        switch self {
        case .yearAlreadyImported(let year):
            return "Data for year \(year) has already been imported"
        case .encodingError(let message):
            return "Character encoding error: \(message)"
        case .emptyFile:
            return "CSV file is empty or contains only headers"
        case .invalidSchema(let message):
            return "Invalid data schema: \(message)"
        case .databaseError(let message):
            return "Database error: \(message)"
        case .importCancelled:
            return "Import was cancelled by user"
        }
    }
}

// MARK: - Database Manager Extensions for Import

extension DatabaseManager {
    // Remove the old executeBatch and executeStatement methods
    // They are causing the escaping closure issues
}
