import SwiftUI
import Observation
import Combine
import OSLog

/// Main view for managing Make/Model regularization mappings
struct RegularizationView: View {
    // Use centralized logging
    private let logger = AppLogger.regularization
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: RegularizationViewModel

    init(viewModel: RegularizationViewModel) {
        self.viewModel = viewModel
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

                    Button("Reload Pairs List") {
                        Task {
                            await viewModel.loadUncuratedPairs()
                        }
                    }
                    .help("Reload the uncurated pairs list from the database to pick up any changes made by auto-regularization or external updates")
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .onAppear {
            // Only load initial data if not already loaded (preserves cached data on reopen)
            if viewModel.uncuratedPairs.isEmpty && !viewModel.isLoading {
                Task { @MainActor in
                    viewModel.loadInitialData()
                }
            }
        }
        .onChange(of: viewModel.selectedPair) { oldValue, newValue in
            // Load mapping when selection changes
            // Use Task.detached to break out of view update cycle and avoid publishing warnings
            if newValue != oldValue, newValue != nil {
                Task.detached { @MainActor in
                    await viewModel.loadMappingForSelectedPair()
                }
            }
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
    @State private var showPartial = true
    @State private var showComplete = true
    @State private var showOnlyRegularizationVehicleTypes = false
    @State private var selectedVehicleTypeFilter: Int? = nil  // Vehicle type ID (nil = All, -1 = Not Assigned)
    @State private var filterByIncompleteFields = false
    @State private var incompleteVehicleType = false
    @State private var incompleteFuelType = false

    enum SortOrder: String, CaseIterable {
        case recordCountDescending = "Record Count (High to Low)"
        case recordCountAscending = "Record Count (Low to High)"
        case makeModelAlphabetical = "Make/Model (A-Z)"
        case percentageDescending = "Percentage (High to Low)"
    }

    // Fast status counts (status embedded in struct - no computation needed)
    var statusCounts: (unassignedCount: Int, partialCount: Int, completeCount: Int) {
        var unassignedCount = 0
        var partialCount = 0
        var completeCount = 0

        for pair in viewModel.uncuratedPairs {
            switch pair.regularizationStatus {
            case .unassigned:
                unassignedCount += 1
            case .partial:
                partialCount += 1
            case .complete:
                completeCount += 1
            }
        }

        return (unassignedCount, partialCount, completeCount)
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

        // Filter by status (using embedded status - instant!)
        pairs = pairs.filter { pair in
            switch pair.regularizationStatus {
            case .unassigned:
                return showUnassigned
            case .partial:
                return showPartial
            case .complete:
                return showComplete
            }
        }

        // Filter by vehicle type (using cached vehicleTypeId for performance)
        // Uses integer enumeration following core architecture pattern
        if let selectedId = selectedVehicleTypeFilter {
            pairs = pairs.filter { pair in
                // Handle "Not Assigned" filter (-1 sentinel value)
                if selectedId == -1 {
                    return pair.vehicleTypeId == nil
                }

                // Handle specific vehicle type filters (integer comparison)
                return pair.vehicleTypeId == selectedId
            }
        }

        // Filter by incomplete fields
        if filterByIncompleteFields && (incompleteVehicleType || incompleteFuelType) {
            pairs = pairs.filter { pair in
                let mappings = viewModel.getMappingsForPair(pair.makeId, pair.modelId)

                // If no mappings exist, this pair is completely unassigned (skip it in incomplete filter)
                if mappings.isEmpty {
                    return false
                }

                let wildcardMapping = mappings.first { $0.modelYearId == nil }
                let tripletMappings = mappings.filter { $0.modelYearId != nil }

                var matchesFilter = false

                // Check Vehicle Type incomplete
                if incompleteVehicleType {
                    // Vehicle type is in wildcard mapping
                    if let wildcard = wildcardMapping, wildcard.vehicleType == nil {
                        matchesFilter = true
                    }
                }

                // Check Fuel Type incomplete
                if incompleteFuelType {
                    // Check if there are triplets AND if ANY triplet has NULL fuel type
                    // This shows pairs where some model years still need fuel type assignment
                    if !tripletMappings.isEmpty && tripletMappings.contains(where: { $0.fuelType == nil }) {
                        matchesFilter = true
                    }
                    // Also include pairs with no triplets at all (completely missing fuel type data)
                    else if tripletMappings.isEmpty {
                        matchesFilter = true
                    }
                }

                return matchesFilter
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

                    HStack(spacing: 8) {
                        StatusFilterButton(
                            isSelected: $showUnassigned,
                            label: "Unassigned",
                            count: statusCounts.unassignedCount,
                            color: .red
                        )

                        StatusFilterButton(
                            isSelected: $showPartial,
                            label: "Partial",
                            count: statusCounts.partialCount,
                            color: .orange
                        )

                        StatusFilterButton(
                            isSelected: $showComplete,
                            label: "Complete",
                            count: statusCounts.completeCount,
                            color: .green
                        )
                    }
                }

                // Vehicle Type Filter
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Filter by Vehicle Type:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Toggle(isOn: $showOnlyRegularizationVehicleTypes) {
                            Text("In regularization list only")
                                .font(.caption2)
                        }
                        .help("Controls which vehicle types appear in the dropdown below: all types from schema (13) vs. only types with existing mappings (~10)")
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .onChange(of: showOnlyRegularizationVehicleTypes) { _, newValue in
                            // Clear selection if toggling to regularization-only and current selection isn't in that list
                            if newValue, let selectedId = selectedVehicleTypeFilter {
                                if selectedId != -1 && !viewModel.regularizationVehicleTypes.contains(where: { $0.id == selectedId }) {
                                    selectedVehicleTypeFilter = nil
                                }
                            }
                        }
                    }

                    Picker("Vehicle Type", selection: $selectedVehicleTypeFilter) {
                        Text("All Types").tag(nil as Int?)

                        // Not Assigned option (pairs with no vehicle type mapping)
                        // Uses -1 as sentinel value (not a valid vehicle_type_enum.id)
                        Text("Not Assigned").tag(-1 as Int?)

                        let vehicleTypes = showOnlyRegularizationVehicleTypes
                            ? viewModel.regularizationVehicleTypes
                            : viewModel.allVehicleTypes

                        // Sort with UK at the end
                        let sortedTypes = vehicleTypes.sorted { type1, type2 in
                            if type1.code == "UK" { return false }
                            if type2.code == "UK" { return true }
                            return type1.code < type2.code
                        }

                        ForEach(sortedTypes, id: \.id) { vehicleType in
                            Text("\(vehicleType.code) - \(vehicleType.description)")
                                .tag(vehicleType.id as Int?)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .id("vehicleTypePicker-\(showOnlyRegularizationVehicleTypes)")
                }

                // Incomplete Fields Filter
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Toggle(isOn: $filterByIncompleteFields) {
                            Text("Filter by Incomplete Fields:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .onChange(of: filterByIncompleteFields) { _, newValue in
                            // Reset checkboxes when toggling off
                            if !newValue {
                                incompleteVehicleType = false
                                incompleteFuelType = false
                            }
                        }
                    }

                    if filterByIncompleteFields {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(isOn: $incompleteVehicleType) {
                                Text("Vehicle Type not assigned")
                                    .font(.caption)
                            }
                            .toggleStyle(.checkbox)
                            .disabled(!filterByIncompleteFields)

                            Toggle(isOn: $incompleteFuelType) {
                                Text("Fuel Type not assigned (any model year)")
                                    .font(.caption)
                            }
                            .toggleStyle(.checkbox)
                            .disabled(!filterByIncompleteFields)
                        }
                        .padding(.leading, 16)
                    }
                }

                // Background processing indicator
                if viewModel.isAutoRegularizing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 12, height: 12)
                        Text("Auto-regularizing exact matches in background...")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Spacer()
                        Text("Status indicators may be delayed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }

                // Summary
                VStack(spacing: 4) {
                    HStack {
                        Text("\(filteredAndSortedPairs.count) Make/Model pairs")
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

            // List - ALWAYS show to prevent UI blocking
            List(selection: $viewModel.selectedPair) {
                if viewModel.isLoading {
                    Section {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading uncurated pairs...")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text("Database query may take several minutes")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                } else if filteredAndSortedPairs.isEmpty {
                    Section {
                        Text(searchText.isEmpty ? "No uncurated pairs found" : "No matches for \"\(searchText)\"")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                } else {
                    ForEach(filteredAndSortedPairs) { pair in
                        UncuratedPairRow(
                            pair: pair,
                            regularizationStatus: pair.regularizationStatus
                        )
                        .tag(pair)
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

struct UncuratedPairRow: View {
    let pair: UnverifiedMakeModelPair
    let regularizationStatus: RegularizationStatus

    // Pre-compute field status using cached data on pair (avoid accessing @Published during view updates)
    private var fieldStatus: (makeModel: Bool, vehicleType: Bool, fuelTypes: Bool) {
        // Make/Model assigned if any mapping exists (status != unassigned)
        let hasMakeModel = pair.regularizationStatus != .unassigned

        // Vehicle type is already cached on the pair from wildcard mapping
        let hasVehicleType = pair.vehicleTypeId != nil

        // Fuel types complete only when overall status is .complete (all model years assigned)
        let hasFuelTypes = pair.regularizationStatus == .complete

        return (makeModel: hasMakeModel, vehicleType: hasVehicleType, fuelTypes: hasFuelTypes)
    }

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

                    Spacer()

                    // Regularization status badges (right-justified)
                    statusBadges
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch regularizationStatus {
        case .unassigned:
            Circle()
                .fill(Color.red)
        case .partial:
            Circle()
                .fill(Color.orange)
        case .complete:
            Circle()
                .fill(Color.green)
        }
    }

    @ViewBuilder
    private var statusBadges: some View {
        switch regularizationStatus {
        case .unassigned:
            Text("Unassigned")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.2))
                .foregroundColor(.red)
                .cornerRadius(4)
        case .partial, .complete:
            // Show field-specific badges for both partial and complete status
            // Note: Overall status already indicated by colored circle on left
            HStack(spacing: 4) {
                // Make/Model badge (always shown)
                FieldBadge(
                    icon: "checkmark",
                    tooltip: "Make/Model assigned",
                    isAssigned: fieldStatus.makeModel,
                    color: .blue
                )

                // Vehicle Type badge
                FieldBadge(
                    icon: "car.fill",
                    tooltip: "Vehicle Type assigned",
                    isAssigned: fieldStatus.vehicleType,
                    color: .orange
                )

                // Fuel Types badge (shown when ALL model years assigned)
                FieldBadge(
                    icon: "fuelpump.fill",
                    tooltip: "Fuel Types assigned (all model years)",
                    isAssigned: fieldStatus.fuelTypes,
                    color: .purple
                )
            }
        }
    }
}

/// Field-specific assignment badge with solid colored background
struct FieldBadge: View {
    let icon: String
    let tooltip: String
    let isAssigned: Bool
    let color: Color

    var body: some View {
        if isAssigned {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(color.opacity(0.25))
                .cornerRadius(4)
                .help(tooltip)
        }
    }
}

/// Regularization status for an uncurated pair
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
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.25))
                            .cornerRadius(4)
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
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.25))
                            .cornerRadius(4)
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
                    if viewModel.selectedVehicleTypeId != nil {
                        Image(systemName: "car.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.25))
                            .cornerRadius(4)
                    }
                }

                Text("Leave unset if uncertain or multiple vehicle types exist")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let model = viewModel.selectedCanonicalModel {
                    Picker("Vehicle Type", selection: $viewModel.selectedVehicleTypeId) {
                        Text("Not Assigned").tag(nil as Int?)

                        // Special "Unknown" option (not in hierarchy since it doesn't appear in curated years)
                        // Uses -1 as placeholder ID - will be resolved to actual enum ID when saving
                        Text("UK - Unknown").tag(-1 as Int?)

                        // Show only vehicle types that exist in curated data for this model
                        // (preserves UX feature of helping users understand canonical mappings)
                        ForEach(model.vehicleTypes) { vehicleType in
                            HStack {
                                Text("\(vehicleType.code) - \(vehicleType.description)")
                                Text("(\(vehicleType.recordCount.formatted()))")
                                    .foregroundStyle(.secondary)
                            }
                            .tag(vehicleType.id as Int?)
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
                        Image(systemName: "fuelpump.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.purple.opacity(0.25))
                            .cornerRadius(4)
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

    // Get all uncurated model years (actual years that exist in database)
    private var uncuratedYears: [Int] {
        viewModel.uncuratedModelYears
    }

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

                Text("\(filteredYears.count) of \(uncuratedYears.count) years")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredYears, id: \.self) { modelYear in
                        ModelYearFuelTypeRow(
                            modelYear: modelYear,
                            model: model,
                            viewModel: viewModel
                        )
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 400)
        }
        .background(Color.gray.opacity(0.03))
        .cornerRadius(6)
    }

    private var sortedYears: [Int] {
        uncuratedYears.sorted()
    }

    private var filteredYears: [Int] {
        if showOnlyNotAssigned {
            return sortedYears.filter { modelYear in
                // Show if no fuel type assigned (using model year directly)
                return viewModel.getSelectedFuelType(forModelYear: modelYear) == nil
            }
        } else {
            return sortedYears
        }
    }
}

struct ModelYearFuelTypeRow: View {
    let modelYear: Int
    let model: MakeModelHierarchy.Model
    @ObservedObject var viewModel: RegularizationViewModel

    // Find yearId in canonical hierarchy (if it exists)
    // Returns unwrapped Int (keys are Int? so .first returns Int??)
    private var yearId: Int? {
        let foundYearId = model.modelYearFuelTypes.keys.first { optionalYearId in
            guard let unwrappedYearId = optionalYearId,
                  let fuelTypes = model.modelYearFuelTypes[unwrappedYearId],
                  let year = fuelTypes.first?.modelYear else {
                return false
            }
            return year == modelYear
        }
        // Unwrap double-optional: foundYearId is Int??, we need Int?
        return foundYearId.flatMap { $0 }
    }

    // Get fuel type options: use canonical if available, otherwise use all from schema
    private var fuelTypes: [MakeModelHierarchy.FuelTypeInfo] {
        if let yearId = yearId, let canonicalTypes = model.modelYearFuelTypes[yearId] {
            // Year exists in canonical hierarchy - use specific fuel types
            return canonicalTypes
        } else {
            // Year NOT in canonical (e.g., 2025) - show all fuel types from schema
            return viewModel.allFuelTypes
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Year header with badges
            HStack(spacing: 8) {
                Text("Model Year \(String(modelYear))")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                // Badge for uncurated-only years (not in canonical hierarchy)
                if yearId == nil {
                    Text("Uncurated Only")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(.purple)
                        .cornerRadius(4)
                        .help("This model year only appears in uncurated data (not in curated years)")
                }

                Spacer()

                // Record count from uncurated data
                if let count = viewModel.uncuratedModelYearCounts[modelYear] {
                    Text("\(count.formatted()) records")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Number of vehicles with this model year in uncurated data")
                }
            }

            // Radio button options
            VStack(alignment: .leading, spacing: 4) {
                // Option 1: Not Assigned (default)
                RadioButtonRow(
                    label: "Not Assigned",
                    isSelected: viewModel.getSelectedFuelType(forModelYear: modelYear) == nil,
                    action: {
                        viewModel.setFuelType(modelYear: modelYear, fuelTypeId: nil)
                    }
                )
                .foregroundColor(.secondary)

                // Option 2: Unknown
                RadioButtonRow(
                    label: "Unknown",
                    isSelected: viewModel.getSelectedFuelType(forModelYear: modelYear) == -1,
                    action: {
                        viewModel.setFuelType(modelYear: modelYear, fuelTypeId: -1)
                    }
                )
                .foregroundColor(.orange)

                Divider()

                // Options 3+: Actual fuel types (filtered)
                ForEach(validFuelTypes) { fuelType in
                    RadioButtonRow(
                        label: "\(fuelType.description) (\(fuelType.recordCount.formatted()))",
                        isSelected: viewModel.getSelectedFuelType(forModelYear: modelYear) == fuelType.id,
                        action: {
                            viewModel.setFuelType(modelYear: modelYear, fuelTypeId: fuelType.id)
                        }
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
            fuelType.id != -1 &&  // Filter out placeholder entries for NULL fuel types
            !fuelType.description.localizedCaseInsensitiveContains("not specified") &&
            !fuelType.description.localizedCaseInsensitiveContains("not assigned") &&
            !fuelType.description.localizedCaseInsensitiveContains("non spécifié")
        }
    }
}

// MARK: - View Model

class RegularizationViewModel: ObservableObject {
    private let databaseManager: DatabaseManager
    private let regularizationManager: RegularizationManager?

    // Use centralized logging
    private let logger = AppLogger.regularization

    @Published var yearConfig: RegularizationYearConfiguration
    @Published var uncuratedPairs: [UnverifiedMakeModelPair] = []
    @Published var canonicalHierarchy: MakeModelHierarchy?
    @Published var selectedPair: UnverifiedMakeModelPair?
    @Published var existingMappings: [String: [RegularizationMapping]] = [:] // Key: "\(makeId)_\(modelId)" → Array of mappings (triplets + wildcard)
    @Published var allVehicleTypes: [MakeModelHierarchy.VehicleTypeInfo] = []
    @Published var regularizationVehicleTypes: [MakeModelHierarchy.VehicleTypeInfo] = []
    @Published var allFuelTypes: [MakeModelHierarchy.FuelTypeInfo] = []  // All fuel types from schema (for new model years)

    // Mapping form state
    @Published var selectedCanonicalMake: MakeModelHierarchy.Make?
    @Published var selectedCanonicalModel: MakeModelHierarchy.Model? {
        didSet {
            // Clear fuel type selections when model changes
            if selectedCanonicalModel?.id != oldValue?.id {
                selectedFuelTypesByModelYear = [:]

                // Auto-populate Vehicle Type and Fuel Types when a new model is selected
                // This is particularly useful for 'Unassigned' pairs where no existing mapping exists
                Task { @MainActor in
                    await autoPopulateFieldsForNewModel()
                }
            }
        }
    }
    // Use integer ID (not struct) to avoid SwiftUI Picker equality issues
    // Follows core architecture pattern of integer enumeration
    @Published var selectedVehicleTypeId: Int?

    // Year-based fuel type selections for table UI (single selection per year)
    // Dictionary: modelYearId → fuelTypeId (or nil for "Not Assigned", -1 for "Unknown")
    @Published var selectedFuelTypesByModelYear: [Int: Int?] = [:]  // Key: model year value (2024, 2025, etc.)

    // Model years that actually exist in uncurated data for selected pair
    // Used to filter fuel type UI (show only years needing assignment)
    @Published var uncuratedModelYears: [Int] = []

    // Record counts per model year for prioritizing regularization effort
    // Dictionary: modelYear → record count in uncurated data
    @Published var uncuratedModelYearCounts: [Int: Int] = [:]

    // Loading states
    @Published var isLoading = false
    @Published var isLoadingHierarchy = false
    @Published var isSaving = false
    @Published var isAutoRegularizing = false

    @MainActor
    var canSaveMapping: Bool {
        selectedPair != nil &&
        selectedCanonicalMake != nil &&
        selectedCanonicalModel != nil
    }

    /// Calculate regularization progress based on total records
    @MainActor
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
        self.regularizationManager = databaseManager.regularizationManager
        self.yearConfig = yearConfig
    }

    /// Updates the year configuration in the regularization manager
    func updateYearConfiguration(_ newConfig: RegularizationYearConfiguration) {
        self.yearConfig = newConfig
        if let manager = regularizationManager {
            manager.setYearConfiguration(newConfig)
        }
    }

    @MainActor
    func loadInitialData() {
        // Update year configuration in manager (main thread OK, just setter)
        if let manager = regularizationManager {
            manager.setYearConfiguration(yearConfig)
        }

        // Launch ALL data loading in background to avoid blocking UI
        // CRITICAL: Must use Task.detached to break away from MainActor context
        // This method returns immediately after launching tasks - no blocking!

        // 1. Load vehicle types (fast, needed for UI) - runs on background thread
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.loadVehicleTypesAsync()
        }

        // 2. Load existing mappings (78K mappings can be slow) - load in background
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.loadExistingMappingsAsync()
        }

        // 3. Load uncurated pairs (SLOW: 29s) - don't await, let it run in background
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.loadUncuratedPairsAsync()
        }

        // 4. Pre-generate canonical hierarchy (0.5s via cache) - ready when user selects a pair
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.loadHierarchyAsync()
        }

        // 5. Auto-regularize exact matches (VERY SLOW) - lowest priority background task
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            await self.autoRegularizeExactMatchesAsync()
        }
    }

