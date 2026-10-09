import SwiftUI
import AppKit

@main
struct UpshiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var job = UpscaleJob()

    var body: some Scene {
        Window("Upshift", id: "main") {
            ContentView().environment(job)
                .onAppear { delegate.job = job }
        }
        .defaultSize(width: 820, height: 700)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Third-Party Notices…") {
                    if let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Video…", action: job.chooseVideo)
                    .keyboardShortcut("o").disabled(job.isRunning)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var job: UpscaleJob?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let job, job.isRunning else { return .terminateNow }
        job.onStopped = { NSApplication.shared.reply(toApplicationShouldTerminate: true) }
        job.cancel()
        return .terminateLater
    }
}
