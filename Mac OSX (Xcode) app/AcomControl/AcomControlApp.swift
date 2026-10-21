//
//  AcomControlApp.swift
//  AcomControl
//
//  macOS application for ACOM 600S amplifier control via an ESP32-S3
//  controller over WebSocket.
//

import SwiftUI

/// Which sheet the main window is showing.
///
/// The menu bar commands and the window's own buttons both need to open these,
/// so the state lives outside the view. v2.0 kept it in `@State` inside
/// ContentView, which left the ⌘K and ⌘H shortcuts its tooltips advertised
/// with nothing to drive — neither command existed.
@MainActor
final class AppRouter: ObservableObject {
    @Published var showDiscovery = false
    @Published var showHistory = false
    @Published var showSettings = false
    @Published var settingsTab: SettingsView.Tab = .connection

    func openSettings(_ tab: SettingsView.Tab) {
        settingsTab = tab
        showSettings = true
    }
}

@main
struct AcomControlApp: App {
    @StateObject private var controller = AmplifierController()
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .environmentObject(router)
        }
        // `.contentSize` pinned the window to the content's own limits, which
        // fought the scroll view. `.contentMinSize` lets the operator size the
        // window while still preventing a layout-breaking squeeze.
        .windowResizability(.contentMinSize)
        .commands { AcomCommands(controller: controller, router: router) }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(controller)
                .environmentObject(router)
        } label: {
            MenuBarLabel().environmentObject(controller)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(isSheet: false)
                .environmentObject(controller)
                .environmentObject(router)
        }
    }
}

/// Keyboard shortcuts for the operations that matter mid-contest.
struct AcomCommands: Commands {
    @ObservedObject var controller: AmplifierController
    @ObservedObject var router: AppRouter

    private var isLive: Bool { controller.connectionState.isConnected }

    var body: some Commands {
        CommandGroup(replacing: .newItem) { }

        CommandMenu("Amplifier") {
            Button("Standby") { controller.setMode(.standby) }
                .keyboardShortcut("1", modifiers: [.command])
                .disabled(!isLive)

            Button("Operate") { controller.setMode(.operate) }
                .keyboardShortcut("2", modifiers: [.command])
                .disabled(!isLive)

            Divider()

            Menu("Band") {
                ForEach(BandSelection.allBands) { band in
                    Button(band.name) { controller.setBand(band.code) }
                        .disabled(!isLive || controller.amplifierState.isTx)
                }
            }

            Button("Clear Soft Faults") { controller.clearErrors() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(!isLive)

            Button("Refresh Amplifier Info") { controller.requestInfo() }
                .disabled(!isLive)

            Divider()

            // These two back the ⌘K and ⌘H the window's tooltips promise.
            Button("Connect to a Controller…") { router.showDiscovery = true }
                .keyboardShortcut("k", modifiers: [.command])

            Button("Session History") { router.showHistory = true }
                .keyboardShortcut("h", modifiers: [.command])

            Button("Reset Session Statistics") { controller.resetSession() }

            Divider()

            Button("Disconnect") { controller.disconnect() }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(!isLive)

            Button("Reconnect") { controller.retry() }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(controller.connectedHost.isEmpty || isLive)
        }

        CommandGroup(after: .toolbar) {
            // Opens the Diagnostics tab, where the log actually is. v2.0 fired
            // the private `showSettingsWindow:` selector, which opened Settings
            // on whichever tab happened to be selected last.
            Button("Show Connection Log") { router.openSettings(.diagnostics) }
        }
    }
}
