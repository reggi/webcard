import AppKit
import SwiftUI
import WebcardCore

enum WebcardFolderLayoutMode: String, CaseIterable {
    private static let gridImageAspectRatio: CGFloat = 1.91

    case masonry
    case grid

    var menuTitle: String {
        switch self {
        case .masonry:
            "Use Masonry"
        case .grid:
            "Use Grid"
        }
    }

    var descriptionLineLimit: Int? {
        self == .grid ? 2 : nil
    }

    var masksImage: Bool {
        self == .grid
    }

    func imageHeight(width: CGFloat, imageSize: CGSize) -> CGFloat {
        switch self {
        case .masonry:
            width * imageSize.height / max(1, imageSize.width)
        case .grid:
            width / Self.gridImageAspectRatio
        }
    }
}

@MainActor
final class WebcardFolderSettings: ObservableObject {
    static let shared = WebcardFolderSettings()

    @Published var layoutMode: WebcardFolderLayoutMode {
        didSet {
            UserDefaults.standard.set(layoutMode.rawValue, forKey: Self.layoutModeKey)
        }
    }

    private static let layoutModeKey = "webcardFolderLayoutMode"

    private init() {
        let storedValue = UserDefaults.standard.string(forKey: Self.layoutModeKey)
        layoutMode = WebcardFolderLayoutMode(rawValue: storedValue ?? "") ?? .masonry
    }
}

@MainActor
final class WebcardFolderCommandCenter: ObservableObject {
    static let shared = WebcardFolderCommandCenter()

    @Published var hasActiveFolder = false

    private init() {}
}

struct WebcardFolderItem: Identifiable, Sendable {
    let fileURL: URL
    let file: WebcardFile

    var id: URL {
        fileURL
    }

    var capture: WebcardCapture? {
        file.currentCapture
    }
}

enum WebcardFuzzySearch {
    static func score(query: String, in values: [String]) -> Int? {
        let terms = query
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else {
            return 0
        }

        let candidates = values.map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
        var total = 0
        for term in terms {
            guard let best = candidates.compactMap({ score(term: term, in: $0) }).max() else {
                return nil
            }
            total += best
        }
        return total
    }

    private static func score(term: String, in candidate: String) -> Int? {
        if candidate == term {
            return 1_000
        }
        if candidate.hasPrefix(term) {
            return 900 - candidate.count
        }
        if let range = candidate.range(of: term) {
            return 800 - candidate.distance(from: candidate.startIndex, to: range.lowerBound)
        }

        var searchIndex = candidate.startIndex
        var firstMatch: String.Index?
        var previousMatch: String.Index?
        var gaps = 0
        for character in term {
            guard let match = candidate[searchIndex...].firstIndex(of: character) else {
                return nil
            }
            firstMatch = firstMatch ?? match
            if let previousMatch {
                gaps += max(0, candidate.distance(from: previousMatch, to: match) - 1)
            }
            previousMatch = match
            searchIndex = candidate.index(after: match)
        }
        let start = firstMatch.map { candidate.distance(from: candidate.startIndex, to: $0) } ?? 0
        return 500 - gaps * 4 - start
    }
}

