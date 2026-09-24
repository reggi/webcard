import Foundation
import Testing
import ZIPFoundation
@testable import WebcardCore

struct WebcardArchiveTests {
    @Test
    func suggestsFilenameFromCurrentCaptureTitle() {
        let capture = WebcardCapture(
            id: "capture",
            canonicalURL: URL(string: "https://runningonrealfood.com/recipe")!,
            title: "  Healthy Banana/Oatmeal: Cookies\n",
            summary: "Description",
            siteName: "Running on Real Food",
            imageSHA256: "hash",
            capturedAt: Date(timeIntervalSince1970: 0),
            imageData: Data()
        )
        let file = WebcardFile(
            sourceURL: URL(string: "https://runningonrealfood.com/recipe")!,
            captures: [capture]
        )

        #expect(file.suggestedFilename == "healthy-banana-oatmeal-cookies.webcard")
    }

    @Test
    func suggestsFilenameFromHostWhenCardTextIsEmpty() {
        let capture = WebcardCapture(
            id: "capture",
            canonicalURL: URL(string: "https://example.com/article")!,
            title: " ",
            summary: "",
            siteName: "\n",
            imageSHA256: "hash",
            capturedAt: Date(timeIntervalSince1970: 0),
            imageData: Data()
        )
        let file = WebcardFile(captures: [capture])

        #expect(file.suggestedFilename == "example-com.webcard")
        #expect(WebcardFile().suggestedFilename == "webcard.webcard")
    }

    @Test
    func shortensMarketplaceProductTitle() {
        let capture = WebcardCapture(
            id: "capture",
            canonicalURL: URL(string: "https://www.ebay.com/itm/235202569033")!,
            title: "Dell Latitude E6420, 6 GB RAM, 128 GB SSD, core i3, read description and look. | eBay",
            summary: "Generic charger included.",
            siteName: "eBay",
            imageSHA256: "hash",
            capturedAt: Date(timeIntervalSince1970: 0),
            imageData: Data()
        )
        let file = WebcardFile(captures: [capture])

        #expect(file.suggestedFilename == "dell-latitude-e6420.webcard")
    }

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
            imageData: image,
            socialMetadata: WebcardSocialMetadata(
                imageAlt: "A useful image description",
                contentType: "article",
                author: "Example Author",
                imageWidth: 1200,
                imageHeight: 630
            )
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
        #expect(decoded.currentCapture?.socialMetadata == capture.socialMetadata)
    }

    @Test
    func parsesUsefulSocialMetadata() throws {
        let html = """
        <html>
          <head>
            <meta property="og:title" content="Social title">
            <meta property="og:image" content="/card.jpg">
            <meta property="og:image:alt" content="A nightjar perched on a branch">
            <meta property="og:image:type" content="image/jpeg">
            <meta property="og:image:width" content="1200">
            <meta property="og:image:height" content="630">
            <meta property="og:type" content="article">
            <meta property="og:locale" content="en_US">
            <meta property="article:author" content="Example Author">
            <meta property="article:published_time" content="2026-09-23T12:00:00Z">
            <meta property="article:modified_time" content="2026-09-23T13:00:00Z">
            <meta property="article:section" content="Birds">
            <meta name="twitter:card" content="summary_large_image">
          </head>
        </html>
        """

        let metadata = HTMLMetadata.parse(
            html,
            pageURL: URL(string: "https://example.com/article")!
        )

        #expect(metadata.socialMetadata.imageAlt == "A nightjar perched on a branch")
        #expect(metadata.socialMetadata.contentType == "article")
        #expect(metadata.socialMetadata.locale == "en_US")
        #expect(metadata.socialMetadata.author == "Example Author")
        #expect(metadata.socialMetadata.publishedTime == "2026-09-23T12:00:00Z")
        #expect(metadata.socialMetadata.modifiedTime == "2026-09-23T13:00:00Z")
        #expect(metadata.socialMetadata.section == "Birds")
        #expect(metadata.socialMetadata.twitterCard == "summary_large_image")
        #expect(metadata.socialMetadata.imageMIMEType == "image/jpeg")
        #expect(metadata.socialMetadata.imageWidth == 1200)
        #expect(metadata.socialMetadata.imageHeight == 630)
    }

    @Test
    func prefersSketchfabSocialImageOverProxyBackground() throws {
        let imageURL = "https://media.sketchfab.com/models/68227964f50f4dbc821315b2ed639d0e/thumbnails/5d3a9dfb3bee41f2b37fbf0606ade113/89a3a151b0b145f4a9bfe5dd465bc1b1.jpeg"
        let html = """
        <html>
          <head>
            <meta property="twitter:image" content="\(imageURL)">
            <meta property="og:image" content="\(imageURL)">
            <style>
              .thumbnail {
                background-image: url(&quot;/api/image-proxy?url=https%3A%2F%2Fmedia.sketchfab.com%2Fignored.jpeg&quot;);
              }
            </style>
          </head>
        </html>
        """

        let metadata = HTMLMetadata.parse(
            html,
            pageURL: URL(string: "https://sketchfab.com/3d-models/example")!
        )

        #expect(metadata.imageURL == URL(string: imageURL))
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
