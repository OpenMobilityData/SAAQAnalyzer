//
//  RWIEditDialogs.swift
//  SAAQAnalyzer
//
//  Created on 2025-10-24.
//  Edit dialogs for RWI configuration
//

import SwiftUI

// MARK: - Axle Configuration Edit View

struct AxleConfigEditView: View {
    let configuration: AxleConfiguration
    let onSave: (AxleConfiguration) -> Void
    let onCancel: () -> Void

    @State private var weightDistribution: [Double]
    @State private var coefficient: Double

    init(configuration: AxleConfiguration, onSave: @escaping (AxleConfiguration) -> Void, onCancel: @escaping () -> Void) {
        self.configuration = configuration
        self.onSave = onSave
        self.onCancel = onCancel
        _weightDistribution = State(initialValue: configuration.weightDistribution)
        _coefficient = State(initialValue: configuration.coefficient)
    }

    private var totalWeight: Double {
        weightDistribution.reduce(0, +)
    }

    private var isValid: Bool {
        abs(totalWeight - 100.0) < 0.01 &&
        weightDistribution.allSatisfy { $0 > 0 && $0 <= 100 }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Edit \(configuration.axleCount == 6 ? "6+" : "\(configuration.axleCount)")-Axle Configuration")
                .font(.headline)

            Divider()

            // Weight distribution fields
            VStack(alignment: .leading, spacing: 12) {
                Text("Weight Distribution:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(weightDistribution.indices, id: \.self) { index in
                    HStack {
                        Text(axleLabel(for: index))
                            .frame(width: 100, alignment: .leading)

                        TextField("Percent", value: $weightDistribution[index], format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onChange(of: weightDistribution[index]) { _, _ in
                                recalculateCoefficient()
                            }

                        Text("%")
                    }
                }

                Divider()

                // Total weight display
                HStack {
                    Text("Total:")
                        .font(.subheadline)
                        .frame(width: 100, alignment: .leading)

                    Text(String(format: "%.1f%%", totalWeight))
                        .font(.body.monospacedDigit())
                        .foregroundColor(isValid ? .green : .red)

                    if isValid {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            // Calculated coefficient
            VStack(alignment: .leading, spacing: 8) {
                Text("Calculated Coefficient:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(String(format: "%.4f", coefficient))
                    .font(.title2.monospacedDigit())

                Text("ℹ️ Coefficient = Σ(weight_fraction⁴)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    var updated = configuration
                    updated.weightDistribution = weightDistribution
                    updated.coefficient = coefficient
                    onSave(updated)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding()
        .frame(width: 400, height: 500)
    }

    private func axleLabel(for index: Int) -> String {
        if configuration.axleCount == 2 {
            return index == 0 ? "Front Axle:" : "Rear Axle:"
        } else if configuration.axleCount == 3 {
            return index == 0 ? "Front Axle:" : "Rear Axle \(index):"
        } else {
            return "Axle \(index + 1):"
        }
    }

    private func recalculateCoefficient() {
        coefficient = weightDistribution
            .map { pow($0 / 100.0, 4) }
            .reduce(0, +)
    }
}

// MARK: - Vehicle Type Fallback Edit View

struct VehicleTypeFallbackEditView: View {
    let fallback: VehicleTypeFallback
    let onSave: (VehicleTypeFallback) -> Void
    let onCancel: () -> Void

    @State private var assumedAxles: Int
    @State private var weightDistribution: [Double]
    @State private var coefficient: Double

    init(fallback: VehicleTypeFallback, onSave: @escaping (VehicleTypeFallback) -> Void, onCancel: @escaping () -> Void) {
        self.fallback = fallback
        self.onSave = onSave
        self.onCancel = onCancel
        _assumedAxles = State(initialValue: fallback.assumedAxles)
        _weightDistribution = State(initialValue: fallback.weightDistribution)
        _coefficient = State(initialValue: fallback.coefficient)
    }

    private var totalWeight: Double {
        weightDistribution.reduce(0, +)
    }

    private var isValid: Bool {
        abs(totalWeight - 100.0) < 0.01 &&
        weightDistribution.count == assumedAxles &&
        weightDistribution.allSatisfy { $0 > 0 && $0 <= 100 } &&
        assumedAxles >= 2 && assumedAxles <= 6
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Edit \(fallback.typeCode) (\(fallback.description)) Fallback")
                .font(.headline)

            Divider()

            // Assumed axles picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Assumed Axle Count:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Assumed Axles", selection: $assumedAxles) {
                    ForEach(2...6, id: \.self) { count in
                        Text("\(count) axles").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: assumedAxles) { oldValue, newValue in
                    updateWeightDistribution(from: oldValue, to: newValue)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            // Weight distribution fields
            VStack(alignment: .leading, spacing: 12) {
                Text("Weight Distribution:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(weightDistribution.indices, id: \.self) { index in
                    HStack {
                        Text("Axle \(index + 1):")
                            .frame(width: 80, alignment: .leading)

                        TextField("Percent", value: $weightDistribution[index], format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onChange(of: weightDistribution[index]) { _, _ in
                                recalculateCoefficient()
                            }

                        Text("%")
                    }
                }

                Divider()

                // Total weight display
                HStack {
                    Text("Total:")
                        .font(.subheadline)
                        .frame(width: 80, alignment: .leading)

                    Text(String(format: "%.1f%%", totalWeight))
                        .font(.body.monospacedDigit())
                        .foregroundColor(isValid ? .green : .red)

                    if isValid {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            // Calculated coefficient
            VStack(alignment: .leading, spacing: 8) {
                Text("Calculated Coefficient:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(String(format: "%.4f", coefficient))
                    .font(.title2.monospacedDigit())

                Text("ℹ️ Coefficient = Σ(weight_fraction⁴)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    var updated = fallback
                    updated.assumedAxles = assumedAxles
                    updated.weightDistribution = weightDistribution
                    updated.coefficient = coefficient
                    onSave(updated)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding()
        .frame(width: 400, height: 550)
    }

    private func updateWeightDistribution(from oldCount: Int, to newCount: Int) {
        if newCount > oldCount {
            // Add axles with equal distribution
            let evenDistribution = 100.0 / Double(newCount)
            weightDistribution = Array(repeating: evenDistribution, count: newCount)
        } else if newCount < oldCount {
            // Remove axles from the end
            weightDistribution = Array(weightDistribution.prefix(newCount))
            // Redistribute to 100%
            let evenDistribution = 100.0 / Double(newCount)
            weightDistribution = Array(repeating: evenDistribution, count: newCount)
        }
        recalculateCoefficient()
    }

    private func recalculateCoefficient() {
        coefficient = weightDistribution
            .map { pow($0 / 100.0, 4) }
            .reduce(0, +)
    }
}
