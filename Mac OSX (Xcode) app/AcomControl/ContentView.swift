//
//  ContentView.swift
//  AcomControl
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var controller: AmplifierController
    @State private var showingSettings = false
    @State private var showingDiscovery = false
    
    var body: some View {
        ZStack {
            // Background
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with connection status
                HeaderView(showingSettings: $showingSettings, showingDiscovery: $showingDiscovery)
                
                // Main content
                ScrollView {
                    VStack(spacing: 20) {
                        // Primary meters
                        PrimaryMetersView()
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        
                        // Control buttons
                        ControlButtonsView()
                            .padding(.horizontal, 20)
                        
                        // Secondary telemetry
                        SecondaryTelemetryView()
                            .padding(.horizontal, 20)
                        
                        // Error display
                        if !controller.amplifierState.errors.isEmpty {
                            ErrorDisplayView()
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingDiscovery) {
            DiscoveryView()
        }
    }
}

// MARK: - Header View
struct HeaderView: View {
    @EnvironmentObject var controller: AmplifierController
    @Binding var showingSettings: Bool
    @Binding var showingDiscovery: Bool
    
    var body: some View {
        HStack(spacing: 15) {
            // App icon/logo
            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("AcomControl")
                    .font(.system(size: 18, weight: .semibold))
                Text(controller.amplifierState.serialNumber)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Connection status
            ConnectionStatusView()
            
            // Discover button
            Button(action: { showingDiscovery = true }) {
                Label("Discover", systemImage: "network")
            }
            .buttonStyle(.bordered)
            
            // Settings button
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Connection Status
struct ConnectionStatusView: View {
    @EnvironmentObject var controller: AmplifierController
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            
            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
            
            if controller.connectionState == .connected {
                Text(controller.connectedIP)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(statusColor.opacity(0.1))
        )
    }
    
    private var statusColor: Color {
        switch controller.connectionState {
        case .disconnected:
            return .red
        case .connecting:
            return .orange
        case .connected:
            return .green
        }
    }
    
    private var statusText: String {
        switch controller.connectionState {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        }
    }
}

// MARK: - Primary Meters
struct PrimaryMetersView: View {
    @EnvironmentObject var controller: AmplifierController
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 15) {
            // Power Meter
            MeterView(
                title: "Forward Power",
                value: controller.amplifierState.forwardPower,
                unit: "W",
                maxValue: 600,
                color: controller.amplifierState.isTx ? .red : .green,
                icon: "bolt.fill"
            )
            
            // SWR Meter
            MeterView(
                title: "SWR",
                value: controller.amplifierState.swr,
                unit: ":1",
                maxValue: 3.0,
                color: swrColor,
                icon: "waveform.path.ecg",
                warningThreshold: 2.0,
                dangerThreshold: 2.5
            )
            
            // Temperature Meter
            MeterView(
                title: "Temperature",
                value: controller.amplifierState.temperature,
                unit: "°C",
                maxValue: 80,
                color: temperatureColor,
                icon: "thermometer.medium",
                warningThreshold: 60,
                dangerThreshold: 70
            )
            
            // Band Display
            BandDisplayView()
        }
    }
    
    private var swrColor: Color {
        if controller.amplifierState.swr > 2.5 {
            return .red
        } else if controller.amplifierState.swr > 2.0 {
            return .orange
        } else {
            return .green
        }
    }
    
    private var temperatureColor: Color {
        if controller.amplifierState.temperature > 70 {
            return .red
        } else if controller.amplifierState.temperature > 60 {
            return .orange
        } else {
            return .blue
        }
    }
}

// MARK: - Meter View
struct MeterView: View {
    let title: String
    let value: Double
    let unit: String
    let maxValue: Double
    let color: Color
    let icon: String
    var warningThreshold: Double? = nil
    var dangerThreshold: Double? = nil
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
            }
            
            // Large value display
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                Text(unit)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                    
                    // Warning zones
                    if let warning = warningThreshold {
                        let warningStart = CGFloat(warning / maxValue) * geometry.size.width
                        Rectangle()
                            .fill(Color.orange.opacity(0.3))
                            .frame(width: geometry.size.width - warningStart)
                            .offset(x: warningStart)
                    }
                    
                    if let danger = dangerThreshold {
                        let dangerStart = CGFloat(danger / maxValue) * geometry.size.width
                        Rectangle()
                            .fill(Color.red.opacity(0.3))
                            .frame(width: geometry.size.width - dangerStart)
                            .offset(x: dangerStart)
                    }
                    
                    // Value bar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: min(CGFloat(value / maxValue) * geometry.size.width, geometry.size.width))
                        .animation(.easeInOut(duration: 0.2), value: value)
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        )
    }
}

