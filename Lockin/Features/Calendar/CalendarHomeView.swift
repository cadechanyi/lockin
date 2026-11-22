import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

enum CalendarScope: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct CalendarItem: Identifiable, Hashable {
    enum Kind: Hashable { case event, session, milestone, draft }
    var id: String
    var eventID: UUID?
    var sessionID: UUID?
    var milestoneID: UUID?
    var title: String
    var subtitle: String
    var colorHex: String
    var start: Date
    var end: Date
    var kind: Kind
    /// True when this day's block is a continuation from a prior day.
    var continuesFromPrevious: Bool = false
    /// True when the item keeps going past the end of this day.
    var continuesIntoNext: Bool = false
    var isDraft: Bool { kind == .draft }
    /// Milestones are point-in-time (start only).
    var isPointInTime: Bool { kind == .milestone }
}

struct CalendarHomeView: View {
    @EnvironmentObject private var lockState: LockState
    @Query(sort: \CalendarEvent.startDate) private var events: [CalendarEvent]
    @Query(sort: \StudySession.startDate) private var sessions: [StudySession]
    @Query(sort: \Milestone.startDate) private var milestones: [Milestone]

    @AppStorage("calendar.showSessions") private var showSessions = true
    @State private var scope: CalendarScope = .month
    @State private var cursor = Date()
    @State private var selectedDay = Date()
    @State private var draftSeed: DraftCalendarDate?
    @State private var editingEvent: CalendarEvent?
    @State private var editingSession: StudySession?
    @State private var editingMilestone: Milestone?
    @State private var livePreview: EventDraftPreview?
    @State private var visibleMonth = Date()
    @State private var scrollWeekID: String?

    /// Synthetic visual length for milestone markers on the timed grid.
    private static let milestoneDisplayDuration: TimeInterval = 45 * 60

    private let hourHeight: CGFloat = 52
    private let dayStartHour = 0
    private let dayEndHour = 24
    private let weeksBefore = 78
    private let weeksAfter = 78

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Picker("Scope", selection: $scope) {
                        ForEach(CalendarScope.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Toggle(isOn: $showSessions) {
                        HStack(spacing: 4) {
                            Image(systemName: showSessions ? "lock.fill" : "lock.open")
                            Text("Sessions")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    .toggleStyle(.button)
                    .help(showSessions ? "Hide scheduled sessions" : "Show scheduled sessions")
                    .accessibilityLabel(showSessions ? "Hide sessions" : "Show sessions")
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 6)

                switch scope {
                case .month:
                    Text(DateFormatters.monthYear.string(from: visibleMonth))
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                        .animation(.easeInOut(duration: 0.15), value: DateFormatters.monthYear.string(from: visibleMonth))
                    monthScroller
                case .week:
                    weekHeader
                    timedGrid(days: weekDays)
                        .modifier(DirectionalScrollNavigator {
                            shiftCursor($0)
                        })
                case .day:
                    dayHeader
                    timedGrid(days: [Calendar.current.startOfDay(for: cursor)])
                        .modifier(DirectionalScrollNavigator {
                            shiftCursor($0)
                        })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Calendar")
            #if os(macOS)
            .focusable()
            .onKeyPress(.leftArrow) {
                shiftCursor(-1)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                shiftCursor(1)
                return .handled
            }
            #endif
            .onChange(of: scope) { _, newScope in
                if newScope == .month {
                    visibleMonth = cursor
                    scrollWeekID = weekID(startOfWeek(cursor))
                }
            }
            .sheet(item: $draftSeed) { draft in
                editorSheet(initialDate: draft.date, event: nil, session: nil, milestone: nil)
            }
            .sheet(isPresented: Binding(
                get: { editingEvent != nil || editingSession != nil || editingMilestone != nil },
                set: { if !$0 { clearEditor() } }
            )) {
                if let event = editingEvent {
                    editorSheet(initialDate: event.startDate, event: event, session: nil, milestone: nil)
                } else if let session = editingSession {
                    editorSheet(initialDate: session.startDate, event: nil, session: session, milestone: nil)
                } else if let milestone = editingMilestone {
                    editorSheet(initialDate: milestone.startDate, event: nil, session: nil, milestone: milestone)
                }
            }
        }
    }

    private func clearEditor() {
        draftSeed = nil
        editingEvent = nil
        editingSession = nil
        editingMilestone = nil
        livePreview = nil
    }

    @ViewBuilder
    private func editorSheet(
        initialDate: Date,
        event: CalendarEvent?,
        session: StudySession?,
        milestone: Milestone?
    ) -> some View {
        NavigationStack {
            EventEditorView(
                event: event,
                session: session,
                milestone: milestone,
                initialDate: initialDate,
                onSave: {
                    if livePreview?.isSession == true {
                        showSessions = true
                    }
                    clearEditor()
                },
                onCancel: { clearEditor() },
                preview: $livePreview
            )
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #if os(iOS)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        #endif
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 520)
        #endif
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: startOfWeek(cursor)) }
    }

