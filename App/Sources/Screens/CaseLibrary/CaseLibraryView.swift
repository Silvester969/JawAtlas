import SwiftUI
import UniformTypeIdentifiers
import JawAtlasCore

struct CaseLibraryView: View {
    @Binding var path: [String]
    @Environment(AppEnvironment.self) private var environment
    @State private var coordinator: ImportCoordinator?
    @State private var showSettings = false
    @State private var showFileImporter = false
    @State private var renameTarget: CaseRecord?
    @State private var renameText = ""
    @State private var deleteTarget: CaseRecord?
    @State private var tagTarget: CaseRecord?
    @State private var tagText = ""
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var toast: LibraryToast?

    var body: some View {
        content
            .background(Color.dsBackground)
            .navigationTitle("JawAtlas")
            .navigationDestination(for: String.self) { caseID in
                if let record = environment.cases.first(where: { $0.id == caseID }) {
                    CaseViewerView(record: record)
                } else {
                    MissingCaseView()
                }
            }
            .toolbar { toolbarContent }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.folder, .data],
                allowsMultipleSelection: true
            ) { handleFileImport($0) }
            .sheet(isPresented: importSheetBinding) {
                if let coordinator {
                    ImportProgressSheet(coordinator: coordinator, onOpen: openImported, onClose: closeImport)
                }
            }
            .alert(
                "Case Group",
                isPresented: Binding(get: { tagTarget != nil }, set: { if !$0 { tagTarget = nil } })
            ) {
                TextField("Course, topic or case set", text: $tagText)
                Button("Cancel", role: .cancel) { tagTarget = nil }
                Button("Save") { commitTag() }
            } message: {
                Text("Groups this scan in your library, for example by course, topic or case set.")
            }
            .sheet(isPresented: Binding(
                get: { exportURL != nil },
                set: { if !$0 { exportURL = nil } }
            )) {
                if let exportURL {
                    ActivityShareView(items: [exportURL])
                        .presentationDetents([.medium])
                }
            }
            .alert("Rename Scan", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
                TextField("Label", text: $renameText)
                Button("Cancel", role: .cancel) { renameTarget = nil }
                Button("Save") { commitRename() }
            }
            .confirmationDialog(
                deleteDialogTitle,
                isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete Scan", role: .destructive) { commitDelete() }
                Button("Keep Scan", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("This scan file will be permanently removed from this device. This cannot be undone.")
            }
            .overlay(alignment: .bottom) { toastView }
            .onAppear {
                prepareCoordinator()
                consumePendingImports(environment.pendingImportURLs)
            }
            .onChange(of: environment.pendingImportURLs) { _, urls in
                consumePendingImports(urls)
            }
            .onChange(of: environment.incomingFailureMessage) { _, message in
                if let message {
                    toast = LibraryToast(text: message)
                    environment.clearIncomingFailure()
                }
            }
    }

    private var importSheetBinding: Binding<Bool> {
        Binding(
            get: { coordinator.map { $0.stage != .idle } ?? false },
            set: { isPresented in if !isPresented { coordinator?.dismiss() } }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch environment.state {
        case .loading:
            ProgressView("Opening your library…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .seeding(progress):
            SeedingView(progress: progress)
        case .failed(let message):
            LibraryErrorView(message: message) {
                Task { await environment.refresh() }
            }
        case .ready:
            if environment.cases.isEmpty {
                emptyState
            } else {
                caseList
            }
        }
    }

    private var groupedCases: [(tag: String?, records: [CaseRecord])] {
        let tagged = Dictionary(grouping: environment.cases) { $0.patientTag }
        let names = tagged.keys.compactMap { $0 }.sorted()
        var groups: [(String?, [CaseRecord])] = names.map { ($0, tagged[$0] ?? []) }
        if let untagged = tagged[nil], !untagged.isEmpty {
            groups.append((nil, untagged))
        }
        return groups
    }

    @State private var didAutoNavigate = false

    private func handleLaunchArguments() {
        guard !didAutoNavigate, let first = environment.cases.first else { return }
        let arguments = CommandLine.arguments
        if arguments.contains("-openDemoCase") {
            didAutoNavigate = true
            path = [first.id]
        } else if arguments.contains("-shareCase") {
            didAutoNavigate = true
            shareCase(first)
        } else if arguments.contains("-adoptInbox") {
            didAutoNavigate = true
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            guard let documentsURL = documents.first else { return }
            let archives = ((try? FileManager.default.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: nil
            )) ?? []).filter { $0.pathExtension.lowercased() == "zip" }
            for archive in archives {
                environment.receiveIncoming(url: archive)
            }
        }
    }

    private var caseList: some View {
        List {
            ForEach(groupedCases, id: \.tag) { group in
                Section(group.tag ?? (groupedCases.count > 1 ? "Other scans" : "Scans")) {
                    ForEach(group.records) { record in
                        caseRow(record)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await environment.refresh() }
        .onAppear { handleLaunchArguments() }
        .onChange(of: environment.cases.count) { _, _ in handleLaunchArguments() }
    }

    private func caseRow(_ record: CaseRecord) -> some View {
        NavigationLink(value: record.id) {
            CaseCardView(record: record, isDemo: environment.isDemo(record))
        }
        .listRowBackground(Color.dsCard)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { deleteTarget = record } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                renameText = record.label
                renameTarget = record
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                tagText = record.patientTag ?? ""
                tagTarget = record
            } label: {
                Label("Group", systemImage: "folder.badge.gearshape")
            }
            Button {
                shareCase(record)
            } label: {
                Label("Share Case", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) { deleteTarget = record } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func shareCase(_ record: CaseRecord) {
        guard !isExporting else { return }
        isExporting = true
        toast = LibraryToast(text: "Packing the case…")
        Task {
            let url = await environment.exportCase(record)
            isExporting = false
            if let url {
                exportURL = url
            } else {
                toast = LibraryToast(text: "The case could not be packed.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 48))
                .foregroundStyle(Color.dsTextSecondary)
            Text("No scans yet")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.dsTextPrimary)
            Text("Import a CBCT scan to get started.")
                .font(.body)
                .foregroundStyle(Color.dsTextSecondary)
            Button("Import a Scan") { showFileImporter = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Settings")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Import from Files") { showFileImporter = true }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Import")
            .disabled(environment.isBusy || coordinator?.isRunning == true)
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast.text)
                .font(.footnote)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 24)
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(2.5))
                    self.toast = nil
                }
        }
    }

    private var deleteDialogTitle: String {
        deleteTarget.map { "Delete \($0.label)?" } ?? "Delete scan?"
    }

    private func prepareCoordinator() {
        if coordinator == nil {
            coordinator = ImportCoordinator(environment: environment)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        prepareCoordinator()
        switch result {
        case let .success(urls):
            guard !urls.isEmpty else { return }
            coordinator?.begin(urls: urls)
        case .failure:
            toast = LibraryToast(text: "That selection could not be read.")
        }
    }

    private func openImported(_ caseID: String) {
        coordinator?.dismiss()
        toast = LibraryToast(text: "Scan added to your library")
        path = [caseID]
    }

    private func closeImport() {
        coordinator?.dismiss()
        consumePendingImports(environment.pendingImportURLs)
    }

    private func consumePendingImports(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        prepareCoordinator()
        guard let coordinator, !coordinator.isRunning, coordinator.stage == .idle else { return }
        environment.clearPendingImports()
        coordinator.begin(urls: urls)
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        let label = renameText
        renameTarget = nil
        Task { await environment.rename(target, to: label) }
    }

    private func commitTag() {
        guard let target = tagTarget else { return }
        let tag = tagText
        tagTarget = nil
        Task { await environment.setPatientTag(target, to: tag) }
    }

    private func commitDelete() {
        guard let target = deleteTarget else { return }
        deleteTarget = nil
        Task { await environment.delete(target) }
    }
}

struct LibraryToast: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

struct SeedingView: View {
    let progress: ImportProgress

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
                .frame(maxWidth: 320)
            Text("Preparing the demo scan…")
                .font(.headline)
                .foregroundStyle(Color.dsTextPrimary)
            Text("\(progress.phase.displayName) · \(progress.countsDescription)")
                .font(.caption)
                .foregroundStyle(Color.dsTextSecondary)
                .monospacedDigit()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LibraryErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.dsSafetyOrange)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.dsTextPrimary)
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MissingCaseView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 40))
                .foregroundStyle(Color.dsTextSecondary)
            Text("This scan is no longer stored on this device.")
                .foregroundStyle(Color.dsTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBackground)
    }
}
