import SwiftUI
import SwiftData

struct ZonesView: View {
    @EnvironmentObject private var lockState: LockState
    @Environment(\.modelContext) private var context
    @Query(sort: \Zone.title) private var zones: [Zone]
    @State private var path = NavigationPath()
    @State private var showNew = false

    private var zoneCardHeight: CGFloat {
        #if os(macOS)
        260
        #else
        220
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                EntityCardGrid(
                    minimumWidth: {
                        #if os(macOS)
                        280
                        #else
                        200
                        #endif
                    }(),
                    maximumWidth: {
                        #if os(macOS)
                        380
                        #else
                        280
                        #endif
                    }()
                ) {
                    ForEach(zones, id: \.id) { zone in
                        ZoneCard(
                            zone: zone,
                            milestones: nearestMilestones(for: zone),
                            detail: milestoneDetail,
                            minHeight: zoneCardHeight
                        ) {
                            path.append(zone.id)
                        }
                        .contextMenu {
                            if !lockState.isFrozen {
                                Button("Delete", role: .destructive) {
                                    context.delete(zone)
                                    try? context.save()
                                }
                            }
                        }
                    }

                    AddEntityCard(title: "Add new Zone", minHeight: zoneCardHeight) {
                        showNew = true
                    }
                }
            }
            .navigationTitle("Zones")
            .navigationDestination(for: UUID.self) { id in
                if let zone = zones.first(where: { $0.id == id }) {
                    ZoneEditorView(zone: zone)
                }
            }
            .sheet(isPresented: $showNew) {
                NavigationStack {
                    ZoneEditorView(zone: nil, onDone: { showNew = false })
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { showNew = false }
                            }
                        }
                }
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 520)
                #endif
            }
        }
    }

    /// Upcoming by scheduled start first, then past.
    private func nearestMilestones(for zone: Zone) -> [Milestone] {
        let now = Date()
        return (zone.milestones ?? []).sorted { lhs, rhs in
            let left = proximity(for: lhs, now: now)
            let right = proximity(for: rhs, now: now)
            if left.rank != right.rank { return left.rank < right.rank }
            if left.date != right.date { return left.date < right.date }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func proximity(for milestone: Milestone, now: Date) -> (rank: Int, date: Date) {
        if milestone.startDate >= now {
            return (0, milestone.startDate)
        }
        return (1, milestone.startDate)
    }

    private func milestoneDetail(_ milestone: Milestone) -> String? {
        let dateText = DateFormatters.shortDate.string(from: milestone.startDate)
        let kind = milestone.kind.title
        return "\(kind) · \(dateText)"
    }
}

private struct ZoneCard: View {
    var zone: Zone
    var milestones: [Milestone]
    var detail: (Milestone) -> String?
    var minHeight: CGFloat
    var onOpen: () -> Void

    private var accent: Color { Color(hex: zone.colorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(zone.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(zone.isClass ? "Class" : "Zone")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text("Milestones")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if milestones.isEmpty {
                            Text("No milestones yet")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(milestones, id: \.id) { milestone in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Circle()
                                        .fill(accent)
                                        .frame(width: 6, height: 6)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(milestone.title)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        if let detail = detail(milestone) {
                                            Text(detail)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 128)
                .padding(8)
                .background(
                    Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent, lineWidth: 2.5)
        )
    }
}
