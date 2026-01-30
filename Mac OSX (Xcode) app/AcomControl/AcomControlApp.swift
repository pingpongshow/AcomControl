//
//  AcomControlApp.swift
//  AcomControl
//
//  macOS Application for ACOM 600S Amplifier Control
//  Connects to ESP32-S3 controller via WebSocket
//

import SwiftUI

@main
struct AcomControlApp: App {
    @StateObject private var amplifierController = AmplifierController()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(amplifierController)
                .frame(minWidth: 900, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        Settings {
            SettingsView()
                .environmentObject(amplifierController)
        }
    }
}
