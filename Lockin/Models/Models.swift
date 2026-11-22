import Foundation
import SwiftData

enum EventKind: String, CaseIterable, Identifiable, Codable {
    case lecture, quiz, lab, midterm, finalExam = "final", assignment, project, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .finalExam: return "Final"
        default: return rawValue.capitalized
        }
    }
}

@Model
final class Zone {
    var id: UUID = UUID()
    var title: String = ""
    var colorHex: String = "#2563EB"
    var isClass: Bool = true
    var textbookResources: String = ""
    var practiceQuizzes: String = ""
    var customMaterialsJSON: String = "[]"
    var createdAt: Date = Date()
    /// Course grade (percent) the student is aiming for. Drives "what do I need" math.
    var targetGrade: Double = 80

    @Relationship(deleteRule: .cascade, inverse: \Milestone.zone)
    var milestones: [Milestone]? = []

    @Relationship(deleteRule: .cascade, inverse: \CalendarEvent.zone)
    var events: [CalendarEvent]? = []

    @Relationship(deleteRule: .cascade, inverse: \StudySession.zone)
    var sessions: [StudySession]? = []

    init(title: String, colorHex: String = "#2563EB", isClass: Bool = true) {
        self.title = title
        self.colorHex = colorHex
        self.isClass = isClass
    }

    var customMaterials: [NamedMaterial] {
        get { (try? JSONDecoder().decode([NamedMaterial].self, from: Data(customMaterialsJSON.utf8))) ?? [] }
        set { customMaterialsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }
}

struct NamedMaterial: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var content: String = ""
}

/// Where the student is with a milestone. Graded milestones (a score is entered) are
/// always treated as finished regardless of this value.
enum MilestoneStatus: String, CaseIterable, Identifiable, Codable {
    case notStarted, studying, ready, done
    var id: String { rawValue }
    var title: String {
        switch self {
        case .notStarted: return "Not started"
        case .studying: return "Studying"
        case .ready: return "Ready"
        case .done: return "Done"
        }
    }
    var systemImage: String {
        switch self {
        case .notStarted: return "circle"
        case .studying: return "book"
        case .ready: return "checkmark.seal"
        case .done: return "checkmark.circle.fill"
        }
    }
}

/// A dated thing in a class (assignment, quiz, exam…). Doubles as both the study scope
/// that sessions attach to and the graded item that feeds the course grade.
@Model
final class Milestone {
    var id: UUID = UUID()
    var title: String = ""
    var scope: String = ""
    var kindRaw: String = EventKind.custom.rawValue
    /// When it happens / is due. (Name kept for calendar + CloudKit compatibility.)
    var startDate: Date = Date()
    var createdAt: Date = Date()
    var zone: Zone?

    /// Share of the course grade, in percent. 0 means it does not count toward the grade.
    var weight: Double = 0
    /// Score earned. `nil` means not graded yet.
    var scoreEarned: Double?
    var scoreMax: Double = 100
    var statusRaw: String = MilestoneStatus.notStarted.rawValue
    var notes: String = ""

    @Relationship(deleteRule: .nullify, inverse: \StudySession.milestone)
    var sessions: [StudySession]? = []

    var kind: EventKind {
        get { EventKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    var status: MilestoneStatus {
        get { MilestoneStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    var isGraded: Bool { scoreEarned != nil }

    /// Score as a percent, if graded.
    var scorePercent: Double? {
        guard let earned = scoreEarned, scoreMax > 0 else { return nil }
        return earned / scoreMax * 100
    }

    /// Finished = graded, or explicitly marked done.
    var isFinished: Bool { isGraded || status == .done }

    var gradeItem: GradeItem {
        GradeItem(weight: weight, earned: scoreEarned, max: scoreMax)
    }

    init(
        title: String,
        scope: String = "",
        kind: EventKind = .custom,
        startDate: Date = Date(),
        zone: Zone? = nil
    ) {
        self.title = title
        self.scope = scope
        self.kindRaw = kind.rawValue
        self.startDate = startDate
        self.zone = zone
    }
}

@Model
final class CalendarEvent {
    var id: UUID = UUID()
    var title: String = ""
    var kindRaw: String = EventKind.custom.rawValue
    var startDate: Date = Date()
    var endDate: Date = Date()
    var allDay: Bool = false
    var zone: Zone?

    var kind: EventKind {
        get { EventKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    init(title: String, kind: EventKind = .custom, startDate: Date, endDate: Date, zone: Zone? = nil) {
        self.title = title
        self.kindRaw = kind.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.zone = zone
    }
}

@Model
final class Blocklist {
    var id: UUID = UUID()
    var name: String = ""
    var familyActivitySelectionData: Data?
    var macFamilyActivitySelectionData: Data?
    var websitePresetsJSON: String = "[]"
    var customWebsitesJSON: String = "[]"
    var xboxEnabled: Bool = false
    var xboxGamertag: String = ""
    var macBundleIDsJSON: String = "[]"
    var createdAt: Date = Date()

    @Relationship(inverse: \StudySession.blocklist)
    var sessions: [StudySession]? = []

    init(name: String) {
        self.name = name
    }

    var websitePresets: [WebsitePreset] {
        get {
            let raw = (try? JSONDecoder().decode([String].self, from: Data(websitePresetsJSON.utf8))) ?? []
            return raw.compactMap(WebsitePreset.init(rawValue:))
        }
        set {
            websitePresetsJSON = (try? String(data: JSONEncoder().encode(newValue.map(\.rawValue)), encoding: .utf8)) ?? "[]"
        }
    }

    var customWebsites: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(customWebsitesJSON.utf8))) ?? [] }
        set { customWebsitesJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }

    var macBundleIDs: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(macBundleIDsJSON.utf8))) ?? [] }
        set { macBundleIDsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }
}

