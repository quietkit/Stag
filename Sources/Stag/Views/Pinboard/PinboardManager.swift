import Cocoa
import SwiftUI

final class PinboardManager: ObservableObject {
    static let shared = PinboardManager()

    @Published var pinnedWindows: [PinboardWindow] = []

    func pin(image: NSImage) {
        let window = PinboardWindow(image: image)
        window.onClose = { [weak self] in
            guard let self = self else { return }
            self.pinnedWindows.removeAll { $0 === window }
        }
        DispatchQueue.main.async {
            self.pinnedWindows.append(window)
            window.show()
        }
    }

    func unpinAll() {
        for w in pinnedWindows {
            w.close()
        }
        pinnedWindows.removeAll()
    }
}
