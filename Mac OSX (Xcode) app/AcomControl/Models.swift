//
//  Models.swift
//  AcomControl
//
//  Wire formats, telemetry history, session statistics and fault decoding.
//

import Foundation
import SwiftUI

// MARK: - API envelope

/// Documented response shape: `{success, timestamp, data, error}`.
///
/// `success` tolerates absence so that a controller still running firmware
/// v5.0 (which returned a bare object) degrades gracefully instead of failing
/// outright — that mismatch is what made network discovery find nothing.
struct APIResponse<T: Decodable>: Decodable {
    let success: Bool
    let timestamp: Int?
    let data: T?
    let error: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? container.decode(Bool.self, forKey: .success)) ?? true
        timestamp = try? container.decode(Int.self, forKey: .timestamp)
        data = try? container.decode(T.self, forKey: .data)
        error = try? container.decode(String.self, forKey: .error)
    }

    private enum CodingKeys: String, CodingKey {
        case success, timestamp, data, error
    }
}

struct EmptyResponse: Decodable {}

enum APIDecoder {
    /// Decodes the documented envelope, falling back to a bare object so the
    /// app interoperates with both firmware v6.0 and the older v5.0 format.
    static func payload<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if let envelope = try? JSONDecoder().decode(APIResponse<T>.self, from: data) {
            if let payload = envelope.data { return payload }
            if !envelope.success { throw NetworkError.apiError(envelope.error ?? "Request failed") }
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum NetworkError: Error, LocalizedError {
    case invalidIP
    case invalidURL
    case apiError(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidIP:            return "Invalid IP address"
        case .invalidURL:           return "Invalid URL"
        case .notConnected:         return "Not connected to a controller"
        case .apiError(let message): return message
        }
    }
}

// MARK: - Amplifier state

/// Live amplifier telemetry.
///
/// The controller transmits raw amplifier units (SWR ×100, temperature in
/// Kelvin, drive power ×10, current in mA, HV ×10). Scaling happens here.
///
/// Decodable, not Codable: the decoder below rescales as it reads, so a
/// synthesised `encode(to:)` would write the *scaled* values back under the
/// same keys and a round trip would scale twice.
struct AmplifierState: Decodable, Equatable {
    var connected: Bool = false
    var mode: String = "N/A"
    var modeCode: Int = 0
    var band: String = "---"
    var bandCode: Int = 0
    var antenna: Int = 1
    var antennaType: Int = 0
    var isTx: Bool = false

    var forwardPower: Double = 0.0      // W
    var reflectedPower: Double = 0.0    // W
    var swr: Double = 1.0               // ratio :1
    var temperature: Double = 0.0       // °C
    var inputPower: Double = 0.0        // W
    var current: Double = 0.0           // A
    var frequency: Int = 0              // kHz
    var fanSpeed: Int = 0               // percent
    var fanLevel: Int = 0               // raw 0...fanLevelMax
    var fanLevelMax: Int = 4            // telemetry byte 69 gives 0...4
    var hvVoltage: Double = 0.0         // V
    var vcc5: Double = 0.0              // V
    var vcc26: Double = 0.0             // V
    var pdcPower: Double = 0.0          // W
    var disPower: Double = 0.0          // W
    var lpfChannel: Int = 0

    var errorCode: Int = 0
    var errorParam: Int = 0
    /// Severity the amplifier itself reports for `errorCode`, from telemetry
    /// byte 70. Empty when there is no live fault.
    var errorSeverity: String = ""
    var errorIsHardFault: Bool = false
    /// Fault code numbers, already decoded from the message 0x21 bitfield by
    /// the controller. v6.0's firmware sent the raw bitmask words instead.
    var errors: [Int] = []

    var serialNumber: String = "Unknown"
    var lastUpdate: Int = 0
    var msgCount: Int = 0
    var autoBandFollow: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ key: CodingKeys, _ fallback: Int = 0) -> Int {
            (try? c.decode(Int.self, forKey: key)) ?? fallback
        }
        func dbl(_ key: CodingKeys, _ fallback: Double = 0) -> Double {
            (try? c.decode(Double.self, forKey: key)) ?? fallback
        }

