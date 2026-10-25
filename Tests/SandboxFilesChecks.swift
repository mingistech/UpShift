import Foundation

@main
struct SandboxFilesChecks {
    static func main() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("UpshiftFileChecks-" + UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let source = folder.appendingPathComponent("original.mp4")
        let original = Data("original video must remain intact".utf8)
        try original.write(to: source)
        let job = try SandboxFiles.prepare(source)
        defer { try? fm.removeItem(at: job.directory) }
        guard job.directory.deletingLastPathComponent() == fm.temporaryDirectory,
              try Data(contentsOf: job.input) == original,
              job.input != source else { fatalError("Input was not staged safely") }
        let rendered = Data("verified rendered output".utf8)
        try rendered.write(to: job.output)
        let destination = folder.appendingPathComponent("export.mp4")
        try SandboxFiles.save(job.output, to: destination, protecting: source)
        guard try Data(contentsOf: destination) == rendered else { fatalError("New export failed") }
        try Data("previous export".utf8).write(to: destination)
        try SandboxFiles.save(job.output, to: destination, protecting: source)
        guard try Data(contentsOf: destination) == rendered else { fatalError("Safe replacement failed") }
        do {
            try SandboxFiles.save(folder.appendingPathComponent("missing.mp4"), to: destination, protecting: source)
            fatalError("Missing render unexpectedly saved")
        } catch {
            guard try Data(contentsOf: destination) == rendered else { fatalError("Failed export destroyed previous file") }
        }
        do {
            try SandboxFiles.save(job.output, to: source, protecting: source)
            fatalError("Saving over the original was allowed")
        } catch {
            guard try Data(contentsOf: source) == original else { fatalError("Original was modified") }
        }
        var hidden = URLResourceValues()
        hidden.isHidden = true
        var output = job.output
        try output.setResourceValues(hidden)
        try SandboxFiles.save(output, to: destination, protecting: source)
        guard try destination.resourceValues(forKeys: [.isHiddenKey]).isHidden == false else {
            fatalError("Export inherited a hidden flag")
        }
        print("PASS: staged input, new export, safe replacement, failure protection, original protection, visible output")
    }
}
