import AppKit
import SwiftUI
import XCTest
import WebcardCore
@testable import Webcard

final class SelectableMetadataViewTests: XCTestCase {
    @MainActor
    func testEntireImageFillsCardWidthWithoutCropping() throws {
        for sourceSize in [CGSize(width: 20, height: 100), CGSize(width: 100, height: 20)] {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(sourceSize.width), pixelsHigh: Int(sourceSize.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let color: NSColor
                    if y < 2 {
                        color = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
                    } else if y >= bitmap.pixelsHigh - 2 {
                        color = NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1)
                    } else {
                        color = NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
                    }
                    bitmap.setColor(color, atX: x, y: y)
                }
            }
            let image = NSImage(size: sourceSize)
            image.addRepresentation(bitmap)
            for width: CGFloat in [100, 200, 300] {
                let height = width * sourceSize.height / sourceSize.width
                let renderer = ImageRenderer(content: WebcardDocumentView.cardImage(image, width: width, height: height))
                let rendered = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                XCTAssertEqual(rendered.pixelsWide, Int(width))
                XCTAssertEqual(rendered.pixelsHigh, Int(height))
                for x in 0..<rendered.pixelsWide {
                    let color = try XCTUnwrap(rendered.colorAt(x: x, y: rendered.pixelsHigh / 2))
                    XCTAssertGreaterThan(color.alphaComponent, 0.99, "Image must fill column \(x)")
                    XCTAssertGreaterThan(color.blueComponent, 0.9)
                }
                for y in [0, rendered.pixelsHigh - 1] {
                    let edge = try XCTUnwrap(rendered.colorAt(x: rendered.pixelsWide / 2, y: y))
                    XCTAssertLessThan(edge.blueComponent, 0.1, "Original image edges must remain visible")
                    XCTAssertGreaterThan(edge.redComponent + edge.greenComponent, 0.9)
                }
            }
        }
    }

    @MainActor
    func testResizingDoesNotJumpWhenTextWraps() {
        let longCapture = capture()
        let shortCapture = WebcardCapture(
            id: "short", canonicalURL: URL(string: "https://example.com")!,
            title: "Short", summary: "Short summary", siteName: "Example", imageSHA256: "",
            capturedAt: Date(timeIntervalSince1970: 0), imageData: Data()
        )
        var previousImageHeight: CGFloat?
        for step in 0...600 {
            let size = CGSize(width: 360 + CGFloat(step) * 0.75, height: 340 + CGFloat(step) * 0.5)
            let long = WebcardDocumentView.cardLayout(
                capture: longCapture, availableSize: size, imageSize: CGSize(width: 191, height: 100),
                usesInsecureHTTP: false, truncatesText: true
            )
            let short = WebcardDocumentView.cardLayout(
                capture: shortCapture, availableSize: size, imageSize: CGSize(width: 191, height: 100),
                usesInsecureHTTP: false, truncatesText: true
            )
            XCTAssertEqual(long.imageHeight, short.imageHeight)
            XCTAssertEqual(long.metadataHeight, short.metadataHeight)
            XCTAssertEqual(long.paddedHeight, size.height, accuracy: 0.001)
            if let previousImageHeight {
                XCTAssertLessThanOrEqual(abs(long.imageHeight - previousImageHeight), 0.5 + 0.000001)
            }
            previousImageHeight = long.imageHeight
        }
    }

    @MainActor
    func testCardReservesSpaceForBrowserButtonWithLongText() {
        for width: CGFloat in [360, 700] {
            for height: CGFloat in [340, 400, 600, 800] {
                let layout = WebcardDocumentView.cardLayout(
                    capture: capture(),
                    availableSize: CGSize(width: width, height: height),
                    imageSize: CGSize(width: 191, height: 100),
                    usesInsecureHTTP: true,
                    truncatesText: true
                )
                XCTAssertLessThanOrEqual(layout.paddedHeight, height)
                XCTAssertGreaterThan(layout.imageHeight, 0)
                XCTAssertGreaterThan(layout.metadataHeight, 0)
                XCTAssertLessThanOrEqual(layout.imageHeight, layout.width / 1.91 + 0.001)
                XCTAssertEqual(
                    layout.paddedHeight - layout.imageHeight - layout.metadataHeight,
                    32 + 18 * 3 + layout.verticalPadding * 2,
                    accuracy: 0.001,
                    "Reserve the browser button, content spacing, and outer padding"
                )
            }
        }
    }

    @MainActor
    func testImageShrinksAndUntruncatedTextCanScroll() {
        let short = WebcardDocumentView.cardLayout(
            capture: capture(), availableSize: CGSize(width: 700, height: 340),
            imageSize: CGSize(width: 191, height: 100),
            usesInsecureHTTP: false, truncatesText: true
        )
        let tall = WebcardDocumentView.cardLayout(
            capture: capture(), availableSize: CGSize(width: 700, height: 800),
            imageSize: CGSize(width: 191, height: 100),
            usesInsecureHTTP: false, truncatesText: true
        )
        let untruncated = WebcardDocumentView.cardLayout(
            capture: capture(), availableSize: CGSize(width: 700, height: 340),
            imageSize: CGSize(width: 191, height: 100),
            usesInsecureHTTP: false, truncatesText: false
        )
        XCTAssertLessThan(short.imageHeight, tall.imageHeight)
        XCTAssertLessThan(short.metadataHeight, tall.metadataHeight)
        XCTAssertNil(untruncated.maximumMetadataHeight)
        XCTAssertGreaterThan(untruncated.paddedHeight, 340)
    }

    @MainActor
    func testLongMetadataFitsAvailableHeight() {
        let capture = capture()
        for width: CGFloat in [288, 388, 628] {
            for height: CGFloat in [0, 20, 60, 100, 180, 300] {
                for insecure in [false, true] {
                    let measured = SelectableMetadataView.height(
                        for: capture,
                        usesInsecureHTTP: insecure,
                        width: width,
                        maximumHeight: height
                    )
                    XCTAssertLessThanOrEqual(
                        measured,
                        max(height, SelectableMetadataView.minimumHeight(
                            for: capture, usesInsecureHTTP: insecure, width: width
                        ))
                    )
                    let text = SelectableMetadataView.attributedString(
                        capture: capture, usesInsecureHTTP: insecure, width: width, maximumHeight: height
                    )
                    XCTAssertTrue(text.string.hasSuffix(capture.canonicalURL.absoluteString))
                    XCTAssertTrue(text.string.contains("A lo"))
                    XCTAssertTrue(text.string.contains("Lots"))
                }
            }
        }
    }

    @MainActor
    func testLongURLWrapsWithoutTruncation() {
        let url = URL(string: "https://example.com/" + String(repeating: "long-path/", count: 30))!
        let capture = capture(canonicalURL: url)
        let width: CGFloat = 240
        let urlHeight = SelectableMetadataView.urlHeight(for: capture, width: width)
        XCTAssertGreaterThan(urlHeight, 30)
        for height in [urlHeight, urlHeight + 50, urlHeight + 200] {
            let text = SelectableMetadataView.attributedString(
                capture: capture, usesInsecureHTTP: false, width: width, maximumHeight: height
            )
            XCTAssertTrue(text.string.hasSuffix(url.absoluteString))
            XCTAssertLessThanOrEqual(
                SelectableMetadataView.height(
                    for: capture, usesInsecureHTTP: false, width: width, maximumHeight: height
                ),
                max(height, SelectableMetadataView.minimumHeight(
                    for: capture, usesInsecureHTTP: false, width: width
                ))
            )
        }
    }

    @MainActor
    func testFaviconCardKeepsTitleAndDescriptionWhileResizing() throws {
        let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        let image = NSImage(size: NSSize(width: 191, height: 100), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        let capture = WebcardCapture(
            id: "favicon",
            canonicalURL: URL(string: "https://example.com/species/nightjar")!,
            title: "Indian Nightjar - Great Backyard Bird Count",
            summary: String(repeating: "Cryptically-colored nightbird with patterned feathers. ", count: 20),
            siteName: "Example",
            imageSHA256: "",
            capturedAt: Date(timeIntervalSince1970: 0),
            imageData: try XCTUnwrap(image.tiffRepresentation),
            iconData: try XCTUnwrap(icon.tiffRepresentation)
        )
        let document = WebcardDocument(file: WebcardFile(captures: [capture]))
        let host = NSHostingView(rootView: WebcardDocumentView(document: .constant(document)))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 340),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        var lengths: [Int] = []
        for height: CGFloat in [340, 440, 600, 800] {
            let layout = WebcardDocumentView.cardLayout(
                capture: capture, availableSize: CGSize(width: 700, height: height),
                imageSize: CGSize(width: 191, height: 100), usesInsecureHTTP: false, truncatesText: true
            )
            let text = SelectableMetadataView.attributedString(
                capture: capture, usesInsecureHTTP: false,
                width: layout.width - 36, maximumHeight: layout.maximumMetadataHeight
            ).string
            XCTAssertTrue(text.contains("Indi"), "Title must keep an excerpt at height \(height)")
            XCTAssertTrue(text.contains("Cryp"), "Description must keep an excerpt at height \(height)")
            if !text.contains(capture.summary.trimmingCharacters(in: .whitespacesAndNewlines)) {
                XCTAssertTrue(text.contains("\u{2026}"), "Shortened text must have an ellipsis")
            }
            XCTAssertTrue(text.hasSuffix(capture.canonicalURL.absoluteString))
            lengths.append(text.count)

            window.setContentSize(NSSize(width: 700, height: height))
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            let textView = try XCTUnwrap(metadataTextView(in: host))
            XCTAssertFalse(textView.isHiddenOrHasHiddenAncestor)
            XCTAssertGreaterThan(textView.bounds.height, 0)
            XCTAssertTrue(textView.string.contains("Indi"))
            XCTAssertTrue(textView.string.contains("Cryp"))
            XCTAssertTrue(textView.string.hasSuffix(capture.canonicalURL.absoluteString))
            let container = try XCTUnwrap(textView.textContainer)
            let manager = try XCTUnwrap(textView.layoutManager)
            manager.ensureLayout(for: container)
            XCTAssertLessThanOrEqual(manager.usedRect(for: container).maxY, textView.bounds.height + 1)
        }
        XCTAssertGreaterThan(lengths[1], lengths[0])
        XCTAssertGreaterThan(lengths[2], lengths[1])
        XCTAssertGreaterThan(lengths[3], lengths[2])
        let untruncated = SelectableMetadataView.attributedString(
            capture: capture, usesInsecureHTTP: false, width: 300, maximumHeight: nil
        ).string
        XCTAssertTrue(untruncated.contains(capture.title))
        XCTAssertTrue(untruncated.contains(capture.summary.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    @MainActor
    private func metadataTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }
        for child in view.subviews {
            if let textView = metadataTextView(in: child) {
                return textView
            }
        }
        return nil
    }

    @MainActor
    func testDisablingTruncationRestoresFullTextHeight() {
        let capture = capture()
        let fullHeight = SelectableMetadataView.height(
            for: capture,
            usesInsecureHTTP: false,
            width: 288
        )
        let shortHeight = SelectableMetadataView.height(
            for: capture,
            usesInsecureHTTP: false,
            width: 288,
            maximumHeight: 100
        )
        let tallHeight = SelectableMetadataView.height(
            for: capture,
            usesInsecureHTTP: false,
            width: 288,
            maximumHeight: 300
        )
        XCTAssertGreaterThan(fullHeight, 1000)
        XCTAssertGreaterThan(tallHeight, shortHeight)
        XCTAssertGreaterThan(fullHeight, tallHeight)
        XCTAssertEqual(
            SelectableMetadataView.height(
                for: capture,
                usesInsecureHTTP: false,
                width: 288,
                maximumHeight: fullHeight
            ),
            fullHeight
        )
    }

    private func capture(canonicalURL: URL = URL(string: "https://example.com")!) -> WebcardCapture {
        WebcardCapture(
            id: "layout",
            canonicalURL: canonicalURL,
            title: String(repeating: "A long title with e\u{301} and \u{1F469}\u{200D}\u{1F4BB} ", count: 20),
            summary: String(repeating: "Lots of text that must not push the browser button out of view. ", count: 100),
            siteName: "Example",
            imageSHA256: "",
            capturedAt: Date(timeIntervalSince1970: 0),
            imageData: Data()
        )
    }
}
