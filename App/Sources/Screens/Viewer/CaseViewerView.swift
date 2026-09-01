import SwiftUI
import Observation
import simd
import JawAtlasCore

@MainActor
@Observable
final class ViewerModel {
    enum State: Equatable {
        case loading
        case ready
        case failed(String)
    }

    enum Tab: String, CaseIterable {
        case volume = "3D"
        case mpr = "MPR"
        case pano = "Pano"
        case slice = "Slice"
    }

    private(set) var state: State = .loading
    private(set) var handle: VolumeHandle?
    private(set) var geometry: VolumeGeometry?
    private(set) var renderer: VolumeRenderer?
    private(set) var directory: URL?

    var tab: Tab = .volume
    var camera = OrbitCamera()
    var preset: WindowPreset = .bone {
        didSet {
            if let level = preset.level { window = level }
        }
    }
    var window: WindowLevel = .bone
    var planeAzimuth: Float = 0
    var planeElevation: Float = 0
    var planeOffsetMM: Float = 0
    var planeSpanMM: Float = 120
    var planePan = SIMD2<Float>(0, 0)
    var isTwoFingerNavigating = false
    var story = StoryState()
    var activeMomentID: UUID?
    var isMarking = false
    var currentStrokeLocalMM: [Vec3] = []
    var focusLocalMM = SIMD3<Float>(0, 0, 0)
    var mprSelectedPane: MPRPlaneKind = .axial
    var mprSpanMM: [MPRPlaneKind: Float] = [:]
    var mprPanMM: [MPRPlaneKind: SIMD2<Float>] = [:]
    var panoArcT: Float = 0.5
    var isEditingArch = false
    var archDraftLocalMM: [Vec3] = []

    enum MeasureTool: String {
        case length
        case angle

        var requiredPoints: Int {
            self == .length ? 2 : 3
        }
    }

    struct PaneMeasurement: Identifiable, Equatable {
        let id = UUID()
        var tool: MeasureTool
        var pointsLocalMM: [SIMD3<Float>]

        var label: String {
            switch tool {
            case .length:
                guard pointsLocalMM.count == 2 else { return "" }
                return MeasurementMath.distanceText(Double(
                    simd_distance(pointsLocalMM[0], pointsLocalMM[1])
                ))
            case .angle:
                guard pointsLocalMM.count == 3 else { return "" }
                func vec(_ point: SIMD3<Float>) -> Vec3 {
                    Vec3(Double(point.x), Double(point.y), Double(point.z))
                }
                return MeasurementMath.angleText(MeasurementMath.angleDegrees(
                    vertex: vec(pointsLocalMM[1]),
                    first: vec(pointsLocalMM[0]),
                    second: vec(pointsLocalMM[2])
                ))
            }
        }
    }

    enum MPRTool: String, CaseIterable {
        case navigate
        case window
        case length
        case angle

        var displayName: String {
            switch self {
            case .navigate: return "Move"
            case .window: return "Adjust"
            case .length: return "Measure"
            case .angle: return "Angle"
            }
        }

        var systemImage: String {
            switch self {
            case .navigate: return "plus.viewfinder"
            case .window: return "circle.lefthalf.filled"
            case .length: return "ruler"
            case .angle: return "angle"
            }
        }

        var measureKind: MeasureTool? {
            switch self {
            case .length: return .length
            case .angle: return .angle
            case .navigate, .window: return nil
            }
        }
    }

    var mprTool: MPRTool = .navigate
    var measureDraft: [SIMD3<Float>] = []
    var measurements: [PaneMeasurement] = []

    var measureTool: MeasureTool? { mprTool.measureKind }

    var mprPrompt: String? {
        switch mprTool {
        case .navigate:
            return nil
        case .window:
            return "Drag on the picture — up and down for brightness, left and right for contrast"
        case .length:
            return measureDraft.isEmpty
                ? "Tap where the measurement should start"
                : "Tap where it should end"
        case .angle:
            switch measureDraft.count {
            case 0: return "Tap the first point of the angle"
            case 1: return "Tap the corner, where the two lines meet"
            default: return "Tap the last point of the angle"
            }
        }
    }

    func selectMPRTool(_ tool: MPRTool) {
        measureDraft = []
        mprTool = mprTool == tool && tool != .navigate ? .navigate : tool
    }

    func addMeasurePoint(_ point: SIMD3<Float>) {
        guard let tool = mprTool.measureKind else { return }
        measureDraft.append(point)
        if measureDraft.count == tool.requiredPoints {
            measurements.append(PaneMeasurement(tool: tool, pointsLocalMM: measureDraft))
            measureDraft = []
        }
    }

    func clearMeasurements() {
        measureDraft = []
        measurements = []
    }

