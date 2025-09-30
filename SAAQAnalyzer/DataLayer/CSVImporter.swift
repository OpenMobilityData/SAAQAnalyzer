import Foundation
import UniformTypeIdentifiers
import SQLite3

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
    
    /// Generic import method that detects file type and routes to appropriate handler
    func importFile(at url: URL, year: Int, dataType: DataEntityType, skipDuplicateCheck: Bool = false) async throws -> ImportResult {
        switch dataType {
        case .vehicle:
            return try await importVehicleFile(at: url, year: year, skipDuplicateCheck: skipDuplicateCheck)
        case .license:
            return try await importLicenseFile(at: url, year: year, skipDuplicateCheck: skipDuplicateCheck)
        }
    }

    /// Imports a vehicle registration CSV file for a specific year
    func importVehicleFile(at url: URL, year: Int, skipDuplicateCheck: Bool = false) async throws -> ImportResult {
        let overallStartTime = Date()
        print("🚀 Starting import of \(url.lastPathComponent) for year \(year)")
        
        // Start progress tracking (only if not already started by UI or batch import)
        if !skipDuplicateCheck {
            let isBatchInProgress = await progressManager?.isBatchImport ?? false
            if !isBatchInProgress {
                await progressManager?.startImport()
            }
        }
        
        // Check if year is already imported (unless skipped for SwiftUI handling)
        if !skipDuplicateCheck {
            let yearExists = await databaseManager.isYearImported(year)
            if yearExists {
                print("⚠️ Year \(year) already exists. Replacing existing data...")
                print("🗑️ Deleting existing data for year \(year)...")
                try await databaseManager.clearYearData(year)
                print("✅ Existing data for year \(year) deleted successfully")
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

    /// Imports a driver's license CSV file for a specific year
    func importLicenseFile(at url: URL, year: Int, skipDuplicateCheck: Bool = false) async throws -> ImportResult {
        let overallStartTime = Date()
        print("🚀 Starting license import of \(url.lastPathComponent) for year \(year)")

        // Start progress tracking (only if not already started by UI or batch import)
        if !skipDuplicateCheck {
            let isBatchInProgress = await progressManager?.isBatchImport ?? false
            if !isBatchInProgress {
                await progressManager?.startImport()
            }
        }

        // Check if year is already imported (unless skipped for SwiftUI handling)
        if !skipDuplicateCheck {
            let yearExists = await databaseManager.isYearImported(year)
            if yearExists {
                print("⚠️ Year \(year) already exists. Replacing existing data...")
                print("🗑️ Deleting existing data for year \(year)...")
                try await databaseManager.clearYearData(year)
                print("✅ Existing data for year \(year) deleted successfully")
            }
        }

        // Update to reading stage
        await progressManager?.updateToReading()

        // Read and parse CSV file for licenses (20 fields)
        let parseStartTime = Date()
        print("📖 Reading and parsing license CSV file...")
        let records = try await parseLicenseCSVFile(at: url)
        let parseTime = Date().timeIntervalSince(parseStartTime)
        print("✅ License CSV parsing completed in \(String(format: "%.1f", parseTime)) seconds")

        // Import records to database
        print("💾 Starting license database import...")
        let importStartTime = Date()
        let result = try await importLicenseRecords(records, year: year, fileName: url.lastPathComponent)
        let importTime = Date().timeIntervalSince(importStartTime)

        let totalTime = Date().timeIntervalSince(overallStartTime)
        print("🎉 License import completed successfully!")
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

        print("🔍 Trying encodings for file: \(url.lastPathComponent)")
        print("🔍 File path: \(url.path)")

        // Start accessing security-scoped resource (needed for files outside sandbox)
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        for encoding in encodings {
            print("  Attempting encoding: \(encoding)")
            if let content = try? String(contentsOf: url, encoding: encoding) {
                print("  ✅ Successfully read with \(encoding), checking for French characters...")
                // Quick check for common French characters
                if content.contains("é") || content.contains("è") || content.contains("à") {
                    print("  ✅ Found French characters, using this encoding")
                    fileContent = content
                    break
                } else {
                    print("  ⚠️ No French characters found, trying next encoding...")
                }
            } else {
                print("  ❌ Failed to read with \(encoding)")
            }
        }

        guard let content = fileContent else {
            throw ImportError.encodingError("Unable to read file with proper character encoding")
        }
        print("✅ File successfully read with proper encoding")
        
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
        // Skip cache refresh if this is part of a batch import (progressManager.isBatchImport)
        await progressManager?.updateToIndexing()
        let skipCache = await progressManager?.isBatchImport ?? false
        await databaseManager.endBulkImport(progressManager: progressManager, skipCacheRefresh: skipCache)
        
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
    
    /// Parses a license CSV file with proper character encoding handling
    private func parseLicenseCSVFile(at url: URL) async throws -> [[String: String]] {
        // Update to parsing stage immediately to show progress
        await progressManager?.updateToParsing(totalRecords: 0, workerCount: 1)

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

        // Get headers from first line - expected 20 fields for licenses
        let headers = parseCSVLine(lines[0])

        // Validate expected columns for license data (20 fields)
        guard headers.count == 20 else {
            throw ImportError.invalidSchema(
                "Expected 20 columns for license data but found \(headers.count)"
            )
        }

        let dataLines = Array(lines[1...]).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        print("🚀 Parsing \(dataLines.count) license records using parallel processing...")

        // Determine optimal thread count using settings
        let settings = AppSettings.shared
        let workerCount = await MainActor.run {
            settings.getOptimalThreadCount(for: dataLines.count)
        }
        let chunkSize = min(50_000, max(10_000, dataLines.count / workerCount))

        let threadMode = await MainActor.run {
            settings.useAdaptiveThreadCount ? "adaptive" : "manual"
        }
        print("   • Using \(workerCount) parallel workers (\(threadMode) mode)")
        print("   • Chunk size: \(chunkSize) records per worker")

        // Update to parsing stage with correct record count
        await progressManager?.updateToParsing(totalRecords: dataLines.count, workerCount: workerCount)

        // Split data into chunks for parallel processing
        var chunks: [ArraySlice<String>] = []
        for i in stride(from: 0, to: dataLines.count, by: chunkSize) {
            let endIndex = min(i + chunkSize, dataLines.count)
            chunks.append(dataLines[i..<endIndex])
        }

        print("   • Processing \(chunks.count) chunks in parallel...")

        let startTime = Date()

        // Thread-safe progress tracker
        let progressTracker = ProgressTracker()

        // Start a background task to update progress periodically
        let progressUpdateTask = Task {
            while !Task.isCancelled {
                let currentProcessed = await progressTracker.getProgress()
                await progressManager?.updateParsingProgress(processedRecords: currentProcessed, workerCount: workerCount)

                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        // Process chunks in parallel using TaskGroup
        let results = await withTaskGroup(of: (Int, [[String: String]]).self) { group in
            // Add tasks for each chunk
            for (index, chunk) in chunks.enumerated() {
                group.addTask {
                    let chunkResults = await self.parseLicenseChunk(Array(chunk), headers: headers, chunkIndex: index, progressTracker: progressTracker)
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

                let progressPercent = Int(Double(completedChunks) / Double(totalChunks) * 100)
                print("   • Chunk \(completedChunks)/\(totalChunks) completed (\(progressPercent)%) - \(records.count) records in this chunk")
            }

            // Combine all results in order
            var allResults: [[String: String]] = []
            for i in 0..<totalChunks {
                if let chunkRecords = chunkResults[i] {
                    allResults.append(contentsOf: chunkRecords)
                }
            }

            return allResults
        }

        // Cancel progress update task
        progressUpdateTask.cancel()

        let parsingTime = Date().timeIntervalSince(startTime)
        print("✅ Parallel parsing completed in \(String(format: "%.2f", parsingTime)) seconds")
        print("   • Total records parsed: \(results.count)")
        print("   • Parsing rate: \(String(format: "%.0f", Double(results.count)/parsingTime)) records/second")

        return results
    }

    /// Parse a chunk of license CSV lines in parallel
    private func parseLicenseChunk(_ lines: [String], headers: [String], chunkIndex: Int, progressTracker: ProgressTracker) async -> [[String: String]] {
        var records: [[String: String]] = []

        for line in lines {
            let columns = parseCSVLine(line)

            // Validate column count for license data
            guard columns.count == 20 else {
                print("⚠️ Skipping invalid license record with \(columns.count) columns (expected 20)")
                continue
            }

            // Create record dictionary
            var record: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                if index < columns.count {
                    record[header] = columns[index]
                }
            }

            records.append(record)
            await progressTracker.increment()
        }

        return records
    }

    /// Import license records to database
    private func importLicenseRecords(_ records: [[String: String]], year: Int, fileName: String) async throws -> ImportResult {
        let startTime = Date()
        var successCount = 0
        var errorCount = 0

        // Prepare database for bulk import
        await databaseManager.beginBulkImport()

        // Process records in larger batches for efficiency
        let batchSize = 50000

        // Update to importing stage
        let totalBatches = (records.count + batchSize - 1) / batchSize
        await progressManager?.updateToImporting(totalBatches: totalBatches)

        print("📊 Processing \(records.count) license records in batches of \(batchSize)...")

        for i in stride(from: 0, to: records.count, by: batchSize) {
            let endIndex = min(i + batchSize, records.count)
            let batch = Array(records[i..<endIndex])

            let batchNumber = (i / batchSize) + 1
            let totalBatches = (records.count + batchSize - 1) / batchSize

            print("   • Processing batch \(batchNumber)/\(totalBatches) (\(batch.count) records)...")

            do {
                let batchResult = try await importLicenseBatch(batch, year: year)
                successCount += batchResult.success
                errorCount += batchResult.errors

                // Update progress
                await progressManager?.updateImportingProgress(
                    currentBatch: batchNumber,
                    recordsProcessed: min(endIndex, records.count)
                )

                let progressPercent = Int(Double(endIndex) / Double(records.count) * 100)
                print("   • Batch \(batchNumber) completed (\(progressPercent)% total) - \(batchResult.success) successful, \(batchResult.errors) errors")

            } catch {
                print("❌ Error in batch \(batchNumber): \(error)")
                errorCount += batch.count
            }
        }

        // Complete bulk import and rebuild indexes
        // Skip cache refresh if this is part of a batch import (progressManager.isBatchImport)
        await progressManager?.updateToIndexing()
        let skipCache = await progressManager?.isBatchImport ?? false
        await databaseManager.endBulkImport(progressManager: progressManager, skipCacheRefresh: skipCache)

        // Log import to database
        let status = errorCount > 0 ? "completed_with_errors" : "completed"
        try await logImport(fileName: fileName, year: year, recordCount: successCount, status: status)

        let duration = Date().timeIntervalSince(startTime)

        print("✅ License import completed: \(successCount) successful, \(errorCount) errors")
        print("   • Success rate: \(String(format: "%.1f", Double(successCount)/Double(records.count)*100))%")
        print("   • Import rate: \(String(format: "%.0f", Double(successCount)/duration)) records/second")

        return ImportResult(
            totalRecords: records.count,
            successCount: successCount,
            errorCount: errorCount,
            duration: duration
        )
    }

    /// Import a batch of license records to database
    private func importLicenseBatch(_ records: [[String: String]], year: Int) async throws -> (success: Int, errors: Int) {
        return try await withCheckedThrowingContinuation { continuation in
            databaseManager.dbQueue.async {
                guard let db = self.databaseManager.db else {
                    continuation.resume(throwing: ImportError.databaseError("Database not connected"))
                    return
                }

                var successCount = 0
                var errorCount = 0

                // Begin transaction for this batch
                if sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil) != SQLITE_OK {
                    continuation.resume(throwing: ImportError.databaseError("Failed to begin transaction"))
                    return
                }

                // Prepare insert statement for licenses
                let insertSQL = """
                    INSERT INTO licenses (
                        year, license_sequence, age_group, gender, mrc, admin_region, license_type,
                        has_learner_permit_123, has_learner_permit_5, has_learner_permit_6a6r,
                        has_driver_license_1234, has_driver_license_5, has_driver_license_6abce,
                        has_driver_license_6d, has_driver_license_8, is_probationary,
                        experience_1234, experience_5, experience_6abce, experience_global
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """

                var insertStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) != SQLITE_OK {
                    sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                    continuation.resume(throwing: ImportError.databaseError("Failed to prepare license insert statement"))
                    return
                }

                defer {
                    sqlite3_finalize(insertStmt)
                }

                // Process each record in the batch
                for record in records {
                    do {
                        // Reset the statement for reuse
                        sqlite3_reset(insertStmt)

                        // Bind all the license fields
                        sqlite3_bind_int(insertStmt, 1, Int32(year))
                        sqlite3_bind_text(insertStmt, 2, record["NOSEQ_TITUL"] ?? "", -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 3, record["AGE_1ER_JUIN"] ?? "", -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 4, record["SEXE"] ?? "", -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 5, record["MRC"] ?? "", -1, SQLITE_TRANSIENT)

                        // Normalize admin_region format (ensure space before parentheses)
                        let rawAdminRegion = record["REG_ADM"] ?? ""
                        let normalizedAdminRegion = self.normalizeAdminRegion(rawAdminRegion)
                        sqlite3_bind_text(insertStmt, 6, normalizedAdminRegion, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 7, record["TYPE_PERMIS"] ?? "", -1, SQLITE_TRANSIENT)

                        // Bind boolean fields (convert OUI/NON to 1/0)
                        sqlite3_bind_int(insertStmt, 8, (record["IND_PERMISAPPRENTI_123"] == "OUI") ? 1 : 0)
                        sqlite3_bind_int(insertStmt, 9, (record["IND_PERMISAPPRENTI_5"] == "OUI") ? 1 : 0)
                        sqlite3_bind_int(insertStmt, 10, (record["IND_PERMISAPPRENTI_6A6R"] == "OUI") ? 1 : 0)
                        sqlite3_bind_int(insertStmt, 11, (record["IND_PERMISCONDUIRE_1234"] == "OUI") ? 1 : 0)
                        sqlite3_bind_int(insertStmt, 12, (record["IND_PERMISCONDUIRE_5"] == "OUI") ? 1 : 0)
                        sqlite3_bind_int(insertStmt, 13, (record["IND_PERMISCONDUIRE_6ABCE"] == "OUI") ? 1 : 0)
                        sqlite3_bind_int(insertStmt, 14, (record["IND_PERMISCONDUIRE_6D"] == "OUI") ? 1 : 0)
                        sqlite3_bind_int(insertStmt, 15, (record["IND_PERMISCONDUIRE_8"] == "OUI") ? 1 : 0)
                        sqlite3_bind_int(insertStmt, 16, (record["IND_PROBATOIRE"] == "OUI") ? 1 : 0)

                        // Bind experience fields
                        sqlite3_bind_text(insertStmt, 17, record["EXPERIENCE_1234"] ?? "", -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 18, record["EXPERIENCE_5"] ?? "", -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 19, record["EXPERIENCE_6ABCE"] ?? "", -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 20, record["EXPERIENCE_GLOBALE"] ?? "", -1, SQLITE_TRANSIENT)

                        // Execute the insert
                        if sqlite3_step(insertStmt) == SQLITE_DONE {
                            successCount += 1
                        } else {
                            errorCount += 1
                            if let errorMessage = sqlite3_errmsg(db) {
                                print("❌ Error inserting license record: \(String(cString: errorMessage))")
                            }
                        }
                    } catch {
                        errorCount += 1
                        print("❌ Error processing license record: \(error)")
                    }
                }

                // Commit transaction
                if sqlite3_exec(db, "COMMIT", nil, nil, nil) != SQLITE_OK {
                    sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                    continuation.resume(throwing: ImportError.databaseError("Failed to commit transaction"))
                    return
                }

                continuation.resume(returning: (success: successCount, errors: errorCount))
            }
        }
    }

    /// Normalizes admin_region format to ensure consistency across years
    /// Ensures there's always a space before the parentheses
    private func normalizeAdminRegion(_ region: String) -> String {
        let trimmed = region.trimmingCharacters(in: .whitespaces)

        // If empty, return as-is
        guard !trimmed.isEmpty else { return trimmed }

        // Check if it contains parentheses without a space before them
        if let openParenIndex = trimmed.lastIndex(of: "(") {
            let beforeParen = trimmed.index(before: openParenIndex)

            // If the character before '(' is not a space, add one
            if beforeParen >= trimmed.startIndex && trimmed[beforeParen] != " " {
                let prefix = String(trimmed[..<openParenIndex])
                let suffix = String(trimmed[openParenIndex...])
                return "\(prefix) \(suffix)"
            }
        }

        return trimmed
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
