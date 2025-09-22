import Foundation
import Combine

/// Application settings for performance tuning and preferences
@MainActor
class AppSettings: ObservableObject {
    /// Singleton instance
    static let shared = AppSettings()
    
    // MARK: - Import Performance Settings
    
    /// Whether to use adaptive thread count based on system and file size
    @Published var useAdaptiveThreadCount: Bool {
        didSet {
            UserDefaults.standard.set(useAdaptiveThreadCount, forKey: "useAdaptiveThreadCount")
        }
    }
    
    /// Manual thread count (used when adaptive is disabled)
    @Published var manualThreadCount: Int {
        didSet {
            UserDefaults.standard.set(manualThreadCount, forKey: "manualThreadCount")
        }
    }
    
    /// Maximum thread count for adaptive mode
    @Published var maxThreadCount: Int {
        didSet {
            UserDefaults.standard.set(maxThreadCount, forKey: "maxThreadCount")
        }
    }
    
    // MARK: - Computed Properties
    
    /// Available processor cores on this system
    var systemProcessorCount: Int {
        ProcessInfo.processInfo.activeProcessorCount
    }
    
    /// Estimated performance cores (rough heuristic for Apple Silicon)
    var estimatedPerformanceCores: Int {
        // Apple Silicon typically has ~2/3 performance cores
        // M3 Ultra: 24 total → ~16 performance cores
        let total = systemProcessorCount
        return max(4, Int(Double(total) * 0.67))
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
        // Load settings from UserDefaults with sensible defaults
        self.useAdaptiveThreadCount = UserDefaults.standard.object(forKey: "useAdaptiveThreadCount") as? Bool ?? true
        self.manualThreadCount = UserDefaults.standard.object(forKey: "manualThreadCount") as? Int ?? 8
        self.maxThreadCount = UserDefaults.standard.object(forKey: "maxThreadCount") as? Int ?? min(16, ProcessInfo.processInfo.activeProcessorCount)
    }
    
    /// Calculates optimal thread count based on system characteristics and workload
    private func calculateAdaptiveThreadCount(recordCount: Int) -> Int {
        // Base calculation on performance cores and record count
        let baseCores = estimatedPerformanceCores
        
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
        useAdaptiveThreadCount = true
        manualThreadCount = 8
        maxThreadCount = min(16, systemProcessorCount)
    }
}