//
//  DiscoveryView.swift
//  AcomControl
//
//  Finds controllers by Bonjour first (firmware v6.0 advertises _acom._tcp),
//  falling back to a subnet sweep for older firmware.
//

import SwiftUI
import Network

struct DiscoveredDevice: Identifiable, Equatable {
    let id: String            // host, so repeat sightings coalesce
    let host: String
    let displayHost: String   // hostname when Bonjour supplied one
    let chipModel: String?
    let firmwareVersion: String?
    let serialNumber: String?
    let rssi: Int?
    let viaBonjour: Bool

    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool { lhs.id == rhs.id }
}

struct DiscoveryView: View {
    @EnvironmentObject var controller: AmplifierController
    @StateObject private var discovery = NetworkDiscoveryManager()
    @Environment(\.dismiss) private var dismiss

    @State private var manualHost = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect to a Controller")
                        .font(.system(size: 18, weight: .semibold))
                    Text(discovery.statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    savedSection
                    foundSection
                    manualSection
                }
                .padding(18)
            }
        }
        .frame(minWidth: 620, idealWidth: 660, minHeight: 520, idealHeight: 600)
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
    }

    // MARK: Sections

    @ViewBuilder
    private var savedSection: some View {
        if !controller.devices.devices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(controller.devices.devices) { device in
                    HStack(spacing: 12) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.displayName)
                                .font(.system(size: 13, weight: .semibold))
                            HStack(spacing: 8) {
                                Text(device.host)
                                if let sn = device.serialNumber, sn != "Unknown" {
                                    Text("S/N \(sn)")
                                }
                                if let seen = device.lastSeen {
                                    Text(seen, style: .relative) + Text(" ago")
                                }
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Forget") { controller.devices.remove(device) }
                            .buttonStyle(.link)
                        Button("Connect") {
                            controller.connect(to: device.host)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(12)
                    .background(CardBackground())
                }
            }
        }
    }

    @ViewBuilder
    private var foundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("On this network")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if discovery.isScanning {
                    ProgressView()
                        .controlSize(.small)
                    Button("Stop") { discovery.stop() }
                        .buttonStyle(.link)
                } else {
                    Button("Scan Subnet") { discovery.startSubnetScan() }
                        .buttonStyle(.link)
                        .help("Probe every address on the local /24 for older firmware without Bonjour")
                }
            }

            if discovery.isScanning && discovery.scanTotal > 0 {
                ProgressView(value: Double(discovery.scanCompleted),
                             total: Double(discovery.scanTotal))
                    .progressViewStyle(.linear)
            }

            if discovery.devices.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: discovery.isScanning ? "antenna.radiowaves.left.and.right" : "network.slash")
                        .font(.system(size: 34))
                        .foregroundStyle(.tertiary)
                    Text(discovery.isScanning ? "Looking for controllers…" : "No controllers found")
                        .font(.system(size: 13, weight: .medium))
                    Text("Firmware 6.0 and later announces itself over Bonjour. For older firmware, use Scan Subnet or type the address below.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
            } else {
                ForEach(discovery.devices) { device in
                    DeviceRow(device: device) {
                        controller.connect(to: device.host)
                        dismiss()
                    }
                }
            }
        }
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manual")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack {
                TextField("192.168.4.1 or acomcontrol.local", text: $manualHost)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(connectManually)
                Button("Connect", action: connectManually)
                    .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("AP Mode") {
                    controller.connect(to: "192.168.4.1")
                    dismiss()
                }
                .help("Connect to the controller's own access point at 192.168.4.1")
            }
        }
        .padding(12)
        .background(CardBackground())
    }

    private func connectManually() {
        let host = manualHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        controller.connect(to: host)
        dismiss()
    }
}

