import SwiftUI

/// Filter panel for selecting data criteria
struct FilterPanel: View {
    @Binding var configuration: FilterConfiguration
    @EnvironmentObject var databaseManager: DatabaseManager
    
    // Available options loaded from database (shared)
    @State private var availableYears: [Int] = []
    @State private var availableRegions: [String] = []
    @State private var availableMRCs: [String] = []
    @State private var availableMunicipalities: [String] = []

    // Vehicle-specific options
    @State private var availableClassifications: [String] = []
    @State private var availableVehicleMakes: [String] = []
    @State private var availableVehicleModels: [String] = []
    @State private var availableVehicleColors: [String] = []
    @State private var availableModelYears: [Int] = []

    // License-specific options
    @State private var availableLicenseTypes: [String] = []
    @State private var availableAgeGroups: [String] = []
    @State private var availableGenders: [String] = []
    @State private var availableExperienceLevels: [String] = []
    @State private var availableLicenseClasses: [String] = []

    // Municipality code-to-name mapping for UI display
    @State private var municipalityCodeToName: [String: String] = [:]
    
    // Loading state
    @State private var isLoadingData = true
    @State private var hasInitiallyLoaded = false
    @State private var isLoadingLicenseCharacteristics = false
    
    // Expansion states for sections
    @State private var yearSectionExpanded = true
    @State private var geographySectionExpanded = true
    @State private var vehicleSectionExpanded = true
    @State private var ageSectionExpanded = false
    @State private var licenseSectionExpanded = true
    @State private var metricSectionExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Filters", systemImage: "line.horizontal.3.decrease.circle")
                    .font(.headline)
                
                Spacer()
                
                Button("Clear All") {
                    clearAllFilters()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Filter sections
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isLoadingData {
                        // Loading indicator
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading filter options...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .padding()
                    }
                    // Years section
                    DisclosureGroup(isExpanded: $yearSectionExpanded) {
                        YearFilterSection(
                            availableYears: availableYears,
                            selectedYears: Binding(
                                get: { configuration.years },
                                set: { newYears in
                                    configuration.years = newYears
                                }
                            )
                        )
                    } label: {
                        Label("Years", systemImage: "calendar")
                            .font(.subheadline)
                    }
                    
                    Divider()
                    
                    // Geographic hierarchy section
                    DisclosureGroup(isExpanded: $geographySectionExpanded) {
                        SimpleGeographicFilterSection(
                            availableRegions: availableRegions,
                            availableMRCs: availableMRCs,
                            availableMunicipalities: availableMunicipalities,
                            municipalityCodeToName: municipalityCodeToName,
                            configuration: $configuration
                        )
                    } label: {
                        Label("Geographic Location", systemImage: "map")
                            .font(.subheadline)
                    }
                    
                    Divider()

                    // Data type specific sections
                    if configuration.dataEntityType == .vehicle {
                        // Vehicle characteristics section
                        DisclosureGroup(isExpanded: $vehicleSectionExpanded) {
                            VehicleFilterSection(
                                selectedClassifications: $configuration.vehicleClassifications,
                                selectedVehicleMakes: $configuration.vehicleMakes,
                                selectedVehicleModels: $configuration.vehicleModels,
                                selectedVehicleColors: $configuration.vehicleColors,
                                selectedModelYears: $configuration.modelYears,
                                selectedFuelTypes: $configuration.fuelTypes,
                                availableYears: availableYears,
                                availableClassifications: availableClassifications,
                                availableVehicleMakes: availableVehicleMakes,
                                availableVehicleModels: availableVehicleModels,
                                availableVehicleColors: availableVehicleColors,
                                availableModelYears: availableModelYears
                            )
                        } label: {
                            Label("Vehicle Characteristics", systemImage: "car")
                                .font(.subheadline)
                        }

                        Divider()

                        // Vehicle age ranges section
                        DisclosureGroup(isExpanded: $ageSectionExpanded) {
                            AgeRangeFilterSection(ageRanges: $configuration.ageRanges)
                        } label: {
                            Label("Vehicle Age", systemImage: "clock")
                                .font(.subheadline)
                        }
                    } else {
                        // License characteristics section
                        DisclosureGroup(isExpanded: $licenseSectionExpanded) {
                            if isLoadingLicenseCharacteristics {
                                // Loading indicator for license characteristics
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Loading license characteristics...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 100)
                                .padding()
                            } else {
                                LicenseFilterSection(
                                    selectedLicenseTypes: $configuration.licenseTypes,
                                    selectedAgeGroups: $configuration.ageGroups,
                                    selectedGenders: $configuration.genders,
                                    selectedExperienceLevels: $configuration.experienceLevels,
                                    selectedLicenseClasses: $configuration.licenseClasses,
                                    availableLicenseTypes: availableLicenseTypes,
                                    availableAgeGroups: availableAgeGroups,
                                    availableGenders: availableGenders,
                                    availableExperienceLevels: availableExperienceLevels,
                                    availableLicenseClasses: availableLicenseClasses
                                )
                            }
                        } label: {
                            Label("License Characteristics", systemImage: "person.crop.circle")
                                .font(.subheadline)
                        }
                    }