        connected      = (try? c.decode(Bool.self, forKey: .connected)) ?? false
        mode           = (try? c.decode(String.self, forKey: .mode)) ?? "N/A"
        modeCode       = int(.modeCode)
        band           = (try? c.decode(String.self, forKey: .band)) ?? "---"
        bandCode       = int(.bandCode)
        antenna        = int(.antenna, 1)
        antennaType    = int(.antennaType)
        isTx           = (try? c.decode(Bool.self, forKey: .isTx)) ?? false

        forwardPower   = dbl(.forwardPower)
        reflectedPower = dbl(.reflectedPower)
        swr            = dbl(.swr, 100) / 100.0            // ×100 → ratio
        temperature    = dbl(.temperature, 273) - 273.0    // Kelvin → °C
        inputPower     = dbl(.inputPower) / 10.0           // ×10 W → W
        current        = dbl(.current) / 1000.0            // mA → A
        frequency      = int(.frequency)
        fanSpeed       = int(.fanSpeed)
        fanLevel       = int(.fanLevel)
        fanLevelMax    = max(1, int(.fanLevelMax, 4))
        hvVoltage      = dbl(.hvVoltage) / 10.0            // ×10 V → V
        vcc5           = dbl(.vcc5) / 1000.0               // mV → V
        vcc26          = dbl(.vcc26) / 10.0                // ×10 V → V
        pdcPower       = dbl(.pdcPower) / 10.0             // ×10 W → W
        disPower       = dbl(.disPower) / 10.0             // ×10 W → W
        lpfChannel     = int(.lpfChannel)

        errorCode      = int(.errorCode)
        errorParam     = int(.errorParam)
        errorSeverity  = (try? c.decode(String.self, forKey: .errorSeverity)) ?? ""
        errorIsHardFault = (try? c.decode(Bool.self, forKey: .errorIsHardFault)) ?? false
        errors         = (try? c.decode([Int].self, forKey: .errors)) ?? []

        serialNumber   = (try? c.decode(String.self, forKey: .serialNumber)) ?? "Unknown"
        lastUpdate     = int(.lastUpdate)
        msgCount       = int(.msgCount)
        autoBandFollow = (try? c.decode(Bool.self, forKey: .autoBandFollow)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case connected, mode, modeCode, band, bandCode, antenna, antennaType, isTx
        case forwardPower, reflectedPower, swr, temperature, inputPower, current
        case frequency, fanSpeed, fanLevel, fanLevelMax, hvVoltage, vcc5, vcc26
        case pdcPower, disPower, lpfChannel, errorCode, errorParam, errorSeverity
        case errorIsHardFault, errors, serialNumber, lastUpdate
        case msgCount, autoBandFollow
    }

    /// Frequency rendered the way operators read it.
    var frequencyDisplay: String {
        guard frequency > 0 else { return "—" }
        return String(format: "%.3f MHz", Double(frequency) / 1000.0)
    }

    var hasFault: Bool { errorCode != 0 || !errors.isEmpty }
}

// MARK: - System information

/// Controller (not amplifier) diagnostics.
///
/// Every field is optional-tolerant: a decode failure here used to abort the
/// whole discovery scan, so a firmware that omits one key must not hide the
/// device.
struct SystemInfo: Decodable {
    var chipModel: String = "Unknown"
    var chipRevision: Int = 0
    var cpuFreqMHz: Int = 0
    var flashSize: Int = 0
    var freeHeap: Int = 0
    var heapSize: Int = 0
    var psramSize: Int = 0
    var psramFree: Int = 0
    var uptime: Int = 0                 // milliseconds
    var wifiMode: String = "—"
    var wifiSSID: String = "—"
    var ipAddress: String = ""
    var rssi: Int = 0
    var hostname: String = ""
    var firmwareVersion: String = "—"
    var autoBandFollow: Bool = false
    var loggingEnabled: Bool = false
    var historyCount: Int = 0
    var historyCapacity: Int = 0
    var logBytes: Int = 0
    /// True only while the amplifier is genuinely streaming telemetry. The v6.0
    /// firmware reported this as true from boot regardless.
    var telemetryEnabled: Bool = false
    /// Whether the controller requires a password, and whether its setup access
    /// point is open. Both default to the safe-looking value so that an older
    /// firmware that omits them is not reported as insecure.
    var authEnabled: Bool = true
    var apOpen: Bool = false
    var performance: PerformanceInfo = PerformanceInfo()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func str(_ k: CodingKeys, _ f: String) -> String { (try? c.decode(String.self, forKey: k)) ?? f }
        func int(_ k: CodingKeys, _ f: Int = 0) -> Int { (try? c.decode(Int.self, forKey: k)) ?? f }

