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
        preferredContentSize = NSSize(width: 860, height: 760)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping ((any Error)?) -> Void) {
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let file = try WebcardArchive.read(data)
            guard let capture = file.currentCapture,
                  let image = NSImage(data: capture.imageData) else {
                throw WebcardError.invalidImage
            }
            hostingView.rootView = QuickLookCardView(
                capture: capture,
                sourceURL: file.sourceURL
            )
            preferredContentSize = QuickLookCardView.preferredContentSize(
                capture: capture,
                image: image,
                sourceURL: file.sourceURL
            )
            handler(nil)
        } catch {
            handler(error)
        }
    }
}

private struct QuickLookCardView: View {
    private struct Layout {
        let width: CGFloat
        let imageHeight: CGFloat
        let metadataHeight: CGFloat
        let maximumMetadataHeight: CGFloat

        var cardHeight: CGFloat {
            imageHeight + metadataHeight + WebcardLayoutMetrics.contentInset * 2
        }
    }

    private static let previewWidth: CGFloat = 860
    private static let maximumPreviewHeight: CGFloat = 760
    private static let minimumPreviewHeight: CGFloat = 320
    private static let outerPadding: CGFloat = 24

    let capture: WebcardCapture?
    let sourceURL: URL?

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            if let capture, let image = NSImage(data: capture.imageData) {
                GeometryReader { geometry in
                    let usesInsecureHTTP = sourceURL?.scheme?.lowercased() == "http"
                    let layout = Self.layout(
                        capture: capture,
                        availableSize: geometry.size,
                        imageSize: image.size,
                        usesInsecureHTTP: usesInsecureHTTP
                    )

                    VStack {
                        Spacer(minLength: Self.outerPadding)

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

                        Spacer(minLength: Self.outerPadding)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ProgressView()
            }
        }
    }

    @MainActor
    static func preferredContentSize(
        capture: WebcardCapture,
        image: NSImage,
        sourceURL: URL?
    ) -> NSSize {
        let maximumSize = CGSize(width: previewWidth, height: maximumPreviewHeight)
        let layout = layout(
            capture: capture,
            availableSize: maximumSize,
            imageSize: image.size,
            usesInsecureHTTP: sourceURL?.scheme?.lowercased() == "http"
        )
        return NSSize(
            width: previewWidth,
            height: min(
                maximumPreviewHeight,
                max(minimumPreviewHeight, layout.cardHeight + outerPadding * 2)
            )
        )
    }

    @MainActor
    private static func layout(
        capture: WebcardCapture,
        availableSize: CGSize,
        imageSize: CGSize,
        usesInsecureHTTP: Bool
    ) -> Layout {
        let width = min(
            WebcardLayoutMetrics.maximumCardWidth,
            max(1, availableSize.width - outerPadding * 2)
        )
        let metadataWidth = max(1, width - WebcardLayoutMetrics.contentInset * 2)
        let minimumMetadataHeight = SelectableMetadataView.minimumHeight(
            for: capture,
            usesInsecureHTTP: usesInsecureHTTP,
            width: metadataWidth
        )
        let availableCardHeight = max(1, availableSize.height - outerPadding * 2)
        let availableContentHeight = max(
            1,
            availableCardHeight - WebcardLayoutMetrics.contentInset * 2
        )
        let naturalImageHeight = imageSize.width > 0 && imageSize.height > 0
            ? width * imageSize.height / imageSize.width
            : WebcardLayoutMetrics.compactImageHeight
        let imageHeight = min(
            naturalImageHeight,
            max(1, availableContentHeight - minimumMetadataHeight)
        )
        let maximumMetadataHeight = max(
            minimumMetadataHeight,
            availableContentHeight - imageHeight
        )
        let metadataHeight = SelectableMetadataView.height(
            for: capture,
            usesInsecureHTTP: usesInsecureHTTP,
            width: metadataWidth,
            maximumHeight: maximumMetadataHeight
        )
        return Layout(
            width: width,
            imageHeight: imageHeight,
            metadataHeight: metadataHeight,
            maximumMetadataHeight: maximumMetadataHeight
        )
    }
}
