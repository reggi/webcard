import Foundation
import Testing
import ZIPFoundation
@testable import WebcardCore

struct WebcardArchiveTests {
    @Test
    func roundTripsVersionTwoArchive() throws {
        let date = Date(timeIntervalSince1970: 1_790_196_000)
        let image = Data("image bytes".utf8)
        let capture = WebcardCapture(
            id: WebcardArchive.captureID(for: date),
            canonicalURL: URL(string: "https://example.com/article")!,
            title: "Example",
            summary: "Description",
            siteName: "Example",
            imageSHA256: WebcardArchive.sha256(image),
            capturedAt: date,
            imageData: image
        )
        let source = WebcardFile(
            sourceURL: URL(string: "https://example.com")!,
            captures: [capture],
            currentCaptureID: capture.id
        )

        let encoded = try WebcardArchive.write(source)
        let decoded = try WebcardArchive.read(encoded)

        #expect(decoded.sourceURL == source.sourceURL)
        #expect(decoded.currentCaptureID == source.currentCaptureID)
        #expect(decoded.lastRefreshedAt == capture.capturedAt)
        #expect(decoded.currentCapture?.hasSameContent(as: capture) == true)
        #expect(decoded.currentCapture?.imageData == capture.imageData)
    }

    @Test
    func rejectsChangedImageBytes() throws {
        let date = Date(timeIntervalSince1970: 1_790_196_000)
        let image = Data("image bytes".utf8)
        let capture = WebcardCapture(
            id: WebcardArchive.captureID(for: date),
            canonicalURL: URL(string: "https://example.com")!,
            title: "Example",
            summary: "",
            siteName: "Example",
            imageSHA256: String(repeating: "0", count: 64),
            capturedAt: date,
            imageData: image
        )

        #expect(throws: WebcardError.self) {
            try WebcardArchive.write(
                WebcardFile(sourceURL: URL(string: "https://example.com")!, captures: [capture])
            )
        }
    }

    @Test
    func readsVersionOneArchiveWithFractionalDate() throws {
        let manifest = Data(
            """
            {
              "version": 1,
              "url": "https://example.com/original",
              "canonicalUrl": "https://example.com/article",
              "title": "Saved article",
              "description": "A useful description.",
              "siteName": "Example",
              "image": "card.webp",
              "savedAt": "2026-09-21T06:53:00.000Z"
            }
            """.utf8
        )
        let image = Data("version one image".utf8)
        let archive = try Archive(accessMode: .create)
        try add(manifest, path: "manifest.json", to: archive)
        try add(image, path: "card.webp", to: archive)

        let file = try WebcardArchive.read(try #require(archive.data))

        #expect(file.sourceURL == URL(string: "https://example.com/original"))
        #expect(file.currentCapture?.canonicalURL == URL(string: "https://example.com/article"))
        #expect(file.currentCapture?.title == "Saved article")
        #expect(file.currentCapture?.imageData == image)
    }

    @Test
    func detectsCaptureContentChanges() {
        let image = Data("image".utf8)
        let first = WebcardCapture(
            id: "first",
            canonicalURL: URL(string: "https://example.com")!,
            title: "First",
            summary: "Description",
            siteName: "Example",
            imageSHA256: WebcardArchive.sha256(image),
            capturedAt: .distantPast,
            imageData: image
        )
        let changed = WebcardCapture(
            id: "second",
            canonicalURL: first.canonicalURL,
            title: "Changed",
            summary: first.summary,
            siteName: first.siteName,
            imageSHA256: first.imageSHA256,
            capturedAt: .now,
            imageData: image
        )

        #expect(first.hasSameContent(as: first))
        #expect(!first.hasSameContent(as: changed))
    }

    @Test
    func storesSharedImageOnlyOnceForTextOnlyChanges() throws {
        let image = Data("shared image".utf8)
        let imageSHA256 = WebcardArchive.sha256(image)
        let first = WebcardCapture(
            id: "first",
            canonicalURL: URL(string: "https://example.com")!,
            title: "First title",
            summary: "First description",
            siteName: "Example",
            imageSHA256: imageSHA256,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            imageData: image
        )
        let second = WebcardCapture(
            id: "second",
            canonicalURL: first.canonicalURL,
            title: "Updated title",
            summary: "Updated description",
            siteName: first.siteName,
            imageSHA256: imageSHA256,
            capturedAt: Date(timeIntervalSince1970: 2_000),
            imageData: image
        )

        let data = try WebcardArchive.write(
            WebcardFile(
                sourceURL: URL(string: "https://example.com")!,
                captures: [first, second],
                currentCaptureID: second.id
            )
        )
        let archive = try Archive(data: data, accessMode: .read)
        let imageEntries = archive.map(\.path).filter { $0.hasPrefix("images/") }

        #expect(imageEntries == ["images/\(imageSHA256).webp"])
        #expect(!archive.map(\.path).contains("captures/first/card.webp"))
        #expect(!archive.map(\.path).contains("captures/second/card.webp"))
        #expect(try WebcardArchive.read(data).captures.count == 2)
    }

    @Test
    func roundTripsAndDeduplicatesSiteIcons() throws {
        let image = Data("card image".utf8)
        let icon = Data("site icon".utf8)
        let iconSHA256 = WebcardArchive.sha256(icon)
        let capture = WebcardCapture(
            id: "capture",
            canonicalURL: URL(string: "https://example.com")!,
            title: "Example",
            summary: "",
            siteName: "Example",
            imageSHA256: WebcardArchive.sha256(image),
            capturedAt: Date(timeIntervalSince1970: 1_000),
            imageData: image,
            iconSHA256: iconSHA256,
            iconData: icon
        )

        let data = try WebcardArchive.write(
            WebcardFile(sourceURL: capture.canonicalURL, captures: [capture])
        )
        let archive = try Archive(data: data, accessMode: .read)
        let decoded = try WebcardArchive.read(data)

        #expect(archive.map(\.path).contains("images/\(iconSHA256).webp"))
        #expect(decoded.currentCapture?.iconData == icon)
        #expect(decoded.currentCapture?.iconSHA256 == iconSHA256)
    }

    @Test
    func normalizesSchemeOptionalAddresses() {
        let plain = WebcardAddress.requestPlan(from: "example.com/path")
        #expect(plain?.preferredURL == URL(string: "https://example.com/path"))
        #expect(plain?.fallbackURL == URL(string: "http://example.com/path"))

        let http = WebcardAddress.requestPlan(from: "http://example.com")
        #expect(http?.preferredURL == URL(string: "https://example.com"))
        #expect(http?.fallbackURL == URL(string: "http://example.com"))

        let https = WebcardAddress.requestPlan(from: "https://example.com")
        #expect(https?.preferredURL == URL(string: "https://example.com"))
        #expect(https?.fallbackURL == nil)

        #expect(WebcardAddress.requestPlan(from: "ftp://example.com") == nil)
        #expect(WebcardAddress.requestPlan(from: "file:///tmp/example") == nil)
    }

    @Test
    func updatesLastRefreshWithoutAddingCapture() {
        let image = Data("image".utf8)
        let capture = WebcardCapture(
            id: "capture",
            canonicalURL: URL(string: "https://example.com")!,
            title: "Example",
            summary: "",
            siteName: "Example",
            imageSHA256: WebcardArchive.sha256(image),
            capturedAt: Date(timeIntervalSince1970: 1_000),
            imageData: image
        )
        var file = WebcardFile(
            sourceURL: URL(string: "https://example.com")!,
            captures: [capture]
        )
        let refreshedAt = Date(timeIntervalSince1970: 2_000)

        file.lastRefreshedAt = refreshedAt

        #expect(file.captures.count == 1)
        #expect(file.lastRefreshedAt == refreshedAt)
        #expect(file.currentCapture?.capturedAt == capture.capturedAt)
    }

    private func add(_ data: Data, path: String, to archive: Archive) throws {
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: .deflate
        ) { position, size in
            let lower = Int(position)
            return data.subdata(in: lower..<min(lower + size, data.count))
        }
    }
}