    // MARK: - Async Database Loading Methods (nonisolated, run on background threads)

    nonisolated func loadVehicleTypesAsync() async {
        guard let manager = regularizationManager else {
            logger.error("RegularizationManager not available")
            return
        }

        do {
            let allTypes = try await manager.getAllVehicleTypes()
            let regTypes = try await manager.getRegularizationVehicleTypes()
            let allFuels = try await manager.getAllFuelTypes()

            await MainActor.run {
                self.allVehicleTypes = allTypes
                self.regularizationVehicleTypes = regTypes
                self.allFuelTypes = allFuels
            }

            logger.info("Loaded vehicle types: \(allTypes.count) total, \(regTypes.count) in regularization list")
            logger.info("Loaded fuel types: \(allFuels.count) from schema")
        } catch {
            logger.error("Error loading vehicle types: \(error.localizedDescription)")
        }
    }

    nonisolated func loadExistingMappingsAsync() async {
        guard let manager = regularizationManager else { return }

        do {
            let mappings = try await manager.getAllMappings()

            // Build mappingsDict on background thread (compute key manually to avoid actor isolation)
            let mappingsDict = await Task.detached {
                var dict: [String: [RegularizationMapping]] = [:]
                for mapping in mappings {
                    // Compute key manually instead of using .uncuratedKey property
                    let key = "\(mapping.uncuratedMakeId)_\(mapping.uncuratedModelId)"
                    if dict[key] == nil {
                        dict[key] = []
                    }
                    dict[key]?.append(mapping)
                }
                return dict
            }.value

            await MainActor.run {
                self.existingMappings = mappingsDict
            }

            // Count unique pairs vs total mappings (including triplets)
            let uniquePairs = mappingsDict.count
            let totalMappings = mappings.count
            if totalMappings > uniquePairs {
                logger.info("Loaded \(totalMappings) mappings (\(uniquePairs) pairs, \(totalMappings - uniquePairs) triplets)")
            } else {
                logger.info("Loaded \(mappings.count) existing mappings")
            }
        } catch {
            logger.error("Error loading existing mappings: \(error.localizedDescription)")
        }
    }

