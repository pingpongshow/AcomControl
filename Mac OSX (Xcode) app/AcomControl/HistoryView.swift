//
//  HistoryView.swift
//  AcomControl
//
//  Session statistics, time-series charts and CSV export.
//

import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

struct HistoryView: View {
    @EnvironmentObject var controller: AmplifierController
    @Environment(\.dismiss) private var dismiss

    enum Window: String, CaseIterable, Identifiable {
        case oneMinute = "1 min"
        case fiveMinutes = "5 min"
        case fifteenMinutes = "15 min"
        case session = "Session"

        var id: String { rawValue }

        var seconds: TimeInterval {
            switch self {
            case .oneMinute:      return 60
            case .fiveMinutes:    return 300
            case .fifteenMinutes: return 900
            case .session:        return .greatestFiniteMagnitude
            }
        }
    }

    @State private var window: Window = .fiveMinutes
    @State private var isImporting = false
    @State private var isDownloading = false
    @State private var importMessage: String?

    private var samples: [TelemetrySample] {
        window == .session ? controller.history
                           : controller.recentSamples(seconds: window.seconds)
    }

    /// Charting every frame of a long session is pointless and slow; thin to
    /// roughly 600 points by taking every nth sample.
    private var plotted: [TelemetrySample] {
        let target = 600
        guard samples.count > target else { return samples }
        let stride = samples.count / target + 1
        return Swift.stride(from: 0, to: samples.count, by: stride).map { samples[$0] }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if samples.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        statsGrid
                        chart(title: "Forward & Reflected Power", unit: "W") {
                            powerChart
                        }
                        chart(title: "SWR", unit: ":1") {
                            swrChart
                        }
                        chart(title: "PA Temperature & Drain Current", unit: "°C / A") {
                            thermalChart
                        }
                    }
                    .padding(18)
                }
            }

            Divider()
            footer
        }
        .frame(minWidth: 760, idealWidth: 880, minHeight: 560, idealHeight: 680)
    }

    // MARK: Chrome

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Session History")
                    .font(.system(size: 18, weight: .semibold))
                Text("\(controller.history.count) samples since \(controller.stats.startedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $window) {
                ForEach(Window.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)

            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let importMessage {
                Text(importMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                Task { await importDeviceHistory() }
            } label: {
                if isImporting {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Load Controller History", systemImage: "arrow.down.circle")
                }
            }
            .disabled(!controller.connectionState.isConnected || isImporting)
            .help("Fetch telemetry the controller recorded before this app connected")

            Button {
                Task { await downloadDeviceLog() }
            } label: {
                if isDownloading {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Save Controller Log", systemImage: "doc.text")
                }
            }
            .disabled(!controller.connectionState.isConnected || isDownloading)
            .help("Download the CSV log the controller keeps on its own flash")

            Button {
                exportCSV()
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .disabled(samples.isEmpty)
            .keyboardShortcut("e", modifiers: .command)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No telemetry recorded yet")
                .font(.system(size: 14, weight: .medium))
            Text("Connect to a controller, or load the history the controller stored itself.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button("Load Controller History") {
                Task { await importDeviceHistory() }
            }
            .disabled(!controller.connectionState.isConnected)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Statistics

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            StatTile(title: "Peak Power",
                     value: String(format: "%.0f W", controller.stats.peakForwardPower),
                     detail: String(format: "average %.0f W while keyed",
                                    controller.stats.averageTransmitPower),
                     tint: .blue)
            StatTile(title: "Peak SWR",
                     value: String(format: "%.2f:1", controller.stats.peakSWR),
                     detail: String(format: "peak reflected %.0f W",
                                    controller.stats.peakReflectedPower),
                     tint: controller.stats.peakSWR >= 2.5 ? .red : .green)
            StatTile(title: "Peak Temperature",
                     value: String(format: "%.0f °C", controller.stats.peakTemperature),
                     detail: String(format: "peak drain %.1f A", controller.stats.peakCurrent),
                     tint: controller.stats.peakTemperature >= 70 ? .red : .teal)
            StatTile(title: "Transmit Time",
                     value: Format.duration(controller.stats.transmitSeconds),
                     detail: "\(controller.stats.transmissions) transmissions")
            StatTile(title: "Duty Cycle",
                     value: String(format: "%.0f%%", controller.stats.dutyCycle * 100),
                     detail: "of \(Format.duration(controller.stats.totalSeconds)) observed")
            StatTile(title: "Samples",
                     value: "\(controller.history.count)",
                     detail: "\(samples.count) in view")
        }
    }

    // MARK: Charts

    private func chart<Content: View>(title: String, unit: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            content()
                .frame(height: 180)
        }
        .padding(14)
        .background(CardBackground())
    }

    // The marks below style themselves with `foregroundStyle(by:)`, which is
    // what feeds both `chartForegroundStyleScale` and the legend. v2.0 declared
    // the scales but coloured each mark with a literal `foregroundStyle(_:)`,
    // so the scales did nothing and the legends rendered empty.
    private var powerChart: some View {
        Chart {
            ForEach(plotted) { sample in
                AreaMark(x: .value("Time", sample.date),
                         y: .value("Power", sample.forwardPower),
                         series: .value("Series", "Forward"))
                    .foregroundStyle(Color.blue.opacity(0.16))
                LineMark(x: .value("Time", sample.date),
                         y: .value("Power", sample.forwardPower),
                         series: .value("Series", "Forward"))
                    .foregroundStyle(by: .value("Series", "Forward"))
                LineMark(x: .value("Time", sample.date),
                         y: .value("Power", sample.reflectedPower),
                         series: .value("Series", "Reflected"))
                    .foregroundStyle(by: .value("Series", "Reflected"))
            }
        }
        .chartForegroundStyleScale(["Forward": Color.blue, "Reflected": Color.orange])
        .chartYAxisLabel("W")
        .chartLegend(position: .top, alignment: .trailing)
    }

    private var swrChart: some View {
        Chart {
            RuleMark(y: .value("Protection limit", 2.0))
                .foregroundStyle(Color.orange.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("2.0:1 protection threshold")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
            // One series in one colour. v2.0 varied the colour per point on a
            // single series, which Swift Charts resolves to whichever point it
            // drew last rather than a per-segment gradient.
            ForEach(plotted) { sample in
                LineMark(x: .value("Time", sample.date),
                         y: .value("SWR", sample.swr))
            }
            .foregroundStyle(controller.stats.peakSWR >= 2.5 ? Color.red : Color.green)
        }
        .chartYScale(domain: 1...max(3.0, controller.stats.peakSWR + 0.2))
        .chartYAxisLabel(":1")
    }

    private var thermalChart: some View {
        Chart {
            ForEach(plotted) { sample in
                LineMark(x: .value("Time", sample.date),
                         y: .value("Value", sample.temperature),
                         series: .value("Series", "Temperature °C"))
                    .foregroundStyle(by: .value("Series", "Temperature °C"))
                LineMark(x: .value("Time", sample.date),
                         // Scaled onto the temperature axis so both fit one plot.
                         y: .value("Value", sample.current * 2),
                         series: .value("Series", "Drain current ×2 (A)"))
                    .foregroundStyle(by: .value("Series", "Drain current ×2 (A)"))
            }
        }
        .chartForegroundStyleScale(["Temperature °C": Color.teal,
                                    "Drain current ×2 (A)": Color.purple])
        .chartLegend(position: .top, alignment: .trailing)
    }

    // MARK: Actions

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "acomcontrol-\(Self.filenameStamp()).csv"
        panel.canCreateDirectories = true
        panel.title = "Export Session Telemetry"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try samples.csvRepresentation().write(to: url, atomically: true, encoding: .utf8)
            importMessage = "Exported \(samples.count) samples"
        } catch {
            importMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Pulls the controller's own telemetry buffer into the session history.
    ///
    /// v2.0 fetched it and discarded it — the count was reported and the
    /// samples went nowhere, so the button did nothing but print a number.
    private func importDeviceHistory() async {
        isImporting = true
        defer { isImporting = false }
        do {
            let added = try await controller.importDeviceHistory()
            if added == 0 {
                importMessage = "Nothing new — the controller's buffer is already covered"
            } else {
                importMessage = "Added \(added) samples recorded by the controller"
            }
        } catch {
            importMessage = "Could not load history: \(error.localizedDescription)"
        }
    }

    /// Saves the controller's CSV session log. Fetched through the app's own
    /// session so it still works once the controller has a password, which
    /// handing the URL to a browser would not.
    private func downloadDeviceLog() async {
        isDownloading = true
        defer { isDownloading = false }
        do {
            let data = try await controller.downloadDeviceLog()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "acomcontrol-controller-\(Self.filenameStamp()).csv"
            panel.canCreateDirectories = true
            panel.title = "Save Controller Session Log"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url)
            importMessage = "Saved \(Format.bytes(data.count)) of controller log"
        } catch {
            importMessage = "Could not download the log: \(error.localizedDescription)"
        }
    }

    private static func filenameStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }
}

#Preview {
    HistoryView()
        .environmentObject(AmplifierController())
        .environmentObject(AppRouter())
}
