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
    var isSaving = false
    var progress: Double?
    var status = "Choose a video to get started."
    var error: String?
    var log = ""
    let runtimePath: String
    @ObservationIgnored private var process: Process?
    @ObservationIgnored var onStopped: (() -> Void)?
    @ObservationIgnored private var completedOutput: URL?
    @ObservationIgnored private var prepared: PreparedVideo?
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var inputAccess: SecurityScopedFile?
    @ObservationIgnored private var outputAccess: SecurityScopedFile?
    @ObservationIgnored private var destinationAccess: SecurityScopedFile?

    init() {
        runtimePath = Bundle.main.bundleURL.appendingPathComponent("Contents/SharedSupport/Engine").path
        if let data = UserDefaults.standard.data(forKey: "lastCompletedOutputBookmark") {
            do {
                let access = try SecurityScopedFile.restore(data)
                if FileManager.default.fileExists(atPath: access.url.path) {
                    outputAccess = access
                    output = access.url
                    UserDefaults.standard.set(try access.bookmark(), forKey: "lastCompletedOutputBookmark")
                    status = "Last completed export."
                } else {
                    UserDefaults.standard.removeObject(forKey: "lastCompletedOutputBookmark")
                }
            } catch {
                UserDefaults.standard.removeObject(forKey: "lastCompletedOutputBookmark")
            }
        }
    }

    var engineReady: Bool {
        FileManager.default.isExecutableFile(atPath: runtimePath + "/venv/bin/python") &&
        FileManager.default.fileExists(atPath: runtimePath + "/engine.json")
    }

    func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        select(url)
    }

    func select(_ url: URL) {
        guard !isRunning else { return }
        let access = SecurityScopedFile(url)
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else {
            error = "Choose a readable video on this Mac."
            return
        }
        player?.pause()
        player = nil
        inputAccess = access
        input = url
        player = AVPlayer(url: url)
        output = nil
        outputAccess = nil
        error = nil
        progress = nil
        status = "Ready for a 2× upscale."
    }

    func start() {
        guard let input, !isRunning, engineReady else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = input.deletingPathExtension().lastPathComponent + "-Upshift-2x.mp4"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard destination.resolvingSymlinksInPath() != input.resolvingSymlinksInPath() else {
            error = "Choose a different name so your original video stays safe."
            return
        }
        destinationAccess = SecurityScopedFile(destination)
        output = nil
        outputAccess = nil
        completedOutput = nil
        error = nil
        log = ""
        progress = nil
        isRunning = true
        isCancelling = false
        status = "Preparing video…"
        player?.pause()
        preparation = Task {
            let worker = Task.detached(priority: .userInitiated) { try SandboxFiles.prepare(input) }
            do {
                let prepared = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                self.prepared = prepared
                try Task.checkCancellation()
                preparation = nil
                launch(prepared)
            } catch {
                preparation = nil
                stopped(error: isCancelling ? nil : error)
            }
        }
    }

    private func launch(_ prepared: PreparedVideo) {
        guard let bridge = Bundle.main.url(forResource: "upshift_bridge", withExtension: "py") else {
            stopped(error: NSError(domain: "Upshift", code: 1, userInfo: [NSLocalizedDescriptionKey: "The processing engine is missing from this build."]))
            return
        }
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: runtimePath + "/venv/bin/python")
        task.arguments = ["-u", bridge.path, "--runtime", runtimePath,
                          "--input", prepared.input.path, "--output", prepared.output.path]
        task.currentDirectoryURL = prepared.directory
        task.standardOutput = pipe
        task.standardError = pipe
        task.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["PYTHONNOUSERSITE"] = "1"
        environment["XDG_CACHE_HOME"] = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].path
        environment.removeValue(forKey: "PYTHONHOME")
        environment.removeValue(forKey: "PYTHONPATH")
        environment.removeValue(forKey: "IMAGEIO_FFMPEG_EXE")
        task.environment = environment
        status = "Checking video and engine…"
        do {
            try task.run()
            process = task
            // One reader owns the pipe so completion is processed before exit.
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
        } catch { stopped(error: error) }
    }

    func cancel() {
        guard isRunning, !isCancelling, !isSaving else { return }
        isCancelling = true
        status = "Cancelling…"
        preparation?.cancel()
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
            else if !isCancelling && type != "complete" { status = message }
        }
        if type == "progress", let value = event["fraction"] as? Double, !isCancelling {
            progress = min(max(value, 0), 0.99)
        }
        if type == "complete", let path = event["output"] as? String,
           let expected = prepared?.output,
           URL(fileURLWithPath: path).standardizedFileURL == expected.standardizedFileURL {
            completedOutput = expected
        }
    }

    private func appendLog(_ message: String) {
        log += message + "\n"
        if log.count > 24000 { log = String(log.suffix(16000)) }
    }

    private func finished(_ code: Int32) {
        process = nil
        guard code == 0, let completedOutput, let destinationAccess, let input, !isCancelling else {
            if !isCancelling && error == nil { error = "The engine stopped (code \(code)). Open details for its log." }
            stopped(error: nil)
            return
        }
        isSaving = true
        status = "Saving your verified video…"
        let destination = destinationAccess.url
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try SandboxFiles.save(completedOutput, to: destination, protecting: input)
                }.value
                output = destination
                outputAccess = destinationAccess
                do {
                    UserDefaults.standard.set(try destinationAccess.bookmark(), forKey: "lastCompletedOutputBookmark")
                } catch {
                    appendLog("Export saved; could not remember its location: \(error.localizedDescription)")
                }
                status = "Your upscaled video is ready."
                progress = 1
                releaseJob()
            } catch { stopped(error: error) }
        }
    }

    private func stopped(error: Error?) {
        if let error { self.error = error.localizedDescription }
        if isCancelling {
            status = "Cancelled."
            self.error = nil
        } else { status = "Upscale couldn’t finish." }
        progress = nil
        releaseJob()
    }

    private func releaseJob() {
        if let directory = prepared?.directory { try? FileManager.default.removeItem(at: directory) }
        prepared = nil
        completedOutput = nil
        destinationAccess = nil
        process = nil
        isRunning = false
        isCancelling = false
        isSaving = false
        onStopped?()
        onStopped = nil
    }
}