        // `chip` is the v5.0 spelling of `chipModel`; accept both.
        chipModel       = (try? c.decode(String.self, forKey: .chipModel))
                       ?? (try? c.decode(String.self, forKey: .chip)) ?? "Unknown"
        chipRevision    = int(.chipRevision)
        cpuFreqMHz      = int(.cpuFreqMHz)
        flashSize       = int(.flashSize)
        freeHeap        = int(.freeHeap)
        heapSize        = int(.heapSize)
        psramSize       = int(.psramSize)
        psramFree       = int(.psramFree)
        uptime          = int(.uptime)
        wifiMode        = str(.wifiMode, "—")
        wifiSSID        = str(.wifiSSID, "—")
        ipAddress       = (try? c.decode(String.self, forKey: .ipAddress))
                       ?? (try? c.decode(String.self, forKey: .ip)) ?? ""
        rssi            = int(.rssi)
        hostname        = str(.hostname, "")
        firmwareVersion = (try? c.decode(String.self, forKey: .firmwareVersion))
                       ?? (try? c.decode(String.self, forKey: .version)) ?? "—"
        autoBandFollow  = (try? c.decode(Bool.self, forKey: .autoBandFollow)) ?? false
        loggingEnabled  = (try? c.decode(Bool.self, forKey: .loggingEnabled)) ?? false
        historyCount    = int(.historyCount)
        historyCapacity = int(.historyCapacity)
        logBytes        = int(.logBytes)
        telemetryEnabled = (try? c.decode(Bool.self, forKey: .telemetryEnabled)) ?? false
        authEnabled     = (try? c.decode(Bool.self, forKey: .authEnabled)) ?? true
        apOpen          = (try? c.decode(Bool.self, forKey: .apOpen)) ?? false
        performance     = (try? c.decode(PerformanceInfo.self, forKey: .performance)) ?? PerformanceInfo()
    }

    private enum CodingKeys: String, CodingKey {
        case chipModel, chip, chipRevision, cpuFreqMHz, flashSize, freeHeap, heapSize
        case psramSize, psramFree, uptime, wifiMode, wifiSSID, ipAddress, ip, rssi
        case hostname, firmwareVersion, version, autoBandFollow, loggingEnabled
        case historyCount, historyCapacity, logBytes, telemetryEnabled
        case authEnabled, apOpen, performance
    }
}

struct PerformanceInfo: Decodable {
    var wsUpdateCount: Int = 0
    var sseUpdateCount: Int = 0
    var serialRxCount: Int = 0
    var wsClients: Int = 0
    var sseClients: Int = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ k: CodingKeys) -> Int { (try? c.decode(Int.self, forKey: k)) ?? 0 }
        wsUpdateCount = int(.wsUpdateCount)
        sseUpdateCount = int(.sseUpdateCount)
        serialRxCount = int(.serialRxCount)
        wsClients = int(.wsClients)
        sseClients = int(.sseClients)
    }

    private enum CodingKeys: String, CodingKey {
        case wsUpdateCount, sseUpdateCount, serialRxCount, wsClients, sseClients
    }
}

