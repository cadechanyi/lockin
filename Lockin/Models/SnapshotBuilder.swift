import Foundation
import SwiftData

enum SnapshotBuilder {
    static func build(sessions: [StudySession]) -> ScheduleSnapshot {
        let snaps: [SessionSnapshot] = sessions.compactMap { session in
            guard let blocklist = session.blocklist else { return nil }
            var segments = (session.segments ?? []).map {
                SegmentSnapshot(
                    id: $0.id,
                    start: $0.startDate,
                    end: $0.endDate,
                    milestoneSubset: $0.milestoneSubset,
                    validated: $0.validatedAt != nil
                )
            }
            if segments.isEmpty {
                segments = [
                    SegmentSnapshot(
                        id: session.id,
                        start: session.startDate,
                        end: session.endDate,
                        milestoneSubset: session.milestone?.scope ?? "",
                        validated: false
                    )
                ]
            }
            let breaks = (session.breaks ?? []).map {
                BreakSnapshot(
                    id: $0.id,
                    kind: $0.kindRaw,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    durationMinutes: $0.durationMinutes,
                    intervalMinutes: $0.intervalMinutes,
                    offsetMinutes: $0.offsetMinutes,
                    segmentID: $0.segmentID
                )
            }
            return SessionSnapshot(
                id: session.id,
                zoneTitle: session.zone?.title ?? "Focus",
                zoneColorHex: session.zone?.colorHex ?? "#64748B",
                start: session.startDate,
                end: session.endDate,
                validationEnabled: session.validationEnabled,
                milestoneTitle: session.milestone?.title ?? "",
                blocklistName: blocklist.name,
                xboxGamertag: blocklist.xboxGamertag,
                xboxEnabled: blocklist.xboxEnabled,
                macBundleIDs: blocklist.macBundleIDs,
                familyActivitySelectionData: blocklist.familyActivitySelectionData,
                segments: segments,
                breaks: breaks,
                capDate: session.capDate
            )
        }
        return ScheduleSnapshot(sessions: snaps, updatedAt: Date())
    }
}
