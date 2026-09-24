import AppKit
import SwiftUI
import XCTest
import WebcardCore
@testable import Webcard

final class LayoutDebugTests: XCTestCase {
    @MainActor
    func testRegularWindowUsesCapturedImageMetadataRatio() throws {
        let image = NSImage(size: NSSize(width: 900, height: 672), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.green.setFill()
            rect.fill()
            return true
        }
        let capture = WebcardCapture(
            id: "regular-calibration",
            canonicalURL: URL(string: "https://ebird.org/species/indnig1")!,
            title: "Indian Nightjar - Great Backyard Bird Count",
            summary: "Cryptically-colored nightbird. Note white “moustache” streak, golden-brown collar, and pointed buff-and-black feathers above the wing. Much more intricately marked than Large-tailed Nightjar; also lacks white throat of that species. Not as diffusely patterned as Savanna and Jungle Nightjars, both of which lack Indian’s white “moustache” and clear collar. Male shows bright white patches near the wingtips and on the tail-tips in flight. Found in a range of wooded habitats, from hilly dry forest to garden edges. Listen for its distinctive song, an accelerating knocking akin to a ping-pong ball dropping and bouncing rapidly on the floor.",
            siteName: "ebird.org",
            imageSHA256: "regular-calibration",
            capturedAt: Date(timeIntervalSince1970: 0),
            imageData: try XCTUnwrap(image.tiffRepresentation),
            iconData: try XCTUnwrap(icon.tiffRepresentation)
        )
        let report = try LayoutDebugCapture.report(
            capture: capture,
            viewport: CGSize(width: 668, height: 574),
            usesInsecureHTTP: false,
            truncatesText: true,
            settings: WebcardDebugSettings()
        )

        XCTAssertEqual(report.current.layout.width, 632)
        XCTAssertEqual(report.current.layout.imageHeight, 309)
        XCTAssertEqual(report.current.layout.metadataHeight, 146)
        XCTAssertEqual(report.current.layout.paddedHeight, 574)
        XCTAssertEqual(report.current.visibleTitleLines, 1)
        XCTAssertEqual(report.current.visibleDescriptionLines, 4)
        XCTAssertTrue(report.current.maskImage)
        XCTAssertFalse(report.current.horizontalOverflow)
        XCTAssertFalse(report.current.verticalOverflow)
    }

    @MainActor
    func testAutomaticTitleUsesRemainingSpaceWithoutDescription() throws {
        let source = try fixture()
        let capture = WebcardCapture(
            id: "title-only", canonicalURL: source.canonicalURL,
            title: String(repeating: source.title + " ", count: 20), summary: "",
            siteName: source.siteName, imageSHA256: source.imageSHA256,
            capturedAt: source.capturedAt, imageData: source.imageData
        )
        let short = SelectableMetadataView.attributedString(
            capture: capture, usesInsecureHTTP: false, width: 300, maximumHeight: 140
        )
        let tall = SelectableMetadataView.attributedString(
            capture: capture, usesInsecureHTTP: false, width: 300, maximumHeight: 300
        )
        let shortLines = SelectableMetadataView.displayedLineCount(for: .title, in: short, width: 300)
        let tallLines = SelectableMetadataView.displayedLineCount(for: .title, in: tall, width: 300)
        XCTAssertGreaterThan(shortLines, 2)
        XCTAssertGreaterThan(tallLines, shortLines)
        XCTAssertLessThanOrEqual(
            SelectableMetadataView.height(for: capture, usesInsecureHTTP: false, width: 300, maximumHeight: 300),
            300
        )
    }