    func measurementsVisible(onPlaneWithNormal normal: SIMD3<Float>, offset: Float) -> [PaneMeasurement] {
        let tolerance: Float = 1.0
        var visible = measurements.filter { measurement in
            measurement.pointsLocalMM.allSatisfy {
                abs(simd_dot($0, normal) - offset) <= tolerance
            }
        }
        if !measureDraft.isEmpty,
           measureDraft.allSatisfy({ abs(simd_dot($0, normal) - offset) <= tolerance }) {
            visible.append(PaneMeasurement(tool: measureTool ?? .length, pointsLocalMM: measureDraft))
        }
        return visible
    }

    func adjustWindow(centerDelta: Double, widthDelta: Double) {
        window = window.adjusted(centerDelta: centerDelta, widthDelta: widthDelta)
        if preset != .custom { preset = .custom }
    }

    var volumeStyle: VolumePresentation = .bone
    var volumeShaded = true
    var volumeMIP = false

    var presentation: VolumePresentation {
        tab == .volume ? volumeStyle : (preset == .softTissue ? .softTissue : .bone)
    }

    var boundingRadiusMM: Float { renderer?.boundingRadiusMM ?? 100 }

    var defaultSpanMM: Float {
        guard let geometry else { return 120 }
        return Float(geometry.extentMM.z) * 1.15
    }

    var planeRangeMM: Float {
        guard let geometry else { return 60 }
        let normal = SlicePlaneMath.planeNormal(azimuth: planeAzimuth, elevation: planeElevation)
        let ex = Float(geometry.extentMM.x)
        let ey = Float(geometry.extentMM.y)
        let ez = Float(geometry.extentMM.z)
        return (abs(normal.x) * ex + abs(normal.y) * ey + abs(normal.z) * ez) / 2
    }

    func setDirection(azimuth: Float, elevation: Float) {
        setAngles(azimuth: azimuth, elevation: elevation, keepingFocus: currentFocusLocalMM())
    }

    func currentFocusLocalMM() -> SIMD3<Float> {
        SlicePlaneMath.focusPoint(
            azimuth: planeAzimuth,
            elevation: planeElevation,
            offsetMM: planeOffsetMM,
            pan: planePan
        )
    }

    func setAngles(azimuth: Float, elevation: Float, keepingFocus focus: SIMD3<Float>) {
        planeAzimuth = azimuth
        planeElevation = min(max(elevation, -1.55), 1.55)
        let pose = SlicePlaneMath.pose(focus: focus, azimuth: planeAzimuth, elevation: planeElevation)
        planeOffsetMM = pose.offsetMM
        planePan = pose.pan
    }

    func cancelActiveStroke() {
        currentStrokeLocalMM = []
    }

    func load(store: CaseStore, caseID: String) async {
        state = .loading
        do {
            let renderer = try VolumeRenderer()
            let loaded = try await store.makeHandle(forCaseID: caseID)
            let directory = loaded.directoryHint(store: store, caseID: caseID)
            let manifest = try IntegrityVerifier.loadManifest(in: directory)
            let geometry = VolumeGeometry(manifest: manifest)
            try renderer.upload(handle: loaded, geometry: geometry)
            self.handle = loaded
            self.geometry = geometry
            self.renderer = renderer
            self.directory = directory
            self.story = StoryStateIO.load(from: directory)
            camera.reset(framing: renderer.boundingRadiusMM)
            planeAzimuth = 0
            planeElevation = 0
            planeOffsetMM = 0
            planeSpanMM = Float(geometry.extentMM.z) * 1.15
            planePan = .zero
            focusLocalMM = .zero
            mprSpanMM = [:]
            mprPanMM = [:]
            state = .ready
        } catch let error as RendererError {
            state = .failed(error.userMessage)
        } catch {
            state = .failed(AppEnvironment.message(for: error))
        }
    }

    func close() {
        saveStory()
        renderer?.discardVolume()
        renderer = nil
        handle?.close()
        handle = nil
        geometry = nil
    }

    func resetView() {
        camera.reset(framing: boundingRadiusMM)
        planeAzimuth = 0
        planeElevation = 0
        planeOffsetMM = 0
        planeSpanMM = defaultSpanMM
        planePan = .zero
        focusLocalMM = .zero
        mprSpanMM = [:]
        mprPanMM = [:]
    }

    func planeToLocal(aspect: Float) -> simd_float4x4 {
        SlicePlaneMath.planeToLocal(
            azimuth: planeAzimuth,
            elevation: planeElevation,
            offsetMM: planeOffsetMM,
            pan: planePan,
            spanMM: planeSpanMM,
            aspect: aspect
        )
    }

    func mprFrame(for pane: MPRPlaneKind) -> MPRPlaneFrame? {
        guard let geometry else { return nil }
        return MPRPlaneFrame(kind: pane, geometry: geometry)
    }

    private func simd(_ vector: Vec3) -> SIMD3<Float> {
        SIMD3<Float>(Float(vector.x), Float(vector.y), Float(vector.z))
    }

