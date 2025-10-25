//
//  RWISettings.swift
//  SAAQAnalyzer
//
//  Created on 2025-10-24.
//  Settings UI for Road Wear Index configuration
//

import SwiftUI
import OSLog
import UniformTypeIdentifiers

struct RWISettingsView: View {
    @State private var configManager = RWIConfigurationManager.shared
    @State private var showingResetConfirmation = false
    @State private var editingAxleConfig: AxleConfiguration?
    @State private var editingVehicleType: VehicleTypeFallback?
    @State private var showingExportPanel = false
    @State private var showingImportPanel = false
    @State private var alertMessage: AlertMessage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Overview Section
                overviewSection

                Divider()

                // Axle-Based Coefficients Section
                axleCoefficientsSection

                Divider()

                // Vehicle Type Fallbacks Section
                vehicleTypeFallbacksSection

                Divider()

                // Advanced Options (placeholder)
                advancedOptionsSection

                Divider()

                // Action Buttons
                actionButtonsSection
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 600)
        .sheet(item: $editingAxleConfig) { config in
            AxleConfigEditView(configuration: config) { updated in
                configManager.updateAxleConfiguration(updated)
                editingAxleConfig = nil
            } onCancel: {
                editingAxleConfig = nil
            }
        }
        .sheet(item: $editingVehicleType) { fallback in
            VehicleTypeFallbackEditView(fallback: fallback) { updated in
                configManager.updateVehicleTypeFallback(updated)
                editingVehicleType = nil
            } onCancel: {
                editingVehicleType = nil
            }
        }
        .confirmationDialog("Reset All RWI Settings?", isPresented: $showingResetConfirmation) {
            Button("Reset to Defaults", role: .destructive) {
                configManager.resetToDefaults()
                alertMessage = AlertMessage(
                    title: "Settings Reset",
                    message: "All Road Wear Index settings have been restored to their default values."
                )
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore all Road Wear Index settings to their default values. This action cannot be undone.")
        }
        .alert(item: $alertMessage) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Overview Section

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Road Wear Index Overview", systemImage: "truck.box.fill")
                .font(.headline)

            Text("""
            The Road Wear Index (RWI) quantifies infrastructure impact using the 4th power law:

            Road Damage ∝ (Axle Load)⁴

            This means a vehicle with twice the axle load causes 16× the road damage. The calculation uses:

            • Actual axle count data when available (BCA trucks)
            • Vehicle type assumptions as fallback (when axle data is NULL)
            • Net vehicle mass (kg) from SAAQ records

            Example: A 6-axle truck causes 97% less damage per kg than a 2-axle truck due to weight distribution.
            """)
            .font(.body)
            .foregroundColor(.secondary)
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Axle-Based Coefficients Section

    private var axleCoefficientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Axle-Based Weight Distribution", systemImage: "gauge")
                .font(.headline)

            Text("Used when max_axles data is available")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Axles")
                        .frame(width: 60, alignment: .leading)
                    Text("Weight Distribution")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Coefficient")
                        .frame(width: 100, alignment: .trailing)
                    Text("")
                        .frame(width: 60)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                // Rows
                ForEach([2, 3, 4, 5, 6], id: \.self) { axleCount in
                    if let config = configManager.configuration.axleConfigurations[axleCount] {
                        axleConfigRow(config: config)
                        Divider()
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            Button("Reset Axle Coefficients to Defaults") {
                resetAxleCoefficientsToDefaults()
            }
            .buttonStyle(.bordered)
        }
    }

    private func axleConfigRow(config: AxleConfiguration) -> some View {
        HStack {
            Text(config.axleCount == 6 ? "6+" : "\(config.axleCount)")
                .frame(width: 60, alignment: .leading)
                .font(.body.monospacedDigit())

            Text(config.distributionDescription)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.4f", config.coefficient))
                .frame(width: 100, alignment: .trailing)
                .font(.body.monospacedDigit())

            Button(action: {
                editingAxleConfig = config
            }) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .frame(width: 60)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Vehicle Type Fallbacks Section

    private var vehicleTypeFallbacksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Vehicle Type Fallbacks", systemImage: "car.fill")
                .font(.headline)

            Text("Used when max_axles is NULL")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Type")
                        .frame(width: 50, alignment: .leading)
                    Text("Description")
                        .frame(width: 100, alignment: .leading)
                    Text("Axles")
                        .frame(width: 50, alignment: .center)
                    Text("Weight Dist")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Coefficient")
                        .frame(width: 100, alignment: .trailing)
                    Text("")
                        .frame(width: 60)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                // Rows (sorted by type code)
                ForEach(["CA", "VO", "AB", "AU", "*"], id: \.self) { typeCode in
                    if let fallback = configManager.configuration.vehicleTypeFallbacks[typeCode] {
                        vehicleTypeFallbackRow(fallback: fallback)
                        Divider()
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            Button("Reset Vehicle Type Fallbacks to Defaults") {
                resetVehicleTypeFallbacksToDefaults()
            }
            .buttonStyle(.bordered)
        }
    }

    private func vehicleTypeFallbackRow(fallback: VehicleTypeFallback) -> some View {
        HStack {
            Text(fallback.typeCode)
                .frame(width: 50, alignment: .leading)
                .font(.body.monospacedDigit())

            Text(fallback.description)
                .frame(width: 100, alignment: .leading)

            Text("\(fallback.assumedAxles)")
                .frame(width: 50, alignment: .center)
                .font(.body.monospacedDigit())

            Text(fallback.distributionDescription)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.4f", fallback.coefficient))
                .frame(width: 100, alignment: .trailing)
                .font(.body.monospacedDigit())

            Button(action: {
                editingVehicleType = fallback
            }) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .frame(width: 60)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Advanced Options Section

    private var advancedOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Advanced Options", systemImage: "gearshape.2")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundColor(.secondary)
                    Text("Coming Soon")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                Text("""
                Future capabilities:
                • Make/Model-specific mass overrides
                • Make/Model-specific axle count defaults
                • Useful for uncurated years with incomplete data

                This feature will allow you to define defaults for new vehicle combinations appearing in recent years.
                """)
                .font(.body)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Action Buttons Section

    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            Button("Reset All to Defaults") {
                showingResetConfirmation = true
            }
            .buttonStyle(.bordered)

            Button("Export Config...") {
                exportConfiguration()
            }
            .buttonStyle(.bordered)

            Button("Import Config...") {
                importConfiguration()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }

    // MARK: - Helper Functions

    private func resetAxleCoefficientsToDefaults() {
        let defaults = RWIConfigurationData.defaultConfiguration
        for (_, config) in defaults.axleConfigurations {
            configManager.updateAxleConfiguration(config)
        }
        alertMessage = AlertMessage(
            title: "Axle Coefficients Reset",
            message: "Axle-based coefficients have been restored to their default values."
        )
    }

    private func resetVehicleTypeFallbacksToDefaults() {
        let defaults = RWIConfigurationData.defaultConfiguration
        for (_, fallback) in defaults.vehicleTypeFallbacks {
            configManager.updateVehicleTypeFallback(fallback)
        }
        alertMessage = AlertMessage(
            title: "Vehicle Type Fallbacks Reset",
            message: "Vehicle type fallbacks have been restored to their default values."
        )
    }

    private func exportConfiguration() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        let dateString = Date().formatted(.iso8601.year().month().day())
        savePanel.nameFieldStringValue = "RWI_Configuration_\(dateString).json"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            do {
                try configManager.exportConfiguration(to: url)
                alertMessage = AlertMessage(
                    title: "Export Successful",
                    message: "Configuration exported to \(url.lastPathComponent)"
                )
            } catch {
                alertMessage = AlertMessage(
                    title: "Export Failed",
                    message: "Failed to export configuration: \(error.localizedDescription)"
                )
            }
        }
    }

    private func importConfiguration() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false

        openPanel.begin { response in
            guard response == .OK, let url = openPanel.urls.first else { return }

            do {
                try configManager.importConfiguration(from: url)
                alertMessage = AlertMessage(
                    title: "Import Successful",
                    message: "Configuration imported from \(url.lastPathComponent)"
                )
            } catch {
                alertMessage = AlertMessage(
                    title: "Import Failed",
                    message: error.localizedDescription
                )
            }
        }
    }
}

// MARK: - Helper Types

struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
