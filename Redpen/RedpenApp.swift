import SwiftUI
import UserNotifications

@main
struct RedpenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ReviewStore.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(store)
        } label: {
            MenuBarLabel()
                .environment(store)
        }
        .menuBarExtraStyle(.window)

        Window("Redpen", id: WindowID.editor) {
            EditorView()
                .environment(store)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 820)
        .defaultPosition(.center)

        Window("Redpen Settings", id: WindowID.settings) {
            SettingsView()
                .environment(store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// Always in the menu bar, so it's where the app opens windows on the store's behalf.
struct MenuBarLabel: View {
    @Environment(ReviewStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Keys.welcomed) private var welcomed = false

    var body: some View {
        Image(nsImage: MenuBarIcon.image(pending: !store.pending.isEmpty))
            .task {
                store.start()
                if !welcomed {
                    welcomed = true
                    store.requestEditor()
                }
            }
            .onChange(of: store.editorRequests) {
                openWindow(id: WindowID.editor)
                NSApp.activate()
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Images opened with Redpen from Finder, or dropped on its Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        ReviewStore.shared.add(urls: urls)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { ReviewStore.shared.addPending() }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        []
    }
}
