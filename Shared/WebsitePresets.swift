import Foundation

enum WebsitePreset: String, CaseIterable, Identifiable, Codable {
    case youtube
    case instagram
    case tiktok
    case twitter
    case reddit
    case facebook
    case snapchat
    case netflix
    case twitch
    case discord

    var id: String { rawValue }

    var title: String {
        switch self {
        case .youtube: return "YouTube"
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .twitter: return "X / Twitter"
        case .reddit: return "Reddit"
        case .facebook: return "Facebook"
        case .snapchat: return "Snapchat"
        case .netflix: return "Netflix"
        case .twitch: return "Twitch"
        case .discord: return "Discord"
        }
    }

    var domains: [String] {
        switch self {
        case .youtube: return ["youtube.com", "youtu.be", "m.youtube.com"]
        case .instagram: return ["instagram.com"]
        case .tiktok: return ["tiktok.com"]
        case .twitter: return ["twitter.com", "x.com"]
        case .reddit: return ["reddit.com"]
        case .facebook: return ["facebook.com", "fb.com"]
        case .snapchat: return ["snapchat.com"]
        case .netflix: return ["netflix.com"]
        case .twitch: return ["twitch.tv"]
        case .discord: return ["discord.com"]
        }
    }
}