/// Runtime controller settings exposed by `/api/config`.
struct ControllerConfig: Decodable {
    var hostname: String = "acomcontrol"
    var autoBandFollow: Bool = false
    var logging: Bool = true
    var otaPasswordSet: Bool = false
    /// The network the controller is configured to JOIN. Firmware 6.0 reported
    /// the controller's own access point name here whenever it was in AP mode,
    /// which is why this app used to special-case the string "AcomControl".
    var wifiSSID: String = ""
    var apMode: Bool = false
    var apSSID: String = "AcomControl"
    var apPassword: String = ""
    var apOpen: Bool = false
    var authEnabled: Bool = true
    var apiUser: String = "acom"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hostname = (try? c.decode(String.self, forKey: .hostname)) ?? "acomcontrol"
        autoBandFollow = (try? c.decode(Bool.self, forKey: .autoBandFollow)) ?? false
        logging = (try? c.decode(Bool.self, forKey: .logging)) ?? true
        otaPasswordSet = (try? c.decode(Bool.self, forKey: .otaPasswordSet)) ?? false
        wifiSSID = (try? c.decode(String.self, forKey: .wifiSSID)) ?? ""
        apMode = (try? c.decode(Bool.self, forKey: .apMode)) ?? false
        apSSID = (try? c.decode(String.self, forKey: .apSSID)) ?? "AcomControl"
        apPassword = (try? c.decode(String.self, forKey: .apPassword)) ?? ""
        apOpen = (try? c.decode(Bool.self, forKey: .apOpen)) ?? false
        authEnabled = (try? c.decode(Bool.self, forKey: .authEnabled)) ?? true
        apiUser = (try? c.decode(String.self, forKey: .apiUser)) ?? "acom"
    }

    private enum CodingKeys: String, CodingKey {
        case hostname, autoBandFollow, logging, otaPasswordSet, wifiSSID
        case apMode, apSSID, apPassword, apOpen, authEnabled, apiUser
    }
}

// MARK: - Bands, modes, antennas

struct BandSelection: Identifiable, Hashable {
    let code: Int
    let name: String
    var id: Int { code }

    /// The one band numbering, shared by the amplifier, the low-pass filter
    /// channel in telemetry byte 69 and the controller. Section 5.1 of the ACOM
    /// RS-232 specification fixes it: command 0x09 takes 0x01...0x0A, and the
    /// command 0x0C relay test names all ten in order.
    ///
    /// 60m has no code of its own — section 3.3.7 byte 13 groups it with 40m —
    /// so band 3 carries both. v2.0 of this app labelled band 2 "80/60m".
    static let allBands: [BandSelection] = [
        .init(code: 1, name: "160m"),  .init(code: 2, name: "80m"),
        .init(code: 3, name: "40/60m"), .init(code: 4, name: "30m"),
        .init(code: 5, name: "20m"),   .init(code: 6, name: "17m"),
        .init(code: 7, name: "15m"),   .init(code: 8, name: "12m"),
        .init(code: 9, name: "10m"),   .init(code: 10, name: "6m")
    ]

    static func name(for code: Int) -> String {
        allBands.first { $0.code == code }?.name ?? "—"
    }

    /// Band a frequency in kHz falls into, or nil when out of amateur range.
    static func code(forFrequencyKHz f: Int) -> Int? {
        switch f {
        case 1800...2000:   return 1
        case 3500...4000:   return 2
        case 5250...5450:   return 3   // 60m shares the 40m low-pass filter
        case 7000...7300:   return 3
        case 10100...10150: return 4
        case 14000...14350: return 5
        case 18068...18168: return 6
        case 21000...21450: return 7
        case 24890...24990: return 8
        case 28000...29700: return 9
        case 50000...54000: return 10
        default:            return nil
        }
    }
}

enum AmplifierMode: Int, CaseIterable, Identifiable {
    case standby = 5
    case operate = 6
    case powerOff = 10

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .standby:  return "Standby"
        case .operate:  return "Operate"
        case .powerOff: return "Power Off"
        }
    }

    var icon: String {
        switch self {
        case .standby:  return "pause.circle.fill"
        case .operate:  return "play.circle.fill"
        case .powerOff: return "power.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .standby:  return .blue
        case .operate:  return .green
        case .powerOff: return .red
        }
    }

    /// Power Off is irreversible from the app's point of view — the amplifier
    /// cannot be woken again over the serial link once its supply is down.
    var needsConfirmation: Bool { self == .powerOff }

    /// True when the reported telemetry mode byte corresponds to this mode.
    func matches(modeCode: Int) -> Bool {
        switch self {
        case .standby:  return modeCode & 0xF0 == 0x50
        case .operate:  return modeCode & 0xF0 == 0x60 || modeCode & 0xF0 == 0x70
        case .powerOff: return modeCode & 0xF0 == 0xA0
        }
    }
}

// MARK: - Fault decoding

/// Fault severity as defined by the ACOM user manual's three protection levels.
enum FaultSeverity {
    case warning     // transmission continues
    case softFault   // reverts to standby
    case hardFault   // supply shuts down
    case unknown

