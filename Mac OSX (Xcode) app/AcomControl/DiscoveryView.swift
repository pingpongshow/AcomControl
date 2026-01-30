//
//  DiscoveryView.swift
//  AcomControl
//

import SwiftUI

struct DiscoveryView: View {
    @EnvironmentObject var controller: AmplifierController
    @StateObject private var discoveryManager = NetworkDiscoveryManager()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Discover ESP32 Controllers")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Scanning local network for AcomControl devices")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") {
                    discoveryManager.stopScan()
                    dismiss()
                }
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Content
            VStack(spacing: 20) {
                // Scan controls
                HStack {
                    if discoveryManager.isScanning {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Scanning... (\(discoveryManager.scannedCount)/254)")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    } else {
                        Button(action: {
                            discoveryManager.startScan()
                        }) {
                            Label("Scan Network", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Spacer()
                    
                    if discoveryManager.isScanning {
                        Button("Stop Scan") {
                            discoveryManager.stopScan()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Results
                if discoveryManager.discoveredDevices.isEmpty && !discoveryManager.isScanning {
                    VStack(spacing: 12) {
                        Image(systemName: "network.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No devices found")
                            .font(.system(size: 16, weight: .medium))
                        
                        Text("Click 'Scan Network' to search for ESP32 controllers")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(discoveryManager.discoveredDevices) { device in
                                DeviceRow(device: device) {
                                    controller.connect(to: device.ipAddress)
                                    dismiss()
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                }
                
                // Network info
                if let subnet = discoveryManager.currentSubnet {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("Scanning subnet: \(subnet).x")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(width: 600, height: 500)
        .onDisappear {
            discoveryManager.stopScan()
        }
    }
}

struct DeviceRow: View {
    let device: DiscoveredDevice
    let onConnect: () -> Void
    
    var body: some View {
        HStack(spacing: 15) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "network")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
            }
            
            // Device info
            VStack(alignment: .leading, spacing: 4) {
                Text("ESP32-S3 Controller")
                    .font(.system(size: 14, weight: .semibold))
                
                HStack(spacing: 12) {
                    Label(device.ipAddress, systemImage: "network")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    if let model = device.chipModel {
                        Label(model, systemImage: "chip")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    if let serialNumber = device.serialNumber, !serialNumber.isEmpty, serialNumber != "Unknown" {
                        Label(serialNumber, systemImage: "number")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Connect button
            Button("Connect") {
                onConnect()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        )
    }
}

// MARK: - Network Discovery Manager

struct DiscoveredDevice: Identifiable {
    let id = UUID()
    let ipAddress: String
    let chipModel: String?
    let serialNumber: String?
    let rssi: Int?
}

class NetworkDiscoveryManager: ObservableObject {
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var isScanning = false
    @Published var scannedCount = 0
    @Published var currentSubnet: String?
    
    private var scanTask: Task<Void, Never>?
    private let maxConcurrentScans = 50 // Limit concurrent network requests
    
    func startScan() {
        // Cancel any existing scan
        stopScan()
        
        discoveredDevices.removeAll()
        isScanning = true
        scannedCount = 0
        
        // Get current subnet
        currentSubnet = getCurrentSubnet()
        
        scanTask = Task {
            await scanNetwork()
        }
    }
    
    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        DispatchQueue.main.async {
            self.isScanning = false
        }
    }
    
    private func scanNetwork() async {
        guard let subnet = currentSubnet else {
            await MainActor.run {
                isScanning = false
            }
            return
        }
        
        await withTaskGroup(of: DiscoveredDevice?.self) { group in
            var activeTaskCount = 0
            
            for i in 1...254 {
                // Check if cancelled
                if Task.isCancelled {
                    break
                }
                
                let ip = "\(subnet).\(i)"
                
                // Limit concurrent tasks
                if activeTaskCount >= maxConcurrentScans {
                    // Wait for one to complete
                    if let device = await group.next() {
                        activeTaskCount -= 1
                        if let device = device {
                            await addDevice(device)
                        }
                    }
                }
                
                group.addTask {
                    await self.checkDevice(at: ip)
                }
                activeTaskCount += 1
                
                await MainActor.run {
                    self.scannedCount = i
                }
            }
            
            // Collect remaining results
            for await device in group {
                if let device = device {
                    await addDevice(device)
                }
            }
        }
        
        await MainActor.run {
            isScanning = false
        }
    }
    
    private func checkDevice(at ipAddress: String) async -> DiscoveredDevice? {
        guard let url = URL(string: "http://\(ipAddress)/api/system") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            let apiResponse = try JSONDecoder().decode(APIResponse<SystemInfo>.self, from: data)
            
            guard apiResponse.success, let systemInfo = apiResponse.data else {
                return nil
            }
            
            // Also try to get serial number from status endpoint
            var serialNumber: String? = nil
            if let statusURL = URL(string: "http://\(ipAddress)/api/status") {
                do {
                    var statusRequest = URLRequest(url: statusURL)
                    statusRequest.timeoutInterval = 1.0
                    statusRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                    let (statusData, _) = try await URLSession.shared.data(for: statusRequest)
                    let statusResponse = try JSONDecoder().decode(APIResponse<AmplifierState>.self, from: statusData)
                    serialNumber = statusResponse.data?.serialNumber
                } catch {
                    // Ignore error, serial number is optional
                }
            }
            
            return DiscoveredDevice(
                ipAddress: ipAddress,
                chipModel: systemInfo.chipModel,
                serialNumber: serialNumber,
                rssi: systemInfo.rssi
            )
        } catch {
            // Not an ESP32 or not responding
            return nil
        }
    }
    
    @MainActor
    private func addDevice(_ device: DiscoveredDevice) {
        if !discoveredDevices.contains(where: { $0.ipAddress == device.ipAddress }) {
            discoveredDevices.append(device)
            // Sort by IP address numerically
            discoveredDevices.sort { lhs, rhs in
                let lhsParts = lhs.ipAddress.split(separator: ".").compactMap { Int($0) }
                let rhsParts = rhs.ipAddress.split(separator: ".").compactMap { Int($0) }
                
                for (l, r) in zip(lhsParts, rhsParts) {
                    if l != r {
                        return l < r
                    }
                }
                return false
            }
        }
    }
    
    private func getCurrentSubnet() -> String? {
        // Try to detect current network subnet
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else {
            return "192.168.1" // Default fallback
        }
        
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                
                // Check for active network interfaces (WiFi or Ethernet)
                if name == "en0" || name == "en1" || name.hasPrefix("en") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let result = getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        socklen_t(0),
                        NI_NUMERICHOST
                    )
                    
                    if result == 0 {
                        let detectedAddress = String(cString: hostname)
                        // Skip loopback
                        if !detectedAddress.hasPrefix("127.") && !detectedAddress.hasPrefix("169.254.") {
                            address = detectedAddress
                            break
                        }
                    }
                }
            }
        }
        
        if let address = address {
            let components = address.split(separator: ".")
            if components.count == 4 {
                return "\(components[0]).\(components[1]).\(components[2])"
            }
        }
        
        // Default to common private network
        return "192.168.1"
    }
}

struct DiscoveryView_Previews: PreviewProvider {
    static var previews: some View {
        DiscoveryView()
            .environmentObject(AmplifierController())
    }
}