    nonisolated func loadUncuratedPairsAsync() async {
        guard let manager = regularizationManager else {
            logger.error("RegularizationManager not available")
            return
        }

        await MainActor.run {
            self.isLoading = true
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            // Always load all pairs (including exact matches) - filtering is done in UI by status
            let pairs = try await manager.findUncuratedPairs(includeExactMatches: true)
            await MainActor.run {
                self.uncuratedPairs = pairs
                self.isLoading = false
            }
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logger.notice("Loaded \(pairs.count) uncurated pairs in \(String(format: "%.3f", duration))s")
        } catch {
            logger.error("Error loading uncurated pairs: \(error.localizedDescription)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    // Keep old method for backwards compatibility (delegates to async version)
    @MainActor
    func loadUncuratedPairs() async {
        Task {
            await loadUncuratedPairsAsync()
        }
    }

    nonisolated func loadHierarchyAsync() async {
        guard let manager = regularizationManager else {
            logger.error("RegularizationManager not available")
            return
        }

        do {
            let hierarchy = try await manager.generateCanonicalHierarchy(forceRefresh: false)
            await MainActor.run {
                self.canonicalHierarchy = hierarchy
            }
            logger.debug("Pre-warmed canonical hierarchy in background: \(hierarchy.makes.count) makes")
        } catch {
            logger.error("Failed to pre-warm hierarchy: \(error.localizedDescription)")
        }
    }

    @MainActor
    func generateHierarchy() async {
        guard let manager = regularizationManager else {
            logger.error("RegularizationManager not available")
            return
        }

        isLoadingHierarchy = true

        do {
            let hierarchy = try await manager.generateCanonicalHierarchy(forceRefresh: true)
            canonicalHierarchy = hierarchy
            isLoadingHierarchy = false
            logger.info("Generated hierarchy with \(hierarchy.makes.count) makes")
        } catch {
            logger.error("Error generating hierarchy: \(error.localizedDescription)")
            isLoadingHierarchy = false
        }
    }

    @MainActor
    func saveMapping() async {
        guard let manager = regularizationManager,
              let pair = selectedPair,
              let canonicalMake = selectedCanonicalMake,
              let canonicalModel = selectedCanonicalModel else {
            return
        }

        isSaving = true

        do {
            // Resolve vehicle type ID (handle "Unknown" placeholder ID -1)
            var vehicleTypeId = selectedVehicleTypeId

            if selectedVehicleTypeId == -1 {
                logger.debug("Resolving placeholder VehicleType ID -1 (Unknown)")
                let enumManager = CategoricalEnumManager(databaseManager: databaseManager)
                if let resolvedId = try await enumManager.getEnumId(
                    table: "vehicle_type_enum",
                    column: "code",
                    value: "UK"
                ) {
                    vehicleTypeId = resolvedId
                    logger.debug("Resolved VehicleType 'UK' to ID \(resolvedId)")
                } else {
                    logger.error("Failed to resolve VehicleType 'UK' - will save as NULL")
                    vehicleTypeId = nil
                }
            }

            // STEP 1: Create ONE wildcard mapping with VehicleType only (FuelType = NULL)
            let vtIdString = vehicleTypeId != nil ? String(vehicleTypeId!) : "nil"
            logger.debug("💾 About to save wildcard: vehicleTypeId=\(vtIdString)")

            try await manager.saveMapping(
                uncuratedMakeId: pair.makeId,
                uncuratedModelId: pair.modelId,
                modelYearId: nil,  // Wildcard (applies to all years)
                canonicalMakeId: canonicalMake.id,
                canonicalModelId: canonicalModel.id,
                fuelTypeId: nil,   // FuelType will be set by triplets
                vehicleTypeId: vehicleTypeId
            )

            // Log vehicle type description for debugging
            let vtDesc = vehicleTypeId != nil ? (allVehicleTypes.first(where: { $0.id == vehicleTypeId })?.description ?? "ID:\(vehicleTypeId!)") : "NULL"
            logger.info("Saved wildcard mapping: \(pair.makeModelDisplay) → \(canonicalMake.name)/\(canonicalModel.name), VehicleType=\(vtDesc)")

            // STEP 2: Create triplet mappings for ALL model years (with user selections or NULL)
            var tripletCount = 0
            var assignedCount = 0
            var unknownCount = 0

            if let model = selectedCanonicalModel {
                // Iterate through all uncurated model years (includes non-canonical years like 2024, 2025)
                for modelYear in uncuratedModelYears {
                    // Get user selection for this year (nil = Not Assigned, -1 = Unknown, or specific ID)
                    let selectedFuelTypeId = selectedFuelTypesByModelYear[modelYear] ?? nil

                    // Look up yearId from model year value
                    // First try to find it in canonical hierarchy
                    var yearId: Int? = nil
                    for (candidateYearId, fuelTypes) in model.modelYearFuelTypes {
                        if let unwrappedYearId = candidateYearId,
                           let firstFuel = fuelTypes.first,
                           firstFuel.modelYear == modelYear {
                            yearId = unwrappedYearId
                            break
                        }
                    }

                    // If not in canonical hierarchy, look up from enum table
                    if yearId == nil {
                        let enumManager = CategoricalEnumManager(databaseManager: databaseManager)
                        yearId = try await enumManager.getEnumId(
                            table: "model_year_enum",
                            column: "year",
                            value: String(modelYear)
                        )
                    }

                    guard let yearId = yearId else {
                        logger.warning("Could not find yearId for model year \(modelYear) - skipping")
                        continue
                    }

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
                            logger.warning("'Unknown' fuel type (code 'U') not found in enum table - saving as NULL")
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
                }
            }

            logger.info("Saved \(tripletCount) triplet mappings: \(assignedCount) assigned, \(unknownCount) unknown, \(tripletCount - assignedCount - unknownCount) not assigned")

            // Reload existing mappings to update status indicators (MUST wait before reloading form)
            await loadExistingMappingsAsync()

            // Reload the mapping for the current pair to show updated form fields
            await loadMappingForSelectedPair()

            // Update the status for the affected pair in the uncurated pairs list
            if let index = uncuratedPairs.firstIndex(where: { $0.id == pair.id }) {
                // Recompute status with updated mappings
                let key = "\(pair.makeId)_\(pair.modelId)"
                let pairMappings = existingMappings[key] ?? []

                // Get mappings dict in the format expected by computeRegularizationStatus
                var mappingsDict: [String: [RegularizationMapping]] = [:]
                for mapping in pairMappings {
                    let key = "\(mapping.uncuratedMakeId)_\(mapping.uncuratedModelId)"
                    if mappingsDict[key] == nil {
                        mappingsDict[key] = []
                    }
                    mappingsDict[key]?.append(mapping)
                }

                let yearRange = pair.earliestYear...pair.latestYear
                let newStatus = await manager.computeRegularizationStatus(
                    forKey: key,
                    mappings: mappingsDict,
                    yearRange: yearRange
                )

                // Recompute vehicleTypeId from updated mappings
                let vehicleTypeId: Int? = {
                    guard let pairMappings = existingMappings[key] else { return nil }
                    guard let wildcardMapping = pairMappings.first(where: { $0.modelYearId == nil }) else { return nil }
                    return wildcardMapping.vehicleTypeId
                }()

                // Update the pair with new status and vehicleTypeId
                var updatedPair = pair
                updatedPair.regularizationStatus = newStatus
                updatedPair.vehicleTypeId = vehicleTypeId
                uncuratedPairs[index] = updatedPair

                let statusString = switch newStatus {
                case .unassigned: "unassigned"
                case .partial: "partial"
                case .complete: "complete"
                }
                logger.debug("Updated status for \(pair.makeModelDisplay): \(statusString)")
            }

            // Invalidate cache ONCE after all saves (wildcard + all triplets)
            Task {
                do {
                    try await databaseManager.invalidateUncuratedPairsCache()
                    logger.info("Invalidated uncurated pairs cache after batch save")
                } catch {
                    logger.error("Failed to invalidate cache: \(error.localizedDescription)")
                }
            }

        } catch {
            logger.error("Error saving mapping: \(error.localizedDescription)")
        }

        isSaving = false
    }

    @MainActor
    func clearMappingSelection() {
        selectedPair = nil
        clearMappingFormFields()
    }

    @MainActor
    func clearMappingFormFields() {
        selectedCanonicalMake = nil
        selectedCanonicalModel = nil
        selectedVehicleTypeId = nil
        selectedFuelTypesByModelYear = [:]
        uncuratedModelYears = []
        uncuratedModelYearCounts = [:]
    }

    // MARK: - Year-Based Fuel Type Selection Methods

    /// Get the selected fuel type ID for a given model year
    /// Returns: fuel type ID, -1 for "Unknown", or nil for "Not Assigned"
    @MainActor
    func getSelectedFuelType(forModelYear modelYear: Int) -> Int? {
        return selectedFuelTypesByModelYear[modelYear] ?? nil
    }

    /// Set the fuel type for a specific model year
    /// Pass nil for "Not Assigned", -1 for "Unknown", or a specific fuel type ID
    @MainActor
    func setFuelType(modelYear: Int, fuelTypeId: Int?) {
        selectedFuelTypesByModelYear[modelYear] = fuelTypeId
    }

    /// Check if all model years have assigned fuel types (not "Not Assigned")
    /// Returns true if all years have either a specific fuel type or "Unknown" (-1)
    @MainActor
    func allFuelTypesAssigned(for model: MakeModelHierarchy.Model) -> Bool {
        // Check ALL uncurated model years (not just canonical years)
        for modelYear in uncuratedModelYears {
            let selection = selectedFuelTypesByModelYear[modelYear] ?? nil
            if selection == nil {
                return false  // "Not Assigned" found
            }
        }
        return true
    }

    /// Auto-regularize pairs where Make/Model exactly match curated pairs
    nonisolated func autoRegularizeExactMatchesAsync() async {
        guard let manager = regularizationManager else {
            logger.error("RegularizationManager not available for auto-regularization")
            return
        }

        // Wait for hierarchy to be pre-warmed by background task (avoid duplicate generation)
        // Poll for up to 60 seconds, checking every 0.5s
        var hierarchy = await MainActor.run { canonicalHierarchy }
        var waitAttempts = 0
        while hierarchy == nil && waitAttempts < 120 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            hierarchy = await MainActor.run { canonicalHierarchy }
            waitAttempts += 1
        }

        if hierarchy == nil {
            logger.warning("Hierarchy not ready after 60s, skipping auto-regularization")
            return
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        await MainActor.run {
            self.isAutoRegularizing = true
        }

        // Build a lookup of canonical Make/Model combinations with their metadata
        var canonicalPairs: [String: MakeModelHierarchy.Model] = [:]
        for make in hierarchy!.makes {
            for model in make.models {
                let key = "\(make.name)/\(model.name)"
                canonicalPairs[key] = model
            }
        }

        // Wait for uncurated pairs to be loaded by loadUncuratedPairs() task (avoid duplicate query)
        // Poll for up to 60 seconds, checking every 0.5s
        var allUncuratedPairs = await MainActor.run { uncuratedPairs }
        var pairsWaitAttempts = 0
        while allUncuratedPairs.isEmpty && pairsWaitAttempts < 120 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            allUncuratedPairs = await MainActor.run { uncuratedPairs }
            pairsWaitAttempts += 1
        }

        if allUncuratedPairs.isEmpty {
            logger.info("No uncurated pairs loaded after 60s, skipping auto-regularization")
            await MainActor.run {
                self.isAutoRegularizing = false
            }
            return
        }

        // Get existingMappings snapshot
        let existingMappingsSnapshot = await MainActor.run { existingMappings }

        // Capture AppSettings values before entering loop (avoid main actor access in nonisolated context)
        let useCardinalTypes = await MainActor.run { AppSettings.shared.useCardinalTypes }
        let cardinalCodes = await MainActor.run { AppSettings.shared.cardinalVehicleTypeCodes }

        // Find uncurated pairs that exactly match
        var autoRegularizedCount = 0
        for pair in allUncuratedPairs {
            let pairKey = "\(pair.makeName)/\(pair.modelName)"

            // Check if this pair already has a mapping (check if array is non-empty)
            let key = "\(pair.makeId)_\(pair.modelId)"
            let mappings = existingMappingsSnapshot[key] ?? []
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

                    if validVehicleTypes.count > 1 && useCardinalTypes {
                        for cardinalCode in cardinalCodes {
                            if let matchingType = validVehicleTypes.first(where: { $0.code == cardinalCode }) {
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
                        fuelType.id != -1 &&  // Filter out placeholder entries for NULL fuel types
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
                } catch {
                    logger.error("Error auto-regularizing \(pairKey): \(error.localizedDescription)")
                }
            }
        }

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        if autoRegularizedCount > 0 {
            logger.notice("Auto-regularized \(autoRegularizedCount) exact matches in \(String(format: "%.3f", duration))s")
            // Reload mappings in background - don't block UI with immediate status recalculation
            // The UI will update naturally when users interact with the list
            await loadExistingMappingsAsync()
            logger.info("Background auto-regularization complete - status indicators will update on next refresh")
        } else {
            logger.debug("No exact matches found for auto-regularization")
        }

        await MainActor.run {
            self.isAutoRegularizing = false
        }
    }

    /// Helper: Get all mappings for a Make/Model pair (includes triplets and wildcards)
    @MainActor
    func getMappingsForPair(_ makeId: Int, _ modelId: Int) -> [RegularizationMapping] {
        let key = "\(makeId)_\(modelId)"
        return existingMappings[key] ?? []
    }

    /// Helper: Get the wildcard mapping for a pair (model_year_id = NULL)
    @MainActor
    func getWildcardMapping(for pair: UnverifiedMakeModelPair) -> RegularizationMapping? {
        let allMappings = getMappingsForPair(pair.makeId, pair.modelId)
        let wildcard = allMappings.first { $0.modelYearId == nil }
        logger.debug("getWildcardMapping: \(allMappings.count) total mappings, wildcard vehicleType: \(wildcard?.vehicleType ?? "nil")")
        return wildcard
    }

    /// Helper: Get vehicle type code from description
    @MainActor
    func getVehicleTypeCode(for description: String) -> String? {
        // Check in allVehicleTypes first (includes all types from schema)
        if let vehicleType = allVehicleTypes.first(where: { $0.description == description }) {
            return vehicleType.code
        }
        // Fallback to regularization vehicle types
        if let vehicleType = regularizationVehicleTypes.first(where: { $0.description == description }) {
            return vehicleType.code
        }
        return nil
    }

    /// Helper: Get field assignment status for a pair
    /// Returns tuple: (hasMakeModel, hasVehicleType, hasFuelTypes)
    /// Note: hasFuelTypes only true if status is .complete (ALL model years assigned)
    @MainActor
    func getFieldAssignmentStatus(for pair: UnverifiedMakeModelPair) -> (makeModel: Bool, vehicleType: Bool, fuelTypes: Bool) {
        let mappings = getMappingsForPair(pair.makeId, pair.modelId)

        // If no mappings, nothing is assigned
        guard !mappings.isEmpty else {
            return (makeModel: false, vehicleType: false, fuelTypes: false)
        }

        // Make/Model always assigned if any mapping exists
        let hasMakeModel = true

        // Check vehicle type (from wildcard mapping)
        let wildcardMapping = mappings.first { $0.modelYearId == nil }
        let hasVehicleType = wildcardMapping?.vehicleTypeId != nil

        // Fuel types only considered complete if status is .complete
        // (meaning ALL model years have assigned fuel types, not just some)
        let hasFuelTypes = pair.regularizationStatus == .complete

        return (makeModel: hasMakeModel, vehicleType: hasVehicleType, fuelTypes: hasFuelTypes)
    }

    /// Auto-populate Vehicle Type and Fuel Types when user selects a canonical Make/Model
    /// This enhances UX for 'Unassigned' pairs by suggesting values from the canonical hierarchy
    @MainActor
    func autoPopulateFieldsForNewModel() async {
        guard let model = selectedCanonicalModel else { return }

        // Only auto-populate if this appears to be a new assignment (no existing mappings)
        // Check if we're working with an 'Unassigned' pair
        guard let pair = selectedPair else { return }
        let existingMappings = getMappingsForPair(pair.makeId, pair.modelId)

        // If mappings already exist, don't auto-populate (preserve user's existing work)
        if !existingMappings.isEmpty {
            logger.debug("Skipping auto-population - existing mappings found for \(pair.makeModelDisplay)")
            return
        }

        logger.debug("Auto-populating fields for newly assigned model: \(model.name)")

        // STEP 1: Auto-populate Vehicle Type
        // Strategy: Use cardinal type matching (same logic as auto-regularization)
        let validVehicleTypes = model.vehicleTypes.filter { vehicleType in
            !vehicleType.description.localizedCaseInsensitiveContains("not specified") &&
            !vehicleType.description.localizedCaseInsensitiveContains("not assigned") &&
            !vehicleType.description.localizedCaseInsensitiveContains("non spécifié")
        }

        if validVehicleTypes.count == 1 {
            // Single vehicle type - auto-assign it
            selectedVehicleTypeId = validVehicleTypes.first?.id
        } else if validVehicleTypes.count > 1 && AppSettings.shared.useCardinalTypes {
            // Multiple types - try cardinal matching
            let cardinalCodes = AppSettings.shared.cardinalVehicleTypeCodes
            for cardinalCode in cardinalCodes {
                if let matchingType = validVehicleTypes.first(where: { $0.code == cardinalCode }) {
                    selectedVehicleTypeId = matchingType.id
                    break
                }
            }
        }

        // STEP 2: Auto-populate Fuel Types by Model Year
        // Strategy: Only auto-assign if a model year has exactly ONE valid fuel type
        for (modelYearId, fuelTypes) in model.modelYearFuelTypes {
            guard modelYearId != nil else { continue }

            let validFuelTypes = fuelTypes.filter { fuelType in
                fuelType.id != -1 &&  // Filter out placeholder entries
                !fuelType.description.localizedCaseInsensitiveContains("not specified") &&
                !fuelType.description.localizedCaseInsensitiveContains("not assigned") &&
                !fuelType.description.localizedCaseInsensitiveContains("non spécifié")
            }

            if validFuelTypes.count == 1, let fuelType = validFuelTypes.first {
                // Single fuel type - auto-assign it
                // modelYearId is actually the yearId, need to convert to modelYear
                if let modelYear = fuelType.modelYear {
                    selectedFuelTypesByModelYear[modelYear] = fuelType.id
                }
            }
        }

        let assignedVT = selectedVehicleTypeId != nil
        let assignedFT = selectedFuelTypesByModelYear.values.filter { $0 != nil }.count
        logger.debug("Auto-population complete: VehicleType=\(assignedVT), FuelTypes=\(assignedFT)/\(self.uncuratedModelYears.count)")
    }

    /// Load existing mapping data for the selected pair
    @MainActor
    func loadMappingForSelectedPair() async {
        guard let pair = selectedPair else {
            clearMappingFormFields()
            return
        }

        // Load model years that exist in uncurated data for this pair
        let manager = RegularizationManager(databaseManager: databaseManager)
        do {
            self.uncuratedModelYears = try await manager.getModelYearsForUncuratedPair(
                makeId: pair.makeId,
                modelId: pair.modelId
            )
            logger.debug("Loaded \(self.uncuratedModelYears.count) uncurated model years: \(self.uncuratedModelYears)")
        } catch {
            logger.error("Failed to load uncurated model years: \(error.localizedDescription)")
            self.uncuratedModelYears = []
        }

        // Load record counts per model year for prioritization
        do {
            self.uncuratedModelYearCounts = try await manager.getModelYearCountsForUncuratedPair(
                makeId: pair.makeId,
                modelId: pair.modelId
            )
            let totalRecords = self.uncuratedModelYearCounts.values.reduce(0, +)
            logger.debug("Loaded model year counts: \(totalRecords) total records across \(self.uncuratedModelYearCounts.count) model years")
        } catch {
            logger.error("Failed to load model year counts: \(error.localizedDescription)")
            self.uncuratedModelYearCounts = [:]
        }

        // Ensure hierarchy is loaded (wait if it's still loading in background)
        var hierarchy = canonicalHierarchy
        if hierarchy == nil {
            logger.debug("Hierarchy not ready, generating now for \(pair.makeModelDisplay)")
            await generateHierarchy()
            hierarchy = canonicalHierarchy
            guard hierarchy != nil else {
                logger.error("Failed to generate hierarchy for mapping lookup")
                clearMappingFormFields()
                return
            }
        }

        // Get the wildcard mapping for this pair (form editor uses wildcard for UI display)
        let mapping = getWildcardMapping(for: pair)

        logger.debug("🔍 loadMappingForSelectedPair for \(pair.makeModelDisplay)")
        logger.debug("  Wildcard mapping exists: \(mapping != nil)")
        if let mapping = mapping {
            logger.debug("  Mapping vehicleType: \(mapping.vehicleType ?? "nil")")
            logger.debug("  Mapping fuelType: \(mapping.fuelType ?? "nil")")
        }

        // Try to find canonical Make/Model for this pair
        // First check if there's an existing mapping
        var canonicalMakeName: String?
        var canonicalModelName: String?

        if let mapping = mapping {
            // Use wildcard mapping's canonical values
            canonicalMakeName = mapping.canonicalMake
            canonicalModelName = mapping.canonicalModel
            logger.debug("  Using canonical: \(canonicalMakeName!)/\(canonicalModelName!)")
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

            logger.debug("  Searching hierarchy for \(canonicalMakeName)/\(canonicalModelName)")

            if let make = hierarchy!.makes.first(where: { $0.name == canonicalMakeName }) {
                selectedCanonicalMake = make
                logger.debug("  ✅ Found make in hierarchy")

                // Find the canonical model
                if let model = make.models.first(where: { $0.name == canonicalModelName }) {
                    selectedCanonicalModel = model
                    logger.debug("  ✅ Found model in hierarchy, vehicleTypes count: \(model.vehicleTypes.count)")

                    // Reset type selections first (in case mapping has NULL values)
                    selectedVehicleTypeId = nil

                    // Find the vehicle type if assigned (only from existing mapping)
                    // Use integer ID directly (matches picker's tag values)
                    if let mapping = mapping, let vehicleTypeId = mapping.vehicleTypeId {
                        logger.debug("Loading vehicle type ID from mapping: \(vehicleTypeId)")
                        selectedVehicleTypeId = vehicleTypeId

                        // Log for debugging (optional - look up description)
                        if let vtInfo = allVehicleTypes.first(where: { $0.id == vehicleTypeId }) {
                            logger.debug("✅ Set selectedVehicleTypeId: \(vehicleTypeId) (\(vtInfo.code) - \(vtInfo.description))")
                        } else {
                            logger.debug("✅ Set selectedVehicleTypeId: \(vehicleTypeId) (not in allVehicleTypes, might be UK)")
                        }
                    }

                    // Populate year-based fuel type radio selections from triplet mappings
                    selectedFuelTypesByModelYear = [:]
                    let allMappings = getMappingsForPair(pair.makeId, pair.modelId)

                    for mapping in allMappings {
                        // Only process triplet mappings (those with model_year_id set)
                        if let yearId = mapping.modelYearId {
                            // Convert yearId to modelYear value
                            var modelYear: Int? = nil

                            // First try to find it in canonical hierarchy
                            for (candidateYearId, fuelTypes) in model.modelYearFuelTypes {
                                if candidateYearId == yearId, let firstFuel = fuelTypes.first {
                                    modelYear = firstFuel.modelYear
                                    break
                                }
                            }

                            // If not in canonical hierarchy, look it up from RegularizationMapping
                            if modelYear == nil, let mappingYear = mapping.modelYear {
                                modelYear = mappingYear
                            }

                            guard let modelYear = modelYear else {
                                logger.warning("Could not find model year for yearId \(yearId) - skipping")
                                continue
                            }

                            if let fuelTypeName = mapping.fuelType {
                                // Check if this is "Unknown"
                                if fuelTypeName == "Unknown" {
                                    selectedFuelTypesByModelYear[modelYear] = -1
                                } else {
                                    // Find the fuel type ID by matching description
                                    // Try canonical hierarchy first
                                    var fuelTypeId: Int? = nil
                                    if let yearFuelTypes = model.modelYearFuelTypes[yearId] {
                                        fuelTypeId = yearFuelTypes.first(where: { $0.description == fuelTypeName })?.id
                                    }
                                    // If not found, try allFuelTypes
                                    if fuelTypeId == nil {
                                        fuelTypeId = allFuelTypes.first(where: { $0.description == fuelTypeName })?.id
                                    }
                                    if let fuelTypeId = fuelTypeId {
                                        selectedFuelTypesByModelYear[modelYear] = fuelTypeId
                                    }
                                }
                            } else {
                                // Fuel type is NULL (Not Assigned)
                                selectedFuelTypesByModelYear[modelYear] = nil
                            }
                        }
                    }
                }
            }

            let vtDesc = selectedVehicleTypeId != nil ? String(selectedVehicleTypeId!) : "nil"
            logger.debug("  Final state - selectedVehicleTypeId: \(vtDesc)")
            logger.debug("Loaded mapping for \(pair.makeModelDisplay): \(mapping != nil ? "existing" : "exact match")")
        } else {
            // No mapping and no exact match - clear form fields but keep pair selected
            // User can manually select canonical Make/Model for typo corrections
            clearMappingFormFields()
            logger.debug("No auto-population for \(pair.makeModelDisplay) - manual mapping required")
        }
    }
}

// MARK: - Status Filter Button

struct StatusFilterButton: View {
    @Binding var isSelected: Bool
    let label: String
    let count: Int
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
                    .lineLimit(1)

                Text("(\(count))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle)
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
        .help(isSelected ? "Hide \(label.lowercased()) Make/Model pairs (\(count) total)" : "Show \(label.lowercased()) Make/Model pairs (\(count) total)")
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
