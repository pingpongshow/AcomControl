//
//  ContentView.swift
//  AcomControl
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var controller: AmplifierController
    @EnvironmentObject var router: AppRouter

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    ConnectionBanner()
                    SecurityBanner()
                    TransmitBanner()
                    PrimaryGaugesView()
                    ControlPanelView()

                    if controller.amplifierState.hasFault {
                        FaultPanelView()
                    }

                    TelemetryGridView()
                    SessionSummaryView()
                }
                .padding(20)
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $router.showDiscovery) { DiscoveryView() }
        .sheet(isPresented: $router.showHistory) { HistoryView() }
        .sheet(isPresented: $router.showSettings) { SettingsView(isSheet: true) }
        .sheet(isPresented: $controller.needsCredentials) { CredentialPrompt() }
        .alert("Command Failed",
               isPresented: Binding(get: { controller.lastCommandError != nil },
                                    set: { if !$0 { controller.lastCommandError = nil } })) {
            Button("OK", role: .cancel) { controller.lastCommandError = nil }
        } message: {
            Text(controller.lastCommandError ?? "")
        }
    }
}

/// Asks for the controller's password when it answers 401.
struct CredentialPrompt: View {
    @EnvironmentObject var controller: AmplifierController
    @Environment(\.dismiss) private var dismiss

    @State private var user = "acom"
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Password Required")
                .font(.system(size: 16, weight: .semibold))
            Text("The controller at \(controller.connectedHost) is password protected. "
                 + "The password is stored in your login keychain.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("User", text: $user)
            SecureField("Password", text: $password)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Connect") {
                    controller.setCredentials(user: user, password: password)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 360)
        .onAppear { user = controller.storedCredentials?.user ?? "acom" }
    }
}

/// Says out loud when the controller has no password set. A 600 W amplifier
/// reachable by anything on the network is worth one line of warning.
struct SecurityBanner: View {
    @EnvironmentObject var controller: AmplifierController
    @EnvironmentObject var router: AppRouter

    var body: some View {
        if let info = controller.systemInfo, !info.authEnabled || info.apOpen {
            HStack(spacing: 12) {
                Image(systemName: "lock.open.trianglebadge.exclamationmark")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("This controller is unprotected")
                        .font(.system(size: 13, weight: .semibold))
                    Text(reason(info))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Settings") { router.openSettings(.controller) }
            }
            .padding(14)
            .background(CardBackground(tint: Color.orange.opacity(0.10)))
            .accessibilityElement(children: .combine)
        }
    }

    private func reason(_ info: SystemInfo) -> String {
        var parts: [String] = []
        if !info.authEnabled { parts.append("it has no API password") }
        if info.apOpen { parts.append("its setup access point is open") }
        return "Anyone who can reach it can change bands or flash firmware, because "
            + parts.joined(separator: " and ") + "."
    }
}

// MARK: - Header

struct HeaderView: View {
    @EnvironmentObject var controller: AmplifierController
    @EnvironmentObject var router: AppRouter