@Model
final class StudySession {
    var id: UUID = UUID()
    var title: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date().addingTimeInterval(3600)
    var validationEnabled: Bool = false
    var isSegmented: Bool = false
    var createdAt: Date = Date()
    var zone: Zone?
    var milestone: Milestone?
    var blocklist: Blocklist?

    /// Display title with fallbacks for sessions created before titles were required.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let zoneTitle = zone?.title, !zoneTitle.isEmpty { return zoneTitle }
        if let listName = blocklist?.name, !listName.isEmpty { return listName }
        return "Focus block"
    }

    @Relationship(deleteRule: .cascade, inverse: \SessionSegment.session)
    var segments: [SessionSegment]? = []

    @Relationship(deleteRule: .cascade, inverse: \BreakWindow.session)
    var breaks: [BreakWindow]? = []

    init() {}

    var capDate: Date {
        startDate.addingTimeInterval(TimeInterval(ScheduleEvaluator.maxSessionDays * 24 * 60 * 60))
    }

    var effectiveSegments: [SessionSegment] {
        let existing = (segments ?? []).sorted { $0.startDate < $1.startDate }
        if !existing.isEmpty { return existing }
        return []
    }
}

@Model
final class SessionSegment {
    var id: UUID = UUID()
    var startDate: Date = Date()
    var endDate: Date = Date().addingTimeInterval(3600)
    var milestoneSubset: String = ""
    var validatedAt: Date?
    var session: StudySession?

    init() {}

    var isValidated: Bool { validatedAt != nil }
}

@Model
final class BreakWindow {
    var id: UUID = UUID()
    var kindRaw: String = "custom"
    var startDate: Date?
    var endDate: Date?
    var durationMinutes: Int = 5
    var intervalMinutes: Int = 60
    var offsetMinutes: Int = 55
    var session: StudySession?
    var segmentID: UUID?

    init() {}
}

/// Synced preferences (LLM provider, Xbox nudge). Per-device flags (onboarding, Screen
/// Time authorization, login item) live in `DeviceSettings` — they must NOT sync, since
/// "this phone is authorized" says nothing about the Mac. The legacy per-device fields
/// below are kept only so existing stores keep opening; nothing reads them any more
/// except the one-time onboarding migration in `RootView`.
@Model
final class AppSettings {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var screenTimeAuthorized: Bool = false
    var screenTimePasscodeConfirmed: Bool = false
    var onboardingComplete: Bool = false
    var macOnboardingComplete: Bool = false
    var macScreenTimeAuthorized: Bool = false
    var xboxNudgeIntervalMinutes: Int = 15
    var llmProviderRaw: String = "anthropic"
    var openAtLogin: Bool = false

    init() {}
}

@Model
final class BreakUsageLog {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    var sessionID: UUID = UUID()
    var note: String = ""

    init() {}
}

@Model
final class XboxPresenceLog {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var gamertag: String = ""
    var isPlaying: Bool = false
    var titleName: String = ""
    var sessionID: UUID?

    init() {}
}

@Model
final class ValidationAttempt {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var sessionID: UUID = UUID()
    var segmentID: UUID?
    var passed: Bool = false
    var mastery: Bool = false
    var questionKind: String = ""

    init() {}
}
