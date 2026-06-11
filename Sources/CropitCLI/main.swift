import Foundation
import AppKit

// MARK: - Entry point

let args = CommandLine.arguments.dropFirst()
guard let command = args.first else { printHelp(); exit(0) }

switch command {
case "capture":   runCapture(Array(args.dropFirst()))
case "history":   runHistory(Array(args.dropFirst()))
case "export":    runExport(Array(args.dropFirst()))
case "open":      runOpen(Array(args.dropFirst()))
case "version":   print("Cropit CLI 1.0.0"); exit(0)
case "--help", "-h", "help": printHelp(); exit(0)
default:
    fputs("Unknown command: \(command)\n", stderr)
    printHelp()
    exit(1)
}

// MARK: - capture

func runCapture(_ args: [String]) {
    var type = "area"
    var shouldWait = false
    var timeout: TimeInterval = 30
    var outputPath: String? = nil

    var i = 0
    while i < args.count {
        switch args[i] {
        case "--area":       type = "area"
        case "--window":     type = "window"
        case "--fullscreen": type = "fullscreen"
        case "--scrolling":  type = "scrolling"
        case "--gif":        type = "gif"
        case "--recording":  type = "recording"
        case "--wait":       shouldWait = true
        case "--timeout":
            i += 1
            if i < args.count, let t = TimeInterval(args[i]) { timeout = t }
        case "--output":
            i += 1
            if i < args.count { outputPath = args[i]; shouldWait = true }
        default:
            fputs("Unknown flag: \(args[i])\n", stderr)
        }
        i += 1
    }

    let url = URL(string: "cropit://capture?type=\(type)")!

    if shouldWait {
        let saveDir = resolveSavePath()
        let before = latestFile(in: saveDir)
        NSWorkspace.shared.open(url)
        // Poll for a new file up to timeout
        let deadline = Date().addingTimeInterval(timeout)
        var found: URL? = nil
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
            let latest = latestFile(in: saveDir)
            if latest != before, let f = latest {
                found = f
                break
            }
        }
        if let found {
            if let dest = outputPath {
                let destURL = URL(fileURLWithPath: dest)
                try? FileManager.default.copyItem(at: found, to: destURL)
                print(dest)
            } else {
                print(found.path)
            }
        } else {
            fputs("Timed out waiting for capture.\n", stderr)
            exit(1)
        }
    } else {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - history

func runHistory(_ args: [String]) {
    var limit = 50
    var filterType: String? = nil
    var favoritesOnly = false
    var format = "text"

    var i = 0
    while i < args.count {
        switch args[i] {
        case "--limit", "-n":
            i += 1
            if i < args.count, let n = Int(args[i]) { limit = n }
        case "--type":
            i += 1
            if i < args.count { filterType = args[i] }
        case "--favorites":  favoritesOnly = true
        case "--format":
            i += 1
            if i < args.count { format = args[i] }
        default:
            fputs("Unknown flag: \(args[i])\n", stderr)
        }
        i += 1
    }

    let records = loadHistory()
    let filtered = records
        .filter { filterType == nil || $0["type"] as? String == filterType }
        .filter { !favoritesOnly || ($0["isFavorite"] as? Bool == true) }
        .prefix(limit)

    if format == "json" {
        guard let data = try? JSONSerialization.data(withJSONObject: Array(filtered),
                                                     options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            fputs("Failed to encode JSON.\n", stderr); exit(1)
        }
        print(str)
    } else {
        for (idx, r) in filtered.enumerated() {
            let date  = r["date"]  as? String ?? "?"
            let type  = r["type"]  as? String ?? "?"
            let path  = r["filePath"] as? String ?? "?"
            let app   = r["appName"] as? String ?? ""
            let star  = (r["isFavorite"] as? Bool == true) ? "★ " : ""
            let appTag = app.isEmpty ? "" : " [\(app)]"
            print("\(idx + 1). \(star)\(date)  \(type)\(appTag)")
            print("   \(path)")
        }
    }
}

// MARK: - export (metadata JSON sidecar)

func runExport(_ args: [String]) {
    guard let filePath = args.first else {
        fputs("Usage: cropit export <image-path>\n", stderr)
        exit(1)
    }
    let records = loadHistory()
    let abs = URL(fileURLWithPath: filePath).standardizedFileURL.path
    guard let record = records.first(where: { ($0["filePath"] as? String) == abs }) else {
        fputs("No history entry found for: \(filePath)\n", stderr)
        exit(1)
    }
    let imageURL = URL(fileURLWithPath: abs)
    let sidecarURL = imageURL.deletingPathExtension().appendingPathExtension("json")
    guard let data = try? JSONSerialization.data(withJSONObject: record,
                                                  options: [.prettyPrinted, .sortedKeys]) else {
        fputs("Failed to encode JSON.\n", stderr); exit(1)
    }
    try? data.write(to: sidecarURL, options: .atomic)
    print(sidecarURL.path)
}

// MARK: - open (open image in Cropit editor)

func runOpen(_ args: [String]) {
    guard let filePath = args.first else {
        fputs("Usage: cropit open <image-path>\n", stderr)
        exit(1)
    }
    let fileURL = URL(fileURLWithPath: filePath)
    // Try to open with Cropit app if running, else fall back to default app
    let cropitBundle = "com.ganwar.Cropit"
    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: cropitBundle) {
        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: .init(), completionHandler: nil)
    } else {
        NSWorkspace.shared.open(fileURL)
    }
}

