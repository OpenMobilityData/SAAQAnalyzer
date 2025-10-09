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

                // Show exact matches toggle
                Toggle("Show Exact Matches", isOn: $viewModel.showExactMatches)
                    .controlSize(.small)
                    .help("When enabled, shows Make/Model pairs that exist in both curated and uncurated years. Useful for adding FuelType/VehicleType disambiguation.")

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
                        Text("Not Specified").tag(nil as MakeModelHierarchy.VehicleTypeInfo?)

                        // Special "Unknown" option (not in hierarchy since it doesn't appear in curated years)
                        Text("Unknown").tag(MakeModelHierarchy.VehicleTypeInfo(
                            id: -1,  // Placeholder ID - will be looked up from enum table when saving
                            code: "UNK",
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

            // Step 4: Select Fuel Type (optional)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("4. Select Fuel Type (Optional)")
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

                        // Special "Unknown" option (not in hierarchy since it doesn't appear in curated years)
                        Text("Unknown").tag(MakeModelHierarchy.FuelTypeInfo(
                            id: -1,  // Placeholder ID - will be looked up from enum table when saving
                            code: "U",
                            description: "Unknown",
                            recordCount: 0
                        ) as MakeModelHierarchy.FuelTypeInfo?)

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
    @Published var showExactMatches: Bool = false {
        didSet {
            if showExactMatches != oldValue {
                Task { @MainActor in
                    await loadUncuratedPairs()
                }
            }
        }
    }
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

    /// Calculate regularization progress based on total records
    var regularizationProgress: (regularizedRecords: Int, totalRecords: Int, percentage: Double) {
        let totalRecords = uncuratedPairs.reduce(0) { $0 + $1.recordCount }

        // Count records that have mappings
        var regularizedRecords = 0
        for pair in uncuratedPairs {
            let key = "\(pair.makeId)_\(pair.modelId)"
            if existingMappings[key] != nil {
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

            await MainActor.run {
                existingMappings = mappingsDict
            }
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

        await MainActor.run {
            isLoading = true
        }

        do {
            let pairs = try await manager.findUncuratedPairs(includeExactMatches: showExactMatches)
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
            // Resolve placeholder IDs for "Unknown" options
            var fuelTypeId = selectedFuelType?.id
            var vehicleTypeId = selectedVehicleType?.id

            // If fuel type has placeholder ID (-1), lookup real ID by code
            if let fuelType = selectedFuelType, fuelType.id == -1 {
                print("🔍 Resolving placeholder FuelType ID -1 (code: \(fuelType.code))")
                let enumManager = CategoricalEnumManager(databaseManager: databaseManager)
                if let resolvedId = try await enumManager.getEnumId(
                    table: "fuel_type_enum",
                    column: "code",
                    value: fuelType.code
                ) {
                    fuelTypeId = resolvedId
                    print("✅ Resolved FuelType '\(fuelType.code)' to ID \(resolvedId)")
                } else {
                    print("❌ ERROR: Failed to resolve FuelType '\(fuelType.code)' - will save as NULL!")
                    fuelTypeId = nil
                }
            }

            // If vehicle type has placeholder ID (-1), lookup real ID by code
            if let vehicleType = selectedVehicleType, vehicleType.id == -1 {
                print("🔍 Resolving placeholder VehicleType ID -1 (code: \(vehicleType.code))")
                let enumManager = CategoricalEnumManager(databaseManager: databaseManager)
                if let resolvedId = try await enumManager.getEnumId(
                    table: "classification_enum",
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

            try await manager.saveMapping(
                uncuratedMakeId: pair.makeId,
                uncuratedModelId: pair.modelId,
                canonicalMakeId: canonicalMake.id,
                canonicalModelId: canonicalModel.id,
                fuelTypeId: fuelTypeId,
                vehicleTypeId: vehicleTypeId
            )

            print("✅ Saved mapping: \(pair.makeModelDisplay) → \(canonicalMake.name)/\(canonicalModel.name)")

            // Reload existing mappings to update status indicators
            // This will trigger UI updates for status badges without rebuilding the pairs array
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

            // Check if this pair already has a mapping
            let mappingKey = "\(pair.makeId)_\(pair.modelId)"
            if existingMappings[mappingKey] != nil {
                continue  // Already mapped
            }

            // Check if there's an exact match
            if let canonicalModel = canonicalPairs[pairKey] {
                // Filter out "Not Specified" placeholders when counting valid options
                // Note: "Unknown" will never appear in canonical hierarchy (curated years only)
                let validFuelTypes = canonicalModel.fuelTypes.filter { fuelType in
                    !fuelType.description.localizedCaseInsensitiveContains("not specified") &&
                    !fuelType.description.localizedCaseInsensitiveContains("non spécifié")
                }
                let validVehicleTypes = canonicalModel.vehicleTypes.filter { vehicleType in
                    !vehicleType.description.localizedCaseInsensitiveContains("not specified") &&
                    !vehicleType.description.localizedCaseInsensitiveContains("non spécifié")
                }

                // Auto-assign FuelType if there's only one valid option
                let fuelTypeId: Int? = validFuelTypes.count == 1
                    ? validFuelTypes.first?.id
                    : nil

                // Auto-assign VehicleType if there's only one valid option
                let vehicleTypeId: Int? = validVehicleTypes.count == 1
                    ? validVehicleTypes.first?.id
                    : nil

                do {
                    try await manager.saveMapping(
                        uncuratedMakeId: pair.makeId,
                        uncuratedModelId: pair.modelId,
                        canonicalMakeId: canonicalModel.makeId,
                        canonicalModelId: canonicalModel.id,
                        fuelTypeId: fuelTypeId,
                        vehicleTypeId: vehicleTypeId
                    )
                    autoRegularizedCount += 1

                    // Log what was auto-assigned
                    var autoAssignedFields: [String] = ["M/M"]
                    if fuelTypeId != nil {
                        autoAssignedFields.append("FuelType")
                    }
                    if vehicleTypeId != nil {
                        autoAssignedFields.append("VehicleType")
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

    /// Get regularization status for a pair
    func getRegularizationStatus(for pair: UnverifiedMakeModelPair) -> RegularizationStatus {
        let key = "\(pair.makeId)_\(pair.modelId)"

        guard let mapping = existingMappings[key] else {
            return .none  // 🔴 No mapping exists
        }

        // Check if both fuel type AND vehicle type are assigned (non-NULL)
        // "Unknown" counts as assigned (user has made a decision)
        let hasFuelType = mapping.fuelType != nil
        let hasVehicleType = mapping.vehicleType != nil

        if hasFuelType && hasVehicleType {
            return .fullyRegularized  // 🟢 Both fields assigned (including "Unknown")
        } else {
            return .needsReview  // 🟠 At least one field is NULL (needs review)
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

        let key = "\(pair.makeId)_\(pair.modelId)"
        let mapping = existingMappings[key]

        // Try to find canonical Make/Model for this pair
        // First check if there's an existing mapping
        var canonicalMakeName: String?
        var canonicalModelName: String?

        if let mapping = mapping {
            // Use mapping's canonical values
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
                    selectedFuelType = nil
                    selectedVehicleType = nil

                    // Find the fuel type if assigned (only from existing mapping)
                    if let mapping = mapping, let fuelTypeName = mapping.fuelType {
                        if fuelTypeName == "Unknown" {
                            // Create special "Unknown" instance (matches picker option)
                            selectedFuelType = MakeModelHierarchy.FuelTypeInfo(
                                id: -1,
                                code: "U",
                                description: "Unknown",
                                recordCount: 0
                            )
                        } else {
                            selectedFuelType = model.fuelTypes.first { $0.description == fuelTypeName }
                        }
                    }

                    // Find the vehicle type if assigned (only from existing mapping)
                    if let mapping = mapping, let vehicleTypeName = mapping.vehicleType {
                        if vehicleTypeName == "Unknown" {
                            // Create special "Unknown" instance (matches picker option)
                            selectedVehicleType = MakeModelHierarchy.VehicleTypeInfo(
                                id: -1,
                                code: "UNK",
                                description: "Unknown",
                                recordCount: 0
                            )
                        } else {
                            selectedVehicleType = model.vehicleTypes.first { $0.description == vehicleTypeName }
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
