import SwiftUI
import simd
import JawAtlasCore

struct OrientationEdgeLabels: View {
    let leftLabel: String
    let rightLabel: String
    let topLabel: String
    let bottomLabel: String
    var trailingInset: CGFloat = 0

    var body: some View {
        ZStack {
            VStack {
                chip(topLabel)
                Spacer()
                chip(bottomLabel)
            }
            HStack {
                chip(leftLabel)
                Spacer()
                chip(rightLabel)
                    .padding(.trailing, trailingInset)
            }
        }
        .padding(10)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func chip(_ text: String) -> some View {
        if !text.isEmpty {
            Text(text)
                .font(.caption.weight(.bold).monospaced())
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

struct OrientationBadge: View {
    let horizontalLocal: SIMD3<Float>
    let verticalLocal: SIMD3<Float>
    let geometry: VolumeGeometry
    var trailingInset: CGFloat = 40

    var body: some View {
        let right = patientDirection(horizontalLocal)
        let up = patientDirection(verticalLocal)
        OrientationEdgeLabels(
            leftLabel: AnatomicOrientation.label(forPatientDirection: right.negated),
            rightLabel: AnatomicOrientation.label(forPatientDirection: right),
            topLabel: AnatomicOrientation.label(forPatientDirection: up),
            bottomLabel: AnatomicOrientation.label(forPatientDirection: up.negated),
            trailingInset: trailingInset
        )
    }

    private func patientDirection(_ local: SIMD3<Float>) -> Vec3 {
        MPRPlaneFrame.patientDirection(
            Vec3(Double(local.x), Double(local.y), Double(local.z)),
            geometry: geometry
        )
    }
}
