import AppKit
import SwiftUI
import XCTest
import WebcardCore
@testable import Webcard

final class MetadataWindowTests: XCTestCase {
    func testSnapshotPreservesSelectedVersionWithoutImageData() throws {
        let capture = fixture()
        let snapshot = MetadataSnapshot(capture: capture, usesInsecureHTTP: true)
        XCTAssertEqual(snapshot.captureID, capture.id)
        XCTAssertEqual(snapshot.title, capture.title)
        XCTAssertEqual(snapshot.summary, capture.summary)
        XCTAssertEqual(snapshot.url, capture.canonicalURL)
        XCTAssertEqual(snapshot.capturedAt, capture.capturedAt)
        XCTAssertTrue(snapshot.usesInsecureHTTP)
        XCTAssertTrue(snapshot.textCapture.imageData.isEmpty)
        XCTAssertNil(snapshot.textCapture.iconData)
        XCTAssertTrue(snapshot.plainText.contains(capture.title))
        XCTAssertTrue(snapshot.plainText.contains(capture.summary))
        XCTAssertTrue(snapshot.plainText.contains(capture.canonicalURL.absoluteString))
        let encoded = try JSONEncoder().encode(snapshot)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("imageData"))
        XCTAssertEqual(try JSONDecoder().decode(MetadataSnapshot.self, from: encoded), snapshot)
    }

    @MainActor
    func testMetadataWindowHasFullSelectableReadOnlyText() throws {
        _ = NSApplication.shared
        let capture = fixture()
        let snapshot = MetadataSnapshot(capture: capture, usesInsecureHTTP: false)
        let host = NSHostingView(rootView: MetadataWindow(snapshot: snapshot))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 360),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let textView = try XCTUnwrap(metadataTextView(in: host, containing: capture.title))
        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertTrue(textView.string.contains(capture.summary))
        XCTAssertTrue(textView.string.contains(capture.canonicalURL.absoluteString))
        XCTAssertFalse(textView.string.contains("\u{2026}"))
    }

    @MainActor
    private func metadataTextView(in view: NSView, containing title: String) -> NSTextView? {
        if let textView = view as? NSTextView, textView.string.contains(title) {
            return textView
        }
        for child in view.subviews {
            if let textView = metadataTextView(in: child, containing: title) {
                return textView
            }
        }
        return nil
    }

    private func fixture() -> WebcardCapture {
        WebcardCapture(
            id: "older-version",
            canonicalURL: URL(string: "https://example.com/full-metadata")!,
            title: Array(repeating: "The full title", count: 15).joined(separator: " "),
            summary: Array(repeating: "The complete description remains selectable.", count: 60).joined(separator: " "),
            siteName: "Example",
            imageSHA256: "fixture-image",
            capturedAt: Date(timeIntervalSince1970: 1000),
            imageData: Data([1, 2, 3]),
            iconData: Data([4, 5, 6])
        )
    }
}
