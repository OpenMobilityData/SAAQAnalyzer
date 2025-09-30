import Foundation
import Combine

/// Manages import progress tracking with detailed stage information
@MainActor
class ImportProgressManager: ObservableObject {
    /// Current import progress (0.0 to 1.0)
    @Published var overallProgress: Double = 0.0
    
    /// Current stage being executed
    @Published var currentStage: ImportStage = .idle
    
    /// Detailed progress information for current stage
    @Published var stageProgress: StageProgress = .idle
    
    /// Whether an import is currently in progress
    @Published var isImporting: Bool = false

    /// Import start time for duration calculation
    private var importStartTime: Date?

    /// Total number of records being imported (set during file reading)
    private var totalRecords: Int = 0

    /// Number of batches for database import
    private var totalBatches: Int = 0

    /// Batch import tracking
    @Published var currentFileIndex: Int = 0
    @Published var totalFiles: Int = 0
    @Published var currentFileName: String = ""
    var isBatchImport: Bool { totalFiles > 1 }
    
    // MARK: - Import Stages
    
    enum ImportStage: Int, CaseIterable {
        case idle = 0
        case reading = 1
        case parsing = 2
        case importing = 3
        case indexing = 4
        case completed = 5
        
        var title: String {
            switch self {
            case .idle: return "Ready"
            case .reading: return "Reading File"
            case .parsing: return "Parsing CSV Data"
            case .importing: return "Importing to Database"
            case .indexing: return "Rebuilding Indexes"
            case .completed: return "Import Complete"
            }
        }
        
        var description: String {
            switch self {
            case .idle: return "Ready to import"
            case .reading: return "Reading and validating CSV file structure"
            case .parsing: return "Processing CSV data with parallel workers"
            case .importing: return "Writing records to database in batches"
            case .indexing: return "Optimizing database for queries"
            case .completed: return "Import finished successfully"
            }
        }
        
        var stepNumber: Int { rawValue }
        static var totalSteps: Int { ImportStage.allCases.count - 1 } // Exclude idle
    }
    
    // MARK: - Stage Progress Details
    
    enum StageProgress {
        case idle
        case reading
        case parsing(processed: Int, total: Int, workersActive: Int)
        case importing(batch: Int, totalBatches: Int, recordsProcessed: Int, totalRecords: Int)
        case indexing(operation: String)
        case completed(duration: TimeInterval, recordsImported: Int, recordsPerSecond: Int)
        
        var progressText: String {
            switch self {
            case .idle:
                return "Ready to start import"
                
            case .reading:
                return "Preparing import..."
                
            case .parsing(let processed, let total, let workers):
                let percentage = total > 0 ? Int((Double(processed) / Double(total)) * 100) : 0
                return "Parsed \(processed.formatted()) / \(total.formatted()) records (\(percentage)%) • \(workers) workers"
                
            case .importing(let batch, let totalBatches, let recordsProcessed, let totalRecords):
                let batchPercentage = Int((Double(batch) / Double(totalBatches)) * 100)
                let recordPercentage = Int((Double(recordsProcessed) / Double(totalRecords)) * 100)
                return "Batch \(batch) / \(totalBatches) (\(batchPercentage)%) • \(recordsProcessed.formatted()) / \(totalRecords.formatted()) records (\(recordPercentage)%)"
                
            case .indexing(let operation):
                return operation
                
            case .completed(let duration, let records, let rate):
                let minutes = Int(duration) / 60
                let seconds = Int(duration) % 60
                return "Imported \(records.formatted()) records in \(minutes)m \(seconds)s • \(rate.formatted()) records/sec"
            }
        }
        
        var quantitativeProgress: Double? {
            switch self {
            case .parsing(let processed, let total, _):
                return total > 0 ? Double(processed) / Double(total) : nil
            case .importing(let batch, let totalBatches, _, _):
                return totalBatches > 0 ? Double(batch) / Double(totalBatches) : nil
            default:
                return nil
            }
        }
    }
    
    // MARK: - Progress Management