    private var serialText: String {
        let sn = controller.amplifierState.serialNumber
        return (sn.isEmpty || sn == "Unknown") ? "ACOM 600S" : "ACOM 600S · S/N \(sn)"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("AcomControl")
                    .font(.system(size: 17, weight: .semibold))
                Text(serialText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ConnectionStatusPill()

            // The main window now offers connect/disconnect directly instead of
            // hiding it inside Settings.
            if controller.connectionState.isConnected {
                Button {
                    controller.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "bolt.slash")
                }
                .help("Disconnect from the controller (⌘D)")
            } else {
                Button {
                    router.showDiscovery = true
                } label: {
                    Label("Connect", systemImage: "network")
                }
                .help("Find a controller on the network (⌘K)")
            }

            Button {
                router.showHistory = true
            } label: {
                Image(systemName: "chart.xyaxis.line")
            }
            .help("Session history and statistics (⌘H)")
            .accessibilityLabel("Session history")

            Button {
                router.openSettings(.connection)
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct ConnectionStatusPill: View {
    @EnvironmentObject var controller: AmplifierController

    private var ampOnline: Bool { controller.amplifierState.connected }

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(controller.connectionState.color)
                .frame(width: 8, height: 8)

            Text(controller.connectionState.label)
                .font(.system(size: 12, weight: .medium))

            if controller.connectionState.isConnected {
                Text(controller.connectedHost)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                // Reaching the controller and reaching the amplifier are two
                // different things; the previous UI conflated them.
                Text(ampOnline ? "· amp online" : "· no amp")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ampOnline ? .green : .orange)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(controller.connectionState.color.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection status")
        .accessibilityValue(controller.connectionState.label +
                            (controller.connectionState.isConnected
                             ? (ampOnline ? ", amplifier online" : ", amplifier not responding") : ""))
    }
}

// MARK: - Banners

/// Surfaces a failed connection with a way out. Previously the controller gave
/// up silently after ten attempts and said so only in the debug log.
struct ConnectionBanner: View {
    @EnvironmentObject var controller: AmplifierController

    var body: some View {
        if case .failed(let reason) = controller.connectionState {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cannot reach the controller")
                        .font(.system(size: 13, weight: .semibold))
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Retry") { controller.retry() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(14)
            .background(CardBackground(tint: Color.red.opacity(0.10)))
            .accessibilityElement(children: .combine)
        }
    }
}

/// Transmit state deserves the whole width — it was one small tile among eight.
struct TransmitBanner: View {
    @EnvironmentObject var controller: AmplifierController

    private var isTx: Bool { controller.amplifierState.isTx }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isTx ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                .font(.system(size: 15, weight: .bold))
            Text(isTx ? "TRANSMITTING" : "RECEIVE")
                .font(.system(size: 15, weight: .heavy))
                .tracking(2.5)
            if isTx {
                Text(String(format: "%.0f W · SWR %.2f:1",
                            controller.amplifierState.forwardPower,
                            controller.amplifierState.swr))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isTx ? Color.red : Color.primary.opacity(0.06))
        )
        .foregroundStyle(isTx ? Color.white : Color.secondary)
        .animation(.easeInOut(duration: 0.12), value: isTx)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Transmit state")
        .accessibilityValue(isTx ? "Transmitting" : "Receiving")
    }
}

// MARK: - Primary gauges

struct PrimaryGaugesView: View {
    @EnvironmentObject var controller: AmplifierController

    private var samples: [TelemetrySample] { controller.recentSamples(seconds: 60) }

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4),
                      spacing: 14) {

                VStack(spacing: 0) {
                    ArcGauge(title: "Forward Power",
                             value: controller.amplifierState.forwardPower,
                             unit: "W",
                             range: 0...600,
                             icon: "bolt.fill",
                             peak: controller.peakForward,
                             warningThreshold: 480,
                             dangerThreshold: 560,
                             decimals: 0,
                             tint: .blue,
                             caption: String(format: "peak %.0f · avg %.0f",
                                             controller.peakForward,
                                             controller.stats.averageTransmitPower))
                    Sparkline(values: samples.map(\.forwardPower), range: 0...600, tint: .blue)
                        .frame(height: 26)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
                .background(CardBackground())

                VStack(spacing: 0) {
                    ArcGauge(title: "SWR",
                             value: controller.amplifierState.swr,
                             unit: ":1",
                             range: 1...3,
                             icon: "waveform.path.ecg",
                             peak: controller.peakSWR,
                             warningThreshold: 2.0,
                             dangerThreshold: 2.5,
                             decimals: 2,
                             tint: .green,
                             caption: String(format: "peak %.2f:1", controller.peakSWR))
                    Sparkline(values: samples.map(\.swr), range: 1...3, tint: .green)
                        .frame(height: 26)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
                .background(CardBackground())

                VStack(spacing: 0) {
                    ArcGauge(title: "PA Temperature",
                             value: controller.amplifierState.temperature,
                             unit: "°C",
                             range: 0...90,
                             icon: "thermometer.medium",
                             peak: controller.peakTemperature,
                             warningThreshold: 60,
                             dangerThreshold: 70,
                             decimals: 0,
                             tint: .teal,
                             caption: String(format: "peak %.0f °C", controller.peakTemperature))
                    Sparkline(values: samples.map(\.temperature), range: 0...90, tint: .teal)
                        .frame(height: 26)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
                .background(CardBackground())

                BandAntennaCard()
            }
        }
    }
}

