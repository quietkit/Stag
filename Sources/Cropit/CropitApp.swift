import SwiftUI

@main
struct CropitApp: App {
    @NSApplicationDelegateAdaptor(CropitAppDelegate.self) var appDelegate
    @StateObject private var store = AppStore.shared

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .environmentObject(store)
    }
}