    var label: String {
        switch self {
        case .warning:   return "Warning"
        case .softFault: return "Soft fault"
        case .hardFault: return "Hard fault"
        case .unknown:   return "Fault"
        }
    }

    var color: Color {
        switch self {
        case .warning:  return .orange
        case .unknown:  return .orange
        default:        return .red
        }
    }
}

/// A decoded amplifier fault.
///
/// Names and severities come from `ACOMFaultCodes`, transcribed from section
/// 3.4.1 of the ACOM RS-232 specification. v2.0 of this app claimed that
/// specification was unavailable and asked the operator to supply their own
/// table; it ships with the firmware in this repository.
struct AmplifierFault: Identifiable, Hashable {
    let id: String
    let code: Int
    let parameter: Int?
    let title: String
    let detail: String
    let severity: FaultSeverity
    let isStored: Bool

    var codeText: String { String(format: "0x%02X", code) }
}

/// Optional override for the built-in fault code table.
///
/// The built-in table (`ACOMFaultCodes`) covers every code the specification
/// names. This exists for the handful the specification leaves blank, and for
/// anyone who wants different wording. Drop a JSON file mapping code strings to
/// descriptions at
/// `~/Library/Containers/com.acomcontrol.AcomControl/Data/Library/Application Support/AcomControl/fault-codes.json`
/// (Settings ▸ Alerts ▸ "Reveal Fault Code Table" opens the folder):
///
///     { "0x2A": "My own wording", "0x14": "Something the spec leaves unnamed" }
///
/// Codes may be written as "0x2A", "2A" or "42".
enum FaultCatalog {
    private static var overrides: [Int: String] = [:]
    private static var loaded = false

    static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("AcomControl/fault-codes.json")
    }

    /// Number of codes the app can name: the specification's table plus any
    /// override the operator added for a code it does not cover.
    static var entryCount: Int {
        if !loaded { reload() }
        return Set(ACOMFaultCodes.table.keys).union(overrides.keys).count
    }

    static var overrideCount: Int {
        if !loaded { reload() }
        return overrides.count
    }

    static func reload() {
        loaded = true
        overrides = [:]
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return }

        for (key, value) in raw {
            let trimmed = key.trimmingCharacters(in: .whitespaces).lowercased()
            // The template carries a "_comment" key, which parses as neither.
            let parsed: Int?
            if trimmed.hasPrefix("0x") {
                parsed = Int(trimmed.dropFirst(2), radix: 16)
            } else if let decimal = Int(trimmed) {
                parsed = decimal
            } else {
                parsed = Int(trimmed, radix: 16)
            }
            if let code = parsed { overrides[code] = value }
        }
    }

    /// Text for a code: the operator's wording if they supplied any, otherwise
    /// the specification's. nil only for codes the specification leaves unnamed
    /// and the operator has not named either.
    static func title(for code: Int) -> String? {
        if !loaded { reload() }
        return overrides[code] ?? ACOMFaultCodes.text(for: code)
    }

    /// Creates the folder and a documented starter file if none exists.
    @discardableResult
    static func ensureTemplate() -> URL? {
        guard let url = fileURL else { return nil }
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            let template = """
            {
              "_comment": "Overrides the built-in ACOM fault code table. Codes may be \\"0x2A\\", \\"2A\\" or \\"42\\". Delete this comment key.",
              "0x14": "Reserved - not named in the specification"
            }
            """
            try? template.data(using: .utf8)?.write(to: url)
        }
        return url
    }
}

extension AmplifierState {
    /// Thresholds the amplifier's protection system watches, per the user manual:
    /// reflected power, PA temperature, drain current, drive power and SWR.
    var thresholdViolations: [String] {
        var causes: [String] = []
        if swr >= 2.0 {
            causes.append(String(format: "SWR %.2f:1 is at or above the 2.0 protection threshold", swr))
        }
        if reflectedPower >= 50 {
            causes.append(String(format: "reflected power %.0f W", reflectedPower))
        }
        if temperature >= 70 {
            causes.append(String(format: "PA temperature %.0f °C", temperature))
        }
        if current >= 25 {
            causes.append(String(format: "drain current %.1f A", current))
        }
        if inputPower >= 40 {
            causes.append(String(format: "drive power %.1f W", inputPower))
        }
        if bandCode == 0 && frequency > 0 {
            causes.append("no low-pass filter selected for \(frequencyDisplay)")
        }
        return causes
    }

