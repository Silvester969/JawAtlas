import SwiftUI
import JawAtlasCore

struct StoryStrip: View {
    let model: ViewerModel

    @State private var draftTitle = ""
    @State private var draftCaption = ""
    @State private var showsAddAlert = false
    @State private var renameTargetID: UUID?
    @State private var captionTargetID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                addButton
                ForEach(model.story.moments) { moment in
                    card(for: moment)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .alert("Save this view", isPresented: $showsAddAlert) {
            TextField("Title", text: $draftTitle)
            Button("Save") {
                withAnimation(.snappy) {
                    model.addMoment(title: normalizedTitle(fallback: defaultTitle))
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Give this view a short name so you can bring it back during the visit.")
        }
        .alert("Rename moment", isPresented: renamePresented) {
            TextField("Title", text: $draftTitle)
            Button("Save") {
                if let id = renameTargetID {
                    model.renameMoment(id: id, title: normalizedTitle(fallback: ""))
                }
                renameTargetID = nil
            }
            Button("Cancel", role: .cancel) { renameTargetID = nil }
        }
        .alert("Edit caption", isPresented: captionPresented) {
            TextField("What should the viewer learn here?", text: $draftCaption)
            Button("Save") {
                if let id = captionTargetID {
                    model.setCaption(id: id, caption: draftCaption)
                }
                captionTargetID = nil
            }
            Button("Cancel", role: .cancel) { captionTargetID = nil }
        } message: {
            Text("A short plain sentence shown over the picture, like \"This dark area is the infection\".")
        }
    }

    private var defaultTitle: String {
        "Moment \(model.story.moments.count + 1)"
    }

    private func normalizedTitle(fallback: String) -> String {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { renameTargetID != nil },
            set: { if !$0 { renameTargetID = nil } }
        )
    }

    private var captionPresented: Binding<Bool> {
        Binding(
            get: { captionTargetID != nil },
            set: { if !$0 { captionTargetID = nil } }
        )
    }

    private var addButton: some View {
        Button {
            draftTitle = defaultTitle
            showsAddAlert = true
        } label: {
            Label("Save this view", systemImage: "plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.dsBrandPrimary)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color.dsCard, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.dsBrandPrimary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
        }
        .buttonStyle(.plain)
    }

    private func card(for moment: StoryMoment) -> some View {
        let isActive = model.activeMomentID == moment.id
        return Button {
            withAnimation(.snappy(duration: 0.35)) {
                model.apply(moment)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(moment.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: moment.stage == .volume ? "cube" : "square.split.diagonal")
                        .font(.system(size: 9))
                    Text(moment.stage == .volume ? "3D view" : "Slice view")
                    if !moment.strokesLocalMM.isEmpty {
                        Image(systemName: "pencil.tip")
                            .font(.system(size: 9))
                    }
                }
                .font(.caption2)
                .foregroundStyle(Color.dsTextSecondary)
            }
            .padding(.horizontal, 12)
            .frame(minWidth: 96, minHeight: 44, alignment: .leading)
            .background(
                isActive ? Color.dsBrandPrimary.opacity(0.14) : Color.dsCard,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isActive ? Color.dsBrandPrimary : Color.dsSeparator, lineWidth: isActive ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                draftTitle = moment.title
                renameTargetID = moment.id
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                draftCaption = moment.caption
                captionTargetID = moment.id
            } label: {
                Label("Edit caption", systemImage: "text.bubble")
            }
            Button(role: .destructive) {
                withAnimation(.snappy) {
                    model.removeMoment(id: moment.id)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
