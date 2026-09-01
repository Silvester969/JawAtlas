import SwiftUI
import simd
import JawAtlasCore

struct PanoStage: View {
    @Bindable var model: ViewerModel

    var body: some View {
        if model.isEditingArch || model.archCurve == nil {
            ArchEditView(model: model)
        } else {
            panoLayout
        }
    }

    private var panoLayout: some View {
        VStack(spacing: 2) {
            panoView
            crossSectionView
        }
        .background(Color.black)
    }

    private var panoView: some View {
        Group {
            if let renderer = model.renderer, let geometry = model.geometry {
                let points = model.archResampledLocal()
                let arcLength = max(model.archLengthMM, 1)
                let zExtent = max(Float(geometry.extentMM.z), 1)
                GeometryReader { proxy in
                    VolumeMetalView(
                        renderer: renderer,
                        mode: .panoramic(points, slabMM: 2),
                        camera: model.camera,
                        window: model.window,
                        presentation: model.presentation,
                        isPaused: false
                    )
                    .background(Color.black)
                    .overlay(panoScout(size: proxy.size).allowsHitTesting(false))
                    .overlay(
                        OrientationEdgeLabels(
                            leftLabel: "R",
                            rightLabel: "L",
                            topLabel: "H",
                            bottomLabel: "F"
                        )
                    )
                    .overlay(alignment: .topLeading) {
                        Text("Panoramic")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(8)
                            .padding(.leading, 24)
                            .allowsHitTesting(false)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                model.panoArcT = min(max(Float(value.location.x / max(proxy.size.width, 1)), 0), 1)
                            }
                    )
                }
                .aspectRatio(CGFloat(arcLength / zExtent), contentMode: .fit)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func panoScout(size: CGSize) -> some View {
        Canvas { context, _ in
            let x = CGFloat(model.panoArcT) * size.width
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(line, with: .color(.yellow.opacity(0.8)), lineWidth: 1.5)
        }
    }

    private var crossSectionView: some View {
        Group {
            if let renderer = model.renderer, let geometry = model.geometry {
                GeometryReader { proxy in
                    let aspect = Float(max(proxy.size.width, 1) / max(proxy.size.height, 1))
                    if let matrix = model.panoCrossSectionMatrix(
                        aspect: aspect,
                        spanMM: model.panoCrossSectionSpanMM
                    ) {
                        VolumeMetalView(
                            renderer: renderer,
                            mode: .crossSection(matrix),
                            camera: model.camera,
                            window: model.window,
                            presentation: model.presentation,
                            isPaused: false
                        )
                        .background(Color.black)
                        .overlay(crossSectionLabels(geometry: geometry))
                        .overlay(alignment: .bottomLeading) {
                            ScaleRuler(spanMM: model.panoCrossSectionSpanMM, paneSize: proxy.size)
                                .padding(.leading, 10)
                                .padding(.bottom, 10)
                        }
                        .overlay(alignment: .topLeading) {
                            Text(crossSectionTitle)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.45), in: Capsule())
                                .padding(8)
                                .padding(.leading, 24)
                                .allowsHitTesting(false)
                        }
                        .overlay(alignment: .bottomTrailing) { editButton }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func crossSectionLabels(geometry: VolumeGeometry) -> some View {
        if let axes = model.panoCrossSectionAxes() {
            OrientationBadge(
                horizontalLocal: axes.horizontal,
                verticalLocal: axes.vertical,
                geometry: geometry,
                trailingInset: 0
            )
        }
    }

    private var crossSectionTitle: String {
        String(format: "Cross-section · %.0f mm along arch", model.panoArcT * model.archLengthMM)
    }

    private var editButton: some View {
        Button {
            model.beginArchEditing()
        } label: {
            Label("Edit arch", systemImage: "pencil.and.outline")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .tint(.white)
        .padding(12)
    }
}

struct ArchEditView: View {
    @Bindable var model: ViewerModel

    var body: some View {
        VStack(spacing: 0) {
            axialPane
            controls
        }
        .background(Color.dsBackground)
        .onAppear {
            if !model.isEditingArch { model.beginArchEditing() }
        }
    }

    private var axialPane: some View {
        Group {
            if let renderer = model.renderer, let geometry = model.geometry {
                GeometryReader { proxy in
                    let aspect = Float(max(proxy.size.width, 1) / max(proxy.size.height, 1))
                    let mapper = SliceMarkMapper(
                        planeToLocal: model.mprPlaneToLocal(pane: .axial, aspect: aspect),
                        size: proxy.size
                    )
                    VolumeMetalView(
                        renderer: renderer,
                        mode: .crossSection(mapper.planeToLocal),
                        camera: model.camera,
                        window: model.window,
                        presentation: model.presentation,
                        isPaused: false,
                        onTwoFingerPan: { delta, size in
                            let scale = model.mprSpan(for: .axial) / Float(max(size.height, 1))
                            model.mprPan(pane: .axial, byMM: SIMD2<Float>(
                                Float(-delta.width) * scale,
                                Float(delta.height) * scale
                            ))
                        }
                    )
                    .background(Color.black)
                    .overlay(draftOverlay(mapper: mapper).allowsHitTesting(false))
                    .overlay(
                        OrientationEdgeLabels(
                            leftLabel: "R",
                            rightLabel: "L",
                            topLabel: "A",
                            bottomLabel: "P",
                            trailingInset: 34
                        )
                    )
                    .overlay(alignment: .trailing) {
                        SliceDepthBar(
                            offsetMM: Binding(
                                get: { model.mprOffset(for: .axial) },
                                set: { model.mprSetOffset($0, for: .axial) }
                            ),
                            rangeMM: model.mprRange(for: .axial)
                        )
                        .padding(.trailing, 4)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let point = mapper.localMM(fromScreenPoint: location)
                        model.appendArchPoint(point)
                    }
                }
                .clipped()
            }
        }
    }

    private func draftOverlay(mapper: SliceMarkMapper) -> some View {
        let controlPoints = model.archDraftLocalMM.map { mapper.screenPoint(fromLocalMM: $0) }
        let preview: [CGPoint]
        if model.archDraftLocalMM.count >= 2 {
            preview = ArchCurve(controlPointsLocalMM: model.archDraftLocalMM)
                .densePolyline()
                .map { mapper.screenPoint(fromLocalMM: $0) }
        } else {
            preview = []
        }
        return Canvas { context, _ in
            if preview.count > 1 {
                var path = Path()
                path.addLines(preview)
                context.stroke(
                    path,
                    with: .color(Color.dsBrandPrimary.opacity(0.85)),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
            }
            for point in controlPoints {
                let rect = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: rect), with: .color(.white))
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(Color.dsBrandPrimary),
                    lineWidth: 2
                )
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Text("Tap along the dental arch to trace it — at least \(ArchCurve.minimumControlPoints) points")
                .font(.caption)
                .foregroundStyle(Color.dsTextSecondary)
            HStack(spacing: 12) {
                Button {
                    model.undoArchPoint()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(model.archDraftLocalMM.isEmpty)
                Button(role: .destructive) {
                    model.clearArchDraft()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(model.archDraftLocalMM.isEmpty)
                Spacer()
                Button {
                    model.commitArchDraft()
                } label: {
                    Label("Show panoramic", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.archDraftLocalMM.count < ArchCurve.minimumControlPoints)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
