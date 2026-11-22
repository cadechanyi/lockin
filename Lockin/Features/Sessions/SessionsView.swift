import SwiftUI
import SwiftData

struct SessionsView: View {
    @EnvironmentObject private var lockState: LockState
    @Environment(\.modelContext) private var context
    @Query(sort: \StudySession.startDate, order: .reverse) private var sessions: [StudySession]
    @State private var path = NavigationPath()
    @State private var showWizard = false

    private var grouped: [(title: String, items: [StudySession])] {
        let now = Date()
        let activeIDs = Set(lockState.activePhases.compactMap(\.sessionID))
        let active = sessions.filter { activeIDs.contains($0.id) }
        let upcoming = sessions.filter { !activeIDs.contains($0.id) && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
        let past = sessions.filter { !activeIDs.contains($0.id) && $0.endDate <= now }
            .sorted { $0.startDate > $1.startDate }
        var groups: [(String, [StudySession])] = []
        if !active.isEmpty { groups.append(("Active", active)) }
        if !upcoming.isEmpty { groups.append(("Upcoming", upcoming)) }
        if !past.isEmpty { groups.append(("Past", past)) }
        return groups
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    EntityCardGrid {
                        AddEntityCard(title: "Add new Session") {
                            showWizard = true
                        }
                    }
                    .padding(.bottom, -8)

                    ForEach(grouped, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.title)
                                .font(.title2.weight(.bold))
                                .padding(.horizontal)

                            EntityCardGrid {
                                ForEach(group.items, id: \.id) { session in
                                    Button {
                                        path.append(session.id)
                                    } label: {
                                        EntityCard(
                                            title: session.displayTitle,
                                            subtitle: sessionSubtitle(session),
                                            borderColor: Color(hex: session.zone?.colorHex ?? "#64748B"),
                                            fill: Color(hex: session.zone?.colorHex ?? "#64748B").opacity(0.08)
                                        ) {
                                            statusBadge(for: session)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        if !lockState.isFrozen || lockState.activePhases.allSatisfy({ $0.sessionID != session.id }) {
                                            Button("Delete", role: .destructive) {
                                                context.delete(session)
                                                try? context.save()
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.top, -8)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Sessions")
            .navigationDestination(for: UUID.self) { id in
                if let session = sessions.first(where: { $0.id == id }) {
                    SessionDetailView(session: session)
                }
            }
            .sheet(isPresented: $showWizard) {
                NavigationStack {
                    SessionWizardView(onSave: { showWizard = false })
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { showWizard = false }
                            }
                        }
                }
                #if os(macOS)
                .frame(minWidth: 560, minHeight: 640)
                #endif
            }
        }
    }

    private func sessionSubtitle(_ session: StudySession) -> String {
        let range = "\(DateFormatters.shortDate.string(from: session.startDate)) – \(DateFormatters.shortDate.string(from: session.endDate))"
        let unlock = session.validationEnabled
            ? "Proof · \(session.milestone?.title ?? "milestone")"
            : "Unlocks by time"
        let list = session.blocklist?.name ?? "No block list"
        return "\(range)\n\(unlock) · \(list)"
    }

    @ViewBuilder
    private func statusBadge(for session: StudySession) -> some View {
        if let phase = lockState.activePhases.first(where: { $0.sessionID == session.id }) {
            switch phase {
            case .activeBlock(_, _, let ends):
                Label("Blocking until \(DateFormatters.shortTime.string(from: ends))", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            case .onBreak(_, _, let until):
                Label("Break until \(DateFormatters.shortTime.string(from: until))", systemImage: "pause.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            case .overrun(_, _, _):
                Label("Overrun — validate to unlock", systemImage: "exclamationmark.lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
            case .idle:
                EmptyView()
            }
        }
    }
}

struct SessionDetailView: View {
    @EnvironmentObject private var lockState: LockState
    @Bindable var session: StudySession

    var body: some View {
        List {
            Section("Title") {
                Text(session.displayTitle)
            }
            Section("When") {
                Text("\(DateFormatters.day.string(from: session.startDate)) \(DateFormatters.shortTime.string(from: session.startDate)) – \(DateFormatters.shortTime.string(from: session.endDate))")
                Text("Hard cap: \(DateFormatters.day.string(from: session.capDate))")
                    .foregroundStyle(.secondary)
            }
            Section("Zone") {
                Text(session.zone?.title ?? "None — block only")
            }
            Section("Unlock") {
                Text(session.validationEnabled ? "Proof of \(session.milestone?.title ?? "milestone")" : "When time ends")
            }
            Section("Block list") {
                Text(session.blocklist?.name ?? "None")
            }
            if let segments = session.segments, !segments.isEmpty {
                Section("Segments") {
                    ForEach(Array(segments.sorted { $0.startDate < $1.startDate }.enumerated()), id: \.element.id) { index, segment in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .frame(width: 40, alignment: .center)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(DateFormatters.shortTime.string(from: segment.startDate)) – \(DateFormatters.shortTime.string(from: segment.endDate))")
                                if !segment.milestoneSubset.isEmpty {
                                    Text(segment.milestoneSubset).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(segment.isValidated ? "Validated" : "Not validated")
                                    .font(.caption2)
                                    .foregroundStyle(segment.isValidated ? .green : .secondary)
                            }
                        }
                    }
                }
            }
            if lockState.activePhases.contains(where: { $0.sessionID == session.id }), session.validationEnabled {
                Section {
                    Button("Validate now") { lockState.openValidation(for: session.id) }
                }
            }
        }
        .navigationTitle(session.displayTitle)
    }
}
