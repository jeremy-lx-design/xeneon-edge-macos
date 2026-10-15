// A very small SwiftUI front end for the `xeneonctl` CLI: three sliders,
// nothing else. All the actual DDC/CI protocol work happens in the CLI
// binary (../xeneonctl); this just shells out to it.
import SwiftUI
import Foundation

enum CLI {
    static let binaryPath: String? = {
        // Next to the running executable: how a downloaded release is laid
        // out, with xeneonctl alongside the app binary in Contents/MacOS.
        let adjacent = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("xeneonctl")
            .path
        // #filePath is the source location at build time, so this only
        // resolves when running from a checkout - which is the point.
        let repoRelative = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // XeneonUI/
            .deletingLastPathComponent() // Sources/
            .deletingLastPathComponent() // gui/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("xeneonctl")
            .path
        return [adjacent, repoRelative, "/usr/local/bin/xeneonctl", "/opt/homebrew/bin/xeneonctl"]
            .compactMap { $0 }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    private static func run(_ args: [String]) -> String? {
        guard let binaryPath else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    static func get(_ setting: String) -> Int? {
        run(["get", setting]).flatMap { $0.split(separator: " ").first }.flatMap { Int($0) }
    }

    static func set(_ setting: String, _ value: Int) {
        _ = run(["set", setting, String(value)])
    }
}

@main
struct XeneonUIApp: App {
    var body: some Scene {
        WindowGroup("Xeneon Edge") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    // nil when the display doesn't support that setting.
    @State private var brightness: Double?
    @State private var contrast: Double?
    @State private var volume: Double?
    @State private var ready = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            } else if !ready {
                ProgressView("Reading display…")
            } else {
                if let value = Binding($brightness) {
                    slider(title: "Brightness", value: value, setting: "brightness")
                }
                if let value = Binding($contrast) {
                    slider(title: "Contrast", value: value, setting: "contrast")
                }
                if let value = Binding($volume) {
                    slider(title: "Volume", value: value, setting: "volume")
                }
            }
        }
        .padding(20)
        .frame(width: 280)
        .task { await load() }
    }

    private func slider(title: String, value: Binding<Double>, setting: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...100, step: 1) { editing in
                guard !editing else { return }
                let newValue = Int(value.wrappedValue)
                Task.detached { CLI.set(setting, newValue) }
            }
        }
    }

    private func load() async {
        guard CLI.binaryPath != nil else {
            errorMessage = "xeneonctl not found.\nRun 'make' in the project root first."
            return
        }
        // Not every panel implements every setting - the XENEON EDGE has no
        // speakers, so it rejects volume - so only show the sliders for the
        // settings that actually read back.
        let (b, c, v) = await Task.detached {
            (CLI.get("brightness"), CLI.get("contrast"), CLI.get("volume"))
        }.value

        guard b != nil || c != nil || v != nil else {
            errorMessage = "Could not read display settings.\nIs the XENEON EDGE connected?"
            return
        }
        (brightness, contrast, volume) = (b.map(Double.init), c.map(Double.init), v.map(Double.init))
        ready = true
    }
}
