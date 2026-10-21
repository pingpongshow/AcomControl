//
//  MenuBarView.swift
//  AcomControl
//
//  Amplifier status in the menu bar, so TX state, SWR and temperature stay
//  visible without keeping the main window in front.
//

import SwiftUI

/// The compact label drawn in the menu bar itself.
struct MenuBarLabel: View {
    @EnvironmentObject var controller: AmplifierController

    private var state: AmplifierState { controller.amplifierState }

    private var symbol: String {
        guard controller.connectionState.isConnected else { return "wave.3.right" }
        if state.hasFault { return "exclamationmark.triangle.fill" }
        return state.isTx ? "dot.radiowaves.left.and.right" : "wave.3.right"
    }

    private var summary: String? {
        guard controller.connectionState.isConnected, state.connected else { return nil }
        if state.isTx {
            return String(format: "%.0fW %.1f:1", state.forwardPower, state.swr)
        }
        if state.temperature >= 60 {
            return String(format: "%.0f°", state.temperature)
        }
        return state.band == "---" ? nil : state.band
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            if let summary {
                Text(summary)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
        }
    }
}

/// The dropdown contents.
struct MenuBarContent: View {
    @EnvironmentObject var controller: AmplifierController

    private var state: AmplifierState { controller.amplifierState }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if controller.connectionState.isConnected {
                Divider()
                readouts
                Divider()
                controls
            } else {
                Divider()
                Text("Not connected to a controller.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if !controller.connectedHost.isEmpty {
                    Button("Reconnect to \(controller.connectedHost)") { controller.retry() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }

            Divider()

            HStack {
                Button("Open AcomControl") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
                }
                .controlSize(.small)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(controller.connectionState.color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(controller.connectionState.label)
                    .font(.system(size: 12, weight: .semibold))
                if controller.connectionState.isConnected {
                    Text(state.connected ? "Amplifier online" : "No amplifier on the serial link")
                        .font(.system(size: 10))
                        .foregroundStyle(state.connected ? Color.secondary : Color.orange)
                }
            }
            Spacer()
        }
    }

    private var readouts: some View {
        VStack(spacing: 6) {
            HStack {
                Text(state.isTx ? "TRANSMITTING" : "RECEIVE")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(state.isTx ? .red : .secondary)
                Spacer()
                Text(state.band)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)
            }

            row("Forward", String(format: "%.0f W", state.forwardPower))
            row("SWR", String(format: "%.2f:1", state.swr),
                tint: state.swr >= 2.5 ? .red : (state.swr >= 2.0 ? .orange : .primary))
            row("Temperature", String(format: "%.0f °C", state.temperature),
                tint: state.temperature >= 70 ? .red : (state.temperature >= 60 ? .orange : .primary))
            row("Frequency", state.frequencyDisplay)

            if state.hasFault {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("\(state.faults.count) active fault\(state.faults.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                    Spacer()
                }
            }
        }
    }

    private func row(_ title: String, _ value: String, tint: Color = .primary) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button("Standby") { controller.setMode(.standby) }
                .controlSize(.small)
            Button("Operate") { controller.setMode(.operate) }
                .controlSize(.small)
            Spacer()
            if state.hasFault {
                Button("Clear") { controller.clearErrors() }
                    .controlSize(.small)
            }
        }
    }
}
