import Foundation

/// Retain the user-granted scope for as long as a preview or export needs it.
final class SecurityScopedFile {
    let url: URL
    private let accessing: Bool

    init(_ url: URL) {
        self.url = url
        accessing = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if accessing { url.stopAccessingSecurityScopedResource() }
    }

    func bookmark() throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func restore(_ data: Data) throws -> SecurityScopedFile {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        // Re-save the bookmark after acquiring access, including when it was stale.
        return SecurityScopedFile(url)
    }
}

struct PreparedVideo: Sendable {
    let directory: URL
    let input: URL
    let output: URL

    nonisolated init(directory: URL, input: URL, output: URL) {
        self.directory = directory
        self.input = input
        self.output = output
    }
}

enum SandboxFiles {
    /// Helpers see only app-owned files, never the original user-selected paths.
    nonisolated static func prepare(_ source: URL) throws -> PreparedVideo {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("Upshift-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try Task.checkCancellation()
            let input = directory.appendingPathComponent("source").appendingPathExtension(source.pathExtension)
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { coordinatedURL in
                do { try fm.copyItem(at: coordinatedURL, to: input) }
                catch { copyError = error }
            }
            if let coordinationError { throw coordinationError }
            if let copyError { throw copyError }
            try Task.checkCancellation()
            return PreparedVideo(directory: directory, input: input,
                                 output: directory.appendingPathComponent("upscaled.mp4"))
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
    }

    /// Safe-save via a same-volume replacement directory granted by Foundation.
    /// The engine must finish verification before this method is called.
    nonisolated static func save(_ rendered: URL, to destination: URL, protecting original: URL) throws {
        let fm = FileManager.default
        var coordinationError: NSError?
        var saveError: Error?
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing,
                                       error: &coordinationError) { coordinatedURL in
            do {
                guard coordinatedURL.resolvingSymlinksInPath().standardizedFileURL != original.resolvingSymlinksInPath().standardizedFileURL else {
                    throw NSError(domain: "Upshift", code: 2, userInfo: [NSLocalizedDescriptionKey: "Choose a different name so your original video stays safe."])
                }
                let replacement = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                             appropriateFor: coordinatedURL, create: true)
                defer { try? fm.removeItem(at: replacement) }
                var staged = replacement.appendingPathComponent("upscaled.mp4")
                try fm.copyItem(at: rendered, to: staged)
                var values = URLResourceValues()
                values.isHidden = false
                try staged.setResourceValues(values)
                if fm.fileExists(atPath: coordinatedURL.path) {
                    _ = try fm.replaceItemAt(coordinatedURL, withItemAt: staged,
                                             backupItemName: nil, options: [.usingNewMetadataOnly])
                } else {
                    try fm.moveItem(at: staged, to: coordinatedURL)
                }
            } catch { saveError = error }
        }
        if let coordinationError { throw coordinationError }
        if let saveError { throw saveError }
    }
}
