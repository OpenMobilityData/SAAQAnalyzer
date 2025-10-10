import SwiftUI
import Observation
import Combine

/// Main view for managing Make/Model regularization mappings
struct RegularizationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RegularizationViewModel

    init(databaseManager: DatabaseManager, yearConfig: RegularizationYearConfiguration) {
        _viewModel = StateObject(wrappedValue: RegularizationViewModel(
            databaseManager: databaseManager,
            yearConfig: yearConfig
        ))
    }

    var body: some View {
        NavigationView {
            // Left panel: Uncurated pairs list
            UncuratedPairsListView(viewModel: viewModel)
                .frame(minWidth: 400)

            // Right panel: Mapping editor
            MappingEditorView(viewModel: viewModel)
                .frame(minWidth: 600)
        }
        .navigationTitle("Make/Model Regularization")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }

                    Button("Refresh") {
                        Task {
                            await viewModel.loadUncuratedPairs()
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .task {
            await viewModel.loadInitialData()
        }
        .frame(minWidth: 1000, minHeight: 700)
    }
}

// MARK: - Left Panel: Uncurated Pairs List

struct UncuratedPairsListView: View {
    @ObservedObject var viewModel: RegularizationViewModel
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .recordCountDescending
    @State private var showUnassigned = true
    @State private var showNeedsReview = true
    @State private var showComplete = true

    enum SortOrder: String, CaseIterable {
        case recordCountDescending = "Record Count (High to Low)"
        case recordCountAscending = "Record Count (Low to High)"
        case makeModelAlphabetical = "Make/Model (A-Z)"
        case percentageDescending = "Percentage (High to Low)"
    }

    var filteredAndSortedPairs: [UnverifiedMakeModelPair] {
        var pairs = viewModel.uncuratedPairs

        // Filter by search text
        if !searchText.isEmpty {
            pairs = pairs.filter { pair in
                pair.makeName.localizedCaseInsensitiveContains(searchText) ||
                pair.modelName.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Filter by status
        pairs = pairs.filter { pair in
            let status = viewModel.getRegularizationStatus(for: pair)
            switch status {
            case .none:
                return showUnassigned
            case .needsReview:
                return showNeedsReview
            case .fullyRegularized:
                return showComplete
            }
        }

        // Sort
        switch sortOrder {
        case .recordCountDescending:
            pairs.sort { $0.recordCount > $1.recordCount }
        case .recordCountAscending:
            pairs.sort { $0.recordCount < $1.recordCount }
        case .makeModelAlphabetical:
            pairs.sort { $0.makeModelDisplay < $1.makeModelDisplay }
        case .percentageDescending:
            pairs.sort { $0.percentageOfTotal > $1.percentageOfTotal }
        }

        return pairs
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Text("Uncurated Make/Model Pairs")
                    .font(.headline)

                // Search field
                TextField("Search Make or Model...", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                // Sort picker
                Picker("Sort by", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                // Status filters
                VStack(alignment: .leading, spacing: 6) {
                    Text("Show Status:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        StatusFilterButton(
                            isSelected: $showUnassigned,
                            label: "Unassigned",
                            color: .red
                        )

                        StatusFilterButton(
                            isSelected: $showNeedsReview,
                            label: "Needs Review",
                            color: .orange
                        )

                        StatusFilterButton(
                            isSelected: $showComplete,
                            label: "Complete",
                            color: .green
                        )
                    }
                }

                // Summary
                VStack(spacing: 4) {
                    HStack {
                        Text("\(filteredAndSortedPairs.count) pairs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let selected = viewModel.selectedPair {
                            Text("Selected: \(selected.makeName)/\(selected.modelName)")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }

                    // Regularization progress
                    let progress = viewModel.regularizationProgress
                    if progress.totalRecords > 0 {
                        HStack(spacing: 4) {
                            Text("Regularization Progress:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(progress.regularizedRecords.formatted()) / \(progress.totalRecords.formatted()) records")
                                .font(.caption)
                                .foregroundStyle(.primary)
                            Text("(\(progress.percentage, specifier: "%.1f")%)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(progress.percentage >= 100 ? .green : (progress.percentage >= 50 ? .orange : .red))
                        }
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))

            Divider()

            // List
            if viewModel.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading uncurated pairs...")
                    Spacer()
                }
            } else if filteredAndSortedPairs.isEmpty {
                VStack {
                    Spacer()
                    Text(searchText.isEmpty ? "No uncurated pairs found" : "No matches for \"\(searchText)\"")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(selection: $viewModel.selectedPair) {
                    ForEach(filteredAndSortedPairs) { pair in
                        UncuratedPairRow(
                            pair: pair,
                            regularizationStatus: viewModel.getRegularizationStatus(for: pair)
                        )
                        .tag(pair)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct UncuratedPairRow: View {
    let pair: UnverifiedMakeModelPair
    let regularizationStatus: RegularizationStatus

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            statusIndicator
                .frame(width: 8, height: 8)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(pair.makeModelDisplay)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                    Spacer()
                }

                HStack(spacing: 12) {
                    Label("\(pair.recordCount.formatted())", systemImage: "number")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label(String(format: "%.2f%%", pair.percentageOfTotal), systemImage: "percent")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label(String(format: "%d–%d", pair.earliestYear, pair.latestYear), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Regularization status badge
                    statusBadge
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch regularizationStatus {
        case .none:
            Circle()
                .fill(Color.red)
        case .needsReview:
            Circle()
                .fill(Color.orange)
        case .fullyRegularized:
            Circle()
                .fill(Color.green)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch regularizationStatus {
        case .none:
            Text("Unassigned")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.2))
                .foregroundColor(.red)
                .cornerRadius(4)
        case .needsReview:
            Text("Needs Review")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.2))
                .foregroundColor(.orange)
                .cornerRadius(4)
        case .fullyRegularized:
            Text("Complete")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.2))
                .foregroundColor(.green)
                .cornerRadius(4)
        }
    }
}

/// Regularization status for an uncurated pair
enum RegularizationStatus {
    case none                   // 🔴 No mapping exists
    case needsReview            // 🟠 Mapping exists but FuelType/VehicleType are NULL (needs user review)
    case fullyRegularized       // 🟢 Mapping exists with both fields assigned (including "Unknown")
}

// MARK: - Right Panel: Mapping Editor

struct MappingEditorView: View {
    @ObservedObject var viewModel: RegularizationViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Regularization Mapping Editor")
                    .font(.headline)

                if let pair = viewModel.selectedPair {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Uncurated Pair")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(pair.makeName) / \(pair.modelName)")
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(pair.recordCount.formatted()) records")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f%% of uncurated", pair.percentageOfTotal))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))

