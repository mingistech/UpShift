import AppKit
import AVKit
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class UpscaleJob {
    var input: URL?
    var output: URL?
    var player: AVPlayer?
    var isRunning = false
    var isCancelling = false
    var progress: Double?
    var status = "Choose a video to get started."
    var error: String?
    var log = ""
    var runtimePath: String
    var restoreCompression = false
    @ObservationIgnored private var process: Process?
    @ObservationIgnored var onStopped: (() -> Void)?
    @ObservationIgnored private var completedOutput: URL?

    init() {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/SharedSupport/Engine")
        if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("engine.json").path) {
            runtimePath = bundled.path
        } else {
            runtimePath = UserDefaults.standard.string(forKey: "runtimePath") ?? project.appendingPathComponent(".runtime").path
        }
        if let path = UserDefaults.standard.string(forKey: "lastCompletedOutput"),
           FileManager.default.fileExists(atPath: path) {
            output = URL(fileURLWithPath: path)
            status = "Last completed export."
        }
    }

    var engineReady: Bool {
        FileManager.default.isExecutableFile(atPath: runtimePath + "/venv/bin/python") &&
        FileManager.default.fileExists(atPath: runtimePath + "/engine.json")
    }

    func chooseEngine() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose the Upshift project folder, or its .runtime folder."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        runtimePath = folder.lastPathComponent == ".runtime" ? folder.path : folder.appendingPathComponent(".runtime").path
        UserDefaults.standard.set(runtimePath, forKey: "runtimePath")
    }

    func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        select(url)
    }

    func select(_ url: URL) {
        guard !isRunning else { return }
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else {
            error = "Choose a readable video on this Mac."
            return
        }
        player?.pause()
        input = url
        player = AVPlayer(url: url)
        output = nil
        error = nil
        progress = nil
        status = "Ready for a 2× upscale."
    }

    func start() {
        guard let input, !isRunning, engineReady else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        let suffix = restoreCompression ? "-Upshift-2x-Clean.mp4" : "-Upshift-2x.mp4"
        panel.nameFieldStringValue = input.deletingPathExtension().lastPathComponent + suffix
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard destination.resolvingSymlinksInPath() != input.resolvingSymlinksInPath() else {
            error = "Choose a different name so your original video stays safe."
            return
        }
        launch(input: input, destination: destination)
    }

    private func launch(input: URL, destination: URL) {
        guard let bridge = Bundle.main.url(forResource: "upshift_bridge", withExtension: "py") else {
            error = "The processing bridge is missing from the app. Rebuild Upshift in Xcode."
            return
        }
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: runtimePath + "/venv/bin/python")
        task.arguments = ["-u", bridge.path, "--runtime", runtimePath, "--input", input.path, "--output", destination.path, "--replace"]
        if restoreCompression { task.arguments?.append("--restore-compression") }
        task.standardOutput = pipe
        task.standardError = pipe
        task.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["PYTHONNOUSERSITE"] = "1"
        environment.removeValue(forKey: "PYTHONHOME")
        environment.removeValue(forKey: "PYTHONPATH")
        task.environment = environment
        error = nil
        output = nil
        completedOutput = nil
        log = ""
        progress = nil
        isCancelling = false
        status = "Checking video and engine…"
        player?.pause()
        do {
            try task.run()
            process = task
            isRunning = true
            // One reader owns the pipe so the final event is processed before completion.
            DispatchQueue.global(qos: .userInitiated).async {
                var pending = Data()
                while let chunk = try? pipe.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                    pending.append(chunk)
                    while let newline = pending.firstIndex(of: 10) {
                        let line = String(decoding: pending[..<newline], as: UTF8.self)
                        pending.removeSubrange(...newline)
                        DispatchQueue.main.async { self.receive(line) }
                    }
                }
                if !pending.isEmpty {
                    let line = String(decoding: pending, as: UTF8.self)
                    DispatchQueue.main.async { self.receive(line) }
                }
                task.waitUntilExit()
                let code = task.terminationStatus
                DispatchQueue.main.async { self.finished(code) }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func cancel() {
        guard isRunning, !isCancelling else { return }
        isCancelling = true
        status = "Cancelling…"
        process?.terminate()
    }

    private func receive(_ line: String) {
        guard let data = line.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else {
            appendLog(line)
            return
        }
        if let message = event["message"] as? String {
            if type == "log" { appendLog(message) }
            else if type == "error" { error = message }
            else if !isCancelling { status = message }
        }
        if type == "progress", let value = event["fraction"] as? Double, !isCancelling {
            progress = min(max(value, 0), 0.99)
        }
        if type == "complete", let path = event["output"] as? String {
            completedOutput = URL(fileURLWithPath: path)
        }
    }

    private func appendLog(_ message: String) {
        log += message + "\n"
        if log.count > 24000 { log = String(log.suffix(16000)) }
    }

    private func finished(_ code: Int32) {
        isRunning = false
        process = nil
        if code == 0, let completedOutput {
            output = completedOutput
            UserDefaults.standard.set(completedOutput.path, forKey: "lastCompletedOutput")
            status = "Your upscaled video is ready."
            progress = 1
        } else if isCancelling {
            status = "Cancelled."
            error = nil
            progress = nil
        } else {
            status = "Upscale couldn’t finish."
            if error == nil { error = "The engine stopped (code \(code)). Open details for its log." }
        }
        isCancelling = false
        onStopped?()
        onStopped = nil
    }
}
