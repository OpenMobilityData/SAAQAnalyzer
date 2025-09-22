import SwiftUI

/// Filter panel for selecting data criteria
struct FilterPanel: View {
    @Binding var configuration: FilterConfiguration
    @EnvironmentObject var databaseManager: DatabaseManager
    
    // Available options loaded from database
    @State private var availableYears: [Int] = []
    @State private var availableRegions: [String] = []
    @State private var availableMRCs: [String] = []
    @State private var availableClassifications: [String] = []
    
    // Loading state
    @State private var isLoadingData = true
    @State private var hasInitiallyLoaded = false
    
    // Expansion states for sections
    @State private var yearSectionExpanded = true
    @State private var geographySectionExpanded = true
    @State private var vehicleSectionExpanded = true
    @State private var ageSectionExpanded = false
    
    // Selected geographic hierarchy
    @State private var selectedRegions: Set<String> = []
    @State private var selectedMRCs: Set<String> = []
    @State private var selectedMunicipalities: Set<String> = []
    
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
                            selectedYears: $configuration.years
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
                            selectedFuelTypes: $configuration.fuelTypes,
                            availableYears: availableYears,
                            availableClassifications: availableClassifications
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
            
            // Load all available options from database
            availableYears = await databaseManager.getAvailableYears()
            availableRegions = await databaseManager.getAvailableRegions()
            availableMRCs = await databaseManager.getAvailableMRCs()
            availableClassifications = await databaseManager.getAvailableClassifications()
            
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
        }
    }
    
    /// Clears all filter selections
    private func clearAllFilters() {
        configuration = FilterConfiguration()
        selectedRegions.removeAll()
        selectedMRCs.removeAll()
        selectedMunicipalities.removeAll()
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
    @Binding var configuration: FilterConfiguration
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Regions section
            if !availableRegions.isEmpty {
                Text("Administrative Regions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [GridItem(.flexible())], spacing: 4) {
                    ForEach(availableRegions, id: \.self) { region in
                        Toggle(region, isOn: Binding(
                            get: { configuration.regions.contains(region) },
                            set: { isSelected in
                                if isSelected {
                                    configuration.regions.insert(region)
                                } else {
                                    configuration.regions.remove(region)
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    }
                }
            }
            
            // MRCs section  
            if !availableMRCs.isEmpty {
                Divider()
                
                Text("MRCs")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [GridItem(.flexible())], spacing: 4) {
                    ForEach(availableMRCs, id: \.self) { mrc in
                        Toggle(mrc, isOn: Binding(
                            get: { configuration.mrcs.contains(mrc) },
                            set: { isSelected in
                                if isSelected {
                                    configuration.mrcs.insert(mrc)
                                } else {
                                    configuration.mrcs.remove(mrc)
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    }
                }
            }
            
            // Summary of selections
            if !configuration.regions.isEmpty || !configuration.mrcs.isEmpty {
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
    @Binding var selectedFuelTypes: Set<String>
    let availableYears: [Int]
    let availableClassifications: [String]
    
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
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(availableClassifications, id: \.self) { classification in
                        Toggle(getDisplayName(for: classification), isOn: Binding(
                            get: { selectedClassifications.contains(classification) },
                            set: { isSelected in
                                if isSelected {
                                    selectedClassifications.insert(classification)
                                } else {
                                    selectedClassifications.remove(classification)
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .help(getDescription(for: classification))  // Tooltip with description
                    }
                }
            }
            
            // Fuel types (only if 2017+ data is available)
            if hasFuelTypeYears {
                Divider()
                
                Text("Fuel Type (2017+)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(FuelType.allCases, id: \.rawValue) { fuelType in
                        Toggle(fuelType.description, isOn: Binding(
                            get: { selectedFuelTypes.contains(fuelType.rawValue) },
                            set: { isSelected in
                                if isSelected {
                                    selectedFuelTypes.insert(fuelType.rawValue)
                                } else {
                                    selectedFuelTypes.remove(fuelType.rawValue)
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
            }
        }
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
