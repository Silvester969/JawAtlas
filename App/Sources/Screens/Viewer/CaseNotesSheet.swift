import SwiftUI
import JawAtlasCore

struct CaseNotesSheet: View {
    @Bindable var model: ViewerModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("Anything the next reader should know about this case — the anatomy to look for, the question it answers, what makes it worth studying.")
                    .font(.caption)
                    .foregroundStyle(Color.dsTextSecondary)
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.dsCard, in: RoundedRectangle(cornerRadius: 12))
                    .frame(minHeight: 220)
                Text("Notes travel with the case when you share it. They are not included in the exported summary.")
                    .font(.caption2)
                    .foregroundStyle(Color.dsTextSecondary)
                Spacer()
            }
            .padding(20)
            .background(Color.dsBackground)
            .navigationTitle("Case Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.story.notes = trimmed.isEmpty ? nil : trimmed
                        model.saveStory()
                        dismiss()
                    }
                }
            }
            .onAppear { text = model.story.notes ?? "" }
        }
        .presentationDetents([.medium, .large])
    }
}
