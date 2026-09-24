import AppKit
import WebcardCore

struct LayoutDebugReport: Codable {
    struct Sample: Codable {
        let layout: WebcardCardLayout
        let renderedMetadata: String
        let visibleTitle: String
        let visibleDescription: String
        let titleLineLimit: Int?
        let descriptionLineLimit: Int?
        let visibleTitleLines: Int
        let visibleDescriptionLines: Int
        let maskImage: Bool
        let cropPosition: ImageCropPosition
        let horizontalOverflow: Bool
        let verticalOverflow: Bool
        let notes: String
    }

    let schemaVersion: String
    let createdAt: Date
    let appVersion: String
    let operatingSystem: String
    let appearance: String
    let viewport: CGSize
    let originalImageSize: CGSize
    let captureID: String
    let captureDate: Date
    let canonicalURL: URL
    let originalTitle: String
    let originalDescription: String
    let siteName: String
    let usesInsecureHTTP: Bool
    let automaticTruncationEnabled: Bool
    let current: Sample
    let desired: Sample
}

@MainActor
enum LayoutDebugCapture {
    enum CaptureError: LocalizedError {
        case invalidViewport
        case invalidSettings

        var errorDescription: String? {
            switch self {
            case .invalidViewport: "The card needs a visible window before it can be captured."
            case .invalidSettings: "Debug line limits must be between 0 and 100, card width between 180 and 4000 points, and image height between 1 and 10000 points."
            }
        }
    }

    static func report(
        capture: WebcardCapture,
        viewport: CGSize,
        usesInsecureHTTP: Bool,
        truncatesText: Bool,
        settings: WebcardDebugSettings
    ) throws -> LayoutDebugReport {
        guard viewport.width.isFinite, viewport.height.isFinite,
              viewport.width >= 72, viewport.height > 0 else {
            throw CaptureError.invalidViewport
        }
        guard (0...100).contains(settings.titleLines), (0...100).contains(settings.descriptionLines),
              settings.cardWidth.isFinite, (180...4000).contains(settings.cardWidth),
              settings.imageHeight.isFinite, (1...10000).contains(settings.imageHeight) else {
            throw CaptureError.invalidSettings
        }
        guard let image = NSImage(data: capture.imageData), image.size.width > 0, image.size.height > 0 else {
            throw WebcardError.invalidImage
        }
        let automatic = WebcardDocumentView.cardLayout(
            capture: capture, availableSize: viewport, imageSize: image.size,
            usesInsecureHTTP: usesInsecureHTTP, truncatesText: truncatesText
        )
        let desired = WebcardDocumentView.desiredLayout(
            capture: capture, imageSize: image.size,
            usesInsecureHTTP: usesInsecureHTTP, settings: settings
        )
        func sample(_ layout: WebcardCardLayout, desired: Bool) -> LayoutDebugReport.Sample {
            let titleLimit = desired ? settings.titleLines : nil
            let descriptionLimit = desired ? settings.descriptionLines : nil
            let metadata = SelectableMetadataView.attributedString(
                capture: capture, usesInsecureHTTP: usesInsecureHTTP,
                width: layout.width - 36, maximumHeight: layout.maximumMetadataHeight,
                titleLineLimit: titleLimit, descriptionLineLimit: descriptionLimit
            )
            return LayoutDebugReport.Sample(
                layout: layout,
                renderedMetadata: metadata.string,
                visibleTitle: SelectableMetadataView.displayedText(for: .title, in: metadata),
                visibleDescription: SelectableMetadataView.displayedText(for: .description, in: metadata),
                titleLineLimit: titleLimit,
                descriptionLineLimit: descriptionLimit,
                visibleTitleLines: SelectableMetadataView.displayedLineCount(for: .title, in: metadata, width: layout.width - 36),
                visibleDescriptionLines: SelectableMetadataView.displayedLineCount(for: .description, in: metadata, width: layout.width - 36),
                maskImage: desired ? settings.maskImage : layout.masksImage(image.size),
                cropPosition: desired ? settings.cropPosition : .center,
                horizontalOverflow: layout.width + 36 > viewport.width + 0.5,
                verticalOverflow: layout.paddedHeight > viewport.height + 0.5,
                notes: desired ? settings.desiredNotes : settings.actualNotes
            )
        }
        return LayoutDebugReport(
            schemaVersion: "2.0.0",
            createdAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            appearance: NSApplication.shared.effectiveAppearance.name.rawValue,
            viewport: viewport,
            originalImageSize: image.size,
            captureID: capture.id,
            captureDate: capture.capturedAt,
            canonicalURL: capture.canonicalURL,
            originalTitle: capture.title,
            originalDescription: capture.summary,
            siteName: capture.siteName,
            usesInsecureHTTP: usesInsecureHTTP,
            automaticTruncationEnabled: truncatesText,
            current: sample(automatic, desired: false),
            desired: sample(desired, desired: true)
        )
    }

    static func json(
        capture: WebcardCapture,
        viewport: CGSize,
        usesInsecureHTTP: Bool,
        truncatesText: Bool,
        settings: WebcardDebugSettings
    ) throws -> Data {
        let report = try report(
            capture: capture, viewport: viewport, usesInsecureHTTP: usesInsecureHTTP,
            truncatesText: truncatesText, settings: settings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
}
