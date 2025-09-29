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
    @State private var duplicateYearToReplace: Int?
    @State private var pendingImportURLs: [URL] = []
    @State private var currentImportIndex = 0
    @State private var currentImportType: DataEntityType = .vehicle

    // Data package import handling state
    @State private var showingPackageAlert = false
    @State private var packageAlertMessage = ""


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
            // Left side: Mode selection and series creation (after app name)
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
            }

            // Right side: Import and export
            ToolbarItemGroup(placement: .primaryAction) {
                // Import menu
                Menu {
                    Label("CSV Files", systemImage: "doc.text")
                        .font(.caption)
                    Button("Import Vehicle CSV...") {
                        importVehicleData()
                    }
                    Button("Import Driver CSV...") {
                        importLicenseData()
                    }

                    Divider()

                    Label("Data Package", systemImage: "shippingbox")
                        .font(.caption)
                    Button("Import Data Package...") {
                        importDataPackage()
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
                ExportMenu(chartData: chartData)
                    .withPackageAlerts()

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
                    
                    SeriesQueryProgressView(
                        queryPattern: currentQueryPattern,
                        isIndexed: currentQueryIsIndexed,
                        dataType: "vehicle registrations"
                    )
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
        .alert("Year \(duplicateYearToReplace?.formatted(.number.grouping(.never)) ?? "Unknown") Already Exists", isPresented: $showingDuplicateYearAlert) {
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
            Text("Data for year \(duplicateYearToReplace?.formatted(.number.grouping(.never)) ?? "Unknown") has already been imported. Do you want to replace the existing data with the new import?")
        }
        .alert("Data Package Import", isPresented: $showingPackageAlert) {
            Button("OK") {
                showingPackageAlert = false
            }
        } message: {
            Text(packageAlertMessage)
        }
        .onAppear {
            // Check for Option key bypass or environment variable for testing
            let optionKeyPressed = NSEvent.modifierFlags.contains(.option)
            let envBypass = ProcessInfo.processInfo.environment["SAAQ_BYPASS_CACHE"] != nil

            if optionKeyPressed || envBypass {
                // Show alert about bypass mode and skip all initialization
                Task { @MainActor in
                    let bypassMethod = envBypass ? "Environment variable SAAQ_BYPASS_CACHE" : "Option key"
                    packageAlertMessage = "Cache loading bypassed via \(bypassMethod). First launch setup skipped. You can now import a data package immediately without waiting for cache rebuild."
                    showingPackageAlert = true
                }
                // Mark first launch complete to prevent geographic data import
                if AppSettings.shared.isFirstLaunch {
                    AppSettings.shared.markFirstLaunchComplete()
                    let bypassMethod = envBypass ? "Environment variable" : "Option key"
                    print("⚠️ \(bypassMethod) bypass: Skipping first launch setup")
                }
            } else if AppSettings.shared.isFirstLaunch {
                // Import bundled geographic data on first launch
                Task {
                    await importBundledGeographicDataOnFirstLaunch()
                }
            }
        }
    }

    /// Imports bundled geographic data on first launch
    private func importBundledGeographicDataOnFirstLaunch() async {
        do {
            print("🚀 First launch detected - importing bundled geographic data...")
            let importer = GeographicDataImporter(databaseManager: databaseManager)
            try await importer.importBundledGeographicData()

            // Mark first launch as complete
            await MainActor.run {
                AppSettings.shared.markFirstLaunchComplete()
            }

            print("✅ First launch setup completed")
        } catch {
            print("❌ Error importing bundled geographic data: \(error.localizedDescription)")
            // Don't mark first launch complete if import failed, so it will retry next time
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
            let queryPattern = generateQueryPattern(from: selectedFilters)

            // Analyze actual index usage deterministically
            let actualIndexUsage = await databaseManager.analyzeQueryIndexUsage(filters: selectedFilters)

            await MainActor.run {
                currentQueryPattern = queryPattern
                currentQueryIsIndexed = actualIndexUsage
                isAddingSeries = true
            }

            do {
                let series = try await databaseManager.queryData(
                    filters: selectedFilters
                )
                await MainActor.run {
                    // Assign unique color based on series index
                    series.color = Color.forSeriesIndex(chartData.count)
                    chartData.append(series)
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
                print("Error adding series: \(error)")
            }
        }
    }
    

    /// Generates a descriptive query pattern from filter configuration
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

    /// Imports license data from CSV file(s)
    private func importLicenseData() {
        Task { @MainActor in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.allowsMultipleSelection = true
            panel.message = "Select license CSV file(s) - multiple files will be imported sequentially"

            panel.begin { response in
                guard response == .OK, !panel.urls.isEmpty else { return }

                Task {
                    await self.importMultipleLicenseFiles(panel.urls)
                }
            }
        }
    }

    /// Imports multiple license files sequentially
    private func importMultipleLicenseFiles(_ urls: [URL]) async {
        pendingImportURLs = urls
        currentImportIndex = 0
        currentImportType = .license
        await processNextLicenseImport()
    }

    /// Processes the next license import in the queue
    private func processNextLicenseImport() async {
        guard currentImportIndex < pendingImportURLs.count else {
            // All imports completed
            print("🎉 Batch license import completed!")
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
            await processNextLicenseImport()
            return
        }

        print("📁 Importing license file \(currentImportIndex + 1)/\(pendingImportURLs.count): \(filename)")

        // Show progress immediately while checking for duplicates
        await MainActor.run {
            showingImportProgress = true
        }
        await progressManager.startImport()
        await progressManager.updateToReading()

        // Check if license year already exists
        if await databaseManager.isLicenseYearImported(year) {
            // Temporarily hide progress for alert
            await MainActor.run {
                showingImportProgress = false
                duplicateYearToReplace = year
                showingDuplicateYearAlert = true
            }
        } else {
            // Proceed with license import directly
            await performLicenseImport(url: url, year: year)
        }
    }

    /// Performs the actual license import
    private func performLicenseImport(url: URL, year: Int) async {
        do {
            let importer = CSVImporter(databaseManager: databaseManager, progressManager: progressManager)
            // Use the generic import method with license type
            let result = try await importer.importFile(at: url, year: year, dataType: .license, skipDuplicateCheck: true)
            print("✅ License import completed: \(result.successCount) records imported for year \(year)")
        } catch {
            await progressManager.reset()
            print("❌ Error importing license data: \(error)")
        }

        currentImportIndex += 1
        await processNextLicenseImport()
    }

    /// Imports multiple vehicle files sequentially
    private func importMultipleFiles(_ urls: [URL]) async {
        pendingImportURLs = urls
        currentImportIndex = 0
        currentImportType = .vehicle
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

                // Call the appropriate import method based on current import type
                if currentImportType == .license {
                    await performLicenseImport(url: url, year: year)
                } else {
                    await performImport(url: url, year: year)
                }
            } catch {
                print("❌ Error deleting data for year \(year): \(error)")
                await progressManager.reset()
                currentImportIndex += 1

                // Call the appropriate process method based on import type
                if currentImportType == .license {
                    await processNextLicenseImport()
                } else {
                    await processNextImport()
                }
            }
        } else {
            print("⏹️ Import cancelled by user for year \(year)")
            await progressManager.reset()
            currentImportIndex += 1

            // Call the appropriate process method based on import type
            if currentImportType == .license {
                await processNextLicenseImport()
            } else {
                await processNextImport()
            }
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
    
    // MARK: - Data Package Operations

    /// Imports a data package file
    private func importDataPackage() {
        Task { @MainActor in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.saaqPackage]
            panel.allowsMultipleSelection = false
            panel.message = "Select a SAAQ data package to import"
            panel.prompt = "Import Package"

            if panel.runModal() == .OK, let url = panel.url {
                // Validate package first
                let validationResult = await packageManager.validateDataPackage(at: url)

                if validationResult != .valid {
                    packageAlertMessage = validationResult.errorMessage
                    showingPackageAlert = true
                    return
                }

                // Confirm import with user
                let alert = NSAlert()
                alert.messageText = "Import Data Package?"
                alert.informativeText = "This will replace your current database and caches. This operation cannot be undone."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Import")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    do {
                        // Package manager has its own progress tracking
                        try await packageManager.importDataPackage(from: url)

                        // Refresh UI after import
                        await databaseManager.refreshFilterCache()

                        // Force full UI refresh after package import
                        await MainActor.run {
                            // Clear chart data to force refresh
                            chartData.removeAll()
                            selectedFilters = FilterConfiguration()
                        }

                        packageAlertMessage = "Data package imported successfully! All filters and data are now available."
                        showingPackageAlert = true
                    } catch {
                        packageAlertMessage = "Import failed: \(error.localizedDescription)"
                        showingPackageAlert = true
                    }
                }
            }
        }
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
        TabView {
            // General tab
            GeneralSettingsTab(databaseManager: databaseManager, defaultImportPath: $defaultImportPath)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            // Performance tab
            PerformanceSettingsTab(settings: settings)
                .tabItem {
                    Label("Performance", systemImage: "speedometer")
                }

            // Export tab
            ExportSettingsTab(settings: settings)
                .tabItem {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
        }
        .frame(width: 500, height: 790)
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    let databaseManager: DatabaseManager
    @Binding var defaultImportPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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

            // Database Summary Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Database Summary")
                    .font(.headline)

                DatabaseSummaryView(databaseManager: databaseManager)
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
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

                            LazyVGrid(columns: [
                                GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)
                            ], alignment: .leading, spacing: 2) {
                                Text("• \(cacheInfo.itemCounts.years) years")
                                Text("• \(cacheInfo.itemCounts.regions) regions")
                                Text("• \(cacheInfo.itemCounts.mrcs) MRCs")
                                Text("• \(cacheInfo.itemCounts.classifications) vehicle types")
                                Text("• \(cacheInfo.itemCounts.vehicleMakes) vehicle makes")
                                Text("• \(cacheInfo.itemCounts.vehicleModels) vehicle models")
                                Text("• \(cacheInfo.itemCounts.modelYears) model years")
                                Text("") // Empty cell to balance the grid
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
                    .help("Clear ALL cached filter options (vehicle AND license data - will reload everything from database)")

                    Spacer()
                }
            }

            Divider()

            // Development Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Development")
                    .font(.headline)

                Text("Advanced tools for development and exceptional circumstances.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Import Geographic Data File...") {
                    importGeographicDataFile()
                }
                .buttonStyle(.bordered)
                .help("Import a custom d001_min.txt file for development purposes")

                Button("Clear License Cache") {
                    FilterCache().clearLicenseCache()
                }
                .buttonStyle(.bordered)
                .help("Clear ONLY license data cache (preserves vehicle cache - use for testing license-specific fixes)")
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 32)
        .padding(.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private func importGeographicDataFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.message = "Select d001_min.txt file"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            Task {
                do {
                    let importer = GeographicDataImporter(databaseManager: databaseManager)
                    try await importer.importD001File(at: url)
                    print("Geographic data imported successfully from: \(url.lastPathComponent)")
                } catch {
                    print("Error importing geographic data: \(error)")
                }
            }
        }
    }
}

