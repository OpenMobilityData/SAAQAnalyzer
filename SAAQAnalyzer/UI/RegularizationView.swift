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

                // Summary
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

                    Label("\(pair.earliestYear)–\(pair.latestYear)", systemImage: "calendar")
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
        case .autoRegularized:
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
            Text("Not Regularized")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.2))
                .foregroundColor(.red)
                .cornerRadius(4)
        case .autoRegularized:
            Text("Auto (M/M only)")
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
    case none                   // No regularization mapping exists
    case autoRegularized        // Auto-mapped (Make/Model match), but no FuelType/VehicleType
    case fullyRegularized       // Complete mapping with FuelType or VehicleType assigned
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

            // Step 3: Select Fuel Type (optional)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("3. Select Fuel Type (Optional)")
                        .font(.headline)
                    Spacer()
                    if viewModel.selectedFuelType != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }

                Text("Leave unset if uncertain or multiple fuel types exist")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let model = viewModel.selectedCanonicalModel {
                    Picker("Fuel Type", selection: $viewModel.selectedFuelType) {
                        Text("Not Specified").tag(nil as MakeModelHierarchy.FuelTypeInfo?)
                        ForEach(model.fuelTypes) { fuelType in
                            HStack {
                                Text(fuelType.description)
                                Text("(\(fuelType.recordCount.formatted()))")
                                    .foregroundStyle(.secondary)
                            }
                            .tag(fuelType as MakeModelHierarchy.FuelTypeInfo?)
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

            // Step 4: Select Vehicle Type (optional)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("4. Select Vehicle Type (Optional)")
                        .font(.headline)
                    Spacer()
                    if viewModel.selectedVehicleType != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }

                Text("Leave unset if uncertain or multiple vehicle types exist")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let model = viewModel.selectedCanonicalModel {
                    Picker("Vehicle Type", selection: $viewModel.selectedVehicleType) {
                        Text("Not Specified").tag(nil as MakeModelHierarchy.VehicleTypeInfo?)
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
    @Published var selectedPair: UnverifiedMakeModelPair?
    @Published var existingMappings: [String: RegularizationMapping] = [:] // Key: "\(makeId)_\(modelId)"

    // Mapping form state
    @Published var selectedCanonicalMake: MakeModelHierarchy.Make?
    @Published var selectedCanonicalModel: MakeModelHierarchy.Model?
    @Published var selectedFuelType: MakeModelHierarchy.FuelTypeInfo?
    @Published var selectedVehicleType: MakeModelHierarchy.VehicleTypeInfo?

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

    init(databaseManager: DatabaseManager, yearConfig: RegularizationYearConfiguration) {
        self.databaseManager = databaseManager
        self.yearConfig = yearConfig
    }

    func loadInitialData() async {
        // Update year configuration in manager
        if let manager = regularizationManager {
            await manager.setYearConfiguration(yearConfig)
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
            var mappingsDict: [String: RegularizationMapping] = [:]

            for mapping in mappings {
                // Use uncuratedKey from the mapping
                mappingsDict[mapping.uncuratedKey] = mapping
            }

            existingMappings = mappingsDict
            print("✅ Loaded \(mappings.count) existing mappings")
        } catch {
            print("❌ Error loading existing mappings: \(error)")
        }
    }

    func loadUncuratedPairs() async {
        guard let manager = regularizationManager else {
            print("❌ RegularizationManager not available")
            return
        }

        isLoading = true

        do {
            let pairs = try await manager.findUncuratedPairs()
            uncuratedPairs = pairs
            print("✅ Loaded \(pairs.count) uncurated pairs")
        } catch {
            print("❌ Error loading uncurated pairs: \(error)")
        }

        isLoading = false
    }

    func generateHierarchy() async {
        guard let manager = regularizationManager else {
            print("❌ RegularizationManager not available")
            return
        }

        isLoadingHierarchy = true

        do {
            let hierarchy = try await manager.generateCanonicalHierarchy(forceRefresh: true)
            canonicalHierarchy = hierarchy
            print("✅ Generated hierarchy with \(hierarchy.makes.count) makes")
        } catch {
            print("❌ Error generating hierarchy: \(error)")
        }

        isLoadingHierarchy = false
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
            try await manager.saveMapping(
                uncuratedMakeId: pair.makeId,
                uncuratedModelId: pair.modelId,
                canonicalMakeId: canonicalMake.id,
                canonicalModelId: canonicalModel.id,
                fuelTypeId: selectedFuelType?.id,
                vehicleTypeId: selectedVehicleType?.id
            )

            print("✅ Saved mapping: \(pair.makeModelDisplay) → \(canonicalMake.name)/\(canonicalModel.name)")

            // Reload existing mappings to update status indicators
            await loadExistingMappings()

            // Clear selection and refresh pairs
            clearMappingSelection()
            await loadUncuratedPairs()

        } catch {
            print("❌ Error saving mapping: \(error)")
        }

        isSaving = false
    }

    func clearMappingSelection() {
        selectedCanonicalMake = nil
        selectedCanonicalModel = nil
        selectedFuelType = nil
        selectedVehicleType = nil
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

        // Build a lookup of canonical Make/Model combinations
        var canonicalPairs: [String: (makeId: Int, modelId: Int)] = [:]
        for make in hierarchy!.makes {
            for model in make.models {
                let key = "\(make.name)/\(model.name)"
                canonicalPairs[key] = (make.id, model.id)
            }
        }

        // Find uncurated pairs that exactly match
        var autoRegularizedCount = 0
        for pair in uncuratedPairs {
            let pairKey = "\(pair.makeName)/\(pair.modelName)"

            // Check if this pair already has a mapping
            let mappingKey = "\(pair.makeId)_\(pair.modelId)"
            if existingMappings[mappingKey] != nil {
                continue  // Already mapped
            }

            // Check if there's an exact match
            if let canonical = canonicalPairs[pairKey] {
                do {
                    try await manager.saveMapping(
                        uncuratedMakeId: pair.makeId,
                        uncuratedModelId: pair.modelId,
                        canonicalMakeId: canonical.makeId,
                        canonicalModelId: canonical.modelId,
                        fuelTypeId: nil,  // Not specified in auto-regularization
                        vehicleTypeId: nil  // Not specified in auto-regularization
                    )
                    autoRegularizedCount += 1
                    print("✅ Auto-regularized: \(pairKey)")
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

    /// Get regularization status for a pair
    func getRegularizationStatus(for pair: UnverifiedMakeModelPair) -> RegularizationStatus {
        let key = "\(pair.makeId)_\(pair.modelId)"

        guard let mapping = existingMappings[key] else {
            return .none
        }

        // Check if fuel type or vehicle type is assigned
        if mapping.fuelType != nil || mapping.vehicleType != nil {
            return .fullyRegularized
        } else {
            return .autoRegularized
        }
    }
}
