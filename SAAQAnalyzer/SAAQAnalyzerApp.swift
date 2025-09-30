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
    @StateObject private var packageManager = DataPackageManager.shared
    @State private var selectedFilters = FilterConfiguration()
    @State private var chartData: [FilteredDataSeries] = []
    @State private var selectedSeries: FilteredDataSeries?
    @State private var showingImportProgress = false
    @State private var isAddingSeries = false

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

    // Data package import handling state
    @State private var showingPackageAlert = false

    // Schema optimization state
    @State private var isMigratingSchema = false
    @State private var isRunningPerformanceTest = false
    @State private var showingOptimizationResults = false
    @State private var optimizationResults: String = ""
    @State private var packageAlertMessage = ""

    // SwiftUI file dialog states
    @State private var showingGeographicFileImporter = false
    @State private var showingVehicleFileImporter = false
    @State private var showingLicenseFileImporter = false
    @State private var showingPackageFileImporter = false
    @State private var showingPackageExporter = false
    @State private var showingPackageImporter = false
    @State private var showingDatabaseLocationPicker = false
    @State private var showingGeographicDataFileImporter = false

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
        Task { @MainActor in
            switch result {
            case .success(let urls):
                guard !urls.isEmpty else { return }
                await importMultipleFiles(urls)
            case .failure(let error):
                print("File selection error: \(error)")
            }
        }
    }

    /// Handle license file import result
    private func handleLicenseFileImport(_ result: Result<[URL], Error>) {
        Task { @MainActor in
            switch result {
            case .success(let urls):
                guard !urls.isEmpty else { return }
                await importMultipleLicenseFiles(urls)
            case .failure(let error):
                print("File selection error: \(error)")
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
                isPresented: $showingGeographicFileImporter,
                allowedContentTypes: [.plainText],
                allowsMultipleSelection: false
            ) { result in
                handleGeographicFileImport(result)
            }
            .fileImporter(
                isPresented: $showingVehicleFileImporter,
                allowedContentTypes: [.commaSeparatedText],
                allowsMultipleSelection: true
            ) { result in
                handleVehicleFileImport(result)
            }
            .fileImporter(
                isPresented: $showingLicenseFileImporter,
                allowedContentTypes: [.commaSeparatedText],
                allowsMultipleSelection: true
            ) { result in
                handleLicenseFileImport(result)
            }
            .fileImporter(
                isPresented: $showingPackageFileImporter,
                allowedContentTypes: [.saaqPackage],
                allowsMultipleSelection: false
            ) { result in
                handlePackageImport(result)
            }
            .fileImporter(
                isPresented: $showingPackageImporter,
                allowedContentTypes: [.saaqPackage],
                allowsMultipleSelection: false
            ) { result in
                handlePackageImport(result)
            }
            .fileImporter(
                isPresented: $showingGeographicDataFileImporter,
                allowedContentTypes: [.plainText],
                allowsMultipleSelection: false
            ) { result in
                handleGeographicDataFileImport(result)
            }
            .fileExporter(
                isPresented: $showingPackageExporter,
                document: DataPackageDocument(),
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
                    showingPackageFileImporter = true
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

            // Export button
            Menu {
                Button("Export Chart as PNG...") {
                    // This would be handled by ChartView's export functionality
                    print("Export chart - use ChartView export buttons")
                }
                .disabled(chartData.isEmpty)

                Button("Export Data as CSV...") {
                    // This would be handled by DataInspector's export functionality
                    print("Export data - use DataInspector export buttons")
                }
                .disabled(chartData.isEmpty)

                Divider()

                Button("Export Data Package...") {
                    showingPackageExporter = true
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }

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
                let newSeries = try await databaseManager.queryVehicleData(filters: selectedFilters)

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
        showingVehicleFileImporter = true
    }

    private func importLicenseFiles() {
        showingLicenseFileImporter = true
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
        pendingImportURLs = urls
        currentImportIndex = 0
        await processNextVehicleImport()
    }

    private func importMultipleLicenseFiles(_ urls: [URL]) async {
        pendingImportURLs = urls
        currentImportIndex = 0
        await processNextLicenseImport()
    }

    private func processNextVehicleImport() async {
        guard currentImportIndex < pendingImportURLs.count else {
            // All files processed
            await progressManager.reset()
            currentImportIndex = 0
            pendingImportURLs = []
            return
        }

        let url = pendingImportURLs[currentImportIndex]
        let filename = url.lastPathComponent
        let yearString = String(filename.prefix(4))

        guard let year = Int(yearString) else {
            print("❌ Could not extract year from filename: \(filename)")
            currentImportIndex += 1
            await processNextVehicleImport()
            return
        }

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
            await progressManager.reset()
            currentImportIndex = 0
            pendingImportURLs = []
            return
        }

        let url = pendingImportURLs[currentImportIndex]
        let filename = url.lastPathComponent
        let yearString = String(filename.prefix(4))

        guard let year = Int(yearString) else {
            print("❌ Could not extract year from filename: \(filename)")
            currentImportIndex += 1
            await processNextLicenseImport()
            return
        }

        await performLicenseImport(url: url, year: year)
    }

    private func performVehicleImport(url: URL, year: Int) async {
        do {
            let importer = CSVImporter(databaseManager: databaseManager, progressManager: progressManager)
            let result = try await importer.importFile(at: url, year: year, dataType: .vehicle, skipDuplicateCheck: false)
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
            let result = try await importer.importFile(at: url, year: year, dataType: .license, skipDuplicateCheck: true)
            print("✅ License import completed: \(result.successCount) records imported for year \(year)")
        } catch {
            await progressManager.reset()
            print("❌ Error importing license data: \(error)")
        }

        currentImportIndex += 1
        await processNextLicenseImport()
    }

    private func handlePackageExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                do {
                    let options = DataPackageExportOptions.complete
                    try await packageManager.exportDataPackage(to: url, options: options)
                    packageAlertMessage = "Data package exported successfully to: \(url.lastPathComponent)"
                    showingPackageAlert = true
                } catch {
                    packageAlertMessage = "Export failed: \(error.localizedDescription)"
                    showingPackageAlert = true
                }
            }
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

    init() {}

    init(configuration: ReadConfiguration) throws {}

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Return empty file wrapper - actual export is handled in the result handler
        return FileWrapper(regularFileWithContents: Data())
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

                // Index status information
                if let indexed = isIndexed {
                    HStack(spacing: 4) {
                        Image(systemName: indexed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(indexed ? .green : .orange)
                        Text(indexed ? "Using optimized index" : "Limited indexing - may take longer")
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
            return "Non-Indexed Query in Progress"
        }
        return "Querying Database"
    }

    private var subtitleText: String {
        if let indexed = isIndexed {
            if indexed {
                return "Analyzing \(dataType) with optimized indexes..."
            } else {
                return "Query requires table scan due to limited indexing - this may take several minutes..."
            }
        }
        return "Analyzing \(dataType) with your filter criteria..."
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @StateObject private var databaseManager = DatabaseManager.shared
    @State private var cachedStats: CachedDatabaseStats?
    @State private var isLoading = true

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
        }
        .frame(width: 400, height: 300)
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

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
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