// MARK: - Band Display
struct BandDisplayView: View {
    @EnvironmentObject var controller: AmplifierController
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.purple)
                Text("Band & Antenna")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
            }
            
            VStack(spacing: 8) {
                // Band
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(controller.amplifierState.band)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.purple)
                }
                
                // Antenna
                HStack {
                    Text("Antenna \(controller.amplifierState.antenna)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        )
    }
}

// MARK: - Control Buttons
struct ControlButtonsView: View {
    @EnvironmentObject var controller: AmplifierController
    
    var body: some View {
        VStack(spacing: 15) {
            // Mode controls
            VStack(alignment: .leading, spacing: 8) {
                Text("Mode Control")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 10) {
                    ModeButton(title: "Standby", mode: 5, icon: "pause.circle.fill", color: .blue)
                    ModeButton(title: "Operate RX", mode: 6, icon: "play.circle.fill", color: .green)
                    ModeButton(title: "Power Off", mode: 10, icon: "power.circle.fill", color: .red)
                }
            }
            
            // Band selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Band Selection")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(BandSelection.allBands, id: \.code) { band in
                        BandButton(band: band)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        )
    }
}

// MARK: - Mode Button
struct ModeButton: View {
    @EnvironmentObject var controller: AmplifierController
    let title: String
    let mode: Int
    let icon: String
    let color: Color
    
    var isActive: Bool {
        controller.amplifierState.modeCode == mode
    }
    
    var body: some View {
        Button(action: {
            controller.setMode(mode)
        }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? color : Color.gray.opacity(0.2))
            )
            .foregroundColor(isActive ? .white : .primary)
        }
        .buttonStyle(.plain)
        .disabled(controller.connectionState != .connected)
    }
}

// MARK: - Band Button
struct BandButton: View {
    @EnvironmentObject var controller: AmplifierController
    let band: BandSelection
    
    var isActive: Bool {
        controller.amplifierState.bandCode == band.code
    }
    
    var body: some View {
        Button(action: {
            controller.setBand(band.code)
        }) {
            Text(band.name)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.purple : Color.gray.opacity(0.2))
                )
                .foregroundColor(isActive ? .white : .primary)
        }
        .buttonStyle(.plain)
        .disabled(controller.connectionState != .connected)
    }
}

// MARK: - Secondary Telemetry
struct SecondaryTelemetryView: View {
    @EnvironmentObject var controller: AmplifierController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Additional Telemetry")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                TelemetryItem(title: "Mode", value: controller.amplifierState.mode, icon: "gear")
                TelemetryItem(title: "Reflected Power", value: "\(Int(controller.amplifierState.reflectedPower)) W", icon: "arrow.left")
                TelemetryItem(title: "Input Power", value: String(format: "%.1f W", controller.amplifierState.inputPower), icon: "arrow.down")
                TelemetryItem(title: "Current", value: String(format: "%.2f A", controller.amplifierState.current), icon: "bolt.circle")
                TelemetryItem(title: "Frequency", value: "\(controller.amplifierState.frequency) kHz", icon: "waveform")
                TelemetryItem(title: "Fan Speed", value: "\(controller.amplifierState.fanSpeed)%", icon: "fan")
                TelemetryItem(title: "HV Voltage", value: "\(controller.amplifierState.hvVoltage) V", icon: "bolt.badge.a")
                TelemetryItem(title: "TX Status", value: controller.amplifierState.isTx ? "TRANSMITTING" : "Receiving", icon: "antenna.radiowaves.left.and.right", color: controller.amplifierState.isTx ? .red : .green)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        )
    }
}

// MARK: - Telemetry Item
struct TelemetryItem: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .primary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.1))
        )
    }
}

// MARK: - Error Display
struct ErrorDisplayView: View {
    @EnvironmentObject var controller: AmplifierController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Active Errors")
                    .font(.system(size: 14, weight: .semibold))
                
                Spacer()
                
                Button("Clear Errors") {
                    controller.clearErrors()
                }
                .buttonStyle(.bordered)
                .disabled(controller.connectionState != .connected)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(controller.amplifierState.errors, id: \.self) { errorCode in
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("Error Code: 0x\(String(format: "%02X", errorCode))")
                            .font(.system(size: 12))
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AmplifierController())
            .frame(width: 900, height: 700)
    }
}
