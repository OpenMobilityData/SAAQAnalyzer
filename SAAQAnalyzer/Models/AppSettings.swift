import Foundation
import Observation

/// Application settings for performance tuning and preferences
@MainActor
@Observable
class AppSettings {
    /// Singleton instance
    static let shared = AppSettings()

    // MARK: - Export Settings

    /// Background color luminosity for PNG exports (0.0 = black, 1.0 = white)
    var exportBackgroundLuminosity: Double {
        didSet {
            UserDefaults.standard.set(exportBackgroundLuminosity, forKey: "exportBackgroundLuminosity")
        }
    }

    /// Line thickness for chart lines in PNG exports
    var exportLineThickness: Double {
        didSet {
            UserDefaults.standard.set(exportLineThickness, forKey: "exportLineThickness")
        }
    }

    /// Whether to use bold font for axis labels in PNG exports
    var exportBoldAxisLabels: Bool {
        didSet {
            UserDefaults.standard.set(exportBoldAxisLabels, forKey: "exportBoldAxisLabels")
        }
    }

    /// Export image scale factor (1.0 = standard, 2.0 = high DPI)
    var exportScaleFactor: Double {
        didSet {
            UserDefaults.standard.set(exportScaleFactor, forKey: "exportScaleFactor")
        }
    }

    /// Whether to include legend in PNG exports when multiple series are present
    var exportIncludeLegend: Bool {
        didSet {
            UserDefaults.standard.set(exportIncludeLegend, forKey: "exportIncludeLegend")
        }
    }

    // MARK: - First Launch Settings

    /// Whether this is the first time the app has been launched
    var isFirstLaunch: Bool {
        !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
    }

    /// Marks the app as having been launched before
    func markFirstLaunchComplete() {
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
    }

    // MARK: - Import Performance Settings

    /// Whether to use adaptive thread count based on system and file size
    var useAdaptiveThreadCount: Bool {
        didSet {
            UserDefaults.standard.set(useAdaptiveThreadCount, forKey: "useAdaptiveThreadCount")
        }
    }

    /// Manual thread count (used when adaptive is disabled)
    var manualThreadCount: Int {
        didSet {
            UserDefaults.standard.set(manualThreadCount, forKey: "manualThreadCount")
        }
    }

    /// Maximum thread count for adaptive mode
    var maxThreadCount: Int {
        didSet {
            UserDefaults.standard.set(maxThreadCount, forKey: "maxThreadCount")
        }
    }

    // MARK: - Database Performance Settings

    /// Whether to update database statistics (ANALYZE) on launch
    var updateDatabaseStatisticsOnLaunch: Bool {
        didSet {
            UserDefaults.standard.set(updateDatabaseStatisticsOnLaunch, forKey: "updateDatabaseStatisticsOnLaunch")
        }
    }
    
    // MARK: - Computed Properties

    /// Available processor cores on this system
    var systemProcessorCount: Int {
        ProcessInfo.processInfo.activeProcessorCount
    }

    /// Physical memory in GB
    var systemMemoryGB: Int {
        let bytes = ProcessInfo.processInfo.physicalMemory
        return Int(bytes / 1_073_741_824) // Convert to GB
    }

    /// Number of performance cores (accurate for Apple Silicon)
    var performanceCoreCount: Int {
        var perfCores: Int32 = 0
        var size = MemoryLayout<Int32>.size

        // Try to get actual performance core count (works on macOS 12+)
        let result = sysctlbyname("hw.perflevel0.logicalcpu", &perfCores, &size, nil, 0)

        if result == 0 && perfCores > 0 {
            return Int(perfCores)
        }

        // Fallback to estimation if sysctl fails
        return estimatedPerformanceCores
    }

    /// Estimated performance cores (fallback heuristic for non-Apple Silicon or older OS)
    private var estimatedPerformanceCores: Int {
        // Apple Silicon typically has ~2/3 performance cores
        // M3 Ultra: 24 total → ~16 performance cores
        let total = systemProcessorCount
        return max(4, Int(Double(total) * 0.67))
    }

    /// Number of efficiency cores
    var efficiencyCoreCount: Int {
        return systemProcessorCount - performanceCoreCount
    }
    
    /// Gets the optimal thread count based on current settings
    func getOptimalThreadCount(for recordCount: Int) -> Int {
        if useAdaptiveThreadCount {
            return calculateAdaptiveThreadCount(recordCount: recordCount)
        } else {
            return manualThreadCount
        }
    }
    
    // MARK: - Private Methods
    
    private init() {
        // Load export settings from UserDefaults with sensible defaults
        self.exportBackgroundLuminosity = UserDefaults.standard.object(forKey: "exportBackgroundLuminosity") as? Double ?? 0.9
        self.exportLineThickness = UserDefaults.standard.object(forKey: "exportLineThickness") as? Double ?? 6.0
        self.exportBoldAxisLabels = UserDefaults.standard.object(forKey: "exportBoldAxisLabels") as? Bool ?? true
        self.exportScaleFactor = UserDefaults.standard.object(forKey: "exportScaleFactor") as? Double ?? 2.0
        self.exportIncludeLegend = UserDefaults.standard.object(forKey: "exportIncludeLegend") as? Bool ?? true

        // Load performance settings from UserDefaults with sensible defaults
        self.useAdaptiveThreadCount = UserDefaults.standard.object(forKey: "useAdaptiveThreadCount") as? Bool ?? true
        self.manualThreadCount = UserDefaults.standard.object(forKey: "manualThreadCount") as? Int ?? 8
        self.maxThreadCount = UserDefaults.standard.object(forKey: "maxThreadCount") as? Int ?? min(16, ProcessInfo.processInfo.activeProcessorCount)

        // Load database performance settings (off by default to avoid launch delays)
        self.updateDatabaseStatisticsOnLaunch = UserDefaults.standard.object(forKey: "updateDatabaseStatisticsOnLaunch") as? Bool ?? false
    }
    
    /// Calculates optimal thread count based on system characteristics and workload
    private func calculateAdaptiveThreadCount(recordCount: Int) -> Int {
        // Base calculation on actual performance cores
        let baseCores = performanceCoreCount

        // Scale based on workload size
        let workloadFactor: Double
        switch recordCount {
        case 0..<100_000:
            workloadFactor = 0.25  // Small files: use fewer threads (overhead not worth it)
        case 100_000..<1_000_000:
            workloadFactor = 0.5   // Medium files: moderate threading
        case 1_000_000..<5_000_000:
            workloadFactor = 0.75  // Large files: more aggressive threading
        default:
            workloadFactor = 1.0   // Very large files: maximum threading
        }

        let calculatedThreads = Int(Double(baseCores) * workloadFactor)

        // Ensure reasonable bounds
        let minThreads = max(1, recordCount / 1_000_000) // At least 1, more for huge files
        let maxThreads = min(maxThreadCount, baseCores)

        return max(minThreads, min(calculatedThreads, maxThreads))
    }
    
    /// Resets all settings to defaults
    func resetToDefaults() {
        // Reset export settings
        exportBackgroundLuminosity = 0.9
        exportLineThickness = 6.0
        exportBoldAxisLabels = true
        exportScaleFactor = 2.0
        exportIncludeLegend = true

        // Reset performance settings
        useAdaptiveThreadCount = true
        manualThreadCount = 8
        maxThreadCount = min(16, systemProcessorCount)

        // Reset database performance settings
        updateDatabaseStatisticsOnLaunch = false
    }
}