    func mprDefaultSpanMM(for pane: MPRPlaneKind) -> Float {
        guard let geometry, let frame = mprFrame(for: pane) else { return 120 }
        let up = simd(frame.localUp)
        let extent = geometry.extentMM
        let span = abs(up.x) * Float(extent.x) + abs(up.y) * Float(extent.y) + abs(up.z) * Float(extent.z)
        return max(span * 1.05, 10)
    }

    func mprSpan(for pane: MPRPlaneKind) -> Float {
        mprSpanMM[pane] ?? mprDefaultSpanMM(for: pane)
    }

    func mprPan(for pane: MPRPlaneKind) -> SIMD2<Float> {
        mprPanMM[pane] ?? .zero
    }

    func mprZoom(pane: MPRPlaneKind, by scale: Float) {
        let base = mprDefaultSpanMM(for: pane)
        let current = mprSpan(for: pane)
        mprSpanMM[pane] = min(max(current / max(scale, 0.05), base * 0.2), base * 2.2)
    }

    func mprPan(pane: MPRPlaneKind, byMM delta: SIMD2<Float>) {
        let limit = mprDefaultSpanMM(for: pane)
        let current = mprPan(for: pane)
        mprPanMM[pane] = SIMD2<Float>(
            min(max(current.x + delta.x, -limit), limit),
            min(max(current.y + delta.y, -limit), limit)
        )
    }

    func mprResetPane(_ pane: MPRPlaneKind) {
        mprSpanMM[pane] = nil
        mprPanMM[pane] = nil
        focusLocalMM = .zero
    }

    var localHalfExtent: SIMD3<Float> {
        guard let geometry else { return SIMD3<Float>(60, 60, 60) }
        let extent = geometry.extentMM
        return SIMD3<Float>(Float(extent.x / 2), Float(extent.y / 2), Float(extent.z / 2))
    }

    func clampFocus(_ focus: SIMD3<Float>) -> SIMD3<Float> {
        let half = localHalfExtent
        return SIMD3<Float>(
            min(max(focus.x, -half.x), half.x),
            min(max(focus.y, -half.y), half.y),
            min(max(focus.z, -half.z), half.z)
        )
    }

    func mprPlaneToLocal(pane: MPRPlaneKind, aspect: Float) -> simd_float4x4 {
        guard let frame = mprFrame(for: pane) else { return matrix_identity_float4x4 }
        let right = simd(frame.localRight)
        let up = simd(frame.localUp)
        let normal = simd(frame.localNormal)
        let span = mprSpan(for: pane)
        let pan = mprPan(for: pane)
        let halfHeight = span / 2
        let halfWidth = halfHeight * aspect
        let center = normal * simd_dot(focusLocalMM, normal) + right * pan.x + up * pan.y
        return simd_float4x4(
            SIMD4<Float>(right * halfWidth, 0),
            SIMD4<Float>(up * halfHeight, 0),
            SIMD4<Float>(normal, 0),
            SIMD4<Float>(center, 1)
        )
    }

    func mprOffset(for pane: MPRPlaneKind) -> Float {
        guard let frame = mprFrame(for: pane) else { return 0 }
        return simd_dot(focusLocalMM, simd(frame.localNormal))
    }

    func mprSetOffset(_ offset: Float, for pane: MPRPlaneKind) {
        guard let frame = mprFrame(for: pane) else { return }
        let normal = simd(frame.localNormal)
        let inPlane = focusLocalMM - normal * simd_dot(focusLocalMM, normal)
        focusLocalMM = clampFocus(inPlane + normal * offset)
    }

    func mprRange(for pane: MPRPlaneKind) -> Float {
        guard let geometry, let frame = mprFrame(for: pane) else { return 60 }
        let normal = simd(frame.localNormal)
        let extent = geometry.extentMM
        return (abs(normal.x) * Float(extent.x) + abs(normal.y) * Float(extent.y)
            + abs(normal.z) * Float(extent.z)) / 2
    }

    func mprCrosshairNDC(for pane: MPRPlaneKind, aspect: Float) -> SIMD2<Float> {
        guard let frame = mprFrame(for: pane) else { return .zero }
        let right = simd(frame.localRight)
        let up = simd(frame.localUp)
        let span = mprSpan(for: pane)
        let pan = mprPan(for: pane)
        let halfHeight = span / 2
        let halfWidth = halfHeight * aspect
        let u = (simd_dot(focusLocalMM, right) - pan.x) / max(halfWidth, 0.001)
        let v = (simd_dot(focusLocalMM, up) - pan.y) / max(halfHeight, 0.001)
        return SIMD2<Float>(u, v)
    }

    func mprSetCrosshair(ndc: SIMD2<Float>, pane: MPRPlaneKind, aspect: Float) {
        guard let frame = mprFrame(for: pane) else { return }
        let right = simd(frame.localRight)
        let up = simd(frame.localUp)
        let normal = simd(frame.localNormal)
        let span = mprSpan(for: pane)
        let pan = mprPan(for: pane)
        let halfHeight = span / 2
        let halfWidth = halfHeight * aspect
        let inPlaneRight = pan.x + ndc.x * halfWidth
        let inPlaneUp = pan.y + ndc.y * halfHeight
        let alongNormal = simd_dot(focusLocalMM, normal)
        focusLocalMM = clampFocus(normal * alongNormal + right * inPlaneRight + up * inPlaneUp)
    }

