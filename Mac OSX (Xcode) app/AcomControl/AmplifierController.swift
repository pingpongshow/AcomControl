//
//  AmplifierController.swift
//  AcomControl
//

import Foundation
import Combine
import Network

enum ConnectionState {
    case disconnected
    case connecting
    case connected
}

class AmplifierController: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var amplifierState = AmplifierState()
    @Published var connectedIP = ""
    @Published var debugLog: [String] = []
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var reconnectTimer: Timer?
    private var pingTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private let reconnectDelay: TimeInterval = 2.0
    private var urlSession: URLSession?
    
    // Network monitor to check local network access
    private var pathMonitor: NWPathMonitor?
    
    init() {
        // Create a URLSession with custom configuration
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: configuration)
        
        // Start network monitoring to trigger permission prompt
        startNetworkMonitoring()
        
        // Try to load last connected IP (but don't auto-connect)
        if let lastIP = UserDefaults.standard.string(forKey: "lastConnectedIP") {
            connectedIP = lastIP
        }
        
        log("AmplifierController initialized")
    }
    
    deinit {
        disconnect()
        pathMonitor?.cancel()
        urlSession?.invalidateAndCancel()
    }
    
    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMessage = "[\(timestamp)] \(message)"
        print(logMessage)
        DispatchQueue.main.async {
            self.debugLog.append(logMessage)
            if self.debugLog.count > 50 {
                self.debugLog.removeFirst()
            }
        }
    }
    
    private func startNetworkMonitoring() {
        pathMonitor = NWPathMonitor()
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            self?.log("Network status: \(path.status)")
            if path.status == .satisfied {
                self?.log("Network available on: \(path.availableInterfaces.map { $0.name }.joined(separator: ", "))")
            }
        }
        pathMonitor?.start(queue: DispatchQueue.global(qos: .background))
    }
    
    // MARK: - Connection Management
    
    func connect(to ipAddress: String) {
        // Ensure we're on main thread for state changes
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.connect(to: ipAddress)
            }
            return
        }
        
        log("Attempting to connect to \(ipAddress)")
        
        // Clean up any existing connection WITHOUT changing state
        cleanupConnection()
        
        connectedIP = ipAddress
        UserDefaults.standard.set(ipAddress, forKey: "lastConnectedIP")
        
        // Set connecting state SYNCHRONOUSLY before creating task
        connectionState = .connecting
        
        guard let url = URL(string: "ws://\(ipAddress)/ws") else {
            log("ERROR: Invalid WebSocket URL: ws://\(ipAddress)/ws")
            connectionState = .disconnected
            return
        }
        
        log("WebSocket URL: \(url.absoluteString)")
        
        guard let session = urlSession else {
            log("ERROR: URLSession not initialized")
            connectionState = .disconnected
            return
        }
        
        log("Creating WebSocket task...")
        webSocketTask = session.webSocketTask(with: url)
        
        // Log the task state
        if let task = webSocketTask {
            log("WebSocket task created, state: \(task.state.rawValue)")
        }
        
        log("Resuming WebSocket task...")
        webSocketTask?.resume()
        log("WebSocket task resumed")
        
        // Start receiving messages immediately
        receiveMessage()
        
        // Start ping timer
        startPingTimer()
        
        // Set timeout for connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self else { return }
            if self.connectionState == .connecting {
                self.log("ERROR: Connection timeout after 10 seconds")
                self.handleDisconnection()
            }
        }
    }
    
    func disconnect() {
        // Ensure we're on main thread for state changes
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.disconnect()
            }
            return
        }
        
        log("Disconnecting...")
        cleanupConnection()
        reconnectAttempts = 0
        
        // Set state synchronously
        if connectionState != .disconnected {
            connectionState = .disconnected
            log("Disconnected")
        }
    }
    
    private func cleanupConnection() {
        // Clean up without changing connection state
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        stopPingTimer()
        stopReconnectTimer()
    }
    
    private func receiveMessage() {
        guard let task = webSocketTask else {
            log("ERROR: Cannot receive - no WebSocket task")
            return
        }
        
        log("Starting to receive messages...")
        
        task.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.log("Received text message (\(text.count) bytes)")
                    self.handleMessage(text)
                case .data(let data):
                    self.log("Received binary message (\(data.count) bytes)")
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                
                // Continue receiving messages
                self.receiveMessage()
                
            case .failure(let error):
                self.log("ERROR: WebSocket receive error: \(error.localizedDescription)")
                if let urlError = error as? URLError {
                    self.log("ERROR: URLError code: \(urlError.code.rawValue)")
                    self.log("ERROR: URLError description: \(urlError.localizedDescription)")
                }
                self.handleDisconnection()
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            log("ERROR: Cannot convert message to data")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let state = try decoder.decode(AmplifierState.self, from: data)
            
            DispatchQueue.main.async {
                self.amplifierState = state
                
                // Mark as connected on first message
                if self.connectionState == .connecting {
                    self.connectionState = .connected
                    self.reconnectAttempts = 0
                    self.log("✓ Connected successfully! Receiving telemetry.")
                }
            }
        } catch {
            log("ERROR: Failed to decode message: \(error.localizedDescription)")
        }
    }
    
    private func handleDisconnection() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            guard self.connectionState != .disconnected else { 
                self.log("Already disconnected, skipping reconnection logic")
                return 
            }
            
            self.log("Handling disconnection...")
            self.connectionState = .disconnected
            self.cleanupConnection()
            
            // Attempt reconnection only if we haven't exceeded max attempts
            guard self.reconnectAttempts < self.maxReconnectAttempts,
                  !self.connectedIP.isEmpty else {
                if self.reconnectAttempts >= self.maxReconnectAttempts {
                    self.log("Max reconnection attempts (\(self.maxReconnectAttempts)) reached")
                }
                return
            }
            
            self.reconnectAttempts += 1
            let delay = min(self.reconnectDelay * Double(self.reconnectAttempts), 30.0) // Cap at 30 seconds
            self.log("Reconnecting in \(Int(delay))s... (attempt \(self.reconnectAttempts)/\(self.maxReconnectAttempts))")
            
            self.reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.connect(to: self.connectedIP)
            }
            RunLoop.main.add(self.reconnectTimer!, forMode: .common)
        }
    }
    
    private func startPingTimer() {
        stopPingTimer()
        log("Starting ping timer...")
        
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
        RunLoop.main.add(pingTimer!, forMode: .common)
    }
    
    private func stopPingTimer() {
        if pingTimer != nil {
            log("Stopping ping timer")
        }
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    private func stopReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    private func sendPing() {
        guard webSocketTask != nil else { return }
        
        log("Sending ping...")
        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                self?.log("Ping failed: \(error.localizedDescription)")
                self?.handleDisconnection()
            } else {
                self?.log("Ping successful")
            }
        }
    }
    
    // MARK: - Command Sending
    
    private func sendCommand(_ command: [String: Any]) {
        guard connectionState == .connected else {
            log("Cannot send command: not connected (state: \(connectionState))")
            return
        }
        
        guard let webSocketTask = webSocketTask else {
            log("Cannot send command: WebSocket task is nil")
            return
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: command)
            guard let jsonString = String(data: data, encoding: .utf8) else {
                log("Failed to convert command to string")
                return
            }
            let message = URLSessionWebSocketTask.Message.string(jsonString)
            
            webSocketTask.send(message) { [weak self] error in
                if let error = error {
                    self?.log("Failed to send command: \(error.localizedDescription)")
                } else {
                    if let cmdName = command["cmd"] as? String {
                        self?.log("Command sent: \(cmdName) - \(jsonString)")
                    }
                }
            }
        } catch {
            log("Failed to encode command: \(error.localizedDescription)")
        }
    }
    
    func setMode(_ mode: Int) {
        sendCommand(["cmd": "setMode", "mode": mode])
    }
    
    func setBand(_ band: Int) {
        sendCommand(["cmd": "setBand", "band": band, "antenna": 1])
    }
    
    func clearErrors() {
        sendCommand(["cmd": "clearErrors"])
    }
    
    func clearDebugLog() {
        DispatchQueue.main.async {
            self.debugLog.removeAll()
        }
    }
    
    // MARK: - REST API Methods
    
    func fetchStatus() async throws -> AmplifierState {
        guard !connectedIP.isEmpty else {
            throw NetworkError.invalidIP
        }
        
        guard let url = URL(string: "http://\(connectedIP)/api/status") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.apiError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NetworkError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        let apiResponse = try JSONDecoder().decode(APIResponse<AmplifierState>.self, from: data)
        
        if apiResponse.success, let state = apiResponse.data {
            return state
        } else {
            throw NetworkError.apiError(apiResponse.error ?? "Unknown error")
        }
    }
    
    func getSystemInfo() async throws -> SystemInfo {
        guard !connectedIP.isEmpty else {
            throw NetworkError.invalidIP
        }
        
        guard let url = URL(string: "http://\(connectedIP)/api/system") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.apiError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NetworkError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        let apiResponse = try JSONDecoder().decode(APIResponse<SystemInfo>.self, from: data)
        
        if apiResponse.success, let info = apiResponse.data {
            return info
        } else {
            throw NetworkError.apiError(apiResponse.error ?? "Unknown error")
        }
    }
    
    func configureWiFi(ssid: String, password: String) async throws {
        guard !connectedIP.isEmpty else {
            throw NetworkError.invalidIP
        }
        
        guard let url = URL(string: "http://\(connectedIP)/api/wifi") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        
        let body = ["ssid": ssid, "password": password]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.apiError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NetworkError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        let apiResponse = try JSONDecoder().decode(APIResponse<EmptyResponse>.self, from: data)
        
        if !apiResponse.success {
            throw NetworkError.apiError(apiResponse.error ?? "WiFi configuration failed")
        }
    }
}

