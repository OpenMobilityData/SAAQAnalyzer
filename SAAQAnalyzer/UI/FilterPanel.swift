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
    @State private var availableVehicleTypes: [String] = []
    @State private var availableVehicleMakes: [String] = []
    @State private var availableVehicleModels: [String] = []
    @State private var availableVehicleColors: [String] = []
    @State private var availableModelYears: [Int] = []
    @State private var availableAxleCounts: [Int] = []

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
    @State private var metricSectionExpanded = false  // Y-Axis Metric collapsed on launch
    @State private var filterOptionsSectionExpanded = true  // Filter Options expanded on launch

    // Analytics section height for draggable divider
    @State private var analyticsHeight: CGFloat = 400

    // Hierarchical filtering state
    @State private var isModelListFiltered: Bool = false

    // Regularization state (from AppStorage to match FilterOptionsSection)
    @AppStorage("regularizationEnabled") private var regularizationEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Analytics Section Header
            HStack {
                Label("Analytics", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline.weight(.medium))
                    .fontDesign(.rounded)
                    .symbolRenderingMode(.hierarchical)

                Spacer()
            }
            .padding()

            Divider()

            // Analytics configuration (Y-Axis Metric)
            if metricSectionExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Metric configuration section
                        DisclosureGroup(isExpanded: $metricSectionExpanded) {
                            MetricConfigurationSection(
                                metricType: $configuration.metricType,
                                metricField: $configuration.metricField,
                                percentageBaseFilters: $configuration.percentageBaseFilters,
                                coverageField: $configuration.coverageField,
                                coverageAsPercentage: $configuration.coverageAsPercentage,
                                roadWearIndexMode: $configuration.roadWearIndexMode,
                                normalizeToFirstYear: $configuration.normalizeToFirstYear,
                                showCumulativeSum: $configuration.showCumulativeSum,
                                currentFilters: configuration
                            )
                        } label: {
                            Label("Y-Axis Metric", systemImage: "chart.line.uptrend.xyaxis")
                                .font(.subheadline)
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                    .padding()
                }
                .frame(height: analyticsHeight)
                .clipped()  // Prevent content overflow when dragging divider

                // Draggable divider
                DraggableDivider(height: $analyticsHeight)
            } else {
                // Collapsed state - just show the disclosure group header
                VStack(alignment: .leading, spacing: 16) {
                    DisclosureGroup(isExpanded: $metricSectionExpanded) {
                        EmptyView()
                    } label: {
                        Label("Y-Axis Metric", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.subheadline)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .padding()
            }

            Divider()

            // Filters Section Header
            HStack {
                Label("Filters", systemImage: "line.horizontal.3.decrease.circle")
                    .font(.headline.weight(.medium))
                    .fontDesign(.rounded)
                    .symbolRenderingMode(.hierarchical)
                    .typesettingLanguage(.init(languageCode: .french))

                Spacer()

                Button("Clear All") {
                    clearAllFilters()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .tint(.secondary)
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
                            Text("Loading filter data...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .padding()
                    }

                    // Filter Options section
                    DisclosureGroup(isExpanded: $filterOptionsSectionExpanded) {
                        FilterOptionsSection(
                            limitToCuratedYears: $configuration.limitToCuratedYears
                        )
                    } label: {
                        Label("Filter Options", systemImage: "slider.horizontal.3")
                            .font(.subheadline)
                            .symbolRenderingMode(.hierarchical)
                    }

                    Divider()

                    // Years section
                    DisclosureGroup(isExpanded: $yearSectionExpanded) {
                        YearFilterSection(
                            availableYears: availableYears,
                            selectedYears: Binding(
                                get: { configuration.years },
                                set: { newYears in
                                    configuration.years = newYears
                                }
                            ),
                            limitToCuratedYears: configuration.limitToCuratedYears,
                            curatedYears: Set(databaseManager.regularizationManager?.getYearConfiguration().curatedYears ?? [])
                        )
                    } label: {
                        Label("Years", systemImage: "calendar")
                            .font(.subheadline)
                            .symbolRenderingMode(.hierarchical)
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
                            .symbolRenderingMode(.hierarchical)
                    }
                    
                    Divider()

                    // Data type specific sections
                    if configuration.dataEntityType == .vehicle {
                        // Vehicle characteristics section
                        vehicleCharacteristicsDisclosureGroup

                        Divider()

                        // Vehicle age ranges section
                        DisclosureGroup(isExpanded: $ageSectionExpanded) {
                            AgeRangeFilterSection(ageRanges: $configuration.ageRanges)
                        } label: {
                            Label("Vehicle Age", systemImage: "clock")
                                .font(.subheadline)
                                .symbolRenderingMode(.hierarchical)
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
                                        .foregroundStyle(.secondary)
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
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }
                .padding()
            }
            .scrollIndicators(.visible, axes: .vertical)
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 0))
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
        .onReceive(databaseManager.$dataVersion) { newVersion in
            // Reload filter options when dataVersion changes
            if hasInitiallyLoaded {
                Task {
                    print("🔄 Data version changed to \(newVersion), reloading all filter options")
                    // Reload all filter options to pick up new enumeration data
                    loadAvailableOptions()
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
        .onChange(of: configuration.limitToCuratedYears) { _, newValue in
            // Reload filter options when curated years toggle changes
            Task {
                print("🔄 Curated years filter changed to: \(newValue)")
                isModelListFiltered = false  // Reset filter state

                // When limiting to curated years, automatically deselect uncurated years
                if newValue {
                    if let regManager = databaseManager.regularizationManager {
                        let yearConfig = regManager.getYearConfiguration()
                        let curatedYearsSet = yearConfig.curatedYears

                        // Remove uncurated years from selection
                        let uncuratedYearsToRemove = configuration.years.subtracting(curatedYearsSet)
                        if !uncuratedYearsToRemove.isEmpty {
                            configuration.years = configuration.years.intersection(curatedYearsSet)
                            print("📊 Auto-deselected \(uncuratedYearsToRemove.count) uncurated year(s): \(uncuratedYearsToRemove.sorted())")
                        }
                    }
                }

                // Don't auto-select years when reloading (would re-add the years we just removed)
                await loadDataTypeSpecificOptions(autoSelectYears: false)
            }
        }
    }
    
    /// Quickly loads only years for incremental updates during batch imports
    private func loadYearsOnly() async {
        let years = await databaseManager.getAvailableYears(for: configuration.dataEntityType)
        await MainActor.run {
            availableYears = years
            print("📊 Reloaded years: \(years.count) available")
        }
    }

    /// Loads available filter options from database
    private func loadAvailableOptions() {
        Task {
            // Show loading if we don't already have data loaded
            let shouldShowLoading = availableYears.isEmpty

            if shouldShowLoading {
                isLoadingData = true
            }

            // Filter cache is now always available via enumeration tables
            print("🔍 Reading cached data version: \(databaseManager.dataVersion)")
            
            // Load shared options from database/cache in parallel
            async let years = databaseManager.getAvailableYears(for: configuration.dataEntityType)
            async let regions = databaseManager.getAvailableRegions(for: configuration.dataEntityType)
            async let mrcs = databaseManager.getAvailableMRCs(for: configuration.dataEntityType)
            async let municipalities = databaseManager.getAvailableMunicipalities(for: configuration.dataEntityType)
            async let municipalityMapping = databaseManager.getMunicipalityCodeToNameMapping()

            // Wait for all to complete
            let loadedData = await (years, regions, mrcs, municipalities, municipalityMapping)

            // Update UI state on main thread
            await MainActor.run {
                (availableYears, availableRegions, availableMRCs, availableMunicipalities, municipalityCodeToName) = loadedData
                print("📊 Loaded filter options: \(availableYears.count) years, \(availableRegions.count) regions, \(availableMRCs.count) MRCs")

                // Auto-select all years on initial load if none are selected
                // OR auto-select newly available years during batch imports
                if configuration.years.isEmpty && !availableYears.isEmpty {
                    configuration.years = Set(availableYears)
                    print("📊 Auto-selected all \(availableYears.count) years on initial load")
                } else {
                    // During batch import, auto-select any newly available years
                    let newYears = Set(availableYears).subtracting(configuration.years)
                    if !newYears.isEmpty {
                        configuration.years.formUnion(newYears)
                        print("📊 Auto-selected \(newYears.count) newly imported year(s): \(newYears.sorted())")
                    }
                }

                // If "Limit to Curated Years" is ON, deselect uncurated years
                // This ensures correct state on app launch when toggle is already ON
                if configuration.limitToCuratedYears {
                    if let regManager = databaseManager.regularizationManager {
                        let yearConfig = regManager.getYearConfiguration()
                        let curatedYearsSet = yearConfig.curatedYears

                        let uncuratedYearsToRemove = configuration.years.subtracting(curatedYearsSet)
                        if !uncuratedYearsToRemove.isEmpty {
                            configuration.years = configuration.years.intersection(curatedYearsSet)
                            print("📊 Removed \(uncuratedYearsToRemove.count) uncurated year(s) on initial load: \(uncuratedYearsToRemove.sorted())")
                        }
                    }
                }
            }

            // Load data type specific options
            await loadDataTypeSpecificOptions()

            await MainActor.run {
                isLoadingData = false
                hasInitiallyLoaded = true
            }
        }
    }

    /// Loads data type specific filter options
    /// - Parameter autoSelectYears: Whether to auto-select years (default: true). Set to false when called from hierarchical filtering to avoid AttributeGraph crashes.
    private func loadDataTypeSpecificOptions(autoSelectYears: Bool = true) async {
        // Load new data for the current mode
        if hasInitiallyLoaded {
            let years = await databaseManager.getAvailableYears(for: configuration.dataEntityType)
            let regions = await databaseManager.getAvailableRegions(for: configuration.dataEntityType)
            let mrcs = await databaseManager.getAvailableMRCs(for: configuration.dataEntityType)
            let municipalities = await databaseManager.getAvailableMunicipalities(for: configuration.dataEntityType)

            await MainActor.run {
                availableYears = years
                availableRegions = regions
                availableMRCs = mrcs
                availableMunicipalities = municipalities

                // Only auto-select years when explicitly requested (not during hierarchical filter resets)
                if autoSelectYears {
                    // Auto-select all years when switching data types if none are selected
                    // OR auto-select newly available years
                    if configuration.years.isEmpty && !years.isEmpty {
                        configuration.years = Set(years)
                        print("📊 Auto-selected all \(years.count) years after data type switch")
                    } else {
                        // Auto-select any newly available years
                        let newYears = Set(years).subtracting(configuration.years)
                        if !newYears.isEmpty {
                            configuration.years.formUnion(newYears)
                            print("📊 Auto-selected \(newYears.count) newly available year(s): \(newYears.sorted())")
                        }
                    }
                }
            }
        }

        switch configuration.dataEntityType {
        case .vehicle:
            // Load vehicle-specific options in parallel for better performance
            // Pass limitToCuratedYears to filter out uncurated Makes/Models if enabled
            async let vehicleClasses = databaseManager.getAvailableVehicleClasses()
            async let vehicleTypes = databaseManager.getAvailableVehicleTypes()
            let vehicleMakesItems = try? await databaseManager.filterCacheManager?.getAvailableMakes(limitToCuratedYears: configuration.limitToCuratedYears) ?? []

            // Always load all models (hierarchical filtering is now manual via button)
            let vehicleModelsItems = try? await databaseManager.filterCacheManager?.getAvailableModels(
                limitToCuratedYears: configuration.limitToCuratedYears,
                forMakeIds: nil
            ) ?? []
            async let vehicleColors = databaseManager.getAvailableVehicleColors()
            async let modelYears = databaseManager.getAvailableModelYears()
            let axleCounts = try? await databaseManager.filterCacheManager?.getAvailableAxleCounts() ?? []

            // Wait for all to complete
            let vehicleData = await (vehicleClasses, vehicleTypes, vehicleColors, modelYears)

            // Convert FilterItems to display names
            let vehicleMakes = vehicleMakesItems?.map { $0.displayName } ?? []
            let vehicleModels = vehicleModelsItems?.map { $0.displayName } ?? []

            // Update UI state on main thread
            await MainActor.run {
                (availableClassifications, availableVehicleTypes, availableVehicleColors, availableModelYears) = vehicleData
                availableVehicleMakes = vehicleMakes
                availableAxleCounts = axleCounts ?? []
                availableVehicleModels = vehicleModels

                // Clear license options
                availableLicenseTypes = []
                availableAgeGroups = []
                availableGenders = []
                availableExperienceLevels = []
                availableLicenseClasses = []
            }

        case .license:
            // Set loading state for license characteristics
            await MainActor.run {
                isLoadingLicenseCharacteristics = true
            }

            // Load license-specific options in parallel for better performance
            async let licenseTypes = databaseManager.getAvailableLicenseTypes()
            async let ageGroups = databaseManager.getAvailableAgeGroups()
            async let genders = databaseManager.getAvailableGenders()
            async let experienceLevels = databaseManager.getAvailableExperienceLevels()
            async let licenseClasses = databaseManager.getAvailableLicenseClasses()

            // Wait for all to complete
            let licenseData = await (licenseTypes, ageGroups, genders, experienceLevels, licenseClasses)

            // Update UI state on main thread
            await MainActor.run {
                (availableLicenseTypes, availableAgeGroups, availableGenders,
                 availableExperienceLevels, availableLicenseClasses) = licenseData

                // Clear loading state
                isLoadingLicenseCharacteristics = false

                // Clear vehicle options
                availableClassifications = []
                availableVehicleTypes = []
                availableVehicleMakes = []
                availableVehicleModels = []
                availableVehicleColors = []
                availableModelYears = []
                availableAxleCounts = []
            }
        }
    }
    
    /// Smart refresh that only updates if there are actual changes
    private func refreshIfNeeded() async {
        // Check if we already have data loaded
        if !availableYears.isEmpty {
            print("📊 Data already loaded, skipping refresh")
            return
        }

        // Check if years have changed (most common update)
        let newYears = await databaseManager.getAvailableYears(for: configuration.dataEntityType)

        // Only reload everything if we have new years
        // (replacing existing year data doesn't add new years)
        if Set(newYears) != Set(availableYears) {
            print("📊 New years detected, refreshing filter options...")
            availableYears = newYears

            // Also refresh vehicleClasses in case new year has different vehicle types
            availableClassifications = await databaseManager.getAvailableVehicleClasses()
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
                configuration.vehicleClasses.removeAll()
                configuration.vehicleTypes.removeAll()
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

    // MARK: - Helper Views

    /// Extract vehicle characteristics section to avoid type checker complexity
    private var vehicleCharacteristicsDisclosureGroup: some View {
        DisclosureGroup(isExpanded: $vehicleSectionExpanded) {
            VehicleFilterSection(
                selectedVehicleClasses: $configuration.vehicleClasses,
                selectedVehicleTypes: $configuration.vehicleTypes,
                selectedVehicleMakes: $configuration.vehicleMakes,
                selectedVehicleModels: $configuration.vehicleModels,
                selectedVehicleColors: $configuration.vehicleColors,
                selectedModelYears: $configuration.modelYears,
                selectedFuelTypes: $configuration.fuelTypes,
                selectedAxleCounts: $configuration.axleCounts,
                availableYears: availableYears,
                availableVehicleClasses: availableClassifications,
                availableVehicleTypes: availableVehicleTypes,
                availableVehicleMakes: availableVehicleMakes,
                availableVehicleModels: availableVehicleModels,
                availableVehicleColors: availableVehicleColors,
                availableModelYears: availableModelYears,
                availableAxleCounts: availableAxleCounts,
                isModelListFiltered: $isModelListFiltered,
                selectedMakesCount: configuration.vehicleMakes.count,
                onFilterByMakes: { Task { await filterModelsBySelectedMakes() } },
                enableQueryRegularization: regularizationEnabled
            )
        } label: {
            Label("Vehicle Characteristics", systemImage: "car")
                .font(.subheadline)
                .symbolRenderingMode(.hierarchical)
        }
    }

    // MARK: - Helper Functions

    /// Filter models by selected makes (manual button action)
    /// This is a minimal function that ONLY updates the model list - nothing else.
    /// Avoids AttributeGraph crashes by not triggering cascading binding updates.
    private func filterModelsBySelectedMakes() async {
        if configuration.vehicleMakes.isEmpty {
            // No makes selected, reload ALL models only
            let vehicleModelsItems = try? await databaseManager.filterCacheManager?
                .getAvailableModels(
                    limitToCuratedYears: configuration.limitToCuratedYears,
                    forMakeIds: nil  // nil = all models
                ) ?? []

            await MainActor.run {
                availableVehicleModels = vehicleModelsItems?.map { $0.displayName } ?? []
                isModelListFiltered = false
                print("🔄 Reset to all \(availableVehicleModels.count) models")
            }
            return
        }

        // Get selected make IDs
        let vehicleMakesItems = try? await databaseManager.filterCacheManager?
            .getAvailableMakes(limitToCuratedYears: configuration.limitToCuratedYears) ?? []

        let selectedMakeIds = Set(vehicleMakesItems?.filter { make in
            configuration.vehicleMakes.contains(make.displayName)
        }.map { $0.id } ?? [])

        guard !selectedMakeIds.isEmpty else {
            // No valid make IDs, show all models
            let vehicleModelsItems = try? await databaseManager.filterCacheManager?
                .getAvailableModels(
                    limitToCuratedYears: configuration.limitToCuratedYears,
                    forMakeIds: nil  // nil = all models
                ) ?? []

            await MainActor.run {
                availableVehicleModels = vehicleModelsItems?.map { $0.displayName } ?? []
                isModelListFiltered = false
                print("🔄 Reset to all \(availableVehicleModels.count) models (invalid make IDs)")
            }
            return
        }

        // Load filtered models
        let vehicleModelsItems = try? await databaseManager.filterCacheManager?
            .getAvailableModels(
                limitToCuratedYears: configuration.limitToCuratedYears,
                forMakeIds: selectedMakeIds
            ) ?? []

        await MainActor.run {
            availableVehicleModels = vehicleModelsItems?.map { $0.displayName } ?? []
            isModelListFiltered = true
            print("🔄 Filtered models to \(availableVehicleModels.count) for \(configuration.vehicleMakes.count) selected make(s)")
        }
    }
}

// MARK: - Year Filter Section

struct YearFilterSection: View {
    let availableYears: [Int]
    @Binding var selectedYears: Set<Int>
    let limitToCuratedYears: Bool
    let curatedYears: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Quick select buttons
            HStack {
                Button("All") {
                    selectedYears = Set(availableYears)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.small)

                Button("Last 5") {
                    let lastFive = availableYears.suffix(5)
                    selectedYears = Set(lastFive)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.small)

                Button("Clear") {
                    selectedYears.removeAll()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.small)
            }

            // Year checkboxes in a grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 8) {
                ForEach(availableYears, id: \.self) { year in
                    let isUncurated = limitToCuratedYears && !curatedYears.contains(year)

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
                    .disabled(isUncurated)
                    .opacity(isUncurated ? 0.4 : 1.0)
                    .help(isUncurated ? "This year is not curated and will be excluded from queries" : "")
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
                    .foregroundStyle(.secondary)
                
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
                    .foregroundStyle(.secondary)
                
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
                    .foregroundStyle(.secondary)

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
                        .foregroundStyle(.secondary)
                    
                    if !configuration.regions.isEmpty {
                        HStack {
                            Image(systemName: "flag.fill")
                                .foregroundStyle(.blue)
                            Text("\(configuration.regions.count) region(s)")
                                .font(.caption)
                        }
                    }
                    
                    if !configuration.mrcs.isEmpty {
                        HStack {
                            Image(systemName: "building.2.fill")
                                .foregroundStyle(.green)
                            Text("\(configuration.mrcs.count) MRC(s)")
                                .font(.caption)
                        }
                    }
                    
                    if !configuration.municipalities.isEmpty {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundStyle(.orange)
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
    @Binding var selectedVehicleClasses: Set<String>
    @Binding var selectedVehicleTypes: Set<String>
    @Binding var selectedVehicleMakes: Set<String>
    @Binding var selectedVehicleModels: Set<String>
    @Binding var selectedVehicleColors: Set<String>
    @Binding var selectedModelYears: Set<Int>
    @Binding var selectedFuelTypes: Set<String>
    @Binding var selectedAxleCounts: Set<Int>
    let availableYears: [Int]
    let availableVehicleClasses: [String]
    let availableVehicleTypes: [String]
    let availableVehicleMakes: [String]
    let availableVehicleModels: [String]
    let availableVehicleColors: [String]
    let availableModelYears: [Int]
    let availableAxleCounts: [Int]

    // Model filtering parameters
    @Binding var isModelListFiltered: Bool
    let selectedMakesCount: Int
    let onFilterByMakes: () -> Void

    // Regularization state (for dimming inactive mappings)
    let enableQueryRegularization: Bool

    // Check if any year from 2017+ is selected (for fuel type filter)
    private var hasFuelTypeYears: Bool {
        availableYears.contains { $0 >= 2017 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Vehicle classes (use actual database values)
            if !availableVehicleClasses.isEmpty {
                Text("Vehicle Class")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VehicleClassFilterList(
                    availableVehicleClasses: availableVehicleClasses,
                    selectedVehicleClasses: $selectedVehicleClasses
                )
            }

            // Vehicle types (use actual database values)
            if !availableVehicleTypes.isEmpty {
                Divider()

                Text("Vehicle Type")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VehicleTypeFilterList(
                    availableVehicleTypes: availableVehicleTypes,
                    selectedVehicleTypes: $selectedVehicleTypes
                )
            }

            // Vehicle Makes
            if !availableVehicleMakes.isEmpty {
                Divider()

                Text("Vehicle Make")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SearchableFilterList(
                    items: availableVehicleMakes,
                    selectedItems: $selectedVehicleMakes,
                    searchPrompt: "Search vehicle makes...",
                    dimRegularizationMappings: !enableQueryRegularization
                )
            }

            // Vehicle Models
            if !availableVehicleModels.isEmpty {
                Divider()

                HStack {
                    Text("Vehicle Model")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Manual filter button (show when makes are selected OR when list is filtered)
                    if selectedMakesCount > 0 || isModelListFiltered {
                        Button(action: onFilterByMakes) {
                            HStack(spacing: 4) {
                                Image(systemName: isModelListFiltered ? "line.horizontal.3.decrease.circle.fill" : "line.horizontal.3.decrease.circle")
                                if isModelListFiltered && selectedMakesCount > 0 {
                                    // List is filtered AND makes are still selected - show status
                                    Text("Filtering by \(selectedMakesCount) Make\(selectedMakesCount > 1 ? "s" : "")")
                                } else if isModelListFiltered {
                                    // List is filtered but no makes selected - can show all
                                    Text("Show All Models")
                                } else {
                                    // Makes selected but not yet filtered - offer to filter
                                    Text("Filter by Selected Makes (\(selectedMakesCount))")
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(isModelListFiltered && selectedMakesCount > 0)
                        .help(isModelListFiltered && selectedMakesCount > 0
                            ? "Deselect makes to show all models"
                            : (isModelListFiltered
                                ? "Show all available models"
                                : "Show only models for selected make(s)"))
                    }
                }

                SearchableFilterList(
                    items: availableVehicleModels,
                    selectedItems: $selectedVehicleModels,
                    searchPrompt: "Search vehicle models...",
                    dimRegularizationMappings: !enableQueryRegularization
                )
            }

            // Vehicle Colors
            if !availableVehicleColors.isEmpty {
                Divider()

                Text("Vehicle Color")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
                    .foregroundStyle(.secondary)

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
                    .foregroundStyle(.secondary)

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

            // Axle Count (trucks only - vehicles with axle data)
            if !availableAxleCounts.isEmpty {
                Divider()

                Text("Axle Count")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SearchableFilterList(
                    items: availableAxleCounts.map { "\($0) axle\($0 > 1 ? "s" : "")" },
                    selectedItems: Binding(
                        get: {
                            Set(selectedAxleCounts.map { count in
                                "\(count) axle\(count > 1 ? "s" : "")"
                            })
                        },
                        set: { stringSet in
                            selectedAxleCounts = Set(stringSet.compactMap { str in
                                // Extract the number from "N axle(s)" format
                                Int(str.split(separator: " ").first.map(String.init) ?? "")
                            })
                        }
                    ),
                    searchPrompt: "Search axle counts..."
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
                .foregroundStyle(.secondary)
            
            HStack {
                Button("-1 to 5 years") {
                    addAgeRange(min: -1, max: 5)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.small)
                .help("Includes vehicles registered before their model year (e.g., 2022 models registered in late 2021)")

                Button("6-10 years") {
                    addAgeRange(min: 6, max: 10)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.small)

                Button("11-15 years") {
                    addAgeRange(min: 11, max: 15)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.small)

                Button("16+ years") {
                    addAgeRange(min: 16, max: nil)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.small)
            }
            
            // Custom ranges
            if !ageRanges.isEmpty {
                Divider()
                
                Text("Selected Ranges")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
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
                                .foregroundStyle(.secondary)
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
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle)
            .controlSize(.small)
            .popover(isPresented: $showAddRange) {
                CustomAgeRangeView(ageRanges: $ageRanges)
                    .presentationSizing(.fitted)
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
                .buttonBorderShape(.roundedRectangle)

                Button("Add") {
                    addRange()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle)
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
    var dimRegularizationMappings: Bool = false  // Simpler: just a bool flag

    @State private var searchText = ""
    @State private var isExpanded = false
    
    private var filteredItems: [String] {
        // ALWAYS include selected items (even if they don't match search)
        // Then add unselected items that match search
        let selectedInItems = items.filter { selectedItems.contains($0) }

        if searchText.isEmpty {
            // No search: return all items with selected first
            let unselectedInItems = items.filter { !selectedItems.contains($0) }
            return selectedInItems.sorted() + unselectedInItems.sorted()
        }

        // With search: selected items first (all of them), then matching unselected items
        let matchingUnselected = items.filter { item in
            !selectedItems.contains(item) && item.localizedCaseInsensitiveContains(searchText)
        }
        return selectedInItems.sorted() + matchingUnselected.sorted()
    }

    private var displayedItems: [String] {
        // Auto-expand if:
        // 1. User explicitly expanded the list, OR
        // 2. Search is active and results are small enough (≤20 items), OR
        // 3. Search is active and narrowed results significantly (≤30% of original)
        let shouldAutoExpand = isExpanded ||
                              (!searchText.isEmpty && filteredItems.count <= 20) ||
                              (!searchText.isEmpty && items.count > 0 && Double(filteredItems.count) / Double(items.count) <= 0.3)

        return shouldAutoExpand ? filteredItems : Array(filteredItems.prefix(5))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Search field
            if items.count > 8 {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    TextField(searchPrompt, text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
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
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.mini)

                Button("Clear") {
                    selectedItems.removeAll()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.mini)
                
                Spacer()

                // Only show expand/collapse button when:
                // 1. List is large enough (>5 items)
                // 2. No active search (search auto-expands)
                // 3. OR search is active but didn't auto-expand (still many results)
                let hasActiveSearch = !searchText.isEmpty
                let autoExpandedBySearch = hasActiveSearch && (filteredItems.count <= 20 || (items.count > 0 && Double(filteredItems.count) / Double(items.count) <= 0.3))

                if items.count > 5 && !autoExpandedBySearch {
                    Button(isExpanded ? "Show Less" : "Show All (\(items.count))") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                    .tint(.accentColor)
                }
            }
            
            // Filter items
            VStack(alignment: .leading, spacing: 2) {
                ForEach(displayedItems, id: \.self) { item in
                    let isRegularizationMapping = item.contains(" → ")
                    let shouldDim = dimRegularizationMappings && isRegularizationMapping

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
                            .typesettingLanguage(.init(languageCode: .french))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(shouldDim ? 0.5 : 1.0)
                    }
                    .padding(.vertical, 1)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: displayedItems.count)
            
            // Search results summary
            if !searchText.isEmpty && filteredItems.count != items.count {
                Text("Showing \(filteredItems.count) of \(items.count) items")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Vehicle Classification Filter List

struct VehicleClassFilterList: View {
    let availableVehicleClasses: [String]
    @Binding var selectedVehicleClasses: Set<String>
    
    @State private var searchText = ""
    @State private var isExpanded = false
    
    private var filteredItems: [String] {
        // ALWAYS include selected items (even if they don't match search)
        // Then add unselected items that match search
        let selectedInItems = availableVehicleClasses.filter { selectedVehicleClasses.contains($0) }

        if searchText.isEmpty {
            // No search: return all items with selected first
            let unselectedInItems = availableVehicleClasses.filter { !selectedVehicleClasses.contains($0) }
            return selectedInItems.sorted() + unselectedInItems.sorted()
        }

        // With search: selected items first (all of them), then matching unselected items
        let matchingUnselected = availableVehicleClasses.filter { vehicleClass in
            if selectedVehicleClasses.contains(vehicleClass) { return false }
            let displayName = getDisplayName(for: vehicleClass)
            return displayName.localizedCaseInsensitiveContains(searchText) ||
                   vehicleClass.localizedCaseInsensitiveContains(searchText)
        }
        return selectedInItems.sorted() + matchingUnselected.sorted()
    }

    private var displayedItems: [String] {
        // No additional sorting needed - filteredItems already has correct order
        return isExpanded ? filteredItems : Array(filteredItems.prefix(6))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Search field
            if availableVehicleClasses.count > 10 {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
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
                    selectedVehicleClasses = Set(filteredItems)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.mini)

                Button("Clear") {
                    selectedVehicleClasses.removeAll()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.mini)
                
                Spacer()
                
                if availableVehicleClasses.count > 6 && searchText.isEmpty {
                    Button(isExpanded ? "Show Less" : "Show All (\(availableVehicleClasses.count))") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                    .tint(.accentColor)
                }
            }
            
            // Filter items
            VStack(alignment: .leading, spacing: 2) {
                ForEach(displayedItems, id: \.self) { vehicleClass in
                    HStack(alignment: .top, spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { selectedVehicleClasses.contains(vehicleClass) },
                            set: { isSelected in
                                if isSelected {
                                    selectedVehicleClasses.insert(vehicleClass)
                                } else {
                                    selectedVehicleClasses.remove(vehicleClass)
                                }
                            }
                        )) {
                            EmptyView()
                        }
                        .toggleStyle(.checkbox)
                        .controlSize(.mini)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(getDisplayName(for: vehicleClass))
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 1)
                    .help(getDescription(for: vehicleClass))  // Tooltip with description
                }
            }
            .animation(.easeInOut(duration: 0.2), value: displayedItems.count)
            
            // Search results summary
            if !searchText.isEmpty && filteredItems.count != availableVehicleClasses.count {
                Text("Showing \(filteredItems.count) of \(availableVehicleClasses.count) vehicle types")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
    
    // Helper methods for vehicle vehicleClass display
    private func getDisplayName(for vehicleClass: String) -> String {
        // Handle special NULL case (empty string from database)
        if vehicleClass.isEmpty || vehicleClass.trimmingCharacters(in: .whitespaces).isEmpty {
            return "NUL - Not Specified"
        }

        // Handle UNK special case
        if vehicleClass.uppercased() == "UNK" {
            return "UNK - Unknown"
        }

        // Handle normal vehicle classes
        if let vehicleClass = VehicleClass(rawValue: vehicleClass) {
            return "\(vehicleClass.rawValue.uppercased()) - \(vehicleClass.description)"
        }

        return vehicleClass
    }
    
    private func getDescription(for vehicleClass: String) -> String {
        if let vehicleClass = VehicleClass(rawValue: vehicleClass) {
            return vehicleClass.description
        }
        return "Unknown vehicleClass: \(vehicleClass)"
    }
}

// MARK: - Vehicle Type Filter List

struct VehicleTypeFilterList: View {
    let availableVehicleTypes: [String]
    @Binding var selectedVehicleTypes: Set<String>

    @State private var searchText = ""
    @State private var isExpanded = false

    private var filteredItems: [String] {
        // ALWAYS include selected items (even if they don't match search)
        // Then add unselected items that match search
        let selectedInItems = availableVehicleTypes.filter { selectedVehicleTypes.contains($0) }

        if searchText.isEmpty {
            // No search: return all items with selected first
            let unselectedInItems = availableVehicleTypes.filter { !selectedVehicleTypes.contains($0) }
            return selectedInItems.sorted() + unselectedInItems.sorted()
        }

        // With search: selected items first (all of them), then matching unselected items
        let matchingUnselected = availableVehicleTypes.filter { vehicleType in
            if selectedVehicleTypes.contains(vehicleType) { return false }
            let displayName = getDisplayName(for: vehicleType)
            return displayName.localizedCaseInsensitiveContains(searchText) ||
                   vehicleType.localizedCaseInsensitiveContains(searchText)
        }
        return selectedInItems.sorted() + matchingUnselected.sorted()
    }

    private var displayedItems: [String] {
        // Sort with special handling: UK (Unknown) goes at the end
        // Apply this sorting WITHIN each group (selected vs unselected)
        let sorted = filteredItems.sorted { item1, item2 in
            // If either is UK, put it at the end
            if item1.uppercased() == "UK" { return false }
            if item2.uppercased() == "UK" { return true }
            // Otherwise sort alphabetically
            return item1 < item2
        }
        return isExpanded ? sorted : Array(sorted.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Search field
            if availableVehicleTypes.count > 10 {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
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
                    selectedVehicleTypes = Set(filteredItems)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.mini)

                Button("Clear") {
                    selectedVehicleTypes.removeAll()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.mini)

                Spacer()

                if availableVehicleTypes.count > 6 && searchText.isEmpty {
                    Button(isExpanded ? "Show Less" : "Show All (\(availableVehicleTypes.count))") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                    .tint(.accentColor)
                }
            }

            // Filter items
            VStack(alignment: .leading, spacing: 2) {
                ForEach(displayedItems, id: \.self) { vehicleType in
                    HStack(alignment: .top, spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { selectedVehicleTypes.contains(vehicleType) },
                            set: { isSelected in
                                if isSelected {
                                    selectedVehicleTypes.insert(vehicleType)
                                } else {
                                    selectedVehicleTypes.remove(vehicleType)
                                }
                            }
                        )) {
                            EmptyView()
                        }
                        .toggleStyle(.checkbox)
                        .controlSize(.mini)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(getDisplayName(for: vehicleType))
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 1)
                    .help(getDescription(for: vehicleType))  // Tooltip with description
                }
            }
            .animation(.easeInOut(duration: 0.2), value: displayedItems.count)

            // Search results summary
            if !searchText.isEmpty && filteredItems.count != availableVehicleTypes.count {
                Text("Showing \(filteredItems.count) of \(availableVehicleTypes.count) vehicle types")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    // Helper methods for vehicle type display
    private func getDisplayName(for vehicleType: String) -> String {
        // Handle special NULL case (empty string from database)
        if vehicleType.isEmpty || vehicleType.trimmingCharacters(in: .whitespaces).isEmpty {
            return "NUL - Not Specified"
        }

        // Handle UK special case (Unknown)
        if vehicleType.uppercased() == "UK" {
            return "UK - Unknown"
        }

        // Handle normal vehicle types
        let typeDescription: String
        switch vehicleType {
        case "AB": typeDescription = "Bus"
        case "AT": typeDescription = "Dealer Plates"
        case "AU": typeDescription = "Automobile or Light Truck"
        case "CA": typeDescription = "Truck or Road Tractor"
        case "CY": typeDescription = "Moped"
        case "HM": typeDescription = "Motorhome"
        case "MC": typeDescription = "Motorcycle"
        case "MN": typeDescription = "Snowmobile"
        case "NV": typeDescription = "Other Off-Road Vehicle"
        case "SN": typeDescription = "Snow Blower"
        case "VO": typeDescription = "Tool Vehicle"
        case "VT": typeDescription = "All-Terrain Vehicle"
        default: return vehicleType
        }

        return "\(vehicleType.uppercased()) - \(typeDescription)"
    }

    private func getDescription(for vehicleType: String) -> String {
        switch vehicleType {
        case "AB": return "Bus"
        case "AT": return "Dealer Plates (Auto/Temporary)"
        case "AU": return "Automobile or Light Truck"
        case "CA": return "Truck or Road Tractor"
        case "CY": return "Moped"
        case "HM": return "Motorhome"
        case "MC": return "Motorcycle"
        case "MN": return "Snowmobile"
        case "NV": return "Other Off-Road Vehicle"
        case "SN": return "Snow Blower"
        case "UK": return "Unknown (user-assigned)"
        case "VO": return "Tool Vehicle"
        case "VT": return "All-Terrain Vehicle"
        default: return "Unknown vehicle type: \(vehicleType)"
        }
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
        // ALWAYS include selected items (even if they don't match search)
        // Then add unselected items that match search
        let selectedInItems = displayItems.filter { selectedCodes.contains($0.code) }

        if searchText.isEmpty {
            // No search: return all items with selected first
            let unselectedInItems = displayItems.filter { !selectedCodes.contains($0.code) }
            return selectedInItems.sorted { $0.name < $1.name } + unselectedInItems.sorted { $0.name < $1.name }
        }

        // With search: selected items first (all of them), then matching unselected items
        let matchingUnselected = displayItems.filter { item in
            !selectedCodes.contains(item.code) && item.name.localizedCaseInsensitiveContains(searchText)
        }
        return selectedInItems.sorted { $0.name < $1.name } + matchingUnselected.sorted { $0.name < $1.name }
    }

    private var displayedItems: [(name: String, code: String)] {
        // No additional sorting needed - filteredItems already has correct order
        return isExpanded ? filteredItems : Array(filteredItems.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Search field
            if displayItems.count > 8 {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
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
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.mini)

                Button("Clear") {
                    selectedCodes.removeAll()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.mini)

                Spacer()

                if displayItems.count > 5 && searchText.isEmpty {
                    Button(isExpanded ? "Show Less" : "Show All (\(displayItems.count))") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                    .tint(.accentColor)
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
                            .typesettingLanguage(.init(languageCode: .french))
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
                    .foregroundStyle(.secondary)
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
    @Binding var coverageField: CoverageField?
    @Binding var coverageAsPercentage: Bool
    @Binding var roadWearIndexMode: FilterConfiguration.RoadWearIndexMode
    @Binding var normalizeToFirstYear: Bool
    @Binding var showCumulativeSum: Bool
    let currentFilters: FilterConfiguration

    @State private var selectedCategoryToRemove: FilterCategory?

    enum FilterCategory: String, CaseIterable {
        // Geographic filters (shared)
        case regions = "Admin Region"
        case mrcs = "MRC"
        case municipalities = "Municipality"

        // Vehicle-specific filters
        case vehicleClasses = "Vehicle Class"
        case vehicleTypes = "Vehicle Type"
        case fuelTypes = "Fuel Type"
        case vehicleMakes = "Vehicle Make"
        case vehicleModels = "Vehicle Model"
        case vehicleColors = "Vehicle Color"
        case modelYears = "Model Year"
        case axleCounts = "Axle Count"
        case ageRanges = "Vehicle Age"

        // License-specific filters
        case licenseTypes = "License Type"
        case ageGroups = "Age Group"
        case genders = "Gender"
        case experienceLevels = "Experience Level"
        case licenseClasses = "License Classes"
    }

    private var availableCategories: [FilterCategory] {
        var categories: [FilterCategory] = []

        // Geographic filters (shared)
        if !currentFilters.regions.isEmpty { categories.append(.regions) }
        if !currentFilters.mrcs.isEmpty { categories.append(.mrcs) }
        if !currentFilters.municipalities.isEmpty { categories.append(.municipalities) }

        // Vehicle-specific filters
        if !currentFilters.vehicleClasses.isEmpty { categories.append(.vehicleClasses) }
        if !currentFilters.vehicleTypes.isEmpty { categories.append(.vehicleTypes) }
        if !currentFilters.fuelTypes.isEmpty { categories.append(.fuelTypes) }
        if !currentFilters.vehicleMakes.isEmpty { categories.append(.vehicleMakes) }
        if !currentFilters.vehicleModels.isEmpty { categories.append(.vehicleModels) }
        if !currentFilters.vehicleColors.isEmpty { categories.append(.vehicleColors) }
        if !currentFilters.modelYears.isEmpty { categories.append(.modelYears) }
        if !currentFilters.ageRanges.isEmpty { categories.append(.ageRanges) }

        // License-specific filters
        if !currentFilters.licenseTypes.isEmpty { categories.append(.licenseTypes) }
        if !currentFilters.ageGroups.isEmpty { categories.append(.ageGroups) }
        if !currentFilters.genders.isEmpty { categories.append(.genders) }
        if !currentFilters.experienceLevels.isEmpty { categories.append(.experienceLevels) }
        if !currentFilters.licenseClasses.isEmpty { categories.append(.licenseClasses) }

        // Ensure selected category is always included even if filter is temporarily empty
        if let selected = selectedCategoryToRemove, !categories.contains(selected) {
            categories.append(selected)
        }

        return categories
    }

    /// Available metric types based on data entity type
    private var availableMetricTypes: [ChartMetricType] {
        switch currentFilters.dataEntityType {
        case .license:
            // License data only has meaningful count, percentage, and coverage metrics
            return [.count, .percentage, .coverage]
        case .vehicle:
            // Vehicle data supports all metric types (count, sum, average, percentage, coverage)
            return ChartMetricType.allCases
        }
    }

    /// Available fields for coverage analysis based on data entity type
    private var availableCoverageFields: [CoverageField] {
        return CoverageField.allCases.filter { $0.isApplicable(to: currentFilters.dataEntityType) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Metric type selector
            VStack(alignment: .leading, spacing: 4) {
                Text("Metric Type")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: $metricType) {
                    ForEach(availableMetricTypes, id: \.self) { type in
                        Text(type.description).tag(type)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            .onAppear {
                // Sync selectedCategoryToRemove from percentageBaseFilters on view load
                // This ensures UI state is restored when view is recreated
                syncCategorySelectionFromBaseFilters()
            }

            // Field selector (shown for sum, average, median, minimum, and maximum)
            if metricType == .sum || metricType == .average || metricType == .median || metricType == .minimum || metricType == .maximum {
                VStack(alignment: .leading, spacing: 4) {
                    let preposition = (metricType == .minimum || metricType == .maximum) ? "for" : "to"
                    Text("Field \(preposition) \(metricType.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $metricField) {
                        ForEach(ChartMetricField.allCases.filter { $0 != .none }, id: \.self) { field in
                            HStack {
                                Text(field.rawValue)
                                if let unit = field.unit {
                                    Text("(\(unit))")
                                        .foregroundStyle(.secondary)
                                }
                            }.tag(field)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .controlSize(.small)
                }
            }

            // Percentage configuration
            if metricType == .percentage {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Numerator Category")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    .controlSize(.small)

                    if selectedCategoryToRemove != nil {
                        Text("Percentage of \(currentFilters.dataEntityType == .license ? "license holders" : "vehicles") within other selected filters")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }

            // Coverage configuration
            if metricType == .coverage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Field to Analyze")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $coverageField) {
                        Text("Select field...").tag(CoverageField?.none)
                        ForEach(availableCoverageFields, id: \.self) { field in
                            Text(field.rawValue).tag(CoverageField?.some(field))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .controlSize(.small)

                    if coverageField != nil {
                        // Toggle between percentage and raw count
                        Toggle(isOn: $coverageAsPercentage) {
                            Text("Show as percentage")
                                .font(.caption)
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        Text(coverageAsPercentage
                            ? "Percentage of records with non-NULL \(coverageField?.rawValue ?? "") values"
                            : "Count of NULL \(coverageField?.rawValue ?? "") values")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }

            // Road Wear Index configuration
            if metricType == .roadWearIndex {
                VStack(alignment: .leading, spacing: 8) {
                    // Mode selector (Average vs Sum)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Road Wear Index Mode")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Mode", selection: $roadWearIndexMode) {
                            ForEach(FilterConfiguration.RoadWearIndexMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                }
            }

            // Normalize to first year toggle (available for all metrics)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $normalizeToFirstYear) {
                    Text("Normalize to first year")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Text(normalizeToFirstYear
                    ? "First year = 1.0, other years show relative change (e.g., 1.05 = 5% increase)"
                    : "Shows raw metric values")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }

            // Cumulative sum toggle (available for all metrics)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $showCumulativeSum) {
                    Text("Show cumulative sum")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Text(showCumulativeSum
                    ? "Each year shows total accumulated from all previous years"
                    : "Each year shows value for that year only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }

            // Description of what will be displayed
            // Skip for coverage when field is selected since we already show description above
            if metricType != .count && !(metricType == .coverage && coverageField != nil) {
                HStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                    Text(descriptionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: currentFilters.dataEntityType) { _, newDataType in
            // Reset metric type to count if current selection is not available for the new data type
            if !availableMetricTypes.contains(metricType) {
                metricType = .count
            }
        }
    }

    private func createBaselineFilters(droppingCategory: FilterCategory) -> PercentageBaseFilters {
        var baseFilters = PercentageBaseFilters.from(currentFilters)

        switch droppingCategory {
        // Geographic filters (shared)
        case .regions:
            baseFilters.regions.removeAll()
        case .mrcs:
            baseFilters.mrcs.removeAll()
        case .municipalities:
            baseFilters.municipalities.removeAll()

        // Vehicle-specific filters
        case .vehicleClasses:
            baseFilters.vehicleClasses.removeAll()
        case .vehicleTypes:
            baseFilters.vehicleTypes.removeAll()
        case .fuelTypes:
            baseFilters.fuelTypes.removeAll()
        case .vehicleMakes:
            baseFilters.vehicleMakes.removeAll()
        case .vehicleModels:
            baseFilters.vehicleModels.removeAll()
        case .vehicleColors:
            baseFilters.vehicleColors.removeAll()
        case .modelYears:
            baseFilters.modelYears.removeAll()
        case .axleCounts:
            baseFilters.axleCounts.removeAll()
        case .ageRanges:
            baseFilters.ageRanges.removeAll()

        // License-specific filters
        case .licenseTypes:
            baseFilters.licenseTypes.removeAll()
        case .ageGroups:
            baseFilters.ageGroups.removeAll()
        case .genders:
            baseFilters.genders.removeAll()
        case .experienceLevels:
            baseFilters.experienceLevels.removeAll()
        case .licenseClasses:
            baseFilters.licenseClasses.removeAll()
        }

        return baseFilters
    }

    /// Syncs the selected category from existing percentageBaseFilters
    /// This restores UI state when the view is recreated
    private func syncCategorySelectionFromBaseFilters() {
        guard let baseFilters = percentageBaseFilters else {
            // No base filters set, nothing to sync
            selectedCategoryToRemove = nil
            return
        }

        // Determine which category was removed by comparing base filters with current filters
        // The removed category will be empty in baseFilters but non-empty in currentFilters
        let currentFilters = currentFilters

        // Check each category type to find which one is empty in base but not in current
        if !currentFilters.regions.isEmpty && baseFilters.regions.isEmpty {
            selectedCategoryToRemove = .regions
        } else if !currentFilters.mrcs.isEmpty && baseFilters.mrcs.isEmpty {
            selectedCategoryToRemove = .mrcs
        } else if !currentFilters.municipalities.isEmpty && baseFilters.municipalities.isEmpty {
            selectedCategoryToRemove = .municipalities
        } else if !currentFilters.vehicleClasses.isEmpty && baseFilters.vehicleClasses.isEmpty {
            selectedCategoryToRemove = .vehicleClasses
        } else if !currentFilters.vehicleTypes.isEmpty && baseFilters.vehicleTypes.isEmpty {
            selectedCategoryToRemove = .vehicleTypes
        } else if !currentFilters.fuelTypes.isEmpty && baseFilters.fuelTypes.isEmpty {
            selectedCategoryToRemove = .fuelTypes
        } else if !currentFilters.vehicleMakes.isEmpty && baseFilters.vehicleMakes.isEmpty {
            selectedCategoryToRemove = .vehicleMakes
        } else if !currentFilters.vehicleModels.isEmpty && baseFilters.vehicleModels.isEmpty {
            selectedCategoryToRemove = .vehicleModels
        } else if !currentFilters.vehicleColors.isEmpty && baseFilters.vehicleColors.isEmpty {
            selectedCategoryToRemove = .vehicleColors
        } else if !currentFilters.modelYears.isEmpty && baseFilters.modelYears.isEmpty {
            selectedCategoryToRemove = .modelYears
        } else if !currentFilters.ageRanges.isEmpty && baseFilters.ageRanges.isEmpty {
            selectedCategoryToRemove = .ageRanges
        } else if !currentFilters.licenseTypes.isEmpty && baseFilters.licenseTypes.isEmpty {
            selectedCategoryToRemove = .licenseTypes
        } else if !currentFilters.ageGroups.isEmpty && baseFilters.ageGroups.isEmpty {
            selectedCategoryToRemove = .ageGroups
        } else if !currentFilters.genders.isEmpty && baseFilters.genders.isEmpty {
            selectedCategoryToRemove = .genders
        } else if !currentFilters.experienceLevels.isEmpty && baseFilters.experienceLevels.isEmpty {
            selectedCategoryToRemove = .experienceLevels
        } else if !currentFilters.licenseClasses.isEmpty && baseFilters.licenseClasses.isEmpty {
            selectedCategoryToRemove = .licenseClasses
        }

        // Silently restore UI state from saved configuration
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
        case .median:
            switch metricField {
            case .netMass:
                return "Median vehicle weight"
            case .displacement:
                return "Median engine displacement"
            case .cylinderCount:
                return "Median cylinders per vehicle"
            case .vehicleAge:
                return "Median age of vehicles"
            case .modelYear:
                return "Median model year"
            default:
                return "Median \(metricField.rawValue)"
            }
        case .minimum:
            switch metricField {
            case .netMass:
                return "Minimum vehicle weight"
            case .displacement:
                return "Minimum engine displacement"
            case .cylinderCount:
                return "Minimum cylinders per vehicle"
            case .vehicleAge:
                return "Minimum age of vehicles"
            case .modelYear:
                return "Minimum model year"
            default:
                return "Minimum \(metricField.rawValue)"
            }
        case .maximum:
            switch metricField {
            case .netMass:
                return "Maximum vehicle weight"
            case .displacement:
                return "Maximum engine displacement"
            case .cylinderCount:
                return "Maximum cylinders per vehicle"
            case .vehicleAge:
                return "Maximum age of vehicles"
            case .modelYear:
                return "Maximum model year"
            default:
                return "Maximum \(metricField.rawValue)"
            }
        case .percentage:
            return "Percentage of baseline category"
        case .coverage:
            if let field = coverageField {
                return coverageAsPercentage
                    ? "Percentage of records with non-NULL \(field.rawValue)"
                    : "Count of NULL \(field.rawValue) values"
            } else {
                return "Select a field to analyze coverage"
            }
        case .roadWearIndex:
            switch currentFilters.roadWearIndexMode {
            case .average:
                return "Average road wear index (4th power law)"
            case .median:
                return "Median road wear index (4th power law)"
            case .sum:
                return "Total road wear index (4th power law)"
            }
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
                    .foregroundStyle(.secondary)

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
                    .foregroundStyle(.secondary)

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
                    .foregroundStyle(.secondary)

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
                    .foregroundStyle(.secondary)

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
                    .foregroundStyle(.secondary)

                SearchableFilterList(
                    items: availableLicenseClasses,
                    selectedItems: $selectedLicenseClasses,
                    searchPrompt: "Search license classes..."
                )
            }
        }
    }
}

// MARK: - Filter Options Section

struct FilterOptionsSection: View {
    @Binding var limitToCuratedYears: Bool
    @AppStorage("limitToCuratedYears") private var limitToCuratedYearsStorage = true
    @AppStorage("regularizationEnabled") private var regularizationEnabled = false
    @AppStorage("regularizationCoupling") private var regularizationCoupling = true
    @EnvironmentObject var databaseManager: DatabaseManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Limit to Curated Years toggle
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(
                    get: { limitToCuratedYearsStorage },
                    set: { newValue in
                        limitToCuratedYearsStorage = newValue
                        limitToCuratedYears = newValue
                    }
                )) {
                    Text("Limit to Curated Years Only")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .onAppear {
                    // Sync binding with storage on appear
                    limitToCuratedYears = limitToCuratedYearsStorage
                }

                Text(limitToCuratedYears
                    ? "Showing only data from curated years (filters exclude uncurated Make/Model pairs)"
                    : "Showing all years (uncurated items marked with badges)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }

            // Query Regularization toggle (only visible when NOT limiting to curated years)
            // Regularization only applies to uncurated years (2023-2024)
            if !limitToCuratedYears {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $regularizationEnabled) {
                        Text("Enable Query Regularization")
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Text(regularizationEnabled
                        ? "Queries merge uncurated Make/Model variants into canonical values"
                        : "Uncurated Make/Model variants remain separate")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)

                    // Coupling toggle (only visible when regularization is enabled)
                    if regularizationEnabled {
                        Toggle(isOn: $regularizationCoupling) {
                            Text("Couple Make/Model in Queries")
                                .font(.caption)
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .padding(.top, 4)

                        Text(regularizationCoupling
                            ? "Filtering by Model includes associated Make"
                            : "Make and Model filters remain independent")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: regularizationEnabled) { _, newValue in
            updateRegularizationInQueryManager(enabled: newValue, coupling: regularizationCoupling)
        }
        .onChange(of: regularizationCoupling) { _, newValue in
            updateRegularizationInQueryManager(enabled: regularizationEnabled, coupling: newValue)
        }
    }

    private func updateRegularizationInQueryManager(enabled: Bool, coupling: Bool) {
        if let queryManager = databaseManager.optimizedQueryManager {
            queryManager.regularizationEnabled = enabled
            queryManager.regularizationCoupling = coupling
            if enabled {
                print("✅ Regularization ENABLED in queries (\(coupling ? "coupled" : "decoupled") mode)")
            } else {
                print("⚪️ Regularization DISABLED in queries")
            }
        }
    }
}

// MARK: - Draggable Divider

struct DraggableDivider: View {
    @Binding var height: CGFloat
    @State private var isDragging = false

    private let minHeight: CGFloat = 200
    private let maxHeight: CGFloat = 600

    var body: some View {
        HStack {
            Spacer()
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(isDragging ? Color.accentColor : Color.secondary)
                .font(.caption)
            Spacer()
        }
        .frame(height: 20)
        .background(isDragging ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    let newHeight = height + value.translation.height
                    height = min(max(newHeight, minHeight), maxHeight)
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }
}

// MARK: - Query Preview Bar (Persistent Bottom Bar)

struct QueryPreviewBar: View {
    let queryPreviewText: String
    let isLoading: Bool
    let onExecuteQuery: () -> Void
    let onClearAll: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                // Query preview text (scrollable if too long)
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .controlSize(.small)
                        Text("Generating preview...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if queryPreviewText.isEmpty {
                    Text("No query configured")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(queryPreviewText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }

                // Copy button
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(queryPreviewText, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .help("Copy query to clipboard")
                .disabled(queryPreviewText.isEmpty)

                Divider()
                    .frame(height: 28)

                // Clear filters button (X icon)
                Button(action: onClearAll) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("Clear all filters")

                // Execute Query button (like Play button) - on the right
                Button(action: onExecuteQuery) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                        Text("Execute")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isLoading || queryPreviewText.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }
}

