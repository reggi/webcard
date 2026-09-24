import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebcardCore

@MainActor
final class WebcardAppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: WebcardAppDelegate?

    private var welcomeWindowController: WebcardWelcomeWindowController?
    private var openedItemsAtLaunch = false

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !openedItemsAtLaunch else {
                return
            }

            let documents = NSDocumentController.shared.documents
            guard !documents.contains(where: { $0.fileURL != nil }) else {
                return
            }
            documents.forEach { $0.close() }
            showStartWindow()
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        showStartWindow()
        // Claim the request so SwiftUI does not create a blank document afterward.
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openedItemsAtLaunch = true
        welcomeWindowController?.close()
        WebcardOpenRouter.open(urls)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            showStartWindow()
        }
        return true
    }

    func showStartWindow() {
        if let welcomeWindowController {
            welcomeWindowController.showWindow(nil)
            welcomeWindowController.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = WebcardWelcomeWindowController(
            createWebcard: { [weak self] file in
                try WebcardOpenRouter.createDocument(file)
                self?.welcomeWindowController?.close()
            },
            selectItems: { [weak self] in
                guard let urls = WebcardOpenPanel.selectItems() else {
                    return
                }
                self?.welcomeWindowController?.close()
                WebcardOpenRouter.open(urls)
            },
            openItems: { [weak self] urls in
                self?.welcomeWindowController?.close()
                WebcardOpenRouter.open(urls)
            }
        )
        welcomeWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
enum WebcardOpenRouter {
    private static var folderWindows: [URL: WebcardFolderWindowController] = [:]

    static func createDocument(_ file: WebcardFile) throws {
        let fileType = UTType.webcard.identifier
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("webcard-\(UUID().uuidString)")
            .appendingPathExtension("webcard")

        try WebcardArchive.write(file).write(to: temporaryURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        let controller = NSDocumentController.shared
        let document = try controller.makeDocument(
            withContentsOf: temporaryURL,
            ofType: fileType
        )
        document.fileURL = nil
        document.displayName = file.suggestedFilename
        controller.addDocument(document)
        document.makeWindowControllers()
        document.updateChangeCount(.changeDone)
        document.showWindows()
    }

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
private final class WebcardWelcomeWindowController: NSWindowController {
    init(
        createWebcard: @escaping (WebcardFile) throws -> Void,
        selectItems: @escaping () -> Void,
        openItems: @escaping ([URL]) -> Void
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Webcard"
        window.contentViewController = NSHostingController(
            rootView: WebcardWelcomeView(
                createWebcard: createWebcard,
                selectItems: selectItems,
                openItems: openItems
            )
        )
        window.setContentSize(NSSize(width: 680, height: 480))
        window.contentMinSize = NSSize(width: 560, height: 430)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct WebcardWelcomeView: View {
    let createWebcard: (WebcardFile) throws -> Void
    let selectItems: () -> Void
    let openItems: ([URL]) -> Void

    @State private var isCreating = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Webcard")
                .font(.largeTitle.weight(.semibold))

            openingActions
            WebcardCreationPanel(
                isCreating: $isCreating,
                showsInstructions: true
            ) { file in
                try createWebcard(file)
                return nil
            }
        }
        .padding(32)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 430, idealHeight: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var openingActions: some View {
        HStack(spacing: 16) {
            welcomeAction(
                title: "Open a Webcard or Folder",
                detail: "Choose a .webcard file or a folder of webcards.",
                systemImage: "folder"
            ) {
                Button("Choose File or Folder", action: selectItems)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut("o")
            }

            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 32))

                Text("Drag and Drop a Webcard or Folder")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("Drop a .webcard file or a folder of webcards.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        isDropTargeted
                            ? Color.accentColor.opacity(0.14)
                            : Color.secondary.opacity(0.08)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.45),
                        style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [7])
                    )
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard !urls.isEmpty else {
                    return false
                }
                openItems(urls)
                return true
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
        }
        .disabled(isCreating)
        .opacity(isCreating ? 0.45 : 1)
    }

    private func welcomeAction<Content: View>(
        title: String,
        detail: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.tint)

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.08))
        )
    }

}

struct WebcardCreationPanel: View {
    @Binding var isCreating: Bool
    let showsInstructions: Bool
    let createWebcard: (WebcardFile) throws -> URL?
    var onCreated: (URL?) -> Void = { _ in }

