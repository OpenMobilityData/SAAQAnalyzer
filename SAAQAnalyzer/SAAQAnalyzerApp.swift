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
                .alert("Test Database Found", isPresented: Binding(
                    get: { databaseManager.testDatabaseCleanupNeeded != nil },
                    set: { if !$0 { databaseManager.testDatabaseCleanupNeeded = nil } }
                )) {
                    Button("Keep Existing") {
                        if let testPath = databaseManager.testDatabaseCleanupNeeded {
                            databaseManager.handleTestDatabaseCleanupDecision(shouldDelete: false, testDBPath: testPath)
                        }
                    }
                    Button("Delete and Start Fresh", role: .destructive) {
                        if let testPath = databaseManager.testDatabaseCleanupNeeded {
                            databaseManager.handleTestDatabaseCleanupDecision(shouldDelete: true, testDBPath: testPath)
                        }
                    }
                } message: {
                    Text("A test database from a previous session exists. Would you like to keep it and continue testing, or delete it and start fresh?")
                }
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
    @StateObject private var packageManager = DataPackageManager.shared
    @State private var selectedFilters = FilterConfiguration()
    @State private var chartData: [FilteredDataSeries] = []
    @State private var selectedSeries: FilteredDataSeries?
    @State private var showingImportProgress = false
    @State private var isAddingSeries = false
    @State private var isPreparingImport = false

    // Series query progress state
    @State private var currentQueryPattern: String?
    @State private var currentQueryIsIndexed: Bool?
    @State private var queryStartTime: Date?

    // Import handling state
    @State private var showingDuplicateYearAlert = false
    @State private var showingClearDataAlert = false
    @State private var duplicateYearToReplace: Int?
    @State private var pendingImportURLs: [URL] = []
    @State private var currentImportIndex = 0
    @State private var currentImportType: DataEntityType = .vehicle
    @State private var batchImportStartTime: Date?

    // Data package import handling state
    @State private var showingPackageAlert = false

    // Schema optimization state
    @State private var isMigratingSchema = false
    @State private var isRunningPerformanceTest = false
    @State private var showingOptimizationResults = false
    @State private var optimizationResults: String = ""
    @State private var packageAlertMessage = ""

    // SwiftUI file dialog states - consolidated to avoid SwiftUI fileImporter bug
    enum FileImporterMode {
        case vehicle, license, dataPackage, geographic
    }
    @State private var activeFileImporterMode: FileImporterMode?
    @State private var pendingFileImporterMode: FileImporterMode? // Preserved across dialog dismissal
    @State private var showingPackageExporter = false

    // Confirmation dialog states
    @State private var showingClearDataConfirmation = false
    @State private var showingPackageImportConfirmation = false
    @State private var pendingPackageURL: URL?

    // MARK: - SwiftUI File Dialog Handlers

    /// Handle geographic file import result
    private func handleGeographicFileImport(_ result: Result<[URL], Error>) {
        Task {
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    let importer = GeographicDataImporter(databaseManager: databaseManager)
                    try await importer.importD001File(at: url)
                    print("Geographic data imported successfully")
                } catch {
                    print("Error importing geographic data: \(error)")
                }
            case .failure(let error):
                print("File selection error: \(error)")
            }
        }
    }

    /// Handle geographic data file import result (for development)
    private func handleGeographicDataFileImport(_ result: Result<[URL], Error>) {
        Task {
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    let importer = GeographicDataImporter(databaseManager: databaseManager)
                    try await importer.importD001File(at: url)
                    print("Geographic data imported successfully from: \(url.lastPathComponent)")
                } catch {
                    print("Error importing geographic data: \(error)")
                }
            case .failure(let error):
                print("File selection error: \(error)")
            }
        }
    }

    /// Handle vehicle file import result
    private func handleVehicleFileImport(_ result: Result<[URL], Error>) {
        Task {
            switch result {
            case .success(let urls):
                guard !urls.isEmpty else {
                    await MainActor.run { isPreparingImport = false }
                    return
                }
                await importMultipleFiles(urls)
            case .failure(let error):
                print("File selection error: \(error)")
                await MainActor.run { isPreparingImport = false }
            }
        }
    }

    /// Handle license file import result
    private func handleLicenseFileImport(_ result: Result<[URL], Error>) {
        Task {
            switch result {
            case .success(let urls):
                guard !urls.isEmpty else {
                    await MainActor.run { isPreparingImport = false }
                    return
                }
                await importMultipleLicenseFiles(urls)
            case .failure(let error):
                print("File selection error: \(error)")
                await MainActor.run { isPreparingImport = false }
            }
        }
    }

    /// Handle data package import result
    private func handlePackageImport(_ result: Result<[URL], Error>) {
        Task { @MainActor in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }

                // Validate package first
                let validationResult = await packageManager.validateDataPackage(at: url)

                if validationResult != .valid {
                    packageAlertMessage = validationResult.errorMessage
                    showingPackageAlert = true
                    return
                }

                // Show confirmation dialog
                pendingPackageURL = url
                showingPackageImportConfirmation = true

            case .failure(let error):
                print("File selection error: \(error)")
            }
        }
    }

    /// Perform clear all data action
    private func performClearAllData() {
        Task {
            do {
                try await databaseManager.clearAllData()
                await MainActor.run {
                    chartData.removeAll()
                    selectedSeries = nil
                }
                print("✅ All data cleared successfully")
            } catch {
                print("❌ Error clearing data: \(error)")
            }
        }
    }

    /// Perform data package import action
    private func performPackageImport(_ url: URL) {
        Task { @MainActor in
            do {
                try await packageManager.importDataPackage(from: url)

                // Reset UI state
                chartData.removeAll()
                selectedSeries = nil

                packageAlertMessage = "Data package imported successfully!"
                showingPackageAlert = true

                print("✅ Data package imported successfully")

            } catch {
                packageAlertMessage = "Failed to import data package: \(error.localizedDescription)"
                showingPackageAlert = true
                print("❌ Error importing data package: \(error)")
            }

            pendingPackageURL = nil
        }
    }

    var body: some View {
        mainContent
            .fileImporter(
                isPresented: Binding(
                    get: { activeFileImporterMode != nil },
                    set: { newValue in
                        if !newValue {
                            // Dialog is closing - preserve mode for result handler
                            pendingFileImporterMode = activeFileImporterMode
                            activeFileImporterMode = nil
                        }
                    }
                ),
                allowedContentTypes: allowedFileTypes,
                allowsMultipleSelection: allowsMultipleSelection
            ) { result in
                handleFileImportResult(result)
            }
            .fileExporter(
                isPresented: $showingPackageExporter,
                document: DataPackageDocument(packageManager: packageManager, databaseManager: databaseManager),
                contentType: .saaqPackage,
                defaultFilename: "SAAQData_\(Date().formatted(date: .abbreviated, time: .omitted)).saaqpackage"
            ) { result in
                handlePackageExportResult(result)
            }
            .confirmationDialog("Clear All Data?", isPresented: $showingClearDataConfirmation) {
                Button("Clear All Data", role: .destructive) {
                    performClearAllData()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will delete all imported vehicle and geographic data. This cannot be undone.")
            }
            .confirmationDialog("Import Data Package?", isPresented: $showingPackageImportConfirmation) {
                Button("Import", role: .destructive) {
                    if let url = pendingPackageURL {
                        performPackageImport(url)
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingPackageURL = nil
                }
            } message: {
                Text("This will replace your current database and caches. This operation cannot be undone.")
            }
    }

    private var leftPanel: some View {
        // Left panel: Filter tree
        FilterPanel(configuration: $selectedFilters)
            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
    }

    private var centerPanel: some View {
        // Center panel: Chart display
        ChartView(dataSeries: $chartData, selectedSeries: $selectedSeries)
            .navigationSplitViewColumnWidth(min: 500, ideal: 700)
    }

    private var rightPanel: some View {
        // Right panel: Data inspector
        DataInspectorView(series: selectedSeries)
            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
    }

    private var splitView: some View {
        NavigationSplitView {
            leftPanel
        } content: {
            centerPanel
        } detail: {
            rightPanel
        }
    }

    private var principalToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            // Data type selector
            Menu {
                ForEach(DataEntityType.allCases, id: \.self) { dataType in
                    Button {
                        selectedFilters.dataEntityType = dataType
                    } label: {
                        Label(dataType.description, systemImage: dataType == .vehicle ? "car" : "person.crop.circle")
                    }
                }
            } label: {
                Label(selectedFilters.dataEntityType.description,
                      systemImage: selectedFilters.dataEntityType == .vehicle ? "car" : "person.crop.circle")
            }

            // Create Series button
            Button {
                refreshChartData()
            } label: {
                if isAddingSeries {
                    Label("Adding Series...", systemImage: "arrow.triangle.2.circlepath")
                        .symbolEffect(.rotate, isActive: isAddingSeries)
                } else {
                    Label("Add Series", systemImage: "plus.circle")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAddingSeries)
        }
    }

    private var primaryActionToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Import menu
            Menu {
                Label("CSV Files", systemImage: "doc.text")
                    .font(.caption)
                Button("Import Vehicle Data Files...") {
                    importVehicleFiles()
                }
                Button("Import License Data Files...") {
                    importLicenseFiles()
                }

                Divider()

                Label("Data Package", systemImage: "shippingbox")
                    .font(.caption)
                Button("Import Data Package...") {
                    activeFileImporterMode = .dataPackage
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

            // Export menu
            Menu {
                Button("Export Data Package...") {
                    showingPackageExporter = true
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export options")

            // Schema Optimization menu
            Menu {
                Label("Database Optimization", systemImage: "speedometer")
                    .font(.caption)
                Button(isMigratingSchema ? "Migrating Schema..." : "Migrate to Optimized Schema") {
                    migrateToOptimizedSchema()
                }
                .disabled(isMigratingSchema)

                Button(isRunningPerformanceTest ? "Testing Performance..." : "Run Performance Test") {
                    runPerformanceTest()
                }
                .disabled(isRunningPerformanceTest)

                if !optimizationResults.isEmpty {
                    Divider()
                    Button("Show Last Results") {
                        showingOptimizationResults = true
                    }
                }
            } label: {
                Label("Optimize", systemImage: "speedometer")
            }
        }
    }

    private var mainContent: some View {
        splitView
        .toolbar {
            principalToolbar
            primaryActionToolbar
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
        .alert("Year \\(duplicateYearToReplace?.formatted(.number.grouping(.never)) ?? \"Unknown\") Already Exists", isPresented: $showingDuplicateYearAlert) {
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
            Text("This will replace your current database and caches. This operation cannot be undone.")
        }
        .alert("Clear All Data", isPresented: $showingClearDataAlert) {
            Button("Clear All Data", role: .destructive) {
                Task {
                    do {
                        try await databaseManager.clearAllData()
                        chartData.removeAll()
                        selectedSeries = nil
                        print("✅ All data cleared successfully")
                    } catch {
                        print("❌ Error clearing data: \(error)")
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete all imported data. This action cannot be undone.")
        }
        .alert("Schema Optimization Results", isPresented: $showingOptimizationResults) {
            Button("OK") { }
        } message: {
            Text(optimizationResults)
        }
        .overlay(alignment: .center) {
            // Preparing import overlay (instant feedback)
            if isPreparingImport {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))

                        Text("Preparing import...")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    .padding(40)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    .transition(.scale.combined(with: .opacity))
                }
            }

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

                    SeriesQueryProgressView(
                        queryPattern: currentQueryPattern,
                        isIndexed: currentQueryIsIndexed,
                        dataType: selectedFilters.dataEntityType == .vehicle ? "vehicle registrations" : "license holders"
                    )
                    .frame(maxWidth: 400)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - File Importer Helpers

    private var allowedFileTypes: [UTType] {
        switch activeFileImporterMode {
        case .vehicle, .license:
            return [.commaSeparatedText]
        case .dataPackage:
            return [.saaqPackage]
        case .geographic:
            return [.plainText]
        case .none:
            return []
        }
    }

    private var allowsMultipleSelection: Bool {
        switch activeFileImporterMode {
        case .vehicle, .license:
            return true
        case .dataPackage, .geographic:
            return false
        case .none:
            return false
        }
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        // Use pending mode that was preserved when dialog closed
        let mode = pendingFileImporterMode
        print("🔍 Consolidated fileImporter result handler called for mode: \(String(describing: mode))")

        // Clear pending mode after use
        pendingFileImporterMode = nil

        switch mode {
        case .vehicle:
            handleVehicleFileImport(result)
        case .license:
            handleLicenseFileImport(result)
        case .dataPackage:
            handlePackageImport(result)
        case .geographic:
            handleGeographicFileImport(result)
        case .none:
            print("⚠️ Warning: fileImporter mode was nil when handling result")
            break
        }
    }

    // MARK: - Helper Functions

    private func refreshChartData() {
        Task {
            let queryPattern = generateQueryPattern(from: selectedFilters)

            // Analyze actual index usage deterministically
            let actualIndexUsage = await databaseManager.analyzeQueryIndexUsage(filters: selectedFilters)

            await MainActor.run {
                currentQueryPattern = queryPattern
                currentQueryIsIndexed = actualIndexUsage
                isAddingSeries = true
            }

            do {
                let newSeries = try await databaseManager.queryData(filters: selectedFilters)

                await MainActor.run {
                    // Assign unique color based on series index
                    newSeries.color = Color.forSeriesIndex(chartData.count)
                    chartData.append(newSeries)
                    selectedSeries = newSeries
                    isAddingSeries = false
                    currentQueryPattern = nil
                    currentQueryIsIndexed = nil
                }
            } catch {
                await MainActor.run {
                    isAddingSeries = false
                    currentQueryPattern = nil
                    currentQueryIsIndexed = nil
                }
                print("❌ Error creating chart series: \(error)")
            }
        }
    }

    private func generateQueryPattern(from filters: FilterConfiguration) -> String {
        var components: [String] = []

        // Data type
        components.append(filters.dataEntityType.rawValue.capitalized)

        // Years
        if !filters.years.isEmpty {
            let yearList = filters.years.sorted()
            if yearList.count <= 3 {
                components.append("Years: \(yearList.map(String.init).joined(separator: ", "))")
            } else {
                components.append("Years: \(yearList.first!)–\(yearList.last!) (\(yearList.count) years)")
            }
        }

        // Geography (show actual values for better transparency)
        if !filters.regions.isEmpty {
            let regionList = Array(filters.regions).sorted()
            if regionList.count <= 2 {
                components.append("Regions: \(regionList.joined(separator: ", "))")
            } else {
                components.append("Regions: \(regionList.prefix(2).joined(separator: ", "))... (\(regionList.count) total)")
            }
        } else if !filters.mrcs.isEmpty {
            let mrcList = Array(filters.mrcs).sorted()
            if mrcList.count <= 2 {
                components.append("MRCs: \(mrcList.joined(separator: ", "))")
            } else {
                components.append("MRCs: \(mrcList.prefix(2).joined(separator: ", "))... (\(mrcList.count) total)")
            }
        } else if !filters.municipalities.isEmpty {
            let municipalityList = Array(filters.municipalities).sorted()
            if municipalityList.count <= 2 {
                components.append("Municipalities: \(municipalityList.joined(separator: ", "))")
            } else {
                components.append("Municipalities: \(municipalityList.prefix(2).joined(separator: ", "))... (\(municipalityList.count) total)")
            }
        }

        // Vehicle-specific filters (show actual values)
        if filters.dataEntityType == .vehicle {
            if !filters.vehicleClassifications.isEmpty {
                let classificationList = Array(filters.vehicleClassifications).sorted()
                if classificationList.count <= 2 {
                    components.append("Classifications: \(classificationList.joined(separator: ", "))")
                } else {
                    components.append("Classifications: \(classificationList.prefix(2).joined(separator: ", "))... (\(classificationList.count) total)")
                }
            }
            if !filters.fuelTypes.isEmpty {
                let fuelList = Array(filters.fuelTypes).sorted()
                if fuelList.count <= 2 {
                    components.append("Fuel: \(fuelList.joined(separator: ", "))")
                } else {
                    components.append("Fuel: \(fuelList.prefix(2).joined(separator: ", "))... (\(fuelList.count) total)")
                }
            }
            if !filters.ageRanges.isEmpty {
                components.append("Age ranges: \(filters.ageRanges.count)")
            }
        }

        // License-specific filters (show actual values)
        if filters.dataEntityType == .license {
            if !filters.licenseTypes.isEmpty {
                let licenseList = Array(filters.licenseTypes).sorted()
                if licenseList.count <= 2 {
                    components.append("License types: \(licenseList.joined(separator: ", "))")
                } else {
                    components.append("License types: \(licenseList.prefix(2).joined(separator: ", "))... (\(licenseList.count) total)")
                }
            }
            if !filters.ageGroups.isEmpty {
                let ageList = Array(filters.ageGroups).sorted()
                if ageList.count <= 2 {
                    components.append("Age groups: \(ageList.joined(separator: ", "))")
                } else {
                    components.append("Age groups: \(ageList.prefix(2).joined(separator: ", "))... (\(ageList.count) total)")
                }
            }
        }

        return components.joined(separator: " • ")
    }

    private func importVehicleFiles() {
        print("🔍 importVehicleFiles() called - setting activeFileImporterMode to .vehicle")
        // Show preparing overlay immediately for instant feedback
        isPreparingImport = true
        activeFileImporterMode = .vehicle
    }

    private func importLicenseFiles() {
        // Show preparing overlay immediately for instant feedback
        isPreparingImport = true
        activeFileImporterMode = .license
    }

    private func clearAllData() {
        showingClearDataAlert = true
    }

    private func showDatabaseContents() {
        Task {
            let stats = await databaseManager.getDatabaseStats()
            print("📊 Database Statistics:")
            print("   Vehicle Records: \(stats.totalVehicleRecords)")
            print("   License Records: \(stats.totalLicenseRecords)")
            print("   Vehicle Years: \(stats.vehicleYearRange)")
            print("   License Years: \(stats.licenseYearRange)")
            print("   Database size: \(formatFileSize(stats.fileSizeBytes))")
        }
    }

    private func handleDuplicateYearReplace(replace: Bool) async {
        if replace, let year = duplicateYearToReplace {
            print("🔄 Replacing data for year \(year)")
            // Continue with import for the duplicate year
            await processNextVehicleImport()
        } else {
            print("❌ Import cancelled for duplicate year")
            // Reset import state
            await progressManager.reset()
            currentImportIndex = 0
            pendingImportURLs = []
        }

        // Reset the duplicate year state
        duplicateYearToReplace = nil
        showingDuplicateYearAlert = false
    }

    private func importMultipleFiles(_ urls: [URL]) async {
        // Start timing
        await MainActor.run {
            batchImportStartTime = Date()
        }

        print("📦 Starting batch import of \(urls.count) vehicle files")

        // Start progress UI (this will trigger showingImportProgress = true)
        await progressManager.startBatchImport(totalFiles: urls.count)

        // Wait for progress UI to appear before hiding preparing overlay
        await MainActor.run {
            pendingImportURLs = urls
            currentImportIndex = 0
            // Hide preparing overlay now that real progress is showing
            isPreparingImport = false
        }

        // Sort files by year extracted from filename (background work)
        let sortedURLs = urls.sorted { url1, url2 in
            let year1 = extractYearFromFilename(url1.lastPathComponent) ?? 0
            let year2 = extractYearFromFilename(url2.lastPathComponent) ?? 0
            return year1 < year2
        }

        print("📋 Sorted \(sortedURLs.count) files by year:")
        for (index, url) in sortedURLs.enumerated() {
            let year = extractYearFromFilename(url.lastPathComponent) ?? 0
            print("   \(index + 1). Year \(year): \(url.lastPathComponent)")
        }

        // Update with sorted URLs
        await MainActor.run {
            pendingImportURLs = sortedURLs
        }

        // Begin processing
        await processNextVehicleImport()
    }

    private func importMultipleLicenseFiles(_ urls: [URL]) async {
        // Start timing
        await MainActor.run {
            batchImportStartTime = Date()
        }

        print("📦 Starting batch import of \(urls.count) license files")

        // Start progress UI (this will trigger showingImportProgress = true)
        await progressManager.startBatchImport(totalFiles: urls.count)

        // Wait for progress UI to appear before hiding preparing overlay
        await MainActor.run {
            pendingImportURLs = urls
            currentImportIndex = 0
            // Hide preparing overlay now that real progress is showing
            isPreparingImport = false
        }

        // Sort files by year extracted from filename (background work)
        let sortedURLs = urls.sorted { url1, url2 in
            let year1 = extractYearFromFilename(url1.lastPathComponent) ?? 0
            let year2 = extractYearFromFilename(url2.lastPathComponent) ?? 0
            return year1 < year2
        }

        print("📋 Sorted \(sortedURLs.count) license files by year:")
        for (index, url) in sortedURLs.enumerated() {
            let year = extractYearFromFilename(url.lastPathComponent) ?? 0
            print("   \(index + 1). Year \(year): \(url.lastPathComponent)")
        }

        // Update with sorted URLs
        await MainActor.run {
            pendingImportURLs = sortedURLs
        }

        // Begin processing
        await processNextLicenseImport()
    }

    /// Extract year from filename (supports "2011_..." or "..._2011.csv" formats)
    private func extractYearFromFilename(_ filename: String) -> Int? {
        let components = filename.components(separatedBy: CharacterSet(charactersIn: "_."))
        let yearString = components.first { $0.count == 4 && Int($0) != nil }
        return yearString.flatMap { Int($0) }
    }

    private func processNextVehicleImport() async {
        guard currentImportIndex < pendingImportURLs.count else {
            // All files processed - now refresh cache once
            let fileCount = pendingImportURLs.count
            let totalElapsed = batchImportStartTime.map { Date().timeIntervalSince($0) } ?? 0

            print("🎉 All \(fileCount) files imported successfully!")
            if totalElapsed > 0 {
                let minutes = Int(totalElapsed) / 60
                let seconds = Int(totalElapsed) % 60
                print("⏱️  Total batch import time: \(minutes)m \(seconds)s (\(String(format: "%.1f", totalElapsed))s)")
                print("   Average per file: \(String(format: "%.1f", totalElapsed / Double(fileCount)))s")
            }
            print("🔄 Refreshing filter cache for all imported data...")

            await progressManager.updateIndexingOperation("Refreshing filter cache for all years...")

            // Trigger cache refresh on main database manager
            await databaseManager.refreshAllCachesAfterBatchImport()

            // Complete progress
            await progressManager.completeImport(recordsImported: 0) // Records already logged per file

            currentImportIndex = 0
            pendingImportURLs = []
            batchImportStartTime = nil
            return
        }

        let url = pendingImportURLs[currentImportIndex]
        let filename = url.lastPathComponent

        // Update batch progress
        await progressManager.updateCurrentFile(index: currentImportIndex, fileName: filename)

        guard let year = extractYearFromFilename(filename) else {
            print("❌ Could not extract year from filename: \(filename)")
            currentImportIndex += 1
            await processNextVehicleImport()
            return
        }
        print("📅 Extracted year \(year) from filename: \(filename)")

        // Check for duplicates
        let yearExists = await databaseManager.isYearImported(year)
        if yearExists {
            duplicateYearToReplace = year
            showingDuplicateYearAlert = true
            return
        }

        await performVehicleImport(url: url, year: year)
    }

    private func processNextLicenseImport() async {
        guard currentImportIndex < pendingImportURLs.count else {
            // All files processed - now refresh cache once
            let fileCount = pendingImportURLs.count
            let totalElapsed = batchImportStartTime.map { Date().timeIntervalSince($0) } ?? 0

            print("🎉 All \(fileCount) license files imported successfully!")
            if totalElapsed > 0 {
                let minutes = Int(totalElapsed) / 60
                let seconds = Int(totalElapsed) % 60
                print("⏱️  Total batch import time: \(minutes)m \(seconds)s (\(String(format: "%.1f", totalElapsed))s)")
                print("   Average per file: \(String(format: "%.1f", totalElapsed / Double(fileCount)))s")
            }
            print("🔄 Refreshing filter cache for all imported data...")

            await progressManager.updateIndexingOperation("Refreshing filter cache for all years...")

            // Trigger cache refresh on main database manager
            await databaseManager.refreshAllCachesAfterBatchImport()

            // Complete progress
            await progressManager.completeImport(recordsImported: 0) // Records already logged per file

            currentImportIndex = 0
            pendingImportURLs = []
            batchImportStartTime = nil
            return
        }

        let url = pendingImportURLs[currentImportIndex]
        let filename = url.lastPathComponent

        // Update batch progress
        await progressManager.updateCurrentFile(index: currentImportIndex, fileName: filename)

        guard let year = extractYearFromFilename(filename) else {
            print("❌ Could not extract year from filename: \(filename)")
            currentImportIndex += 1
            await processNextLicenseImport()
            return
        }
        print("📅 Extracted year \(year) from filename: \(filename)")

        await performLicenseImport(url: url, year: year)
    }

    private func performVehicleImport(url: URL, year: Int) async {
        do {
            let importer = CSVImporter(databaseManager: databaseManager, progressManager: progressManager)
            // Skip duplicate check during batch imports - we already checked at batch level
            let result = try await importer.importFile(at: url, year: year, dataType: .vehicle, skipDuplicateCheck: true)
            print("✅ Import completed: \(result.successCount) records imported for year \(year)")
        } catch {
            await progressManager.reset()
            print("❌ Error importing vehicle data: \(error)")
        }

        currentImportIndex += 1
        await processNextVehicleImport()
    }

    private func performLicenseImport(url: URL, year: Int) async {
        do {
            let importer = CSVImporter(databaseManager: databaseManager, progressManager: progressManager)
            // Skip duplicate check during batch imports - we already checked at batch level
            let result = try await importer.importFile(at: url, year: year, dataType: .license, skipDuplicateCheck: true)
            print("✅ License import completed: \(result.successCount) records imported for year \(year)")
        } catch {
            await progressManager.reset()
            print("❌ Error importing license data: \(error)")
        }

        currentImportIndex += 1
        await processNextLicenseImport()
    }

    /// Handle package export result
    private func handlePackageExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            packageAlertMessage = "Data package exported successfully to: \(url.lastPathComponent)"
            showingPackageAlert = true
        case .failure(let error):
            packageAlertMessage = "Export cancelled: \(error.localizedDescription)"
            showingPackageAlert = true
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Schema Optimization Functions

    private func migrateToOptimizedSchema() {
        guard let schemaManager = databaseManager.schemaManager else {
            print("❌ Schema manager not available")
            return
        }

        isMigratingSchema = true
        optimizationResults = ""

        Task {
            do {
                let startTime = Date()
                try await schemaManager.migrateToOptimizedSchema()
                let duration = Date().timeIntervalSince(startTime)

                await MainActor.run {
                    optimizationResults = """
                    ✅ Schema Migration Completed Successfully!

                    Duration: \(String(format: "%.2f", duration)) seconds

                    Categorical enumeration tables created and populated.
                    Integer foreign key columns added to main tables.
                    Optimized indexes created for improved performance.

                    Your database is now using categorical enumeration for:
                    • Vehicle classifications, makes, models, colors, fuel types
                    • Geographic regions, MRCs, municipalities
                    • License age groups, genders, license types
                    • Years and other categorical data

                    Expected benefits:
                    • 3-5x faster query performance
                    • 50-70% reduction in storage size
                    • Improved memory efficiency
                    """
                    isMigratingSchema = false
                    showingOptimizationResults = true
                }
            } catch {
                await MainActor.run {
                    optimizationResults = "❌ Schema migration failed: \(error.localizedDescription)"
                    isMigratingSchema = false
                    showingOptimizationResults = true
                }
            }
        }
    }

    private func runPerformanceTest() {
        guard let optimizedQueryManager = databaseManager.optimizedQueryManager else {
            print("❌ Optimized query manager not available")
            return
        }

        isRunningPerformanceTest = true
        optimizationResults = ""

        Task {
            do {
                let testFilters = FilterConfiguration()
                let results = try await optimizedQueryManager.analyzePerformanceImprovement(filters: testFilters)

                await MainActor.run {
                    optimizationResults = results.description
                    isRunningPerformanceTest = false
                    showingOptimizationResults = true
                }
            } catch {
                await MainActor.run {
                    optimizationResults = "❌ Performance test failed: \(error.localizedDescription)"
                    isRunningPerformanceTest = false
                    showingOptimizationResults = true
                }
            }
        }
    }
}

// MARK: - Data Package Document

/// Document wrapper for data package export
struct DataPackageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.saaqPackage] }

    let packageManager: DataPackageManager
    let databaseManager: DatabaseManager

    init(packageManager: DataPackageManager, databaseManager: DatabaseManager) {
        self.packageManager = packageManager
        self.databaseManager = databaseManager
    }

    init(configuration: ReadConfiguration) throws {
        // Not used for export
        self.packageManager = DataPackageManager.shared
        self.databaseManager = DatabaseManager.shared
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Create package in temp location synchronously
        let tempDir = FileManager.default.temporaryDirectory
        let packageURL = tempDir.appendingPathComponent("ExportPackage_\(UUID().uuidString).saaqpackage")

        print("📦 Starting package export to: \(packageURL.path)")

        // Export package synchronously by blocking on async operation
        let semaphore = DispatchSemaphore(value: 0)
        var exportError: Error?

        Task { @MainActor in
            do {
                let options = DataPackageExportOptions.complete
                try await packageManager.exportDataPackage(to: packageURL, options: options)
                print("✅ Package export completed successfully")
            } catch {
                print("❌ Package export failed: \(error)")
                exportError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = exportError {
            throw error
        }

        // Verify package structure before returning
        let contentsURL = packageURL.appendingPathComponent("Contents")
        if FileManager.default.fileExists(atPath: contentsURL.path) {
            print("✓ Contents directory exists")
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: contentsURL.path) {
                print("✓ Contents: \(contents)")
            }
        } else {
            print("❌ Contents directory missing!")
        }

        // Return the package directory as a FileWrapper with recursive reading
        let wrapper = try FileWrapper(url: packageURL, options: [.immediate, .withoutMapping])

        // Verify the wrapper contains all subdirectories
        print("📦 FileWrapper contains \(wrapper.fileWrappers?.count ?? 0) items")
        if let wrappers = wrapper.fileWrappers {
            for (name, _) in wrappers {
                print("  - \(name)")
            }
        }

        return wrapper
    }
}

// MARK: - Series Query Progress View

/// Progress indicator for database queries when adding series
struct SeriesQueryProgressView: View {
    @State private var animationOffset: CGFloat = 0

    // Query information for enhanced feedback
    let queryPattern: String?
    let isIndexed: Bool?
    let dataType: String

    init(queryPattern: String? = nil, isIndexed: Bool? = nil, dataType: String = "data") {
        self.queryPattern = queryPattern
        self.isIndexed = isIndexed
        self.dataType = dataType
    }

    var body: some View {
        VStack(spacing: 16) {
            // Progress animation
            VStack(spacing: 8) {
                // Icon based on index status
                Image(systemName: iconName)
                    .font(.title)
                    .foregroundColor(iconColor)
                    .symbolEffect(.pulse, isActive: true)

                Text(titleText)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(subtitleText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                // Query pattern information
                if let pattern = queryPattern {
                    Text("Query: \(pattern)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                }

                // Query optimization status
                if let indexed = isIndexed {
                    HStack(spacing: 4) {
                        Image(systemName: indexed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(indexed ? .green : .orange)
                        Text(indexed ? "Using integer enumeration optimization" : "Using legacy query path")
                            .font(.caption2)
                            .foregroundColor(indexed ? .green : .orange)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 2)
                    .background((indexed ? Color.green : Color.orange).opacity(0.1))
                    .cornerRadius(4)
                }
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

    // MARK: - Computed Properties

    private var iconName: String {
        if let indexed = isIndexed {
            return indexed ? "magnifyingglass" : "clock.arrow.circlepath"
        }
        return "magnifyingglass"
    }

    private var iconColor: Color {
        if let indexed = isIndexed {
            return indexed ? .accentColor : .orange
        }
        return .accentColor
    }

    private var titleText: String {
        if let indexed = isIndexed, !indexed {
            return "Legacy Query in Progress"
        }
        return "Querying Database"
    }

    private var subtitleText: String {
        if let indexed = isIndexed {
            if indexed {
                return "Processing \(dataType) using integer-based enumeration tables..."
            } else {
                return "Using legacy string-based queries - consider reimporting data for optimal performance..."
            }
        }
        return "Analyzing \(dataType) with your filter criteria..."
    }
}

// MARK: - Settings View

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)

            PerformanceSettingsView()
                .tabItem {
                    Label("Performance", systemImage: "speedometer")
                }
                .tag(1)

            DatabaseSettingsView()
                .tabItem {
                    Label("Database", systemImage: "cylinder.split.1x2")
                }
                .tag(2)

            ExportSettingsView()
                .tabItem {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .tag(3)
        }
        .frame(width: 550, height: 650)
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsView: View {
    @StateObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Application") {
                Button("Reset All Settings to Defaults") {
                    settings.resetToDefaults()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
}

// MARK: - Performance Settings Tab

struct PerformanceSettingsView: View {
    @StateObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // System Information
                VStack(alignment: .leading, spacing: 4) {
                    Text("System Information")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack {
                        Text("Physical Memory:")
                        Spacer()
                        Text("\(settings.systemMemoryGB) GB")
                            .fontWeight(.medium)
                    }

                    HStack {
                        Text("Total CPU Cores:")
                        Spacer()
                        Text("\(settings.systemProcessorCount)")
                            .fontWeight(.medium)
                    }

                    HStack {
                        Text("Performance Cores:")
                        Spacer()
                        Text("\(settings.performanceCoreCount)")
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }

                    HStack {
                        Text("Efficiency Cores:")
                        Spacer()
                        Text("\(settings.efficiencyCoreCount)")
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)

                Divider()

                // Thread Configuration
                VStack(alignment: .leading, spacing: 12) {
                    Text("Thread Configuration")
                        .font(.headline)

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
            }
            .padding(20)
        }
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
}

// MARK: - Database Settings Tab

struct DatabaseSettingsView: View {
    @StateObject private var databaseManager = DatabaseManager.shared
    @StateObject private var settings = AppSettings.shared
    @State private var cachedStats: CachedDatabaseStats?
    @State private var isLoading = true
    @State private var isOptimizing = false

    var body: some View {
        Form {
            Section("Database Statistics") {
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading statistics...")
                            .foregroundColor(.secondary)
                    }
                } else if let stats = cachedStats {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Vehicle Records: \(stats.totalVehicleRecords.formatted())")
                        Text("License Records: \(stats.totalLicenseRecords.formatted())")
                        Text("Vehicle Years: \(stats.vehicleYearRange)")
                        Text("License Years: \(stats.licenseYearRange)")
                        Text("Municipalities: \(stats.municipalities)")
                        Text("Regions: \(stats.regions)")
                        Text("Database Size: \(formatFileSize(stats.fileSizeBytes))")
                        Text("Last Updated: \(stats.lastUpdated.formatted())")
                    }
                    .font(.system(.body, design: .monospaced))
                } else {
                    Text("Unable to load statistics")
                        .foregroundColor(.secondary)
                }
            }

            Section("Database Optimization") {
                Toggle("Update Statistics on Launch", isOn: $settings.updateDatabaseStatisticsOnLaunch)
                    .help("Run ANALYZE command on launch to update query planner statistics (may delay startup)")

                Button(isOptimizing ? "Optimizing..." : "Update Statistics Now") {
                    Task {
                        await optimizeDatabase()
                    }
                }
                .disabled(isOptimizing)
                .help("Run ANALYZE to update SQLite query planner statistics")
            }
        }
        .padding(20)
        .task {
            await loadStats()
        }
    }

    private func loadStats() async {
        await MainActor.run {
            isLoading = true
        }

        let stats = await databaseManager.getDatabaseStats()

        await MainActor.run {
            cachedStats = stats
            isLoading = false
        }
    }

    private func optimizeDatabase() async {
        await MainActor.run {
            isOptimizing = true
        }

        do {
            try await databaseManager.updateDatabaseStatistics()
        } catch {
            print("⚠️ Failed to update database statistics: \(error)")
        }

        await MainActor.run {
            isOptimizing = false
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Export Settings Tab

struct ExportSettingsView: View {
    @StateObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Chart Export") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Background Brightness:")
                        Slider(value: $settings.exportBackgroundLuminosity, in: 0...1)
                        Text("\(Int(settings.exportBackgroundLuminosity * 100))%")
                            .frame(width: 40)
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Line Thickness:")
                        Slider(value: $settings.exportLineThickness, in: 1...12)
                        Text("\(Int(settings.exportLineThickness))")
                            .frame(width: 40)
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Export Scale:")
                        Slider(value: $settings.exportScaleFactor, in: 1...4, step: 0.5)
                        Text("\(settings.exportScaleFactor, specifier: "%.1f")×")
                            .frame(width: 40)
                            .monospacedDigit()
                    }

                    Toggle("Bold Axis Labels", isOn: $settings.exportBoldAxisLabels)
                    Toggle("Include Legend", isOn: $settings.exportIncludeLegend)
                }
            }
        }
        .padding(20)
    }
}

// MARK: - SwiftUI Preview

#Preview {
    PreviewContainer()
}

// Preview wrapper for the main content
private struct PreviewContainer: View {
    var body: some View {
        Text("SAAQAnalyzer")
            .font(.title)
            .padding()
    }
}