// MARK: - Data Models

struct AmplifierState: Codable {
    var connected: Bool = false
    var mode: String = "N/A"
    var modeCode: Int = 0
    var band: String = "N/A"
    var bandCode: Int = 0
    var antenna: Int = 1
    var isTx: Bool = false
    var forwardPower: Double = 0.0
    var reflectedPower: Double = 0.0
    var swr: Double = 1.0
    var temperature: Double = 0.0
    var inputPower: Double = 0.0
    var current: Double = 0.0
    var frequency: Int = 0
    var fanSpeed: Int = 0
    var hvVoltage: Int = 0
    var vcc5: Int = 0
    var vcc26: Int = 0
    var pdcPower: Double = 0.0
    var disPower: Double = 0.0
    var lpfChannel: Int = 0
    var errorCode: Int = 0
    var errorParam: Int = 0
    var errors: [Int] = []  // Changed to [Int] to match ESP32 output
    var serialNumber: String = "Unknown"
    var lastUpdate: Int = 0
    var msgCount: Int = 0
    
    // Custom decoding to handle missing fields gracefully and apply scaling
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        connected = (try? container.decode(Bool.self, forKey: .connected)) ?? false
        mode = (try? container.decode(String.self, forKey: .mode)) ?? "N/A"
        modeCode = (try? container.decode(Int.self, forKey: .modeCode)) ?? 0
        band = (try? container.decode(String.self, forKey: .band)) ?? "N/A"
        bandCode = (try? container.decode(Int.self, forKey: .bandCode)) ?? 0
        antenna = (try? container.decode(Int.self, forKey: .antenna)) ?? 1
        isTx = (try? container.decode(Bool.self, forKey: .isTx)) ?? false
        forwardPower = (try? container.decode(Double.self, forKey: .forwardPower)) ?? 0.0
        reflectedPower = (try? container.decode(Double.self, forKey: .reflectedPower)) ?? 0.0
        
