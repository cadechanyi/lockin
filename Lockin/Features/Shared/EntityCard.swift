import SwiftUI

/// Shared large rounded entity card used by Zones, Blocklists, and Sessions.
struct EntityCard<Accessory: View>: View {
    var title: String
    var subtitle: String? = nil
    var borderColor: Color
    var fill: Color = Color.secondary.opacity(0.06)
    var minHeight: CGFloat = 110
    @ViewBuilder var accessory: () -> Accessory

    init(
        title: String,
        subtitle: String? = nil,
        borderColor: Color,
        fill: Color = Color.secondary.opacity(0.06),
        minHeight: CGFloat = 110,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.borderColor = borderColor
        self.fill = fill
        self.minHeight = minHeight
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            accessory()
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 2.5)
        )
    }
}

struct AddEntityCard: View {
    var title: String
    var borderColor: Color = Color.accentColor.opacity(0.55)
    var minHeight: CGFloat = 110
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.title.weight(.semibold))
                Text(title)
                    .font(.headline)
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(borderColor, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            )
        }
        .buttonStyle(.plain)
    }
}

struct EntityCardGrid<Content: View>: View {
    var minimumWidth: CGFloat? = nil
    var maximumWidth: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    private var columns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: minimumWidth ?? 220, maximum: maximumWidth ?? 320), spacing: 16)]
        #else
        [GridItem(.adaptive(minimum: minimumWidth ?? 160, maximum: maximumWidth ?? 220), spacing: 12)]
        #endif
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            content()
        }
        .padding()
    }
}
