import AppKit
import QuickLookThumbnailing
import WebcardCore

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, (any Error)?) -> Void
    ) {
        do {
            let data = try Data(contentsOf: request.fileURL, options: .mappedIfSafe)
            let file = try WebcardArchive.read(data)
            guard let capture = file.currentCapture else {
                throw WebcardError.missingCapture
            }
            let image = try thumbnailImage(for: capture, maximumSize: request.maximumSize)
            let targetSize = fittedSize(image.size, inside: request.maximumSize)
            let reply = QLThumbnailReply(contextSize: targetSize) {
                let rect = CGRect(origin: .zero, size: targetSize)
                NSColor.clear.setFill()
                rect.fill()
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                return true
            }
            handler(reply, nil)
        } catch {
            handler(nil, error)
        }
    }

    private func thumbnailImage(
        for capture: WebcardCapture,
        maximumSize: CGSize
    ) throws -> NSImage {
        let maximumDimension = max(maximumSize.width, maximumSize.height)
        if maximumDimension <= 64,
           let iconData = capture.iconData,
           let icon = NSImage(data: iconData) {
            return icon
        }
        guard let image = NSImage(data: capture.imageData) else {
            throw WebcardError.invalidImage
        }
        return image
    }

    private func fittedSize(_ size: CGSize, inside bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else {
            return bounds
        }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(
            width: max(1, (size.width * scale).rounded(.down)),
            height: max(1, (size.height * scale).rounded(.down))
        )
    }
}
