import SwiftUI

/// Filter panel for selecting data criteria
struct FilterPanel: View {
    @Binding var configuration: FilterConfiguration
    @EnvironmentObject var databaseManager: DatabaseManager
    
    // Available options loaded from database
    @State private var availableYears: [Int] = []
    @State private var availableRegions: [String] = []
    @State private var availableMRCs: [String] = []
    @State private var availableMunicipalities: [String] = []
    @State private var availableClassifications: [String] = []
    @State private var availableVehicleMakes: [String] = []
    @State private var availableVehicleModels: [String] = []
    @State private var availableModelYears: [Int] = []

    // Municipality code-to-name mapping for UI display
    @State private var municipalityCodeToName: [String: String] = [:]
    
    // Loading state
    @State private var isLoadingData = true
    @State private var hasInitiallyLoaded = false
    
    // Expansion states for sections
    @State private var yearSectionExpanded = true
    @State private var geographySectionExpanded = true
    @State private var vehicleSectionExpanded = true
    @State private var ageSectionExpanded = false
    
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
                    
                    // Vehicle characteristics section
                    DisclosureGroup(isExpanded: $vehicleSectionExpanded) {
                        VehicleFilterSection(
                            selectedClassifications: $configuration.vehicleClassifications,
                            selectedVehicleMakes: $configuration.vehicleMakes,
                            selectedVehicleModels: $configuration.vehicleModels,
                            selectedModelYears: $configuration.modelYears,
                            selectedFuelTypes: $configuration.fuelTypes,
                            availableYears: availableYears,
                            availableClassifications: availableClassifications,
                            availableVehicleMakes: availableVehicleMakes,
                            availableVehicleModels: availableVehicleModels,
                            availableModelYears: availableModelYears
                        )
                    } label: {
                        Label("Vehicle Characteristics", systemImage: "car")
                            .font(.subheadline)
                    }
                    
                    Divider()
                    
                    // Age ranges section
                    DisclosureGroup(isExpanded: $ageSectionExpanded) {
                        AgeRangeFilterSection(ageRanges: $configuration.ageRanges)
                    } label: {
                        Label("Vehicle Age", systemImage: "clock")
                            .font(.subheadline)
                    }
                }
                .padding()
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            if !hasInitiallyLoaded {
                loadAvailableOptions()
            }
        }
        .onReceive(databaseManager.$dataVersion) { _ in
            // Only reload if we might have new years or geographic data
            // Skip reload if we're just replacing existing year data
            if hasInitiallyLoaded {
                Task {
                    await refreshIfNeeded()
                }
            }
        }
    }
    
    /// Loads available filter options from database
    private func loadAvailableOptions() {
        Task {
            isLoadingData = true
            
            // Check if we need to populate cache first
            let cacheInfo = databaseManager.filterCacheInfo
            print("🔍 Filter cache status: hasCache=\(cacheInfo.hasCache), years=\(cacheInfo.itemCounts.years)")
            if !cacheInfo.hasCache {
                print("💾 No filter cache found, populating cache before loading options...")
                await databaseManager.refreshFilterCache()
            } else {
                print("✅ Using existing filter cache")
            }
            
            // Load all available options from database/cache
            availableYears = await databaseManager.getAvailableYears()
            availableRegions = await databaseManager.getAvailableRegions()
            availableMRCs = await databaseManager.getAvailableMRCs()
            availableMunicipalities = await databaseManager.getAvailableMunicipalities()
            availableClassifications = await databaseManager.getAvailableClassifications()
            availableVehicleMakes = await databaseManager.getAvailableVehicleMakes()
            availableVehicleModels = await databaseManager.getAvailableVehicleModels()
            availableModelYears = await databaseManager.getAvailableModelYears()

            print("📊 Loaded filter options: \(availableYears.count) years, \(availableVehicleMakes.count) makes, \(availableVehicleModels.count) models, \(availableModelYears.count) model years")

            // Load municipality mapping for UI display
            municipalityCodeToName = await databaseManager.getMunicipalityCodeToNameMapping()
            
            isLoadingData = false
            hasInitiallyLoaded = true
        }
    }
    
    /// Smart refresh that only updates if there are actual changes
    private func refreshIfNeeded() async {
        // Check if years have changed (most common update)
        let newYears = await databaseManager.getAvailableYears()
        
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
            availableRegions = await databaseManager.getAvailableRegions()
            availableMRCs = await databaseManager.getAvailableMRCs()
            availableMunicipalities = await databaseManager.getAvailableMunicipalities()
            municipalityCodeToName = await databaseManager.getMunicipalityCodeToNameMapping()
        }
    }
    
    /// Clears all filter selections
    private func clearAllFilters() {
        configuration = FilterConfiguration()
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
    @Binding var selectedModelYears: Set<Int>
    @Binding var selectedFuelTypes: Set<String>
    let availableYears: [Int]
    let availableClassifications: [String]
    let availableVehicleMakes: [String]
    let availableVehicleModels: [String]
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
