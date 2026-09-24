import AppKit
import os
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

    var titleLineLimit: Int? {
        self == .grid ? 3 : nil
    }

    var urlLineLimit: Int? {
        self == .grid ? 1 : nil
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

enum WebcardFolderPresentationMode: String, CaseIterable {
    case inline
    case cards

    var menuTitle: String {
        switch self {
        case .inline:
            "Inline"
        case .cards:
            "As Cards"
        }
    }
}

enum WebcardFolderColumnMode: String, CaseIterable {
    case dynamic
    case one
    case two
    case three
    case four

    var menuTitle: String {
        switch self {
        case .dynamic:
            "Deyn"
        case .one:
            "1 Column"
        case .two:
            "2 Columns"
        case .three:
            "3 Columns"
        case .four:
            "4 Columns"
        }
    }

    func columnCount(availableWidth: CGFloat, spacing: CGFloat) -> Int {
        switch self {
        case .dynamic:
            let minimumCardWidth = WebcardLayoutMetrics.compactCardWidth
            let fittingColumns = Int(
                (availableWidth + spacing) / (minimumCardWidth + spacing)
            )
            return min(4, max(1, fittingColumns))
        case .one:
            return 1
        case .two:
            return 2
        case .three:
            return 3
        case .four:
            return 4
        }
    }

    func columnCount(
        availableWidth: CGFloat,
        spacing: CGFloat,
        itemCount: Int
    ) -> Int {
        let responsiveColumns = columnCount(
            availableWidth: availableWidth,
            spacing: spacing
        )
        guard self == .dynamic else {
            return responsiveColumns
        }
        return min(responsiveColumns, max(2, itemCount))
    }
}

enum WebcardVisualHierarchy {
    static let maximumInlineDepth = 2

    static func usesContinuationItems(at visualDepth: Int) -> Bool {
        visualDepth >= maximumInlineDepth
    }
}

struct WebcardGalleryMetrics: Equatable {
    let columns: Int
    let cardWidth: CGFloat
    let contentWidth: CGFloat

    init(
        availableWidth: CGFloat,
        requestedColumns: Int,
        spacing: CGFloat,
        maximumCardWidth: CGFloat = WebcardLayoutMetrics.maximumCardWidth
    ) {
        columns = max(1, requestedColumns)
        let unconstrainedWidth = max(
            1,
            (availableWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        )
        cardWidth = min(maximumCardWidth, unconstrainedWidth)
        contentWidth = cardWidth * CGFloat(columns)
            + CGFloat(columns - 1) * spacing
    }
}

enum WebcardGridRowMetrics {
    static func optimizedColumnCount(
        maximumColumns: Int,
        itemCount: Int
    ) -> Int {
        let maximumColumns = max(1, maximumColumns)
        guard maximumColumns > 1, itemCount > 1 else {
            return maximumColumns
        }
        guard itemCount <= maximumColumns * 2 else {
            return maximumColumns
        }

        var bestColumns = maximumColumns
        var fewestEmptyCells = emptyCellCount(
            columns: maximumColumns,
            itemCount: itemCount
        )
        for columns in stride(from: maximumColumns - 1, through: 2, by: -1) {
            let emptyCells = emptyCellCount(
                columns: columns,
                itemCount: itemCount
            )
            if emptyCells < fewestEmptyCells {
                bestColumns = columns
                fewestEmptyCells = emptyCells
            }
        }
        return bestColumns
    }

    static func equalizedHeights(
        _ heights: [CGFloat],
        columns: Int
    ) -> [CGFloat] {
        guard columns > 0 else {
            return heights
        }

        return stride(from: 0, to: heights.count, by: columns).flatMap { rowStart in
            let rowEnd = min(rowStart + columns, heights.count)
            let row = heights[rowStart..<rowEnd]
            return Array(repeating: row.max() ?? 0, count: row.count)
        }
    }

    private static func emptyCellCount(
        columns: Int,
        itemCount: Int
    ) -> Int {
        let remainder = itemCount % columns
        return remainder == 0 ? 0 : columns - remainder
    }
}

struct WebcardGalleryGroup: Identifiable {
    let id: URL
    let node: WebcardDirectoryNode
    let path: [String]
    let entryIDs: [String]
}

struct WebcardGalleryEntry: Identifiable {
    enum Content {
        case webcard(WebcardFolderItem)
        case continuation(WebcardDirectoryNode, path: [String])
    }

    let id: String
    let content: Content
    let groupIDs: [URL]
}

struct WebcardGalleryProjection {
    let entries: [WebcardGalleryEntry]
    let groups: [WebcardGalleryGroup]

    static func make(
        hierarchy: WebcardDirectoryNode,
        presentationMode: WebcardFolderPresentationMode
    ) -> WebcardGalleryProjection {
        var builder = Builder()
        builder.appendWebcards(hierarchy.directWebcards, groupIDs: [])

        switch presentationMode {
        case .inline:
            for child in hierarchy.children.filter(\.hasDiscoveredContent) {
                builder.appendInlineGroup(
                    child,
                    visualDepth: 1,
                    path: [displayName(for: child.directoryURL)],
                    ancestorGroupIDs: []
                )
            }
        case .cards:
            for child in hierarchy.children.filter(\.hasDiscoveredContent) {
                builder.appendContinuation(
                    child,
                    path: [displayName(for: child.directoryURL)],
                    groupIDs: []
                )
            }
        }
        return WebcardGalleryProjection(
            entries: builder.entries,
            groups: builder.groups
        )
    }

    private static func displayName(for url: URL) -> String {
        url.path == "/" ? "/" : url.lastPathComponent
    }

    private struct Builder {
        var entries: [WebcardGalleryEntry] = []
        var groups: [WebcardGalleryGroup] = []

        mutating func appendInlineGroup(
            _ node: WebcardDirectoryNode,
            visualDepth: Int,
            path: [String],
            ancestorGroupIDs: [URL]
        ) {
            let groupIDs = ancestorGroupIDs + [node.id]
            let firstEntryIndex = entries.count
            appendWebcards(node.directWebcards, groupIDs: groupIDs)

            if WebcardVisualHierarchy.usesContinuationItems(at: visualDepth) {
                for child in node.children.filter(\.hasDiscoveredContent) {
                    appendContinuation(
                        child,
                        path: path + [WebcardGalleryProjection.displayName(for: child.directoryURL)],
                        groupIDs: groupIDs
                    )
                }
            } else {
                for child in node.children.filter(\.hasDiscoveredContent) {
                    appendInlineGroup(
                        child,
                        visualDepth: visualDepth + 1,
                        path: path + [WebcardGalleryProjection.displayName(for: child.directoryURL)],
                        ancestorGroupIDs: groupIDs
                    )
                }
            }

            let entryIDs = entries[firstEntryIndex...].map(\.id)
            if !entryIDs.isEmpty {
                groups.append(
                    WebcardGalleryGroup(
                        id: node.id,
                        node: node,
                        path: path,
                        entryIDs: entryIDs
                    )
                )
            }
        }

        mutating func appendWebcards(
            _ webcards: [WebcardFolderItem],
            groupIDs: [URL]
        ) {
            for item in webcards.sorted(by: {
                $0.fileURL.lastPathComponent.localizedStandardCompare(
                    $1.fileURL.lastPathComponent
                ) == .orderedAscending
            }) {
                entries.append(
                    WebcardGalleryEntry(
                        id: "webcard:\(item.id.absoluteString)",
                        content: .webcard(item),
                        groupIDs: groupIDs
                    )
                )
            }
        }

        mutating func appendContinuation(
            _ node: WebcardDirectoryNode,
            path: [String],
            groupIDs: [URL]
        ) {
            entries.append(
                WebcardGalleryEntry(
                    id: "folder:\(node.id.absoluteString)",
                    content: .continuation(node, path: path),
                    groupIDs: groupIDs
                )
            )
        }
    }
}

enum WebcardFolderCountFormatter {
    static func label(for node: WebcardDirectoryNode) -> String {
        let webcardSuffix = node.isComplete ? "" : "+"
        let webcardNoun = node.discoveredWebcardCount == 1 ? "webcard" : "webcards"
        let folderNoun = node.discoveredFolderCount == 1 ? "folder" : "folders"
        if node.discoveredFolderCount == 0 {
            return "\(node.discoveredWebcardCount)\(webcardSuffix) \(webcardNoun)"
        }
        return "\(node.discoveredWebcardCount)\(webcardSuffix) \(webcardNoun) · \(node.discoveredFolderCount) \(folderNoun)"
    }
}

struct WebcardOutlineSegment: Equatable {
    let start: CGPoint
    let end: CGPoint
}

enum WebcardGroupOutlineGeometry {
    static func boundarySegments(
        frames: [CGRect],
        expansion: CGFloat
    ) -> [WebcardOutlineSegment] {
        let rectangles = frames.map {
            $0.insetBy(dx: -expansion, dy: -expansion)
        }
        var segments: [WebcardOutlineSegment] = []

        for (index, rectangle) in rectangles.enumerated() {
            let others = Array(rectangles[..<index]) + Array(rectangles[(index + 1)...])
            segments += horizontalSegments(
                from: rectangle.minX,
                to: rectangle.maxX,
                y: rectangle.minY,
                coveredBy: others.compactMap { other in
                    other.minY < rectangle.minY && other.maxY >= rectangle.minY
                        ? other.minX...other.maxX
                        : nil
                }
            )
            segments += horizontalSegments(
                from: rectangle.minX,
                to: rectangle.maxX,
                y: rectangle.maxY,
                coveredBy: others.compactMap { other in
                    other.minY <= rectangle.maxY && other.maxY > rectangle.maxY
                        ? other.minX...other.maxX
                        : nil
                }
            )
            segments += verticalSegments(
                from: rectangle.minY,
                to: rectangle.maxY,
                x: rectangle.minX,
                coveredBy: others.compactMap { other in
                    other.minX < rectangle.minX && other.maxX >= rectangle.minX
                        ? other.minY...other.maxY
                        : nil
                }
            )
            segments += verticalSegments(
                from: rectangle.minY,
                to: rectangle.maxY,
                x: rectangle.maxX,
                coveredBy: others.compactMap { other in
                    other.minX <= rectangle.maxX && other.maxX > rectangle.maxX
                        ? other.minY...other.maxY
                        : nil
                }
            )
        }
        return segments
    }

    static func path(
        frames: [CGRect],
        expansion: CGFloat
    ) -> Path {
        var path = Path()
        for segment in boundarySegments(frames: frames, expansion: expansion) {
            path.move(to: segment.start)
            path.addLine(to: segment.end)
        }
        return path
    }

    private static func horizontalSegments(
        from start: CGFloat,
        to end: CGFloat,
        y: CGFloat,
        coveredBy intervals: [ClosedRange<CGFloat>]
    ) -> [WebcardOutlineSegment] {
        subtract(intervals, from: start...end).map {
            WebcardOutlineSegment(
                start: CGPoint(x: $0.lowerBound, y: y),
                end: CGPoint(x: $0.upperBound, y: y)
            )
        }
    }

    private static func verticalSegments(
        from start: CGFloat,
        to end: CGFloat,
        x: CGFloat,
        coveredBy intervals: [ClosedRange<CGFloat>]
    ) -> [WebcardOutlineSegment] {
        subtract(intervals, from: start...end).map {
            WebcardOutlineSegment(
                start: CGPoint(x: x, y: $0.lowerBound),
                end: CGPoint(x: x, y: $0.upperBound)
            )
        }
    }

    private static func subtract(
        _ intervals: [ClosedRange<CGFloat>],
        from source: ClosedRange<CGFloat>
    ) -> [ClosedRange<CGFloat>] {
        var remaining = [source]
        for interval in intervals {
            remaining = remaining.flatMap { candidate in
                let lower = max(candidate.lowerBound, interval.lowerBound)
                let upper = min(candidate.upperBound, interval.upperBound)
                guard lower < upper else {
                    return [candidate]
                }

                var pieces: [ClosedRange<CGFloat>] = []
                if candidate.lowerBound < lower {
                    pieces.append(candidate.lowerBound...lower)
                }
                if upper < candidate.upperBound {
                    pieces.append(upper...candidate.upperBound)
                }
                return pieces
            }
        }
        return remaining.filter { $0.lowerBound < $0.upperBound }
    }
}

private struct WebcardDynamicGroupOutline: View {
    let group: WebcardGalleryGroup
    let frames: [CGRect]
    let spacing: CGFloat
    let countLabel: String
    let open: () -> Void

    private var unionBounds: CGRect {
        frames.reduce(.null) { $0.union($1) }
    }

    private var expansion: CGFloat {
        spacing / 2 + 2
    }

    private var labelAnchor: CGPoint {
        let firstFrame = frames.min {
            if abs($0.minY - $1.minY) < 0.5 {
                return $0.minX < $1.minX
            }
            return $0.minY < $1.minY
        } ?? unionBounds
        return CGPoint(
            x: firstFrame.minX,
            y: max(0, firstFrame.minY - expansion - 11)
        )
    }

    var body: some View {
        if !frames.isEmpty {
            Canvas { context, _ in
                context.stroke(
                    WebcardGroupOutlineGeometry.path(
                        frames: frames,
                        expansion: expansion
                    ),
                    with: .color(Color.accentColor.opacity(0.9)),
                    style: StrokeStyle(
                        lineWidth: 1.5,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
            .allowsHitTesting(false)

            Button(action: open) {
                HStack(spacing: 7) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(group.path.last ?? group.node.directoryURL.lastPathComponent)
                        .font(.headline)
                    Text(countLabel)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .offset(
                x: labelAnchor.x,
                y: labelAnchor.y
            )
            .help("Open \(group.path.joined(separator: " › "))")
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

    @Published var presentationMode: WebcardFolderPresentationMode {
        didSet {
            UserDefaults.standard.set(
                presentationMode.rawValue,
                forKey: Self.presentationModeKey
            )
        }
    }

    @Published var columnMode: WebcardFolderColumnMode {
        didSet {
            UserDefaults.standard.set(
                columnMode.rawValue,
                forKey: Self.columnModeKey
            )
        }
    }

    @Published var isDirectoryDrawerVisible: Bool {
        didSet {
            UserDefaults.standard.set(
                isDirectoryDrawerVisible,
                forKey: Self.directoryDrawerVisibleKey
            )
        }
    }

    private static let layoutModeKey = "webcardFolderLayoutMode"
    private static let presentationModeKey = "webcardFolderPresentationMode"
    private static let columnModeKey = "webcardFolderColumnMode"
    private static let directoryDrawerVisibleKey = "webcardDirectoryDrawerVisible"

    private init() {
        let storedValue = UserDefaults.standard.string(forKey: Self.layoutModeKey)
        layoutMode = WebcardFolderLayoutMode(rawValue: storedValue ?? "") ?? .masonry
        let storedPresentation = UserDefaults.standard.string(
            forKey: Self.presentationModeKey
        )
        presentationMode = WebcardFolderPresentationMode(
            rawValue: storedPresentation ?? ""
        ) ?? .inline
        let storedColumnMode = UserDefaults.standard.string(
            forKey: Self.columnModeKey
        )
        columnMode = WebcardFolderColumnMode(
            rawValue: storedColumnMode ?? ""
        ) ?? .dynamic
        isDirectoryDrawerVisible = UserDefaults.standard.object(
            forKey: Self.directoryDrawerVisibleKey
        ) as? Bool ?? true
    }
}

@MainActor
final class WebcardFolderCommandCenter: ObservableObject {
    static let shared = WebcardFolderCommandCenter()

    @Published private(set) var hasActiveFolder = false

    private var activeFolderID: UUID?

    private init() {}

    func activate(id: UUID) {
        activeFolderID = id
        hasActiveFolder = true
    }

    func deactivate(id: UUID) {
        guard activeFolderID == id else { return }
        activeFolderID = nil
        hasActiveFolder = false
    }
}

enum WebcardFolderFileWriter {
    static func write(
        _ file: WebcardFile,
        to directoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let data = try WebcardArchive.write(file)
        let destinationURL = try availableDestinationURL(
            suggestedFilename: file.suggestedFilename,
            in: directoryURL,
            fileManager: fileManager
        )
        try data.write(to: destinationURL, options: .atomic)
        return destinationURL.standardizedFileURL
    }

    static func writeWebloc(
        for url: URL,
        to directoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let destinationURL = try availableDestinationURL(
            suggestedFilename: WebcardWebloc.suggestedFilename(for: url),
            in: directoryURL,
            fileManager: fileManager
        )
        try WebcardWebloc.write(url).write(to: destinationURL, options: .atomic)
        return destinationURL.standardizedFileURL
    }

    static func availableDestinationURL(
        suggestedFilename: String,
        in directoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let existingNames = Set(
            try fileManager.contentsOfDirectory(atPath: directoryURL.path)
                .map { $0.folding(options: [.caseInsensitive], locale: .current) }
        )
        let suggestedURL = URL(fileURLWithPath: suggestedFilename)
        let basename = suggestedURL.deletingPathExtension().lastPathComponent
        let pathExtension = suggestedURL.pathExtension

        var candidate = suggestedFilename
        var suffix = 2
        while existingNames.contains(
            candidate.folding(options: [.caseInsensitive], locale: .current)
        ) {
            candidate = "\(basename) \(suffix)"
            if !pathExtension.isEmpty {
                candidate += ".\(pathExtension)"
            }
            suffix += 1
        }
        return directoryURL.appendingPathComponent(candidate, isDirectory: false)
    }
}

@MainActor
final class WebcardFolderBrowserModel: ObservableObject {
    @Published private(set) var hierarchy: WebcardDirectoryNode?
    @Published private(set) var sidebarHierarchy: WebcardDirectoryNode?
    @Published private(set) var navigationPath: [URL]
    @Published private(set) var isLoadingImmediate = true
    @Published private(set) var isDiscovering = false
    @Published var errorMessage: String?

    private let browser: DirectoryBrowser
    private let rootURL: URL
    private var loadTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var directoryMonitor: WebcardDirectoryMonitor?

    init(
        rootURL: URL,
        browser: DirectoryBrowser = DirectoryBrowser()
    ) {
        let standardizedRootURL = rootURL.standardizedFileURL
        self.rootURL = standardizedRootURL
        navigationPath = [standardizedRootURL]
        self.browser = browser
    }

    deinit {
        loadTask?.cancel()
        refreshTask?.cancel()
    }

    var currentURL: URL {
        navigationPath.last!
    }

    var canGoBack: Bool {
        navigationPath.count > 1
    }

    func loadIfNeeded() {
        guard hierarchy == nil, loadTask == nil else {
            return
        }
        monitorCurrentDirectory()
        loadCurrentDirectory()
    }

    func navigate(to directoryURL: URL) {
        let standardizedURL = directoryURL.standardizedFileURL
        guard standardizedURL != currentURL else {
            return
        }
        guard let newPath = Self.navigationPath(
            from: rootURL,
            to: standardizedURL
        ) else {
            return
        }
        navigationPath = newPath
        monitorCurrentDirectory()
        loadCurrentDirectory()
    }

    func goBack() {
        guard canGoBack else {
            return
        }
        navigationPath.removeLast()
        monitorCurrentDirectory()
        loadCurrentDirectory()
    }

    func refresh() {
        scheduleRefresh(delay: .zero)
    }

    func navigateToBreadcrumb(at index: Int) {
        guard navigationPath.indices.contains(index), index < navigationPath.count - 1 else {
            return
        }
        navigationPath.removeSubrange((index + 1)...)
        monitorCurrentDirectory()
        loadCurrentDirectory()
    }

    private func loadCurrentDirectory() {
        loadTask?.cancel()
        refreshTask?.cancel()
        let directoryURL = currentURL
        hierarchy = nil
        errorMessage = nil
        isLoadingImmediate = true
        isDiscovering = false

        loadTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let immediate = try await browser.immediateContents(at: directoryURL)
                try Task.checkCancellation()
                guard currentURL == directoryURL else {
                    return
                }
                hierarchy = immediate.hierarchy
                if directoryURL == rootURL {
                    sidebarHierarchy = immediate.hierarchy
                }
                isLoadingImmediate = false
                isDiscovering = true
                updateErrors(immediate.errors)

                let discovered = try await browser.discover(at: directoryURL)
                try Task.checkCancellation()
                guard currentURL == directoryURL else {
                    return
                }
                hierarchy = discovered.hierarchy
                updateSidebarHierarchy(with: discovered.hierarchy)
                isDiscovering = false
                updateErrors(discovered.errors)
            } catch is CancellationError {
                return
            } catch {
                guard currentURL == directoryURL else {
                    return
                }
                hierarchy = nil
                isLoadingImmediate = false
                isDiscovering = false
                errorMessage = error.localizedDescription
            }
            loadTask = nil
        }
    }

    private func monitorCurrentDirectory() {
        directoryMonitor = WebcardDirectoryMonitor(directoryURL: currentURL) { [weak self] in
            self?.scheduleRefresh()
        }
    }

    private func scheduleRefresh(delay: Duration = .milliseconds(300)) {
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let directoryURL = currentURL
        refreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                guard let self, currentURL == directoryURL else {
                    return
                }
                await browser.invalidate(directoryURL)
                let discovered = try await browser.discover(at: directoryURL)
                try Task.checkCancellation()
                guard currentURL == directoryURL else {
                    return
                }
                hierarchy = discovered.hierarchy
                updateSidebarHierarchy(with: discovered.hierarchy)
                isLoadingImmediate = false
                isDiscovering = false
                updateErrors(discovered.errors)
            } catch is CancellationError {
                return
            } catch {
                guard let self, currentURL == directoryURL else {
                    return
                }
                isLoadingImmediate = false
                isDiscovering = false
                errorMessage = error.localizedDescription
            }
            if self?.refreshGeneration == generation {
                self?.refreshTask = nil
            }
        }
    }

    private func updateErrors(_ errors: [String]) {
        guard !errors.isEmpty else {
            return
        }
        errorMessage = errors.prefix(20).joined(separator: "\n")
    }

    private func updateSidebarHierarchy(with node: WebcardDirectoryNode) {
        if node.directoryURL == rootURL || sidebarHierarchy == nil {
            sidebarHierarchy = node
        } else {
            sidebarHierarchy = sidebarHierarchy?.replacingSubtree(with: node)
        }
    }

    nonisolated static func navigationPath(
        from rootURL: URL,
        to directoryURL: URL
    ) -> [URL]? {
        let root = rootURL.standardizedFileURL
        let directory = directoryURL.standardizedFileURL
        let rootComponents = root.pathComponents
        let directoryComponents = directory.pathComponents
        guard directoryComponents.starts(with: rootComponents) else {
            return nil
        }

        var path = [root]
        var current = root
        for component in directoryComponents.dropFirst(rootComponents.count) {
            current.appendPathComponent(component, isDirectory: true)
            path.append(current.standardizedFileURL)
        }
        return path
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
        let itemHeights = subviews.map {
            $0.sizeThatFits(
                ProposedViewSize(width: columnWidth, height: nil)
            ).height
        }
        return WebcardMasonryPlanner.measurements(
            width: width,
            itemHeights: itemHeights,
            columns: columnCount,
            spacing: spacing
        )
    }
}

enum WebcardMasonryPlanner {
    static func measurements(
        width: CGFloat,
        itemHeights: [CGFloat],
        columns: Int,
        spacing: CGFloat
    ) -> (frames: [CGRect], height: CGFloat) {
        let columnCount = max(1, columns)
        let columnWidth = max(
            1,
            (width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        )
        var heights = Array(repeating: CGFloat.zero, count: columnCount)
        var frames: [CGRect] = []

        for itemHeight in itemHeights {
            let column = heights.enumerated().min {
                $0.element < $1.element
            }?.offset ?? 0
            let frame = CGRect(
                x: CGFloat(column) * (columnWidth + spacing),
                y: heights[column],
                width: columnWidth,
                height: itemHeight
            )
            frames.append(frame)
            heights[column] = frame.maxY + spacing
        }

        return (frames, max(0, (heights.max() ?? 0) - spacing))
    }
}

struct WebcardWebLocationDocumentView: View {
    let fileURL: URL
    let url: URL

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                let width = min(max(proxy.size.width - 40, 280), 520)
                WebcardWebLocationCard(
                    fileURL: fileURL,
                    url: url,
                    width: width,
                    imageHeight: width * 9 / 16,
                    metadataHeight: 86,
                    urlLineLimit: nil
                )
                .frame(maxWidth: .infinity)
                .padding(20)
            }
        }
        .frame(minWidth: 360, minHeight: 420)
    }
}

struct WebcardWebLocationCard: View {
    let fileURL: URL
    let url: URL
    let width: CGFloat
    let imageHeight: CGFloat
    let metadataHeight: CGFloat
    let urlLineLimit: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color.blue.opacity(0.1)
                Image(systemName: "link")
                    .font(.system(size: min(width * 0.2, 64), weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .frame(width: width, height: imageHeight)

            VStack(alignment: .leading, spacing: WebcardLayoutMetrics.contentInset) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Web Location")
                        .font(.headline)
                    Text(url.host ?? fileURL.deletingPathExtension().lastPathComponent)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(url.absoluteString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(urlLineLimit ?? 2)
                        .textSelection(.enabled)
                }
                .frame(height: metadataHeight, alignment: .topLeading)

                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
                .frame(height: WebcardLayoutMetrics.buttonHeight)
            }
            .padding(WebcardLayoutMetrics.contentInset)
            .frame(width: width, alignment: .topLeading)
        }
        .frame(width: width, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 14, y: 5)
        .id(fileURL.standardizedFileURL)
        .contextMenu {
            Button("Open in Browser") {
                NSWorkspace.shared.open(url)
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
        }
    }
}

struct WebcardFolderView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Webcard",
        category: "FolderLayout"
    )

    @ObservedObject private var folderSettings = WebcardFolderSettings.shared
    @StateObject private var browserModel: WebcardFolderBrowserModel
    @State private var searchText = ""
    @State private var pendingScrollURL: URL?

    private let spacing: CGFloat = 20

    init(folderURL: URL) {
        _browserModel = StateObject(
            wrappedValue: WebcardFolderBrowserModel(rootURL: folderURL)
        )
    }

    private var layoutMode: WebcardFolderLayoutMode {
        folderSettings.layoutMode
    }

    private var visibleHierarchy: WebcardDirectoryNode? {
        browserModel.hierarchy?.filtering(query: searchText)
    }

    private var allVisibleItems: [WebcardFolderItem] {
        guard let visibleHierarchy else {
            return []
        }
        return flattenWebcards(in: visibleHierarchy)
    }

    private var hasSearchQuery: Bool {
        !WebcardSearch.isEmpty(searchText)
    }

    var body: some View {
        HSplitView {
            if folderSettings.isDirectoryDrawerVisible {
                WebcardFolderSidebar(
                    hierarchy: browserModel.sidebarHierarchy,
                    selectedURL: browserModel.currentURL,
                    isLoading: browserModel.isLoadingImmediate && browserModel.sidebarHierarchy == nil,
                    navigate: browserModel.navigate(to:)
                )
                .frame(minWidth: 190, idealWidth: 240, maxWidth: 320)
            }

            VStack(spacing: 0) {
                controls
                Divider()

                if browserModel.isLoadingImmediate {
                    ProgressView("Loading webcards…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if browserModel.hierarchy?.hasDiscoveredContent == false,
                          !browserModel.isDiscovering {
                    ContentUnavailableView(
                        "No Webcards",
                        systemImage: "rectangle.stack",
                        description: Text(
                            browserModel.hierarchy?.isComplete == true
                                ? "No readable .webcard files were found within the discovery limits."
                                : "No webcards have been discovered yet. The bounded scan was incomplete."
                        )
                    )
                } else if visibleHierarchy == nil, hasSearchQuery {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    gallery
                }
            }
            .frame(minWidth: 520)
        }
        .navigationTitle(displayName(for: browserModel.currentURL))
        .navigationSubtitle(navigationSubtitle)
        .task {
            browserModel.loadIfNeeded()
        }
        .alert("Some Webcards Could Not Be Opened", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(browserModel.errorMessage ?? "")
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    folderSettings.isDirectoryDrawerVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(
                    folderSettings.isDirectoryDrawerVisible
                        ? "Hide Directory Drawer"
                        : "Show Directory Drawer"
                )
                .accessibilityLabel(
                    folderSettings.isDirectoryDrawerVisible
                        ? "Hide Directory Drawer"
                        : "Show Directory Drawer"
                )

                Button {
                    browserModel.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!browserModel.canGoBack)
                .help("Back")

                breadcrumb

                Spacer()

                if browserModel.isDiscovering {
                    ProgressView()
                        .controlSize(.small)
                    Text("Discovering nested webcards…")
                        .foregroundStyle(.secondary)
                }

                Button {
                    WebcardAppDelegate.shared?.showAddWebcardWindow(
                        destinationDirectory: browserModel.currentURL
                    ) { fileURL in
                        searchText = ""
                        pendingScrollURL = fileURL
                        browserModel.refresh()
                    }
                } label: {
                    Label("Add Webcard", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .webcardPointingHandCursor()
            }

            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(
                        "Search titles, URLs, descriptions, and metadata",
                        text: $searchText
                    )
                    .textFieldStyle(.plain)
                    if hasSearchQuery {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear Search")
                        .accessibilityLabel("Clear Search")
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }
                .frame(minWidth: 280, maxWidth: 520)

                if hasSearchQuery {
                    Text(searchResultLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(12)
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            ForEach(Array(browserModel.navigationPath.enumerated()), id: \.element) { index, url in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(displayName(for: url)) {
                    browserModel.navigateToBreadcrumb(at: index)
                }
                .buttonStyle(.plain)
                .disabled(index == browserModel.navigationPath.count - 1)
            }
        }
        .lineLimit(1)
    }

    private var gallery: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    let availableWidth = max(1, geometry.size.width - 40)
                    let breakpointColumns = folderSettings.columnMode.columnCount(
                        availableWidth: availableWidth,
                        spacing: spacing
                    )
                    if let visibleHierarchy {
                        VStack(alignment: .leading, spacing: spacing) {
                            cardFlow(
                                items: sorted(visibleHierarchy.directWebcards),
                                availableWidth: availableWidth
                            )

                            if folderSettings.presentationMode == .inline {
                                ForEach(visibleHierarchy.children.filter(\.hasDiscoveredContent)) { child in
                                    inlineGroup(
                                        child,
                                        visualDepth: 1,
                                        path: [displayName(for: child.directoryURL)],
                                        availableWidth: availableWidth
                                    )
                                }
                            } else {
                                continuationFlow(
                                    visibleHierarchy.children.filter(\.hasDiscoveredContent),
                                    pathPrefix: [],
                                    availableWidth: availableWidth
                                )
                            }
                        }
                        .id("\(layoutMode.rawValue)-\(breakpointColumns)-\(folderSettings.presentationMode.rawValue)")
                        .frame(width: availableWidth, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(20)
                    }
                }
                .onChange(of: allVisibleItems.map(\.fileURL), initial: true) { _, fileURLs in
                    guard let pendingScrollURL,
                          fileURLs.map(\.standardizedFileURL).contains(pendingScrollURL) else {
                        return
                    }
                    DispatchQueue.main.async {
                        withAnimation {
                            proxy.scrollTo(pendingScrollURL, anchor: .center)
                        }
                        self.pendingScrollURL = nil
                    }
                }
            }
            .task(id: "\(layoutDebugID)-\(Int(geometry.size.width / 50))x\(Int(geometry.size.height / 50))") {
                logLayoutState(viewportSize: geometry.size)
            }
        }
    }

    private func inlineGroup(
        _ node: WebcardDirectoryNode,
        visualDepth: Int,
        path: [String],
        availableWidth: CGFloat
    ) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: spacing) {
                groupHeader(node, path: path)
                cardFlow(
                    items: sorted(node.directWebcards),
                    availableWidth: availableWidth
                )

                if !WebcardVisualHierarchy.usesContinuationItems(at: visualDepth) {
                    ForEach(node.children.filter(\.hasDiscoveredContent)) { child in
                        inlineGroup(
                            child,
                            visualDepth: visualDepth + 1,
                            path: path + [displayName(for: child.directoryURL)],
                            availableWidth: availableWidth
                        )
                    }
                } else {
                    continuationFlow(
                        node.children.filter(\.hasDiscoveredContent),
                        pathPrefix: path,
                        availableWidth: availableWidth
                    )
                }
            }
        )
    }

    private func groupHeader(
        _ node: WebcardDirectoryNode,
        path: [String]
    ) -> some View {
        Button {
            browserModel.navigate(to: node.directoryURL)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(path.last ?? displayName(for: node.directoryURL))
                        .font(.headline)
                    Text(path.joined(separator: "/"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(countLabel(for: node))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(path.joined(separator: " › "))")
    }

    @ViewBuilder
    private func continuationFlow(
        _ nodes: [WebcardDirectoryNode],
        pathPrefix: [String],
        availableWidth: CGFloat
    ) -> some View {
        if !nodes.isEmpty {
            let metrics = galleryMetrics(
                availableWidth: availableWidth,
                itemCount: nodes.count
            )
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(metrics.cardWidth), spacing: spacing, alignment: .top),
                    count: metrics.columns
                ),
                alignment: .leading,
                spacing: spacing
            ) {
                ForEach(nodes) { node in
                    continuationItem(
                        node,
                        path: pathPrefix + [displayName(for: node.directoryURL)],
                        width: metrics.cardWidth
                    )
                }
            }
            .frame(width: metrics.contentWidth, alignment: .leading)
        }
    }

    private func continuationItem(
        _ node: WebcardDirectoryNode,
        path: [String],
        width: CGFloat
    ) -> some View {
        Button {
            browserModel.navigate(to: node.directoryURL)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(path.joined(separator: " › "))
                        .font(.headline)
                        .lineLimit(2)
                    Spacer()
                }
                Text(countLabel(for: node))
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Open")
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(Color.accentColor)
            }
            .frame(width: width, alignment: .leading)
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func unifiedFlow(
        _ entries: [WebcardGalleryEntry],
        width: CGFloat,
        fixedMetadataHeight: CGFloat?,
        columns: Int
    ) -> some View {
        if !entries.isEmpty {
            let flowWidth = CGFloat(columns) * width + CGFloat(columns - 1) * spacing
            if layoutMode == .masonry {
                MasonryLayout(columns: columns, spacing: spacing) {
                    ForEach(entries) { entry in
                        galleryEntry(
                            entry,
                            width: width,
                            fixedMetadataHeight: nil
                        )
                    }
                }
                .frame(width: flowWidth, alignment: .leading)
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(width), spacing: spacing, alignment: .top),
                        count: columns
                    ),
                    alignment: .leading,
                    spacing: spacing
                ) {
                    ForEach(entries) { entry in
                        galleryEntry(
                            entry,
                            width: width,
                            fixedMetadataHeight: fixedMetadataHeight
                        )
                    }
                }
                .frame(width: flowWidth, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func cardFlow(
        items: [WebcardFolderItem],
        availableWidth: CGFloat
    ) -> some View {
        if !items.isEmpty {
            let metrics = galleryMetrics(
                availableWidth: availableWidth,
                itemCount: items.count
            )
            if layoutMode == .masonry {
                MasonryLayout(columns: metrics.columns, spacing: spacing) {
                    ForEach(items) { item in
                        folderCard(
                            item,
                            width: metrics.cardWidth,
                            fixedMetadataHeight: nil
                        )
                    }
                }
                .frame(width: metrics.contentWidth, alignment: .leading)
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(metrics.cardWidth), spacing: spacing, alignment: .top),
                        count: metrics.columns
                    ),
                    alignment: .leading,
                    spacing: spacing
                ) {
                    let metadataHeights = gridMetadataHeights(
                        items: items,
                        width: metrics.cardWidth,
                        columns: metrics.columns
                    )
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        folderCard(
                            item,
                            width: metrics.cardWidth,
                            fixedMetadataHeight: metadataHeights[index]
                        )
                    }
                }
                .frame(width: metrics.contentWidth, alignment: .leading)
            }
        }
    }

    private func galleryMetrics(
        availableWidth: CGFloat,
        itemCount: Int
    ) -> WebcardGalleryMetrics {
        let maximumColumns = folderSettings.columnMode.columnCount(
            availableWidth: availableWidth,
            spacing: spacing,
            itemCount: itemCount
        )
        let columns = if layoutMode == .grid,
                         folderSettings.columnMode == .dynamic {
            WebcardGridRowMetrics.optimizedColumnCount(
                maximumColumns: maximumColumns,
                itemCount: itemCount
            )
        } else {
            maximumColumns
        }
        return WebcardGalleryMetrics(
            availableWidth: availableWidth,
            requestedColumns: columns,
            spacing: spacing
        )
    }

    @ViewBuilder
    private func galleryEntry(
        _ entry: WebcardGalleryEntry,
        width: CGFloat,
        fixedMetadataHeight: CGFloat?
    ) -> some View {
        Group {
            switch entry.content {
            case let .webcard(item):
                folderCard(
                    item,
                    width: width,
                    fixedMetadataHeight: fixedMetadataHeight
                )
            case let .continuation(node, path):
                continuationItem(node, path: path, width: width)
            }
        }
    }

    @ViewBuilder
    private func folderCard(
        _ item: WebcardFolderItem,
        width: CGFloat,
        fixedMetadataHeight: CGFloat?
    ) -> some View {
        switch item.content {
        case let .webcard(file):
            if let capture = file.currentCapture, let image = NSImage(data: capture.imageData) {
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
                usesInsecureHTTP: file.sourceURL?.scheme?.lowercased() == "http",
                masksImage: layoutMode.masksImage,
                titleLineLimit: layoutMode.titleLineLimit,
                descriptionLineLimit: layoutMode.descriptionLineLimit,
                urlLineLimit: layoutMode.urlLineLimit
            )
            .id(item.fileURL.standardizedFileURL)
            .contextMenu {
                Button("Open Webcard") {
                    let folderURL = browserModel.currentURL
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
        case let .webLocation(url):
            WebcardWebLocationCard(
                fileURL: item.fileURL,
                url: url,
                width: width,
                imageHeight: layoutMode.imageHeight(
                    width: width,
                    imageSize: NSSize(width: 16, height: 9)
                ),
                metadataHeight: fixedMetadataHeight ?? measuredMetadataHeight(
                    for: item,
                    width: width
                ),
                urlLineLimit: layoutMode.urlLineLimit
            )
        }
    }

    private func gridMetadataHeights(
        items: [WebcardFolderItem],
        width: CGFloat,
        columns: Int
    ) -> [CGFloat] {
        let measuredHeights = items.map {
            measuredMetadataHeight(for: $0, width: width)
        }
        return WebcardGridRowMetrics.equalizedHeights(
            measuredHeights,
            columns: columns
        )
    }

    private func measuredMetadataHeight(
        for item: WebcardFolderItem,
        width: CGFloat
    ) -> CGFloat {
        guard let capture = item.capture else {
            return 86
        }
        return SelectableMetadataView.height(
            for: capture,
            usesInsecureHTTP: item.file?.sourceURL?.scheme?.lowercased() == "http",
            width: width - WebcardLayoutMetrics.contentInset * 2,
            titleLineLimit: layoutMode.titleLineLimit,
            descriptionLineLimit: layoutMode.descriptionLineLimit,
            urlLineLimit: layoutMode.urlLineLimit
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { browserModel.errorMessage != nil },
            set: { if !$0 { browserModel.errorMessage = nil } }
        )
    }

    private var navigationSubtitle: String {
        guard let hierarchy = browserModel.hierarchy else {
            return ""
        }
        return countLabel(for: hierarchy)
    }

    private var layoutDebugID: String {
        let hierarchy = browserModel.hierarchy
        return [
            browserModel.currentURL.path,
            layoutMode.rawValue,
            folderSettings.presentationMode.rawValue,
            folderSettings.columnMode.rawValue,
            String(folderSettings.isDirectoryDrawerVisible),
            String(browserModel.isDiscovering),
            String(hierarchy?.discoveredWebcardCount ?? 0),
            String(hierarchy?.discoveredFolderCount ?? 0)
        ].joined(separator: "|")
    }

    private func logLayoutState(viewportSize: CGSize) {
        let availableWidth = max(1, viewportSize.width - 40)
        let breakpointColumns = folderSettings.columnMode.columnCount(
            availableWidth: availableWidth,
            spacing: spacing
        )
        Self.logger.debug(
            """
            directory=\(displayName(for: browserModel.currentURL), privacy: .public) \
            layout=\(layoutMode.rawValue, privacy: .public) \
            presentation=\(folderSettings.presentationMode.rawValue, privacy: .public) \
            columnMode=\(folderSettings.columnMode.rawValue, privacy: .public) \
            breakpointColumns=\(breakpointColumns) \
            viewport=\(viewportSize.width)x\(viewportSize.height) \
            visibleWebcards=\(allVisibleItems.count) \
            discovering=\(browserModel.isDiscovering)
            """
        )
    }

    private func countLabel(for node: WebcardDirectoryNode) -> String {
        WebcardFolderCountFormatter.label(for: node)
    }

    private var searchResultLabel: String {
        let count = allVisibleItems.count
        return "\(count) \(count == 1 ? "result" : "results")"
    }

    private func flattenWebcards(
        in node: WebcardDirectoryNode
    ) -> [WebcardFolderItem] {
        return node.directWebcards + node.children.flatMap { child in
            flattenWebcards(in: child)
        }
    }

    private func sorted(
        _ items: [WebcardFolderItem]
    ) -> [WebcardFolderItem] {
        if hasSearchQuery {
            return items
        }
        return items.sorted {
            $0.fileURL.lastPathComponent.localizedStandardCompare(
                $1.fileURL.lastPathComponent
            ) == .orderedAscending
        }
    }

    private func displayName(for url: URL) -> String {
        if url.path == "/" {
            return "/"
        }
        return url.lastPathComponent
    }

}

private struct WebcardFolderSidebar: View {
    let hierarchy: WebcardDirectoryNode?
    let selectedURL: URL
    let isLoading: Bool
    let navigate: (URL) -> Void

    @State private var expandedURLs: Set<URL> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Folders")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 8)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let hierarchy {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        sidebarButton(
                            title: "All Webcards",
                            systemImage: "rectangle.stack.fill",
                            node: hierarchy,
                            depth: 0
                        )

                        ForEach(hierarchy.children.filter(\.hasDiscoveredContent)) { child in
                            WebcardFolderTreeRow(
                                node: child,
                                depth: 0,
                                selectedURL: selectedURL,
                                expandedURLs: $expandedURLs,
                                navigate: navigate
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
                .onChange(of: hierarchy.children.map(\.id), initial: true) { _, childIDs in
                    expandedURLs.formUnion(childIDs)
                }
            } else {
                ContentUnavailableView(
                    "No Folders",
                    systemImage: "folder"
                )
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func sidebarButton(
        title: String,
        systemImage: String,
        node: WebcardDirectoryNode,
        depth: Int
    ) -> some View {
        Button {
            navigate(node.directoryURL)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(node.discoveredWebcardCount)\(node.isComplete ? "" : "+")")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.leading, CGFloat(depth) * 16)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                selectedURL == node.directoryURL
                    ? Color.accentColor.opacity(0.18)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(WebcardFolderCountFormatter.label(for: node))
    }
}

private struct WebcardFolderTreeRow: View {
    let node: WebcardDirectoryNode
    let depth: Int
    let selectedURL: URL
    @Binding var expandedURLs: Set<URL>
    let navigate: (URL) -> Void

    private var isExpanded: Bool {
        expandedURLs.contains(node.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Button {
                    if isExpanded {
                        expandedURLs.remove(node.id)
                    } else {
                        expandedURLs.insert(node.id)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(node.children.isEmpty ? 0 : 1)
                .disabled(node.children.isEmpty)

                Button {
                    navigate(node.directoryURL)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 16)
                        Text(node.directoryURL.lastPathComponent)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text("\(node.discoveredWebcardCount)\(node.isComplete ? "" : "+")")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background(
                        selectedURL == node.directoryURL
                            ? Color.accentColor.opacity(0.18)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(WebcardFolderCountFormatter.label(for: node))
            }
            .padding(.leading, CGFloat(depth) * 16)

            if isExpanded {
                ForEach(node.children.filter(\.hasDiscoveredContent)) { child in
                    WebcardFolderTreeRow(
                        node: child,
                        depth: depth + 1,
                        selectedURL: selectedURL,
                        expandedURLs: $expandedURLs,
                        navigate: navigate
                    )
                }
            }
        }
    }
}
