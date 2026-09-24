import AppKit
import SwiftUI
import WebcardCore

struct WebcardDocumentView: View {
    private static let outerPadding = WebcardLayoutMetrics.outerPadding

    @Binding var document: WebcardDocument
    @State private var selectedCaptureID: String?
    @State private var isRefreshing = false
    @State private var alertTitle = "Refresh Failed"
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var truncatesText = true
    @State private var metadataWindow: NSWindow?

    private let refresher = WebcardRefresher()

    private var selectedCapture: WebcardCapture? {
        let id = selectedCaptureID ?? document.file.currentCaptureID
        return document.file.captures.first { $0.id == id } ?? document.file.currentCapture
    }

    var body: some View {
        VStack(spacing: 0) {
            if let capture = selectedCapture {
                card(capture)
            }
        }
        .focusedSceneValue(\.webcardCommands, commandState)
        .navigationSubtitle(statusMessage ?? "")
        .task {
            selectedCaptureID = document.file.currentCaptureID
        }
        .onDisappear {
            metadataWindow?.close()
            metadataWindow = nil
        }
        .alert(alertTitle, isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "The webcard could not be refreshed.")
        }
    }

    private func card(_ capture: WebcardCapture) -> some View {
        GeometryReader { geometry in
            if let image = NSImage(data: capture.imageData) {
                let usesInsecureHTTP = document.file.sourceURL?.scheme?.lowercased() == "http"
                let layout = Self.cardLayout(
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
                    masksImage: layout.masksImage(image.size)
                )

                if truncatesText && layout.paddedHeight <= geometry.size.height + 0.5 {
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

    static func cardImage(
        _ image: NSImage,
        width: CGFloat,
        height: CGFloat,
        maskImage: Bool = false
    ) -> some View {
        WebcardCardView.cardImage(
            image,
            width: width,
            height: height,
            maskImage: maskImage
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
        masksImage: Bool
    ) -> some View {
        WebcardCardView(
            capture: capture,
            image: image,
            width: width,
            imageHeight: imageHeight,
            metadataHeight: metadataHeight,
            maximumMetadataHeight: maximumMetadataHeight,
            usesInsecureHTTP: usesInsecureHTTP,
            masksImage: masksImage
        )
    }

    private var commandState: WebcardCommandState {
        WebcardCommandState(
            truncatesText: $truncatesText,
            canChangeTruncation: true,
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
            openMetadata: openMetadata
        )
    }

    private func openMetadata() {
        guard let capture = selectedCapture else {
            return
        }
        let snapshot = MetadataSnapshot(
            capture: capture,
            usesInsecureHTTP: document.file.sourceURL?.scheme?.lowercased() == "http"
        )
        let rootView = MetadataWindow(snapshot: snapshot)

        if let metadataWindow {
            metadataWindow.title = snapshot.title.isEmpty ? "Selectable Metadata" : snapshot.title
            metadataWindow.contentViewController = NSHostingController(rootView: rootView)
            NSApp.activate(ignoringOtherApps: true)
            metadataWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = snapshot.title.isEmpty ? "Selectable Metadata" : snapshot.title
        window.contentViewController = NSHostingController(rootView: rootView)
        window.minSize = NSSize(width: 360, height: 280)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        metadataWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private var refreshPlan: WebcardRequestPlan? {
        document.file.sourceURL.map(WebcardRequestPlan.init(url:))
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
        alertTitle = "Refresh Failed"
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
                            statusMessage = "Secure source URL updated. Save the document to keep it."
                        } else {
                            statusMessage = "Webcard is current."
                        }
                    } else {
                        document.file.sourceURL = result.sourceURL
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
