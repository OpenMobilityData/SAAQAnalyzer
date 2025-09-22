import SwiftUI
import UniformTypeIdentifiers

/// Main application entry point for SAAQ data analyzer
@main
struct SAAQAnalyzerApp: App {
    @StateObject private var databaseManager = DatabaseManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(databaseManager)
                .frame(minWidth: 1200, minHeight: 800)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        
        Settings {
            SettingsView()
                .environmentObject(databaseManager)
        }
    }
}

/// Main content view with three-panel layout
struct ContentView: View {
    @EnvironmentObject var databaseManager: DatabaseManager
    @StateObject private var progressManager = ImportProgressManager()
    @State private var selectedFilters = FilterConfiguration()
    @State private var chartData: [FilteredDataSeries] = []
    @State private var selectedSeries: FilteredDataSeries?
    @State private var showingImportProgress = false
    @State private var isAddingSeries = false
    
    // Import handling state
    @State private var showingDuplicateYearAlert = false
    @State private var duplicateYearToReplace: Int?
    @State private var pendingImportURLs: [URL] = []
    @State private var currentImportIndex = 0
    
    var body: some View {
        NavigationSplitView {
            // Left panel: Filter tree
            FilterPanel(configuration: $selectedFilters)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        } content: {
            // Center panel: Chart display
            ChartView(dataSeries: $chartData, selectedSeries: $selectedSeries)
                .navigationSplitViewColumnWidth(min: 500, ideal: 700)
        } detail: {
            // Right panel: Data inspector
            DataInspectorView(series: selectedSeries)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Import menu
                Menu {
                    Button("Import Geographic Data...") {
                        importGeographicData()
                    }
                    Button("Import Vehicle Data...") {
                        importVehicleData()
                    }
                    Divider()
                    Button("Clear All Data", role: .destructive) {
                        clearAllData()
                    }
                    Divider()
                    Button("Debug: Show Database Contents") {
                        showDatabaseContents()
                    }
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                
                Divider()
                
                // Add series button
                Button {
                    addNewSeries()
                } label: {
                    if isAddingSeries {
                        Label("Adding Series...", systemImage: "arrow.triangle.2.circlepath")
                            .symbolEffect(.rotate, isActive: isAddingSeries)
                    } else {
                        Label("Add Series", systemImage: "plus.circle")
                    }
                }
                .disabled(isAddingSeries)
                
                // Export button
                ExportMenu(chartData: chartData)
                
                Divider()
                
                // Settings are available via macOS Settings menu automatically
            }
        }
        .overlay(alignment: .center) {
            // Import progress overlay
            if showingImportProgress {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    ImportProgressView(progressManager: progressManager)
                        .frame(maxWidth: 600)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            
            // Series query progress overlay
            if isAddingSeries {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                    
                    SeriesQueryProgressView()
                        .frame(maxWidth: 400)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .onChange(of: progressManager.isImporting) { _, isImporting in
            withAnimation(.spring()) {
                showingImportProgress = isImporting
            }
        }
        .onChange(of: progressManager.currentStage) { _, stage in
            if stage == .completed {
                // Auto-hide progress after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.spring()) {
                        showingImportProgress = false
                    }
                }
            }
        }
        .alert("Year \(duplicateYearToReplace ?? 0) Already Exists", isPresented: $showingDuplicateYearAlert) {
            Button("Replace Existing Data", role: .destructive) {
                Task {
                    await handleDuplicateYearReplace(replace: true)
                }
            }
            Button("Cancel Import", role: .cancel) {
                Task {
                    await handleDuplicateYearReplace(replace: false)
                }
            }
        } message: {
            Text("Data for year \(duplicateYearToReplace ?? 0) has already been imported. Do you want to replace the existing data with the new import?")
        }
    }
    
    /// Clears all data from the database
    private func clearAllData() {
        let alert = NSAlert()
        alert.messageText = "Clear All Data?"
        alert.informativeText = "This will delete all imported vehicle and geographic data. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                do {
                    try await databaseManager.clearAllData()
                    await MainActor.run {
                        chartData.removeAll()
                        selectedFilters = FilterConfiguration()
                    }
                    print("All data cleared successfully")
                } catch {
                    print("Error clearing data: \(error)")
                }
            }
        }
    }
    
    /// Adds a new data series based on current filter configuration
    private func addNewSeries() {
        Task {
            await MainActor.run {
                isAddingSeries = true
            }
            
            do {
                let series = try await databaseManager.queryVehicleData(
                    filters: selectedFilters
                )
                await MainActor.run {
                    // Assign unique color based on series index
                    series.color = Color.forSeriesIndex(chartData.count)
                    chartData.append(series)
                    isAddingSeries = false
                }
            } catch {
                await MainActor.run {
                    isAddingSeries = false
                }
                print("Error adding series: \(error)")
            }
        }
    }
    
    /// Imports geographic data from d001 file
    private func importGeographicData() {
        Task { @MainActor in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.plainText]
            panel.message = "Select d001_min.txt file"
            
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                
                Task {
                    do {
                        let importer = GeographicDataImporter(databaseManager: databaseManager)
                        try await importer.importD001File(at: url)
                        print("Geographic data imported successfully")
                    } catch {
                        print("Error importing geographic data: \(error)")
                    }
                }
            }
        }
    }
    
    /// Imports vehicle data from CSV file(s)
    private func importVehicleData() {
        Task { @MainActor in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.allowsMultipleSelection = true
            panel.message = "Select vehicle CSV file(s) - multiple files will be imported sequentially"
            
            panel.begin { response in
                guard response == .OK, !panel.urls.isEmpty else { return }
                
                Task {
                    await self.importMultipleFiles(panel.urls)
                }
            }
        }
    }
    
    /// Imports multiple vehicle files sequentially
    private func importMultipleFiles(_ urls: [URL]) async {
        pendingImportURLs = urls
        currentImportIndex = 0
        await processNextImport()
    }
    
    /// Processes the next import in the queue
    private func processNextImport() async {
        guard currentImportIndex < pendingImportURLs.count else {
            // All imports completed
            print("🎉 Batch import completed!")
            await progressManager.reset()
            pendingImportURLs = []
            currentImportIndex = 0
            return
        }
        
        let url = pendingImportURLs[currentImportIndex]
        let filename = url.lastPathComponent
        let yearPattern = /(\d{4})/
        
        guard let match = filename.firstMatch(of: yearPattern),
              let year = Int(match.1) else {
            print("❌ Could not extract year from filename: \(filename)")
            currentImportIndex += 1
            await processNextImport()
            return
        }
        
        print("📁 Importing file \(currentImportIndex + 1)/\(pendingImportURLs.count): \(filename)")
        
        // Show progress immediately while checking for duplicates
        await MainActor.run {
            showingImportProgress = true
        }
        await progressManager.startImport()
        await progressManager.updateToReading()
        
        // Check if year already exists
        if await databaseManager.isYearImported(year) {
            // Temporarily hide progress for alert
            await MainActor.run {
                showingImportProgress = false
                duplicateYearToReplace = year
                showingDuplicateYearAlert = true
            }
        } else {
            // Proceed with import directly
            await performImport(url: url, year: year)
        }
    }
    
    /// Handles the user's choice for duplicate year
    private func handleDuplicateYearReplace(replace: Bool) async {
        guard let year = duplicateYearToReplace,
              currentImportIndex < pendingImportURLs.count else { return }
        
        let url = pendingImportURLs[currentImportIndex]
        
        if replace {
            // Show progress immediately
            await MainActor.run {
                showingImportProgress = true
            }
            
            // Update progress to show we're deleting
            await progressManager.updateToReading()
            
            print("🗑️ Deleting existing data for year \(year)...")
            do {
                try await databaseManager.clearYearData(year)
                print("✅ Existing data for year \(year) deleted successfully")
                await performImport(url: url, year: year)
            } catch {
                print("❌ Error deleting data for year \(year): \(error)")
                await progressManager.reset()
                currentImportIndex += 1
                await processNextImport()
            }
        } else {
            print("⏹️ Import cancelled by user for year \(year)")
            await progressManager.reset()
            currentImportIndex += 1
            await processNextImport()
        }
        
        duplicateYearToReplace = nil
    }
    
    /// Performs the actual import (with duplicate check already handled by UI)
    private func performImport(url: URL, year: Int) async {
        do {
            let importer = CSVImporter(databaseManager: databaseManager, progressManager: progressManager)
            // Skip duplicate check since we've already handled it in the UI layer
            let result = try await importer.importVehicleFile(at: url, year: year, skipDuplicateCheck: true)
            print("✅ Import completed: \(result.successCount) records imported for year \(year)")
        } catch {
            await progressManager.reset()
            print("❌ Error importing: \(error)")
        }
        
        currentImportIndex += 1
        await processNextImport()
    }
    
    /// Shows database contents for debugging
    private func showDatabaseContents() {
        Task {
            await databaseManager.debugShowContents()
        }
    }
}

