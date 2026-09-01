import SwiftUI

struct WelcomeView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.dsBrandPrimary)
                        Text("Learn CBCT anatomy in 3D")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Color.dsTextPrimary)
                        Text("JawAtlas turns a dental CBCT scan into an interactive 3D study companion.")
                            .font(.body)
                            .foregroundStyle(Color.dsTextSecondary)
                    }

                    step(
                        icon: "square.and.arrow.down",
                        title: "Bring a scan in",
                        text: "AirDrop a zipped DICOM folder or import one from Files. Everything stays on this device."
                    )
                    step(
                        icon: "bookmark",
                        title: "Mark what matters",
                        text: "Slice to a structure, draw a mark on it, and save it as a moment. Replay moments like slides when you study or teach."
                    )
                    step(
                        icon: "arkit",
                        title: "Put the jaw on the table",
                        text: "Show the scan life-size in augmented reality and cut through the anatomy live by moving your device."
                    )
                    step(
                        icon: "square.and.arrow.up",
                        title: "Share a case",
                        text: "Send a case with its moments and notes to a classmate or student, or export a summary of your marked views."
                    )

                    Text("JawAtlas is an education and training aid. It is not a medical device and must not be used for diagnosis or treatment decisions.")
                        .font(.caption)
                        .foregroundStyle(Color.dsTextSecondary)
                }
                .padding(28)
            }
            Button {
                onDone()
            } label: {
                Text("Get started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        .background(Color.dsBackground)
        .interactiveDismissDisabled(true)
    }

    private func step(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.dsBrandPrimary)
                .frame(width: 34, height: 34)
                .background(Color.dsBrandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.dsTextPrimary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Color.dsTextSecondary)
            }
        }
    }
}
