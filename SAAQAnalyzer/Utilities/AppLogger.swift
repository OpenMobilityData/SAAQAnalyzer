//
//  AppLogger.swift
//  SAAQAnalyzer
//
//  Unified logging infrastructure using os.Logger (macOS best practices)
//

import Foundation
import OSLog

/// Centralized logging system for SAAQAnalyzer
/// Uses os.Logger for proper integration with Console.app and unified logging system
///
/// Usage:
/// ```
/// AppLogger.database.info("Database opened successfully")
/// AppLogger.performance.notice("Import completed in \(time)s")
/// AppLogger.regularization.debug("Processing mapping ID \(id)")
///
/// // Performance profiling with signposts (visible in Instruments)
/// let signpostID = OSSignpostID(log: AppLogger.performanceLog)
/// os_signpost(.begin, log: AppLogger.performanceLog, name: "Load Data", signpostID: signpostID)
/// // ... expensive operation ...
/// os_signpost(.end, log: AppLogger.performanceLog, name: "Load Data", signpostID: signpostID)
/// ```
///
/// Log Levels (in order of severity):
/// - `.debug`: Detailed information for debugging (filtered in production builds)
/// - `.info`: General informational messages
/// - `.notice`: Notable events (default level for important operations)
/// - `.error`: Error conditions that need attention
/// - `.fault`: Critical failures that require immediate attention
///
/// Console.app filtering:
/// - Subsystem: com.yourcompany.SAAQAnalyzer
/// - Categories: database, import, query, cache, regularization, ui, performance
struct AppLogger {

    // MARK: - Subsystem Configuration

    /// App subsystem identifier - used for filtering in Console.app
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.saaq.SAAQAnalyzer"

    // MARK: - Category Loggers

    /// Database operations (connections, schema, transactions)
    static let database = Logger(subsystem: subsystem, category: "database")

    /// Data import operations (CSV parsing, file processing)
    static let dataImport = Logger(subsystem: subsystem, category: "import")

    /// Query execution and optimization
    static let query = Logger(subsystem: subsystem, category: "query")

    /// Cache operations (filter cache, enumeration cache)
    static let cache = Logger(subsystem: subsystem, category: "cache")

    /// Regularization system (mappings, canonical hierarchy)
    static let regularization = Logger(subsystem: subsystem, category: "regularization")

    /// UI events and user interactions
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Performance benchmarks and timing measurements
    static let performance = Logger(subsystem: subsystem, category: "performance")

    /// Geographic data operations
    static let geographic = Logger(subsystem: subsystem, category: "geographic")

    /// Application lifecycle (launch, shutdown, version info)
    static let app = Logger(subsystem: subsystem, category: "app")

    // MARK: - Signpost Logs (for Instruments profiling)

    /// OSLog for performance signposts (visible in Instruments Time Profiler and Points of Interest)
    static let performanceLog = OSLog(subsystem: subsystem, category: "Performance")

    /// OSLog for cache operation signposts
    static let cacheLog = OSLog(subsystem: subsystem, category: "Cache")

    /// OSLog for database operation signposts
    static let databaseLog = OSLog(subsystem: subsystem, category: "Database")

    /// OSLog for regularization operation signposts
    static let regularizationLog = OSLog(subsystem: subsystem, category: "Regularization")

    // MARK: - Performance Measurement

    /// Measures and logs execution time of a code block
    /// - Parameters:
    ///   - logger: Logger instance to use for output
    ///   - operation: Description of the operation being timed
    ///   - block: Code block to measure
    /// - Returns: Result of the code block
    /// - Throws: Rethrows any error from the code block
    static func measureTime<T>(
        logger: Logger,
        operation: String,
        block: () throws -> T
    ) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let duration = CFAbsoluteTimeGetCurrent() - start
        logger.notice("\(operation) completed in \(String(format: "%.3f", duration))s")
        return result
    }

    /// Async version of measureTime
    static func measureTime<T>(
        logger: Logger,
        operation: String,
        block: () async throws -> T
    ) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let duration = CFAbsoluteTimeGetCurrent() - start
        logger.notice("\(operation) completed in \(String(format: "%.3f", duration))s")
        return result
    }

    // MARK: - Import Performance Tracking

    /// Structured performance metrics for import operations
    struct ImportPerformance {
        let totalRecords: Int
        let parseTime: TimeInterval
        let importTime: TimeInterval
        let totalTime: TimeInterval

        var recordsPerSecond: Double {
            totalTime > 0 ? Double(totalRecords) / totalTime : 0
        }

        var parsePercentage: Double {
            totalTime > 0 ? (parseTime / totalTime) * 100 : 0
        }

        var importPercentage: Double {
            totalTime > 0 ? (importTime / totalTime) * 100 : 0
        }

        /// Log performance summary using structured logging
        func log(logger: Logger, fileName: String, year: Int) {
            logger.notice("""
                Import completed: \(fileName, privacy: .public)
                Year: \(year)
                Records: \(self.totalRecords)
                Parse time: \(String(format: "%.1f", self.parseTime))s (\(String(format: "%.1f", self.parsePercentage))%)
                Import time: \(String(format: "%.1f", self.importTime))s (\(String(format: "%.1f", self.importPercentage))%)
                Total time: \(String(format: "%.1f", self.totalTime))s
                Throughput: \(String(format: "%.0f", self.recordsPerSecond)) records/sec
                """)
        }
    }

    // MARK: - Query Performance Tracking

    /// Performance rating for query execution
    enum QueryPerformance: String {
        case excellent = "Excellent"  // < 1s
        case good = "Good"            // 1-5s
        case acceptable = "Acceptable" // 5-10s
        case slow = "Slow"            // 10-25s
        case verySlow = "Very Slow"   // > 25s

        var emoji: String {
            switch self {
            case .excellent: return "⚡️"
            case .good: return "✅"
            case .acceptable: return "🔵"
            case .slow: return "⚠️"
            case .verySlow: return "🐌"
            }
        }

        static func rating(for duration: TimeInterval) -> QueryPerformance {
            switch duration {
            case ..<1.0: return .excellent
            case 1.0..<5.0: return .good
            case 5.0..<10.0: return .acceptable
            case 10.0..<25.0: return .slow
            default: return .verySlow
            }
        }
    }

    /// Log query performance with automatic rating
    static func logQueryPerformance(
        queryType: String,
        duration: TimeInterval,
        dataPoints: Int,
        indexUsed: String? = nil
    ) {
        let rating = QueryPerformance.rating(for: duration)

        var message = "\(rating.emoji) \(queryType) query: \(String(format: "%.3f", duration))s, \(dataPoints) points, \(rating.rawValue)"
        if let index = indexUsed {
            message += ", index: \(index)"
        }

        // Log at different levels based on performance
        switch rating {
        case .excellent, .good:
            performance.info("\(message)")
        case .acceptable:
            performance.notice("\(message)")
        case .slow, .verySlow:
            performance.warning("\(message)")
        }
    }
}

// MARK: - Debug Helpers

#if DEBUG
extension AppLogger {
    /// Enable verbose debugging for a specific category
    /// In production builds, these are automatically filtered by the logging system
    static func debugVerbose(_ logger: Logger, _ message: String) {
        logger.debug("\(message)")
    }
}
#endif