    private var weekHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            navArrow(systemName: "chevron.left") { shiftCursor(-1) }

            Text("Week of \(DateFormatters.shortDate.string(from: startOfWeek(cursor)))")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            navArrow(systemName: "chevron.right") { shiftCursor(1) }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                ForEach(weekDays, id: \.self) { day in
                    let selected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
                    let today = Calendar.current.isDateInToday(day)
                    Button {
                        selectedDay = day
                        cursor = day
                    } label: {
                        VStack(spacing: 1) {
                            Text(weekdayLabel(day))
                                .font(.caption2.weight(.semibold))
                            Text("\(Calendar.current.component(.day, from: day))")
                                .font(.subheadline.weight(today ? .bold : .medium))
                        }
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .frame(width: 40, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? Color.accentColor : (today ? Color.accentColor.opacity(0.15) : Color.clear))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var dayHeader: some View {
        HStack(spacing: 12) {
            navArrow(systemName: "chevron.left") { shiftCursor(-1) }
            Text(DateFormatters.day.string(from: cursor))
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            navArrow(systemName: "chevron.right") { shiftCursor(1) }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func navArrow(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Month (continuous week scroll)

    private var monthWeeks: [MonthWeek] {
        let origin = startOfWeek(Date())
        return (-weeksBefore...weeksAfter).compactMap { offset in
            guard let start = Calendar.current.date(byAdding: .weekOfYear, value: offset, to: origin) else { return nil }
            let days = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
            return MonthWeek(id: weekID(start), start: start, days: days)
        }
    }

    private var monthScroller: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)
        return VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { d in
                    Text(d)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 8)

            GeometryReader { geo in
                let weekHeight = max(78, geo.size.height / 5)
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(monthWeeks) { week in
                                HStack(spacing: 1) {
                                    ForEach(week.days, id: \.self) { day in
                                        monthCell(day, height: weekHeight - 2, referenceMonth: visibleMonth)
                                    }
                                }
                                .frame(height: weekHeight)
                                .id(week.id)
                                .scrollTransition(.animated) { content, _ in content }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $scrollWeekID)
                    .onAppear {
                        let id = weekID(startOfWeek(cursor))
                        scrollWeekID = id
                        visibleMonth = monthAnchor(for: startOfWeek(cursor))
                        DispatchQueue.main.async {
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
                    .onChange(of: scrollWeekID) { _, newID in
                        guard let newID,
                              let week = monthWeeks.first(where: { $0.id == newID }) else { return }
                        let anchor = monthAnchor(for: week.start)
                        if !Calendar.current.isDate(anchor, equalTo: visibleMonth, toGranularity: .month) {
                            visibleMonth = anchor
                        }
                        cursor = week.start
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func monthCell(_ day: Date, height: CGFloat, referenceMonth: Date) -> some View {
        let cal = Calendar.current
        let inMonth = cal.isDate(day, equalTo: referenceMonth, toGranularity: .month)
        let isSelected = cal.isDate(day, inSameDayAs: selectedDay)
        let isToday = cal.isDateInToday(day)
        let dayItems = items(on: day)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(inMonth ? 0.06 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
                .modifier(CalendarClickModifier(
                    onSelect: {
                        selectedDay = day
                        cursor = day
                    },
                    onCreate: {
                        selectedDay = day
                        cursor = day
                        beginDraft(at: defaultStart(on: day))
                    }
                ))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(.subheadline.weight(isToday ? .bold : .medium))
                    .foregroundStyle(inMonth ? Color.primary : Color.secondary)
                    .padding(4)
                    .background {
                        if isToday { Circle().fill(Color.accentColor.opacity(0.2)) }
                    }
                    .allowsHitTesting(false)

                ForEach(dayItems.prefix(3)) { item in
                    if item.isDraft {
                        draftChip(item)
                    } else {
                        Button { openItem(item) } label: {
                            Text(item.title)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(hex: item.colorHex).opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if dayItems.count > 3 {
                    Text("+\(dayItems.count - 3) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
                Spacer(minLength: 0).allowsHitTesting(false)
            }
            .padding(4)
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
    }

    private func draftChip(_ item: CalendarItem) -> some View {
        Text(item.title)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: item.colorHex).opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color(hex: item.colorHex), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            )
            .allowsHitTesting(false)
    }

    // MARK: - Week / Day timed grid

    private func timedGrid(days: [Date]) -> some View {
        GeometryReader { geo in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(dayStartHour..<dayEndHour, id: \.self) { hour in
                            Text(hourLabel(hour))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 52, height: hourHeight, alignment: .topTrailing)
                                .padding(.trailing, 6)
                        }
                    }

                    ForEach(days, id: \.self) { day in
                        ZStack(alignment: .topLeading) {
                            VStack(spacing: 0) {
                                ForEach(dayStartHour..<dayEndHour, id: \.self) { hour in
                                    hourSlot(day: day, hour: hour)
                                }
                            }

                            ForEach(items(on: day)) { item in
                                timedEventBlock(item, on: day)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: CGFloat(dayEndHour - dayStartHour) * hourHeight)
                        .clipped()
                        .overlay(Rectangle().fill(Color.secondary.opacity(0.15)).frame(width: 1), alignment: .leading)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
                .frame(minHeight: max(geo.size.height, CGFloat(dayEndHour - dayStartHour) * hourHeight))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hourSlot(day: Date, hour: Int) -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.06))
            .frame(height: 1)
            .frame(maxWidth: .infinity, minHeight: hourHeight, maxHeight: hourHeight, alignment: .top)
            .background(Color.primary.opacity(0.02))
            .contentShape(Rectangle())
            .modifier(CalendarClickModifier(
                onSelect: {
                    selectedDay = day
                    cursor = day
                },
                onCreate: {
                    selectedDay = day
                    cursor = day
                    beginDraft(at: date(on: day, hour: hour))
                }
            ))
    }

    private func timedEventBlock(_ item: CalendarItem, on day: Date) -> some View {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let minutesInDay = (dayEndHour - dayStartHour) * 60
        let startMinutes = min(minutesInDay - 1, max(0, Int(item.start.timeIntervalSince(dayStart) / 60)))
        let rawEndMinutes = Int(item.end.timeIntervalSince(dayStart) / 60)
        let minVisible = item.continuesIntoNext ? 1 : 15
        let endMinutes = min(minutesInDay, max(rawEndMinutes, startMinutes + minVisible))
        let y = CGFloat(startMinutes) / 60 * hourHeight
        let height = max(22, CGFloat(endMinutes - startMinutes) / 60 * hourHeight)

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if item.kind == .milestone || (item.isDraft && livePreview?.isMilestone == true) {
                    Image(systemName: "flag.fill")
                        .font(.caption2)
                }
                Text(item.title)
                    .font(.caption.weight(.bold))
                    .lineLimit(2)
            }
            Text(timedBlockSubtitle(item))
                .font(.caption2)
                .opacity(0.85)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(
            Color(hex: item.colorHex).opacity(item.isDraft ? 0.55 : 0.85),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            if item.isDraft {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(hex: item.colorHex), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            }
        }
        .overlay(alignment: .leading) {
            if item.continuesFromPrevious {
                Rectangle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 3)
            }
        }
        .overlay(alignment: .trailing) {
            if item.continuesIntoNext {
                Rectangle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 3)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 3)
        .offset(y: y)
        .allowsHitTesting(!item.isDraft)
        .onTapGesture { openItem(item) }
    }

    private func timedBlockSubtitle(_ item: CalendarItem) -> String {
        let startText = DateFormatters.shortTime.string(from: item.start)
        if item.isPointInTime {
            return item.subtitle.isEmpty ? startText : "\(item.subtitle) · \(startText)"
        }
        let endText = DateFormatters.shortTime.string(from: item.end)
        switch (item.continuesFromPrevious, item.continuesIntoNext) {
        case (true, true):
            return "all day"
        case (true, false):
            return "← \(endText)"
        case (false, true):
            return "\(startText) →"
        case (false, false):
            return startText
        }
    }

    // MARK: - Helpers

    private func beginDraft(at date: Date) {
        livePreview = EventDraftPreview(
            title: "",
            colorHex: "#64748B",
            start: date,
            end: date.addingTimeInterval(3600),
            kindTitle: EventKind.quiz.title
        )
        draftSeed = DraftCalendarDate(date: date)
    }

    private func openItem(_ item: CalendarItem) {
        guard !item.isDraft else { return }
        if item.kind == .event, let id = item.eventID,
           let event = events.first(where: { $0.id == id }) {
            editingSession = nil
            editingMilestone = nil
            editingEvent = event
        } else if item.kind == .session, let id = item.sessionID,
                  let session = sessions.first(where: { $0.id == id }) {
            editingEvent = nil
            editingMilestone = nil
            editingSession = session
        } else if item.kind == .milestone, let id = item.milestoneID,
                  let milestone = milestones.first(where: { $0.id == id }) {
            editingEvent = nil
            editingSession = nil
            editingMilestone = milestone
        }
    }

    private func items(on day: Date) -> [CalendarItem] {
        let cal = Calendar.current
        var result: [CalendarItem] = []
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? day
        let dayInterval = DateInterval(start: dayStart, end: dayEnd)

        if let preview = livePreview {
            let end = max(preview.end, preview.start.addingTimeInterval(60))
            if DateInterval(start: preview.start, end: end).intersects(dayInterval) {
                let clippedStart = max(preview.start, dayStart)
                let clippedEnd = min(end, dayEnd)
                result.append(CalendarItem(
                    id: "draft-preview-\(dayStart.timeIntervalSince1970)",
                    eventID: nil,
                    sessionID: nil,
                    milestoneID: nil,
                    title: preview.displayTitle,
                    subtitle: preview.isMilestone ? "Milestone · \(preview.kindTitle)" : preview.kindTitle,
                    colorHex: preview.colorHex,
                    start: clippedStart,
                    end: max(clippedEnd, clippedStart.addingTimeInterval(60)),
                    kind: .draft,
                    continuesFromPrevious: preview.start < dayStart,
                    continuesIntoNext: end > dayEnd
                ))
            }
        }

        for event in events {
            // While editing, hide the persisted copy so the live draft replaces it.
            if let editing = editingEvent, editing.id == event.id { continue }
            let end = max(event.endDate, event.startDate.addingTimeInterval(60))
            if DateInterval(start: event.startDate, end: end).intersects(dayInterval) {
                let clippedStart = max(event.startDate, dayStart)
                let clippedEnd = min(end, dayEnd)
                result.append(CalendarItem(
                    id: "e-\(event.id)-\(dayStart.timeIntervalSince1970)",
                    eventID: event.id,
                    sessionID: nil,
                    milestoneID: nil,
                    title: event.title,
                    subtitle: event.kind.title,
                    colorHex: event.zone?.colorHex ?? "#64748B",
                    start: clippedStart,
                    end: max(clippedEnd, clippedStart.addingTimeInterval(60)),
                    kind: .event,
                    continuesFromPrevious: event.startDate < dayStart,
                    continuesIntoNext: end > dayEnd
                ))
            }
        }

        for milestone in milestones {
            if let editing = editingMilestone, editing.id == milestone.id { continue }
            let end = milestone.startDate.addingTimeInterval(Self.milestoneDisplayDuration)
            if DateInterval(start: milestone.startDate, end: end).intersects(dayInterval) {
                let clippedStart = max(milestone.startDate, dayStart)
                let clippedEnd = min(end, dayEnd)
                result.append(CalendarItem(
                    id: "m-\(milestone.id)-\(dayStart.timeIntervalSince1970)",
                    eventID: nil,
                    sessionID: nil,
                    milestoneID: milestone.id,
                    title: milestone.title,
                    subtitle: milestone.kind.title,
                    colorHex: milestone.zone?.colorHex ?? "#64748B",
                    start: clippedStart,
                    end: max(clippedEnd, clippedStart.addingTimeInterval(60)),
                    kind: .milestone,
                    continuesFromPrevious: false,
                    continuesIntoNext: false
                ))
            }
        }

        if showSessions {
            for session in sessions {
                // While editing, hide the persisted copy so the live draft replaces it.
                if let editing = editingSession, editing.id == session.id { continue }
                let interval = DateInterval(start: session.startDate, end: session.endDate)
                if interval.intersects(dayInterval) {
                    let clippedStart = max(session.startDate, dayStart)
                    let clippedEnd = min(session.endDate, dayEnd)
                    result.append(CalendarItem(
                        id: "s-\(session.id)-\(dayStart.timeIntervalSince1970)",
                        eventID: nil,
                        sessionID: session.id,
                        milestoneID: nil,
                        title: session.displayTitle,
                        subtitle: session.milestone?.title ?? session.blocklist?.name ?? "",
                        colorHex: session.zone?.colorHex ?? "#64748B",
                        start: clippedStart,
                        end: max(clippedEnd, clippedStart.addingTimeInterval(60)),
                        kind: .session,
                        continuesFromPrevious: session.startDate < dayStart,
                        continuesIntoNext: session.endDate > dayEnd
                    ))
                }
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    private func shiftCursor(_ delta: Int) {
        let cal = Calendar.current
        switch scope {
        case .day:
            cursor = cal.date(byAdding: .day, value: delta, to: cursor) ?? cursor
            selectedDay = cursor
        case .week:
            cursor = cal.date(byAdding: .weekOfYear, value: delta, to: cursor) ?? cursor
            selectedDay = cursor
        case .month:
            if let next = cal.date(byAdding: .weekOfYear, value: delta, to: startOfWeek(cursor)) {
                cursor = next
                scrollWeekID = weekID(next)
                visibleMonth = monthAnchor(for: next)
            }
        }
    }

    private func startOfWeek(_ date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
    }

    private func weekID(_ start: Date) -> String {
        String(Int(start.timeIntervalSince1970))
    }

    /// Month label follows the month that owns most days in the week (Apple Calendar–like).
    private func monthAnchor(for weekStart: Date) -> Date {
        let cal = Calendar.current
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
        var counts: [DateComponents: Int] = [:]
        for day in days {
            let key = cal.dateComponents([.year, .month], from: day)
            counts[key, default: 0] += 1
        }
        let best = counts.max { $0.value < $1.value }?.key
        return best.flatMap { cal.date(from: $0) } ?? weekStart
    }

    private func weekdayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    private func hourLabel(_ hour: Int) -> String {
        var comps = DateComponents()
        comps.hour = hour
        let date = Calendar.current.date(from: comps) ?? Date()
        return DateFormatters.shortTime.string(from: date)
    }

    private func date(on day: Date, hour: Int) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = hour
        comps.minute = 0
        return cal.date(from: comps) ?? day
    }

    private func defaultStart(on day: Date) -> Date {
        let cal = Calendar.current
        if cal.isDateInToday(day) {
            let hour = max(8, cal.component(.hour, from: Date()))
            return date(on: day, hour: hour)
        }
        return date(on: day, hour: 9)
    }
}

private struct MonthWeek: Identifiable {
    var id: String
    var start: Date
    var days: [Date]
}

private struct DraftCalendarDate: Identifiable {
    let id = UUID()
    var date: Date
}

// MARK: - Click / scroll helpers

private struct CalendarClickModifier: ViewModifier {
    var onSelect: () -> Void
    var onCreate: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            CalendarClickCatcher(onSelect: onSelect, onCreate: onCreate)
        }
    }
}

private struct CalendarClickCatcher: View {
    var onSelect: () -> Void
    var onCreate: () -> Void

    var body: some View {
        #if os(macOS)
        MacClickCatcher(onSelect: onSelect, onCreate: onCreate)
        #else
        IOSClickCatcher(onSelect: onSelect, onCreate: onCreate)
        #endif
    }
}

#if os(macOS)
private struct MacClickCatcher: NSViewRepresentable {
    var onSelect: () -> Void
    var onCreate: () -> Void

    func makeNSView(context: Context) -> ClickView {
        let view = ClickView()
        view.onSelect = onSelect
        view.onCreate = onCreate
        return view
    }

    func updateNSView(_ nsView: ClickView, context: Context) {
        nsView.onSelect = onSelect
        nsView.onCreate = onCreate
    }

    final class ClickView: NSView {
        var onSelect: (() -> Void)?
        var onCreate: (() -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? { self }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount >= 2 { onCreate?() } else { onSelect?() }
        }
        override var acceptsFirstResponder: Bool { true }
    }
}
#endif

#if os(iOS)
private struct IOSClickCatcher: UIViewRepresentable {
    var onSelect: () -> Void
    var onCreate: () -> Void

    func makeUIView(context: Context) -> TapView {
        let view = TapView()
        view.onSelect = onSelect
        view.onCreate = onCreate
        view.isUserInteractionEnabled = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: TapView, context: Context) {
        uiView.onSelect = onSelect
        uiView.onCreate = onCreate
    }

    final class TapView: UIView {
        var onSelect: (() -> Void)?
        var onCreate: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDouble))
            doubleTap.numberOfTapsRequired = 2
            let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingle))
            singleTap.numberOfTapsRequired = 1
            singleTap.require(toFail: doubleTap)
            addGestureRecognizer(doubleTap)
            addGestureRecognizer(singleTap)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        @objc private func handleSingle() { onSelect?() }
        @objc private func handleDouble() { onCreate?() }
    }
}
#endif

/// Two-finger trackpad / scroll-wheel navigation for day & week.
/// One gesture = one day/week step (not continuous scrubbing).
private struct DirectionalScrollNavigator: ViewModifier {
    var onNavigate: (Int) -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.background(
            ScrollWheelMonitor(onNavigate: onNavigate)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 80)
                .onEnded { value in
                    let horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
                    guard horizontal, abs(value.translation.width) > 80 else { return }
                    onNavigate(value.translation.width < 0 ? 1 : -1)
                }
        )
        #else
        content.simultaneousGesture(
            DragGesture(minimumDistance: 100)
                .onEnded { value in
                    let horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
                    guard horizontal, abs(value.translation.width) > 100 else { return }
                    onNavigate(value.translation.width < 0 ? 1 : -1)
                }
        )
        #endif
    }
}

#if os(macOS)
private struct ScrollWheelMonitor: NSViewRepresentable {
    var onNavigate: (Int) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onNavigate = onNavigate
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.onNavigate = onNavigate
    }

    final class MonitorView: NSView {
        var onNavigate: ((Int) -> Void)?
        private var accum: CGFloat = 0
        private var consumedGesture = false
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    self?.handle(event)
                    return event
                }
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        private func handle(_ event: NSEvent) {
            // End of finger contact or momentum — allow the next gesture to move once.
            if event.phase == .ended || event.phase == .cancelled
                || event.momentumPhase == .ended || event.momentumPhase == .cancelled {
                accum = 0
                consumedGesture = false
                return
            }

            // Already moved for this gesture (including leftover momentum).
            if consumedGesture { return }
            // Ignore inertial leftover after the step so one flick ≠ many days.
            if !event.momentumPhase.isEmpty { return }

            let delta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX
                : 0
            guard abs(delta) > 0.2 else { return }

            accum += delta
            // Require a deliberate flick before stepping once.
            if accum > 40 {
                onNavigate?(-1)
                consumedGesture = true
                accum = 0
            } else if accum < -40 {
                onNavigate?(1)
                consumedGesture = true
                accum = 0
            }
        }
    }
}
#endif