// MARK: - Help

func printHelp() {
    print("""
    Cropit CLI — Screenshot tool automation

    USAGE:
      cropit <command> [options]

    COMMANDS:
      capture   Trigger a screenshot capture
      history   List capture history
      export    Export JSON metadata for a captured image
      open      Open an image in Cropit editor
      version   Print version

    CAPTURE OPTIONS:
      --area            Capture screen area (default)
      --window          Capture a window
      --fullscreen      Capture fullscreen
      --scrolling       Scrolling capture
      --gif             Record GIF
      --recording       Record screen video
      --wait            Wait for capture to complete, print file path to stdout
      --timeout N       Seconds to wait (default: 30)
      --output <path>   Copy the capture to <path> (implies --wait)

    HISTORY OPTIONS:
      --limit N         Show only the last N captures (default: 50)
      --type TYPE       Filter by type (area, window, fullscreen, scrolling, gif, recording)
      --favorites       Show only starred captures
      --format json     Output as JSON array instead of plain text

    EXAMPLES:
      cropit capture --area --wait
      cropit capture --fullscreen --output ~/Desktop/shot.png
      cropit history --limit 10 --format json
      cropit history --type area --favorites
      cropit export ~/Desktop/Cropit_shot.png
      cropit open ~/Desktop/Cropit_shot.png
    """)
}

// MARK: - Helpers

func resolveSavePath() -> URL {
    // Read from Cropit's UserDefaults plist
    let prefsPath = NSHomeDirectory() + "/Library/Preferences/com.ganwar.Cropit.plist"
    if let dict = NSDictionary(contentsOfFile: prefsPath),
       let data = dict["com.ganwar.Cropit.preferences"] as? Data,
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let path = json["savePath"] as? String {
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
    return URL(fileURLWithPath: NSHomeDirectory() + "/Desktop/Cropit Screenshots")
}

func latestFile(in dir: URL) -> URL? {
    let fm = FileManager.default
    guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                                                   options: .skipsHiddenFiles) else { return nil }
    let imageExts = Set(["png", "jpg", "jpeg", "gif", "mp4", "mov"])
    return items
        .filter { imageExts.contains($0.pathExtension.lowercased()) }
        .max {
            let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return d1 < d2
        }
}

func loadHistory() -> [[String: Any]] {
    let historyPath = NSHomeDirectory() + "/Library/Application Support/Cropit/capture_history.json"
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: historyPath)),
          let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        return []
    }
    return array
}
