//
//  SettingsView.swift
//  AcomControl
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var controller: AmplifierController
    @EnvironmentObject var router: AppRouter

    /// The same view backs both the gear-button sheet and the ⌘, Settings
    /// scene. Only the sheet gets a Done button — a `dismiss` inside a
    /// `Settings` scene does nothing, which left the old build with a dead
    /// header when opened from the menu.
    var isSheet: Bool = false

    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable, Identifiable {
        case connection = "Connection"
        case controller = "Controller"
        case alerts = "Alerts"
        case diagnostics = "Diagnostics"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .connection:  return "network"
            case .controller:  return "cpu"
            case .alerts:      return "bell.badge"
            case .diagnostics: return "stethoscope"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isSheet {
                HStack {
                    Text("Settings").font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                Divider()
            }

            // The selected tab lives in the router so that "Show Connection
            // Log" can land on Diagnostics instead of wherever the operator
            // happened to leave it.
            TabView(selection: $router.settingsTab) {
                ConnectionSettings()
                    .tabItem { Label(Tab.connection.rawValue, systemImage: Tab.connection.icon) }
                    .tag(Tab.connection)
                ControllerSettings()
                    .tabItem { Label(Tab.controller.rawValue, systemImage: Tab.controller.icon) }
                    .tag(Tab.controller)
                AlertSettings()
                    .tabItem { Label(Tab.alerts.rawValue, systemImage: Tab.alerts.icon) }
                    .tag(Tab.alerts)
                DiagnosticsSettings()
                    .tabItem { Label(Tab.diagnostics.rawValue, systemImage: Tab.diagnostics.icon) }
                    .tag(Tab.diagnostics)
            }
            .padding(isSheet ? 12 : 0)
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 480, idealHeight: 560)
    }
}

// MARK: - Connection

private struct ConnectionSettings: View {
    @EnvironmentObject var controller: AmplifierController
    @State private var host = ""
    @State private var renaming: SavedDevice?
    @State private var newName = ""

