import AppKit
import SwiftUI
import WebcardCore

struct WebcardCardView: View {
    let capture: WebcardCapture
    let image: NSImage
    let width: CGFloat
    let imageHeight: CGFloat
    let metadataHeight: CGFloat
    let maximumMetadataHeight: CGFloat?
    let usesInsecureHTTP: Bool
    let masksImage: Bool
    var titleLineLimit: Int?
    var descriptionLineLimit: Int?
    var debugSettings: WebcardDebugSettings?

    init(
        capture: WebcardCapture,
        image: NSImage,
        width: CGFloat,
        imageHeight: CGFloat,
        metadataHeight: CGFloat,
        maximumMetadataHeight: CGFloat?,
        usesInsecureHTTP: Bool,
        masksImage: Bool,
        titleLineLimit: Int? = nil,
        descriptionLineLimit: Int? = nil,
        debugSettings: WebcardDebugSettings? = nil
    ) {
        self.capture = capture
        self.image = image
        self.width = width
        self.imageHeight = imageHeight
        self.metadataHeight = metadataHeight
        self.maximumMetadataHeight = maximumMetadataHeight
        self.usesInsecureHTTP = usesInsecureHTTP
        self.masksImage = masksImage
        self.titleLineLimit = titleLineLimit
        self.descriptionLineLimit = descriptionLineLimit
        self.debugSettings = debugSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Self.cardImage(
                image,
                width: width,
                height: imageHeight,
                maskImage: debugSettings?.maskImage ?? masksImage,
                cropPosition: debugSettings?.cropPosition ?? .center
            )
            .accessibilityLabel(capture.socialMetadata.imageAlt ?? capture.title)
            .contextMenu {
                Button {
                    copyImage()
                } label: {
                    Label("Copy Image", systemImage: "doc.on.doc")
                }
            }

            VStack(alignment: .leading, spacing: WebcardLayoutMetrics.contentInset) {
                SelectableMetadataView(
                    capture: capture,
                    usesInsecureHTTP: usesInsecureHTTP,
                    layoutWidth: width - WebcardLayoutMetrics.contentInset * 2,
                    maximumHeight: maximumMetadataHeight,
                    titleLineLimit: debugSettings?.titleLines ?? titleLineLimit,
                    descriptionLineLimit: debugSettings?.descriptionLines ?? descriptionLineLimit
                )
                .frame(height: metadataHeight, alignment: .top)

                Button {
                    NSWorkspace.shared.open(capture.canonicalURL)
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
                .frame(height: WebcardLayoutMetrics.buttonHeight)
            }
            .padding(WebcardLayoutMetrics.contentInset)
            .frame(width: width, alignment: .topLeading)
        }
        .frame(width: width, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 14, y: 5)
    }

    static func cardImage(
        _ image: NSImage,
        width: CGFloat,
        height: CGFloat,
        maskImage: Bool = false,
        cropPosition: ImageCropPosition = .center
    ) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: maskImage ? .fill : .fit)
            .frame(width: width, height: height, alignment: cropPosition.alignment)
            .clipped()
    }

    private func copyImage() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        pasteboard.setData(
            capture.imageData,
            forType: NSPasteboard.PasteboardType("org.webmproject.webp")
        )
    }
}
