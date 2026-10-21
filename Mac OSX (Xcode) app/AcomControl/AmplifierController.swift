//
//  AmplifierController.swift
//  AcomControl
//

import Foundation
import Combine
import Network
import SwiftUI

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    /// Reconnection was abandoned after exhausting the retry budget.
    case failed(String)

    var isConnected: Bool { self == .connected }

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting:   return "Connecting…"
        case .connected:    return "Connected"
        case .failed:       return "Connection failed"
        }
    }

    var color: Color {
        switch self {
        case .disconnected: return .secondary
        case .connecting:   return .orange
        case .connected:    return .green
        case .failed:       return .red
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let message: String
    let isError: Bool
    let isSuccess: Bool
}

@MainActor
final class AmplifierController: ObservableObject {

    // MARK: Published state

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var amplifierState = AmplifierState()
    @Published private(set) var connectedHost = ""
    @Published private(set) var debugLog: [LogEntry] = []

    /// Rolling telemetry for the sparklines and history window.
    @Published private(set) var history: [TelemetrySample] = []
    @Published private(set) var stats = SessionStats()

    /// Peak-hold values, reset with the session.
    @Published private(set) var peakForward: Double = 0
    @Published private(set) var peakSWR: Double = 1.0
    @Published private(set) var peakTemperature: Double = 0

    @Published var lastCommandError: String?

    /// Set when the controller answered 401. The UI prompts for credentials.
    @Published var needsCredentials = false

    /// Controller diagnostics, refreshed in the background while connected so
    /// the UI can report things like "this controller has no password".
    @Published private(set) var systemInfo: SystemInfo?

    let devices = DeviceStore()

    // MARK: Configuration

    /// 10 Hz telemetry for ~30 minutes.
    private let historyLimit = 18_000
    /// Samples are trimmed in blocks rather than one at a time: removeFirst(1)
    /// on a full 18,000-element array shifts the whole array on every frame,
    /// which at 10 Hz is ~180,000 element moves a second. Trimming a block
    /// amortises that to a copy every 200 seconds.
    private let historyTrimBlock = 2_000
    private let maxLogEntries = 300
    private let maxReconnectAttempts = 10
    private let reconnectDelay: TimeInterval = 2.0

    // MARK: Private state

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var pathMonitor: NWPathMonitor?

    private var reconnectTimer: Timer?
    private var pingTimer: Timer?
    private var systemInfoTimer: Timer?
    private var connectionTimeoutWork: DispatchWorkItem?
    private var reconnectAttempts = 0
    private var connectionGeneration = 0

    private var lastSampleAt = Date()
    private var wasTransmitting = false

    /// Receive logging is rate limited. The previous version logged two lines
    /// per frame at 10 Hz, which filled a 50 entry buffer in 2.5 seconds and
    /// pushed every real error out of view.
    private var framesSinceLastLog = 0
    private var lastFrameLogAt = Date.distantPast

    private let notifications = NotificationManager()

    // MARK: Lifecycle

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        urlSession = URLSession(configuration: configuration)

        startNetworkMonitoring()
        notifications.requestAuthorizationIfNeeded()
        FaultCatalog.reload()

        log("AcomControl ready")

        // v1.0 loaded the last address and then deliberately never used it.
        if let host = devices.autoConnectHost, !host.isEmpty {
            log("Auto-connecting to \(host)")
            connect(to: host)
        }
    }

    deinit {
        pingTimer?.invalidate()
        systemInfoTimer?.invalidate()
        reconnectTimer?.invalidate()
        pathMonitor?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        urlSession?.invalidateAndCancel()
    }

    private func startNetworkMonitoring() {
        // Touching NWPathMonitor is what prompts macOS for local network access.
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                if path.status != .satisfied {
                    self.log("Network unavailable", isError: true)
                }
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        pathMonitor = monitor
    }

    // MARK: Logging

    private func log(_ message: String, isError: Bool = false, isSuccess: Bool = false) {
        #if DEBUG
        print("[AcomControl] \(message)")
        #endif
        debugLog.append(LogEntry(date: Date(), message: message,
                                 isError: isError, isSuccess: isSuccess))
        if debugLog.count > maxLogEntries {
            debugLog.removeFirst(debugLog.count - maxLogEntries)
        }
    }

    func clearDebugLog() { debugLog.removeAll() }

    var debugLogText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return debugLog.map { "[\(formatter.string(from: $0.date))] \($0.message)" }
            .joined(separator: "\n")
    }

    // MARK: Connection

    func connect(to host: String) {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }

        cleanupConnection()
        connectionGeneration += 1
        let generation = connectionGeneration

        connectedHost = target
        devices.autoConnectHost = target
        devices.remember(host: target)
        connectionState = .connecting
        lastCommandError = nil

        guard let url = URL(string: "ws://\(target)/ws"), let session = urlSession else {
            log("Invalid controller address: \(target)", isError: true)
            connectionState = .failed("“\(target)” is not a valid address")
            return
        }

        log("Connecting to \(target)…")
        // Firmware 7.0 can require a password on the WebSocket upgrade as well
        // as the REST API, so the task is built from a request, not a bare URL.
        var request = URLRequest(url: url)
        if let header = CredentialStore.credentials(for: target)?.basicAuthHeader {
            request.setValue(header, forHTTPHeaderField: "Authorization")
        }
        let task = session.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        receiveMessage(generation: generation)
        startPingTimer()

        // Give the handshake a bounded amount of time.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.connectionGeneration == generation else { return }
            if self.connectionState == .connecting {
                self.log("Connection timed out after 10 s", isError: true)
                self.handleDisconnection(generation: generation, reason: "Timed out")
            }
        }
        connectionTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    /// Reconnect to the current host, resetting the retry budget.
    func retry() {
        guard !connectedHost.isEmpty else { return }
        reconnectAttempts = 0
        connect(to: connectedHost)
    }

    func disconnect() {
        log("Disconnecting")
        connectionGeneration += 1
        cleanupConnection()
        reconnectAttempts = 0
        connectionState = .disconnected
        devices.autoConnectHost = nil
    }

    private func cleanupConnection() {
        connectionTimeoutWork?.cancel()
        connectionTimeoutWork = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        pingTimer?.invalidate()
        pingTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        systemInfoTimer?.invalidate()
        systemInfoTimer = nil
    }

    private func receiveMessage(generation: Int) {
        guard let task = webSocketTask else { return }

        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.connectionGeneration == generation else { return }

                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    self.receiveMessage(generation: generation)

                case .failure(let error):
                    // A controller with a password set rejects the upgrade with
                    // 401, which surfaces here as an opaque socket error. Say
                    // what it actually is so the UI can ask for the password.
                    if let http = task.response as? HTTPURLResponse, http.statusCode == 401 {
                        self.needsCredentials = true
                        self.log("The controller requires a password", isError: true)
                        self.cleanupConnection()
                        self.connectionState = .failed("This controller requires a password")
                        return
                    }
                    self.log("Receive failed: \(error.localizedDescription)", isError: true)
                    self.handleDisconnection(generation: generation,
                                             reason: error.localizedDescription)
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        // The controller replies to a rejected command with an error envelope
        // rather than a state frame.
        if text.contains("\"success\"") ,
           let envelope = try? JSONDecoder().decode(APIResponse<EmptyResponse>.self, from: data),
           envelope.success == false {
            let message = envelope.error ?? "Command rejected"
            log("Controller rejected command: \(message)", isError: true)
            lastCommandError = message
            return
        }

        guard let state = try? JSONDecoder().decode(AmplifierState.self, from: data) else {
            log("Could not decode telemetry frame", isError: true)
            return
        }

        if connectionState != .connected {
            connectionState = .connected
            reconnectAttempts = 0
            connectionTimeoutWork?.cancel()
            log("Connected — receiving telemetry", isSuccess: true)
            devices.remember(host: connectedHost, serialNumber: state.serialNumber)
            startSystemInfoTimer()
        }

        // One summary line per 10 s instead of two lines per frame.
        framesSinceLastLog += 1
        if Date().timeIntervalSince(lastFrameLogAt) >= 10 {
            log("Telemetry healthy (\(framesSinceLastLog) frames in the last 10 s)")
            framesSinceLastLog = 0
            lastFrameLogAt = Date()
        }

        ingest(state)
    }

    private func ingest(_ state: AmplifierState) {
        let now = Date()
        let interval = min(now.timeIntervalSince(lastSampleAt), 1.0)
        lastSampleAt = now

        let previous = amplifierState
        amplifierState = state

        stats.ingest(state, wasTx: wasTransmitting, interval: interval)
        wasTransmitting = state.isTx

        peakForward = max(peakForward, state.forwardPower)
        peakTemperature = max(peakTemperature, state.temperature)
        if state.isTx { peakSWR = max(peakSWR, state.swr) }

        history.append(TelemetrySample(date: now, state: state))
        if history.count > historyLimit + historyTrimBlock {
            history.removeFirst(history.count - historyLimit)
        }

        notifications.evaluate(state: state, previous: previous)
    }

    /// Folds telemetry the controller recorded before this app connected into
    /// the session history, keeping everything ordered by time.
    ///
    /// v2.0 fetched this and threw it away: `HistoryView` awaited the request,
    /// reported how many samples came back, and then had nowhere to put them.
    /// Returns the number of samples actually added.
    @discardableResult
    func mergeHistory(_ imported: [TelemetrySample]) -> Int {
        guard !imported.isEmpty else { return 0 }

        // Controller samples are anchored to its own uptime clock, so a second
        // import of an overlapping window would duplicate points. Keep only
        // samples older than everything we recorded ourselves.
        let oldestLocal = history.first?.date ?? Date.distantFuture
        let fresh = imported.filter { $0.date < oldestLocal }
        guard !fresh.isEmpty else { return 0 }

        history.insert(contentsOf: fresh.sorted { $0.date < $1.date }, at: 0)
        if history.count > historyLimit + historyTrimBlock {
            history.removeFirst(history.count - historyLimit)
        }
        log("Loaded \(fresh.count) samples recorded by the controller", isSuccess: true)
        return fresh.count
    }

    private func handleDisconnection(generation: Int, reason: String) {
        guard connectionGeneration == generation else { return }
        guard connectionState != .disconnected else { return }

        cleanupConnection()

        guard reconnectAttempts < maxReconnectAttempts, !connectedHost.isEmpty else {
            let message = "Gave up after \(maxReconnectAttempts) attempts. \(reason)"
            log(message, isError: true)
            connectionState = .failed(message)
            notifications.notifyDisconnected(host: connectedHost)
            return
        }

        connectionState = .connecting
        reconnectAttempts += 1
        let delay = min(reconnectDelay * Double(reconnectAttempts), 30.0)
        log("Reconnecting in \(Int(delay)) s (attempt \(reconnectAttempts)/\(maxReconnectAttempts))")

        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.connectionGeneration == generation else { return }
                self.connect(to: self.connectedHost)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        reconnectTimer = timer
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        // scheduledTimer already installs on the current run loop; adding it a
        // second time (as v1.0 did) is redundant.
        let timer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendPing() }
        }
        pingTimer = timer
    }

    /// Polls /api/system so the UI can show controller diagnostics and warn
    /// when the controller is left unauthenticated.
    private func startSystemInfoTimer() {
        systemInfoTimer?.invalidate()
        refreshSystemInfo()
        let timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshSystemInfo() }
        }
        systemInfoTimer = timer
    }

    private func refreshSystemInfo() {
        Task { @MainActor in
            systemInfo = try? await getSystemInfo()
        }
    }

    private func sendPing() {
        guard let task = webSocketTask else { return }
        let generation = connectionGeneration
        task.sendPing { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.log("Ping failed: \(error.localizedDescription)", isError: true)
                self?.handleDisconnection(generation: generation,
                                          reason: error.localizedDescription)
            }
        }
    }

    // MARK: Session

    func resetSession() {
        history.removeAll()
        stats.reset()
        peakForward = 0
        peakSWR = 1.0
        peakTemperature = 0
        log("Session statistics reset")
    }

    /// Telemetry from the last `window` seconds, for the sparklines.
    ///
    /// Binary search, not `firstIndex(where:)`. The samples are in time order
    /// and the cutoff is near the END of the array, so a linear scan from the
    /// front walked almost the whole history — on every SwiftUI body evaluation,
    /// for three gauges, ten times a second.
    func recentSamples(seconds window: TimeInterval) -> [TelemetrySample] {
        let cutoff = Date().addingTimeInterval(-window)
        var low = 0, high = history.count
        while low < high {
            let mid = low + (high - low) / 2
            if history[mid].date < cutoff { low = mid + 1 } else { high = mid }
        }
        guard low < history.count else { return [] }
        return Array(history[low...])
    }

    // MARK: Commands

    private func send(_ command: [String: Any]) {
        guard connectionState.isConnected, let task = webSocketTask else {
            lastCommandError = "Not connected to a controller"
            log("Command dropped — not connected", isError: true)
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: command),
              let json = String(data: data, encoding: .utf8) else { return }

        task.send(.string(json)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.log("Send failed: \(error.localizedDescription)", isError: true)
                self?.lastCommandError = error.localizedDescription
            }
        }
    }

    /// `force` carries the operator's confirmation to the controller, which
    /// otherwise refuses to cut the supply mid-transmission.
    func setMode(_ mode: AmplifierMode, force: Bool = false) {
        log("Requesting mode \(mode.title)")
        send(["cmd": "setMode", "mode": mode.rawValue, "force": force])
    }

    /// Band changes keep the currently selected antenna. v1.0 hardcoded
    /// antenna 1 on every band button, silently overriding the operator.
    ///
    /// `force` is the operator's answer to the hot-switching confirmation: the
    /// controller refuses band changes under RF without it.
    func setBand(_ code: Int, antenna: Int? = nil, force: Bool = false) {
        let ant = antenna ?? max(1, amplifierState.antenna)
        log("Requesting band \(BandSelection.name(for: code)) on antenna \(ant)")
        send(["cmd": "setBand", "band": code, "antenna": ant, "force": force])
    }

    func setAntenna(_ antenna: Int, force: Bool = false) {
        guard amplifierState.bandCode > 0 else {
            lastCommandError = "No band is selected yet"
            return
        }
        log("Requesting antenna \(antenna)")
        send(["cmd": "setAntenna", "antenna": antenna,
              "band": amplifierState.bandCode, "force": force])
    }

    func clearErrors() {
        log("Clearing soft faults")
        send(["cmd": "clearErrors"])
    }

    func requestInfo() {
        send(["cmd": "requestInfo"])
    }

    /// Feeds a transceiver frequency to the controller for automatic band following.
    func reportFrequency(kHz: Int) {
        send(["cmd": "setFrequency", "frequency": kHz])
    }

    // MARK: REST

    private func url(_ path: String) throws -> URL {
        guard !connectedHost.isEmpty else { throw NetworkError.notConnected }
        guard let url = URL(string: "http://\(connectedHost)\(path)") else {
            throw NetworkError.invalidURL
        }
        return url
    }

    /// Builds a request against the connected controller, carrying credentials
    /// when any are stored for it.
    private func request(_ path: String, timeout: TimeInterval) throws -> URLRequest {
        var request = URLRequest(url: try url(path))
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        if let header = CredentialStore.credentials(for: connectedHost)?.basicAuthHeader {
            request.setValue(header, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Notes a 401 so the UI can ask for a password, and reports it as an error.
    private func authFailure() -> NetworkError {
        needsCredentials = true
        return .apiError("The controller requires a password")
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type,
                                   timeout: TimeInterval = 5) async throws -> T {
        // The session configured in init(), not URLSession.shared: that is where
        // the cache policy and the timeouts for this app live.
        guard let session = urlSession else { throw NetworkError.notConnected }
        let (data, response) = try await session.data(for: try request(path, timeout: timeout))
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.apiError("Invalid response")
        }
        if http.statusCode == 401 { throw authFailure() }
        guard http.statusCode == 200 else {
            throw NetworkError.apiError("HTTP \(http.statusCode)")
        }
        needsCredentials = false
        return try APIDecoder.payload(type, from: data)
    }

    @discardableResult
    private func post(_ path: String, body: [String: Any],
                      timeout: TimeInterval = 10) async throws -> Data {
        guard let session = urlSession else { throw NetworkError.notConnected }
        var request = try request(path, timeout: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.apiError("Invalid response")
        }
        if http.statusCode == 401 { throw authFailure() }
        if let envelope = try? JSONDecoder().decode(APIResponse<EmptyResponse>.self, from: data),
           !envelope.success {
            throw NetworkError.apiError(envelope.error ?? "Request failed")
        }
        guard (200...299).contains(http.statusCode) else {
            throw NetworkError.apiError("HTTP \(http.statusCode)")
        }
        needsCredentials = false
        return data
    }

    // MARK: Credentials

    var storedCredentials: ControllerCredentials? {
        CredentialStore.credentials(for: connectedHost)
    }

    /// Saves credentials for the connected controller and reconnects with them.
    func setCredentials(user: String, password: String) {
        guard !connectedHost.isEmpty else { return }
        if password.isEmpty {
            CredentialStore.remove(for: connectedHost)
            log("Cleared the saved password for \(connectedHost)")
        } else {
            CredentialStore.save(ControllerCredentials(user: user, password: password),
                                 for: connectedHost)
            log("Saved a password for \(connectedHost)")
        }
        needsCredentials = false
        retry()
    }

    func fetchStatus() async throws -> AmplifierState {
        try await get("/api/status", as: AmplifierState.self)
    }

    func getSystemInfo() async throws -> SystemInfo {
        try await get("/api/system", as: SystemInfo.self)
    }

    func getConfig() async throws -> ControllerConfig {
        try await get("/api/config", as: ControllerConfig.self)
    }

    func setConfig(autoBandFollow: Bool? = nil,
                   logging: Bool? = nil,
                   hostname: String? = nil,
                   apiUser: String? = nil,
                   apiPassword: String? = nil,
                   apPassword: String? = nil) async throws {
        var body: [String: Any] = [:]
        if let autoBandFollow { body["autoBandFollow"] = autoBandFollow }
        if let logging { body["logging"] = logging }
        if let hostname { body["hostname"] = hostname }
        if let apiUser { body["apiUser"] = apiUser }
        if let apiPassword { body["apiPassword"] = apiPassword }
        if let apPassword { body["apPassword"] = apPassword }
        guard !body.isEmpty else { return }
        try await post("/api/config", body: body)

        // Keep the keychain in step: changing the controller's password without
        // updating ours would lock the app out at the next reconnect.
        if let apiPassword {
            setCredentials(user: apiUser ?? storedCredentials?.user ?? "acom",
                           password: apiPassword)
        }
    }

    func configureWiFi(ssid: String, password: String) async throws {
        try await post("/api/wifi", body: ["ssid": ssid, "password": password])
    }

    /// Fetches the telemetry the controller recorded before the app connected
    /// and folds it into the session history. Returns the number added.
    @discardableResult
    func importDeviceHistory(points: Int = 600) async throws -> Int {
        mergeHistory(try await fetchDeviceHistory(points: points))
    }

    /// Telemetry recorded by the controller itself, covering time before the
    /// app connected.
    func fetchDeviceHistory(points: Int = 600) async throws -> [TelemetrySample] {
        struct HistoryPayload: Decodable {
            let samples: [[Double]]
        }
        let payload = try await get("/api/history?points=\(points)",
                                    as: HistoryPayload.self, timeout: 15)

        // fields: [t, forwardPower, reflectedPower, swr, temperature, current, frequency, band, tx]
        let now = Date()
        guard let newest = payload.samples.last?.first else { return [] }

        return payload.samples.compactMap { row in
            guard row.count >= 9 else { return nil }
            var state = AmplifierState()
            state.forwardPower = row[1]
            state.reflectedPower = row[2]
            state.swr = row[3] / 100.0
            state.temperature = row[4] - 273.0
            state.current = row[5] / 1000.0
            state.frequency = Int(row[6])
            state.bandCode = Int(row[7])
            state.isTx = row[8] != 0
            // Controller timestamps are uptime milliseconds; anchor the newest
            // sample to now and work backwards.
            let age = (newest - row[0]) / 1000.0
            return TelemetrySample(date: now.addingTimeInterval(-age), state: state)
        }
    }

    /// Downloads the controller's CSV session log through the authenticated
    /// session. Handing the URL to a browser instead would make the operator
    /// re-enter the controller's password there once one is set.
    func downloadDeviceLog() async throws -> Data {
        guard let session = urlSession else { throw NetworkError.notConnected }
        let (data, response) = try await session.data(
            for: try request("/api/history/download", timeout: 30))
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.apiError("Invalid response")
        }
        if http.statusCode == 401 { throw authFailure() }
        if http.statusCode == 404 {
            throw NetworkError.apiError("The controller has no session log yet")
        }
        guard http.statusCode == 200 else {
            throw NetworkError.apiError("HTTP \(http.statusCode)")
        }
        return data
    }

    func clearDeviceHistory() async throws {
        try await post("/api/history/clear", body: [:])
    }
}