    var body: some View {
        Form {
            Section("Connect") {
                HStack {
                    TextField("Address", text: $host, prompt: Text("192.168.4.1 or acomcontrol.local"))
                        .onSubmit(connect)
                    Button("Connect", action: connect)
                        .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                HStack {
                    Text(controller.connectionState.label)
                        .foregroundStyle(controller.connectionState.color)
                    if controller.connectionState.isConnected {
                        Text(controller.connectedHost).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if controller.connectionState.isConnected {
                        Button("Disconnect") { controller.disconnect() }
                    } else if !controller.connectedHost.isEmpty {
                        Button("Retry") { controller.retry() }
                    }
                }
            }

            Section("Saved Controllers") {
                if controller.devices.devices.isEmpty {
                    Text("Controllers you connect to are remembered here.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(controller.devices.devices) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(device.displayName).font(.system(size: 12, weight: .medium))
                                Text(device.host).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if controller.devices.autoConnectHost == device.host {
                                Text("Auto-connect")
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                            }
                            Menu {
                                Button("Connect") { controller.connect(to: device.host) }
                                Button("Rename…") { renaming = device; newName = device.name }
                                Button(controller.devices.autoConnectHost == device.host
                                       ? "Stop Auto-connecting" : "Auto-connect on Launch") {
                                    controller.devices.autoConnectHost =
                                        controller.devices.autoConnectHost == device.host ? nil : device.host
                                }
                                Divider()
                                Button("Forget", role: .destructive) { controller.devices.remove(device) }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { if host.isEmpty { host = controller.connectedHost } }
        .sheet(item: $renaming) { device in
            VStack(alignment: .leading, spacing: 12) {
                Text("Rename Controller").font(.headline)
                TextField("Name", text: $newName)
                HStack {
                    Spacer()
                    Button("Cancel") { renaming = nil }
                    Button("Save") {
                        controller.devices.rename(device, to: newName)
                        renaming = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(18)
            .frame(width: 320)
        }
    }

    private func connect() {
        let target = host.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        controller.connect(to: target)
    }
}

// MARK: - Controller

private struct ControllerSettings: View {
    @EnvironmentObject var controller: AmplifierController

    @State private var info: SystemInfo?
    @State private var config = ControllerConfig()
    @State private var isLoading = false
    @State private var message: String?

    @State private var ssid = ""
    @State private var password = ""
    @State private var hostname = ""
    @State private var isSavingWiFi = false

    @State private var apiUser = "acom"
    @State private var apiPassword = ""
    @State private var apPassword = ""
    @State private var isSavingAccess = false

    private var isLive: Bool { controller.connectionState.isConnected }

    var body: some View {
        Form {
            Section("Rig Integration") {
                Toggle("Follow the transceiver's frequency (automatic band change)",
                       isOn: Binding(get: { config.autoBandFollow },
                                     set: { apply(autoBandFollow: $0) }))
                    .disabled(!isLive)
                Text("The controller changes bands to match the operating frequency, and never while transmitting. Rig-control software can also push a frequency to POST /api/frequency.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Toggle("Log telemetry to the controller's flash",
                       isOn: Binding(get: { config.logging },
                                     set: { apply(logging: $0) }))
                    .disabled(!isLive)
            }

            Section("Wi-Fi") {
                TextField("Network name", text: $ssid)
                // An empty password is legitimate for an open network; the old
                // build disabled Save until one was typed.
                SecureField("Password (leave blank for an open network)", text: $password)
                HStack {
                    Button("Save & Reboot Controller") {
                        Task { await saveWiFi() }
                    }
                    .disabled(!isLive || ssid.isEmpty || isSavingWiFi)
                    if isSavingWiFi { ProgressView().controlSize(.small) }
                }
            }

            Section("Network Name") {
                HStack {
                    TextField("Hostname", text: $hostname, prompt: Text("acomcontrol"))
                    Button("Save") { Task { await saveHostname() } }
                        .disabled(!isLive || hostname.isEmpty)
                }
                Text("Reachable at \(hostname.isEmpty ? "acomcontrol" : hostname).local. Changing this reboots the controller.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // Firmware 7.0 can require a password and close its setup access
            // point. v6.0 had neither, which left a 600 W amplifier open to
            // anything that could reach it.
            Section("Access") {
                if !config.authEnabled {
                    Label("This controller has no API password. Anyone who can reach it can change bands or flash firmware.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if config.apOpen && config.apMode {
                    Label("Its setup access point “\(config.apSSID)” has no passphrase.",
                          systemImage: "wifi.exclamationmark")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField("API user", text: $apiUser, prompt: Text("acom"))
                SecureField("API password (blank disables authentication)", text: $apiPassword)
                TextField("Access point passphrase (8+ characters, blank reopens it)",
                          text: $apPassword)
                HStack {
                    Button("Save Access & Reboot") { Task { await saveAccess() } }
                        .disabled(!isLive || isSavingAccess)
                    if isSavingAccess { ProgressView().controlSize(.small) }
                }
                Text("Write the access point passphrase down before changing the Wi-Fi settings — it is how you reach the controller if it cannot join your network. The API password is stored in your login keychain.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("System") {
                HStack {
                    Button("Refresh") { Task { await load() } }
                        .disabled(!isLive || isLoading)
                    if isLoading { ProgressView().controlSize(.small) }
                    Spacer()
                    if let message {
                        Text(message).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }

                if let info {
                    LabeledContent("Firmware", value: info.firmwareVersion)
                    LabeledContent("Chip", value: "\(info.chipModel) rev \(info.chipRevision) @ \(info.cpuFreqMHz) MHz")
                    LabeledContent("Flash", value: Format.bytes(info.flashSize))
                    LabeledContent("Free heap", value: Format.bytes(info.freeHeap))
                    if info.psramSize > 0 {
                        LabeledContent("PSRAM free", value: "\(Format.bytes(info.psramFree)) of \(Format.bytes(info.psramSize))")
                    }
                    LabeledContent("Wi-Fi", value: "\(info.wifiMode) · \(info.wifiSSID)")
                    LabeledContent("Address", value: info.ipAddress)
                    if info.wifiMode == "STA" {
                        LabeledContent("Signal", value: "\(info.rssi) dBm")
                    }
                    LabeledContent("Uptime", value: Format.uptime(milliseconds: info.uptime))
                    LabeledContent("Stored telemetry",
                                   value: "\(info.historyCount) of \(info.historyCapacity) samples · \(Format.bytes(info.logBytes)) on flash")
                    LabeledContent("Clients",
                                   value: "\(info.performance.wsClients) WebSocket · \(info.performance.sseClients) SSE")
                    LabeledContent("Serial frames", value: "\(info.performance.serialRxCount)")
                }
            }
        }
        .formStyle(.grouped)
        .task { if isLive { await load() } }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await controller.getSystemInfo()
            info = fetched
            if hostname.isEmpty { hostname = fetched.hostname }
            config = (try? await controller.getConfig()) ?? config
            // wifiSSID is now the network the controller is configured to JOIN,
            // so it can be used as-is. v6.0's firmware reported the access
            // point's own name here in AP mode, which is why this used to carry
            // a hardcoded `!= "AcomControl"` guard.
            if ssid.isEmpty { ssid = config.wifiSSID }
            apiUser = config.apiUser
            if apPassword.isEmpty { apPassword = config.apPassword }
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func apply(autoBandFollow: Bool? = nil, logging: Bool? = nil) {
        if let autoBandFollow { config.autoBandFollow = autoBandFollow }
        if let logging { config.logging = logging }
        Task {
            do {
                try await controller.setConfig(autoBandFollow: autoBandFollow, logging: logging)
                message = "Saved"
            } catch {
                message = error.localizedDescription
                await load()
            }
        }
    }

    private func saveWiFi() async {
        isSavingWiFi = true
        defer { isSavingWiFi = false }
        do {
            try await controller.configureWiFi(ssid: ssid, password: password)
            message = "Saved. The controller is rebooting onto “\(ssid)”."
            password = ""
        } catch {
            message = "Failed: \(error.localizedDescription)"
        }
    }

    private func saveHostname() async {
        do {
            try await controller.setConfig(hostname: hostname)
            message = "Saved. The controller is rebooting as \(hostname).local."
        } catch {
            message = "Failed: \(error.localizedDescription)"
        }
    }

    private func saveAccess() async {
        isSavingAccess = true
        defer { isSavingAccess = false }

        let trimmedAP = apPassword
        guard trimmedAP.isEmpty || trimmedAP.count >= 8 else {
            message = "A WPA2 passphrase needs at least 8 characters."
            return
        }
        do {
            try await controller.setConfig(apiUser: apiUser.isEmpty ? "acom" : apiUser,
                                           apiPassword: apiPassword,
                                           apPassword: trimmedAP)
            message = apiPassword.isEmpty
                ? "Saved. Authentication is OFF and the controller is rebooting."
                : "Saved. The controller is rebooting and will require the new password."
        } catch {
            message = "Failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Alerts

private struct AlertSettings: View {
    @State private var enabled: [String: Bool] = [:]
    @State private var soundEnabled = NotificationManager.soundEnabled

    var body: some View {
        Form {
            Section("Notify me when") {
                ForEach(AlertKind.allCases) { kind in
                    Toggle(kind.settingsLabel, isOn: Binding(
                        get: { enabled[kind.rawValue] ?? NotificationManager.isEnabled(kind) },
                        set: {
                            enabled[kind.rawValue] = $0
                            NotificationManager.setEnabled($0, for: kind)
                        }
                    ))
                }
            }

            Section("Sound") {
                Toggle("Play an alert sound", isOn: Binding(
                    get: { soundEnabled },
                    set: { soundEnabled = $0; NotificationManager.soundEnabled = $0 }
                ))
                Text("If macOS notifications are denied for AcomControl, alerts fall back to bouncing the Dock icon.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Section("Fault Code Names") {
                Text("\(ACOMFaultCodes.table.count) fault codes are built in, from section 3.4.1 of the ACOM RS-232 specification."
                     + (FaultCatalog.overrideCount > 0
                        ? " \(FaultCatalog.overrideCount) are overridden by your own table."
                        : " You can override any of them, or name the few the specification leaves blank, with your own table."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Reveal Fault Code Table") {
                        if let url = FaultCatalog.ensureTemplate() {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    Button("Reload") { FaultCatalog.reload() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            for kind in AlertKind.allCases {
                enabled[kind.rawValue] = NotificationManager.isEnabled(kind)
            }
        }
    }
}

// MARK: - Diagnostics

private struct DiagnosticsSettings: View {
    @EnvironmentObject var controller: AmplifierController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Connection Log")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(controller.debugLogText, forType: .string)
                }
                Button("Clear") { controller.clearDebugLog() }
            }

            // Telemetry frames are summarised rather than logged individually,
            // so real errors stay visible instead of scrolling away in seconds.
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(controller.debugLog) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(entry.date, format: .dateTime.hour().minute().second())
                                    .foregroundStyle(.tertiary)
                                Text(entry.message)
                                    .foregroundStyle(entry.isError ? .red
                                                     : (entry.isSuccess ? .green : .primary))
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .onChange(of: controller.debugLog.count) { _ in
                    if let last = controller.debugLog.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            HStack {
                Text("AcomControl \(Bundle.main.shortVersion) (\(Bundle.main.buildVersion))")
                Spacer()
                Text("ACOM 600S over ESP32-S3")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
        .padding(16)
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    var buildVersion: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

#Preview {
    SettingsView(isSheet: true)
        .environmentObject(AmplifierController())
        .environmentObject(AppRouter())
}