                    Divider()

                    // Metric configuration section
                    DisclosureGroup(isExpanded: $metricSectionExpanded) {
                        MetricConfigurationSection(
                            metricType: $configuration.metricType,
                            metricField: $configuration.metricField,
                            percentageBaseFilters: $configuration.percentageBaseFilters,
                            currentFilters: configuration
                        )
                    } label: {
                        Label("Y-Axis Metric", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.subheadline)
                    }
                }
                .padding()
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            if !hasInitiallyLoaded {
                // Check if Option key is held down or environment variable is set to bypass cache loading
                let optionKeyPressed = NSEvent.modifierFlags.contains(.option)
                let envBypass = ProcessInfo.processInfo.environment["SAAQ_BYPASS_CACHE"] != nil

                if optionKeyPressed || envBypass {
                    if envBypass {
                        print("⚠️ Environment variable SAAQ_BYPASS_CACHE detected - bypassing cache loading")
                    } else {
                        print("⚠️ Option key detected - bypassing cache loading for quick startup")
                    }
                    print("📦 You can now import a data package without waiting for cache rebuild")
                    hasInitiallyLoaded = true
                    isLoadingData = false
                    // Set minimal data to prevent UI issues
                    availableYears = []
                    availableRegions = []
                    availableMRCs = []
                    availableMunicipalities = []
                } else {
                    loadAvailableOptions()
                }
            }
        }
        .onReceive(databaseManager.$dataVersion) { _ in
            // Only reload if we might have new years or geographic data
            // Skip reload if we're just replacing existing year data
            if hasInitiallyLoaded {
                Task {
                    // If we have no data (likely from bypass), do a full reload
                    if availableYears.isEmpty && availableRegions.isEmpty {
                        print("🔄 Full reload needed after cache bypass and import")
                        await loadAvailableOptions()
                    } else {
                        await refreshIfNeeded()
                    }
                }
            }
        }
        .onChange(of: configuration.dataEntityType) { _, _ in
            // Immediately clear geographic data to prevent showing wrong mode's data
            if hasInitiallyLoaded {
                availableRegions = []
                availableMRCs = []
                availableMunicipalities = [] // Clear municipalities when switching modes
            }

            // Reload data type specific options when switching between vehicle and license
            Task {
                await loadDataTypeSpecificOptions()
                // Clear filter selections that are no longer valid for the new data type
                await cleanupInvalidFilterSelections()
            }
        }
        .onChange(of: databaseManager.dataVersion) { _, _ in
            print("🔄 Database version changed, refreshing municipality mapping")
            refreshMunicipalityMapping()
        }
    }
    
    /// Loads available filter options from database
    private func loadAvailableOptions() {
        Task {
            // Only show loading if we don't already have cached data
            let cacheInfo = databaseManager.filterCacheInfo
            let shouldShowLoading = !cacheInfo.hasCache || availableYears.isEmpty

            if shouldShowLoading {
                isLoadingData = true
            }

            // Check if we need to populate cache first
            print("🔍 Filter cache status: hasCache=\(cacheInfo.hasCache), years=\(cacheInfo.itemCounts.years)")
            if !cacheInfo.hasCache {
                print("💾 No filter cache found, populating cache before loading options...")
                await databaseManager.refreshFilterCache()
            } else {
                print("✅ Using existing filter cache")
            }
            
            // Load shared options from database/cache in parallel
            async let years = databaseManager.getAvailableYears(for: configuration.dataEntityType)
            async let regions = databaseManager.getAvailableRegions(for: configuration.dataEntityType)
            async let mrcs = databaseManager.getAvailableMRCs(for: configuration.dataEntityType)
            async let municipalities = databaseManager.getAvailableMunicipalities(for: configuration.dataEntityType)
            async let municipalityMapping = databaseManager.getMunicipalityCodeToNameMapping()

            // Wait for all to complete
            (availableYears, availableRegions, availableMRCs, availableMunicipalities, municipalityCodeToName) =
                await (years, regions, mrcs, municipalities, municipalityMapping)

            // Load data type specific options
            await loadDataTypeSpecificOptions()

            print("📊 Loaded filter options: \(availableYears.count) years, \(availableRegions.count) regions, \(availableMRCs.count) MRCs")
            
            isLoadingData = false
            hasInitiallyLoaded = true
        }
    }

    /// Loads data type specific filter options
    private func loadDataTypeSpecificOptions() async {
        // Load new data for the current mode
        if hasInitiallyLoaded {
            availableYears = await databaseManager.getAvailableYears(for: configuration.dataEntityType)
            availableRegions = await databaseManager.getAvailableRegions(for: configuration.dataEntityType)
            availableMRCs = await databaseManager.getAvailableMRCs(for: configuration.dataEntityType)
            availableMunicipalities = await databaseManager.getAvailableMunicipalities(for: configuration.dataEntityType)
        }

        switch configuration.dataEntityType {
        case .vehicle:
            // Load vehicle-specific options in parallel for better performance
            async let classifications = databaseManager.getAvailableClassifications()
            async let vehicleMakes = databaseManager.getAvailableVehicleMakes()
            async let vehicleModels = databaseManager.getAvailableVehicleModels()
            async let vehicleColors = databaseManager.getAvailableVehicleColors()
            async let modelYears = databaseManager.getAvailableModelYears()

            // Wait for all to complete
            (availableClassifications, availableVehicleMakes, availableVehicleModels,
             availableVehicleColors, availableModelYears) =
                await (classifications, vehicleMakes, vehicleModels, vehicleColors, modelYears)

            // Clear license options
            availableLicenseTypes = []
            availableAgeGroups = []
            availableGenders = []
            availableExperienceLevels = []
            availableLicenseClasses = []

        case .license:
            // Set loading state for license characteristics
            isLoadingLicenseCharacteristics = true

            // Load license-specific options in parallel for better performance
            async let licenseTypes = databaseManager.getAvailableLicenseTypes()
            async let ageGroups = databaseManager.getAvailableAgeGroups()
            async let genders = databaseManager.getAvailableGenders()
            async let experienceLevels = databaseManager.getAvailableExperienceLevels()
            async let licenseClasses = databaseManager.getAvailableLicenseClasses()

            // Wait for all to complete
            (availableLicenseTypes, availableAgeGroups, availableGenders,
             availableExperienceLevels, availableLicenseClasses) =
                await (licenseTypes, ageGroups, genders, experienceLevels, licenseClasses)

            // Clear loading state
            isLoadingLicenseCharacteristics = false

            // Clear vehicle options
            availableClassifications = []
            availableVehicleMakes = []
            availableVehicleModels = []
            availableVehicleColors = []
            availableModelYears = []
        }
    }
    
    /// Smart refresh that only updates if there are actual changes
    private func refreshIfNeeded() async {
        // Check if we already have data loaded and if cache is valid
        let cacheInfo = databaseManager.filterCacheInfo
        if !availableYears.isEmpty && cacheInfo.hasCache {
            print("📊 Cache is valid and data already loaded, skipping refresh")
            return
        }

        // Check if years have changed (most common update)
        let newYears = await databaseManager.getAvailableYears(for: configuration.dataEntityType)

        // Only reload everything if we have new years
        // (replacing existing year data doesn't add new years)
        if Set(newYears) != Set(availableYears) {
            print("📊 New years detected, refreshing filter options...")
            availableYears = newYears

            // Also refresh classifications in case new year has different vehicle types
            availableClassifications = await databaseManager.getAvailableClassifications()
        }
        
        // Geographic data rarely changes after initial load
        // Only check if we have no regions (indicating new geographic import)
        if availableRegions.isEmpty {
            availableRegions = await databaseManager.getAvailableRegions(for: configuration.dataEntityType)
            availableMRCs = await databaseManager.getAvailableMRCs(for: configuration.dataEntityType)
            availableMunicipalities = await databaseManager.getAvailableMunicipalities(for: configuration.dataEntityType)
            municipalityCodeToName = await databaseManager.getMunicipalityCodeToNameMapping()
        }
    }
    
    /// Clears all filter selections
    private func clearAllFilters() {
        configuration = FilterConfiguration()
    }

    /// Removes filter selections that are no longer valid for the current data type
    private func cleanupInvalidFilterSelections() async {
        let currentRegions = await databaseManager.getAvailableRegions(for: configuration.dataEntityType)
        let currentMRCs = await databaseManager.getAvailableMRCs(for: configuration.dataEntityType)

        // Ensure UI updates happen on main thread
        await MainActor.run {
            // Remove region selections that don't exist in the current data type
            configuration.regions = configuration.regions.filter { currentRegions.contains($0) }

            // Remove MRC selections that don't exist in the current data type
            configuration.mrcs = configuration.mrcs.filter { currentMRCs.contains($0) }

            // Clear data-type-specific filters when switching modes
            switch configuration.dataEntityType {
            case .vehicle:
                // Clear all license-specific filters when switching to vehicle mode
                configuration.licenseTypes.removeAll()
                configuration.ageGroups.removeAll()
                configuration.genders.removeAll()
                configuration.experienceLevels.removeAll()
                configuration.licenseClasses.removeAll()

            case .license:
                // Clear all vehicle-specific filters when switching to license mode
                configuration.vehicleClassifications.removeAll()
                configuration.vehicleMakes.removeAll()
                configuration.vehicleModels.removeAll()
                configuration.vehicleColors.removeAll()
                configuration.modelYears.removeAll()
                configuration.fuelTypes.removeAll()
            }

            print("🧹 Cleaned up invalid filter selections for \(configuration.dataEntityType)")
            print("   Remaining regions: \(configuration.regions.count)")
            print("   Remaining MRCs: \(configuration.mrcs.count)")
        }
    }

    /// Refresh municipality mapping after data package import
    func refreshMunicipalityMapping() {
        Task {
            let newMapping = await databaseManager.getMunicipalityCodeToNameMapping()
            await MainActor.run {
                municipalityCodeToName = newMapping
                print("🗺️ Municipality mapping refreshed: \(newMapping.count) entries")
            }
        }
    }
}

