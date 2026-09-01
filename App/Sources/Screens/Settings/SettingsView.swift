import SwiftUI
import JawAtlasCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    @State private var isRestoringDemo = false

    var body: some View {
        NavigationStack {
            List {
                Section("Storage") {
                    LabeledContent("Scans", value: "\(environment.cases.count)")
                    LabeledContent("Space used", value: totalStorage)
                    ForEach(environment.cases) { record in
                        LabeledContent(record.label, value: record.storageDescription)
                            .font(.caption)
                    }
                }
                Section("Demo Scan") {
                    Button {
                        restoreDemo()
                    } label: {
                        if isRestoringDemo {
                            Label("Restoring…", systemImage: "arrow.clockwise")
                        } else {
                            Label("Restore Demo Scan", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isRestoringDemo || environment.isBusy)
                }
                Section("Security") {
                    Toggle(isOn: Binding(
                        get: { environment.appLock.isEnabled },
                        set: { enabled in Task { await environment.appLock.setEnabled(enabled) } }
                    )) {
                        Label("Require \(environment.appLock.biometryName) to open", systemImage: "faceid")
                    }
                    .disabled(!environment.appLock.isAvailable)
                    if !environment.appLock.isAvailable {
                        Text("Set a device passcode to use the app lock.")
                            .font(.caption)
                            .foregroundStyle(Color.dsTextSecondary)
                    }
                    Text("Scan files are stored encrypted by iOS and never leave this device.")
                        .font(.caption)
                        .foregroundStyle(Color.dsTextSecondary)
                }
                Section("Importing Scans") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Export a study as DICOM, compress the folder to a ZIP, and AirDrop it to this device. Choose JawAtlas when asked which app to open it with.")
                            .font(.caption)
                            .foregroundStyle(Color.dsTextSecondary)
                        Text("You can also copy DICOM folders into the JawAtlas folder in the Files app and use Import from Files.")
                            .font(.caption)
                            .foregroundStyle(Color.dsTextSecondary)
                    }
                }
                Section("About") {
                    LabeledContent("App", value: "JawAtlas")
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Made for", value: "Education and training")
                }
                Section("Privacy") {
                    Label("All scans stay on this device", systemImage: "lock.shield")
                    Label("No cloud, no accounts, no analytics", systemImage: "wifi.slash")
                    Text("Only technical imaging tags are read from DICOM files. Patient names, identifiers and contact details are never written to storage, and every import is checked before it is saved.")
                        .font(.caption)
                        .foregroundStyle(Color.dsTextSecondary)
                }
                Section("Intended Use") {
                    Label("Education and training aid", systemImage: "graduationcap")
                    Text("JawAtlas is made for learning to read CBCT anatomy and for exploring scans in teaching and research. It is not a medical device and must not be used for diagnosis or treatment decisions.")
                        .font(.caption)
                        .foregroundStyle(Color.dsTextSecondary)
                }
                Section("Demo Scan Attribution") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lan Feng, Zhi Li, Qihang Gu, Yaqi Wang, Xiaoyang Yu. Adults' dental cone beam computed tomography images dataset for detecting and classifying missing teeth. Science Data Bank, 2026.")
                            .font(.caption)
                            .foregroundStyle(Color.dsTextPrimary)
                        Text("doi.org/10.57760/sciencedb.26465")
                            .font(.caption.monospaced())
                            .foregroundStyle(Color.dsTextSecondary)
                        Text("Licensed under Creative Commons Attribution 4.0 International (CC BY 4.0). Case M29, used unmodified as the bundled demo scan. The dataset is published de-identified, and JawAtlas additionally reads only technical imaging tags.")
                            .font(.caption)
                            .foregroundStyle(Color.dsTextSecondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var totalStorage: String {
        ByteCountFormatter.string(fromByteCount: environment.totalStorageBytes(), countStyle: .file)
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func restoreDemo() {
        isRestoringDemo = true
        Task {
            await environment.seedDemo()
            isRestoringDemo = false
        }
    }
}