    /// Severity for the live fault code. The amplifier reports in telemetry
    /// byte 70 whether the code belongs to a hard fault, and the specification
    /// gives a severity for every code it names, so nothing has to be inferred.
    /// v2.0 guessed from whichever telemetry threshold happened to be exceeded.
    private var liveSeverity: FaultSeverity {
        if errorIsHardFault { return .hardFault }
        switch errorSeverity {
        case "hard": return .hardFault
        case "soft": return .softFault
        case "warning": return .warning
        default: return ACOMFaultCodes.severity(for: errorCode)
        }
    }

    /// Active faults, the live code first and then the fault log.
    ///
    /// The log entries are real code numbers: the controller decodes the
    /// message 0x21 bitfield for us. v2.0 received the ten raw bitmask words
    /// and displayed them as codes.
    var faults: [AmplifierFault] {
        var result: [AmplifierFault] = []
        let violations = thresholdViolations

        if errorCode != 0 {
            // Telemetry context is still worth showing, but as context — not as
            // a guess at what the fault means.
            var detail = "Shown on the amplifier's front panel."
            if errorParam != 0 { detail += " Parameter \(errorParam)." }
            if !violations.isEmpty {
                detail += " At this moment: " + violations.joined(separator: "; ") + "."
            }
            result.append(AmplifierFault(
                id: "active-\(errorCode)-\(errorParam)",
                code: errorCode,
                parameter: errorParam == 0 ? nil : errorParam,
                title: FaultCatalog.title(for: errorCode) ?? "Unnamed in the specification",
                detail: detail,
                severity: liveSeverity,
                isStored: false
            ))
        }

        // The log can hold several distinct codes; the live one is already
        // above, so skip it rather than listing it twice.
        for (index, code) in errors.enumerated() where code != errorCode {
            result.append(AmplifierFault(
                id: "stored-\(index)-\(code)",
                code: code,
                parameter: nil,
                title: FaultCatalog.title(for: code) ?? "Unnamed in the specification",
                detail: "Active in the amplifier's fault log.",
                severity: ACOMFaultCodes.severity(for: code),
                isStored: true
            ))
        }
        return result
    }
}

// MARK: - Telemetry history and session statistics

struct TelemetrySample: Identifiable, Equatable {
    /// A monotonic counter rather than a UUID: these are created ten times a
    /// second for the length of a session, and a UUID costs an allocation and
    /// 16 bytes apiece for an identity that never leaves the process.
    private static var nextID: Int = 0
    let id: Int
    let date: Date
    let forwardPower: Double
    let reflectedPower: Double
    let swr: Double
    let temperature: Double
    let current: Double
    let inputPower: Double
    let frequency: Int
    let bandCode: Int
    let isTx: Bool

    @MainActor
    init(date: Date, state: AmplifierState) {
        TelemetrySample.nextID += 1
        self.id = TelemetrySample.nextID
        self.date = date
        self.forwardPower = state.forwardPower
        self.reflectedPower = state.reflectedPower
        self.swr = state.swr
        self.temperature = state.temperature
        self.current = state.current
        self.inputPower = state.inputPower
        self.frequency = state.frequency
        self.bandCode = state.bandCode
        self.isTx = state.isTx
    }

    static func == (lhs: TelemetrySample, rhs: TelemetrySample) -> Bool { lhs.id == rhs.id }
}

/// Rolling statistics for the current operating session.
struct SessionStats: Equatable {
    var startedAt = Date()
    var peakForwardPower: Double = 0
    var peakReflectedPower: Double = 0
    var peakSWR: Double = 1.0
    var peakTemperature: Double = 0
    var peakCurrent: Double = 0
    var transmitSeconds: Double = 0
    var transmissions: Int = 0
    var totalSeconds: Double = 0
    var forwardPowerSum: Double = 0
    var forwardPowerSamples: Int = 0

    var averageTransmitPower: Double {
        forwardPowerSamples > 0 ? forwardPowerSum / Double(forwardPowerSamples) : 0
    }

    var dutyCycle: Double {
        totalSeconds > 0 ? min(1.0, transmitSeconds / totalSeconds) : 0
    }

    mutating func reset() { self = SessionStats() }

