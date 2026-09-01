import SwiftUI
import JawAtlasCore

struct ImportProgressSheet: View {
    @Bindable var coordinator: ImportCoordinator
    let onOpen: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch coordinator.stage {
                case .idle:
                    Color.clear
                case let .working(progress):
                    workingView(progress)
                case let .failed(message):
                    failureView(message)
                case let .finished(caseID, label):
                    successView(caseID: caseID, label: label)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dsBackground)
            .navigationTitle("Import Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if coordinator.isRunning {
                        Button("Cancel") { coordinator.cancel() }
                    } else {
                        Button("Close") { onClose() }
                    }
                }
            }
            .confirmationDialog(
                "Series has gaps — some slices missing",
                isPresented: gapBinding,
                titleVisibility: .visible
            ) {
                Button("Proceed Anyway") { coordinator.resolveGapWarning(proceed: true) }
                Button("Cancel", role: .cancel) { coordinator.resolveGapWarning(proceed: false) }
            } message: {
                Text("Measurements from a series with missing slices may be less reliable.")
            }
            .confirmationDialog(
                "This scan is already in your library",
                isPresented: duplicateBinding,
                titleVisibility: .visible
            ) {
                Button("Skip") { coordinator.resolveDuplicate(.skip) }
                Button("Import as Copy") { coordinator.resolveDuplicate(.importCopy) }
            } message: {
                Text(duplicateMessage)
            }
            .sheet(isPresented: seriesBinding) {
                SeriesPickerSheet(
                    choices: coordinator.seriesChoices ?? [],
                    onPick: { coordinator.chooseSeries(id: $0) },
                    onCancel: { coordinator.chooseSeries(id: nil) }
                )
            }
        }
        .interactiveDismissDisabled(coordinator.isRunning)
    }

    private func workingView(_ progress: ImportProgress) -> some View {
        VStack(spacing: 18) {
            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
            Text(progress.phase.displayName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.dsTextPrimary)
            Text(progress.countsDescription)
                .font(.body.monospacedDigit())
                .foregroundStyle(Color.dsTextSecondary)
            Text("Elapsed \(elapsedText)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.dsTextSecondary)
            Spacer()
        }
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.dsSafetyOrange)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.dsTextPrimary)
            Button("Close") { onClose() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private func successView(caseID: String, label: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(Color.dsSafetyGreen)
            Text(label)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.dsTextPrimary)
            if let note = coordinator.summaryNote {
                Text(note)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.dsTextSecondary)
            }
            Button("Open now") { onOpen(caseID) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Button("Back to Library") { onClose() }
                .buttonStyle(.bordered)
            Spacer()
        }
    }

    private var elapsedText: String {
        let seconds = Int(coordinator.elapsed)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var duplicateMessage: String {
        coordinator.duplicateChoice.map { "It was imported as \"\($0.existingLabel)\"." } ?? ""
    }

    private var gapBinding: Binding<Bool> {
        Binding(
            get: { coordinator.gapWarningSliceCount != nil },
            set: { if !$0 { coordinator.resolveGapWarning(proceed: false) } }
        )
    }

    private var duplicateBinding: Binding<Bool> {
        Binding(
            get: { coordinator.duplicateChoice != nil },
            set: { if !$0 { coordinator.resolveDuplicate(.skip) } }
        )
    }

    private var seriesBinding: Binding<Bool> {
        Binding(
            get: { coordinator.seriesChoices != nil },
            set: { if !$0 { coordinator.chooseSeries(id: nil) } }
        )
    }
}

struct SeriesPickerSheet: View {
    let choices: [ImportCoordinator.SeriesChoice]
    let onPick: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List(choices) { choice in
                Button {
                    onPick(choice.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(choice.title)
                                .font(.headline)
                                .foregroundStyle(Color.dsTextPrimary)
                            if choice.isRecommended {
                                Text("RECOMMENDED")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.dsSafetyGreenContainer, in: Capsule())
                                    .foregroundStyle(Color.dsSafetyGreen)
                            }
                        }
                        Text(choice.summary)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.dsTextSecondary)
                        if choice.isGapped {
                            Text("Contains gaps")
                                .font(.caption)
                                .foregroundStyle(Color.dsSafetyOrange)
                        }
                    }
                }
            }
            .navigationTitle("Choose a Series")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
        .interactiveDismissDisabled(true)
    }
}
