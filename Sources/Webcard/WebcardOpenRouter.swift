import AppKit
import SwiftUI

@MainActor
final class WebcardAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        WebcardOpenRouter.open(urls)
    }
}

@MainActor
enum WebcardOpenRouter {
    private static var folderWindows: [URL: WebcardFolderWindowController] = [:]

    static func open(_ urls: [URL]) {
        for url in urls {
            open(url)
        }
    }

    static func open(_ url: URL) {
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true {
                openFolder(url)
            } else if values.isRegularFile == true && url.pathExtension.lowercased() == "webcard" {
                openDocument(url)
            } else {
                throw CocoaError(
                    .fileReadUnsupportedScheme,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Choose a .webcard file or a folder containing webcards."
                    ]
                )
            }
        } catch {
            present(error)
        }
    }

    private static func openDocument(_ url: URL) {
        NSDocumentController.shared.openDocument(
            withContentsOf: url,
            display: true
        ) { _, _, error in
            if let error {
                present(error)
            }
        }
    }

    private static func openFolder(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        if let controller = folderWindows[standardizedURL] {
            NSApp.activate(ignoringOtherApps: true)
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = WebcardFolderWindowController(folderURL: standardizedURL) {
            folderWindows[standardizedURL] = nil
        }
        folderWindows[standardizedURL] = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private static func present(_ error: Error) {
        NSApp.presentError(error)
    }
}

@MainActor
private final class WebcardFolderWindowController: NSWindowController, NSWindowDelegate {
    private let folderURL: URL
    private let hasSecurityScopedAccess: Bool
    private let onClose: () -> Void

    init(folderURL: URL, onClose: @escaping () -> Void) {
        self.folderURL = folderURL
        hasSecurityScopedAccess = folderURL.startAccessingSecurityScopedResource()
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = folderURL.lastPathComponent
        window.minSize = NSSize(width: 760, height: 560)
        window.contentViewController = NSHostingController(
            rootView: WebcardFolderView(folderURL: folderURL)
        )
        window.tabbingMode = .preferred
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        WebcardFolderCommandCenter.shared.hasActiveFolder = false
        if hasSecurityScopedAccess {
            folderURL.stopAccessingSecurityScopedResource()
        }
        onClose()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        WebcardFolderCommandCenter.shared.hasActiveFolder = true
    }

    func windowDidResignKey(_ notification: Notification) {
        WebcardFolderCommandCenter.shared.hasActiveFolder = false
    }
}