struct MasonryLayout: Layout {
    let columns: Int
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 0
        let measurements = measurements(width: width, subviews: subviews)
        return CGSize(width: width, height: measurements.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let measurements = measurements(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = measurements.frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func measurements(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        let columnCount = max(1, columns)
        let columnWidth = max(1, (width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount))
        var heights = Array(repeating: CGFloat.zero, count: columnCount)
        var frames: [CGRect] = []

        for subview in subviews {
            let column = heights.enumerated().min { $0.element < $1.element }?.offset ?? 0
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            let frame = CGRect(
                x: CGFloat(column) * (columnWidth + spacing),
                y: heights[column],
                width: columnWidth,
                height: size.height
            )
            frames.append(frame)
            heights[column] = frame.maxY + spacing
        }

        return (frames, max(0, (heights.max() ?? 0) - spacing))
    }
}

struct WebcardFolderView: View {
    let folderURL: URL

    @AppStorage("webcardFolderColumnCount") private var columnCount = 3
    @ObservedObject private var folderSettings = WebcardFolderSettings.shared
    @State private var items: [WebcardFolderItem] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let spacing: CGFloat = 20

    private var layoutMode: WebcardFolderLayoutMode {
        folderSettings.layoutMode
    }

    private var filteredItems: [WebcardFolderItem] {
        items.compactMap { item -> (WebcardFolderItem, Int)? in
            guard let capture = item.capture else {
                return nil
            }
            let score = WebcardFuzzySearch.score(
                query: searchText,
                in: [
                    item.fileURL.deletingPathExtension().lastPathComponent,
                    capture.title,
                    capture.summary,
                    capture.siteName,
                    capture.canonicalURL.absoluteString
                ] + capture.socialMetadata.searchableValues
            )
            return score.map { (item, $0) }
        }
        .sorted {
            if $0.1 == $1.1 {
                return $0.0.fileURL.lastPathComponent.localizedStandardCompare(
                    $1.0.fileURL.lastPathComponent
                ) == .orderedAscending
            }
            return $0.1 > $1.1
        }
        .map(\.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()

            if isLoading {
                ProgressView("Loading webcards…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "No Webcards",
                    systemImage: "rectangle.stack",
                    description: Text("This folder does not contain any readable .webcard files.")
                )
            } else if filteredItems.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        let availableWidth = max(1, geometry.size.width - 40)
                        let contentWidth = min(
                            availableWidth,
                            CGFloat(columnCount) * WebcardLayoutMetrics.maximumCardWidth
                                + CGFloat(columnCount - 1) * spacing
                        )
                        let cardWidth = (
                            contentWidth - CGFloat(columnCount - 1) * spacing
                        ) / CGFloat(columnCount)
                        let gridMetadataHeight = layoutMode == .grid
                            ? maximumMetadataHeight(width: cardWidth)
                            : nil

                        Group {
                            if layoutMode == .masonry {
                                MasonryLayout(columns: columnCount, spacing: spacing) {
                                    ForEach(filteredItems) { item in
                                        folderCard(
                                            item,
                                            width: cardWidth,
                                            fixedMetadataHeight: nil
                                        )
                                    }
                                }
                            } else {
                                LazyVGrid(
                                    columns: Array(
                                        repeating: GridItem(.flexible(), spacing: spacing, alignment: .top),
                                        count: max(1, columnCount)
                                    ),
                                    alignment: .leading,
                                    spacing: spacing
                                ) {
                                    ForEach(filteredItems) { item in
                                        folderCard(
                                            item,
                                            width: cardWidth,
                                            fixedMetadataHeight: gridMetadataHeight
                                        )
                                    }
                                }
                            }
                        }
                        .frame(width: contentWidth)
                        .frame(maxWidth: .infinity)
                        .padding(20)
                    }
                }
            }
        }
        .navigationTitle(folderURL.lastPathComponent)
        .navigationSubtitle("\(filteredItems.count) of \(items.count) webcards")
        .task(id: folderURL) {
            await loadFolder()
        }
        .alert("Some Webcards Could Not Be Opened", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            TextField("Search webcards", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220, maxWidth: 420)

            Spacer()

            Text("\(columnCount) columns")
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Stepper("Columns", value: $columnCount, in: 1...8)
                .labelsHidden()
                .help("Change the number of folder columns")
        }
        .padding(12)
    }

    @ViewBuilder
    private func folderCard(
        _ item: WebcardFolderItem,
        width: CGFloat,
        fixedMetadataHeight: CGFloat?
    ) -> some View {
        if let capture = item.capture, let image = NSImage(data: capture.imageData) {
            let imageHeight = layoutMode.imageHeight(width: width, imageSize: image.size)
            let metadataHeight = fixedMetadataHeight ?? measuredMetadataHeight(
                for: item,
                width: width
            )
            WebcardCardView(
                capture: capture,
                image: image,
                width: width,
                imageHeight: imageHeight,
                metadataHeight: metadataHeight,
                maximumMetadataHeight: nil,
                usesInsecureHTTP: item.file.sourceURL?.scheme?.lowercased() == "http",
                masksImage: layoutMode.masksImage,
                descriptionLineLimit: layoutMode.descriptionLineLimit
            )
            .contextMenu {
                Button("Open Webcard") {
                    let hasAccess = folderURL.startAccessingSecurityScopedResource()
                    NSDocumentController.shared.openDocument(
                        withContentsOf: item.fileURL,
                        display: true
                    ) { _, _, _ in
                        if hasAccess {
                            folderURL.stopAccessingSecurityScopedResource()
                        }
                    }
                }
            }
        }
    }

    private func maximumMetadataHeight(width: CGFloat) -> CGFloat {
        filteredItems.map {
            measuredMetadataHeight(for: $0, width: width)
        }.max() ?? 0
    }

    private func measuredMetadataHeight(
        for item: WebcardFolderItem,
        width: CGFloat
    ) -> CGFloat {
        guard let capture = item.capture else {
            return 0
        }
        return SelectableMetadataView.height(
            for: capture,
            usesInsecureHTTP: item.file.sourceURL?.scheme?.lowercased() == "http",
            width: width - WebcardLayoutMetrics.contentInset * 2,
            descriptionLineLimit: layoutMode.descriptionLineLimit
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func loadFolder() async {
        isLoading = true
        errorMessage = nil
        let hasAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let result = try await Task.detached {
                try Self.readFolder(folderURL)
            }.value
            items = result.items
            let failures = result.failures
            if !failures.isEmpty {
                errorMessage = failures.joined(separator: "\n")
            }
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    nonisolated private static func readFolder(
        _ folderURL: URL
    ) throws -> (items: [WebcardFolderItem], failures: [String]) {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var items: [WebcardFolderItem] = []
        var failures: [String] = []
        for url in urls
            .filter({ $0.pathExtension.lowercased() == "webcard" })
            .sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            do {
                items.append(
                    WebcardFolderItem(
                        fileURL: url,
                        file: try WebcardArchive.read(Data(contentsOf: url))
                    )
                )
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (items, failures)
    }
}