    mutating func ingest(_ state: AmplifierState, wasTx: Bool, interval: TimeInterval) {
        totalSeconds += interval
        peakForwardPower = max(peakForwardPower, state.forwardPower)
        peakReflectedPower = max(peakReflectedPower, state.reflectedPower)
        peakTemperature = max(peakTemperature, state.temperature)
        peakCurrent = max(peakCurrent, state.current)

        if state.isTx {
            transmitSeconds += interval
            // SWR is only meaningful under power.
            peakSWR = max(peakSWR, state.swr)
            if state.forwardPower > 0 {
                forwardPowerSum += state.forwardPower
                forwardPowerSamples += 1
            }
            if !wasTx { transmissions += 1 }
        }
    }
}

extension Array where Element == TelemetrySample {
    /// Comma-separated export of the in-app telemetry history.
    func csvRepresentation() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var out = "timestamp,forward_w,reflected_w,swr,temperature_c,current_a,drive_w,frequency_khz,band,tx\n"
        out.reserveCapacity(count * 96)
        for s in self {
            out += "\(formatter.string(from: s.date)),"
            out += String(format: "%.0f,%.0f,%.2f,%.1f,%.2f,%.1f,",
                          s.forwardPower, s.reflectedPower, s.swr,
                          s.temperature, s.current, s.inputPower)
            out += "\(s.frequency),\(BandSelection.name(for: s.bandCode)),\(s.isTx ? 1 : 0)\n"
        }
        return out
    }
}

// MARK: - Saved devices

struct SavedDevice: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var host: String            // IP address or mDNS hostname
    var serialNumber: String?
    var lastSeen: Date?

    var displayName: String { name.isEmpty ? host : name }
}

/// Persists the controllers the operator has connected to.
/// v1.0 stored a single IP under `lastConnectedIP` and never used it.
final class DeviceStore: ObservableObject {
    @Published private(set) var devices: [SavedDevice] = []
    @Published var autoConnectHost: String? {
        didSet { UserDefaults.standard.set(autoConnectHost, forKey: Keys.autoConnect) }
    }

    private enum Keys {
        static let devices = "savedDevices"
        static let autoConnect = "autoConnectHost"
        static let legacyIP = "lastConnectedIP"
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Keys.devices),
           let decoded = try? JSONDecoder().decode([SavedDevice].self, from: data) {
            devices = decoded
        }
        autoConnectHost = UserDefaults.standard.string(forKey: Keys.autoConnect)

        // Carry across the single address stored by the previous version.
        if devices.isEmpty, let legacy = UserDefaults.standard.string(forKey: Keys.legacyIP),
           !legacy.isEmpty {
            devices = [SavedDevice(name: "", host: legacy, serialNumber: nil, lastSeen: nil)]
            if autoConnectHost == nil { autoConnectHost = legacy }
            persist()
        }
    }

    func remember(host: String, serialNumber: String? = nil) {
        guard !host.isEmpty else { return }
        if let index = devices.firstIndex(where: { $0.host == host }) {
            devices[index].lastSeen = Date()
            if let serialNumber, serialNumber != "Unknown" {
                devices[index].serialNumber = serialNumber
            }
        } else {
            devices.append(SavedDevice(name: "", host: host,
                                       serialNumber: serialNumber, lastSeen: Date()))
        }
        persist()
    }

    func rename(_ device: SavedDevice, to name: String) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index].name = name
        persist()
    }

    func remove(_ device: SavedDevice) {
        devices.removeAll { $0.id == device.id }
        if autoConnectHost == device.host { autoConnectHost = nil }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: Keys.devices)
        }
    }
}

// MARK: - Alerts

enum AlertKind: String, CaseIterable, Identifiable {
    case highSWR
    case overTemperature
    case fault
    case disconnected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highSWR:          return "High SWR"
        case .overTemperature:  return "Amplifier Hot"
        case .fault:            return "Amplifier Fault"
        case .disconnected:     return "Controller Disconnected"
        }
    }

    var settingsLabel: String {
        switch self {
        case .highSWR:          return "High SWR (above 2.5:1 while transmitting)"
        case .overTemperature:  return "PA temperature above 70 °C"
        case .fault:            return "Amplifier reports a fault"
        case .disconnected:     return "Connection to the controller is lost"
        }
    }

    var defaultsKey: String { "alert.\(rawValue)" }
}