        // SWR comes as 100x (e.g., 130 = 1.30:1), so divide by 100
        let rawSwr = (try? container.decode(Double.self, forKey: .swr)) ?? 100.0
        swr = rawSwr / 100.0
        
        // Temperature comes in Kelvin, convert to Celsius
        let rawTemp = (try? container.decode(Double.self, forKey: .temperature)) ?? 273.0
        temperature = rawTemp - 273.0
        
        // Input power comes as 10x W (e.g., 253 = 25.3W), so divide by 10
        let rawInputPower = (try? container.decode(Double.self, forKey: .inputPower)) ?? 0.0
        inputPower = rawInputPower / 10.0
        
        // Current comes in mA, convert to A
        let rawCurrent = (try? container.decode(Double.self, forKey: .current)) ?? 0.0
        current = rawCurrent / 1000.0
        
        frequency = (try? container.decode(Int.self, forKey: .frequency)) ?? 0
        fanSpeed = (try? container.decode(Int.self, forKey: .fanSpeed)) ?? 0
        
        // HV voltage comes as 10x V, so divide by 10
        let rawHV = (try? container.decode(Int.self, forKey: .hvVoltage)) ?? 0
        hvVoltage = rawHV / 10
        
        vcc5 = (try? container.decode(Int.self, forKey: .vcc5)) ?? 0
        vcc26 = (try? container.decode(Int.self, forKey: .vcc26)) ?? 0
        pdcPower = (try? container.decode(Double.self, forKey: .pdcPower)) ?? 0.0
        disPower = (try? container.decode(Double.self, forKey: .disPower)) ?? 0.0
        lpfChannel = (try? container.decode(Int.self, forKey: .lpfChannel)) ?? 0
        errorCode = (try? container.decode(Int.self, forKey: .errorCode)) ?? 0
        errorParam = (try? container.decode(Int.self, forKey: .errorParam)) ?? 0
        errors = (try? container.decode([Int].self, forKey: .errors)) ?? []
        serialNumber = (try? container.decode(String.self, forKey: .serialNumber)) ?? "Unknown"
        lastUpdate = (try? container.decode(Int.self, forKey: .lastUpdate)) ?? 0
        msgCount = (try? container.decode(Int.self, forKey: .msgCount)) ?? 0
    }
    
    init() {
        // Default initializer
    }
    
    private enum CodingKeys: String, CodingKey {
        case connected, mode, modeCode, band, bandCode, antenna, isTx
        case forwardPower, reflectedPower, swr, temperature, inputPower, current
        case frequency, fanSpeed, hvVoltage, vcc5, vcc26, pdcPower, disPower
        case lpfChannel, errorCode, errorParam, errors, serialNumber, lastUpdate, msgCount
    }
}