    /// Starts a new batch import operation
    func startBatchImport(totalFiles: Int) {
        self.totalFiles = totalFiles
        self.currentFileIndex = 0
        self.currentFileName = ""
        isImporting = true
        importStartTime = Date()
        overallProgress = 0.0
        currentStage = .reading
        stageProgress = .reading
        totalRecords = 0
        totalBatches = 0
        print("📦 Starting batch import of \(totalFiles) files")
    }

    /// Updates which file is being processed in a batch
    func updateCurrentFile(index: Int, fileName: String) {
        self.currentFileIndex = index
        self.currentFileName = fileName
        print("📄 Processing file \(index + 1)/\(totalFiles): \(fileName)")
    }

    /// Starts a new import operation
    func startImport() {
        isImporting = true
        importStartTime = Date()
        overallProgress = 0.0
        currentStage = .reading
        stageProgress = .reading
        totalRecords = 0
        totalBatches = 0
        totalFiles = 1
        currentFileIndex = 0
        currentFileName = ""
    }
    
    /// Updates to file reading stage
    func updateToReading() {
        currentStage = .reading
        stageProgress = .reading
        overallProgress = calculateOverallProgress()
    }
    
    /// Updates to parsing stage with initial setup
    func updateToParsing(totalRecords: Int, workerCount: Int) {
        self.totalRecords = totalRecords
        currentStage = .parsing
        stageProgress = .parsing(processed: 0, total: totalRecords, workersActive: workerCount)
        overallProgress = calculateOverallProgress()
    }
    
    /// Updates parsing progress
    func updateParsingProgress(processedRecords: Int, workerCount: Int) {
        guard currentStage == .parsing else { return }
        stageProgress = .parsing(processed: processedRecords, total: totalRecords, workersActive: workerCount)
        overallProgress = calculateOverallProgress()
    }
    
    /// Updates to database import stage
    func updateToImporting(totalBatches: Int) {
        self.totalBatches = totalBatches
        currentStage = .importing
        stageProgress = .importing(batch: 0, totalBatches: totalBatches, recordsProcessed: 0, totalRecords: totalRecords)
        overallProgress = calculateOverallProgress()
    }
    
    /// Updates database import progress
    func updateImportingProgress(currentBatch: Int, recordsProcessed: Int) {
        guard currentStage == .importing else { return }
        stageProgress = .importing(
            batch: currentBatch, 
            totalBatches: totalBatches, 
            recordsProcessed: recordsProcessed, 
            totalRecords: totalRecords
        )
        overallProgress = calculateOverallProgress()
    }
    
    /// Updates to indexing stage
    func updateToIndexing() {
        currentStage = .indexing
        stageProgress = .indexing(operation: "Rebuilding database indexes...")
        overallProgress = calculateOverallProgress()
    }
    
    /// Updates indexing operation description
    func updateIndexingOperation(_ operation: String) {
        guard currentStage == .indexing else { return }
        stageProgress = .indexing(operation: operation)
    }
    
    /// Updates indexing for incremental mode
    func updateIncrementalIndexing() {
        guard currentStage == .indexing else { return }
        stageProgress = .indexing(operation: "Updating statistics (incremental mode - much faster!)")
    }
    
    /// Completes the import with final statistics
    func completeImport(recordsImported: Int) {
        guard let startTime = importStartTime else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        let recordsPerSecond = Int(Double(recordsImported) / duration)
        
        currentStage = .completed
        stageProgress = .completed(duration: duration, recordsImported: recordsImported, recordsPerSecond: recordsPerSecond)
        overallProgress = 1.0
        isImporting = false
    }
    
    /// Resets progress to idle state
    func reset() {
        isImporting = false
        overallProgress = 0.0
        currentStage = .idle
        stageProgress = .idle
        importStartTime = nil
        totalRecords = 0
        totalBatches = 0
        totalFiles = 0
        currentFileIndex = 0
        currentFileName = ""
    }
    
    // MARK: - Private Helpers
    
    private func calculateOverallProgress() -> Double {
        let stageWeight: Double = 1.0 / Double(ImportStage.totalSteps)
        let baseProgress = Double(currentStage.stepNumber - 1) * stageWeight
        
        // Add partial progress within current stage
        if let stageProgress = stageProgress.quantitativeProgress {
            return baseProgress + (stageProgress * stageWeight)
        } else {
            return baseProgress
        }
    }
}