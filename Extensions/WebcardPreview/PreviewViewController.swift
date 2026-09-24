import AppKit
import QuickLookUI
import SwiftUI
import WebcardCore

final class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController {
    private let hostingView = NSHostingView(
        rootView: QuickLookCardView(capture: nil, sourceURL: nil)
    )

    override func loadView() {
        view = hostingView
        preferredContentSize = NSSize(width: 550, height: 550)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping ((any Error)?) -> Void) {
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let file = try WebcardArchive.read(data)
            guard let capture = file.currentCapture,
                  NSImage(data: capture.imageData) != nil else {
                throw WebcardError.invalidImage
            }
            hostingView.rootView = QuickLookCardView(
                capture: capture,
                sourceURL: file.sourceURL
            )
            handler(nil)
        } catch {
            handler(error)
        }
    }
}

private struct QuickLookCardView: View {
    let capture: WebcardCapture?
    let sourceURL: URL?

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            if let capture, let image = NSImage(data: capture.imageData) {
                GeometryReader { geometry in
                    let usesInsecureHTTP = sourceURL?.scheme?.lowercased() == "http"
                    let layout = WebcardLayoutMetrics.cardLayout(
                        capture: capture,
                        availableSize: geometry.size,
                        imageSize: image.size,
                        usesInsecureHTTP: usesInsecureHTTP,
                        truncatesText: true
                    )

                    VStack {
                        Spacer(minLength: 24)

                        VStack(alignment: .leading, spacing: 0) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: layout.width, height: layout.imageHeight)
                                .clipped()

                            SelectableMetadataView(
                                capture: capture,
                                usesInsecureHTTP: usesInsecureHTTP,
                                layoutWidth: layout.width - WebcardLayoutMetrics.contentInset * 2,
                                maximumHeight: layout.maximumMetadataHeight
                            )
                            .frame(height: layout.metadataHeight, alignment: .top)
                            .padding(WebcardLayoutMetrics.contentInset)
                            .frame(width: layout.width, alignment: .leading)
                        }
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.16), radius: 14, y: 5)

                        Spacer(minLength: 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ProgressView()
            }
        }
    }
}
