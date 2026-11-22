import SwiftUI
import SwiftData

/// Live draft shown on the calendar while the editor is open.
struct EventDraftPreview: Equatable {
    var title: String
    var colorHex: String
    var start: Date
    var end: Date
    var kindTitle: String
    var isSession: Bool = false
    var isMilestone: Bool = false

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSession {
            return trimmed.isEmpty ? "New Session" : trimmed
        }
        if isMilestone {
            return trimmed.isEmpty ? "New Milestone" : trimmed
        }
        return trimmed.isEmpty ? "New Event" : trimmed
    }
}

struct EventEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lockState: LockState
    @Query(sort: \Zone.title) private var zones: [Zone]
    @Query(sort: \Blocklist.name) private var blocklists: [Blocklist]

    var event: CalendarEvent?
    var session: StudySession?
    var milestone: Milestone?
    var initialDate: Date = Date()
    var onSave: () -> Void = {}
    var onCancel: () -> Void = {}
    @Binding var preview: EventDraftPreview?

    @State private var isSession: Bool
    @State private var isMilestone: Bool
    @State private var title: String
    @State private var kind: EventKind
    @State private var zone: Zone?
    @State private var start: Date
    @State private var end: Date
    @State private var allDay: Bool
    @State private var sessionDraft = SessionScheduleDraft()
    @State private var error = ""
    @State private var didLoad = false

    /// Synthetic visual length for milestone markers on the timed grid.
    private static let milestoneDisplayDuration: TimeInterval = 45 * 60

    init(
        event: CalendarEvent? = nil,
        session: StudySession? = nil,
        milestone: Milestone? = nil,
        initialDate: Date = Date(),
        onSave: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {},
        preview: Binding<EventDraftPreview?>
    ) {
        self.event = event
        self.session = session
        self.milestone = milestone
        self.initialDate = initialDate
        self.onSave = onSave
        self.onCancel = onCancel
        self._preview = preview

        if let session {
            _isSession = State(initialValue: true)
            _isMilestone = State(initialValue: false)
            _title = State(initialValue: session.title)
            _kind = State(initialValue: .quiz)
            _zone = State(initialValue: session.zone)
            _start = State(initialValue: session.startDate)
            _end = State(initialValue: max(session.endDate, session.startDate.addingTimeInterval(5 * 60)))
            _allDay = State(initialValue: false)
        } else if let milestone {
            _isSession = State(initialValue: false)
            _isMilestone = State(initialValue: true)
            _title = State(initialValue: milestone.title)
            _kind = State(initialValue: milestone.kind)
            _zone = State(initialValue: milestone.zone)
            _start = State(initialValue: milestone.startDate)
            _end = State(initialValue: milestone.startDate.addingTimeInterval(Self.milestoneDisplayDuration))
            _allDay = State(initialValue: false)
        } else if let event {
            _isSession = State(initialValue: false)
            _isMilestone = State(initialValue: false)
            _title = State(initialValue: event.title)
            _kind = State(initialValue: event.kind)
            _zone = State(initialValue: event.zone)
            _start = State(initialValue: event.startDate)
            _end = State(initialValue: max(event.endDate, event.startDate.addingTimeInterval(5 * 60)))
            _allDay = State(initialValue: event.allDay)
        } else {
            _isSession = State(initialValue: false)
            _isMilestone = State(initialValue: false)
            _title = State(initialValue: "")
            _kind = State(initialValue: .quiz)
            _zone = State(initialValue: nil)
            _start = State(initialValue: initialDate)
            _end = State(initialValue: initialDate.addingTimeInterval(3600))
            _allDay = State(initialValue: false)
        }
    }

    private var typeLocked: Bool {
        event != nil || session != nil || milestone != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(headerTitle)
                    .font(.headline)
                Spacer()
                Button {
                    preview = nil
                    onCancel()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Form {
                Section {
                    Toggle("Session", isOn: Binding(
                        get: { isSession },
                        set: { newValue in
                            isSession = newValue
                            if newValue { isMilestone = false }
                        }
                    ))
                    .disabled(typeLocked)

                    Toggle("Milestone", isOn: Binding(
                        get: { isMilestone },
                        set: { newValue in
                            isMilestone = newValue
                            if newValue { isSession = false }
                        }
                    ))
                    .disabled(typeLocked)

                    Text(typeCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isSession {
                    Section("When") {
                        TextField("Title", text: $sessionDraft.title)
                        Picker("Zone (optional)", selection: $zone) {
                            Text("None — block only").tag(Optional<Zone>.none)
                            ForEach(zones, id: \.id) { z in
                                Text(z.title).tag(Optional(z))
                            }
                        }
                        DurationScheduleRow(start: $start, end: $end)
                    }

                    SessionSchedulingFields(
                        draft: $sessionDraft,
                        zone: zone,
                        sessionStart: start,
                        sessionEnd: $end,
                        blocklists: blocklists
                    )
                } else if isMilestone {
                    Section {
                        TextField("Title", text: $title)
                        Picker("Kind", selection: $kind) {
                            ForEach(EventKind.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Zone", selection: $zone) {
                            Text("Select").tag(Optional<Zone>.none)
                            ForEach(zones, id: \.id) { z in
                                Text(z.title).tag(Optional(z))
                            }
                        }
                        DatePicker("Starts", selection: $start)
                    }
                } else {
                    Section {
                        TextField("Title", text: $title)
                        Picker("Kind", selection: $kind) {
                            ForEach(EventKind.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Zone", selection: $zone) {
                            Text("Select").tag(Optional<Zone>.none)
                            ForEach(zones, id: \.id) { z in
                                Text(z.title).tag(Optional(z))
                            }
                        }
                        Toggle("All day", isOn: $allDay)
                        if !allDay {
                            DurationScheduleRow(
                                start: $start,
                                end: $end,
                                clockSize: 150
                            )
                        } else {
                            DatePicker("Starts", selection: $start, displayedComponents: .date)
                            DatePicker("Ends", selection: $end, displayedComponents: .date)
                        }
                    }
                }

                if !error.isEmpty {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if typeLocked {
                        Button("Delete", role: .destructive) { deleteItem() }
                            .disabled(!canDelete)
                    }
                    Spacer()
                    Button("Done") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave)
                }
                if session != nil && !canDelete {
                    Text("Active sessions can’t be deleted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear { loadIfNeeded() }
        .onChange(of: title) { _, _ in pushPreview() }
        .onChange(of: sessionDraft.title) { _, _ in pushPreview() }
        .onChange(of: kind) { _, _ in pushPreview() }
        .onChange(of: zone?.id) { _, _ in
            if isSession {
                sessionDraft.milestone = nil
                if zone == nil { sessionDraft.validationEnabled = false }
            }
            pushPreview()
        }
        .onChange(of: start) { oldStart, newStart in
            if isMilestone {
                end = newStart.addingTimeInterval(Self.milestoneDisplayDuration)
            } else {
                let duration = end.timeIntervalSince(oldStart)
                if duration > 0 {
                    end = newStart.addingTimeInterval(duration)
                }
            }
            pushPreview()
        }
        .onChange(of: end) { _, _ in pushPreview() }
        .onChange(of: allDay) { _, _ in pushPreview() }
        .onChange(of: isSession) { _, sessionMode in
            error = ""
            if sessionMode {
                isMilestone = false
                allDay = false
            }
            pushPreview()
        }
        .onChange(of: isMilestone) { _, milestoneMode in
            error = ""
            if milestoneMode {
                isSession = false
                allDay = false
                end = start.addingTimeInterval(Self.milestoneDisplayDuration)
            }
            pushPreview()
        }
        .onChange(of: sessionDraft.blocklist?.id) { _, _ in pushPreview() }
    }

    private var typeCaption: String {
        if isSession {
            return "Sessions can block apps with a block list, segments, and breaks."
        }
        if isMilestone {
            return "Milestones mark what you need to prove. They appear on the calendar at a start time — no end time."
        }
        return "Events are shown on the calendar only — they never block."
    }

    private var headerTitle: String {
        if session != nil { return "Edit Session" }
        if milestone != nil { return "Edit Milestone" }
        if event != nil { return "Edit Event" }
        if isSession { return "New Session" }
        if isMilestone { return "New Milestone" }
        return "New Event"
    }

    private var canSave: Bool {
        if isSession {
            return !sessionDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && sessionDraft.blocklist != nil
                && end > start
        }
        if isMilestone {
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && zone != nil
        }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && zone != nil
    }

    private var canDelete: Bool {
        if event != nil || milestone != nil { return true }
        guard let session else { return false }
        return !lockState.activePhases.contains { $0.sessionID == session.id }
    }

    private func deleteItem() {
        guard canDelete else {
            error = "Active sessions can’t be deleted."
            return
        }
        if let event {
            context.delete(event)
        } else if let session {
            context.delete(session)
        } else if let milestone {
            context.delete(milestone)
        } else {
            return
        }
        try? context.save()
        preview = nil
        onSave()
        dismiss()
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let session {
            isSession = true
            isMilestone = false
            zone = session.zone
            start = session.startDate
            end = max(session.endDate, session.startDate.addingTimeInterval(5 * 60))
            sessionDraft.load(from: session)
        } else if let milestone {
            isSession = false
            isMilestone = true
            title = milestone.title
            kind = milestone.kind
            zone = milestone.zone
            start = milestone.startDate
            end = milestone.startDate.addingTimeInterval(Self.milestoneDisplayDuration)
            allDay = false
        } else if let event {
            isSession = false
            isMilestone = false
            title = event.title
            kind = event.kind
            zone = event.zone
            start = event.startDate
            end = max(event.endDate, event.startDate.addingTimeInterval(5 * 60))
            allDay = event.allDay
        } else {
            start = initialDate
            end = initialDate.addingTimeInterval(3600)
            zone = zones.first
        }
        pushPreview()
    }

    private func pushPreview() {
        let previewTitle: String
        let kindTitle: String
        let color = zone?.colorHex ?? "#64748B"
        let previewEnd: Date

        if isSession {
            let trimmed = sessionDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            previewTitle = trimmed.isEmpty ? "New Session" : trimmed
            kindTitle = "Session"
            previewEnd = end
        } else if isMilestone {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            previewTitle = trimmed.isEmpty ? "New Milestone" : trimmed
            kindTitle = kind.title
            previewEnd = start.addingTimeInterval(Self.milestoneDisplayDuration)
        } else {
            previewTitle = title
            kindTitle = kind.title
            previewEnd = end
        }

        preview = EventDraftPreview(
            title: previewTitle,
            colorHex: color,
            start: start,
            end: previewEnd,
            kindTitle: kindTitle,
            isSession: isSession,
            isMilestone: isMilestone
        )
    }

    private func save() {
        error = ""
        if isSession {
            if let message = SessionScheduleDraft.save(
                draft: sessionDraft,
                start: start,
                end: end,
                zone: zone,
                context: context,
                existing: session
            ) {
                error = message
                return
            }
        } else if isMilestone {
            guard canSave else { return }
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = milestone ?? Milestone(
                title: trimmed,
                kind: kind,
                startDate: start,
                zone: zone
            )
            target.title = trimmed
            target.kind = kind
            target.zone = zone
            target.startDate = start
            if milestone == nil { context.insert(target) }
            try? context.save()
        } else {
            guard canSave else { return }
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = event ?? CalendarEvent(title: trimmed, kind: kind, startDate: start, endDate: end, zone: zone)
            target.title = trimmed
            target.kind = kind
            target.zone = zone
            target.startDate = start
            target.endDate = end
            target.allDay = allDay
            if event == nil { context.insert(target) }
            try? context.save()
        }
        onSave()
        preview = nil
        dismiss()
    }
}