    @State private var address = ""
    @State private var creationProgress = WebcardCaptureProgress.loadingPage
    @State private var errorMessage: String?

    private let refresher = WebcardRefresher()

    var body: some View {
        Group {
            if isCreating {
                creatingContent
            } else {
                createForm
            }
        }
        .padding(showsInstructions ? 18 : 12)
        .frame(maxWidth: .infinity, minHeight: showsInstructions ? 150 : nil)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(panelColor)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(panelBorderColor, lineWidth: isCreating || errorMessage != nil ? 2 : 1)
        }
        .animation(.easeInOut(duration: 0.2), value: isCreating)
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }

    private var creatingContent: some View {
        VStack(spacing: showsInstructions ? 12 : 8) {
            if showsInstructions {
                Image(systemName: creationProgress.systemImage)
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse)

                Text("Creating Webcard")
                    .font(.title3.weight(.semibold))
            }

            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(creationProgress.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(requestPlan?.preferredURL.host() ?? address)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if showsInstructions {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 360)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private var createForm: some View {
        VStack(spacing: 10) {
            if showsInstructions {
                Text(errorMessage == nil ? "Create a Webcard" : "Webcard Creation Failed")
                    .font(.headline)

                if errorMessage == nil {
                    Text("Enter a public website address to create its first saved capture.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                TextField("example.com or https://example.com", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(create)
                    .onChange(of: address) {
                        errorMessage = nil
                    }

                Button(errorMessage == nil ? "Create Webcard" : "Try Again", action: create)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(requestPlan == nil)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private var requestPlan: WebcardRequestPlan? {
        WebcardAddress.requestPlan(from: address)
    }

    private var panelColor: Color {
        if isCreating {
            return Color.accentColor.opacity(0.14)
        }
        if errorMessage != nil {
            return Color.red.opacity(0.09)
        }
        return Color.secondary.opacity(0.08)
    }

    private var panelBorderColor: Color {
        if isCreating {
            return Color.accentColor.opacity(0.8)
        }
        if errorMessage != nil {
            return Color.red.opacity(0.75)
        }
        return showsInstructions ? .clear : Color.secondary.opacity(0.25)
    }

    private func create() {
        guard let plan = requestPlan, !isCreating else {
            return
        }
        isCreating = true
        errorMessage = nil
        creationProgress = .loadingPage

        Task {
            do {
                let result = try await refresher.capture(plan: plan) { progress in
                    creationProgress = progress
                }
                let file = WebcardFile(
                    sourceURL: result.sourceURL,
                    captures: [result.capture]
                )
                let fileURL = try createWebcard(file)
                isCreating = false
                onCreated(fileURL)
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}

private extension WebcardCaptureProgress {
    var message: String {
        switch self {
        case .loadingPage:
            "Loading the website…"
        case .readingMetadata:
            "Reading the page details…"
        case .loadingImage:
            "Downloading the preview image…"
        case .creatingPreview:
            "Creating a preview image…"
        case .loadingIcon:
            "Downloading the site icon…"
        case .buildingCard:
            "Building the webcard…"
        case .retryingWithoutTLS:
            "Secure connection failed. Trying HTTP…"
        }
    }

    var systemImage: String {
        switch self {
        case .loadingPage, .retryingWithoutTLS:
            "network"
        case .readingMetadata:
            "text.magnifyingglass"
        case .loadingImage, .creatingPreview:
            "photo"
        case .loadingIcon:
            "app.badge"
        case .buildingCard:
            "rectangle.stack.badge.plus"
        }
    }
}

@MainActor
enum WebcardOpenPanel {
    static func selectItems() -> [URL]? {
        let panel = NSOpenPanel()
        panel.title = "Open Webcard or Folder"
        panel.prompt = "Open"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.webcard]
        return panel.runModal() == .OK ? panel.urls : nil
    }
}

@MainActor
private final class WebcardFolderWindowController: NSWindowController, NSWindowDelegate {
    private let folderURL: URL
    private let commandID = UUID()
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
        WebcardFolderCommandCenter.shared.deactivate(id: commandID)
        if hasSecurityScopedAccess {
            folderURL.stopAccessingSecurityScopedResource()
        }
        onClose()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        WebcardFolderCommandCenter.shared.activate(id: commandID)
    }

    func windowDidResignKey(_ notification: Notification) {
        WebcardFolderCommandCenter.shared.deactivate(id: commandID)
    }
}
