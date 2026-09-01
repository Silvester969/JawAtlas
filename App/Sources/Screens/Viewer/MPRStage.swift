import SwiftUI
import simd
import JawAtlasCore

extension MPRPlaneKind {
    var scoutColor: Color {
        switch self {
        case .axial: return .red
        case .coronal: return .green
        case .sagittal: return .yellow
        }
    }
}

struct MPRStage: View {
    @Bindable var model: ViewerModel
    @AppStorage("com.jawatlas.mprCoachSeen") private var coachSeen = false
    @State private var showsCoach = false

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 680 {
                grid
            } else {
                compact
            }
        }
        .background(Color.black)
        .overlay(alignment: .bottom) { toolBar }
        .overlay {
            if showsCoach {
                MPRCoachCard {
                    coachSeen = true
                    withAnimation(.snappy) { showsCoach = false }
                }
            }
        }
        .onAppear {
            if !coachSeen { showsCoach = true }
        }
    }

    private var toolBar: some View {
        VStack(spacing: 8) {
            if let prompt = model.mprPrompt {
                Text(prompt)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.dsBrandPrimary.opacity(0.92), in: Capsule())
                    .transition(.opacity)
            }
            HStack(spacing: 8) {
                ForEach(ViewerModel.MPRTool.allCases, id: \.self) { tool in
                    toolChip(tool)
                }
                if !model.measurements.isEmpty || !model.measureDraft.isEmpty {
                    Button {
                        model.clearMeasurements()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.6), in: Circle())
                    }
                    .accessibilityLabel("Clear measurements")
                }
                Button {
                    withAnimation(.snappy) { showsCoach = true }
                } label: {
                    Image(systemName: "questionmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.6), in: Circle())
                }
                .accessibilityLabel("How this view works")
            }
        }
        .padding(.bottom, 10)
        .animation(.snappy, value: model.mprPrompt)
    }

    private func toolChip(_ tool: ViewerModel.MPRTool) -> some View {
        let active = model.mprTool == tool
        return Button {
            withAnimation(.snappy) { model.selectMPRTool(tool) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(tool.displayName)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(active ? Color.black : .white)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                active ? AnyShapeStyle(.white.opacity(0.94)) : AnyShapeStyle(.black.opacity(0.6)),
                in: Capsule()
            )
        }
        .accessibilityLabel(tool.displayName)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    private var grid: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                MPRPaneView(model: model, pane: .axial)
                MPRPaneView(model: model, pane: .sagittal)
            }
            HStack(spacing: 2) {
                MPRPaneView(model: model, pane: .coronal)
                Mini3DPane(model: model)
            }
        }
    }

    private var compact: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(MPRPlaneKind.allCases) { pane in
                    planeChip(pane)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.dsBackground)
            MPRPaneView(model: model, pane: model.mprSelectedPane)
        }
    }

    private func planeChip(_ pane: MPRPlaneKind) -> some View {
        let selected = model.mprSelectedPane == pane
        return Button {
            withAnimation(.snappy) { model.mprSelectedPane = pane }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(pane.scoutColor)
                    .frame(width: 7, height: 7)
                Text(pane.displayName)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                selected ? AnyShapeStyle(Color.dsBrandPrimary) : AnyShapeStyle(Color.dsCard),
                in: Capsule()
            )
            .foregroundStyle(selected ? .white : Color.dsTextPrimary)
        }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct MPRCoachCard: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How this view works")
                .font(.headline)
                .foregroundStyle(.white)
            coachRow(
                icon: "plus.viewfinder",
                text: "The white cross marks one spot in the jaw. All three views — axial, coronal and sagittal — look at that same spot. Tap or drag to move it."
            )
            VStack(alignment: .leading, spacing: 6) {
                legendRow(color: .red, name: "Axial", description: "seen from below")
                legendRow(color: .green, name: "Coronal", description: "seen from the front")
                legendRow(color: .yellow, name: "Sagittal", description: "seen from the side")
                Text("Each colored line shows where that slice cuts through the picture.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            coachRow(
                icon: "circle.lefthalf.filled",
                text: "Adjust changes the picture: drag up and down for brightness, left and right for contrast. Bone and Soft Tissue below are ready-made settings."
            )
            coachRow(
                icon: "ruler",
                text: "Measure and Angle let you tap points on the picture to read real distances in mm and angles in degrees."
            )
            Button(action: onDismiss) {
                Text("Got it")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: 380)
        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        )
        .padding(24)
        .transition(.opacity)
    }

    private func coachRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.dsBrandPrimary)
                .frame(width: 22)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private func legendRow(color: Color, name: String, description: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
            Text(description)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

struct MPRPaneView: View {
    @Bindable var model: ViewerModel
    let pane: MPRPlaneKind
    @State private var pinchStartSpan: Float = 0
    @State private var windowDragStart: WindowLevel?

    var body: some View {
        if let renderer = model.renderer, let geometry = model.geometry {
            GeometryReader { proxy in
                let aspect = Float(max(proxy.size.width, 1) / max(proxy.size.height, 1))
                let frame = MPRPlaneFrame(kind: pane, geometry: geometry)
                VolumeMetalView(
                    renderer: renderer,
                    mode: .crossSection(model.mprPlaneToLocal(pane: pane, aspect: aspect)),
                    camera: model.camera,
                    window: model.window,
                    presentation: model.presentation,
                    isPaused: false,
                    onTwoFingerPan: { delta, size in
                        let scale = model.mprSpan(for: pane) / Float(max(size.height, 1))
                        model.mprPan(pane: pane, byMM: SIMD2<Float>(
                            Float(-delta.width) * scale,
                            Float(delta.height) * scale
                        ))
                    },
                    onTwoFingerActive: { active in
                        model.isTwoFingerNavigating = active
                    }
                )
                .background(Color.black)
                .overlay(crosshair(aspect: aspect, size: proxy.size).allowsHitTesting(false))
                .overlay(measurementsOverlay(frame: frame, aspect: aspect, size: proxy.size))
                .overlay(
                    OrientationEdgeLabels(
                        leftLabel: frame.leftEdgeLabel,
                        rightLabel: frame.rightEdgeLabel,
                        topLabel: frame.topEdgeLabel,
                        bottomLabel: frame.bottomEdgeLabel,
                        trailingInset: 34
                    )
                )
                .overlay(alignment: .bottomLeading) {
                    ScaleRuler(spanMM: model.mprSpan(for: pane), paneSize: proxy.size)
                        .padding(.leading, 10)
                        .padding(.bottom, 10)
                }
                .overlay(alignment: .topLeading) { readout }
                .overlay(alignment: .trailing) {
                    SliceDepthBar(
                        offsetMM: Binding(
                            get: { model.mprOffset(for: pane) },
                            set: { model.mprSetOffset($0, for: pane) }
                        ),
                        rangeMM: model.mprRange(for: pane)
                    )
                    .padding(.trailing, 4)
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(count: 2)
                        .onEnded { _ in model.mprResetPane(pane) }
                        .exclusively(
                            before: SpatialTapGesture()
                                .onEnded { value in
                                    handleTap(at: value.location, size: proxy.size, aspect: aspect)
                                }
                        )
                )
                .simultaneousGesture(toolDragGesture(size: proxy.size, aspect: aspect))
                .simultaneousGesture(zoomGesture)
                .onAppear { model.mprSelectedPane = pane }
            }
            .clipped()
        }
    }

    private func handleTap(at location: CGPoint, size: CGSize, aspect: Float) {
        model.mprSelectedPane = pane
        let ndc = ndcPoint(at: location, size: size)
        if model.measureTool != nil {
            if let point = model.mprLocalPoint(ndc: ndc, pane: pane, aspect: aspect) {
                model.addMeasurePoint(point)
            }
        } else if model.mprTool == .navigate {
            model.mprSetCrosshair(ndc: ndc, pane: pane, aspect: aspect)
        }
    }

    private func ndcPoint(at location: CGPoint, size: CGSize) -> SIMD2<Float> {
        SIMD2<Float>(
            Float(location.x / max(size.width, 1)) * 2 - 1,
            1 - Float(location.y / max(size.height, 1)) * 2
        )
    }

    private func toolDragGesture(size: CGSize, aspect: Float) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !model.isTwoFingerNavigating else { return }
                switch model.mprTool {
                case .navigate:
                    model.mprSelectedPane = pane
                    model.mprSetCrosshair(
                        ndc: ndcPoint(at: value.location, size: size),
                        pane: pane,
                        aspect: aspect
                    )
                case .window:
                    if windowDragStart == nil { windowDragStart = model.window }
                    guard let start = windowDragStart else { return }
                    let centerDelta = Double(-value.translation.height) * 3
                    let widthDelta = Double(value.translation.width) * 3
                    model.window = start.adjusted(centerDelta: centerDelta, widthDelta: widthDelta)
                    if model.preset != .custom { model.preset = .custom }
                case .length, .angle:
                    break
                }
            }
            .onEnded { _ in windowDragStart = nil }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchStartSpan == 0 { pinchStartSpan = model.mprSpan(for: pane) }
                model.mprSpanMM[pane] = pinchStartSpan
                model.mprZoom(pane: pane, by: Float(value.magnification))
            }
            .onEnded { _ in pinchStartSpan = 0 }
    }

    private func screenPoint(
        _ point: SIMD3<Float>,
        frame: MPRPlaneFrame,
        aspect: Float,
        size: CGSize
    ) -> CGPoint {
        let right = SIMD3<Float>(Float(frame.localRight.x), Float(frame.localRight.y), Float(frame.localRight.z))
        let up = SIMD3<Float>(Float(frame.localUp.x), Float(frame.localUp.y), Float(frame.localUp.z))
        let span = model.mprSpan(for: pane)
        let pan = model.mprPan(for: pane)
        let halfHeight = span / 2
        let halfWidth = halfHeight * aspect
        let u = (simd_dot(point, right) - pan.x) / max(halfWidth, 0.001)
        let v = (simd_dot(point, up) - pan.y) / max(halfHeight, 0.001)
        return CGPoint(
            x: CGFloat((u + 1) / 2) * size.width,
            y: CGFloat((1 - v) / 2) * size.height
        )
    }

    private func measurementsOverlay(
        frame: MPRPlaneFrame,
        aspect: Float,
        size: CGSize
    ) -> some View {
        let normal = SIMD3<Float>(
            Float(frame.localNormal.x),
            Float(frame.localNormal.y),
            Float(frame.localNormal.z)
        )
        let visible = model.measurementsVisible(
            onPlaneWithNormal: normal,
            offset: model.mprOffset(for: pane)
        )
        let projected: [(points: [CGPoint], label: String, anchor: CGPoint)] = visible.map { measurement in
            let screen = measurement.pointsLocalMM.map {
                screenPoint($0, frame: frame, aspect: aspect, size: size)
            }
            let anchor: CGPoint
            if measurement.tool == .angle, screen.count >= 2 {
                anchor = screen[1]
            } else if screen.count == 2 {
                anchor = CGPoint(x: (screen[0].x + screen[1].x) / 2, y: (screen[0].y + screen[1].y) / 2)
            } else {
                anchor = screen.first ?? .zero
            }
            return (screen, measurement.label, anchor)
        }
        return ZStack {
            Canvas { context, _ in
                for entry in projected {
                    if entry.points.count > 1 {
                        var path = Path()
                        path.addLines(entry.points)
                        context.stroke(
                            path,
                            with: .color(Color.dsSafetyGreen),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                    }
                    for point in entry.points {
                        let rect = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
                        context.fill(Path(ellipseIn: rect), with: .color(Color.dsSafetyGreen))
                    }
                }
            }
            ForEach(Array(projected.enumerated()), id: \.offset) { _, entry in
                if !entry.label.isEmpty {
                    Text(entry.label)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.dsSafetyGreen.opacity(0.92), in: RoundedRectangle(cornerRadius: 4))
                        .position(x: entry.anchor.x, y: max(entry.anchor.y - 16, 10))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func crosshair(aspect: Float, size: CGSize) -> some View {
        let ndc = model.mprCrosshairNDC(for: pane, aspect: aspect)
        let x = CGFloat((ndc.x + 1) / 2) * size.width
        let y = CGFloat((1 - ndc.y) / 2) * size.height
        let planes = scoutPlanes
        return Canvas { context, _ in
            var horizontal = Path()
            horizontal.move(to: CGPoint(x: 0, y: y))
            horizontal.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(horizontal, with: .color(planes.horizontal.scoutColor.opacity(0.65)), lineWidth: 1)
            var vertical = Path()
            vertical.move(to: CGPoint(x: x, y: 0))
            vertical.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(vertical, with: .color(planes.vertical.scoutColor.opacity(0.65)), lineWidth: 1)
            let gap = 14.0
            var cross = Path()
            cross.move(to: CGPoint(x: x - gap, y: y))
            cross.addLine(to: CGPoint(x: x - 4, y: y))
            cross.move(to: CGPoint(x: x + 4, y: y))
            cross.addLine(to: CGPoint(x: x + gap, y: y))
            cross.move(to: CGPoint(x: x, y: y - gap))
            cross.addLine(to: CGPoint(x: x, y: y - 4))
            cross.move(to: CGPoint(x: x, y: y + 4))
            cross.addLine(to: CGPoint(x: x, y: y + gap))
            context.stroke(cross, with: .color(.white.opacity(0.9)), lineWidth: 1.5)

            let horizontalTag = Text(planes.horizontal.displayName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(planes.horizontal.scoutColor)
            context.draw(
                horizontalTag,
                at: CGPoint(x: 34, y: max(y - 8, 8)),
                anchor: .leading
            )
            let verticalTag = Text(planes.vertical.displayName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(planes.vertical.scoutColor)
            context.draw(
                verticalTag,
                at: CGPoint(x: min(x + 6, size.width - 40), y: 56),
                anchor: .leading
            )
        }
    }

    private var scoutPlanes: (horizontal: MPRPlaneKind, vertical: MPRPlaneKind) {
        switch pane {
        case .axial: return (.coronal, .sagittal)
        case .coronal: return (.axial, .sagittal)
        case .sagittal: return (.axial, .coronal)
        }
    }

    private var readout: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(pane.scoutColor)
                .frame(width: 7, height: 7)
            Text("\(pane.displayName) \(offsetText)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.45), in: Capsule())
        .padding(.top, 8)
        .padding(.leading, 10)
        .allowsHitTesting(false)
    }

    private var offsetText: String {
        String(format: "%+.1f mm", model.mprOffset(for: pane))
    }
}

struct ScaleRuler: View {
    let spanMM: Float
    let paneSize: CGSize

    var body: some View {
        let pointsPerMM = paneSize.height / CGFloat(max(spanMM, 1))
        let candidates: [CGFloat] = [5, 10, 20, 50, 100]
        let limit = paneSize.width / 3.5
        let lengthMM = candidates.last(where: { $0 * pointsPerMM <= limit }) ?? 5
        let lengthPoints = lengthMM * pointsPerMM
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(Int(lengthMM)) mm")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
            Rectangle()
                .fill(.white.opacity(0.75))
                .frame(width: lengthPoints, height: 1.5)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.75)).frame(width: 1.5, height: 6)
                }
                .overlay(alignment: .trailing) {
                    Rectangle().fill(.white.opacity(0.75)).frame(width: 1.5, height: 6)
                }
        }
        .allowsHitTesting(false)
    }
}

struct Mini3DPane: View {
    @Bindable var model: ViewerModel
    @State private var dragStartAzimuth: Float = 0
    @State private var dragStartElevation: Float = 0
    @State private var pinchStartDistance: Float = 0

    var body: some View {
        if let renderer = model.renderer {
            GeometryReader { proxy in
                VolumeMetalView(
                    renderer: renderer,
                    mode: .volume,
                    camera: model.camera,
                    window: model.window,
                    presentation: model.presentation,
                    isPaused: false
                )
                .background(Color.black)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if value.translation == .zero {
                                dragStartAzimuth = model.camera.azimuth
                                dragStartElevation = model.camera.elevation
                            }
                            let dx = Float(value.translation.width / max(proxy.size.width, 1)) * 3.2
                            let dy = Float(value.translation.height / max(proxy.size.height, 1)) * 2.4
                            model.camera.azimuth = dragStartAzimuth - dx
                            model.camera.elevation = min(
                                max(dragStartElevation + dy, OrbitCamera.minimumElevation),
                                OrbitCamera.maximumElevation
                            )
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            if pinchStartDistance == 0 { pinchStartDistance = model.camera.distance }
                            let radius = model.boundingRadiusMM
                            model.camera.distance = min(
                                max(pinchStartDistance / Float(value.magnification), radius * 0.45),
                                radius * 8
                            )
                        }
                        .onEnded { _ in pinchStartDistance = 0 }
                )
                .onTapGesture(count: 2) { model.camera.reset(framing: model.boundingRadiusMM) }
            }
            .clipped()
        }
    }
}