            Divider()

            // Mapping form
            if viewModel.selectedPair != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        MappingFormView(viewModel: viewModel)
                    }
                    .padding()
                }
            } else {
                VStack {
                    Spacer()
                    Text("Select an uncurated pair to begin mapping")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }
}

struct MappingFormView: View {
    @ObservedObject var viewModel: RegularizationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Step 1: Select Canonical Make
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("1. Select Canonical Make")
                        .font(.headline)
                    Spacer()
                    if viewModel.selectedCanonicalMake != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }

                if viewModel.isLoadingHierarchy {
                    ProgressView("Loading canonical hierarchy...")
                } else if viewModel.canonicalHierarchy == nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Canonical hierarchy not generated yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Generate Canonical Hierarchy") {
                            Task {
                                await viewModel.generateHierarchy()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Picker("Make", selection: $viewModel.selectedCanonicalMake) {
                        Text("Select Make...").tag(nil as MakeModelHierarchy.Make?)
                        ForEach(viewModel.canonicalHierarchy?.makes ?? []) { make in
                            Text(make.name).tag(make as MakeModelHierarchy.Make?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)

            // Step 2: Select Canonical Model
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("2. Select Canonical Model")
                        .font(.headline)
                    Spacer()
                    if viewModel.selectedCanonicalModel != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }

                if let make = viewModel.selectedCanonicalMake {
                    Picker("Model", selection: $viewModel.selectedCanonicalModel) {
                        Text("Select Model...").tag(nil as MakeModelHierarchy.Model?)
                        ForEach(make.models) { model in
                            Text(model.name).tag(model as MakeModelHierarchy.Model?)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Text("Select a make first")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)

            // Step 3: Select Vehicle Type (optional)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("3. Select Vehicle Type (Optional)")
                        .font(.headline)
                    Spacer()
                    if let vehicleType = viewModel.selectedVehicleType {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .onAppear {
                                print("✓ VehicleType checkmark: \(vehicleType.code) - \(vehicleType.description)")
                            }
                    }
                }

                Text("Leave unset if uncertain or multiple vehicle types exist")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let model = viewModel.selectedCanonicalModel {
                    Picker("Vehicle Type", selection: $viewModel.selectedVehicleType) {
                        Text("Not Assigned").tag(nil as MakeModelHierarchy.VehicleTypeInfo?)

                        // Special "Unknown" option (not in hierarchy since it doesn't appear in curated years)
                        Text("UK - Unknown").tag(MakeModelHierarchy.VehicleTypeInfo(
                            id: -1,  // Placeholder ID - will be looked up from enum table when saving
                            code: "UK",  // Unknown vehicle type (user-assigned when type cannot be determined)
                            description: "Unknown",
                            recordCount: 0
                        ) as MakeModelHierarchy.VehicleTypeInfo?)

                        ForEach(model.vehicleTypes) { vehicleType in
                            HStack {
                                Text("\(vehicleType.code) - \(vehicleType.description)")
                                Text("(\(vehicleType.recordCount.formatted()))")
                                    .foregroundStyle(.secondary)
                            }
                            .tag(vehicleType as MakeModelHierarchy.VehicleTypeInfo?)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Text("Select a model first")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)

            // Step 4: Select Fuel Types by Model Year (Radio Button UI)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("4. Select Fuel Type by Model Year")
                        .font(.headline)
                    Spacer()
                    if let model = viewModel.selectedCanonicalModel,
                       viewModel.allFuelTypesAssigned(for: model) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }

                Text("Select ONE fuel type for each year. Choose 'Unknown' if the year has multiple fuel types and cannot be disambiguated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let model = viewModel.selectedCanonicalModel {
                    FuelTypeYearSelectionView(model: model, viewModel: viewModel)
                } else {
                    Text("Select a model first")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)

            // Action buttons
            HStack(spacing: 12) {
                Button("Clear Selection") {
                    viewModel.clearMappingSelection()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedCanonicalMake == nil)

                Spacer()

                Button("Save Mapping") {
                    Task {
                        await viewModel.saveMapping()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSaveMapping || viewModel.isSaving)

                if viewModel.isSaving {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.top)
        }
    }
}

// MARK: - Fuel Type Year Selection View

struct FuelTypeYearSelectionView: View {
    let model: MakeModelHierarchy.Model
    @ObservedObject var viewModel: RegularizationViewModel
    @State private var showOnlyNotAssigned = false

    var body: some View {
        VStack(spacing: 8) {
            // Filter toggle
            HStack {
                Toggle(isOn: $showOnlyNotAssigned) {
                    HStack(spacing: 4) {
                        Image(systemName: showOnlyNotAssigned ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundColor(showOnlyNotAssigned ? .blue : .secondary)
                        Text("Show only Not Assigned")
                            .font(.caption)
                            .foregroundStyle(showOnlyNotAssigned ? .primary : .secondary)
                    }
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)

                Spacer()

                Text("\(filteredYears.count) of \(sortedYears.count) years")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredYears, id: \.self) { yearId in
                        if let yearId = yearId, let fuelTypes = model.modelYearFuelTypes[yearId] {
                            ModelYearFuelTypeRow(
                                yearId: yearId,
                                fuelTypes: fuelTypes,
                                viewModel: viewModel
                            )
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 400)
        }
        .background(Color.gray.opacity(0.03))
        .cornerRadius(6)
    }

    private var sortedYears: [Int?] {
        model.modelYearFuelTypes.keys.sorted { yearId1, yearId2 in
            guard let id1 = yearId1, let fuelTypes1 = model.modelYearFuelTypes[id1], let year1 = fuelTypes1.first?.modelYear else { return false }
            guard let id2 = yearId2, let fuelTypes2 = model.modelYearFuelTypes[id2], let year2 = fuelTypes2.first?.modelYear else { return true }
            return year1 < year2
        }
    }

    private var filteredYears: [Int?] {
        if showOnlyNotAssigned {
            return sortedYears.filter { yearId in
                guard let yearId = yearId else { return false }
                return viewModel.getSelectedFuelType(forYearId: yearId) == nil
            }
        } else {
            return sortedYears
        }
    }
}

struct ModelYearFuelTypeRow: View {
    let yearId: Int
    let fuelTypes: [MakeModelHierarchy.FuelTypeInfo]
    @ObservedObject var viewModel: RegularizationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Year header
            Text("Model Year \(String(fuelTypes.first?.modelYear ?? 0))")
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            // Radio button options
            VStack(alignment: .leading, spacing: 4) {
                // Option 1: Not Assigned (default)
                RadioButtonRow(
                    label: "Not Assigned",
                    isSelected: viewModel.getSelectedFuelType(forYearId: yearId) == nil,
                    action: { viewModel.setFuelType(yearId: yearId, fuelTypeId: nil) }
                )
                .foregroundColor(.secondary)

                // Option 2: Unknown
                RadioButtonRow(
                    label: "Unknown",
                    isSelected: viewModel.getSelectedFuelType(forYearId: yearId) == -1,
                    action: { viewModel.setFuelType(yearId: yearId, fuelTypeId: -1) }
                )
                .foregroundColor(.orange)

                Divider()

                // Options 3+: Actual fuel types (filtered)
                ForEach(validFuelTypes) { fuelType in
                    RadioButtonRow(
                        label: "\(fuelType.description) (\(fuelType.recordCount.formatted()))",
                        isSelected: viewModel.getSelectedFuelType(forYearId: yearId) == fuelType.id,
                        action: { viewModel.setFuelType(yearId: yearId, fuelTypeId: fuelType.id) }
                    )
                }
            }
            .padding(.leading, 8)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(6)
    }

    private var validFuelTypes: [MakeModelHierarchy.FuelTypeInfo] {
        fuelTypes.filter { fuelType in
            !fuelType.description.localizedCaseInsensitiveContains("not specified") &&
            !fuelType.description.localizedCaseInsensitiveContains("not assigned") &&
            !fuelType.description.localizedCaseInsensitiveContains("non spécifié")
        }
    }
}

// MARK: - View Model

@MainActor
class RegularizationViewModel: ObservableObject {
    private let databaseManager: DatabaseManager
    private var regularizationManager: RegularizationManager? {
        databaseManager.regularizationManager
    }

    @Published var yearConfig: RegularizationYearConfiguration
    @Published var uncuratedPairs: [UnverifiedMakeModelPair] = []
    @Published var canonicalHierarchy: MakeModelHierarchy?
    @Published var selectedPair: UnverifiedMakeModelPair? {
        didSet {
            // Load existing mapping when selection changes
            if selectedPair != oldValue {
                Task { @MainActor in
                    await loadMappingForSelectedPair()
                }
            }
        }
    }
    @Published var existingMappings: [String: [RegularizationMapping]] = [:] // Key: "\(makeId)_\(modelId)" → Array of mappings (triplets + wildcard)

    // Mapping form state
    @Published var selectedCanonicalMake: MakeModelHierarchy.Make?
    @Published var selectedCanonicalModel: MakeModelHierarchy.Model? {
        didSet {
            // Clear fuel type selections when model changes
            if selectedCanonicalModel?.id != oldValue?.id {
                selectedFuelTypesByYear = [:]
            }
        }
    }
    @Published var selectedVehicleType: MakeModelHierarchy.VehicleTypeInfo?

    // Year-based fuel type selections for table UI (single selection per year)
    // Dictionary: modelYearId → fuelTypeId (or nil for "Not Assigned", -1 for "Unknown")
    @Published var selectedFuelTypesByYear: [Int: Int?] = [:]

    // Loading states
    @Published var isLoading = false
    @Published var isLoadingHierarchy = false
    @Published var isSaving = false
    @Published var isAutoRegularizing = false

    var canSaveMapping: Bool {
        selectedPair != nil &&
        selectedCanonicalMake != nil &&
        selectedCanonicalModel != nil
    }

    /// Calculate regularization progress based on total records
    var regularizationProgress: (regularizedRecords: Int, totalRecords: Int, percentage: Double) {
        let totalRecords = uncuratedPairs.reduce(0) { $0 + $1.recordCount }

        // Count records that have mappings (check if array is non-empty)
        var regularizedRecords = 0
        for pair in uncuratedPairs {
            let mappings = getMappingsForPair(pair.makeId, pair.modelId)
            if !mappings.isEmpty {
                regularizedRecords += pair.recordCount
            }
        }

        let percentage = totalRecords > 0 ? (Double(regularizedRecords) / Double(totalRecords)) * 100.0 : 0.0
        return (regularizedRecords, totalRecords, percentage)
    }

    init(databaseManager: DatabaseManager, yearConfig: RegularizationYearConfiguration) {
        self.databaseManager = databaseManager
        self.yearConfig = yearConfig
    }

    func loadInitialData() async {
        // Update year configuration in manager
        if let manager = regularizationManager {
            manager.setYearConfiguration(yearConfig)
        }

        // Load existing mappings
        await loadExistingMappings()

        // Load uncurated pairs
        await loadUncuratedPairs()

        // Auto-regularize exact matches
        await autoRegularizeExactMatches()
    }

    func loadExistingMappings() async {
        guard let manager = regularizationManager else { return }

        do {
            let mappings = try await manager.getAllMappings()
            var mappingsDict: [String: [RegularizationMapping]] = [:]

            // Group mappings by Make/Model pair (multiple mappings per pair for triplets)
            for mapping in mappings {
                let key = mapping.uncuratedKey
                if mappingsDict[key] == nil {
                    mappingsDict[key] = []
                }
                mappingsDict[key]?.append(mapping)
            }

            await MainActor.run {
                existingMappings = mappingsDict
            }

            // Count unique pairs vs total mappings (including triplets)
            let uniquePairs = mappingsDict.count
            let totalMappings = mappings.count
            if totalMappings > uniquePairs {
                print("✅ Loaded \(totalMappings) mappings (\(uniquePairs) pairs, \(totalMappings - uniquePairs) triplets)")
            } else {
                print("✅ Loaded \(mappings.count) existing mappings")
            }
        } catch {
            print("❌ Error loading existing mappings: \(error)")
        }
    }

    func loadUncuratedPairs() async {
        guard let manager = regularizationManager else {
            print("❌ RegularizationManager not available")
            return
        }

        await MainActor.run {
            isLoading = true
        }

        do {
            // Always load all pairs (including exact matches) - filtering is done in UI by status
            let pairs = try await manager.findUncuratedPairs(includeExactMatches: true)
            await MainActor.run {
                uncuratedPairs = pairs
                isLoading = false
            }
            print("✅ Loaded \(pairs.count) uncurated pairs")
        } catch {
            print("❌ Error loading uncurated pairs: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }

    func generateHierarchy() async {
        guard let manager = regularizationManager else {
            print("❌ RegularizationManager not available")
            return
        }

        await MainActor.run {
            isLoadingHierarchy = true
        }

        do {
            let hierarchy = try await manager.generateCanonicalHierarchy(forceRefresh: true)
            await MainActor.run {
                canonicalHierarchy = hierarchy
                isLoadingHierarchy = false
            }
            print("✅ Generated hierarchy with \(hierarchy.makes.count) makes")
        } catch {
            print("❌ Error generating hierarchy: \(error)")
            await MainActor.run {
                isLoadingHierarchy = false
            }
        }
    }

    func saveMapping() async {
        guard let manager = regularizationManager,
              let pair = selectedPair,
              let canonicalMake = selectedCanonicalMake,
              let canonicalModel = selectedCanonicalModel else {
            return
        }

        isSaving = true

        do {
            // Resolve vehicle type ID (handle "Unknown" placeholder)
            var vehicleTypeId = selectedVehicleType?.id

            if let vehicleType = selectedVehicleType, vehicleType.id == -1 {
                print("🔍 Resolving placeholder VehicleType ID -1 (code: \(vehicleType.code))")
                let enumManager = CategoricalEnumManager(databaseManager: databaseManager)
                if let resolvedId = try await enumManager.getEnumId(
                    table: "vehicle_type_enum",
                    column: "code",
                    value: vehicleType.code
                ) {
                    vehicleTypeId = resolvedId
                    print("✅ Resolved VehicleType '\(vehicleType.code)' to ID \(resolvedId)")
                } else {
                    print("❌ ERROR: Failed to resolve VehicleType '\(vehicleType.code)' - will save as NULL!")
                    vehicleTypeId = nil
                }
            }

            // STEP 1: Create ONE wildcard mapping with VehicleType only (FuelType = NULL)
            try await manager.saveMapping(
                uncuratedMakeId: pair.makeId,
                uncuratedModelId: pair.modelId,
                modelYearId: nil,  // Wildcard (applies to all years)
                canonicalMakeId: canonicalMake.id,
                canonicalModelId: canonicalModel.id,
                fuelTypeId: nil,   // FuelType will be set by triplets
                vehicleTypeId: vehicleTypeId
            )

            print("✅ Saved wildcard mapping: \(pair.makeModelDisplay) → \(canonicalMake.name)/\(canonicalModel.name), VehicleType=\(selectedVehicleType?.description ?? "NULL")")

            // STEP 2: Create triplet mappings for ALL model years (with user selections or NULL)
            var tripletCount = 0
            var assignedCount = 0
            var unknownCount = 0

            if let model = selectedCanonicalModel {
                for (yearId, fuelTypes) in model.modelYearFuelTypes {
                    guard let yearId = yearId else { continue }

                    // Get user selection for this year (nil = Not Assigned, -1 = Unknown, or specific ID)
                    let selectedFuelTypeId = selectedFuelTypesByYear[yearId] ?? nil

                    // Resolve -1 (Unknown placeholder) to actual Unknown fuel type ID
                    var resolvedFuelTypeId = selectedFuelTypeId
                    if selectedFuelTypeId == -1 {
                        // Look up "Unknown" fuel type ID from enum table
                        let enumManager = CategoricalEnumManager(databaseManager: databaseManager)
                        resolvedFuelTypeId = try await enumManager.getEnumId(
                            table: "fuel_type_enum",
                            column: "code",
                            value: "U"
                        )
                        if resolvedFuelTypeId == nil {
                            print("⚠️ WARNING: 'Unknown' fuel type (code 'U') not found in enum table - saving as NULL")
                        } else {
                            unknownCount += 1
                        }
                    } else if selectedFuelTypeId != nil {
                        assignedCount += 1
                    }

                    // Create triplet mapping
                    try await manager.saveMapping(
                        uncuratedMakeId: pair.makeId,
                        uncuratedModelId: pair.modelId,
                        modelYearId: yearId,
                        canonicalMakeId: canonicalMake.id,
                        canonicalModelId: canonicalModel.id,
                        fuelTypeId: resolvedFuelTypeId,
                        vehicleTypeId: nil  // VehicleType set by wildcard
                    )
                    tripletCount += 1

                    // Log triplet creation
                    let yearValue = fuelTypes.first?.modelYear ?? 0
                    if let ftId = resolvedFuelTypeId, let fuelType = fuelTypes.first(where: { $0.id == ftId }) {
                        print("   ✓ Triplet: ModelYear \(yearValue) → FuelType=\(fuelType.code)")
                    } else if selectedFuelTypeId == -1 {
                        print("   ✓ Triplet: ModelYear \(yearValue) → FuelType=U (Unknown)")
                    } else {
                        print("   ✓ Triplet: ModelYear \(yearValue) → FuelType=NULL (Not Assigned)")
                    }
                }
            }

            print("✅ Saved \(tripletCount) triplet mappings (\(assignedCount) assigned, \(unknownCount) unknown, \(tripletCount - assignedCount - unknownCount) not assigned)")

            // Reload existing mappings to update status indicators
            await loadExistingMappings()

            // Reload the mapping for the current pair to show updated form fields
            await loadMappingForSelectedPair()

        } catch {
            print("❌ Error saving mapping: \(error)")
        }

        isSaving = false
    }

    func clearMappingSelection() {
        selectedPair = nil
        clearMappingFormFields()
    }

    func clearMappingFormFields() {
        selectedCanonicalMake = nil
        selectedCanonicalModel = nil
        selectedVehicleType = nil
        selectedFuelTypesByYear = [:]
    }

    // MARK: - Year-Based Fuel Type Selection Methods

    /// Get the selected fuel type ID for a given model year
    /// Returns: fuel type ID, -1 for "Unknown", or nil for "Not Assigned"
    func getSelectedFuelType(forYearId yearId: Int) -> Int? {
        return selectedFuelTypesByYear[yearId] ?? nil
    }

    /// Set the fuel type for a specific model year
    /// Pass nil for "Not Assigned", -1 for "Unknown", or a specific fuel type ID
    func setFuelType(yearId: Int, fuelTypeId: Int?) {
        selectedFuelTypesByYear[yearId] = fuelTypeId
    }

    /// Check if all model years have assigned fuel types (not "Not Assigned")
    /// Returns true if all years have either a specific fuel type or "Unknown" (-1)
    func allFuelTypesAssigned(for model: MakeModelHierarchy.Model) -> Bool {
        for (yearId, _) in model.modelYearFuelTypes {
            guard let yearId = yearId else { continue }
            let selection = selectedFuelTypesByYear[yearId] ?? nil
            if selection == nil {
                return false  // "Not Assigned" found
            }
        }
        return true
    }

    /// Auto-regularize pairs where Make/Model exactly match curated pairs
    func autoRegularizeExactMatches() async {
        guard let manager = regularizationManager else {
            print("❌ RegularizationManager not available")
            return
        }

        var hierarchy = canonicalHierarchy
        if hierarchy == nil {
            // Generate hierarchy if not already done
            await generateHierarchy()
            hierarchy = canonicalHierarchy
            guard hierarchy != nil else {
                print("❌ Failed to generate hierarchy")
                return
            }
        }

        isAutoRegularizing = true

        // Build a lookup of canonical Make/Model combinations with their metadata
        var canonicalPairs: [String: MakeModelHierarchy.Model] = [:]
        for make in hierarchy!.makes {
            for model in make.models {
                let key = "\(make.name)/\(model.name)"
                canonicalPairs[key] = model
            }
        }

        // Fetch ALL uncurated pairs including exact matches for auto-regularization
        // Don't rely on the uncuratedPairs array since it may have exact matches filtered out
        let allUncuratedPairs: [UnverifiedMakeModelPair]
        do {
            allUncuratedPairs = try await manager.findUncuratedPairs(includeExactMatches: true)
        } catch {
            print("❌ Error fetching uncurated pairs for auto-regularization: \(error)")
            isAutoRegularizing = false
            return
        }

        // Find uncurated pairs that exactly match
        var autoRegularizedCount = 0
        for pair in allUncuratedPairs {
            let pairKey = "\(pair.makeName)/\(pair.modelName)"

            // Check if this pair already has a mapping (check if array is non-empty)
            let mappings = getMappingsForPair(pair.makeId, pair.modelId)
            if !mappings.isEmpty {
                continue  // Already mapped
            }

            // Check if there's an exact match
            if let canonicalModel = canonicalPairs[pairKey] {
                // PHASE 2B: ModelYear-aware auto-regularization
                // Strategy:
                // 1. VehicleType: Create ONE wildcard pair mapping (model_year_id = NULL)
                // 2. FuelType: Create MULTIPLE triplet mappings (one per model year with single fuel type)

                // Filter valid vehicle types
                let validVehicleTypes = canonicalModel.vehicleTypes.filter { vehicleType in
                    !vehicleType.description.localizedCaseInsensitiveContains("not specified") &&
                    !vehicleType.description.localizedCaseInsensitiveContains("not assigned") &&
                    !vehicleType.description.localizedCaseInsensitiveContains("non spécifié")
                }

                // Determine VehicleType assignment using cardinal type matching
                let vehicleTypeId: Int? = {
                    if validVehicleTypes.count == 1 {
                        return validVehicleTypes.first?.id
                    }

                    if validVehicleTypes.count > 1 && AppSettings.shared.useCardinalTypes {
                        let cardinalCodes = AppSettings.shared.cardinalVehicleTypeCodes
                        for cardinalCode in cardinalCodes {
                            if let matchingType = validVehicleTypes.first(where: { $0.code == cardinalCode }) {
                                print("   🎯 Cardinal type match: \(cardinalCode) found among \(validVehicleTypes.map { $0.code }.joined(separator: ", "))")
                                return matchingType.id
                            }
                        }
                    }

                    return nil
                }()

                // Analyze FuelTypes by ModelYear
                // Build dictionary: modelYearId → [FuelTypeInfo] (filtered for valid fuel types)
                var fuelTypesByYear: [Int?: [MakeModelHierarchy.FuelTypeInfo]] = [:]

                for (modelYearId, fuelTypes) in canonicalModel.modelYearFuelTypes {
                    let validFuelTypes = fuelTypes.filter { fuelType in
                        !fuelType.description.localizedCaseInsensitiveContains("not specified") &&
                        !fuelType.description.localizedCaseInsensitiveContains("not assigned") &&
                        !fuelType.description.localizedCaseInsensitiveContains("non spécifié")
                    }

                    if !validFuelTypes.isEmpty {
                        fuelTypesByYear[modelYearId] = validFuelTypes
                    }
                }

                do {
                    // STEP 1: Create triplet mappings for model years with single fuel type
                    var tripletCount = 0
                    for (modelYearId, fuelTypes) in fuelTypesByYear {
                        if let modelYearId = modelYearId, fuelTypes.count == 1, let fuelType = fuelTypes.first {
                            // Single fuel type for this model year → create triplet mapping
                            try await manager.saveMapping(
                                uncuratedMakeId: pair.makeId,
                                uncuratedModelId: pair.modelId,
                                modelYearId: modelYearId,
                                canonicalMakeId: canonicalModel.makeId,
                                canonicalModelId: canonicalModel.id,
                                fuelTypeId: fuelType.id,
                                vehicleTypeId: nil  // Will be set by wildcard pair
                            )
                            tripletCount += 1
                            print("   ✓ Triplet: ModelYear \(fuelType.modelYear ?? 0) → FuelType=\(fuelType.code)")
                        }
                    }

                    // STEP 2: Create wildcard pair mapping for VehicleType only
                    // FuelType is ALWAYS set by triplets (year-specific), not wildcard
                    let wildcardFuelTypeId: Int? = nil

                    try await manager.saveMapping(
                        uncuratedMakeId: pair.makeId,
                        uncuratedModelId: pair.modelId,
                        modelYearId: nil,  // Wildcard (all years)
                        canonicalMakeId: canonicalModel.makeId,
                        canonicalModelId: canonicalModel.id,
                        fuelTypeId: wildcardFuelTypeId,
                        vehicleTypeId: vehicleTypeId
                    )

                    autoRegularizedCount += 1

                    // Log what was auto-assigned
                    var autoAssignedFields: [String] = ["M/M"]
                    if tripletCount > 0 {
                        autoAssignedFields.append("FuelType(\(tripletCount) triplets)")
                    }
                    // Note: wildcardFuelTypeId is always nil (FuelType set by triplets only)
                    if let vtId = vehicleTypeId {
                        let wasCardinalMatch = validVehicleTypes.count > 1 &&
                            AppSettings.shared.useCardinalTypes &&
                            validVehicleTypes.contains(where: {
                                $0.id == vtId && AppSettings.shared.cardinalVehicleTypeCodes.contains($0.code)
                            })
                        if wasCardinalMatch {
                            autoAssignedFields.append("VehicleType(Cardinal)")
                        } else {
                            autoAssignedFields.append("VehicleType")
                        }
                    }
                    print("✅ Auto-regularized: \(pairKey) [\(autoAssignedFields.joined(separator: ", "))]")
                } catch {
                    print("❌ Error auto-regularizing \(pairKey): \(error)")
                }
            }
        }

        if autoRegularizedCount > 0 {
            print("✅ Auto-regularized \(autoRegularizedCount) exact matches")
            // Reload mappings
            await loadExistingMappings()
        }

        isAutoRegularizing = false
    }

    /// Helper: Get all mappings for a Make/Model pair (includes triplets and wildcards)
    func getMappingsForPair(_ makeId: Int, _ modelId: Int) -> [RegularizationMapping] {
        let key = "\(makeId)_\(modelId)"
        return existingMappings[key] ?? []
    }

    /// Helper: Get the wildcard mapping for a pair (model_year_id = NULL)
    func getWildcardMapping(for pair: UnverifiedMakeModelPair) -> RegularizationMapping? {
        return getMappingsForPair(pair.makeId, pair.modelId).first { $0.modelYearId == nil }
    }

    /// Get regularization status for a pair
    /// Status logic:
    /// - 🟢 Complete: VehicleType assigned AND ALL triplets have assigned fuel types (including "Unknown", but NOT "Not Assigned"/NULL)
    /// - 🟠 Needs Review: VehicleType assigned OR some triplets have assigned fuel types (partial work done)
    /// - 🔴 Unassigned: No mappings exist
    func getRegularizationStatus(for pair: UnverifiedMakeModelPair) -> RegularizationStatus {
        let key = "\(pair.makeId)_\(pair.modelId)"

        guard let mappings = existingMappings[key], !mappings.isEmpty else {
            return .none  // 🔴 No mapping exists
        }

        // Separate wildcard and triplet mappings
        let wildcardMapping = mappings.first { $0.modelYearId == nil }
        let tripletMappings = mappings.filter { $0.modelYearId != nil }

        // Check if vehicle type is assigned (should be in wildcard)
        let hasVehicleType = wildcardMapping?.vehicleType != nil

        // CRITICAL: Check if ALL model years have triplets AND all triplets have ASSIGNED fuel types
        // "Unknown" counts as assigned, but NULL does not
        // If there are no triplets at all, we consider this "needs review"
        let allTripletsHaveFuelType: Bool
        if tripletMappings.isEmpty {
            allTripletsHaveFuelType = false  // No triplets = incomplete
        } else {
            // Check that ALL triplets have non-NULL fuel types
            let allExistingTripletsAssigned = tripletMappings.allSatisfy { $0.fuelType != nil }

            // Also check that we have a year-specific mapping for EVERY model year
            // Get expected model years from canonical hierarchy
            var expectedYearCount: Int?
            if let wildcardMapping = wildcardMapping,
               let hierarchy = canonicalHierarchy {

                let canonicalMakeName = wildcardMapping.canonicalMake
                let canonicalModelName = wildcardMapping.canonicalModel

                // Find the canonical model in hierarchy
                if let make = hierarchy.makes.first(where: { $0.name == canonicalMakeName }),
                   let model = make.models.first(where: { $0.name == canonicalModelName }) {
                    expectedYearCount = model.modelYearFuelTypes.count
                }
            }

            // If we can determine expected year count, check that we have all triplets
            if let expectedYearCount = expectedYearCount {
                allTripletsHaveFuelType = allExistingTripletsAssigned &&
                                          tripletMappings.count == expectedYearCount
            } else {
                // Fallback: just check existing triplets (old behavior)
                allTripletsHaveFuelType = allExistingTripletsAssigned
            }

            // DEBUG: Log triplet fuel type status for HONDA/CIVIC
            if pair.makeName == "HONDA" && pair.modelName == "CIVIC" {
                print("🔍 DEBUG Status Check for HONDA/CIVIC:")
                print("   Total triplets in DB: \(tripletMappings.count)")
                print("   Expected model years: \(expectedYearCount ?? -1)")
                print("   Has VehicleType: \(hasVehicleType)")
                print("   All existing triplets assigned: \(allExistingTripletsAssigned)")
                print("   All triplets have fuel type: \(allTripletsHaveFuelType)")
                for (index, triplet) in tripletMappings.enumerated() {
                    let ftStatus = triplet.fuelType != nil ? "✓ \(triplet.fuelType!)" : "✗ NULL"
                    print("   Triplet \(index + 1): ModelYear=\(triplet.modelYear ?? 0), FuelType=\(ftStatus)")
                }
            }
        }

        if hasVehicleType && allTripletsHaveFuelType {
            return .fullyRegularized  // 🟢 VehicleType assigned AND all fuel types assigned (including "Unknown")
        } else if hasVehicleType || tripletMappings.contains(where: { $0.fuelType != nil }) {
            return .needsReview  // 🟠 Partial assignment - some work done but not complete
        } else {
            return .none  // 🔴 No meaningful assignments yet
        }
    }

    /// Load existing mapping data for the selected pair
    func loadMappingForSelectedPair() async {
        guard let pair = selectedPair else {
            clearMappingFormFields()
            return
        }

        // Ensure hierarchy is loaded
        var hierarchy = canonicalHierarchy
        if hierarchy == nil {
            await generateHierarchy()
            hierarchy = canonicalHierarchy
            guard hierarchy != nil else {
                print("❌ Failed to generate hierarchy for mapping lookup")
                clearMappingFormFields()
                return
            }
        }

        // Get the wildcard mapping for this pair (form editor uses wildcard for UI display)
        let mapping = getWildcardMapping(for: pair)

        // Try to find canonical Make/Model for this pair
        // First check if there's an existing mapping
        var canonicalMakeName: String?
        var canonicalModelName: String?

        if let mapping = mapping {
            // Use wildcard mapping's canonical values
            canonicalMakeName = mapping.canonicalMake
            canonicalModelName = mapping.canonicalModel
        } else {
            // Check if this is an exact match to a canonical pair
            let pairKey = "\(pair.makeName)/\(pair.modelName)"
            for make in hierarchy!.makes {
                for model in make.models {
                    if "\(make.name)/\(model.name)" == pairKey {
                        canonicalMakeName = make.name
                        canonicalModelName = model.name
                        break
                    }
                }
                if canonicalMakeName != nil { break }
            }
        }

        // Pre-populate dropdowns if we found canonical values
        if let canonicalMakeName = canonicalMakeName,
           let canonicalModelName = canonicalModelName {

            if let make = hierarchy!.makes.first(where: { $0.name == canonicalMakeName }) {
                selectedCanonicalMake = make

                // Find the canonical model
                if let model = make.models.first(where: { $0.name == canonicalModelName }) {
                    selectedCanonicalModel = model

                    // Reset type selections first (in case mapping has NULL values)
                    selectedVehicleType = nil

                    // Find the vehicle type if assigned (only from existing mapping)
                    if let mapping = mapping, let vehicleTypeName = mapping.vehicleType {
                        if vehicleTypeName == "Unknown" {
                            // Create special "Unknown" instance (matches picker option)
                            selectedVehicleType = MakeModelHierarchy.VehicleTypeInfo(
                                id: -1,
                                code: "UK",  // Unknown vehicle type (user-assigned)
                                description: "Unknown",
                                recordCount: 0
                            )
                        } else {
                            selectedVehicleType = model.vehicleTypes.first { $0.description == vehicleTypeName }
                        }
                    }

                    // Populate year-based fuel type radio selections from triplet mappings
                    selectedFuelTypesByYear = [:]
                    let allMappings = getMappingsForPair(pair.makeId, pair.modelId)

                    for mapping in allMappings {
                        // Only process triplet mappings (those with model_year_id set)
                        if let yearId = mapping.modelYearId {
                            if let fuelTypeName = mapping.fuelType {
                                // Check if this is "Unknown"
                                if fuelTypeName == "Unknown" {
                                    selectedFuelTypesByYear[yearId] = -1
                                } else {
                                    // Find the fuel type ID by matching description
                                    if let yearFuelTypes = model.modelYearFuelTypes[yearId],
                                       let fuelType = yearFuelTypes.first(where: { $0.description == fuelTypeName }) {
                                        selectedFuelTypesByYear[yearId] = fuelType.id
                                    }
                                }
                            } else {
                                // Fuel type is NULL (Not Assigned)
                                selectedFuelTypesByYear[yearId] = nil
                            }
                        }
                    }
                }
            }

            if mapping != nil {
                print("📋 Loaded existing mapping for \(pair.makeModelDisplay)")
            } else {
                print("📋 Pre-populated exact match for \(pair.makeModelDisplay)")
            }
        } else {
            // No mapping and no exact match - clear form fields but keep pair selected
            // User can manually select canonical Make/Model for typo corrections
            clearMappingFormFields()
            print("📋 No auto-population for \(pair.makeModelDisplay) - manual mapping required")
        }
    }
}

// MARK: - Status Filter Button

struct StatusFilterButton: View {
    @Binding var isSelected: Bool
    let label: String
    let color: Color

    var body: some View {
        Button(action: {
            isSelected.toggle()
        }) {
            HStack(spacing: 4) {
                Circle()
                    .strokeBorder(color, lineWidth: isSelected ? 0 : 1)
                    .background(Circle().fill(isSelected ? color : Color.clear))
                    .frame(width: 8, height: 8)

                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle)
        .controlSize(.small)
        .help(isSelected ? "Hide \(label.lowercased()) pairs" : "Show \(label.lowercased()) pairs")
    }
}

// MARK: - Radio Button Row

struct RadioButtonRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .strokeBorder(Color.blue, lineWidth: 2)
                    .background(Circle().fill(isSelected ? Color.blue : Color.clear))
                    .frame(width: 16, height: 16)

                Text(label)
                    .font(.body)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
