import AppKit
import SwiftUI
import WebcardCore

struct WebcardDocumentView: View {
    private static let outerPadding = WebcardLayoutMetrics.outerPadding
    private static let contentInset = WebcardLayoutMetrics.contentInset
    private static let buttonHeight = WebcardLayoutMetrics.buttonHeight

    @Binding var document: WebcardDocument
    @Environment(\.openWindow) private var openWindow
    @State private var selectedCaptureID: String?
    @State private var address = ""
    @State private var isRefreshing = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var truncatesText = true
    @State private var layoutDebugWindow: NSWindow?
    @State private var debugSettings = WebcardDebugSettings()
    @State private var viewportSize = CGSize.zero

    private let refresher = WebcardRefresher()

    private var selectedCapture: WebcardCapture? {
        let id = selectedCaptureID ?? document.file.currentCaptureID
        return document.file.captures.first { $0.id == id } ?? document.file.currentCapture
    }

    var body: some View {
        VStack(spacing: 0) {
            if let capture = selectedCapture {
                card(capture)
            } else {
                emptyState
            }
        }
        .focusedSceneValue(\.webcardCommands, commandState)
        .navigationSubtitle(statusMessage ?? "")
        .task {
            selectedCaptureID = document.file.currentCaptureID
            address = document.file.sourceURL?.absoluteString ?? ""
        }
        .onDisappear {
            layoutDebugWindow?.close()
            layoutDebugWindow = nil
        }
        .alert("Refresh Failed", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "The webcard could not be refreshed.")
        }
    }

    private func card(_ capture: WebcardCapture) -> some View {
        GeometryReader { geometry in
            if let image = NSImage(data: capture.imageData) {
                let usesInsecureHTTP = document.file.sourceURL?.scheme?.lowercased() == "http"
                let layout = debugSettings.enabled ? Self.desiredLayout(
                    capture: capture,
                    imageSize: image.size,
                    usesInsecureHTTP: usesInsecureHTTP,
                    settings: debugSettings
                ) : Self.cardLayout(
                    capture: capture,
                    availableSize: geometry.size,
                    imageSize: image.size,
                    usesInsecureHTTP: usesInsecureHTTP,
                    truncatesText: truncatesText
                )
                let content = canonicalCard(
                    capture,
                    image: image,
                    width: layout.width,
                    imageHeight: layout.imageHeight,
                    metadataHeight: layout.metadataHeight,
                    maximumMetadataHeight: layout.maximumMetadataHeight,
                    usesInsecureHTTP: usesInsecureHTTP,
                    masksImage: layout.masksImage(image.size),
                    debugSettings: debugSettings.enabled ? debugSettings : nil
                )

                if debugSettings.enabled {
                    ScrollView([.horizontal, .vertical]) {
                        content
                            .padding(Self.outerPadding)
                            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .top)
                    }
                } else if truncatesText && layout.paddedHeight <= geometry.size.height + 0.5 {
                    content
                        .padding(.vertical, layout.verticalPadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView(.vertical) {
                        content
                            .padding(.vertical, layout.verticalPadding)
                            .frame(maxWidth: .infinity)
                    }
                }
                Color.clear
                    .allowsHitTesting(false)
                    .onAppear { viewportSize = geometry.size }
                    .onChange(of: geometry.size) { _, size in viewportSize = size }
            }
        }
    }

    static func cardLayout(
        capture: WebcardCapture,
        availableSize: CGSize,
        imageSize: CGSize,
        usesInsecureHTTP: Bool,
        truncatesText: Bool
    ) -> WebcardCardLayout {
        WebcardLayoutMetrics.cardLayout(
            capture: capture,
            availableSize: availableSize,
            imageSize: imageSize,
            usesInsecureHTTP: usesInsecureHTTP,
            truncatesText: truncatesText
        )
    }

    static func desiredLayout(
        capture: WebcardCapture,
        imageSize: CGSize,
        usesInsecureHTTP: Bool,
        settings: WebcardDebugSettings
    ) -> WebcardCardLayout {
        let imageHeight = settings.maskImage
            ? max(1, settings.imageHeight)
            : settings.cardWidth * imageSize.height / imageSize.width
        let metadataHeight = SelectableMetadataView.height(
            for: capture,
            usesInsecureHTTP: usesInsecureHTTP,
            width: settings.cardWidth - contentInset * 2,
            titleLineLimit: settings.titleLines,
            descriptionLineLimit: settings.descriptionLines
        )
        return WebcardCardLayout(
            width: settings.cardWidth,
            imageHeight: imageHeight,
            metadataHeight: metadataHeight,
            maximumMetadataHeight: nil,
            paddedHeight: imageHeight + metadataHeight + contentInset * 3 + buttonHeight + outerPadding * 2
        )
    }

    static func cardImage(
        _ image: NSImage,
        width: CGFloat,
        height: CGFloat,
        maskImage: Bool = false,
        cropPosition: ImageCropPosition = .center
    ) -> some View {
        WebcardCardView.cardImage(
            image,
            width: width,
            height: height,
            maskImage: maskImage,
            cropPosition: cropPosition
        )
    }

    private func canonicalCard(
        _ capture: WebcardCapture,
        image: NSImage,
        width: CGFloat,
        imageHeight: CGFloat,
        metadataHeight: CGFloat,
        maximumMetadataHeight: CGFloat?,
        usesInsecureHTTP: Bool,
        masksImage: Bool,
        debugSettings: WebcardDebugSettings? = nil
    ) -> some View {
        WebcardCardView(
            capture: capture,
            image: image,
            width: width,
            imageHeight: imageHeight,
            metadataHeight: metadataHeight,
            maximumMetadataHeight: maximumMetadataHeight,
            usesInsecureHTTP: usesInsecureHTTP,
            masksImage: masksImage,
            debugSettings: debugSettings
        )
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text("Create a Webcard")
                .font(.title2.weight(.semibold))

            Text("Enter a public website address, then choose Card > Refresh or press Return to create the first saved capture.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            TextField("example.com or https://example.com", text: $address)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420)
                .onSubmit(refresh)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var commandState: WebcardCommandState {
        WebcardCommandState(
            truncatesText: $truncatesText,
            canChangeTruncation: !debugSettings.enabled,
            canRefresh: !isRefreshing && refreshPlan != nil,
            isRefreshing: isRefreshing,
            versions: document.file.captures.enumerated().reversed().map { index, capture in
                WebcardVersionMenuItem(id: capture.id, title: captureLabel(index: index, capture: capture))
            },
            selectedCaptureID: selectedCapture?.id,
            refresh: refresh,
            selectCapture: { id in
                selectedCaptureID = id
                statusMessage = id == document.file.currentCaptureID ? nil : "Viewing an older capture."
            },
            openLayoutDebug: openLayoutDebug,
            openMetadata: {
                if let capture = selectedCapture {
                    openWindow(
                        id: "webcard-metadata",
                        value: MetadataSnapshot(
                            capture: capture,
                            usesInsecureHTTP: document.file.sourceURL?.scheme?.lowercased() == "http"
                        )
                    )
                }
            }
        )
    }

    private func openLayoutDebug() {
        if let layoutDebugWindow {
            NSApp.activate(ignoringOtherApps: true)
            layoutDebugWindow.makeKeyAndOrderFront(nil)
            return
        }

        let document = $document
        let selectedCaptureID = $selectedCaptureID
        let viewport = $viewportSize
        let truncatesText = $truncatesText
        let settings = $debugSettings
        let rootView = LayoutDebugPanel(
            viewport: viewport,
            settings: settings
        ) {
            let file = document.wrappedValue.file
            let captureID = selectedCaptureID.wrappedValue ?? file.currentCaptureID
            guard let capture = file.captures.first(where: { $0.id == captureID }) ?? file.currentCapture else {
                throw CocoaError(
                    .fileReadUnknown,
                    userInfo: [NSLocalizedDescriptionKey: "No webcard capture is available to debug."]
                )
            }
            return try LayoutDebugCapture.json(
                capture: capture,
                viewport: viewport.wrappedValue,
                usesInsecureHTTP: file.sourceURL?.scheme?.lowercased() == "http",
                truncatesText: truncatesText.wrappedValue,
                settings: settings.wrappedValue
            )
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Layout Debug"
        window.contentViewController = NSHostingController(rootView: rootView)
        window.minSize = NSSize(width: 360, height: 560)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        layoutDebugWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private var refreshPlan: WebcardRequestPlan? {
        if let sourceURL = document.file.sourceURL {
            return WebcardRequestPlan(url: sourceURL)
        }
        return WebcardAddress.requestPlan(from: address)
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func refresh() {
        guard let plan = refreshPlan, !isRefreshing else {
            return
        }
        isRefreshing = true
        statusMessage = "Refreshing…"
        errorMessage = nil

        Task {
            do {
                let result = try await refresher.capture(plan: plan)
                await MainActor.run {
                    let capture = result.capture
                    document.file.lastRefreshedAt = capture.capturedAt
                    if let current = document.file.currentCapture, capture.hasSameContent(as: current) {
                        selectedCaptureID = document.file.currentCaptureID
                        if document.file.sourceURL != result.sourceURL {
                            document.file.sourceURL = result.sourceURL
                            address = result.sourceURL.absoluteString
                            statusMessage = "Secure source URL updated. Save the document to keep it."
                        } else {
                            statusMessage = "Webcard is current."
                        }
                    } else {
                        document.file.sourceURL = result.sourceURL
                        address = result.sourceURL.absoluteString
                        document.file.append(capture)
                        selectedCaptureID = capture.id
                        statusMessage = "New capture added. Save the document to keep it."
                    }
                    isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = nil
                    errorMessage = error.localizedDescription
                    isRefreshing = false
                }
            }
        }
    }

    private func displayedDate(for capture: WebcardCapture) -> Date {
        if capture.id == document.file.currentCaptureID {
            return document.file.lastRefreshedAt ?? capture.capturedAt
        }
        return capture.capturedAt
    }

    private func captureLabel(index: Int, capture: WebcardCapture) -> String {
        let date = displayedDate(for: capture).formatted(date: .abbreviated, time: .shortened)
        return "Capture \(index + 1) · \(date)"
    }

}
