import SwiftUI
import JawAtlasCore

struct CaseCardView: View {
    let record: CaseRecord
    let isDemo: Bool

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(url: record.thumbnailURL)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.label)
                    .font(.headline)
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(2)
                Text(record.dimensionsDescription)
                    .font(.caption)
                    .foregroundStyle(Color.dsTextSecondary)
                HStack(spacing: 6) {
                    if isDemo { badge("DEMO", color: .dsSafetyGreen, container: .dsSafetyGreenContainer) }
                    if record.isGapped { badge("GAPPED", color: .dsSafetyOrange, container: .dsSafetyOrangeContainer) }
                    Text(record.importedAt, format: .dateTime.day().month().year())
                        .font(.caption)
                        .foregroundStyle(Color.dsTextSecondary)
                }
                if case let .unreadable(message) = record.status {
                    Text("Unreadable — swipe to remove")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.dsSafetyRed)
                        .accessibilityHint(message)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private func badge(_ text: String, color: Color, container: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(container, in: Capsule())
            .foregroundStyle(color)
    }
}

struct ThumbnailView: View {
    let url: URL?
    @State private var image: Image?

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.dsSafetyNeutralContainer)
            .frame(width: 72, height: 72)
            .overlay {
                if let image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.dsTextSecondary)
                }
            }
            .task(id: url) {
                await load()
            }
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }.value
        if let loaded { image = Image(uiImage: loaded) }
    }
}
