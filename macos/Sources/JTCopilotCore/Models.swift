import Foundation

/// 文档模板类型。数值与 Windows 版 AppSettings 中的 schema 保持一致。
public enum DocumentTemplate: Int, CaseIterable, Codable, Hashable, Sendable {
    case auto = 0
    case projectManagement = 1
    case prd = 2
    case weeklyReport = 3
    case solution = 4
    case general = 5
    case meetingMinutes = 6

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(Int.self)) ?? DocumentTemplate.auto.rawValue
        self = DocumentTemplate(rawValue: rawValue) ?? .auto
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct DocumentTemplateOption: Identifiable, Hashable, Sendable {
    public let value: DocumentTemplate
    public let displayName: String

    public var id: Int { value.rawValue }

    public init(value: DocumentTemplate, displayName: String) {
        self.value = value
        self.displayName = displayName
    }
}

public enum DocumentTemplateCatalog {
    public static let all: [DocumentTemplateOption] = [
        .init(value: .auto, displayName: "自动识别"),
        .init(value: .projectManagement, displayName: "项目管理文档"),
        .init(value: .meetingMinutes, displayName: "会议纪要"),
        .init(value: .prd, displayName: "PRD"),
        .init(value: .weeklyReport, displayName: "周报"),
        .init(value: .solution, displayName: "方案文档")
    ]

    public static func displayName(for template: DocumentTemplate) -> String {
        if let option = all.first(where: { $0.value == template }) {
            return option.displayName
        }

        return template == .general ? "通用写作" : "自动识别"
    }
}

public enum VoiceCaptureState: String, Codable, Sendable {
    case idle
    case recording
    case processing
    case completed
    case captured
    case faulted
}

public struct VoiceCaptureSnapshot: Equatable, Sendable {
    public var state: VoiceCaptureState
    public var elapsed: TimeInterval
    public var errorMessage: String?
    public var recordingPath: String?

    public init(
        state: VoiceCaptureState,
        elapsed: TimeInterval = 0,
        errorMessage: String? = nil,
        recordingPath: String? = nil
    ) {
        self.state = state
        self.elapsed = elapsed
        self.errorMessage = errorMessage
        self.recordingPath = recordingPath
    }

    public static let idle = VoiceCaptureSnapshot(state: .idle)
}

public struct AudioDeviceDescriptor: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let isDefault: Bool

    public init(id: String, displayName: String, isDefault: Bool) {
        self.id = id
        self.displayName = displayName
        self.isDefault = isDefault
    }
}

public struct WritingGuidance: Equatable, Sendable {
    public var framework: [String]
    public var nextSentence: String
    public var nextSentenceHistory: [String]
    public var directions: [String]
    public var missingPoints: [String]
    public var template: DocumentTemplate

    public init(
        framework: [String] = [],
        nextSentence: String = "",
        nextSentenceHistory: [String] = [],
        directions: [String] = [],
        missingPoints: [String] = [],
        template: DocumentTemplate = .auto
    ) {
        self.framework = framework
        self.nextSentence = nextSentence
        self.nextSentenceHistory = nextSentenceHistory
        self.directions = directions
        self.missingPoints = missingPoints
        self.template = template
    }

    public static let empty = WritingGuidance()
}

public struct WritingSessionUpdate: Equatable, Sendable {
    public var stableTranscript: String
    public var draftTranscript: String
    public var guidance: WritingGuidance
    public var statusText: String
    public var optimizedTranscript: String
    public var replacementMessage: String

    public init(
        stableTranscript: String = "",
        draftTranscript: String = "",
        guidance: WritingGuidance = .empty,
        statusText: String = "",
        optimizedTranscript: String = "",
        replacementMessage: String = ""
    ) {
        self.stableTranscript = stableTranscript
        self.draftTranscript = draftTranscript
        self.guidance = guidance
        self.statusText = statusText
        self.optimizedTranscript = optimizedTranscript
        self.replacementMessage = replacementMessage
    }
}

public struct AudioCaptureResult: Sendable {
    public let recordingPath: String?
    public let duration: TimeInterval

    public init(recordingPath: String?, duration: TimeInterval) {
        self.recordingPath = recordingPath
        self.duration = duration
    }
}

public struct TextInsertionResult: Sendable {
    public let success: Bool
    public let message: String

    public init(success: Bool, message: String = "") {
        self.success = success
        self.message = message
    }

    public static let succeeded = TextInsertionResult(success: true)
}

public struct LiveTranscriptUpdate: Sendable {
    public let text: String
    public let isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}
