//
//  NotificationManager.swift
//  AcomControl
//
//  Alerts that protect the hardware: high SWR, overtemperature, faults and
//  loss of contact with the controller. Each alert is edge triggered and rate
//  limited so a sustained condition does not produce a stream of banners.
//

import Foundation
import AppKit
import UserNotifications

@MainActor
final class NotificationManager {

    /// Protection thresholds, matching those the amplifier itself watches.
    enum Threshold {
        static let swrDanger = 2.5
        static let swrClear = 2.2          // hysteresis, so a value hovering at
                                           // the limit does not chatter
        static let temperatureDanger = 70.0
        static let temperatureClear = 65.0
    }

    private var authorized = false
    private var swrLatched = false
    private var temperatureLatched = false
    private var faultLatched = false
    private var lastDelivery: [AlertKind: Date] = [:]
    private let minimumInterval: TimeInterval = 30

    // MARK: Preferences

    static func isEnabled(_ kind: AlertKind) -> Bool {
        // Alerts default to on: the whole point is protecting the amplifier.
        UserDefaults.standard.object(forKey: kind.defaultsKey) as? Bool ?? true
    }

    static func setEnabled(_ enabled: Bool, for kind: AlertKind) {
        UserDefaults.standard.set(enabled, forKey: kind.defaultsKey)
    }

    static var soundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "alert.sound") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "alert.sound") }
    }

    // MARK: Authorisation

    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                Task { @MainActor in self?.authorized = granted }
            }
    }

    // MARK: Evaluation

    /// Called for every telemetry frame. Latches keep one banner per event.
    func evaluate(state: AmplifierState, previous: AmplifierState) {
        // Stale telemetry is not an event. When the amplifier drops off the
        // serial link the controller keeps publishing its last known values, so
        // evaluating them would raise alarms about a reading that is no longer
        // being measured.
        guard state.connected else { return }

        // SWR is only meaningful while power is flowing.
        if state.isTx && state.swr >= Threshold.swrDanger {
            if !swrLatched {
                swrLatched = true
                post(.highSWR,
                     body: String(format: "SWR is %.2f:1 at %.0f W on %@. Stop transmitting and check the antenna.",
                                  state.swr, state.forwardPower,
                                  BandSelection.name(for: state.bandCode)),
                     critical: true)
            }
        } else if !state.isTx || state.swr < Threshold.swrClear {
            // Also clear the moment transmission stops. v2.0 only unlatched
            // below 2.2:1, but the amplifier holds its last SWR reading after
            // you unkey — so an SWR that settled at or above 2.2 left the latch
            // set for the rest of the session and silenced every later alert.
            swrLatched = false
        }

        if state.temperature >= Threshold.temperatureDanger {
            if !temperatureLatched {
                temperatureLatched = true
                post(.overTemperature,
                     body: String(format: "PA temperature is %.0f °C. Reduce duty cycle and let the fan catch up.",
                                  state.temperature),
                     critical: true)
            }
        } else if state.temperature < Threshold.temperatureClear {
            temperatureLatched = false
        }

        if state.hasFault {
            if !faultLatched {
                faultLatched = true
                let fault = state.faults.first
                let detail = fault.map { "\($0.codeText) \($0.severity.label): \($0.title)" }
                    ?? "The amplifier reported a fault."
                post(.fault, body: detail, critical: true)
            }
        } else {
            faultLatched = false
        }
    }

    func notifyDisconnected(host: String) {
        post(.disconnected, body: "Lost contact with the controller at \(host).", critical: false)
    }

    // MARK: Delivery

    private func post(_ kind: AlertKind, body: String, critical: Bool) {
        guard Self.isEnabled(kind) else { return }

        if let last = lastDelivery[kind], Date().timeIntervalSince(last) < minimumInterval {
            return
        }
        lastDelivery[kind] = Date()

        guard authorized else {
            // Notifications are denied, so make the noise ourselves and bounce
            // the Dock icon. A sound distinct from the default banner chime
            // carries better across a shack.
            if Self.soundEnabled {
                NSSound(named: critical ? "Sosumi" : "Submarine")?.play()
            }
            NSApp.requestUserAttention(critical ? .criticalRequest : .informationalRequest)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = kind.title
        content.body = body
        // The notification carries its own sound. v2.0 also played an NSSound
        // just above, so every authorised alert chimed twice.
        content.sound = Self.soundEnabled ? .default : nil
        if critical { content.interruptionLevel = .timeSensitive }

        let request = UNNotificationRequest(identifier: "\(kind.rawValue)-\(Date().timeIntervalSince1970)",
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
