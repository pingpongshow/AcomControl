//
//  SettingsView.swift
//  AcomControl
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var controller: AmplifierController
    @State private var ipAddress: String = ""
    @State private var showingWiFiConfig = false
    @State private var wifiSSID = ""
    @State private var wifiPassword = ""
    @State private var isConfiguringWiFi = false
    @State private var wifiConfigResult: String?
    @State private var systemInfo: SystemInfo?
    @State private var isLoadingSystemInfo = false
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
            
            ScrollView {
                VStack(spacing: 20) {
                    // Connection settings
                    GroupBox(label: Label("Connection", systemImage: "network")) {
                        VStack(alignment: .leading, spacing: 15) {
                            // Manual IP entry
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ESP32 IP Address")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    TextField("192.168.4.1", text: $ipAddress)
                                        .textFieldStyle(.roundedBorder)
                                        .onAppear {
                                            ipAddress = controller.connectedIP
                                        }
                                    
                                    Button("Connect") {
                                        if !ipAddress.isEmpty {
                                            controller.connect(to: ipAddress)
                                        }
                                    }
                                    .disabled(ipAddress.isEmpty)
                                }
                                
                                Text("Enter the IP address of your ESP32-S3 controller")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Divider()
                            
                            // Quick connect presets
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Quick Connect")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    Button("AP Mode (192.168.4.1)") {
                                        ipAddress = "192.168.4.1"
                                        controller.connect(to: "192.168.4.1")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            
                            Divider()
                            
                            // Connection status
                            HStack {
                                Text("Status:")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                
                                switch controller.connectionState {
                                case .disconnected:
                                    Label("Disconnected", systemImage: "circle.fill")
                                        .foregroundColor(.red)
                                case .connecting:
                                    Label("Connecting...", systemImage: "circle.fill")
                                        .foregroundColor(.orange)
                                case .connected:
                                    Label("Connected to \(controller.connectedIP)", systemImage: "circle.fill")
                                        .foregroundColor(.green)
                                }
                                
                                Spacer()
                                
                                if controller.connectionState == .connected {
                                    Button("Disconnect") {
                                        controller.disconnect()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .font(.system(size: 12))
                        }
                        .padding(12)
                    }
                    
                    // WiFi Configuration
                    GroupBox(label: Label("WiFi Configuration", systemImage: "wifi")) {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Configure ESP32 WiFi settings to connect to your network")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            
                            if !showingWiFiConfig {
                                Button("Configure WiFi") {
                                    showingWiFiConfig = true
                                }
                                .buttonStyle(.bordered)
                                .disabled(controller.connectionState != .connected)
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Network SSID")
                                            .font(.system(size: 12, weight: .medium))
                                        TextField("WiFi Network Name", text: $wifiSSID)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Password")
                                            .font(.system(size: 12, weight: .medium))
                                        SecureField("WiFi Password", text: $wifiPassword)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    
                                    HStack {
                                        Button("Cancel") {
                                            showingWiFiConfig = false
                                            wifiSSID = ""
                                            wifiPassword = ""
                                            wifiConfigResult = nil
                                        }
                                        .buttonStyle(.bordered)
                                        
                                        Button("Save & Reboot ESP32") {
                                            configureWiFi()
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(wifiSSID.isEmpty || wifiPassword.isEmpty || isConfiguringWiFi)
                                    }
                                    
                                    if isConfiguringWiFi {
                                        HStack {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                            Text("Configuring WiFi...")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    if let result = wifiConfigResult {
                                        Text(result)
                                            .font(.system(size: 12))
                                            .foregroundColor(result.contains("success") ? .green : .red)
                                    }
                                }
                            }
                        }
                        .padding(12)
                    }
                    
                    // System Information
                    GroupBox(label: Label("System Information", systemImage: "info.circle")) {
                        VStack(alignment: .leading, spacing: 15) {
                            Button("Refresh System Info") {
                                loadSystemInfo()
                            }
                            .buttonStyle(.bordered)
                            .disabled(controller.connectionState != .connected || isLoadingSystemInfo)
                            
                            if isLoadingSystemInfo {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Loading...")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let info = systemInfo {
                                Divider()
                                
                                VStack(spacing: 8) {
                                    SystemInfoRow(label: "Chip Model", value: info.chipModel)
                                    SystemInfoRow(label: "CPU Frequency", value: "\(info.cpuFreqMHz) MHz")
                                    SystemInfoRow(label: "Free Heap", value: formatBytes(info.freeHeap))
                                    SystemInfoRow(label: "PSRAM Free", value: formatBytes(info.psramFree))
                                    SystemInfoRow(label: "WiFi Mode", value: info.wifiMode)
                                    SystemInfoRow(label: "SSID", value: info.wifiSSID)
                                    SystemInfoRow(label: "IP Address", value: info.ipAddress)
                                    SystemInfoRow(label: "RSSI", value: "\(info.rssi) dBm")
                                    SystemInfoRow(label: "Uptime", value: formatUptime(info.uptime))
                                    SystemInfoRow(label: "WebSocket Clients", value: "\(info.performance.wsClients)")
                                }
                            }
                        }
                        .padding(12)
                    }
                    
                    // About
                    GroupBox(label: Label("About", systemImage: "info.circle.fill")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AcomControl")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Version 1.0")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            
                            Divider()
                            
                            Text("macOS Application for ACOM 600S Amplifier Control")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            
                            Text("Connects to ESP32-S3 controller via WebSocket for real-time monitoring and control")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                    }
                    .padding(.horizontal, 20)
                    
                    // Debug Log
                    GroupBox(label: Label("Debug Log", systemImage: "terminal")) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Connection diagnostics")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Clear") {
                                    controller.clearDebugLog()
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 11))
                            }
                            
                            ScrollView {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(Array(controller.debugLog.enumerated()), id: \.offset) { index, log in
                                        Text(log)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(log.contains("ERROR") ? .red : (log.contains("✓") ? .green : .primary))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 150)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                        }
                        .padding(12)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(20)
            }
        }
        .frame(width: 600, height: 700)
    }
    
    private func configureWiFi() {
        isConfiguringWiFi = true
        wifiConfigResult = nil
        
        Task {
            do {
                try await controller.configureWiFi(ssid: wifiSSID, password: wifiPassword)
                await MainActor.run {
                    wifiConfigResult = "✓ WiFi configured successfully. ESP32 will reboot and connect to '\(wifiSSID)'. Check serial console for new IP address."
                    isConfiguringWiFi = false
                    
                    // Clear form after success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showingWiFiConfig = false
                        wifiSSID = ""
                        wifiPassword = ""
                    }
                }
            } catch {
                await MainActor.run {
                    wifiConfigResult = "✗ Failed: \(error.localizedDescription)"
                    isConfiguringWiFi = false
                }
            }
        }
    }
    
    private func loadSystemInfo() {
        isLoadingSystemInfo = true
        
        Task {
            do {
                let info = try await controller.getSystemInfo()
                await MainActor.run {
                    systemInfo = info
                    isLoadingSystemInfo = false
                }
            } catch {
                await MainActor.run {
                    isLoadingSystemInfo = false
                    print("Failed to load system info: \(error)")
                }
            }
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func formatUptime(_ milliseconds: Int) -> String {
        let seconds = milliseconds / 1000
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}

struct SystemInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AmplifierController())
    }
}
