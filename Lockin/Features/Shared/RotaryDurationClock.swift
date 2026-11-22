import SwiftUI

/// Clock-style duration dial. Counterclockwise drag increases time;
/// one full turn from 12 o'clock = 60 minutes; values snap to 5-minute steps.
struct RotaryDurationClock: View {
    @Binding var minutes: Int
    var minimumMinutes: Int = 5
    var maximumMinutes: Int = 14 * 24 * 60
    var size: CGFloat = 200

    @State private var baseMinutes = 0
    @State private var lastAngle: Double?
    @State private var cumulativeTurns = 0.0
    @State private var liveMinutes: Int?

    private let tickStep = 5
    private let minutesPerTurn = 60.0

    private var displayMinutes: Int {
        liveMinutes ?? snapped(minutes)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(formatted(displayMinutes))
                .font(.title2.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())

            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.08))
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 2)

                ForEach(0..<12, id: \.self) { i in
                    Capsule()
                        .fill(Color.secondary.opacity(i % 3 == 0 ? 0.55 : 0.3))
                        .frame(width: i % 3 == 0 ? 3 : 2, height: i % 3 == 0 ? 14 : 8)
                        .offset(y: -(size / 2 - 16))
                        .rotationEffect(.degrees(Double(i) / 12 * 360))
                }

                Circle()
                    .trim(from: 0, to: faceFraction(displayMinutes))
                    .stroke(
                        Color.accentColor.opacity(0.85),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(x: -1, y: 1)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 4, height: size * 0.34)
                    .offset(y: -size * 0.17)
                    .rotationEffect(handAngle(displayMinutes))

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 12, height: 12)

                Text("turn CCW")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .offset(y: size * 0.3)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(dragGesture)
            .accessibilityLabel("Duration dial")
            .accessibilityValue(formatted(displayMinutes))
            .accessibilityAdjustableAction { direction in
                commit(displayMinutes + (direction == .increment ? tickStep : -tickStep))
            }
        }
        .onAppear {
            // Snap display only; avoid writing back through the binding before parent state has loaded.
            let current = minutes
            let snappedValue = snapped(current)
            if snappedValue != current {
                minutes = snappedValue
            }
        }
        .onChange(of: minutes) { _, newValue in
            let snappedValue = snapped(newValue)
            if snappedValue != newValue { minutes = snappedValue }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let angle = clockAngle(from: value.location)
                if lastAngle == nil {
                    baseMinutes = displayMinutes
                    lastAngle = angle
                    cumulativeTurns = 0
                    liveMinutes = displayMinutes
                    return
                }
                guard let previous = lastAngle else { return }

                var delta = angle - previous
                if delta > .pi { delta -= 2 * .pi }
                if delta < -.pi { delta += 2 * .pi }

                // Angle increases clockwise; CCW (negative delta) adds time.
                cumulativeTurns += -delta / (2 * .pi)
                lastAngle = angle
                let proposed = Double(baseMinutes) + cumulativeTurns * minutesPerTurn
                liveMinutes = snapped(Int(proposed.rounded()))
            }
            .onEnded { _ in
                if let live = liveMinutes {
                    commit(live)
                }
                lastAngle = nil
                cumulativeTurns = 0
                liveMinutes = nil
            }
    }

    /// 0 at top, increasing clockwise (radians).
    private func clockAngle(from point: CGPoint) -> Double {
        let dx = point.x - size / 2
        let dy = point.y - size / 2
        return atan2(dx, -dy)
    }

    private func handAngle(_ minutes: Int) -> Angle {
        let faceMinutes = Double(((minutes % 60) + 60) % 60)
        return .degrees(-(faceMinutes / 60.0) * 360.0)
    }

    private func faceFraction(_ minutes: Int) -> CGFloat {
        CGFloat(Double(((minutes % 60) + 60) % 60) / 60.0)
    }

    private func snapped(_ value: Int) -> Int {
        let stepped = Int((Double(value) / Double(tickStep)).rounded()) * tickStep
        return min(maximumMinutes, max(minimumMinutes, stepped))
    }

    private func commit(_ value: Int) {
        minutes = snapped(value)
    }

    private func formatted(_ total: Int) -> String {
        let hours = total / 60
        let mins = total % 60
        if hours == 0 { return "\(mins) min" }
        if mins == 0 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        return "\(hours)h \(mins)m"
    }
}

extension RotaryDurationClock {
    /// Binds duration so `end = start + minutes`.
    static func binding(
        start: Binding<Date>,
        end: Binding<Date>,
        minimumMinutes: Int = 5,
        maximumMinutes: Int = 14 * 24 * 60
    ) -> Binding<Int> {
        Binding(
            get: {
                let raw = max(0, Int((end.wrappedValue.timeIntervalSince(start.wrappedValue) / 60).rounded()))
                let stepped = Int((Double(raw) / 5.0).rounded()) * 5
                return min(maximumMinutes, max(minimumMinutes, max(stepped, minimumMinutes)))
            },
            set: { newMinutes in
                end.wrappedValue = start.wrappedValue.addingTimeInterval(TimeInterval(newMinutes * 60))
            }
        )
    }
}

/// Starts / Ends + presets on the left, rotary clock on the right (one horizontal bar).
struct DurationScheduleRow: View {
    @Binding var start: Date
    @Binding var end: Date
    var includeDate: Bool = true
    var maximumMinutes: Int = 14 * 24 * 60
    var clockSize: CGFloat = 168

    private var selectedPreset: Int? {
        let minutes = Int((end.timeIntervalSince(start) / 60).rounded())
        return [30, 60, 120, 300, 720].contains(minutes) ? minutes : nil
    }

    private var displayedComponents: DatePickerComponents {
        includeDate ? [.date, .hourAndMinute] : [.hourAndMinute]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                timeRow(title: "Starts", selection: $start)
                timeRow(title: "Ends", selection: $end)
                DurationPresetStack(selectedMinutes: selectedPreset) { minutes in
                    end = start.addingTimeInterval(TimeInterval(minutes * 60))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RotaryDurationClock(
                minutes: RotaryDurationClock.binding(
                    start: $start,
                    end: $end,
                    maximumMinutes: maximumMinutes
                ),
                maximumMinutes: maximumMinutes,
                size: clockSize
            )
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
    }

    private func timeRow(title: String, selection: Binding<Date>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            DatePicker("", selection: selection, displayedComponents: displayedComponents)
                .labelsHidden()
                #if os(macOS)
                .datePickerStyle(.field)
                .controlSize(.small)
                #else
                .datePickerStyle(.compact)
                #endif
            Spacer(minLength: 0)
        }
    }
}

struct DurationPresetStack: View {
    var selectedMinutes: Int?
    var onSelect: (Int) -> Void

    private let row1: [(label: String, minutes: Int)] = [
        ("30 min", 30),
        ("1 hour", 60),
        ("2 hours", 120),
    ]
    private let row2: [(label: String, minutes: Int)] = [
        ("5 hours", 300),
        ("12 hours", 720),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            presetRow(row1)
            presetRow(row2)
        }
    }

    private func presetRow(_ presets: [(label: String, minutes: Int)]) -> some View {
        HStack(spacing: 6) {
            ForEach(presets, id: \.minutes) { preset in
                let selected = selectedMinutes == preset.minutes
                Button {
                    onSelect(preset.minutes)
                } label: {
                    Text(preset.label)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? Color.accentColor : Color.secondary.opacity(0.12))
                        )
                        .foregroundStyle(selected ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