    @MainActor
    func testCompactCalibrationAndBeforeAfterCapture() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let before = try ProcessInfo.processInfo.environment["WEBCARD_LAYOUT_REGRESSION_INPUT"].map {
            try decoder.decode(LayoutDebugReport.self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
        }
        let imageSize = before?.originalImageSize ?? CGSize(width: 900, height: 672)
        let image = NSImage(size: imageSize, flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.green.setFill()
            rect.fill()
            return true
        }
        let capture = WebcardCapture(
            id: before?.captureID ?? "compact-calibration",
            canonicalURL: before?.canonicalURL ?? URL(string: "https://ebird.org/species/indnig1")!,
            title: before?.originalTitle ?? "Indian Nightjar - Great Backyard Bird Count",
            summary: before?.originalDescription ?? String(repeating: "Cryptically-colored nightbird. Note white markings and patterned feathers. ", count: 10),
            siteName: before?.siteName ?? "ebird.org",
            imageSHA256: "layout-placeholder",
            capturedAt: before?.captureDate ?? Date(timeIntervalSince1970: 0),
            imageData: try XCTUnwrap(image.tiffRepresentation),
            iconData: try XCTUnwrap(icon.tiffRepresentation)
        )
        var settings = WebcardDebugSettings()
        settings.cardWidth = before.map { Double($0.desired.layout.width) } ?? 266
        settings.imageHeight = before.map { Double($0.desired.layout.imageHeight) } ?? 180
        settings.maskImage = before?.desired.maskImage ?? true
        settings.titleLines = before?.desired.titleLineLimit ?? 1
        settings.descriptionLines = before?.desired.descriptionLineLimit ?? 1
        let after = try LayoutDebugCapture.report(
            capture: capture, viewport: before?.viewport ?? CGSize(width: 900, height: 375),
            usesInsecureHTTP: before?.usesInsecureHTTP ?? false,
            truncatesText: true, settings: settings
        )
        XCTAssertEqual(after.current.layout.width, settings.cardWidth)
        XCTAssertEqual(after.current.layout.imageHeight, settings.imageHeight)
        XCTAssertEqual(after.current.layout.metadataHeight, after.desired.layout.metadataHeight)
        XCTAssertEqual(after.current.maskImage, settings.maskImage)
        XCTAssertEqual(after.current.visibleTitleLines, after.desired.visibleTitleLines)
        XCTAssertEqual(after.current.visibleDescriptionLines, after.desired.visibleDescriptionLines)
        XCTAssertFalse(after.current.verticalOverflow)
        XCTAssertFalse(after.current.horizontalOverflow)
        XCTAssertEqual(after.current.visibleTitle, after.desired.visibleTitle)
        XCTAssertEqual(after.current.visibleDescription, after.desired.visibleDescription)
        XCTAssertTrue(after.current.renderedMetadata.hasSuffix(capture.canonicalURL.absoluteString))
        if let before {
            XCTAssertEqual(after.current.layout.width, before.desired.layout.width)
            XCTAssertEqual(after.current.layout.imageHeight, before.desired.layout.imageHeight)
            XCTAssertEqual(after.current.visibleTitle, before.desired.visibleTitle)
            XCTAssertEqual(after.current.visibleDescription, before.desired.visibleDescription)
            if let path = ProcessInfo.processInfo.environment["WEBCARD_LAYOUT_REGRESSION_OUTPUT"] {
                struct Comparison: Encodable {
                    let measurement: String
                    let source: LayoutDebugReport
                    let viewport: CGSize
                    let beforeVerticalPadding: CGFloat
                    let afterVerticalPadding: CGFloat
                    let before: LayoutDebugReport.Sample
                    let desired: LayoutDebugReport.Sample
                    let after: LayoutDebugReport.Sample
                }
                let comparison = Comparison(
                    measurement: "Replayed from the original text and image dimensions using an 18pt placeholder favicon. No network requests.",
                    source: before,
                    viewport: before.viewport,
                    beforeVerticalPadding: before.current.layout.verticalPadding,
                    afterVerticalPadding: after.current.layout.verticalPadding,
                    before: before.current, desired: before.desired, after: after.current
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(comparison).write(to: URL(fileURLWithPath: path), options: .withoutOverwriting)
            }
        }
    }

    @MainActor
    func testLongDescriptionLiveEditingPerformance() throws {
        let source = try fixture()
        let capture = WebcardCapture(
            id: "long-debug-fixture", canonicalURL: source.canonicalURL,
            title: source.title, summary: String(repeating: source.summary + " ", count: 100),
            siteName: source.siteName, imageSHA256: source.imageSHA256,
            capturedAt: source.capturedAt, imageData: source.imageData
        )
        var settings = WebcardDebugSettings()
        let start = ProcessInfo.processInfo.systemUptime
        for step in 0..<30 {
            settings.cardWidth = 350 + Double(step) * 5
            let layout = WebcardDocumentView.desiredLayout(
                capture: capture, imageSize: CGSize(width: 191, height: 100),
                usesInsecureHTTP: false, settings: settings
            )
            for _ in 0..<3 {
                let text = SelectableMetadataView.attributedString(
                    capture: capture, usesInsecureHTTP: false, width: layout.width - 36,
                    maximumHeight: nil, titleLineLimit: settings.titleLines,
                    descriptionLineLimit: settings.descriptionLines
                )
                XCTAssertTrue(text.string.hasSuffix(capture.canonicalURL.absoluteString))
            }
        }
        let duration = ProcessInfo.processInfo.systemUptime - start
        print("30 long-description preview updates: \(duration) seconds")
        XCTAssertLessThan(duration, 1.5, "Live editing must not repeatedly lay out the entire long description")
    }

    @MainActor
    func testMetadataCacheReusesLayoutWithoutReturningStaleText() throws {
        let capture = try fixture()
        func metadata(_ capture: WebcardCapture, width: CGFloat = 300, lines: Int = 2) -> NSAttributedString {
            SelectableMetadataView.attributedString(
                capture: capture, usesInsecureHTTP: false, width: width, maximumHeight: nil,
                titleLineLimit: 1, descriptionLineLimit: lines
            )
        }
        let first = metadata(capture)
        XCTAssertTrue(first === metadata(capture))
        XCTAssertFalse(first === metadata(capture, width: 350))
        XCTAssertFalse(first === metadata(capture, lines: 3))
        let changedCapture = WebcardCapture(
            id: capture.id, canonicalURL: capture.canonicalURL,
            title: "Changed title", summary: "Changed description",
            siteName: capture.siteName, imageSHA256: capture.imageSHA256,
            capturedAt: capture.capturedAt, imageData: capture.imageData
        )
        let changed = metadata(changedCapture)
        XCTAssertEqual(SelectableMetadataView.displayedText(for: .title, in: changed), "Changed title")
        XCTAssertEqual(SelectableMetadataView.displayedText(for: .description, in: changed), "Changed description")
        XCTAssertFalse(first === changed)
    }

    @MainActor
    func testTitleAndDescriptionLimitsAreIndependent() throws {
        let capture = try fixture()
        for width: CGFloat in [144, 207.5, 340, 464] {
            for (titleLimit, descriptionLimit) in [(0, 3), (1, 0), (1, 2), (2, 5), (100, 100)] {
                let text = SelectableMetadataView.attributedString(
                    capture: capture, usesInsecureHTTP: false, width: width, maximumHeight: nil,
                    titleLineLimit: titleLimit, descriptionLineLimit: descriptionLimit
                )
                for (field, original, limit, font) in [
                    (SelectableMetadataView.Field.title, capture.title, titleLimit, NSFont.systemFont(ofSize: 22, weight: .semibold)),
                    (.description, capture.summary, descriptionLimit, NSFont.systemFont(ofSize: 14))
                ] {
                    let visible = SelectableMetadataView.displayedText(for: field, in: text)
                    let naturalLines = renderedLineCount(original, font: font, width: width)
                    let actualLines = renderedLineCount(visible, font: font, width: width)
                    XCTAssertEqual(actualLines, min(limit, naturalLines), "Exact line budget at width \(width)")
                    XCTAssertEqual(SelectableMetadataView.displayedLineCount(for: field, in: text, width: width), actualLines)
                    if limit == 0 {
                        XCTAssertTrue(visible.isEmpty)
                    } else if naturalLines > limit {
                        XCTAssertTrue(visible.hasSuffix("\u{2026}"))
                    } else {
                        XCTAssertEqual(visible, original)
                    }
                }
                XCTAssertTrue(text.string.hasSuffix(capture.canonicalURL.absoluteString))
            }
        }
    }

    @MainActor
    func testDesiredWidthIsIndependentOfWindowAndAutomaticLayout() throws {
        let capture = try fixture()
        var settings = WebcardDebugSettings()
        settings.titleLines = 1
        settings.descriptionLines = 3
        for width: Double in [240, 500, 900] {
            settings.cardWidth = width
            for viewport in [CGSize(width: 360, height: 420), CGSize(width: 900, height: 800)] {
                let report = try LayoutDebugCapture.report(
                    capture: capture, viewport: viewport, usesInsecureHTTP: false,
                    truncatesText: true, settings: settings
                )
                XCTAssertEqual(report.desired.layout.width, width)
                XCTAssertEqual(report.desired.layout.imageHeight, width * 100 / 191, accuracy: 0.001)
                XCTAssertEqual(report.desired.horizontalOverflow, width + 36 > viewport.width)
                XCTAssertLessThanOrEqual(report.desired.visibleTitleLines, 1)
                XCTAssertEqual(report.desired.visibleDescriptionLines, 3)
            }
        }
        settings.cardWidth = 240
        let narrow = try LayoutDebugCapture.report(
            capture: capture, viewport: CGSize(width: 900, height: 800),
            usesInsecureHTTP: false, truncatesText: true, settings: settings
        )
        settings.cardWidth = 900
        let wide = try LayoutDebugCapture.report(
            capture: capture, viewport: narrow.viewport,
            usesInsecureHTTP: false, truncatesText: true, settings: settings
        )
        XCTAssertGreaterThan(wide.desired.visibleDescription.count, narrow.desired.visibleDescription.count)
    }

    @MainActor
    func testReportSeparatesAutomaticAndDesiredState() throws {
        let capture = try fixture()
        let original = capture
        var settings = WebcardDebugSettings()
        settings.enabled = true
        settings.titleLines = 1
        settings.descriptionLines = 3
        settings.cardWidth = 300
        settings.maskImage = true
        settings.imageHeight = 80
        settings.cropPosition = .bottom
        settings.actualNotes = "Too much title."
        settings.desiredNotes = "A shorter title and more description."
        let report = try LayoutDebugCapture.report(
            capture: capture, viewport: CGSize(width: 700, height: 600),
            usesInsecureHTTP: false, truncatesText: true, settings: settings
        )
        XCTAssertNil(report.current.titleLineLimit)
        XCTAssertTrue(report.current.maskImage)
        XCTAssertEqual(report.desired.titleLineLimit, 1)
        XCTAssertEqual(report.desired.descriptionLineLimit, 3)
        XCTAssertEqual(report.desired.visibleTitleLines, 1)
        XCTAssertEqual(report.desired.visibleDescriptionLines, 3)
        XCTAssertTrue(report.desired.visibleTitle.hasSuffix("\u{2026}"))
        XCTAssertTrue(report.desired.visibleDescription.hasSuffix("\u{2026}"))
        XCTAssertEqual(report.desired.layout.width, 300)
        XCTAssertEqual(report.desired.layout.imageHeight, 80)
        XCTAssertTrue(report.desired.maskImage)
        XCTAssertEqual(report.desired.cropPosition, .bottom)
        XCTAssertEqual(report.current.notes, settings.actualNotes)
        XCTAssertEqual(report.desired.notes, settings.desiredNotes)
        XCTAssertEqual(capture, original)
        settings.enabled = false
        let notPreviewed = try LayoutDebugCapture.report(
            capture: capture, viewport: report.viewport, usesInsecureHTTP: false,
            truncatesText: true, settings: settings
        )
        XCTAssertEqual(notPreviewed.desired.renderedMetadata, report.desired.renderedMetadata)
    }

    @MainActor
    func testCaptureJSONContainsCurrentAndDesiredSettings() throws {
        let capture = try fixture()
        var settings = WebcardDebugSettings()
        settings.titleLines = 1
        settings.descriptionLines = 3
        settings.cardWidth = 500
        settings.maskImage = true
        settings.imageHeight = 80
        settings.actualNotes = "Title and description need different limits."
        settings.desiredNotes = "Keep the URL complete; crop the image in the center."
        let data = try LayoutDebugCapture.json(
            capture: capture, viewport: CGSize(width: 600, height: 500),
            usesInsecureHTTP: false, truncatesText: true, settings: settings
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let current = try XCTUnwrap(object["current"] as? [String: Any])
        let desired = try XCTUnwrap(object["desired"] as? [String: Any])
        XCTAssertEqual(desired["titleLineLimit"] as? Int, settings.titleLines)
        XCTAssertEqual(desired["descriptionLineLimit"] as? Int, settings.descriptionLines)
        XCTAssertEqual(current["maskImage"] as? Bool, true)
        XCTAssertEqual(desired["maskImage"] as? Bool, true)
        XCTAssertNil(object["imageData"])
        XCTAssertNil(object["actual"])
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\n"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(LayoutDebugReport.self, from: data)
        XCTAssertEqual(report.schemaVersion, "2.0.0")
        XCTAssertEqual(report.viewport, CGSize(width: 600, height: 500))
        XCTAssertEqual(report.canonicalURL, capture.canonicalURL)
        XCTAssertEqual(report.originalTitle, capture.title)
        XCTAssertEqual(report.originalDescription, capture.summary)
        XCTAssertEqual(report.desired.notes, settings.desiredNotes)
        XCTAssertEqual(report.desired.layout.width, settings.cardWidth)
        XCTAssertEqual(report.desired.titleLineLimit, settings.titleLines)
        XCTAssertEqual(report.desired.descriptionLineLimit, settings.descriptionLines)
        XCTAssertEqual(report.desired.visibleTitleLines, 1)
        XCTAssertEqual(report.desired.visibleDescriptionLines, 3)
        XCTAssertTrue(report.current.renderedMetadata.hasSuffix(capture.canonicalURL.absoluteString))
        XCTAssertTrue(report.desired.renderedMetadata.hasSuffix(capture.canonicalURL.absoluteString))
        if let path = ProcessInfo.processInfo.environment["WEBCARD_DEBUG_CAPTURE_OUTPUT"] {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    @MainActor
    func testImageCropPositionMatchesTheOriginalImage() throws {
        let image = NSImage(size: NSSize(width: 200, height: 300), flipped: true) { _ in
            NSColor.red.setFill()
            NSRect(x: 0, y: 0, width: 200, height: 100).fill()
            NSColor.green.setFill()
            NSRect(x: 0, y: 100, width: 200, height: 100).fill()
            NSColor.blue.setFill()
            NSRect(x: 0, y: 200, width: 200, height: 100).fill()
            return true
        }
        let full = ImageRenderer(content: WebcardDocumentView.cardImage(image, width: 200, height: 300))
        let original = NSBitmapImageRep(cgImage: try XCTUnwrap(full.cgImage))
        for (position, originalY) in [(ImageCropPosition.top, 15), (.center, 150), (.bottom, 285)] {
            let renderer = ImageRenderer(content: WebcardDocumentView.cardImage(
                image, width: 200, height: 30, maskImage: true, cropPosition: position
            ))
            let cropped = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
            let actual = try XCTUnwrap(cropped.colorAt(x: 100, y: 15)?.usingColorSpace(.deviceRGB))
            let expected = try XCTUnwrap(original.colorAt(x: 100, y: originalY)?.usingColorSpace(.deviceRGB))
            XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.01)
            XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.01)
            XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.01)
        }
    }

    @MainActor
    func testInvalidCaptureSettingsFailExplicitly() throws {
        let capture = try fixture()
        XCTAssertThrowsError(try LayoutDebugCapture.report(
            capture: capture, viewport: .zero, usesInsecureHTTP: false,
            truncatesText: true, settings: WebcardDebugSettings()
        ))
        var settings = WebcardDebugSettings()
        settings.imageHeight = .nan
        XCTAssertThrowsError(try LayoutDebugCapture.report(
            capture: capture, viewport: CGSize(width: 700, height: 600),
            usesInsecureHTTP: false, truncatesText: true, settings: settings
        ))
        settings.imageHeight = 80
        settings.cardWidth = .infinity
        XCTAssertThrowsError(try LayoutDebugCapture.report(
            capture: capture, viewport: CGSize(width: 700, height: 600),
            usesInsecureHTTP: false, truncatesText: true, settings: settings
        ))
        settings.cardWidth = 500
        settings.titleLines = -1
        XCTAssertThrowsError(try LayoutDebugCapture.report(
            capture: capture, viewport: CGSize(width: 700, height: 600),
            usesInsecureHTTP: false, truncatesText: true, settings: settings
        ))
    }

    @MainActor
    private func renderedLineCount(_ text: String, font: NSFont, width: CGFloat) -> Int {
        guard !text.isEmpty else { return 0 }
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10000))
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        guard let manager = textView.layoutManager, let container = textView.textContainer else {
            XCTFail("Native text layout must be available")
            return 0
        }
        manager.ensureLayout(for: container)
        var lines = 0
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, _, _, _, _ in
            lines += 1
        }
        return lines
    }

    @MainActor
    private func fixture() throws -> WebcardCapture {
        let image = NSImage(size: NSSize(width: 191, height: 100), flipped: true) { rect in
            NSColor.magenta.setFill()
            rect.fill()
            return true
        }
        return WebcardCapture(
            id: "debug-fixture",
            canonicalURL: URL(string: "https://example.com/layout-debug")!,
            title: "Example \u{1F469}\u{200D}\u{1F4BB} title for comparing independent truncation",
            summary: Array(repeating: "A detailed description that can be shortened independently of the title.", count: 8).joined(separator: " "),
            siteName: "Example",
            imageSHA256: "fixture",
            capturedAt: Date(timeIntervalSince1970: 0),
            imageData: try XCTUnwrap(image.tiffRepresentation)
        )
    }
}
