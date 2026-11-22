import SwiftUI

extension Color {
    init(hex: String) {
        var hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

enum ZonePalette {
    static let options: [(name: String, hex: String)] = [
        ("Blue", "#2563EB"),
        ("Indigo", "#4F46E5"),
        ("Teal", "#0D9488"),
        ("Green", "#16A34A"),
        ("Amber", "#D97706"),
        ("Orange", "#EA580C"),
        ("Red", "#DC2626"),
        ("Pink", "#DB2777"),
        ("Purple", "#7C3AED"),
        ("Slate", "#475569")
    ]
}

enum DateFormatters {
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()
}
