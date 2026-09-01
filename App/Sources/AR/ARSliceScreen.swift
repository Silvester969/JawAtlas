import SwiftUI
import JawAtlasCore

struct ARSliceScreen: View {
    let renderer: VolumeRenderer
    let geometry: VolumeGeometry
    let caseLabel: String
    var onCapture: ((UIImage) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var model = ARSliceModel()
    @State private var viewportSize: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.stage == .unsupported {
                unsupported
            } else {
                GeometryReader { proxy in
                    ARSliceMetalView(renderer: renderer, model: model, geometry: geometry)
                        .ignoresSafeArea()
                        .onAppear { viewportSize = proxy.size }
                        .onChange(of: proxy.size) { _, size in viewportSize = size }
                }
                .ignoresSafeArea()
                .overlay(alignment: .topTrailing) {
                    if model.anchorTransform != nil { navigatorFrame }
                }
                overlay
                if model.anchorTransform != nil {
                    HStack {
                        Spacer()
                        ScrubBar(
                            value: Binding(
                                get: { model.cutDepthMM },
                                set: { model.cutDepthMM = $0 }
                            ),
                            maximumDepthMM: Float(max(geometry.extentMM.x, geometry.extentMM.y) * 1.05)
                        )
                        .padding(.trailing, 8)
                    }
                }
            }
        }
        .statusBarHidden(true)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.lastCapture) { _, captured in
            if let captured { onCapture?(captured) }
        }
    }

    private var unsupported: some View {
        VStack(spacing: 16) {
            Image(systemName: "arkit")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.7))
            Text("Augmented reality needs a physical iPhone or iPad")
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("The 3D and Slice views work everywhere.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            Button("Back to Viewer") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(32)
    }

    private var overlay: some View {
        VStack {
            topBar
            Spacer()
            if model.anchorTransform == nil { reticle }
            Spacer()
            if let message = model.trackingMessage { banner(message) }
            if let approach = approachText { approachChip(approach) }
            controls
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Label("Done", systemImage: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
            Text(caseLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.top, 8)
    }

    private var reticle: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(model.lastCandidate == nil ? Color.white.opacity(0.25) : Color.dsSafetyGreen)
                    .frame(width: 12, height: 12)
            }
            Text(reticleMessage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.45), in: Capsule())
        }
    }

    private var navigatorFrame: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.55), lineWidth: 1.5)
                .frame(width: 124, height: 124)
            Text("Cut position")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.top, 116)
        .padding(.trailing, 14)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var approachText: String? {
        guard model.anchorTransform != nil, !model.isLocked else { return nil }
        guard !model.isAimedAtVolume else { return nil }
        return "Point the phone at the jaw"
    }

    private func approachChip(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(.bottom, 8)
    }

    private var reticleMessage: String {
        if model.lastCandidate != nil { return "Ready — tap Place jaw here" }
        if model.detectedPlaneCount == 0 {
            return "Move the phone slowly across the table"
        }
        return "Aim a little lower onto the surface"
    }

    private func banner(_ message: String) -> some View {
        Text(message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.dsSafetyOrange.opacity(0.9), in: Capsule())
            .padding(.bottom, 10)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Text("For education and training — not for diagnosis or treatment")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))

            if model.anchorTransform == nil {
                Button {
                    model.place(geometry: geometry, viewportSize: viewportSize)
                } label: {
                    Text("Place jaw here")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                HStack(spacing: 10) {
                    lockPill
                    pill(model.showsVolume ? "Hide jaw" : "Show jaw", systemImage: "cube.transparent") {
                        model.showsVolume.toggle()
                    }
                    pill("Move", systemImage: "arrow.counterclockwise") {
                        model.reset()
                    }
                    pill("Photo", systemImage: "camera") {
                        model.captureRequested = true
                    }
                }
                Picker("Window", selection: Binding(get: { model.preset }, set: { model.preset = $0 })) {
                    Text(WindowPreset.bone.displayName).tag(WindowPreset.bone)
                    Text(WindowPreset.softTissue.displayName).tag(WindowPreset.softTissue)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var lockPill: some View {
        Button {
            model.toggleLock()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: model.isLocked ? "lock.fill" : "lock.open")
                Text(model.isLocked ? "Locked" : "Lock slice").font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                model.isLocked ? AnyShapeStyle(Color.dsBrandPrimary) : AnyShapeStyle(.ultraThinMaterial),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .tint(.white)
    }

    private func pill(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .tint(.white)
    }
}

struct ScrubBar: View {
    @Binding var value: Float
    let maximumDepthMM: Float
    private let barHeight: CGFloat = 240
    private let thumbSize: CGFloat = 34
    @State private var dragStartValue: Float?

    var body: some View {
        VStack(spacing: 6) {
            Text("Deeper")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
            track
            Text("Surface")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
            Text(String(format: "%.0f mm in", value))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.5), in: Capsule())
                .onTapGesture { value = 15 }
        }
    }

    private var travel: CGFloat { barHeight - thumbSize - 6 }

    private var track: some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)
                .frame(width: 44, height: barHeight)
            Capsule()
                .fill(Color.dsBrandPrimary.opacity(0.55))
                .frame(width: 6, height: max(CGFloat(value / max(maximumDepthMM, 1)) * travel, 3))
                .offset(y: travel / 2 - CGFloat(value / max(maximumDepthMM, 1)) * travel / 2)
            Circle()
                .fill(Color.white)
                .frame(width: thumbSize, height: thumbSize)
                .shadow(radius: 3)
                .overlay {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.dsBrandPrimary)
                }
                .offset(y: thumbOffset)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    if dragStartValue == nil { dragStartValue = value }
                    let delta = Float(-gesture.translation.height / travel) * maximumDepthMM
                    value = min(max((dragStartValue ?? 0) + delta, 0), maximumDepthMM)
                }
                .onEnded { _ in dragStartValue = nil }
        )
    }

    private var thumbOffset: CGFloat {
        travel / 2 - CGFloat(value / max(maximumDepthMM, 1)) * travel
    }
}
