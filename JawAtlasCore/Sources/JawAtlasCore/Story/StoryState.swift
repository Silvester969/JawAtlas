import Foundation

public enum MomentStage: String, Codable, Sendable {
    case volume
    case slice
}

public struct StoryMoment: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var caption: String
    public var createdAt: Date
    public var stage: MomentStage
    public var windowPreset: String
    public var planeAzimuth: Double
    public var planeElevation: Double?
    public var planeOffsetMM: Double
    public var planePanX: Double
    public var planePanY: Double
    public var planeSpanMM: Double
    public var cameraAzimuth: Double
    public var cameraElevation: Double
    public var cameraDistance: Double
    public var strokesLocalMM: [[Vec3]]

    public init(
        id: UUID = UUID(),
        title: String,
        caption: String = "",
        createdAt: Date = Date(),
        stage: MomentStage,
        windowPreset: String,
        planeAzimuth: Double,
        planeElevation: Double? = 0,
        planeOffsetMM: Double,
        planePanX: Double,
        planePanY: Double,
        planeSpanMM: Double,
        cameraAzimuth: Double,
        cameraElevation: Double,
        cameraDistance: Double,
        strokesLocalMM: [[Vec3]] = []
    ) {
        self.id = id
        self.title = title
        self.caption = caption
        self.createdAt = createdAt
        self.stage = stage
        self.windowPreset = windowPreset
        self.planeAzimuth = planeAzimuth
        self.planeElevation = planeElevation
        self.planeOffsetMM = planeOffsetMM
        self.planePanX = planePanX
        self.planePanY = planePanY
        self.planeSpanMM = planeSpanMM
        self.cameraAzimuth = cameraAzimuth
        self.cameraElevation = cameraElevation
        self.cameraDistance = cameraDistance
        self.strokesLocalMM = strokesLocalMM
    }
}

public struct StoryState: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var moments: [StoryMoment]
    public var notes: String?
    public var archControlPointsLocalMM: [Vec3]?

    public init(
        schemaVersion: Int = 1,
        moments: [StoryMoment] = [],
        notes: String? = nil,
        archControlPointsLocalMM: [Vec3]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.moments = moments
        self.notes = notes
        self.archControlPointsLocalMM = archControlPointsLocalMM
    }
}

public enum StoryStateIO {
    public static func load(from directory: URL) -> StoryState {
        let url = BundleLayout.storyURL(in: directory)
        guard let data = try? Data(contentsOf: url),
              let state = try? decoder().decode(StoryState.self, from: data),
              state.schemaVersion <= 1 else {
            return StoryState()
        }
        return state
    }

    public static func save(_ state: StoryState, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(
            to: BundleLayout.storyURL(in: directory),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
