import SwiftUI

@main
struct StagApp: App {
    @NSApplicationDelegateAdaptor(StagAppDelegate.self) var appDelegate
    @StateObject private var store = AppStore.shared

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .environmentObject(store)
    }
}
