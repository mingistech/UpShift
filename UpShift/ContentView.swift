import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(UpscaleJob.self) private var job
    @State private var targeted = false
    @State private var showDetails = false

    var body: some View {
        @Bindable var job = job
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Image(systemName: "arrow.up.right.video.fill")
                        .font(.largeTitle).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Upshift").font(.largeTitle.bold())
                        Text("A little more detail. Every frame.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if job.input != nil {
                        Button("Choose Video…", action: job.chooseVideo).disabled(job.isRunning)
                    }
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(targeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                    if let player = job.player {
                        NativeVideoPreview(player: player).clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: "film.stack").font(.system(size: 44, weight: .light))
                            Text("Drop your video here").font(.title2.weight(.medium))
                            Text("Start with a Seedance MP4").foregroundStyle(.secondary)
                            Button("Choose Video…", action: job.chooseVideo)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .frame(height: 320)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(targeted ? Color.accentColor : .clear, lineWidth: 2))
                .dropDestination(for: URL.self) { urls, _ in
                    guard !job.isRunning, urls.count == 1, let url = urls.first else { return false }
                    job.select(url)
                    return true
                } isTargeted: { targeted = $0 }
                if let input = job.input {
                    Text(input.lastPathComponent).font(.headline).lineLimit(1).help(input.path)
                }
                HStack(spacing: 30) {
                    detail("Enhancement", "2× · OpenProteus")
                    detail("Output", "Original preset · HEVC MP4")
                    detail("Frame rate & audio", "Keep original")
                    Spacer()
                }
                Divider()
                Toggle("AI compression cleanup (experimental)", isOn: $job.restoreCompression)
                    .disabled(job.isRunning)
                    .help("Applies full-strength restoration before upscaling. It can reduce compression blocks, but may remove natural texture or give the video an artificial look. Leave off for the original upscale.")
                Text("Leave off to preserve natural texture. Cleanup may reduce blocks, but can make skin and fine detail look overly smooth or artificial.")
                    .font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(job.status).font(.callout).textSelection(.enabled)
                        Spacer()
                        if job.isRunning {
                            Button("Cancel", role: .cancel, action: job.cancel).disabled(job.isCancelling)
                        } else if let output = job.output {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
                        }
                        Button("Upscale & Save…", action: job.start)
                            .buttonStyle(.borderedProminent)
                            .disabled(job.input == nil || job.isRunning || !job.engineReady)
                    }
                    if job.isRunning {
                        if let progress = job.progress { ProgressView(value: progress) }
                        else { ProgressView().progressViewStyle(.linear) }
                    }
                    if let error = job.error {
                        Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
                    }
                    if let output = job.output {
                        Text("Saved to: \(output.path)")
                            .font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                DisclosureGroup("Processing engine & details", isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(job.engineReady ? "Local engine ready" : "Choose the project folder after running setup", systemImage: job.engineReady ? "checkmark.circle" : "exclamationmark.circle")
                            Spacer()
                            Button("Choose Folder…", action: job.chooseEngine).disabled(job.isRunning)
                        }
                        Text(job.runtimePath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Text("Apple GPU processing · 8-bit HEVC MP4 · SDR · Quality 65 · Original frame rate and audio")
                            .font(.caption).foregroundStyle(.secondary)
                        if !job.log.isEmpty {
                            ScrollView {
                                Text(job.log).font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                            }.frame(height: 110)
                        }
                    }.padding(.top, 8)
                }.font(.callout)
            }
            .padding(28)
        }
        .frame(minWidth: 720, minHeight: 620)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium))
        }
    }
}

#Preview { ContentView().environment(UpscaleJob()) }

// Use AppKit's player directly: the SwiftUI VideoPlayer overlay crashes while
// initializing its generic metadata on the macOS 27.2 development build.
private struct NativeVideoPreview: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}
