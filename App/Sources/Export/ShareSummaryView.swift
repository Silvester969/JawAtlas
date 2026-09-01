import SwiftUI
import UIKit
import JawAtlasCore

struct ShareSummaryButton: View {
    let caseLabel: String
    let renderer: VolumeRenderer
    let geometry: VolumeGeometry
    let story: StoryState
    var arPhoto: UIImage?

    @State private var showsSheet = false

    var body: some View {
        Button {
            showsSheet = true
        } label: {
            Label("Take-home summary", systemImage: "square.and.arrow.up")
        }
        .sheet(isPresented: $showsSheet) {
            ShareSummaryView(
                caseLabel: caseLabel,
                renderer: renderer,
                geometry: geometry,
                story: story,
                arPhoto: arPhoto
            )
        }
    }
}

struct ShareSummaryView: View {
    let caseLabel: String
    let renderer: VolumeRenderer
    let geometry: VolumeGeometry
    let story: StoryState
    var arPhoto: UIImage?

    @Environment(\.dismiss) private var dismiss
    @State private var summary: CaseSummary?
    @State private var pagePreviews: [UIImage] = []
    @State private var isRendering = false
    @State private var failureMessage: String?
    @State private var sharePayload: SharePayload?

    private struct SharePayload: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    private var isEmpty: Bool {
        story.moments.isEmpty && arPhoto == nil
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Take-home summary")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .task { await prepare() }
        .sheet(item: $sharePayload) { payload in
            ActivityShareView(items: payload.urls)
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var content: some View {
        if isEmpty {
            emptyState
        } else if let failureMessage {
            failureState(failureMessage)
        } else if isRendering || summary == nil {
            VStack(spacing: 14) {
                ProgressView()
                Text("Preparing the summary…")
                    .font(.subheadline)
                    .foregroundStyle(Color.dsTextSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            readyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 40))
                .foregroundStyle(Color.dsTextSecondary)
            Text("Save a few moments first — they become the pages of the exported summary.")
                .font(.body)
                .foregroundStyle(Color.dsTextPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(Color.dsSafetyOrange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.dsTextPrimary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readyState: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(pagePreviews.enumerated()), id: \.offset) { entry in
                        Image(uiImage: entry.element)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.dsSeparator, lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: .infinity)

            VStack(spacing: 10) {
                Button {
                    shareAsPDF()
                } label: {
                    Label("Share as PDF", systemImage: "doc.richtext")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    shareAsPhotos()
                } label: {
                    Label("Share as photos", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(Color.dsBackground)
    }

    private func prepare() async {
        guard !isEmpty, summary == nil, !isRendering else { return }
        isRendering = true
        var rendered: [SummaryMoment] = []
        for moment in story.moments {
            await Task.yield()
            guard let image = MomentImageRenderer.render(
                renderer: renderer,
                geometry: geometry,
                moment: moment
            ) else {
                failureMessage = "The summary could not be prepared on this device."
                isRendering = false
                return
            }
            rendered.append(SummaryMoment(moment: moment, image: image))
        }
        let built = CaseSummary(caseLabel: caseLabel, moments: rendered, arPhoto: arPhoto)
        await Task.yield()
        pagePreviews = built.images()
        summary = built
        isRendering = false
    }

    private var fileDateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: Date())
    }

    private func shareAsPDF() {
        guard let summary else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scan summary \(fileDateText).pdf")
        do {
            try summary.pdfData().write(to: url, options: [.atomic])
            sharePayload = SharePayload(urls: [url])
        } catch {
            failureMessage = "The summary file could not be written."
        }
    }

    private func shareAsPhotos() {
        guard let summary else { return }
        let pages = summary.images()
        var urls: [URL] = []
        do {
            for (index, page) in pages.enumerated() {
                guard let data = page.pngData() else { continue }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Scan summary \(fileDateText) page \(index + 1).png")
                try data.write(to: url, options: [.atomic])
                urls.append(url)
            }
        } catch {
            failureMessage = "The summary files could not be written."
            return
        }
        guard !urls.isEmpty else {
            failureMessage = "The summary files could not be written."
            return
        }
        sharePayload = SharePayload(urls: urls)
    }
}

struct ActivityShareView: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
    }
}