// MARK: - Year Filter Section

struct YearFilterSection: View {
    let availableYears: [Int]
    @Binding var selectedYears: Set<Int>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Quick select buttons
            HStack {
                Button("All") {
                    selectedYears = Set(availableYears)
                }
                .buttonStyle(.bordered)
                
                Button("Last 5") {
                    let lastFive = availableYears.suffix(5)
                    selectedYears = Set(lastFive)
                }
                .buttonStyle(.bordered)
                
                Button("Clear") {
                    selectedYears.removeAll()
                }
                .buttonStyle(.bordered)
            }
            
            // Year checkboxes in a grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 8) {
                ForEach(availableYears, id: \.self) { year in
                    Toggle(String(year), isOn: Binding(
                        get: { selectedYears.contains(year) },
                        set: { isSelected in
                            if isSelected {
                                selectedYears.insert(year)
                            } else {
                                selectedYears.remove(year)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
        }
    }
}

// MARK: - Geographic Filter Section

struct SimpleGeographicFilterSection: View {
    let availableRegions: [String]
    let availableMRCs: [String]
    let availableMunicipalities: [String]
    let municipalityCodeToName: [String: String]
    @Binding var configuration: FilterConfiguration
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Regions section
            if !availableRegions.isEmpty {
                Text("Administrative Regions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                SearchableFilterList(
                    items: availableRegions,
                    selectedItems: $configuration.regions,
                    searchPrompt: "Search regions..."
                )
            }
            
            // MRCs section  
            if !availableMRCs.isEmpty {
                Divider()
                
                Text("MRCs")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                SearchableFilterList(
                    items: availableMRCs,
                    selectedItems: $configuration.mrcs,
                    searchPrompt: "Search MRCs..."
                )
            }
            
            // Municipalities section
            if !availableMunicipalities.isEmpty {
                Divider()

                Text("Municipalities")
                    .font(.caption)
                    .foregroundColor(.secondary)

                MunicipalityFilterList(
                    availableCodes: availableMunicipalities,
                    codeToNameMapping: municipalityCodeToName,
                    selectedCodes: $configuration.municipalities
                )
            }
            
            // Summary of selections
            if !configuration.regions.isEmpty || !configuration.mrcs.isEmpty || !configuration.municipalities.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected locations:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !configuration.regions.isEmpty {
                        HStack {
                            Image(systemName: "flag.fill")
                                .foregroundColor(.blue)
                            Text("\(configuration.regions.count) region(s)")
                                .font(.caption)
                        }
                    }
                    
                    if !configuration.mrcs.isEmpty {
                        HStack {
                            Image(systemName: "building.2.fill")
                                .foregroundColor(.green)
                            Text("\(configuration.mrcs.count) MRC(s)")
                                .font(.caption)
                        }
                    }
                    
                    if !configuration.municipalities.isEmpty {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundColor(.orange)
                            Text("\(configuration.municipalities.count) municipalit(y/ies)")
                                .font(.caption)
                        }
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }
}

// Note: HierarchicalRegionRow removed - now using SimpleGeographicFilterSection

// MARK: - Vehicle Filter Section

struct VehicleFilterSection: View {
    @Binding var selectedClassifications: Set<String>
    @Binding var selectedVehicleMakes: Set<String>
    @Binding var selectedVehicleModels: Set<String>
    @Binding var selectedVehicleColors: Set<String>
    @Binding var selectedModelYears: Set<Int>
    @Binding var selectedFuelTypes: Set<String>
    let availableYears: [Int]
    let availableClassifications: [String]
    let availableVehicleMakes: [String]
    let availableVehicleModels: [String]
    let availableVehicleColors: [String]
    let availableModelYears: [Int]
    
    // Check if any year from 2017+ is selected (for fuel type filter)
    private var hasFuelTypeYears: Bool {
        availableYears.contains { $0 >= 2017 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Vehicle classifications (use actual database values)
            if !availableClassifications.isEmpty {
                Text("Vehicle Type")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VehicleClassificationFilterList(
                    availableClassifications: availableClassifications,
                    selectedClassifications: $selectedClassifications
                )
            }
            
            // Vehicle Makes
            if !availableVehicleMakes.isEmpty {
                Divider()

                Text("Vehicle Make")
                    .font(.caption)
                    .foregroundColor(.secondary)

                SearchableFilterList(
                    items: availableVehicleMakes,
                    selectedItems: $selectedVehicleMakes,
                    searchPrompt: "Search vehicle makes..."
                )
            }

            // Vehicle Models
            if !availableVehicleModels.isEmpty {
                Divider()

                Text("Vehicle Model")
                    .font(.caption)
                    .foregroundColor(.secondary)

                SearchableFilterList(
                    items: availableVehicleModels,
                    selectedItems: $selectedVehicleModels,
                    searchPrompt: "Search vehicle models..."
                )
            }

            // Vehicle Colors
            if !availableVehicleColors.isEmpty {
                Divider()

                Text("Vehicle Color")
                    .font(.caption)
                    .foregroundColor(.secondary)

                SearchableFilterList(
                    items: availableVehicleColors,
                    selectedItems: $selectedVehicleColors,
                    searchPrompt: "Search vehicle colors..."
                )
            }

            // Model Years
            if !availableModelYears.isEmpty {
                Divider()

                Text("Model Year")
                    .font(.caption)
                    .foregroundColor(.secondary)

                SearchableFilterList(
                    items: availableModelYears.map { String($0) },
                    selectedItems: Binding(
                        get: {
                            Set(selectedModelYears.map { String($0) })
                        },
                        set: { stringSet in
                            selectedModelYears = Set(stringSet.compactMap { Int($0) })
                        }
                    ),
                    searchPrompt: "Search model years..."
                )
            }

            // Fuel types (only if 2017+ data is available)
            if hasFuelTypeYears {
                Divider()

                Text("Fuel Type (2017+)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                SearchableFilterList(
                    items: FuelType.allCases.map { $0.description },
                    selectedItems: Binding(
                        get: {
                            Set(FuelType.allCases.compactMap { fuelType in
                                selectedFuelTypes.contains(fuelType.rawValue) ? fuelType.description : nil
                            })
                        },
                        set: { descriptions in
                            selectedFuelTypes = Set(FuelType.allCases.compactMap { fuelType in
                                descriptions.contains(fuelType.description) ? fuelType.rawValue : nil
                            })
                        }
                    ),
                    searchPrompt: "Search fuel types..."
                )
            }
        }
    }
}

// MARK: - Age Range Filter Section

struct AgeRangeFilterSection: View {
    @Binding var ageRanges: [FilterConfiguration.AgeRange]
    @State private var showAddRange = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Predefined age ranges
            Text("Quick Select")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Button("0-5 years") {
                    addAgeRange(min: 0, max: 5)
                }
                .buttonStyle(.bordered)
                
                Button("6-10 years") {
                    addAgeRange(min: 6, max: 10)
                }
                .buttonStyle(.bordered)
                
                Button("11-15 years") {
                    addAgeRange(min: 11, max: 15)
                }
                .buttonStyle(.bordered)
                
                Button("16+ years") {
                    addAgeRange(min: 16, max: nil)
                }
                .buttonStyle(.bordered)
            }
            
            // Custom ranges
            if !ageRanges.isEmpty {
                Divider()
                
                Text("Selected Ranges")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(Array(ageRanges.enumerated()), id: \.offset) { index, range in
                    HStack {
                        if let max = range.maxAge {
                            Text("\(range.minAge)-\(max) years")
                        } else {
                            Text("\(range.minAge)+ years")
                        }
                        
                        Spacer()
                        
                        Button {
                            ageRanges.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
            
            // Add custom range button
            Button {
                showAddRange.toggle()
            } label: {
                Label("Add Custom Range", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showAddRange) {
                CustomAgeRangeView(ageRanges: $ageRanges)
            }
        }
    }
    
    private func addAgeRange(min: Int, max: Int?) {
        let newRange = FilterConfiguration.AgeRange(minAge: min, maxAge: max)
        if !ageRanges.contains(where: { $0.minAge == min && $0.maxAge == max }) {
            ageRanges.append(newRange)
        }
    }
}

// MARK: - Custom Age Range View

struct CustomAgeRangeView: View {
    @Binding var ageRanges: [FilterConfiguration.AgeRange]
    @State private var minAge = ""
    @State private var maxAge = ""
    @State private var hasMaxAge = true
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Add Custom Age Range")
                .font(.headline)
            
            HStack {
                Text("Minimum Age:")
                TextField("0", text: $minAge)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
            }
            
            Toggle("Has maximum age", isOn: $hasMaxAge)
            
            if hasMaxAge {
                HStack {
                    Text("Maximum Age:")
                    TextField("99", text: $maxAge)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Add") {
                    addRange()
                }
                .buttonStyle(.borderedProminent)
                .disabled(minAge.isEmpty || (hasMaxAge && maxAge.isEmpty))
            }
        }
        .padding()
        .frame(width: 250)
    }
    
    private func addRange() {
        guard let min = Int(minAge) else { return }
        let max = hasMaxAge ? Int(maxAge) : nil
        
        let newRange = FilterConfiguration.AgeRange(minAge: min, maxAge: max)
        if !ageRanges.contains(where: { $0.minAge == min && $0.maxAge == max }) {
            ageRanges.append(newRange)
        }
        
        dismiss()
    }
}

// MARK: - Searchable Filter List

struct SearchableFilterList: View {
    let items: [String]
    @Binding var selectedItems: Set<String>
    let searchPrompt: String
    
    @State private var searchText = ""
    @State private var isExpanded = false
    
    private var filteredItems: [String] {
        if searchText.isEmpty {
            return items
        }
        return items.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var displayedItems: [String] {
        let sorted = filteredItems.sorted()
        return isExpanded ? sorted : Array(sorted.prefix(5))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Search field
            if items.count > 8 {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    TextField(searchPrompt, text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Quick action buttons
            HStack {
                Button("All") {
                    selectedItems = Set(filteredItems)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                
                Button("Clear") {
                    selectedItems.removeAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                
                Spacer()
                
                if items.count > 5 && searchText.isEmpty {
                    Button(isExpanded ? "Show Less" : "Show All (\(items.count))") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                }
            }
            
            // Filter items
            VStack(alignment: .leading, spacing: 2) {
                ForEach(displayedItems, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { selectedItems.contains(item) },
                            set: { isSelected in
                                if isSelected {
                                    selectedItems.insert(item)
                                } else {
                                    selectedItems.remove(item)
                                }
                            }
                        )) {
                            EmptyView()
                        }
                        .toggleStyle(.checkbox)
                        .controlSize(.mini)
                        
                        Text(item)
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 1)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: displayedItems.count)
            
            // Search results summary
            if !searchText.isEmpty && filteredItems.count != items.count {
                Text("Showing \(filteredItems.count) of \(items.count) items")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Vehicle Classification Filter List

struct VehicleClassificationFilterList: View {
    let availableClassifications: [String]
    @Binding var selectedClassifications: Set<String>
    
    @State private var searchText = ""
    @State private var isExpanded = false
    
    private var filteredItems: [String] {
        if searchText.isEmpty {
            return availableClassifications
        }
        return availableClassifications.filter { classification in
            let displayName = getDisplayName(for: classification)
            return displayName.localizedCaseInsensitiveContains(searchText) || 
                   classification.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var displayedItems: [String] {
        let sorted = filteredItems.sorted()
        return isExpanded ? sorted : Array(sorted.prefix(6))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Search field
            if availableClassifications.count > 10 {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    TextField("Search vehicle types...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Quick action buttons
            HStack {
                Button("All") {
                    selectedClassifications = Set(filteredItems)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                
                Button("Clear") {
                    selectedClassifications.removeAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                
                Spacer()
                
                if availableClassifications.count > 6 && searchText.isEmpty {
                    Button(isExpanded ? "Show Less" : "Show All (\(availableClassifications.count))") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                }
            }
            
            // Filter items
            VStack(alignment: .leading, spacing: 2) {
                ForEach(displayedItems, id: \.self) { classification in
                    HStack(alignment: .top, spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { selectedClassifications.contains(classification) },
                            set: { isSelected in
                                if isSelected {
                                    selectedClassifications.insert(classification)
                                } else {
                                    selectedClassifications.remove(classification)
                                }
                            }
                        )) {
                            EmptyView()
                        }
                        .toggleStyle(.checkbox)
                        .controlSize(.mini)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(getDisplayName(for: classification))
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 1)
                    .help(getDescription(for: classification))  // Tooltip with description
                }
            }
            .animation(.easeInOut(duration: 0.2), value: displayedItems.count)
            
            // Search results summary
            if !searchText.isEmpty && filteredItems.count != availableClassifications.count {
                Text("Showing \(filteredItems.count) of \(availableClassifications.count) vehicle types")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
    
    // Helper methods for vehicle classification display
    private func getDisplayName(for classification: String) -> String {
        if let vehicleClass = VehicleClassification(rawValue: classification) {
            return "\(classification) - \(vehicleClass.description)"
        }
        return classification
    }
    
    private func getDescription(for classification: String) -> String {
        if let vehicleClass = VehicleClassification(rawValue: classification) {
            return vehicleClass.description
        }
        return "Unknown classification: \(classification)"
    }
}

// MARK: - Municipality Filter List

/// Specialized filter list for municipalities that displays names but stores codes
struct MunicipalityFilterList: View {
    let availableCodes: [String]
    let codeToNameMapping: [String: String]
    @Binding var selectedCodes: Set<String>

    @State private var searchText = ""
    @State private var isExpanded = false

    // Create display items (name -> code mapping for UI)
    private var displayItems: [(name: String, code: String)] {
        availableCodes.compactMap { code in
            if let name = codeToNameMapping[code] {
                return (name: name, code: code)
            } else {
                // Fallback: if no name mapping, use code as name
                return (name: code, code: code)
            }
        }.sorted { $0.name < $1.name }
    }

    private var filteredItems: [(name: String, code: String)] {
        if searchText.isEmpty {
            return displayItems
        }
        return displayItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var displayedItems: [(name: String, code: String)] {
        return isExpanded ? filteredItems : Array(filteredItems.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Search field
            if displayItems.count > 8 {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    TextField("Search municipalities...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            }

            // Quick action buttons
            HStack {
                Button("All") {
                    selectedCodes = Set(filteredItems.map { $0.code })
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("Clear") {
                    selectedCodes.removeAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Spacer()

                if displayItems.count > 5 && searchText.isEmpty {
                    Button(isExpanded ? "Show Less" : "Show All (\(displayItems.count))") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                }
            }

            // Filter items (display names, store codes)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(displayedItems, id: \.code) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { selectedCodes.contains(item.code) },
                            set: { isSelected in
                                if isSelected {
                                    selectedCodes.insert(item.code)
                                } else {
                                    selectedCodes.remove(item.code)
                                }
                            }
                        )) {
                            EmptyView()
                        }
                        .toggleStyle(.checkbox)
                        .controlSize(.mini)

                        Text(item.name)
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 1)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: displayedItems.count)

            // Search results summary
            if !searchText.isEmpty && filteredItems.count != displayItems.count {
                Text("Showing \(filteredItems.count) of \(displayItems.count) municipalities")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}


// MARK: - Metric Configuration Section

struct MetricConfigurationSection: View {
    @Binding var metricType: ChartMetricType
    @Binding var metricField: ChartMetricField
    @Binding var percentageBaseFilters: PercentageBaseFilters?
    let currentFilters: FilterConfiguration

    @State private var selectedCategoryToRemove: FilterCategory?

    enum FilterCategory: String, CaseIterable {
        case regions = "Admin Region"
        case vehicleClassifications = "Vehicle Type"
        case fuelTypes = "Fuel Type"
        case vehicleMakes = "Vehicle Make"
        case vehicleModels = "Vehicle Model"
        case modelYears = "Model Year"
        case mrcs = "MRC"
        case municipalities = "Municipality"
        case ageRanges = "Vehicle Age"
    }

    private var availableCategories: [FilterCategory] {
        var categories: [FilterCategory] = []
        if !currentFilters.regions.isEmpty { categories.append(.regions) }
        if !currentFilters.vehicleClassifications.isEmpty { categories.append(.vehicleClassifications) }
        if !currentFilters.fuelTypes.isEmpty { categories.append(.fuelTypes) }
        if !currentFilters.vehicleMakes.isEmpty { categories.append(.vehicleMakes) }
        if !currentFilters.vehicleModels.isEmpty { categories.append(.vehicleModels) }
        if !currentFilters.modelYears.isEmpty { categories.append(.modelYears) }
        if !currentFilters.mrcs.isEmpty { categories.append(.mrcs) }
        if !currentFilters.municipalities.isEmpty { categories.append(.municipalities) }
        if !currentFilters.ageRanges.isEmpty { categories.append(.ageRanges) }
        return categories
    }

    /// Available metric types based on data entity type
    private var availableMetricTypes: [ChartMetricType] {
        switch currentFilters.dataEntityType {
        case .license:
            // License data only has meaningful count and percentage metrics
            return [.count, .percentage]
        case .vehicle:
            // Vehicle data supports all metric types (count, sum, average, percentage)
            return ChartMetricType.allCases
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Metric type selector
            VStack(alignment: .leading, spacing: 4) {
                Text("Metric Type")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $metricType) {
                    ForEach(availableMetricTypes, id: \.self) { type in
                        Text(type.description).tag(type)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            // Field selector (shown for sum and average)
            if metricType == .sum || metricType == .average {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Field to \(metricType == .sum ? "Sum" : "Average")")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("", selection: $metricField) {
                        ForEach(ChartMetricField.allCases.filter { $0 != .none }, id: \.self) { field in
                            HStack {
                                Text(field.rawValue)
                                if let unit = field.unit {
                                    Text("(\(unit))")
                                        .foregroundColor(.secondary)
                                }
                            }.tag(field)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }

            // Percentage configuration
            if metricType == .percentage {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Numerator Category")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: Binding(
                        get: { selectedCategoryToRemove },
                        set: { newCategory in
                            selectedCategoryToRemove = newCategory
                            if let category = newCategory {
                                percentageBaseFilters = createBaselineFilters(droppingCategory: category)
                            } else {
                                percentageBaseFilters = nil
                            }
                        }
                    )) {
                        Text("Select category...").tag(FilterCategory?.none)
                        ForEach(availableCategories, id: \.self) { category in
                            Text(category.rawValue).tag(FilterCategory?.some(category))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    if selectedCategoryToRemove != nil {
                        Text("Percentage of \(currentFilters.dataEntityType == .license ? "license holders" : "vehicles") within other selected filters")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }

            // Description of what will be displayed
            if metricType != .count {
                HStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                    Text(descriptionText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: currentFilters.dataEntityType) { newDataType in
            // Reset metric type to count if current selection is not available for the new data type
            if !availableMetricTypes.contains(metricType) {
                metricType = .count
            }
        }
    }

    private func createBaselineFilters(droppingCategory: FilterCategory) -> PercentageBaseFilters {
        var baseFilters = PercentageBaseFilters.from(currentFilters)

        switch droppingCategory {
        case .regions:
            baseFilters.regions.removeAll()
        case .vehicleClassifications:
            baseFilters.vehicleClassifications.removeAll()
        case .fuelTypes:
            baseFilters.fuelTypes.removeAll()
        case .vehicleMakes:
            baseFilters.vehicleMakes.removeAll()
        case .vehicleModels:
            baseFilters.vehicleModels.removeAll()
        case .modelYears:
            baseFilters.modelYears.removeAll()
        case .mrcs:
            baseFilters.mrcs.removeAll()
        case .municipalities:
            baseFilters.municipalities.removeAll()
        case .ageRanges:
            baseFilters.ageRanges.removeAll()
        }

        return baseFilters
    }

    private var descriptionText: String {
        switch metricType {
        case .count:
            return "Number of vehicles matching filters"
        case .sum:
            switch metricField {
            case .netMass:
                return "Total weight of all vehicles"
            case .displacement:
                return "Total engine displacement"
            case .cylinderCount:
                return "Total number of cylinders"
            case .vehicleAge:
                return "Sum of all vehicle ages"
            default:
                return "Sum of \(metricField.rawValue)"
            }
        case .average:
            switch metricField {
            case .netMass:
                return "Average vehicle weight"
            case .displacement:
                return "Average engine displacement"
            case .cylinderCount:
                return "Average cylinders per vehicle"
            case .vehicleAge:
                return "Average age of vehicles"
            case .modelYear:
                return "Average model year"
            default:
                return "Average \(metricField.rawValue)"
            }
        case .percentage:
            return "Percentage of baseline category"
        }
    }
}

// MARK: - License Filter Section

struct LicenseFilterSection: View {
    @Binding var selectedLicenseTypes: Set<String>
    @Binding var selectedAgeGroups: Set<String>
    @Binding var selectedGenders: Set<String>
    @Binding var selectedExperienceLevels: Set<String>
    @Binding var selectedLicenseClasses: Set<String>

    let availableLicenseTypes: [String]
    let availableAgeGroups: [String]
    let availableGenders: [String]
    let availableExperienceLevels: [String]
    let availableLicenseClasses: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // License Types
            if !availableLicenseTypes.isEmpty {
                Text("License Type")
                    .font(.caption)
                    .foregroundColor(.secondary)

                SearchableFilterList(
                    items: availableLicenseTypes,
                    selectedItems: $selectedLicenseTypes,
                    searchPrompt: "Search license types..."
                )
            }

            // Age Groups
            if !availableAgeGroups.isEmpty {
                Divider()

                Text("Age Group")
                    .font(.caption)
                    .foregroundColor(.secondary)

                SearchableFilterList(
                    items: availableAgeGroups,
                    selectedItems: $selectedAgeGroups,
                    searchPrompt: "Search age groups..."
                )
            }

            // Gender
            if !availableGenders.isEmpty {
                Divider()

                Text("Gender")
                    .font(.caption)
                    .foregroundColor(.secondary)

                SearchableFilterList(
                    items: availableGenders.map { gender in
                        switch gender {
                        case "F": return "Female"
                        case "M": return "Male"
                        default: return gender
                        }
                    },
                    selectedItems: Binding(
                        get: {
                            Set(selectedGenders.map { gender in
                                switch gender {
                                case "F": return "Female"
                                case "M": return "Male"
                                default: return gender
                                }
                            })
                        },
                        set: { displayValues in
                            selectedGenders = Set(displayValues.map { displayValue in
                                switch displayValue {
                                case "Female": return "F"
                                case "Male": return "M"
                                default: return displayValue
                                }
                            })
                        }
                    ),
                    searchPrompt: "Search genders..."
                )
            }

            // Experience Levels
            if !availableExperienceLevels.isEmpty {
                Divider()

                Text("Experience Level")
                    .font(.caption)
                    .foregroundColor(.secondary)

                SearchableFilterList(
                    items: availableExperienceLevels,
                    selectedItems: $selectedExperienceLevels,
                    searchPrompt: "Search experience levels..."
                )
            }

            // License Classes
            if !availableLicenseClasses.isEmpty {
                Divider()

                Text("License Classes")
                    .font(.caption)
                    .foregroundColor(.secondary)

                SearchableFilterList(
                    items: availableLicenseClasses,
                    selectedItems: $selectedLicenseClasses,
                    searchPrompt: "Search license classes..."
                )
            }
        }
    }
}

