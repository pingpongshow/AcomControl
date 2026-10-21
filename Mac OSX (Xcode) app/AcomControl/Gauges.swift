//
//  Gauges.swift
//  AcomControl
//
//  Arc gauges with peak-hold needles and sparklines — the instrument idiom
//  operators already know from the amplifier's own front panel.
//

import SwiftUI

// MARK: - Arc gauge

/// A 180° arc gauge with a coloured danger zone and a peak-hold needle.
struct ArcGauge: View {
    let title: String
    let value: Double
    let unit: String
    let range: ClosedRange<Double>
    let icon: String

    var peak: Double? = nil
    var warningThreshold: Double? = nil
    var dangerThreshold: Double? = nil
    var decimals: Int = 0
    var tint: Color = .accentColor
    /// Extra caption under the readout, e.g. "avg 380 W".
    var caption: String? = nil

    private var span: Double { max(range.upperBound - range.lowerBound, .ulpOfOne) }

    /// Normalised 0...1 position, clamped. Values below the range floor must
    /// clamp to 0 rather than produce a negative width.
    private func fraction(_ v: Double) -> Double {
        min(max((v - range.lowerBound) / span, 0), 1)
    }

    private var valueColor: Color {
        if let danger = dangerThreshold, value >= danger { return .red }
        if let warning = warningThreshold, value >= warning { return .orange }
        return tint
    }

    private var accessibilityValue: String {
        let formatted = String(format: "%.\(decimals)f", value)
        var text = "\(formatted) \(unit.isEmpty ? "" : unit)"
        if let danger = dangerThreshold, value >= danger {
            text += ", above the danger threshold"
        } else if let warning = warningThreshold, value >= warning {
            text += ", above the warning threshold"
        }
        return text
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(valueColor)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ZStack {
                GaugeArcShape()
                    .stroke(Color.primary.opacity(0.09),
                            style: StrokeStyle(lineWidth: 13, lineCap: .round))

                if let warning = warningThreshold {
                    GaugeArcShape(from: fraction(warning), to: fraction(dangerThreshold ?? range.upperBound))
                        .stroke(Color.orange.opacity(0.22), style: StrokeStyle(lineWidth: 13))
                }
                if let danger = dangerThreshold {
                    GaugeArcShape(from: fraction(danger), to: 1)
                        .stroke(Color.red.opacity(0.28), style: StrokeStyle(lineWidth: 13))
                }

                GaugeArcShape(from: 0, to: fraction(value))
                    .stroke(valueColor, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                    .animation(.easeOut(duration: 0.18), value: value)

                if let peak {
                    PeakNeedle(fraction: fraction(peak))
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .animation(.easeOut(duration: 0.25), value: peak)
                }

                VStack(spacing: 0) {
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.\(decimals)f", value))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(valueColor)
                        if !unit.isEmpty {
                            Text(unit)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let caption {
                        Text(caption)
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.bottom, 2)
            }
            .frame(height: 96)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityValue)
        }
        .padding(14)
        .background(CardBackground())
    }
}

/// The 180° sweep, drawn from the left horizontal round to the right.
private struct GaugeArcShape: Shape {
    var from: Double = 0
    var to: Double = 1

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width / 2, rect.height) - 8
        let center = CGPoint(x: rect.midX, y: rect.maxY - 4)
        var path = Path()
        guard radius > 0, to > from else { return path }
        path.addArc(center: center,
                    radius: radius,
                    startAngle: .degrees(180 + 180 * from),
                    endAngle: .degrees(180 + 180 * to),
                    clockwise: false)
        return path
    }
}

/// A short radial tick marking the highest value seen this session.
private struct PeakNeedle: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width / 2, rect.height) - 8
        let center = CGPoint(x: rect.midX, y: rect.maxY - 4)
        guard radius > 0 else { return Path() }

        let angle = Angle.degrees(180 + 180 * min(max(fraction, 0), 1)).radians
        let dx = CGFloat(Foundation.cos(angle))
        let dy = CGFloat(Foundation.sin(angle))
        let inner = radius - 9
        let outer = radius + 8

        var path = Path()
        path.move(to: CGPoint(x: center.x + dx * inner, y: center.y + dy * inner))
        path.addLine(to: CGPoint(x: center.x + dx * outer, y: center.y + dy * outer))
        return path
    }
}

// MARK: - Sparkline

/// A compact trace of the recent past, drawn from newest-last samples.
struct Sparkline: View {
    let values: [Double]
    let range: ClosedRange<Double>
    var tint: Color = .accentColor
    var fill: Bool = true

    var body: some View {
        GeometryReader { geo in
            let span = max(range.upperBound - range.lowerBound, .ulpOfOne)
            let points = normalisedPoints(in: geo.size, span: span)

            ZStack {
                if fill, points.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        points.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: points[points.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                }
                if points.count > 1 {
                    Path { p in
                        p.move(to: points[0])
                        points.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5,
                                                     lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func normalisedPoints(in size: CGSize, span: Double) -> [CGPoint] {
        guard values.count > 1, size.width > 0, size.height > 0 else { return [] }
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let clamped = min(max((value - range.lowerBound) / span, 0), 1)
            return CGPoint(x: CGFloat(index) * step,
                           y: size.height - CGFloat(clamped) * size.height)
        }
    }
}

// MARK: - Shared chrome

/// The rounded panel used by every card, adaptive to light and dark.
struct CardBackground: View {
    var tint: Color? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(tint ?? Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

/// A labelled readout used across the telemetry grid.
struct TelemetryTile: View {
    let title: String
    let value: String
    let icon: String
    var tint: Color = .primary
    var emphasised: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 14, weight: emphasised ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

/// A statistic in the session summary.
struct StatTile: View {
    let title: String
    let value: String
    var detail: String? = nil
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            if let detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(CardBackground())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(detail.map { "\(value), \($0)" } ?? value)
    }
}

// MARK: - Formatting helpers

enum Format {
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    static func uptime(milliseconds: Int) -> String {
        duration(Double(milliseconds) / 1000.0)
    }

    static func bytes(_ count: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(count))
    }
}
