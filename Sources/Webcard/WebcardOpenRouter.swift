import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import WebcardCore

private struct WebcardPointingHandCursor: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { isHovering in
            (isHovering ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
    }
}

extension View {
    func webcardPointingHandCursor() -> some View {
        modifier(WebcardPointingHandCursor())
    }
}

@MainActor
final class WebcardAppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: WebcardAppDelegate?

    private var welcomeWindowController: WebcardWelcomeWindowController?
    private var bulkImportWindowController: WebcardBulkImportWindowController?
    private var addWebcardWindowController: WebcardAddWindowController?
    private var openedItemsAtLaunch = false

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }

        let isDefaultLaunch = Self.isDefaultLaunch(notification)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  isDefaultLaunch,
                  !openedItemsAtLaunch else {
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

    static func isDefaultLaunch(_ notification: Notification) -> Bool {
        (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? NSNumber)?
            .boolValue == true
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
            importURLs: { [weak self] in
                self?.showBulkImportWindow()
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

    func showBulkImportWindow(
        destinationDirectory: URL? = nil,
        initialInput: String = ""
    ) {
        if let bulkImportWindowController,
           initialInput.isEmpty,
           destinationDirectory == nil
                || bulkImportWindowController.destinationDirectory == destinationDirectory {
            bulkImportWindowController.showWindow(nil)
            bulkImportWindowController.window?.makeKeyAndOrderFront(nil)
            return
        }

        bulkImportWindowController?.close()
        let controller = WebcardBulkImportWindowController(
            destinationDirectory: destinationDirectory,
            initialInput: initialInput,
            onFinished: { [weak self] destinationDirectory in
                self?.bulkImportWindowController?.close()
                self?.bulkImportWindowController = nil
                WebcardOpenRouter.open(destinationDirectory)
            }
        )
        bulkImportWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func showAddWebcardWindow(
        destinationDirectory: URL,
        onCreated: @escaping (URL) -> Void
    ) {
        addWebcardWindowController?.close()

        let controller = WebcardAddWindowController(
            destinationDirectory: destinationDirectory,
            importURLs: { [weak self] in
                self?.addWebcardWindowController?.close()
                self?.addWebcardWindowController = nil
                self?.showBulkImportWindow(destinationDirectory: destinationDirectory)
            },
            onCreated: { [weak self] fileURL in
                self?.addWebcardWindowController?.close()
                self?.addWebcardWindowController = nil
                onCreated(fileURL)
            }
        )
        addWebcardWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
enum WebcardOpenRouter {
    private static var folderWindows: [URL: WebcardFolderWindowController] = [:]
    private static var webLocationWindows: [URL: WebcardWebLocationWindowController] = [:]

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
            if !url.isFileURL,
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                WebcardAppDelegate.shared?.showBulkImportWindow(
                    initialInput: url.absoluteString
                )
                return
            }

            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true {
                openFolder(url)
            } else if values.isRegularFile == true {
                switch url.pathExtension.lowercased() {
                case "webcard":
                    openDocument(url)
                case "webloc":
                    let hasAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if hasAccess {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    let webLocationURL = try WebcardWebloc.read(
                        Data(contentsOf: url, options: .mappedIfSafe)
                    )
                    openWebLocation(url, webLocationURL: webLocationURL)
                default:
                    throw CocoaError(
                        .fileReadUnsupportedScheme,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Choose a .webcard or .webloc file, or a folder containing them."
                        ]
                    )
                }
            } else {
                throw CocoaError(
                    .fileReadUnsupportedScheme,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Choose a .webcard or .webloc file, or a folder containing them."
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

    private static func openWebLocation(_ fileURL: URL, webLocationURL: URL) {
        let standardizedURL = fileURL.standardizedFileURL
        if let controller = webLocationWindows[standardizedURL] {
            NSApp.activate(ignoringOtherApps: true)
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = WebcardWebLocationWindowController(
            fileURL: standardizedURL,
            webLocationURL: webLocationURL
        ) {
            webLocationWindows[standardizedURL] = nil
        }
        webLocationWindows[standardizedURL] = controller
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
        importURLs: @escaping () -> Void,
        selectItems: @escaping () -> Void,
        openItems: @escaping ([URL]) -> Void
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 690),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Webcard"
        window.contentViewController = NSHostingController(
            rootView: WebcardWelcomeView(
                createWebcard: createWebcard,
                importURLs: importURLs,
                selectItems: selectItems,
                openItems: openItems
            )
        )
        window.setContentSize(NSSize(width: 820, height: 690))
        window.contentMinSize = NSSize(width: 700, height: 620)
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

final class WebcardDroppedFileLoader: @unchecked Sendable {
    private let providers: [NSItemProvider]
    private let completion: @MainActor ([URL]) -> Void
    private var index = 0
    private var urls: [URL] = []

    private init(
        providers: [NSItemProvider],
        completion: @escaping @MainActor ([URL]) -> Void
    ) {
        self.providers = providers
        self.completion = completion
    }

    @MainActor
    static func load(
        _ providers: [NSItemProvider],
        completion: @escaping @MainActor ([URL]) -> Void
    ) {
        WebcardDroppedFileLoader(
            providers: providers,
            completion: completion
        ).loadNext()
    }

    private func loadNext() {
        guard index < providers.count else {
            let urls = urls
            Task { @MainActor in
                completion(urls)
            }
            return
        }

        let provider = providers[index]
        index += 1
        provider.loadDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier
        ) { [self] data, _ in
            if let data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                urls.append(url)
            }
            loadNext()
        }
    }
}

private struct WebcardWelcomeView: View {
    let createWebcard: (WebcardFile) throws -> Void
    let importURLs: () -> Void
    let selectItems: () -> Void
    let openItems: ([URL]) -> Void

    @State private var isCreating = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Webcard")
                .font(.largeTitle.weight(.semibold))

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ],
                spacing: 16
            ) {
                createFromURLCard
                importManyURLsCard
                openItemsCard
                dropItemsCard
            }

        }
        .padding(32)
        .frame(minWidth: 700, idealWidth: 820, minHeight: 620, idealHeight: 690)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $isDropTargeted
        ) { providers in
            guard !isCreating, !providers.isEmpty else {
                return false
            }
            WebcardDroppedFileLoader.load(providers) { urls in
                guard !urls.isEmpty else {
                    return
                }
                openItems(urls)
            }
            return true
        }
    }

    private var createFromURLCard: some View {
        welcomeAction(
            title: "Create from URL",
            detail: "Paste a link to generate a webcard with its title, description, and image.",
            systemImage: "link",
            iconColor: .blue
        ) {
            WebcardCreationPanel(
                isCreating: $isCreating,
                showsInstructions: false,
                isEmbedded: true,
                stacksControls: true
            ) {
                try createWebcard($0)
                return nil
            }
        }
    }

    private var importManyURLsCard: some View {
        welcomeAction(
            title: "Import URLs",
            detail: "Paste a list of website addresses and create cards slowly with per-domain rate limiting.",
            systemImage: "text.badge.plus",
            iconColor: .purple
        ) {
            Button(action: importURLs) {
                Label("Import URLs", systemImage: "text.badge.plus")
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .webcardPointingHandCursor()
        }
        .disabled(isCreating)
        .opacity(isCreating ? 0.45 : 1)
    }

    private var openItemsCard: some View {
        welcomeAction(
            title: "Open a File or Folder",
            detail: "Choose a .webcard or .webloc file, or a folder containing multiple cards.",
            systemImage: "doc",
            iconColor: .orange
        ) {
            Button("Choose File or Folder…", action: selectItems)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("o")
                .frame(maxWidth: .infinity)
                .webcardPointingHandCursor()
        }
        .disabled(isCreating)
        .opacity(isCreating ? 0.45 : 1)
    }

    private var dropItemsCard: some View {
        welcomeAction(
            title: "Drag and Drop",
            detail: "Drop a .webcard, .webloc, website URL, or folder here.",
            systemImage: "square.and.arrow.down",
            iconColor: .green,
            isActive: isDropTargeted,
            isDashed: true
        ) {
            Text("Drop Here")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .disabled(isCreating)
        .opacity(isCreating ? 0.45 : 1)
    }

    private func welcomeAction<Content: View>(
        title: String,
        detail: String,
        systemImage: String,
        iconColor: Color,
        isActive: Bool = false,
        isDashed: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(width: 54, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(iconColor)
                )

            Text(title)
                .font(.title3.weight(.semibold))

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 250, maxHeight: 250, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    isActive
                        ? Color.accentColor.opacity(0.12)
                        : Color.secondary.opacity(0.08)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isActive ? Color.accentColor : Color.secondary.opacity(0.32),
                    style: StrokeStyle(
                        lineWidth: isActive ? 2 : 1,
                        dash: isDashed ? [8] : []
                    )
                )
        }
    }
}

@MainActor
private final class WebcardAddWindowController: NSWindowController {
    init(
        destinationDirectory: URL,
        importURLs: @escaping () -> Void,
        onCreated: @escaping (URL) -> Void
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Add Webcard"
        window.contentViewController = NSHostingController(
            rootView: WebcardAddOptionsView(
                destinationDirectory: destinationDirectory,
                importURLs: importURLs,
                onCreated: onCreated
            )
        )
        window.contentMinSize = NSSize(width: 700, height: 390)
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

private struct WebcardAddOptionsView: View {
    let destinationDirectory: URL
    let importURLs: () -> Void
    let onCreated: (URL) -> Void

    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Add Webcard")
                .font(.largeTitle.weight(.semibold))

            HStack(spacing: 16) {
                optionCard(
                    title: "Create from URL",
                    detail: "Paste a link to generate a webcard with its title, description, and image.",
                    systemImage: "link",
                    iconColor: .blue
                ) {
                    WebcardCreationPanel(
                        isCreating: $isCreating,
                        showsInstructions: false,
                        isEmbedded: true,
                        stacksControls: true,
                        createWebcard: { file in
                            try WebcardFolderFileWriter.write(
                                file,
                                to: destinationDirectory
                            )
                        },
                        onCreated: { fileURL in
                            if let fileURL {
                                onCreated(fileURL)
                            }
                        }
                    )
                }

                optionCard(
                    title: "Import URLs",
                    detail: "Paste a list of website addresses and create cards slowly with per-domain rate limiting.",
                    systemImage: "text.badge.plus",
                    iconColor: .purple
                ) {
                    Button(action: importURLs) {
                        Label("Import URLs", systemImage: "text.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .webcardPointingHandCursor()
                }
                .disabled(isCreating)
                .opacity(isCreating ? 0.45 : 1)
            }
        }
        .padding(32)
        .frame(minWidth: 700, idealWidth: 820, minHeight: 390, idealHeight: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func optionCard<Content: View>(
        title: String,
        detail: String,
        systemImage: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(width: 54, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(iconColor)
                )

            Text(title)
                .font(.title3.weight(.semibold))

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 250, maxHeight: 250, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.32), lineWidth: 1)
        }
    }
}

struct WebcardCreationPanel: View {
    @Binding var isCreating: Bool
    let showsInstructions: Bool
    let isEmbedded: Bool
    let stacksControls: Bool
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
        .padding(isEmbedded ? 0 : showsInstructions ? 18 : 12)
        .frame(maxWidth: .infinity, minHeight: showsInstructions ? 150 : nil)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isEmbedded ? Color.clear : panelColor)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isEmbedded ? Color.clear : panelBorderColor,
                    lineWidth: isCreating || errorMessage != nil ? 2 : 1
                )
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

            let layout = stacksControls
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                TextField("example.com or https://example.com", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .onSubmit(create)
                    .onChange(of: address) {
                        errorMessage = nil
                    }

                Button(errorMessage == nil ? "Create Webcard" : "Try Again", action: create)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(requestPlan == nil)
                    .frame(maxWidth: stacksControls ? .infinity : nil)
                    .webcardPointingHandCursor()
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

@MainActor
private final class WebcardBulkImportWindowController: NSWindowController {
    let destinationDirectory: URL?

    init(
        destinationDirectory: URL?,
        initialInput: String = "",
        onFinished: @escaping @MainActor (URL) -> Void
    ) {
        self.destinationDirectory = destinationDirectory
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Import URLs"
        window.contentViewController = NSHostingController(
            rootView: WebcardBulkImportView(
                destinationDirectory: destinationDirectory,
                initialInput: initialInput,
                onFinished: onFinished
            )
        )
        window.contentMinSize = NSSize(width: 560, height: 460)
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

private struct WebcardBulkImportFailure: Identifiable {
    let id = UUID()
    let address: String
    let message: String
}

private struct WebcardBulkImportView: View {
    let onFinished: @MainActor (URL) -> Void

    @State var destinationDirectory: URL?
    @State private var input: String
    @State private var isImporting = false
    @State private var completedCount = 0
    @State private var currentAddress: String?
    @State private var failures: [WebcardBulkImportFailure] = []
    @State private var importTask: Task<Void, Never>?

    private var batch: WebcardBulkImportBatch {
        WebcardBulkImportBatch.parse(input)
    }

    init(
        destinationDirectory: URL?,
        initialInput: String = "",
        onFinished: @escaping @MainActor (URL) -> Void
    ) {
        self.onFinished = onFinished
        _destinationDirectory = State(initialValue: destinationDirectory)
        _input = State(initialValue: initialInput)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import URLs")
                .font(.title2.weight(.semibold))

            Text("Paste one public website address per line. Imports run one at a time, with at least eight seconds between captures started for the same domain.")
                .foregroundStyle(.secondary)

            TextEditor(text: $input)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25))
                }
                .disabled(isImporting)

            destinationRow
            validationSummary

            if isImporting || completedCount > 0 || !failures.isEmpty {
                importStatus
            }

            HStack {
                Spacer()
                if isImporting {
                    Button("Cancel", role: .cancel) {
                        importTask?.cancel()
                    }
                    .webcardPointingHandCursor()
                }
                Button(isImporting ? "Importing…" : "Import URLs", action: startImport)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isImporting || destinationDirectory == nil || batch.plans.isEmpty)
                    .webcardPointingHandCursor()
            }
        }
        .padding(24)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 460, idealHeight: 560)
        .onDisappear {
            importTask?.cancel()
        }
    }

    private var destinationRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(destinationDirectory?.path(percentEncoded: false) ?? "Choose a destination folder")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(destinationDirectory == nil ? .secondary : .primary)
            Spacer()
            Button("Choose Folder…", action: chooseDestination)
                .disabled(isImporting)
                .webcardPointingHandCursor()
        }
    }

    @ViewBuilder
    private var validationSummary: some View {
        let parsedBatch = batch
        if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HStack(spacing: 12) {
                Text("\(parsedBatch.plans.count) valid URL\(parsedBatch.plans.count == 1 ? "" : "s")")
                if parsedBatch.duplicateCount > 0 {
                    Text("\(parsedBatch.duplicateCount) duplicate\(parsedBatch.duplicateCount == 1 ? "" : "s") skipped")
                }
                if !parsedBatch.invalidInputs.isEmpty {
                    Text("\(parsedBatch.invalidInputs.count) invalid")
                        .foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var importStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isImporting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Imported \(completedCount) of \(batch.plans.count)")
                    if let currentAddress {
                        Text(currentAddress)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("Imported \(completedCount) webcard\(completedCount == 1 ? "" : "s").")
                    .font(.headline)
            }

            if !failures.isEmpty {
                DisclosureGroup("\(failures.count) failed") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(failures) { failure in
                            Text("\(failure.address): \(failure.message)")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose Import Destination"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            destinationDirectory = panel.url?.standardizedFileURL
        }
    }

    private func startImport() {
        let parsedBatch = batch
        guard let destinationDirectory, !parsedBatch.plans.isEmpty, !isImporting else {
            return
        }

        isImporting = true
        completedCount = 0
        failures = parsedBatch.invalidInputs.map {
            WebcardBulkImportFailure(address: $0, message: "Invalid HTTP or HTTPS address.")
        }
        let plans = parsedBatch.plans
        let hasSecurityScopedAccess = destinationDirectory.startAccessingSecurityScopedResource()

        importTask = Task {
            var completedNormally = false
            defer {
                if hasSecurityScopedAccess {
                    destinationDirectory.stopAccessingSecurityScopedResource()
                }
                isImporting = false
                currentAddress = nil
                importTask = nil
                if completedNormally {
                    onFinished(destinationDirectory)
                }
            }

            let refresher = WebcardRefresher()
            let rateLimiter = WebcardDomainRateLimiter()
            for plan in plans {
                guard !Task.isCancelled else {
                    return
                }
                currentAddress = plan.preferredURL.absoluteString
                do {
                    try await rateLimiter.wait(for: plan.preferredURL)
                    let result = try await refresher.capture(plan: plan)
                    let file = WebcardFile(
                        sourceURL: result.sourceURL,
                        captures: [result.capture]
                    )
                    _ = try WebcardFolderFileWriter.write(file, to: destinationDirectory)
                    completedCount += 1
                } catch is CancellationError {
                    return
                } catch {
                    var message = error.localizedDescription
                    do {
                        _ = try WebcardFolderFileWriter.writeWebloc(
                            for: plan.preferredURL,
                            to: destinationDirectory
                        )
                    } catch {
                        message += " The .webloc fallback could not be saved: \(error.localizedDescription)"
                    }
                    failures.append(
                        WebcardBulkImportFailure(
                            address: plan.preferredURL.absoluteString,
                            message: message
                        )
                    )
                }
            }
            completedNormally = true
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
        panel.allowedContentTypes = [
            .webcard,
            UTType(filenameExtension: "webloc")
        ].compactMap { $0 }
        return panel.runModal() == .OK ? panel.urls : nil
    }
}

@MainActor
private final class WebcardFolderWindowController: NSWindowController, NSWindowDelegate {
    private let folderURL: URL
    private let commandID = UUID()
    private let hasSecurityScopedAccess: Bool
    private let onClose: () -> Void
    private let session: WebcardFolderWindowSession
    private let toolbarController: WebcardFolderToolbarController

    init(folderURL: URL, onClose: @escaping () -> Void) {
        self.folderURL = folderURL
        hasSecurityScopedAccess = folderURL.startAccessingSecurityScopedResource()
        self.onClose = onClose
        session = WebcardFolderWindowSession(folderURL: folderURL)
        toolbarController = WebcardFolderToolbarController(session: session)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = folderURL.lastPathComponent
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.styleMask.insert(.fullSizeContentView)
        window.minSize = NSSize(width: 760, height: 560)
        let hostingController = NSHostingController(
            rootView: WebcardFolderView(session: session)
        )
        window.contentViewController = hostingController
        window.tabbingMode = .preferred
        window.center()

        super.init(window: window)
        window.delegate = self
        hostingController.view.layoutSubtreeIfNeeded()
        window.toolbar = toolbarController.makeToolbar(
            tracking: hostingController.view.firstDescendant(ofType: NSSplitView.self)
        )
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

private extension NSView {
    func firstDescendant<ViewType: NSView>(ofType type: ViewType.Type) -> ViewType? {
        if let matchingView = self as? ViewType {
            return matchingView
        }
        for subview in subviews {
            if let matchingView = subview.firstDescendant(ofType: type) {
                return matchingView
            }
        }
        return nil
    }
}

private extension NSToolbarItem.Identifier {
    static let webcardSidebarToggle = Self("webcard.sidebar-toggle")
    static let webcardSidebarSeparator = Self("webcard.sidebar-separator")
    static let webcardBack = Self("webcard.back")
    static let webcardForward = Self("webcard.forward")
    static let webcardFolderTitle = Self("webcard.folder-title")
    static let webcardSearch = Self("webcard.search")
    static let webcardAdd = Self("webcard.add")
}

@MainActor
private final class WebcardFolderToolbarController:
    NSObject,
    NSToolbarDelegate,
    NSToolbarItemValidation
{
    private let session: WebcardFolderWindowSession
    private weak var toolbar: NSToolbar?
    private weak var trackedSplitView: NSSplitView?
    private weak var titleLabel: NSTextField?
    private weak var searchField: NSSearchField?
    private var cancellables: Set<AnyCancellable> = []

    init(session: WebcardFolderWindowSession) {
        self.session = session
        super.init()

        session.browserModel.$navigationPath
            .sink { [weak self] _ in
                self?.updateNavigationItems()
            }
            .store(in: &cancellables)

        session.$searchText
            .removeDuplicates()
            .sink { [weak self] searchText in
                guard self?.searchField?.stringValue != searchText else {
                    return
                }
                self?.searchField?.stringValue = searchText
            }
            .store(in: &cancellables)

        WebcardFolderSettings.shared.$isDirectoryDrawerVisible
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.rebuildToolbarItems()
                }
            }
            .store(in: &cancellables)
    }

    func makeToolbar(tracking splitView: NSSplitView?) -> NSToolbar {
        trackedSplitView = splitView
        let toolbar = NSToolbar(identifier: "webcard.folder-toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .regular
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        self.toolbar = toolbar
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        if WebcardFolderSettings.shared.isDirectoryDrawerVisible {
            return [
                .flexibleSpace,
                .webcardSidebarToggle,
                trackedSplitView == nil ? .sidebarTrackingSeparator : .webcardSidebarSeparator,
                .webcardBack,
                .webcardForward,
                .webcardFolderTitle,
                .flexibleSpace,
                .webcardSearch,
                .webcardAdd
            ]
        }
        return [
            .webcardSidebarToggle,
            .webcardBack,
            .webcardForward,
            .webcardFolderTitle,
            .flexibleSpace,
            .webcardSearch,
            .webcardAdd
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .webcardSidebarToggle:
            return buttonItem(
                identifier: itemIdentifier,
                label: "Toggle Sidebar",
                systemImage: "sidebar.left",
                action: #selector(toggleSidebar)
            )
        case .webcardSidebarSeparator:
            guard let trackedSplitView else {
                return nil
            }
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: trackedSplitView,
                dividerIndex: 0
            )
        case .webcardBack:
            return buttonItem(
                identifier: itemIdentifier,
                label: "Back",
                systemImage: "chevron.left",
                action: #selector(goBack)
            )
        case .webcardForward:
            return buttonItem(
                identifier: itemIdentifier,
                label: "Forward",
                systemImage: "chevron.right",
                action: #selector(goForward)
            )
        case .webcardFolderTitle:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let titleLabel = NSTextField(labelWithString: session.browserModel.currentURL.lastPathComponent)
            titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            item.view = titleLabel
            item.label = "Current Folder"
            item.visibilityPriority = .high
            self.titleLabel = titleLabel
            return item
        case .webcardSearch:
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            let searchField = NSSearchField()
            searchField.placeholderString = "Search webcards"
            searchField.stringValue = session.searchText
            searchField.target = self
            searchField.action = #selector(searchChanged)
            searchField.sendsSearchStringImmediately = true
            item.searchField = searchField
            item.preferredWidthForSearchField = 280
            item.visibilityPriority = .high
            self.searchField = searchField
            return item
        case .webcardAdd:
            let item = buttonItem(
                identifier: itemIdentifier,
                label: "Add Webcard",
                systemImage: "plus",
                action: #selector(addWebcard)
            )
            item.visibilityPriority = .high
            return item
        default:
            return nil
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case .webcardBack:
            return session.browserModel.canGoBack
        case .webcardForward:
            return false
        default:
            return true
        }
    }

    private func buttonItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        systemImage: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: label)
        item.target = self
        item.action = action
        return item
    }

    private func updateNavigationItems() {
        titleLabel?.stringValue = session.browserModel.currentURL.lastPathComponent
        toolbar?.validateVisibleItems()
    }

    private func rebuildToolbarItems() {
        guard let toolbar else {
            return
        }
        for index in toolbar.items.indices.reversed() {
            toolbar.removeItem(at: index)
        }
        for (index, identifier) in toolbarDefaultItemIdentifiers(toolbar).enumerated() {
            toolbar.insertItem(withItemIdentifier: identifier, at: index)
        }
    }

    @objc private func toggleSidebar() {
        WebcardFolderSettings.shared.isDirectoryDrawerVisible.toggle()
    }

    @objc private func goBack() {
        session.browserModel.goBack()
    }

    @objc private func goForward() {}

    @objc private func searchChanged(_ sender: NSSearchField) {
        session.searchText = sender.stringValue
    }

    @objc private func addWebcard() {
        session.addWebcard()
    }
}

@MainActor
private final class WebcardWebLocationWindowController: NSWindowController, NSWindowDelegate {
    private let fileURL: URL
    private let hasSecurityScopedAccess: Bool
    private let onClose: () -> Void

    init(
        fileURL: URL,
        webLocationURL: URL,
        onClose: @escaping () -> Void
    ) {
        self.fileURL = fileURL
        hasSecurityScopedAccess = fileURL.startAccessingSecurityScopedResource()
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = fileURL.deletingPathExtension().lastPathComponent
        window.contentViewController = NSHostingController(
            rootView: WebcardWebLocationDocumentView(
                fileURL: fileURL,
                url: webLocationURL
            )
        )
        window.minSize = NSSize(width: 360, height: 420)
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
        if hasSecurityScopedAccess {
            fileURL.stopAccessingSecurityScopedResource()
        }
        onClose()
    }
}