struct DeviceRow: View {
    let device: DiscoveredDevice
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().fill(Color.blue.opacity(0.18)).frame(width: 38, height: 38)
                Image(systemName: device.viaBonjour ? "bonjour" : "network")
                    .font(.system(size: 16))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayHost)
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: 9) {
                    Text(device.host)
                    if let model = device.chipModel { Text(model) }
                    if let version = device.firmwareVersion { Text("v\(version)") }
                    if let sn = device.serialNumber, !sn.isEmpty, sn != "Unknown" {
                        Text("S/N \(sn)")
                    }
                    if let rssi = device.rssi, rssi != 0 { Text("\(rssi) dBm") }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer()
            Button("Connect", action: onConnect)
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(CardBackground())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Discovery manager

@MainActor
final class NetworkDiscoveryManager: ObservableObject {
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scanCompleted = 0
    @Published private(set) var scanTotal = 0
    @Published private(set) var subnet: String?
    @Published private(set) var bonjourActive = false

    private var browser: NWBrowser?
    private var scanTask: Task<Void, Never>?
    private let maxConcurrentProbes = 32

    var statusText: String {
        if isScanning, scanTotal > 0 {
            return "Scanning \(subnet ?? "local").0/24 — \(scanCompleted) of \(scanTotal) probed"
        }
        if bonjourActive { return "Listening for controllers via Bonjour" }
        return "\(devices.count) controller\(devices.count == 1 ? "" : "s") found"
    }

    // MARK: Bonjour

    func start() {
        guard browser == nil else { return }

        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: "_acom._tcp", domain: nil)
        let browser = NWBrowser(for: descriptor, using: parameters)

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:  self?.bonjourActive = true
                case .failed, .cancelled: self?.bonjourActive = false
                default: break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                for result in results { self?.resolve(result) }
            }
        }

        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        bonjourActive = false
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    private func resolve(_ result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint else { return }

        // The service name is the controller's mDNS hostname, so `<name>.local`
        // is directly usable — no address resolution round trip needed.
        let host = "\(name).local"
        Task { await probe(host: host, displayHost: name, viaBonjour: true) }
    }

    // MARK: Subnet sweep (older firmware without mDNS)

    func startSubnetScan() {
        scanTask?.cancel()
        guard let prefix = Self.currentSubnetPrefix() else { return }

        subnet = prefix
        isScanning = true
        scanCompleted = 0
        scanTotal = 254

        scanTask = Task { [weak self] in
            guard let self else { return }
            let concurrency = self.maxConcurrentProbes
            await withTaskGroup(of: Void.self) { group in
                var inFlight = 0
                for host in 1...254 {
                    if Task.isCancelled { break }
                    if inFlight >= concurrency {
                        await group.next()
                        inFlight -= 1
                    }
                    let address = "\(prefix).\(host)"
                    group.addTask { [weak self] in
                        await self?.probe(host: address, displayHost: address, viaBonjour: false)
                        // Progress counts probes that have *finished*. The old
                        // version incremented as tasks were launched, so the bar
                        // hit 254/254 instantly and then sat there.
                        await self?.noteProbeCompleted()
                    }
                    inFlight += 1
                }
                await group.waitForAll()
            }
            await MainActor.run { self.isScanning = false }
        }
    }

    private func noteProbeCompleted() {
        scanCompleted += 1
    }

    // MARK: Probing

    private func probe(host: String, displayHost: String, viaBonjour: Bool) async {
        guard let url = URL(string: "http://\(host)/api/system") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = viaBonjour ? 4.0 : 1.5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              // Tolerates both the v6.0 envelope and the bare v5.0 object, so a
              // controller that has not been updated yet still shows up.
              let info = try? APIDecoder.payload(SystemInfo.self, from: data)
        else { return }

        // A random web server on the LAN will not carry these fields.
        guard info.chipModel.hasPrefix("ESP32") else { return }

        var serial: String? = nil
        if let statusURL = URL(string: "http://\(host)/api/status") {
            var statusRequest = URLRequest(url: statusURL)
            statusRequest.timeoutInterval = 2.0
            statusRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            if let (statusData, _) = try? await URLSession.shared.data(for: statusRequest),
               let state = try? APIDecoder.payload(AmplifierState.self, from: statusData) {
                serial = state.serialNumber
            }
        }

        add(DiscoveredDevice(
            id: host,
            host: host,
            displayHost: viaBonjour ? displayHost : (info.hostname.isEmpty ? host : info.hostname),
            chipModel: info.chipModel,
            firmwareVersion: info.firmwareVersion == "—" ? nil : info.firmwareVersion,
            serialNumber: serial,
            rssi: info.rssi,
            viaBonjour: viaBonjour
        ))
    }

    private func add(_ device: DiscoveredDevice) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
        // Bonjour results first, then numerically by address.
        devices.sort { lhs, rhs in
            if lhs.viaBonjour != rhs.viaBonjour { return lhs.viaBonjour }
            return Self.sortKey(lhs.host) < Self.sortKey(rhs.host)
        }
    }

    private static func sortKey(_ host: String) -> String {
        let parts = host.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ Int($0) != nil }) else { return host }
        return parts.map { String(format: "%03d", Int($0) ?? 0) }.joined()
    }

    // MARK: Interface inspection

    /// First non-loopback, non-link-local IPv4 address on a real interface.
    static func currentSubnetPrefix() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var pointer = ifaddr
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            guard let addr = current.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: current.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }

            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                              &buffer, socklen_t(buffer.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }

            let address = String(cString: buffer)
            guard !address.hasPrefix("127."), !address.hasPrefix("169.254.") else { continue }

            let octets = address.split(separator: ".")
            if octets.count == 4 {
                return "\(octets[0]).\(octets[1]).\(octets[2])"
            }
        }
        return nil
    }
}

#Preview {
    DiscoveryView()
        .environmentObject(AmplifierController())
        .environmentObject(AppRouter())
}