// MARK: - Performance Settings Tab

struct PerformanceSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // System Information
            VStack(alignment: .leading, spacing: 12) {
                Text("System Information")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
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
            }

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

            // Database Performance
            VStack(alignment: .leading, spacing: 12) {
                Text("Database Performance")
                    .font(.headline)

                Toggle(isOn: $settings.updateDatabaseStatisticsOnLaunch) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update Statistics on Launch")
                            .font(.subheadline)
                        Text("Runs ANALYZE command for optimal query performance (adds 2-5 minutes to startup)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                DatabaseStatisticsButton()
                    .padding(.leading, 20)
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

            Spacer()
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
}

// MARK: - Export Settings Tab

struct ExportSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Export Appearance
            VStack(alignment: .leading, spacing: 12) {
                Text("Export Appearance")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 12) {
                    // Background Luminosity
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Background Luminosity:")
                            Spacer()
                            Text(String(format: "%.0f%%", settings.exportBackgroundLuminosity * 100))
                                .fontWeight(.medium)
                        }

                        Slider(
                            value: $settings.exportBackgroundLuminosity,
                            in: 0.0...1.0,
                            step: 0.05
                        )

                        Text("0% = black, 100% = white")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Line Thickness
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Line Thickness:")
                            Spacer()
                            Text(String(format: "%.1f pt", settings.exportLineThickness))
                                .fontWeight(.medium)
                        }

                        Slider(
                            value: $settings.exportLineThickness,
                            in: 1.0...12.0,
                            step: 0.5
                        )

                        Text("Thickness of chart lines and borders")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Bold Axis Labels
                    Toggle(isOn: $settings.exportBoldAxisLabels) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bold Axis Labels")
                                .font(.subheadline)
                            Text("Use bold font weight for axis labels")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    // Include Legend
                    Toggle(isOn: $settings.exportIncludeLegend) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include Legend")
                                .font(.subheadline)
                            Text("Show legend when multiple series are present")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }

            Divider()

            // Export Quality
            VStack(alignment: .leading, spacing: 12) {
                Text("Export Quality")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Scale Factor:")
                        Spacer()
                        Text("\(settings.exportScaleFactor, specifier: "%.1f")x")
                            .fontWeight(.medium)
                    }

                    Slider(
                        value: $settings.exportScaleFactor,
                        in: 1.0...4.0,
                        step: 0.5
                    )

                    Text("Higher values produce sharper images at larger file sizes")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Quality examples
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Examples:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• 1.0x = Standard definition")
                            .font(.caption2)
                        Text("• 2.0x = High definition (recommended)")
                            .font(.caption2)
                        Text("• 3.0x = Ultra high definition")
                            .font(.caption2)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }

            Spacer()
        }
        .padding()
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Database Statistics Button

