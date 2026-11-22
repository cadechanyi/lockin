import SwiftUI
import SwiftData

struct SessionWizardView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var lockState: LockState
    @Query(sort: \Zone.title) private var zones: [Zone]
    @Query(sort: \Blocklist.name) private var blocklists: [Blocklist]

    var onSave: () -> Void

    @State private var zone: Zone?
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3600)
    @State private var draft = SessionScheduleDraft()
    @State private var error = ""

    var body: some View {
        Form {
            Section {
                Text("Schedule a focus block with a block list. A zone is optional — use one when you want materials and proof unlock.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("When") {
                TextField("Title", text: $draft.title)
                Picker("Zone (optional)", selection: $zone) {
                    Text("None — block only").tag(Optional<Zone>.none)
                    ForEach(zones, id: \.id) { z in Text(z.title).tag(Optional(z)) }
                }
                DurationScheduleRow(start: $start, end: $end)
                Text("A zone is optional. With only a block list, Lockin just locks for the scheduled time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SessionSchedulingFields(
                draft: $draft,
                zone: zone,
                sessionStart: start,
                sessionEnd: $end,
                blocklists: blocklists
            )

            if !error.isEmpty {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }

            Section {
                Button("Schedule session") { save() }
            }
        }
        .navigationTitle("Schedule session")
        .formStyle(.grouped)
        .onChange(of: start) { oldStart, newStart in
            let duration = end.timeIntervalSince(oldStart)
            if duration > 0 {
                end = newStart.addingTimeInterval(duration)
            }
        }
        .onChange(of: zone?.id) { _, _ in
            draft.milestone = nil
            if zone == nil {
                draft.validationEnabled = false
            }
        }
    }

    private func save() {
        if let message = SessionScheduleDraft.save(
            draft: draft,
            start: start,
            end: end,
            zone: zone,
            context: context
        ) {
            error = message
            return
        }
        error = ""
        onSave()
    }
}

/// Shared proof / segments / breaks / block-list controls for session scheduling.
struct SessionSchedulingFields: View {
    @Binding var draft: SessionScheduleDraft
    var zone: Zone?
    var sessionStart: Date
    @Binding var sessionEnd: Date
    var blocklists: [Blocklist]

    var body: some View {
        Section("Proof") {
            Toggle("Require validation (proof)", isOn: $draft.validationEnabled)
                .disabled(zone == nil)
            if zone == nil {
                Text("Attach a zone to enable proof unlock. Without a zone, the session unlocks when time ends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker(draft.validationEnabled ? "Milestone" : "Milestone (optional)", selection: $draft.milestone) {
                    Text(draft.validationEnabled ? "Select" : "None").tag(Optional<Milestone>.none)
                    ForEach(zone?.milestones ?? [], id: \.id) { m in
                        Text(m.title).tag(Optional(m))
                    }
                }
                Text(draft.validationEnabled
                     ? "Apps stay locked until you pass."
                     : "Attach a milestone to count this session as study time toward it. If validation is off, the session ends when time ends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Segments") {
            Toggle("Split into segments", isOn: $draft.useSegments)
            if draft.useSegments {
                Stepper(
                    "\(draft.segments.count) segments",
                    value: Binding(
                        get: { max(draft.segments.count, SessionScheduleDraft.minSegments) },
                        set: {
                            draft.resizeSegments(to: $0, sessionStart: sessionStart, sessionEnd: sessionEnd)
                            expandSessionEndIfNeeded()
                        }
                    ),
                    in: SessionScheduleDraft.minSegments...SessionScheduleDraft.maxSegments
                )

                ForEach(Array(draft.segments.enumerated()), id: \.element.id) { index, _ in
                    SegmentScheduleCard(
                        number: index + 1,
                        start: segmentStartBinding(at: index),
                        end: segmentEndBinding(at: index),
                        subset: $draft.segments[index].subset
                    )
                }

                Text("A segment can start when the previous one ends, but not earlier. Matching times keep the block continuous; a gap is an open break where another session can run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: draft.useSegments) { _, enabled in
            if enabled {
                draft.resizeSegments(
                    to: max(draft.segments.count, SessionScheduleDraft.minSegments),
                    sessionStart: sessionStart,
                    sessionEnd: sessionEnd
                )
                expandSessionEndIfNeeded()
            }
        }
        .onAppear {
            if draft.useSegments && draft.segments.count < SessionScheduleDraft.minSegments {
                draft.resizeSegments(
                    to: SessionScheduleDraft.minSegments,
                    sessionStart: sessionStart,
                    sessionEnd: sessionEnd
                )
                expandSessionEndIfNeeded()
            }
        }

        Section("Breaks") {
            Toggle("Add breaks", isOn: $draft.useBreaks)
            if draft.useBreaks {
                Button("Custom break") {
                    draft.breaks.append(DraftBreak(kind: "custom", start: sessionStart, end: sessionStart.addingTimeInterval(300)))
                }
                Button("Repeating break") {
                    draft.breaks.append(DraftBreak(kind: "repeating", duration: 5, interval: 60, offset: 55))
                }
                ForEach($draft.breaks) { $b in
                    if b.kind == "custom" {
                        DatePicker("Break start", selection: Binding($b.start, replacingNil: sessionStart))
                        DatePicker("Break end", selection: Binding($b.end, replacingNil: sessionStart.addingTimeInterval(300)))
                        if let breakStart = b.start {
                            RotaryDurationClock(
                                minutes: Binding(
                                    get: {
                                        let endDate = b.end ?? breakStart.addingTimeInterval(300)
                                        let raw = max(5, Int((endDate.timeIntervalSince(breakStart) / 60).rounded()))
                                        return Int((Double(raw) / 5.0).rounded()) * 5
                                    },
                                    set: { mins in
                                        b.end = breakStart.addingTimeInterval(TimeInterval(mins * 60))
                                    }
                                ),
                                minimumMinutes: 5,
                                maximumMinutes: 60,
                                size: 140
                            )
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        Text("Break length")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        RotaryDurationClock(
                            minutes: Binding(
                                get: { Int((Double(b.duration) / 5.0).rounded()) * 5 },
                                set: { b.duration = max(5, $0) }
                            ),
                            minimumMinutes: 5,
                            maximumMinutes: 60,
                            size: 140
                        )
                        .frame(maxWidth: .infinity)
                        Stepper("Every \(b.interval) min", value: $b.interval, in: 10...240, step: 5)
                        Stepper("First break after \(b.offset) min", value: $b.offset, in: 0...240, step: 5)
                    }
                }
                .onDelete { draft.breaks.remove(atOffsets: $0) }
            }
        }

        Section("Block list") {
            Picker("Block list", selection: $draft.blocklist) {
                Text("Select").tag(Optional<Blocklist>.none)
                ForEach(blocklists, id: \.id) { b in Text(b.name).tag(Optional(b)) }
            }
            Text("Create block lists in the Blocklist tab first. During a block you can add apps, never remove.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func earliestStart(for index: Int) -> Date {
        if index <= 0 { return sessionStart }
        return draft.segments[index - 1].end
    }

    private func expandSessionEndIfNeeded() {
        if let lastEnd = draft.segments.map(\.end).max(), lastEnd > sessionEnd {
            sessionEnd = lastEnd
        }
    }

    private func segmentStartBinding(at index: Int) -> Binding<Date> {
        Binding(
            get: { draft.segments[index].start },
            set: { newValue in
                let clamped = max(newValue, earliestStart(for: index))
                draft.segments[index].start = clamped
                if draft.segments[index].end <= clamped {
                    draft.segments[index].end = clamped.addingTimeInterval(30 * 60)
                }
                expandSessionEndIfNeeded()
            }
        )
    }

    private func segmentEndBinding(at index: Int) -> Binding<Date> {
        Binding(
            get: { draft.segments[index].end },
            set: { newValue in
                let start = draft.segments[index].start
                let end = max(newValue, start.addingTimeInterval(5 * 60))
                draft.segments[index].end = end

                // Keep later segments from starting before this one ends; preserve each duration.
                var cursor = end
                for i in (index + 1)..<draft.segments.count {
                    let duration = max(
                        draft.segments[i].end.timeIntervalSince(draft.segments[i].start),
                        5 * 60
                    )
                    if draft.segments[i].start < cursor {
                        draft.segments[i].start = cursor
                        draft.segments[i].end = cursor.addingTimeInterval(duration)
                    }
                    cursor = max(cursor, draft.segments[i].end)
                }
                expandSessionEndIfNeeded()
            }
        )
    }
}

/// Numbered segment editor with a compact rotary schedule row.
private struct SegmentScheduleCard: View {
    var number: Int
    @Binding var start: Date
    @Binding var end: Date
    @Binding var subset: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 52, alignment: .center)
                .accessibilityLabel("Segment \(number)")

            VStack(alignment: .leading, spacing: 10) {
                DurationScheduleRow(
                    start: $start,
                    end: $end,
                    maximumMinutes: 24 * 60,
                    clockSize: 120
                )
                TextField("Deliverable (e.g. Ch 2.1)", text: $subset)
            }
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }
}

struct SessionScheduleDraft {
    static let minSegments = 2
    static let maxSegments = 99

    var title = ""
    var validationEnabled = false
    var milestone: Milestone?
    var useSegments = false
    var segments: [DraftSegment] = []
    var useBreaks = false
    var breaks: [DraftBreak] = []
    var blocklist: Blocklist?

    mutating func resizeSegments(to count: Int, sessionStart: Date, sessionEnd: Date) {
        let target = min(Self.maxSegments, max(Self.minSegments, count))
        if segments.isEmpty {
            let total = max(sessionEnd.timeIntervalSince(sessionStart), TimeInterval(target * 30 * 60))
            let slice = total / Double(target)
            segments = (0..<target).map { index in
                let start = sessionStart.addingTimeInterval(slice * Double(index))
                let end = sessionStart.addingTimeInterval(slice * Double(index + 1))
                return DraftSegment(start: start, end: max(end, start.addingTimeInterval(5 * 60)))
            }
            return
        }

        while segments.count < target {
            let previousEnd = segments.last?.end ?? sessionStart
            let end = previousEnd.addingTimeInterval(30 * 60)
            segments.append(DraftSegment(start: previousEnd, end: end))
        }

        if segments.count > target {
            segments = Array(segments.prefix(target))
        }
    }

    /// Persists a new session. Returns an error message, or `nil` on success.
    @discardableResult
    static func save(
        draft: SessionScheduleDraft,
        start: Date,
        end: Date,
        zone: Zone?,
        context: ModelContext,
        existing: StudySession? = nil
    ) -> String? {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return "Enter a title." }
        guard let blocklist = draft.blocklist else { return "Pick a block list." }
        guard end > start else { return "End must be after start." }
        let maxEnd = start.addingTimeInterval(TimeInterval(ScheduleEvaluator.maxSessionDays * 86400))
        guard end <= maxEnd else { return "Session cannot exceed 14 days." }
        if draft.validationEnabled {
            guard zone != nil else { return "Pick a zone to use validation." }
            guard draft.milestone != nil else { return "Attach a milestone or turn validation off." }
        }

        let blockingRanges: [(start: Date, end: Date)]
        if draft.useSegments {
            guard draft.segments.count >= minSegments else {
                return "Use at least \(minSegments) segments or turn segments off."
            }
            guard draft.segments.count <= maxSegments else {
                return "Sessions can have at most \(maxSegments) segments."
            }
            for (index, seg) in draft.segments.enumerated() {
                if seg.end <= seg.start {
                    return "Segment \(index + 1) must end after it starts."
                }
                if seg.start < start || seg.end > end {
                    return "Each segment must sit inside the session period."
                }
                if index > 0 {
                    let previous = draft.segments[index - 1]
                    if seg.start < previous.end {
                        return "Segment \(index + 1) cannot start before segment \(index) ends."
                    }
                }
            }
            blockingRanges = draft.segments.map { ($0.start, $0.end) }
        } else {
            blockingRanges = [(start, end)]
        }

        // iOS DeviceActivity cannot schedule windows shorter than ~15 minutes, so a shorter
        // block would silently never start or end in the background.
        let minBlock: TimeInterval = 15 * 60
        if blockingRanges.contains(where: { $0.end.timeIntervalSince($0.start) < minBlock - 1 }) {
            return "Blocks must be at least 15 minutes long."
        }

        if draft.useBreaks {
            for draftBreak in draft.breaks where draftBreak.kind == "custom" {
                if let s = draftBreak.start, let e = draftBreak.end, s < start || e > end {
                    return "Breaks must fall inside the session."
                }
            }
        }

        if let conflict = conflictingSessionTitle(
            blockingRanges: blockingRanges,
            context: context,
            excluding: existing?.id
        ) {
            return "This session overlaps “\(conflict)”. Blocking sessions can’t share the same time."
        }

        let session = existing ?? StudySession()
        if existing == nil { context.insert(session) }

        // Replace prior segments/breaks when editing.
        if let existing {
            for seg in existing.segments ?? [] { context.delete(seg) }
            for b in existing.breaks ?? [] { context.delete(b) }
        }

        session.title = trimmedTitle
        session.zone = zone
        session.startDate = start
        session.endDate = end
        session.validationEnabled = draft.validationEnabled
        session.milestone = zone != nil ? draft.milestone : nil
        session.blocklist = blocklist
        session.isSegmented = draft.useSegments

        if draft.useSegments {
            for segmentDraft in draft.segments {
                let seg = SessionSegment()
                seg.startDate = segmentDraft.start
                seg.endDate = segmentDraft.end
                seg.milestoneSubset = segmentDraft.subset
                seg.session = session
                context.insert(seg)
            }
        } else {
            let seg = SessionSegment()
            seg.startDate = start
            seg.endDate = end
            seg.milestoneSubset = draft.milestone?.scope ?? ""
            seg.session = session
            context.insert(seg)
        }

        if draft.useBreaks {
            for breakDraft in draft.breaks {
                let b = BreakWindow()
                b.kindRaw = breakDraft.kind
                b.startDate = breakDraft.start
                b.endDate = breakDraft.end
                b.durationMinutes = breakDraft.duration
                b.intervalMinutes = breakDraft.interval
                b.offsetMinutes = breakDraft.offset
                b.session = session
                context.insert(b)
            }
        }

        try? context.save()
        return nil
    }

    /// Half-open style overlap: touching end-to-start is allowed (continuous handoff / open gap boundary).
    private static func rangesOverlap(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> Bool {
        aStart < bEnd && bStart < aEnd
    }

    private static func conflictingSessionTitle(
        blockingRanges: [(start: Date, end: Date)],
        context: ModelContext,
        excluding: UUID?
    ) -> String? {
        let descriptor = FetchDescriptor<StudySession>()
        guard let others = try? context.fetch(descriptor) else { return nil }

        for other in others {
            if let excluding, other.id == excluding { continue }
            let otherRanges = Self.blockingRanges(for: other)
            for range in blockingRanges {
                for otherRange in otherRanges {
                    if rangesOverlap(range.start, range.end, otherRange.start, otherRange.end) {
                        return other.displayTitle
                    }
                }
            }
        }
        return nil
    }

    private static func blockingRanges(for session: StudySession) -> [(start: Date, end: Date)] {
        let segments = (session.segments ?? []).sorted { $0.startDate < $1.startDate }
        if session.isSegmented, !segments.isEmpty {
            return segments.map { ($0.startDate, $0.endDate) }
        }
        if let only = segments.first {
            return [(only.startDate, only.endDate)]
        }
        return [(session.startDate, session.endDate)]
    }

    mutating func load(from session: StudySession) {
        title = session.title
        validationEnabled = session.validationEnabled
        milestone = session.milestone
        blocklist = session.blocklist
        useSegments = session.isSegmented
        segments = (session.segments ?? [])
            .sorted { $0.startDate < $1.startDate }
            .map { DraftSegment(id: $0.id, start: $0.startDate, end: $0.endDate, subset: $0.milestoneSubset) }
        let loadedBreaks = session.breaks ?? []
        useBreaks = !loadedBreaks.isEmpty
        breaks = loadedBreaks.map {
            DraftBreak(
                id: $0.id,
                kind: $0.kindRaw,
                start: $0.startDate,
                end: $0.endDate,
                duration: $0.durationMinutes,
                interval: $0.intervalMinutes,
                offset: $0.offsetMinutes
            )
        }
    }
}

struct DraftSegment: Identifiable {
    var id = UUID()
    var start: Date
    var end: Date
    var subset: String = ""
}

struct DraftBreak: Identifiable {
    var id = UUID()
    var kind: String
    var start: Date? = nil
    var end: Date? = nil
    var duration: Int = 5
    var interval: Int = 60
    var offset: Int = 55
}

extension Binding where Value == Date {
    init(_ source: Binding<Date?>, replacingNil fallback: Date) {
        self.init(
            get: { source.wrappedValue ?? fallback },
            set: { source.wrappedValue = $0 }
        )
    }
}