/// Settings view for database and import preferences
struct SettingsView: View {
    @EnvironmentObject var databaseManager: DatabaseManager
    @StateObject private var settings = AppSettings.shared
    @AppStorage("defaultImportPath") var defaultImportPath = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Configure database, import preferences, and performance settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Database Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Database")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Database Location:")
                        Spacer()
                        Text(databaseManager.databaseURL?.path ?? "Not set")
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    Button("Change Database Location...") {
                        changeDatabaseLocation()
                    }
                    .buttonStyle(.bordered)
                    
                    HStack {
                        Text("Default Import Path:")
                        TextField("Path", text: $defaultImportPath)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            Divider()
            
            // Import Performance Section
            VStack(alignment: .leading, spacing: 16) {
                Text("Import Performance")
                    .font(.headline)
                
                // System Information
                VStack(alignment: .leading, spacing: 4) {
                    Text("System Information")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("Total CPU Cores:")
                        Spacer()
                        Text("\(settings.systemProcessorCount)")
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Estimated Performance Cores:")
                        Spacer()
                        Text("\(settings.estimatedPerformanceCores)")
                            .fontWeight(.medium)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                // Thread Configuration
                VStack(alignment: .leading, spacing: 12) {
                    // Adaptive vs Manual toggle
                    Toggle(isOn: $settings.useAdaptiveThreadCount) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Adaptive Thread Count")
                                .font(.subheadline)
                            Text("Automatically optimize based on file size and system")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if settings.useAdaptiveThreadCount {
                        // Adaptive settings
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Maximum Threads:")
                                Spacer()
                                Text("\(settings.maxThreadCount)")
                                    .fontWeight(.medium)
                            }
                            
                            Slider(
                                value: Binding(
                                    get: { Double(settings.maxThreadCount) },
                                    set: { settings.maxThreadCount = Int($0) }
                                ),
                                in: 1...Double(settings.systemProcessorCount),
                                step: 1
                            )
                            
                            Text("Adaptive calculation preview:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            adaptivePreviewGrid
                        }
                        .padding(.leading, 20)
                    } else {
                        // Manual settings
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Thread Count:")
                                Spacer()
                                Text("\(settings.manualThreadCount)")
                                    .fontWeight(.medium)
                            }
                            
                            Slider(
                                value: Binding(
                                    get: { Double(settings.manualThreadCount) },
                                    set: { settings.manualThreadCount = Int($0) }
                                ),
                                in: 1...Double(settings.systemProcessorCount),
                                step: 1
                            )
                            
                            Text("Fixed thread count for all imports")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 20)
                    }
                }
            }
            
            Divider()
            
            // Performance Tips
            VStack(alignment: .leading, spacing: 8) {
                Text("Performance Tips")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 4) {
                    performanceTip(
                        icon: "cpu",
                        title: "CPU Usage",
                        description: "More threads = faster imports, but may slow other apps"
                    )
                    
                    performanceTip(
                        icon: "memorychip",
                        title: "Memory Usage", 
                        description: "Each thread uses ~200MB during import"
                    )
                    
                    performanceTip(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Adaptive Mode",
                        description: "Recommended for varying file sizes and system loads"
                    )
                }
            }
            
            Divider()
            
            // Filter Cache Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Filter Cache")
                    .font(.headline)
                
                Text("Filter options (regions, vehicle types, etc.) are cached to improve app startup time. The cache is automatically refreshed when new data is imported.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Cache Status
                VStack(alignment: .leading, spacing: 8) {
                    let cacheInfo = databaseManager.filterCacheInfo
                    
                    HStack {
                        Text("Cache Status:")
                        Spacer()
                        Text(cacheInfo.hasCache ? "Active" : "Empty")
                            .fontWeight(.medium)
                            .foregroundColor(cacheInfo.hasCache ? .green : .orange)
                    }
                    
                    if let lastUpdated = cacheInfo.lastUpdated {
                        HStack {
                            Text("Last Updated:")
                            Spacer()
                            Text(lastUpdated, style: .relative)
                                .fontWeight(.medium)
                        }
                    }
                    
                    if cacheInfo.hasCache {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cached Items:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text("• \(cacheInfo.itemCounts.years) years")
                                Spacer()
                                Text("• \(cacheInfo.itemCounts.regions) regions")
                            }
                            .font(.caption2)
                            
                            HStack {
                                Text("• \(cacheInfo.itemCounts.mrcs) MRCs")
                                Spacer()
                                Text("• \(cacheInfo.itemCounts.classifications) vehicle types")
                            }
                            .font(.caption2)
                        }
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                // Cache Actions
                HStack {
                    Button("Refresh Cache") {
                        Task {
                            await databaseManager.refreshFilterCache()
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Force refresh filter cache from database")
                    
                    Button("Clear Cache") {
                        databaseManager.clearFilterCache()
                    }
                    .buttonStyle(.bordered)
                    .help("Clear cached filter options (will reload from database next time)")
                    
                    Spacer()
                }
            }
            
            Spacer()
            
            // Reset button
            HStack {
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    /// Preview grid showing adaptive thread counts for different file sizes
    private var adaptivePreviewGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                Text("File Size")
                    .font(.caption2)
                    .fontWeight(.medium)
                Text("Threads")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(.secondary)
            
            ForEach([
                (name: "Small (100K)", count: 100_000),
                (name: "Medium (1M)", count: 1_000_000),
                (name: "Large (5M)", count: 5_000_000),
                (name: "Very Large (10M)", count: 10_000_000)
            ], id: \.name) { sample in
                GridRow {
                    Text(sample.name)
                        .font(.caption2)
                    Text("\(settings.getOptimalThreadCount(for: sample.count))")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(6)
    }
    
    /// Individual performance tip row
    private func performanceTip(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func changeDatabaseLocation() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "saaq_data.sqlite"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                databaseManager.setDatabaseLocation(url)
            }
        }
    }
}

// MARK: - Series Query Progress View

/// Progress indicator for database queries when adding series
struct SeriesQueryProgressView: View {
    @State private var animationOffset: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 16) {
            // Progress animation
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.title)
                    .foregroundColor(.accentColor)
                    .symbolEffect(.pulse, isActive: true)
                
                Text("Querying Database")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("Analyzing vehicle data with your filter criteria...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Animated progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                    
                    // Animated shimmer effect
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .clear,
                                    Color.accentColor.opacity(0.8),
                                    Color.accentColor,
                                    Color.accentColor.opacity(0.8),
                                    .clear
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 100, height: 6)
                        .offset(x: animationOffset)
                        .mask(
                            RoundedRectangle(cornerRadius: 3)
                                .frame(height: 6)
                        )
                }
            }
            .frame(height: 6)
            .onAppear {
                withAnimation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    animationOffset = 350 // Should cover most typical widths
                }
            }
        }
        .padding(24)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}