    var archCurve: ArchCurve? {
        guard let points = story.archControlPointsLocalMM,
              points.count >= ArchCurve.minimumControlPoints else { return nil }
        return ArchCurve(controlPointsLocalMM: points)
    }

    func archResampledLocal() -> [SIMD3<Float>] {
        guard let curve = archCurve else { return [] }
        return curve.resampledUniformly(count: VolumeRenderer.panoramicPointLimit).map {
            SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z))
        }
    }

    var archLengthMM: Float {
        guard let curve = archCurve else { return 0 }
        return Float(curve.totalLengthMM())
    }

    func beginArchEditing() {
        archDraftLocalMM = story.archControlPointsLocalMM ?? []
        isEditingArch = true
    }

    func appendArchPoint(_ point: Vec3) {
        archDraftLocalMM.append(point)
    }

    func undoArchPoint() {
        guard !archDraftLocalMM.isEmpty else { return }
        archDraftLocalMM.removeLast()
    }

    func clearArchDraft() {
        archDraftLocalMM = []
    }

    func commitArchDraft() {
        guard let geometry, archDraftLocalMM.count >= ArchCurve.minimumControlPoints else { return }
        story.archControlPointsLocalMM = ArchCurve.orientedRightToLeft(archDraftLocalMM, geometry: geometry)
        isEditingArch = false
        panoArcT = 0.5
        saveStory()
    }

    func removeArchCurve() {
        story.archControlPointsLocalMM = nil
        archDraftLocalMM = []
        isEditingArch = true
        saveStory()
    }

    func panoCrossSectionAxes() -> (
        horizontal: SIMD3<Float>, vertical: SIMD3<Float>, normal: SIMD3<Float>, center: SIMD3<Float>
    )? {
        let points = archResampledLocal()
        guard points.count >= 2 else { return nil }
        let clamped = min(max(panoArcT, 0), 1)
        let arc = clamped * Float(points.count - 1)
        let index = min(Int(arc), points.count - 2)
        let fraction = arc - Float(index)
        let base = points[index] + (points[index + 1] - points[index]) * fraction
        let tangent = points[index + 1] - points[index]
        let flatLength = max(sqrt(tangent.x * tangent.x + tangent.y * tangent.y), 1e-5)
        let normal2 = SIMD2<Float>(-tangent.y / flatLength, tangent.x / flatLength)
        return (
            SIMD3<Float>(normal2.x, normal2.y, 0),
            SIMD3<Float>(0, 0, 1),
            SIMD3<Float>(tangent.x / flatLength, tangent.y / flatLength, 0),
            SIMD3<Float>(base.x, base.y, 0)
        )
    }

    func panoCrossSectionMatrix(aspect: Float, spanMM: Float) -> simd_float4x4? {
        guard let axes = panoCrossSectionAxes() else { return nil }
        let halfHeight = spanMM / 2
        let halfWidth = halfHeight * aspect
        return simd_float4x4(
            SIMD4<Float>(axes.horizontal * halfWidth, 0),
            SIMD4<Float>(axes.vertical * halfHeight, 0),
            SIMD4<Float>(axes.normal, 0),
            SIMD4<Float>(axes.center, 1)
        )
    }

    var panoCrossSectionSpanMM: Float {
        guard let geometry else { return 100 }
        return Float(geometry.extentMM.z) * 1.1
    }

    func mprLocalPoint(ndc: SIMD2<Float>, pane: MPRPlaneKind, aspect: Float) -> SIMD3<Float>? {
        guard let frame = mprFrame(for: pane) else { return nil }
        let right = simd(frame.localRight)
        let up = simd(frame.localUp)
        let normal = simd(frame.localNormal)
        let span = mprSpan(for: pane)
        let pan = mprPan(for: pane)
        let halfHeight = span / 2
        let halfWidth = halfHeight * aspect
        let inPlaneRight = pan.x + ndc.x * halfWidth
        let inPlaneUp = pan.y + ndc.y * halfHeight
        let alongNormal = simd_dot(focusLocalMM, normal)
        return clampFocus(normal * alongNormal + right * inPlaneRight + up * inPlaneUp)
    }

    func zoomPlane(by scale: Float) {
        let limit = defaultSpanMM
        planeSpanMM = min(max(planeSpanMM / max(scale, 0.05), limit * 0.25), limit * 2.6)
    }

    func panPlane(byMM delta: SIMD2<Float>) {
        let limit = defaultSpanMM
        planePan = SIMD2<Float>(
            min(max(planePan.x + delta.x, -limit), limit),
            min(max(planePan.y + delta.y, -limit), limit)
        )
    }

    static func sliceAngles(for pane: MPRPlaneKind) -> (azimuth: Float, elevation: Float) {
        switch pane {
        case .axial: return (0, -.pi / 2)
        case .coronal: return (0, 0)
        case .sagittal: return (.pi / 2, 0)
        }
    }

    func snapshotMoment(title: String) -> StoryMoment {
        var azimuth = planeAzimuth
        var elevation = planeElevation
        var offset = planeOffsetMM
        var pan = planePan
        var span = planeSpanMM
        if tab == .mpr {
            let angles = ViewerModel.sliceAngles(for: mprSelectedPane)
            azimuth = angles.azimuth
            elevation = angles.elevation
            let pose = SlicePlaneMath.pose(focus: focusLocalMM, azimuth: azimuth, elevation: elevation)
            offset = pose.offsetMM
            pan = pose.pan
            span = mprSpan(for: mprSelectedPane)
        }
        if tab == .pano, let axes = panoCrossSectionAxes() {
            azimuth = atan2(axes.horizontal.y, axes.horizontal.x)
            elevation = 0
            let pose = SlicePlaneMath.pose(focus: axes.center, azimuth: azimuth, elevation: elevation)
            offset = pose.offsetMM
            pan = pose.pan
            span = panoCrossSectionSpanMM
        }
        return StoryMoment(
            title: title,
            stage: tab == .volume ? .volume : .slice,
            windowPreset: preset.rawValue,
            planeAzimuth: Double(azimuth),
            planeElevation: Double(elevation),
            planeOffsetMM: Double(offset),
            planePanX: Double(pan.x),
            planePanY: Double(pan.y),
            planeSpanMM: Double(span),
            cameraAzimuth: Double(camera.azimuth),
            cameraElevation: Double(camera.elevation),
            cameraDistance: Double(camera.distance)
        )
    }

    func addMoment(title: String) {
        let moment = snapshotMoment(title: title)
        story.moments.append(moment)
        activeMomentID = moment.id
        saveStory()
    }

    func apply(_ moment: StoryMoment) {
        activeMomentID = moment.id
        tab = moment.stage == .volume ? .volume : .slice
        preset = WindowPreset(rawValue: moment.windowPreset) ?? .bone
        planeAzimuth = Float(moment.planeAzimuth)
        planeElevation = Float(moment.planeElevation ?? 0)
        planeOffsetMM = Float(moment.planeOffsetMM)
        planePan = SIMD2<Float>(Float(moment.planePanX), Float(moment.planePanY))
        planeSpanMM = Float(moment.planeSpanMM)
        camera.azimuth = Float(moment.cameraAzimuth)
        camera.elevation = Float(moment.cameraElevation)
        camera.distance = Float(moment.cameraDistance)
    }

    func removeMoment(id: UUID) {
        story.moments.removeAll { $0.id == id }
        if activeMomentID == id { activeMomentID = nil }
        saveStory()
    }

    func saveStory() {
        guard let directory else { return }
        try? StoryStateIO.save(story, to: directory)
    }

    var activeMoment: StoryMoment? {
        guard let activeMomentID else { return nil }
        return story.moments.first { $0.id == activeMomentID }
    }

    var activeSliceMomentMatchesPlane: Bool {
        guard let moment = activeMoment, moment.stage == .slice else { return false }
        return abs(Float(moment.planeAzimuth) - planeAzimuth) < 0.02
            && abs(Float(moment.planeElevation ?? 0) - planeElevation) < 0.02
            && abs(Float(moment.planeOffsetMM) - planeOffsetMM) < 0.5
    }

    func toggleMarking() {
        isMarking.toggle()
        currentStrokeLocalMM = []
    }

    func appendStrokePoint(_ point: Vec3) {
        currentStrokeLocalMM.append(point)
    }

    func endStroke() {
        let stroke = currentStrokeLocalMM
        currentStrokeLocalMM = []
        guard stroke.count >= 2 else { return }
        if !activeSliceMomentMatchesPlane {
            addMoment(title: "Marked view")
        }
        guard let activeMomentID,
              let index = story.moments.firstIndex(where: { $0.id == activeMomentID }) else { return }
        story.moments[index].strokesLocalMM.append(stroke)
        saveStory()
    }

    func undoLastStroke() {
        guard let activeMomentID,
              let index = story.moments.firstIndex(where: { $0.id == activeMomentID }),
              !story.moments[index].strokesLocalMM.isEmpty else { return }
        story.moments[index].strokesLocalMM.removeLast()
        saveStory()
    }

    func clearMarks() {
        guard let activeMomentID,
              let index = story.moments.firstIndex(where: { $0.id == activeMomentID }),
              !story.moments[index].strokesLocalMM.isEmpty else { return }
        story.moments[index].strokesLocalMM.removeAll()
        saveStory()
    }

    func renameMoment(id: UUID, title: String) {
        guard let index = story.moments.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        story.moments[index].title = trimmed
        saveStory()
    }

    func setCaption(id: UUID, caption: String) {
        guard let index = story.moments.firstIndex(where: { $0.id == id }) else { return }
        story.moments[index].caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        saveStory()
    }
}