/// Band, frequency and the antenna selector the previous UI never offered.
struct BandAntennaCard: View {
    @EnvironmentObject var controller: AmplifierController

    @State private var pendingAntenna: Int?
    @State private var confirmingAntenna: Int?

    private var state: AmplifierState { controller.amplifierState }

    /// Switching the antenna relay under RF is hot-switching, so the operator
    /// confirms and the confirmation travels to the controller as `force`.
    private func requestAntenna(_ antenna: Int) {
        if state.isTx {
            confirmingAntenna = antenna
        } else {
            pendingAntenna = antenna
            controller.setAntenna(antenna)
        }
    }

    /// The band the reported frequency implies, used to flag a mismatch
    /// between the selected low-pass filter and where the rig actually is.
    private var impliedBand: Int? {
        BandSelection.code(forFrequencyKHz: state.frequency)
    }

    private var mismatch: Bool {
        guard let implied = impliedBand, state.bandCode > 0 else { return false }
        return implied != state.bandCode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("Band & Antenna")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(state.band)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.purple)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(state.frequencyDisplay)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if mismatch, let implied = impliedBand {
                Label("Rig is on \(BandSelection.name(for: implied))",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 0)

            // The picker shows what the amplifier reports, and a request is
            // only in flight until the next frame confirms it. v2.0 gave no
            // sign of that, so a refused change just silently snapped back.
            Picker("Antenna", selection: Binding(
                get: { pendingAntenna ?? max(1, min(10, state.antenna)) },
                set: { requestAntenna($0) }
            )) {
                ForEach(1...10, id: \.self) { Text("Antenna \($0)").tag($0) }
            }
            .labelsHidden()
            .disabled(!controller.connectionState.isConnected || state.bandCode == 0)
            .accessibilityLabel("Antenna selection")

            if let pending = pendingAntenna, pending != state.antenna {
                Label("Switching to antenna \(pending)…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CardBackground())
        // Clear the pending marker once the amplifier confirms, or once it
        // reports something else entirely (a refusal).
        .onChange(of: state.antenna) { _ in pendingAntenna = nil }
        .confirmationDialog("The amplifier is transmitting",
                            isPresented: Binding(get: { confirmingAntenna != nil },
                                                 set: { if !$0 { confirmingAntenna = nil } }),
                            titleVisibility: .visible) {
            Button("Switch Antenna Anyway", role: .destructive) {
                if let antenna = confirmingAntenna {
                    pendingAntenna = antenna
                    controller.setAntenna(antenna, force: true)
                }
                confirmingAntenna = nil
            }
            Button("Cancel", role: .cancel) { confirmingAntenna = nil }
        } message: {
            Text("Switching the antenna relay under RF risks hot-switching it.")
        }
    }
}

// MARK: - Controls

struct ControlPanelView: View {
    @EnvironmentObject var controller: AmplifierController

    @State private var confirmingMode: AmplifierMode?
    @State private var pendingBand: BandSelection?

    private var isLive: Bool { controller.connectionState.isConnected }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Mode")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(AmplifierMode.allCases) { mode in
                        ModeButton(mode: mode, isLive: isLive) {
                            if mode.needsConfirmation {
                                confirmingMode = mode
                            } else {
                                controller.setMode(mode)
                            }
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Band")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Antenna \(max(1, controller.amplifierState.antenna)) is kept")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                // Adaptive columns so the ten buttons wrap instead of being
                // crushed into a fixed row on a narrow window.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                    ForEach(BandSelection.allBands) { band in
                        BandButton(band: band, isLive: isLive) {
                            // Switching the low-pass filter under RF is exactly
                            // the hot-switching case the amplifier protects against.
                            if controller.amplifierState.isTx {
                                pendingBand = band
                            } else {
                                controller.setBand(band.code)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(CardBackground())
        .confirmationDialog("Power off the amplifier?",
                            isPresented: Binding(get: { confirmingMode != nil },
                                                 set: { if !$0 { confirmingMode = nil } }),
                            titleVisibility: .visible) {
            Button("Power Off", role: .destructive) {
                // force carries the confirmation: the controller refuses to cut
                // the supply mid-transmission without it.
                if let mode = confirmingMode {
                    controller.setMode(mode, force: controller.amplifierState.isTx)
                }
                confirmingMode = nil
            }
            Button("Cancel", role: .cancel) { confirmingMode = nil }
        } message: {
            Text(controller.amplifierState.isTx
                 ? "The amplifier is TRANSMITTING. Its power supply will shut down, and you cannot switch it back on from this app."
                 : "The amplifier's power supply will shut down. You cannot switch it back on from this app.")
        }
        .confirmationDialog("The amplifier is transmitting",
                            isPresented: Binding(get: { pendingBand != nil },
                                                 set: { if !$0 { pendingBand = nil } }),
                            titleVisibility: .visible) {
            Button("Change Band Anyway", role: .destructive) {
                if let band = pendingBand { controller.setBand(band.code, force: true) }
                pendingBand = nil
            }
            Button("Cancel", role: .cancel) { pendingBand = nil }
        } message: {
            Text("Switching the low-pass filter under RF risks hot-switching the antenna relays.")
        }
    }
}

struct ModeButton: View {
    @EnvironmentObject var controller: AmplifierController
    let mode: AmplifierMode
    let isLive: Bool
    let action: () -> Void

    private var isActive: Bool { mode.matches(modeCode: controller.amplifierState.modeCode) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: mode.icon)
                    .font(.system(size: 20))
                Text(mode.title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? mode.tint : Color.primary.opacity(0.07))
            )
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(mode == .powerOff ? Color.red.opacity(0.45) : Color.clear,
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isLive)
        .accessibilityLabel(mode.title)
        .accessibilityValue(isActive ? "Active" : "Inactive")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

struct BandButton: View {
    @EnvironmentObject var controller: AmplifierController
    let band: BandSelection
    let isLive: Bool
    let action: () -> Void

    private var isActive: Bool { controller.amplifierState.bandCode == band.code }

    var body: some View {
        Button(action: action) {
            Text(band.name)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Color.purple : Color.primary.opacity(0.07))
                )
                .foregroundStyle(isActive ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(!isLive)
        .accessibilityLabel("\(band.name) band")
        .accessibilityValue(isActive ? "Selected" : "Not selected")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: - Faults

struct FaultPanelView: View {
    @EnvironmentObject var controller: AmplifierController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Active Faults")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Clear Soft Faults") { controller.clearErrors() }
                    .disabled(!controller.connectionState.isConnected)
            }

            // `id` combines slot and code: the amplifier can report the same
            // code in two log slots, which collided under a plain `id: \.self`.
            ForEach(controller.amplifierState.faults) { fault in
                HStack(alignment: .top, spacing: 10) {
                    Text(fault.codeText)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(fault.severity.color)
                        .frame(width: 52, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(fault.title)
                                .font(.system(size: 12, weight: .semibold))
                            Text(fault.severity.label)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(fault.severity.color.opacity(0.18)))
                                .foregroundStyle(fault.severity.color)
                            if let parameter = fault.parameter {
                                Text("parameter \(parameter)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Text(fault.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(fault.severity.color.opacity(0.09))
                )
                .accessibilityElement(children: .combine)
            }

            Text("Names and severities come from section 3.4.1 of the ACOM RS-232 specification. Only soft faults can be cleared from here; a hard fault has already shut the supply down.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(CardBackground(tint: Color.red.opacity(0.08)))
    }
}

// MARK: - Telemetry grid

struct TelemetryGridView: View {
    @EnvironmentObject var controller: AmplifierController

    private var s: AmplifierState { controller.amplifierState }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Telemetry")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                TelemetryTile(title: "Mode", value: s.mode, icon: "gearshape")
                TelemetryTile(title: "Reflected Power",
                              value: String(format: "%.0f W", s.reflectedPower),
                              icon: "arrow.uturn.left",
                              tint: s.reflectedPower >= 50 ? .orange : .primary)
                TelemetryTile(title: "Drive Power",
                              value: String(format: "%.1f W", s.inputPower), icon: "arrow.down")
                TelemetryTile(title: "Drain Current",
                              value: String(format: "%.2f A", s.current), icon: "bolt.circle")
                TelemetryTile(title: "Frequency", value: s.frequencyDisplay, icon: "waveform")
                // Telemetry byte 69 gives the fan speed as 0...4, which the
                // controller reports alongside the percentage it derives from
                // it. v2.0 showed "/15" because the firmware scaled by 15.
                TelemetryTile(title: "Fan",
                              value: "\(s.fanSpeed)% · lvl \(s.fanLevel)/\(s.fanLevelMax)",
                              icon: "fan")
                TelemetryTile(title: "HV Supply",
                              value: String(format: "%.1f V", s.hvVoltage), icon: "bolt.badge.a")
                TelemetryTile(title: "Dissipation",
                              value: String(format: "%.1f W", s.disPower), icon: "flame")
                TelemetryTile(title: "DC Input",
                              value: String(format: "%.1f W", s.pdcPower), icon: "powerplug")
                TelemetryTile(title: "VCC 5 V",
                              value: String(format: "%.2f V", s.vcc5), icon: "minus.plus.batteryblock")
                TelemetryTile(title: "LPF Channel",
                              value: s.lpfChannel > 0 ? "\(s.lpfChannel)" : "—", icon: "slider.horizontal.3")
                TelemetryTile(title: "Frames", value: "\(s.msgCount)", icon: "number")
            }
        }
        .padding(16)
        .background(CardBackground())
    }
}

// MARK: - Session summary

struct SessionSummaryView: View {
    @EnvironmentObject var controller: AmplifierController
    @EnvironmentObject var router: AppRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This Session")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Details") { router.showHistory = true }
                    .buttonStyle(.link)
                Button("Reset") { controller.resetSession() }
                    .buttonStyle(.link)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                StatTile(title: "Peak Power",
                         value: String(format: "%.0f W", controller.stats.peakForwardPower),
                         detail: String(format: "avg %.0f W", controller.stats.averageTransmitPower),
                         tint: .blue)
                StatTile(title: "Peak SWR",
                         value: String(format: "%.2f:1", controller.stats.peakSWR),
                         detail: String(format: "reflected %.0f W", controller.stats.peakReflectedPower),
                         tint: controller.stats.peakSWR >= 2.5 ? .red : .green)
                StatTile(title: "Peak Temp",
                         value: String(format: "%.0f °C", controller.stats.peakTemperature),
                         detail: String(format: "peak current %.1f A", controller.stats.peakCurrent),
                         tint: controller.stats.peakTemperature >= 70 ? .red : .teal)
                StatTile(title: "Transmit Time",
                         value: Format.duration(controller.stats.transmitSeconds),
                         detail: "\(controller.stats.transmissions) transmissions")
                StatTile(title: "Duty Cycle",
                         value: String(format: "%.0f%%", controller.stats.dutyCycle * 100),
                         detail: "of \(Format.duration(controller.stats.totalSeconds)) observed")
            }
        }
        .padding(16)
        .background(CardBackground())
    }
}

#Preview {
    ContentView()
        .environmentObject(AmplifierController())
        .environmentObject(AppRouter())
        .frame(width: 1000, height: 760)
}
