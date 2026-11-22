import SwiftUI

struct DashboardCard: View {
    var title: String
    var sessions: [StudySession]
    var attempts: [ValidationAttempt]
    var xboxLogs: [XboxPresenceLog]
    var breakLogs: [BreakUsageLog]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            HStack(spacing: 12) {
                stat("Sessions", "\(sessions.count)")
                stat("Passed", "\(attempts.filter(\.passed).count)")
                stat("Failed", "\(attempts.filter { !$0.passed }.count)")
            }
            HStack(spacing: 12) {
                stat("Xbox pings", "\(xboxLogs.filter(\.isPlaying).count)")
                stat("Breaks", "\(breakLogs.count)")
                stat("Xbox min", "\(xboxMinutes)")
            }
            Text("Time-waster minutes only count outside active shields (breaks and gaps). Xbox is nudge-only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private var xboxMinutes: Int {
        // Presence is sampled; treat consecutive playing logs ~15 min apart as 15 minutes each.
        max(0, xboxLogs.filter(\.isPlaying).count * 10)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.weight(.bold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