extension VolumeHandle {
    func directoryHint(store: CaseStore, caseID: String) -> URL {
        CaseStore.defaultRoot().appendingPathComponent("Cases", isDirectory: true)
            .appendingPathComponent(caseID, isDirectory: true)
    }
}

struct CaseViewerView: View {
    let record: CaseRecord

    @Environment(AppEnvironment.self) private var environment
    @State private var model = ViewerModel()
    @State private var dragStartAzimuth: Float = 0
    @State private var dragStartElevation: Float = 0
    @State private var dragStartPlaneElevation: Float = 0
    @State private var dragStartOffset: Float = 0
    @State private var dragStartFocus = SIMD3<Float>(0, 0, 0)
    @State private var rotationBase = CGSize.zero
    @State private var rotationNeedsRebase = false
    @State private var pinchStartDistance: Float = 0
    @State private var pinchStartSpan: Float = 0
    @State private var showsAR = false
    @State private var arPhoto: UIImage?
    @State private var showsNotes = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: Binding(get: { model.tab }, set: { model.tab = $0 })) {
                ForEach(ViewerModel.Tab.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            content

            if case .ready = model.state {
                VStack(spacing: 0) {
                    StoryStrip(model: model)
                    windowingBar
                }
                .frame(maxWidth: 760)
            }
        }
        .background(Color.dsBackground)
        .navigationTitle(record.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task {
            await model.load(store: environment.store, caseID: record.id)
            if CommandLine.arguments.contains("-slice") {
                model.tab = .slice
            }
        }
        .onDisappear { model.close() }
        .sheet(isPresented: $showsNotes) {
            CaseNotesSheet(model: model)
        }
        .fullScreenCover(isPresented: $showsAR) {
            if let renderer = model.renderer, let geometry = model.geometry {
                ARSliceScreen(
                    renderer: renderer,
                    geometry: geometry,
                    caseLabel: record.label,
                    onCapture: { arPhoto = $0 }
                )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Preparing volume…")
                    .font(.body)
                    .foregroundStyle(Color.dsTextSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.dsSafetyOrange)
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.dsTextPrimary)
                Button("Try Again") {
                    Task { await model.load(store: environment.store, caseID: record.id) }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            switch model.tab {
            case .volume: volumeStage
            case .mpr: MPRStage(model: model)
            case .pano: PanoStage(model: model)
            case .slice: sliceStage
            }
        }
    }

    @ViewBuilder
    private var volumeStage: some View {
        if let renderer = model.renderer {
            GeometryReader { proxy in
                VolumeMetalView(
                    renderer: renderer,
                    mode: .volume,
                    camera: model.camera,
                    window: model.window,
                    presentation: model.presentation,
                    shaded: model.volumeShaded,
                    mip: model.volumeMIP,
                    isPaused: false
                )
                .background(Color.black)
                .gesture(orbitGesture(size: proxy.size))
                .simultaneousGesture(zoomGesture)
                .onTapGesture(count: 2) { model.resetView() }
            }
            .overlay(alignment: .bottomLeading) { hint("Drag to rotate · pinch to zoom · double-tap to reset") }
            .overlay(alignment: .topLeading) { volumeStyleControls }
            .overlay(alignment: .top) { captionChip }
        }
    }

    @ViewBuilder
    private var sliceStage: some View {
        if let renderer = model.renderer {
            GeometryReader { proxy in
                let aspect = Float(max(proxy.size.width, 1) / max(proxy.size.height, 1))
                let mapper = SliceMarkMapper(
                    planeToLocal: model.planeToLocal(aspect: aspect),
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
                        let scale = model.planeSpanMM / Float(max(size.height, 1))
                        model.panPlane(byMM: SIMD2<Float>(
                            Float(-delta.width) * scale,
                            Float(delta.height) * scale
                        ))
                    },
                    onTwoFingerActive: { active in
                        model.isTwoFingerNavigating = active
                        if active { model.cancelActiveStroke() }
                    }
                )
                .background(Color.black)
                .overlay(marksOverlay(mapper: mapper).allowsHitTesting(false))
                .contentShape(Rectangle())
                .gesture(sliceDragGesture(size: proxy.size, mapper: mapper))
                .simultaneousGesture(sliceZoomGesture)
                .onTapGesture(count: 2) {
                    if !model.isMarking { model.resetView() }
                }
            }
            .overlay(alignment: .bottomLeading) {
                hint(
                    model.isMarking
                        ? "Draw on the picture to mark it"
                        : "Drag to turn the cut · bar to move through"
                )
            }
            .overlay(alignment: .topTrailing) { markingControls }
            .overlay {
                if let geometry = model.geometry {
                    let axes = SlicePlaneMath.planeAxes(
                        azimuth: model.planeAzimuth,
                        elevation: model.planeElevation
                    )
                    OrientationBadge(
                        horizontalLocal: axes.horizontal,
                        verticalLocal: axes.vertical,
                        geometry: geometry
                    )
                }
            }
            .overlay(alignment: .topLeading) {
                if !model.isMarking { directionPresets }
            }
            .overlay(alignment: .trailing) {
                if !model.isMarking {
                    SliceDepthBar(
                        offsetMM: Binding(
                            get: { model.planeOffsetMM },
                            set: { model.planeOffsetMM = $0 }
                        ),
                        rangeMM: model.planeRangeMM
                    )
                    .padding(.trailing, 6)
                }
            }
            .overlay(alignment: .top) { captionChip.padding(.top, 44) }
        }
    }

    private func marksOverlay(mapper: SliceMarkMapper) -> some View {
        var strokes: [[Vec3]] = []
        if model.activeSliceMomentMatchesPlane, let moment = model.activeMoment {
            strokes = moment.strokesLocalMM
        }
        if model.currentStrokeLocalMM.count > 1 {
            strokes.append(model.currentStrokeLocalMM)
        }
        let polylines: [[CGPoint]] = strokes.map { stroke in
            stroke.map { mapper.screenPoint(fromLocalMM: $0) }
        }
        let ink = Color.dsBrandPrimary.opacity(0.9)
        return Canvas { context, _ in
            for points in polylines where points.count > 1 {
                var path = Path()
                path.addLines(points)
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 1.6))
                    layer.stroke(
                        path,
                        with: .color(.white.opacity(0.55)),
                        style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round)
                    )
                }
                context.stroke(
                    path,
                    with: .color(ink),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    private var markingControls: some View {
        VStack(spacing: 10) {
            stageButton(
                systemImage: "pencil.tip",
                label: model.isMarking ? "Stop marking" : "Mark the picture",
                highlighted: model.isMarking
            ) {
                withAnimation(.snappy) { model.toggleMarking() }
            }
            if model.isMarking {
                stageButton(systemImage: "arrow.uturn.backward", label: "Undo last mark", highlighted: false) {
                    model.undoLastStroke()
                }
                stageButton(systemImage: "trash", label: "Clear marks", highlighted: false) {
                    model.clearMarks()
                }
            }
        }
        .padding(12)
    }

    private func stageButton(
        systemImage: String,
        label: String,
        highlighted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(highlighted ? Color.white : Color.dsBrandPrimary)
                .frame(width: 44, height: 44)
                .background(
                    highlighted ? Color.dsBrandPrimary : Color.dsCard.opacity(0.92),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.dsSeparator.opacity(highlighted ? 0 : 1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var captionChip: some View {
        if let moment = model.activeMoment, !moment.caption.isEmpty {
            Text(moment.caption)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .transition(.opacity)
        }
    }

    private func sliceDragGesture(size: CGSize, mapper: SliceMarkMapper) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if model.isTwoFingerNavigating {
                    rotationNeedsRebase = true
                    return
                }
                if model.isMarking {
                    if model.currentStrokeLocalMM.isEmpty {
                        model.appendStrokePoint(mapper.localMM(fromScreenPoint: value.startLocation))
                    }
                    model.appendStrokePoint(mapper.localMM(fromScreenPoint: value.location))
                } else {
                    if value.translation == .zero || rotationNeedsRebase {
                        dragStartAzimuth = model.planeAzimuth
                        dragStartPlaneElevation = model.planeElevation
                        dragStartFocus = model.currentFocusLocalMM()
                        rotationBase = value.translation
                        rotationNeedsRebase = false
                    }
                    let dx = Float((value.translation.width - rotationBase.width) / max(size.width, 1)) * 3.2
                    let dy = Float((value.translation.height - rotationBase.height) / max(size.height, 1)) * 2.4
                    model.setAngles(
                        azimuth: dragStartAzimuth + dx,
                        elevation: dragStartPlaneElevation + dy,
                        keepingFocus: dragStartFocus
                    )
                }
            }
            .onEnded { _ in
                rotationNeedsRebase = false
                if model.isMarking { model.endStroke() }
            }
    }

    private var volumeStyleControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(VolumePresentation.allCases) { style in
                styleChip(style.displayName, selected: !model.volumeMIP && model.volumeStyle == style) {
                    model.volumeMIP = false
                    model.volumeStyle = style
                }
            }
            styleChip("MIP", selected: model.volumeMIP) {
                model.volumeMIP.toggle()
            }
            styleChip("Shaded", selected: model.volumeShaded) {
                model.volumeShaded.toggle()
            }
            .opacity(model.volumeMIP ? 0.4 : 1)
            .disabled(model.volumeMIP)
        }
        .padding(.leading, 10)
        .padding(.top, 10)
    }

    private func styleChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(selected ? Color.black : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    selected ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.black.opacity(0.45)),
                    in: Capsule()
                )
        }
    }

    private var directionPresets: some View {
        VStack(alignment: .leading, spacing: 6) {
            directionChip("Front", azimuth: 0, elevation: 0)
            directionChip("Side", azimuth: .pi / 2, elevation: 0)
            directionChip("Top", azimuth: 0, elevation: -.pi / 2)
        }
        .padding(.leading, 10)
        .padding(.top, 44)
    }

    private func directionChip(_ title: String, azimuth: Float, elevation: Float) -> some View {
        let selected = abs(model.planeAzimuth - azimuth) < 0.05
            && abs(model.planeElevation - elevation) < 0.05
        return Button {
            withAnimation(.snappy) {
                model.setDirection(azimuth: azimuth, elevation: elevation)
            }
        } label: {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(selected ? Color.black : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    selected ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.black.opacity(0.45)),
                    in: Capsule()
                )
        }
    }

    private func hint(_ text: String) -> some View {
        FadingHint(text: text).id(text)
    }

    private var windowingBar: some View {
        HStack(spacing: 12) {
            Picker("Window", selection: Binding(get: { model.preset }, set: { model.preset = $0 })) {
                Text(WindowPreset.bone.displayName).tag(WindowPreset.bone)
                Text(WindowPreset.softTissue.displayName).tag(WindowPreset.softTissue)
                if model.preset == .custom {
                    Text(WindowPreset.custom.displayName).tag(WindowPreset.custom)
                }
            }
            .pickerStyle(.segmented)
            Text("\(model.window.displayText) grey")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.dsTextSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func orbitGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if value.translation == .zero {
                    dragStartAzimuth = model.camera.azimuth
                    dragStartElevation = model.camera.elevation
                }
                let dx = Float(value.translation.width / max(size.width, 1)) * 3.2
                let dy = Float(value.translation.height / max(size.height, 1)) * 2.4
                model.camera.azimuth = dragStartAzimuth - dx
                model.camera.elevation = min(
                    max(dragStartElevation + dy, OrbitCamera.minimumElevation),
                    OrbitCamera.maximumElevation
                )
            }
    }

    private var zoomGesture: some Gesture {
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
    }

    private var sliceZoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchStartSpan == 0 { pinchStartSpan = model.planeSpanMM }
                model.planeSpanMM = pinchStartSpan
                model.zoomPlane(by: Float(value.magnification))
            }
            .onEnded { _ in pinchStartSpan = 0 }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showsNotes = true
            } label: {
                Image(systemName: (model.story.notes?.isEmpty ?? true) ? "note.text" : "note.text.badge.plus")
            }
            .accessibilityLabel("Notes for the visit")
            .disabled(model.state != .ready)
        }
        ToolbarItemGroup(placement: .bottomBar) {
            if let renderer = model.renderer, let geometry = model.geometry {
                ShareSummaryButton(
                    caseLabel: record.label,
                    renderer: renderer,
                    geometry: geometry,
                    story: model.story,
                    arPhoto: arPhoto
                )
                .labelStyle(.iconOnly)
            }
            Spacer()
            Button {
                showsAR = true
            } label: {
                Label("Show on the table", systemImage: "arkit")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.state != .ready)
        }
    }
}