/// Button to manually update database statistics
struct DatabaseStatisticsButton: View {
    @EnvironmentObject var databaseManager: DatabaseManager
    @State private var isUpdating = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: updateStatistics) {
                HStack {
                    if isUpdating {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                    Text(isUpdating ? "Updating Statistics..." : "Update Statistics Now")
                }
                .foregroundColor(isUpdating ? .secondary : .accentColor)
            }
            .disabled(isUpdating)
            .buttonStyle(.borderless)

            Text("Manually update database statistics for optimal query performance")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .alert("Database Statistics", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func updateStatistics() {
        isUpdating = true
        Task {
            do {
                try await databaseManager.updateDatabaseStatistics()
                await MainActor.run {
                    isUpdating = false
                    alertMessage = "Database statistics updated successfully. Query performance should be improved."
                    isError = false
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    isUpdating = false
                    alertMessage = "Failed to update database statistics: \(error.localizedDescription)"
                    isError = true
                    showAlert = true
                }
            }
        }
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

// MARK: - Database Summary View

struct DatabaseSummaryView: View {
    let databaseManager: DatabaseManager
    @State private var cachedStats: CachedDatabaseStats?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading database statistics...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let stats = cachedStats {
                // Vehicle data section
                if stats.totalVehicleRecords > 0 {
                    HStack {
                        Text("Vehicle Records:")
                        Spacer()
                        Text("\(stats.totalVehicleRecords.formatted())")
                            .fontWeight(.medium)
                    }
                    HStack {
                        Text("Vehicle Years:")
                        Spacer()
                        Text(stats.vehicleYearRange)
                            .fontWeight(.medium)
                    }
                }

                // License data section
                if stats.totalLicenseRecords > 0 {
                    HStack {
                        Text("License Records:")
                        Spacer()
                        Text("\(stats.totalLicenseRecords.formatted())")
                            .fontWeight(.medium)
                    }
                    HStack {
                        Text("License Years:")
                        Spacer()
                        Text(stats.licenseYearRange)
                            .fontWeight(.medium)
                    }
                }

                // Combined totals
                HStack {
                    Text("Combined Total:")
                    Spacer()
                    Text("\(stats.totalRecords.formatted())")
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }



                HStack {
                    Text("Geographic Coverage:")
                    Spacer()
                    Text("\(stats.regions) regions, \(stats.municipalities) municipalities")
                        .fontWeight(.medium)
                }

                HStack {
                    Text("Database Size:")
                    Spacer()
                    Text(formatFileSize(stats.fileSizeBytes))
                        .fontWeight(.medium)
                }

                HStack {
                    Text("Last Updated:")
                    Spacer()
                    Text(stats.lastUpdated, style: .date)
                        .fontWeight(.medium)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Database statistics not available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Import data and refresh cache to see statistics")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .font(.caption)
        .onAppear {
            loadCachedStats()
        }
    }

    private func loadCachedStats() {
        // Try to get stats from cache first
        if let cached = FilterCache().getCachedDatabaseStats() {
            cachedStats = cached
        } else {
            // If no cached stats available, load them asynchronously
            Task {
                await MainActor.run {
                    isLoading = true
                }

                let stats = await databaseManager.getDatabaseStats()

                await MainActor.run {
                    cachedStats = stats
                    isLoading = false
                }
            }
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
