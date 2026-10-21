//
//  Credentials.swift
//  AcomControl
//
//  Per-controller HTTP Basic credentials, kept in the login keychain.
//
//  Firmware 7.0 can require a password on the API, the WebSocket and firmware
//  upload. The password is a secret, so it does not go in UserDefaults
//  alongside the window size — it goes in the keychain, keyed by host.
//

import Foundation
import Security

/// Credentials for one controller.
struct ControllerCredentials: Equatable {
    var user: String
    var password: String

    var basicAuthHeader: String? {
        guard !password.isEmpty,
              let encoded = "\(user):\(password)".data(using: .utf8)?.base64EncodedString()
        else { return nil }
        return "Basic \(encoded)"
    }
}

enum CredentialStore {
    private static let service = "com.acomcontrol.AcomControl.controller"
    private static let userDefaultsPrefix = "controllerUser."

    /// Reads the stored credentials for a host, or nil when none are saved.
    static func credentials(for host: String) -> ControllerCredentials? {
        guard !host.isEmpty else { return nil }
        let user = UserDefaults.standard.string(forKey: userDefaultsPrefix + host) ?? "acom"
        guard let password = password(for: host), !password.isEmpty else { return nil }
        return ControllerCredentials(user: user, password: password)
    }

    static func save(_ credentials: ControllerCredentials, for host: String) {
        guard !host.isEmpty else { return }
        UserDefaults.standard.set(credentials.user, forKey: userDefaultsPrefix + host)

        guard let data = credentials.password.data(using: .utf8) else { return }
        var query = baseQuery(for: host)

        // SecItemUpdate fails if nothing is there yet, so try an update and
        // fall back to an add.
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    static func remove(for host: String) {
        guard !host.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: userDefaultsPrefix + host)
        SecItemDelete(baseQuery(for: host) as CFDictionary)
    }

    // MARK: Private

    private static func baseQuery(for host: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host
        ]
    }

    private static func password(for host: String) -> String? {
        var query = baseQuery(for: host)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