struct FadingHint: View {
    let text: String
    @State private var visible = true

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.35), in: Capsule())
            .padding(12)
            .opacity(visible ? 1 : 0)
            .task {
                try? await Task.sleep(for: .seconds(5))
                withAnimation(.easeOut(duration: 0.8)) { visible = false }
            }
            .allowsHitTesting(false)
    }
}

struct SliceDepthBar: View {
    @Binding var offsetMM: Float
    let rangeMM: Float
    private let barHeight: CGFloat = 190
    private let thumbSize: CGFloat = 28
    @State private var dragStartOffset: Float?

    private var travel: CGFloat { barHeight - thumbSize - 6 }

    var body: some View {
        ZStack {
            Capsule()
                .fill(.black.opacity(0.35))
                .frame(width: 34, height: barHeight)
            Rectangle()
                .fill(.white.opacity(0.5))
                .frame(width: 18, height: 1.5)
            Circle()
                .fill(.white)
                .frame(width: thumbSize, height: thumbSize)
                .shadow(radius: 2)
                .overlay {
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.dsBrandPrimary)
                }
                .offset(y: thumbOffset)
        }
        .contentShape(Rectangle())
        .accessibilityLabel("Move through the jaw")
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    if dragStartOffset == nil { dragStartOffset = offsetMM }
                    let delta = Float(gesture.translation.height / travel) * rangeMM * 2
                    offsetMM = min(max((dragStartOffset ?? 0) + delta, -rangeMM), rangeMM)
                }
                .onEnded { _ in dragStartOffset = nil }
        )
        .onTapGesture(count: 2) { offsetMM = 0 }
    }

    private var thumbOffset: CGFloat {
        guard rangeMM > 0 else { return 0 }
        return CGFloat(offsetMM / rangeMM) * travel / 2
    }
}
