import XCTest
import UniformTypeIdentifiers
import WebcardCore
@testable import Webcard

final class WebcardFolderViewTests: XCTestCase {
    @MainActor
    func testDroppedWeblocPreservesItsFileURL() async {
        let expectedURL = URL(
            fileURLWithPath: "/tmp/Western Honey Bee.webloc",
            isDirectory: false
        )
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier,
            visibility: .all
        ) { completion in
            completion(expectedURL.dataRepresentation, nil)
            return nil
        }

        let urls = await withCheckedContinuation { continuation in
            WebcardDroppedFileLoader.load([provider]) {
                continuation.resume(returning: $0)
            }
        }

        XCTAssertEqual(urls, [expectedURL])
    }

    private let fileManager = FileManager.default

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

    func testGridEqualizesMetadataHeightWithinEachRow() {
        XCTAssertEqual(
            WebcardGridRowMetrics.equalizedHeights(
                [100, 140, 120, 90, 110],
                columns: 3
            ),
            [140, 140, 140, 110, 110]
        )
    }

    func testGridOptimizesSmallFoldersAndUsesFullCountForLargeFolders() {
        let cases: [(items: Int, maximumColumns: Int, expectedColumns: Int)] = [
            (1, 2, 2),
            (5, 4, 3),
            (6, 4, 3),
            (7, 4, 4),
            (8, 4, 4),
            (9, 4, 4),
            (10, 4, 4),
            (5, 3, 3),
            (6, 3, 3)
        ]

        for testCase in cases {
            XCTAssertEqual(
                WebcardGridRowMetrics.optimizedColumnCount(
                    maximumColumns: testCase.maximumColumns,
                    itemCount: testCase.items
                ),
                testCase.expectedColumns,
                "\(testCase.items) items with at most \(testCase.maximumColumns) columns"
            )
        }
    }

    func testLargeFoldersUseFullResponsiveColumnCount() {
        XCTAssertEqual(
            WebcardGridRowMetrics.optimizedColumnCount(
                maximumColumns: 4,
                itemCount: 8
            ),
            4
        )
        XCTAssertEqual(
            WebcardGridRowMetrics.optimizedColumnCount(
                maximumColumns: 4,
                itemCount: 9
            ),
            4
        )
    }

    @MainActor
    func testGridLimitsTitlesToThreeRenderedLines() {
        XCTAssertNil(WebcardFolderLayoutMode.masonry.titleLineLimit)
        XCTAssertEqual(WebcardFolderLayoutMode.grid.titleLineLimit, 3)

        let capture = WebcardCapture(
            id: "long-title",
            canonicalURL: URL(string: "https://example.com/long-title")!,
            title: String(repeating: "A very long webcard title that must be shortened. ", count: 10),
            summary: "Summary",
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
            titleLineLimit: WebcardFolderLayoutMode.grid.titleLineLimit
        )

        XCTAssertEqual(
            SelectableMetadataView.displayedLineCount(for: .title, in: text, width: width),
            3
        )
        XCTAssertTrue(
            SelectableMetadataView.displayedText(for: .title, in: text).hasSuffix("…")
        )
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

    @MainActor
    func testGridLimitsLongURLsToOneRenderedLine() {
        XCTAssertNil(WebcardFolderLayoutMode.masonry.urlLineLimit)
        XCTAssertEqual(WebcardFolderLayoutMode.grid.urlLineLimit, 1)

        let capture = WebcardCapture(
            id: "long-url",
            canonicalURL: URL(
                string: "https://example.com/" + String(repeating: "very-long-path/", count: 30)
            )!,
            title: "Grid card",
            summary: "Summary",
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
            urlLineLimit: WebcardFolderLayoutMode.grid.urlLineLimit
        )

        XCTAssertEqual(
            SelectableMetadataView.displayedLineCount(for: .url, in: text, width: width),
            1
        )
        XCTAssertTrue(
            SelectableMetadataView.displayedText(for: .url, in: text).hasSuffix("…")
        )
    }

    func testSearchMatchesSubsequencesAndMultipleTerms() {
        XCTAssertNotNil(WebcardSearch.score(
            query: "wbc",
            in: ["Webcard"]
        ))
        XCTAssertNotNil(WebcardSearch.score(
            query: "swift layout",
            in: ["A SwiftUI card", "Masonry layout"]
        ))
        XCTAssertNil(WebcardSearch.score(
            query: "swift missing",
            in: ["A SwiftUI card", "Masonry layout"]
        ))
    }

    func testSearchPrefersExactAndPrefixMatches() throws {
        let exact = try XCTUnwrap(WebcardSearch.score(query: "webcard", in: ["webcard"]))
        let prefix = try XCTUnwrap(WebcardSearch.score(query: "web", in: ["webcard"]))
        let subsequence = try XCTUnwrap(WebcardSearch.score(query: "wcd", in: ["webcard"]))

        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, subsequence)
    }

    func testSearchHandlesTyposDiacriticsPunctuationAndQuotedPhrases() {
        XCTAssertNotNil(WebcardSearch.score(
            query: "javscript",
            in: ["JavaScript performance guide"]
        ))
        XCTAssertNotNil(WebcardSearch.score(
            query: "cafe",
            in: ["Café reviews"]
        ))
        XCTAssertNotNil(WebcardSearch.score(
            query: "example com",
            in: ["https://example.com/reference"]
        ))
        XCTAssertNotNil(WebcardSearch.score(
            query: "\"swift layout\"",
            in: ["A practical Swift layout guide"]
        ))
        XCTAssertNil(WebcardSearch.score(
            query: "\"layout swift\"",
            in: ["A practical Swift layout guide"]
        ))
    }

    func testSearchRejectsBroadShortFuzzyMatches() {
        XCTAssertNil(WebcardSearch.score(query: "ab", in: ["A broad unrelated card"]))
    }

    func testSearchRanksStrongFieldsAndNestedFoldersByRelevance() throws {
        let root = URL(fileURLWithPath: "/tmp/Webcards", isDirectory: true)
        let lowMatch = makeSearchItem(
            filename: "alpha",
            title: "General reference",
            summary: "A summary about Swift",
            directory: root
        )
        let highMatch = makeSearchItem(
            filename: "zulu",
            title: "Swift",
            summary: "Language reference",
            directory: root
        )
        let lowChild = WebcardDirectoryNode(
            directoryURL: root.appendingPathComponent("Alpha", isDirectory: true),
            directWebcards: [lowMatch],
            children: [],
            discoveryState: .complete
        )
        let highChild = WebcardDirectoryNode(
            directoryURL: root.appendingPathComponent("Zulu", isDirectory: true),
            directWebcards: [highMatch],
            children: [],
            discoveryState: .complete
        )
        let hierarchy = WebcardDirectoryNode(
            directoryURL: root,
            directWebcards: [lowMatch, highMatch],
            children: [lowChild, highChild],
            discoveryState: .complete
        )

        let filtered = try XCTUnwrap(hierarchy.filtering(query: "swift"))

        XCTAssertEqual(filtered.directWebcards.map(\.fileURL.lastPathComponent), [
            "zulu.webcard",
            "alpha.webcard"
        ])
        XCTAssertEqual(filtered.children.map(\.directoryURL.lastPathComponent), [
            "Zulu",
            "Alpha"
        ])
    }

    func testVisualHierarchyUsesContinuationItemsAfterTwoInlineLevels() {
        XCTAssertFalse(WebcardVisualHierarchy.usesContinuationItems(at: 1))
        XCTAssertTrue(WebcardVisualHierarchy.usesContinuationItems(at: 2))
        XCTAssertTrue(WebcardVisualHierarchy.usesContinuationItems(at: 200))
    }

    func testColumnMetricsRespondToEveryRequestedColumnCount() {
        let one = WebcardGalleryMetrics(
            availableWidth: 1_200,
            requestedColumns: 1,
            spacing: 20
        )
        let three = WebcardGalleryMetrics(
            availableWidth: 1_200,
            requestedColumns: 3,
            spacing: 20
        )
        let six = WebcardGalleryMetrics(
            availableWidth: 1_200,
            requestedColumns: 6,
            spacing: 20
        )

        XCTAssertEqual(one.columns, 1)
        XCTAssertEqual(three.columns, 3)
        XCTAssertEqual(six.columns, 6)
        XCTAssertGreaterThan(one.cardWidth, three.cardWidth)
        XCTAssertGreaterThan(three.cardWidth, six.cardWidth)
        XCTAssertLessThanOrEqual(six.contentWidth, 1_200)
    }

    func testDynamicFolderColumnsRespondToAvailableWidthAndCapAtFour() {
        let spacing: CGFloat = 20

        XCTAssertEqual(
            WebcardFolderColumnMode.dynamic.columnCount(
                availableWidth: 500,
                spacing: spacing
            ),
            1
        )
        XCTAssertEqual(
            WebcardFolderColumnMode.dynamic.columnCount(
                availableWidth: 700,
                spacing: spacing
            ),
            2
        )
        XCTAssertEqual(
            WebcardFolderColumnMode.dynamic.columnCount(
                availableWidth: 900,
                spacing: spacing
            ),
            3
        )
        XCTAssertEqual(
            WebcardFolderColumnMode.dynamic.columnCount(
                availableWidth: 1_200,
                spacing: spacing
            ),
            4
        )
        XCTAssertEqual(
            WebcardFolderColumnMode.dynamic.columnCount(
                availableWidth: 10_000,
                spacing: spacing
            ),
            4
        )
    }

    func testDynamicFolderColumnsDoNotExceedVisibleItemCount() {
        let spacing: CGFloat = 20
        let availableWidth: CGFloat = 1_200

        XCTAssertEqual(
            WebcardFolderColumnMode.dynamic.columnCount(
                availableWidth: availableWidth,
                spacing: spacing,
                itemCount: 4
            ),
            4
        )
        XCTAssertEqual(
            WebcardFolderColumnMode.dynamic.columnCount(
                availableWidth: availableWidth,
                spacing: spacing,
                itemCount: 3
            ),
            3
        )
        XCTAssertEqual(
            WebcardFolderColumnMode.dynamic.columnCount(
                availableWidth: availableWidth,
                spacing: spacing,
                itemCount: 2
            ),
            2
        )
        XCTAssertEqual(
            WebcardFolderColumnMode.dynamic.columnCount(
                availableWidth: availableWidth,
                spacing: spacing,
                itemCount: 1
            ),
            2
        )
        XCTAssertEqual(
            WebcardFolderColumnMode.dynamic.columnCount(
                availableWidth: 900,
                spacing: spacing,
                itemCount: 2
            ),
            2
        )
    }

    func testManualFolderColumnsIgnoreVisibleItemCount() {
        XCTAssertEqual(
            WebcardFolderColumnMode.four.columnCount(
                availableWidth: 1_200,
                spacing: 20,
                itemCount: 1
            ),
            4
        )
    }

    func testManualFolderColumnModesUseTheirExactCounts() {
        let modes: [(WebcardFolderColumnMode, Int)] = [
            (.one, 1),
            (.two, 2),
            (.three, 3),
            (.four, 4)
        ]

        for (mode, expectedCount) in modes {
            XCTAssertEqual(
                mode.columnCount(availableWidth: 1, spacing: 20),
                expectedCount
            )
        }
    }

    @MainActor
    func testFolderCommandCenterTracksActiveWindow() {
        let commandCenter = WebcardFolderCommandCenter.shared
        let firstID = UUID()
        let secondID = UUID()
        defer {
            commandCenter.deactivate(id: firstID)
            commandCenter.deactivate(id: secondID)
        }

        commandCenter.activate(id: firstID)
        XCTAssertTrue(commandCenter.hasActiveFolder)

        commandCenter.activate(id: secondID)
        commandCenter.deactivate(id: firstID)
        XCTAssertTrue(commandCenter.hasActiveFolder)

        commandCenter.deactivate(id: secondID)
        XCTAssertFalse(commandCenter.hasActiveFolder)
    }

    func testFolderNavigationBuildsPathFromRootForSiblingSelection() throws {
        let root = URL(fileURLWithPath: "/tmp/Webcards", isDirectory: true)
        let selected = root
            .appendingPathComponent("Research", isDirectory: true)
            .appendingPathComponent("Birds", isDirectory: true)

        let path = try XCTUnwrap(
            WebcardFolderBrowserModel.navigationPath(from: root, to: selected)
        )

        XCTAssertEqual(path, [
            root,
            root.appendingPathComponent("Research", isDirectory: true),
            selected
        ])
        XCTAssertNil(
            WebcardFolderBrowserModel.navigationPath(
                from: root,
                to: URL(fileURLWithPath: "/tmp/Other", isDirectory: true)
            )
        )
    }

    func testFolderWriterUsesNextAvailableFilenameWithoutChangingSortRules() throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("Example.webcard"))
        try Data().write(to: root.appendingPathComponent("Example 2.webcard"))

        let destination = try WebcardFolderFileWriter.availableDestinationURL(
            suggestedFilename: "Example.webcard",
            in: root
        )

        XCTAssertEqual(destination.lastPathComponent, "Example 3.webcard")
        XCTAssertEqual(
            ["Zulu.webcard", destination.lastPathComponent, "Alpha.webcard"].sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            },
            ["Alpha.webcard", "Example 3.webcard", "Zulu.webcard"]
        )
    }

    func testFolderWriterTreatsFilenameCollisionsCaseInsensitively() throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("example.webcard"))

        let destination = try WebcardFolderFileWriter.availableDestinationURL(
            suggestedFilename: "Example.webcard",
            in: root
        )

        XCTAssertEqual(destination.lastPathComponent, "Example 2.webcard")
    }

    func testFolderWriterKeepsBothBulkItemsWhenTitlesGenerateTheSameFilename() throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let imageData = Data("shared image".utf8)

        func file(path: String, captureID: String) -> WebcardFile {
            let sourceURL = URL(string: "https://example.com/\(path)")!
            let capture = WebcardCapture(
                id: captureID,
                canonicalURL: sourceURL,
                title: "Shared Title",
                summary: path,
                siteName: "Example",
                imageSHA256: WebcardArchive.sha256(imageData),
                capturedAt: Date(timeIntervalSince1970: 0),
                imageData: imageData
            )
            return WebcardFile(
                sourceURL: sourceURL,
                captures: [capture],
                currentCaptureID: capture.id
            )
        }

        let first = try WebcardFolderFileWriter.write(
            file(path: "first", captureID: "first"),
            to: root
        )
        let second = try WebcardFolderFileWriter.write(
            file(path: "second", captureID: "second"),
            to: root
        )

        XCTAssertEqual(first.lastPathComponent, "shared-title.webcard")
        XCTAssertEqual(second.lastPathComponent, "shared-title 2.webcard")
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(fileManager.fileExists(atPath: first.path))
        XCTAssertTrue(fileManager.fileExists(atPath: second.path))
    }

    func testFolderWriterCreatesStandardWeblocFallbacksWithoutOverwriting() throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let url = try XCTUnwrap(
            URL(string: "https://www.inaturalist.org/taxa/47219-Apis-mellifera")
        )

        let first = try WebcardFolderFileWriter.writeWebloc(for: url, to: root)
        let second = try WebcardFolderFileWriter.writeWebloc(for: url, to: root)

        let expectedFilename = WebcardWebloc.suggestedFilename(for: url)
        XCTAssertEqual(first.lastPathComponent, expectedFilename)
        XCTAssertEqual(
            second.lastPathComponent,
            expectedFilename.replacingOccurrences(of: ".webloc", with: " 2.webloc")
        )
        XCTAssertEqual(
            try WebcardWebloc.read(Data(contentsOf: first)),
            url
        )
    }

    func testDiscoveryRendersWebLocationsAlongsideWebcards() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        try writeWebcard(named: "captured", to: root)
        let failedURL = try XCTUnwrap(
            URL(string: "https://www.inaturalist.org/taxa/47219-Apis-mellifera")
        )
        let fallbackURL = root.appendingPathComponent("western-honey-bee.webloc")
        try WebcardWebloc.write(failedURL).write(to: fallbackURL)

        let hierarchy = try await DirectoryBrowser().discover(at: root).hierarchy

        XCTAssertEqual(hierarchy.discoveredWebcardCount, 2)
        XCTAssertEqual(hierarchy.directWebcards.count, 2)
        let fallback = try XCTUnwrap(
            hierarchy.directWebcards.first { $0.fileURL.pathExtension == "webloc" }
        )
        XCTAssertEqual(fallback.sourceURL, failedURL)
        XCTAssertNil(fallback.capture)
        XCTAssertNotNil(WebcardSearch.score(query: "Apis mellifera", for: fallback))
    }

    func testImmediateEnumerationDoesNotWalkNestedDirectories() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        try writeWebcard(named: "root", to: root)
        let nested = root.appendingPathComponent("Research", isDirectory: true)
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try writeWebcard(named: "nested", to: nested)

        let snapshot = try await DirectoryBrowser().immediateContents(at: root)

        XCTAssertEqual(snapshot.hierarchy.directWebcards.count, 1)
        XCTAssertEqual(snapshot.hierarchy.discoveredWebcardCount, 1)
        XCTAssertFalse(snapshot.hierarchy.isComplete)
        XCTAssertTrue(snapshot.hierarchy.children.isEmpty)
    }

    func testDiscoveryPreservesNestedHierarchy() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let research = root.appendingPathComponent("Research", isDirectory: true)
        let birds = research.appendingPathComponent("Birds", isDirectory: true)
        let photography = birds.appendingPathComponent("Photography", isDirectory: true)
        try fileManager.createDirectory(at: photography, withIntermediateDirectories: true)
        try writeWebcard(named: "research", to: research)
        try writeWebcard(named: "birds", to: birds)
        try writeWebcard(named: "photography", to: photography)

        let hierarchy = try await DirectoryBrowser().discover(at: root).hierarchy

        let researchNode = try XCTUnwrap(hierarchy.children.first)
        let birdsNode = try XCTUnwrap(researchNode.children.first)
        let photographyNode = try XCTUnwrap(birdsNode.children.first)
        XCTAssertEqual(researchNode.directoryURL.lastPathComponent, "Research")
        XCTAssertEqual(birdsNode.directoryURL.lastPathComponent, "Birds")
        XCTAssertEqual(photographyNode.directoryURL.lastPathComponent, "Photography")
        XCTAssertEqual(hierarchy.discoveredWebcardCount, 3)
        XCTAssertEqual(hierarchy.discoveredFolderCount, 3)
        XCTAssertTrue(hierarchy.isComplete)
    }

    func testDiscoveryDepthLimitMarksUnknownWithoutFlattening() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let levelOne = root.appendingPathComponent("One", isDirectory: true)
        let levelTwo = levelOne.appendingPathComponent("Two", isDirectory: true)
        try fileManager.createDirectory(at: levelTwo, withIntermediateDirectories: true)
        try writeWebcard(named: "one", to: levelOne)
        try writeWebcard(named: "two", to: levelTwo)
        let limits = WebcardDiscoveryLimits(
            maximumDepth: 1,
            maximumDirectories: 100,
            maximumWebcards: 100,
            maximumEntriesPerDirectory: 100,
            followsSymbolicLinks: false,
            crossesVolumes: false,
            scansPackages: false,
            scansHiddenDirectories: false
        )

        let hierarchy = try await DirectoryBrowser(limits: limits).discover(at: root).hierarchy

        let one = try XCTUnwrap(hierarchy.children.first)
        let two = try XCTUnwrap(one.children.first)
        XCTAssertEqual(one.directWebcards.count, 1)
        XCTAssertEqual(two.discoveryState, .unknown)
        XCTAssertEqual(hierarchy.discoveredWebcardCount, 1)
        XCTAssertFalse(hierarchy.isComplete)
    }

    func testDiscoverySkipsHiddenPackagesAndSymlinks() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        try writeWebcard(named: "visible", to: root)

        let hidden = root.appendingPathComponent(".hidden", isDirectory: true)
        try fileManager.createDirectory(at: hidden, withIntermediateDirectories: true)
        try writeWebcard(named: "hidden", to: hidden)

        let package = root.appendingPathComponent("Fixture.app", isDirectory: true)
        try fileManager.createDirectory(at: package, withIntermediateDirectories: true)
        try writeWebcard(named: "package", to: package)

        let target = root.appendingPathComponent("Target", isDirectory: true)
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        try writeWebcard(named: "target", to: target)
        try fileManager.createSymbolicLink(
            at: target.appendingPathComponent("cycle"),
            withDestinationURL: root
        )

        let hierarchy = try await DirectoryBrowser().discover(at: root).hierarchy

        XCTAssertEqual(hierarchy.discoveredWebcardCount, 2)
        XCTAssertEqual(hierarchy.children.map(\.directoryURL.lastPathComponent), ["Target"])
    }

    func testDiscoveryCardLimitProducesIncompleteCount() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        for index in 0..<5 {
            try writeWebcard(named: "card-\(index)", to: root)
        }
        let limits = WebcardDiscoveryLimits(
            maximumDepth: 5,
            maximumDirectories: 100,
            maximumWebcards: 2,
            maximumEntriesPerDirectory: 100,
            followsSymbolicLinks: false,
            crossesVolumes: false,
            scansPackages: false,
            scansHiddenDirectories: false
        )

        let hierarchy = try await DirectoryBrowser(limits: limits).discover(at: root).hierarchy

        XCTAssertEqual(hierarchy.discoveredWebcardCount, 2)
        XCTAssertFalse(hierarchy.isComplete)
    }

    @MainActor
    func testFolderBrowserRefreshesWhenWebcardEntersFileTree() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        let model = WebcardFolderBrowserModel(rootURL: root)

        model.loadIfNeeded()
        try await waitUntil {
            model.hierarchy?.isComplete == true
        }
        XCTAssertEqual(model.hierarchy?.discoveredWebcardCount, 0)

        try writeWebcard(named: "new-card", to: nested)

        try await waitUntil(timeout: 5) {
            model.hierarchy?.discoveredWebcardCount == 1
        }
        XCTAssertEqual(
            model.hierarchy?.children.first?.directWebcards.first?.fileURL.lastPathComponent,
            "new-card.webcard"
        )
    }

    @MainActor
    func testFolderBrowserKeepsRootTreeWhenNavigatingToChild() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        try fileManager.createDirectory(at: first, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: second, withIntermediateDirectories: true)
        try writeWebcard(named: "first-card", to: first)
        try writeWebcard(named: "second-card", to: second)
        let model = WebcardFolderBrowserModel(rootURL: root)

        model.loadIfNeeded()
        try await waitUntil {
            model.sidebarHierarchy?.children.count == 2
        }
        model.navigate(to: first)
        try await waitUntil {
            model.hierarchy?.directoryURL == first
                && model.hierarchy?.isComplete == true
        }

        XCTAssertEqual(model.currentURL, first)
        XCTAssertEqual(
            model.sidebarHierarchy?.children.map(\.directoryURL.lastPathComponent),
            ["First", "Second"]
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("WebcardFolderTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeWebcard(named name: String, to directory: URL) throws {
        let imageData = Data("image-\(name)".utf8)
        let capture = WebcardCapture(
            id: name,
            canonicalURL: URL(string: "https://example.com/\(name)")!,
            title: name,
            summary: "Summary for \(name)",
            siteName: "Example",
            imageSHA256: WebcardArchive.sha256(imageData),
            capturedAt: Date(timeIntervalSince1970: 0),
            imageData: imageData
        )
        let file = WebcardFile(
            sourceURL: capture.canonicalURL,
            captures: [capture],
            currentCaptureID: capture.id
        )
        try WebcardArchive.write(file).write(
            to: directory.appendingPathComponent("\(name).webcard"),
            options: .atomic
        )
    }

    private func makeSearchItem(
        filename: String,
        title: String,
        summary: String,
        directory: URL
    ) -> WebcardFolderItem {
        let imageData = Data("image-\(filename)".utf8)
        let capture = WebcardCapture(
            id: filename,
            canonicalURL: URL(string: "https://example.com/\(filename)")!,
            title: title,
            summary: summary,
            siteName: "Example",
            imageSHA256: WebcardArchive.sha256(imageData),
            capturedAt: Date(timeIntervalSince1970: 0),
            imageData: imageData
        )
        return WebcardFolderItem(
            fileURL: directory.appendingPathComponent("\(filename).webcard"),
            file: WebcardFile(
                sourceURL: capture.canonicalURL,
                captures: [capture],
                currentCaptureID: capture.id
            )
        )
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

}
