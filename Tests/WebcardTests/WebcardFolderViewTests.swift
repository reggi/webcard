import XCTest
import WebcardCore
@testable import Webcard

final class WebcardFolderViewTests: XCTestCase {
    func testGridUsesOneCroppedImageHeight() {
        let width: CGFloat = 320
        let wide = CGSize(width: 1200, height: 600)
        let tall = CGSize(width: 600, height: 1200)

        XCTAssertEqual(
            WebcardFolderLayoutMode.grid.imageHeight(width: width, imageSize: wide),
            WebcardFolderLayoutMode.grid.imageHeight(width: width, imageSize: tall)
        )
        XCTAssertTrue(WebcardFolderLayoutMode.grid.masksImage)
        XCTAssertNotEqual(
            WebcardFolderLayoutMode.masonry.imageHeight(width: width, imageSize: wide),
            WebcardFolderLayoutMode.masonry.imageHeight(width: width, imageSize: tall)
        )
        XCTAssertFalse(WebcardFolderLayoutMode.masonry.masksImage)
    }

    @MainActor
    func testGridLimitsDescriptionsToTwoRenderedLines() {
        XCTAssertNil(WebcardFolderLayoutMode.masonry.descriptionLineLimit)
        XCTAssertEqual(WebcardFolderLayoutMode.grid.descriptionLineLimit, 2)

        let capture = WebcardCapture(
            id: "grid",
            canonicalURL: URL(string: "https://example.com/grid")!,
            title: "Grid card",
            summary: String(repeating: "A long folder card description that must be shortened. ", count: 20),
            siteName: "Example",
            imageSHA256: "",
            capturedAt: Date(timeIntervalSince1970: 0),
            imageData: Data()
        )
        let width: CGFloat = 240
        let text = SelectableMetadataView.attributedString(
            capture: capture,
            usesInsecureHTTP: false,
            width: width,
            maximumHeight: nil,
            descriptionLineLimit: WebcardFolderLayoutMode.grid.descriptionLineLimit
        )

        XCTAssertEqual(
            SelectableMetadataView.displayedLineCount(
                for: .description,
                in: text,
                width: width
            ),
            2
        )
        XCTAssertTrue(
            SelectableMetadataView.displayedText(for: .description, in: text).hasSuffix("…")
        )
    }

    func testFuzzySearchMatchesSubsequencesAndMultipleTerms() {
        XCTAssertNotNil(WebcardFuzzySearch.score(
            query: "wbc",
            in: ["Webcard"]
        ))
        XCTAssertNotNil(WebcardFuzzySearch.score(
            query: "swift layout",
            in: ["A SwiftUI card", "Masonry layout"]
        ))
        XCTAssertNil(WebcardFuzzySearch.score(
            query: "swift missing",
            in: ["A SwiftUI card", "Masonry layout"]
        ))
    }

    func testFuzzySearchPrefersExactAndPrefixMatches() throws {
        let exact = try XCTUnwrap(WebcardFuzzySearch.score(query: "webcard", in: ["webcard"]))
        let prefix = try XCTUnwrap(WebcardFuzzySearch.score(query: "web", in: ["webcard"]))
        let subsequence = try XCTUnwrap(WebcardFuzzySearch.score(query: "wcd", in: ["webcard"]))

        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, subsequence)
    }
}
