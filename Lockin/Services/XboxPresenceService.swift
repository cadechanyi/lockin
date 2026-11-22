import Foundation
import SwiftData

struct XboxPresence: Equatable {
    var gamertag: String
    var isPlaying: Bool
    var state: String
    var titleName: String
}

actor XboxPresenceService {
    private var lastPlayingSince: Date?
    private var lastNudge: Date = .distantPast

    func poll(gamertag: String, apiKey: String, nudgeMinutes: Int, sessionID: UUID?) async -> XboxPresence? {
        let presence: XboxPresence
        if apiKey.isEmpty {
            presence = XboxPresence(gamertag: gamertag, isPlaying: false, state: "no API key", titleName: "")
        } else {
            presence = (try? await fetchOpenXBL(gamertag: gamertag, apiKey: apiKey))
                ?? XboxPresence(gamertag: gamertag, isPlaying: false, state: "lookup failed", titleName: "")
        }

        if presence.isPlaying {
            if lastPlayingSince == nil { lastPlayingSince = Date() }
            let elapsed = Date().timeIntervalSince(lastPlayingSince ?? Date())
            let minutes = Int(elapsed / 60)
            let interval = TimeInterval(max(5, nudgeMinutes) * 60)
            if Date().timeIntervalSince(lastNudge) >= interval {
                lastNudge = Date()
                await MainActor.run {
                    NotificationService.xboxNudge(
                        gamertag: presence.gamertag,
                        titleName: presence.titleName,
                        minutes: max(nudgeMinutes, minutes)
                    )
                }
            }
        } else {
            lastPlayingSince = nil
        }
        return presence
    }

    @MainActor
    static func logPresence(_ presence: XboxPresence, sessionID: UUID?, context: ModelContext) {
        let log = XboxPresenceLog()
        log.gamertag = presence.gamertag
        log.isPlaying = presence.isPlaying
        log.titleName = presence.titleName
        log.sessionID = sessionID
        context.insert(log)
        try? context.save()
    }

    private func fetchOpenXBL(gamertag: String, apiKey: String) async throws -> XboxPresence {
        let encoded = gamertag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? gamertag
        guard let searchURL = URL(string: "https://xbl.io/api/v2/search/\(encoded)") else {
            throw URLError(.badURL)
        }
        var search = URLRequest(url: searchURL)
        search.addValue(apiKey, forHTTPHeaderField: "X-Authorization")
        search.addValue("application/json", forHTTPHeaderField: "Accept")
        let (searchData, _) = try await URLSession.shared.data(for: search)
        let xuid = extractXUID(from: searchData) ?? encoded

        guard let presenceURL = URL(string: "https://xbl.io/api/v2/presence") else {
            throw URLError(.badURL)
        }
        var presenceReq = URLRequest(url: presenceURL)
        presenceReq.httpMethod = "POST"
        presenceReq.addValue(apiKey, forHTTPHeaderField: "X-Authorization")
        presenceReq.addValue("application/json", forHTTPHeaderField: "Content-Type")
        presenceReq.httpBody = try JSONSerialization.data(withJSONObject: ["xuids": [xuid]])
        let (data, _) = try await URLSession.shared.data(for: presenceReq)
        return parsePresence(data: data, gamertag: gamertag)
    }

    private func extractXUID(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let dict = obj as? [String: Any] {
            if let people = dict["people"] as? [[String: Any]], let first = people.first {
                return (first["xuid"] as? String) ?? (first["id"] as? String)
            }
            if let items = dict["results"] as? [[String: Any]], let first = items.first {
                return first["xuid"] as? String
            }
        }
        if let arr = obj as? [[String: Any]], let first = arr.first {
            return first["xuid"] as? String
        }
        return nil
    }

    private func parsePresence(data: Data, gamertag: String) -> XboxPresence {
        guard let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              let first = arr.first else {
            return XboxPresence(gamertag: gamertag, isPlaying: false, state: "offline", titleName: "")
        }
        let state = (first["state"] as? String ?? "").lowercased()
        var titleName = ""
        if let devices = first["devices"] as? [[String: Any]] {
            for device in devices {
                if let titles = device["titles"] as? [[String: Any]],
                   let playing = titles.first(where: { ($0["placement"] as? String)?.lowercased() == "full" })
                    ?? titles.first {
                    titleName = playing["name"] as? String ?? ""
                }
            }
        }
        let playing = state == "online" || !titleName.isEmpty
        return XboxPresence(gamertag: gamertag, isPlaying: playing, state: state, titleName: titleName)
    }
}