struct SystemInfo: Codable {
    let chipModel: String
    let chipRevision: Int
    let cpuFreqMHz: Int
    let flashSize: Int
    let freeHeap: Int
    let psramSize: Int
    let psramFree: Int
    let uptime: Int
    let wifiMode: String
    let wifiSSID: String
    let ipAddress: String
    let rssi: Int
    let performance: PerformanceInfo
}

struct PerformanceInfo: Codable {
    let wsUpdateCount: Int
    let sseUpdateCount: Int
    let serialRxCount: Int
    let wsClients: Int
    let sseClients: Int
}

struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let timestamp: Int?
    let data: T?
    let error: String?
}

struct EmptyResponse: Codable {}

enum NetworkError: Error, LocalizedError {
    case invalidIP
    case invalidURL
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidIP:
            return "Invalid IP address"
        case .invalidURL:
            return "Invalid URL"
        case .apiError(let message):
            return message
        }
    }
}

// MARK: - Band Selection Helper

struct BandSelection {
    let code: Int
    let name: String
    
    // Band codes match ESP32: 1=160m, 2=80/60m, 3=40m, 4=30m, 5=20m, 6=17m, 7=15m, 8=12m, 9=10m, 10=6m
    static let allBands = [
        BandSelection(code: 1, name: "160m"),
        BandSelection(code: 2, name: "80/60m"),
        BandSelection(code: 3, name: "40m"),
        BandSelection(code: 4, name: "30m"),
        BandSelection(code: 5, name: "20m"),
        BandSelection(code: 6, name: "17m"),
        BandSelection(code: 7, name: "15m"),
        BandSelection(code: 8, name: "12m"),
        BandSelection(code: 9, name: "10m"),
        BandSelection(code: 10, name: "6m")
    ]
}
