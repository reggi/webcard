import Foundation
import CoreServices
import WebcardCore

final class WebcardDirectoryMonitor {
    private final class CallbackBox {
        let handler: () -> Void

        init(handler: @escaping () -> Void) {
            self.handler = handler
        }
    }

    private let callbackBox: CallbackBox
    private var stream: FSEventStreamRef?

    init(directoryURL: URL, handler: @escaping () -> Void) {
        callbackBox = CallbackBox(handler: handler)

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callbackBox).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        stream = FSEventStreamCreate(
            nil,
            { _, callbackInfo, _, _, _, _ in
                guard let callbackInfo else {
                    return
                }
                Unmanaged<CallbackBox>
                    .fromOpaque(callbackInfo)
                    .takeUnretainedValue()
                    .handler()
            },
            &context,
            [directoryURL.standardizedFileURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagWatchRoot
            )
        )

        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            guard FSEventStreamStart(stream) else {
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
                return
            }
        }
    }

    deinit {
        guard let stream else {
            return
        }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
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

struct WebcardDiscoveryLimits: Sendable, Equatable {
    static let standard = WebcardDiscoveryLimits(
        maximumDepth: 5,
        maximumDirectories: 1_000,
        maximumWebcards: 5_000,
        maximumEntriesPerDirectory: 20_000,
        followsSymbolicLinks: false,
        crossesVolumes: false,
        scansPackages: false,
        scansHiddenDirectories: false
    )

    let maximumDepth: Int
    let maximumDirectories: Int
    let maximumWebcards: Int
    let maximumEntriesPerDirectory: Int
    let followsSymbolicLinks: Bool
    let crossesVolumes: Bool
    let scansPackages: Bool
    let scansHiddenDirectories: Bool
}

enum WebcardDiscoveryState: Sendable, Equatable {
    case complete
    case unknown
    case incomplete
}

struct WebcardDirectoryNode: Identifiable, Sendable {
    let directoryURL: URL
    let directWebcards: [WebcardFolderItem]
    let children: [WebcardDirectoryNode]
    let discoveryState: WebcardDiscoveryState

    var id: URL {
        directoryURL
    }

    var discoveredWebcardCount: Int {
        directWebcards.count + children.reduce(0) { $0 + $1.discoveredWebcardCount }
    }

    var discoveredFolderCount: Int {
        children.reduce(0) {
            $0 + ($1.discoveredWebcardCount > 0 ? 1 : 0) + $1.discoveredFolderCount
        }
    }

    var isComplete: Bool {
        discoveryState == .complete && children.allSatisfy(\.isComplete)
    }

    var hasDiscoveredContent: Bool {
        discoveredWebcardCount > 0
    }

    func filtering(query: String) -> WebcardDirectoryNode? {
        guard !query.isEmpty else {
            return self
        }

        let matchingWebcards = directWebcards.filter { item in
            guard let capture = item.capture else {
                return false
            }
            return WebcardFuzzySearch.score(
                query: query,
                in: [
                    item.fileURL.deletingPathExtension().lastPathComponent,
                    capture.title,
                    capture.summary,
                    capture.siteName,
                    capture.canonicalURL.absoluteString
                ] + capture.socialMetadata.searchableValues
            ) != nil
        }
        let matchingChildren = children.compactMap { $0.filtering(query: query) }
        guard !matchingWebcards.isEmpty || !matchingChildren.isEmpty else {
            return nil
        }
        return WebcardDirectoryNode(
            directoryURL: directoryURL,
            directWebcards: matchingWebcards,
            children: matchingChildren,
            discoveryState: discoveryState
        )
    }

    func replacingSubtree(
        with replacement: WebcardDirectoryNode
    ) -> WebcardDirectoryNode {
        if directoryURL == replacement.directoryURL {
            return replacement
        }
        return WebcardDirectoryNode(
            directoryURL: directoryURL,
            directWebcards: directWebcards,
            children: children.map { $0.replacingSubtree(with: replacement) },
            discoveryState: discoveryState
        )
    }
}

struct WebcardDirectorySnapshot: Sendable {
    let hierarchy: WebcardDirectoryNode
    let errors: [String]
}

actor WebcardDiscoveryCache {
    private struct Entry {
        let snapshot: WebcardDirectorySnapshot
        let directoryModificationDate: Date?
        let cachedAt: Date
    }

    private var entries: [URL: Entry] = [:]
    private let maximumAge: TimeInterval = 30

    func snapshot(
        for url: URL,
        directoryModificationDate: Date?
    ) -> WebcardDirectorySnapshot? {
        let key = url.standardizedFileURL
        guard let entry = entries[key],
              Date().timeIntervalSince(entry.cachedAt) <= maximumAge,
              entry.directoryModificationDate == directoryModificationDate else {
            entries[key] = nil
            return nil
        }
        return entry.snapshot
    }

    func store(
        _ snapshot: WebcardDirectorySnapshot,
        for url: URL,
        directoryModificationDate: Date?
    ) {
        entries[url.standardizedFileURL] = Entry(
            snapshot: snapshot,
            directoryModificationDate: directoryModificationDate,
            cachedAt: Date()
        )
    }

    func invalidate(_ url: URL) {
        entries[url.standardizedFileURL] = nil
    }
}

struct DirectoryBrowser: Sendable {
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .isHiddenKey,
        .isPackageKey,
        .volumeIdentifierKey,
        .contentModificationDateKey
    ]

    let limits: WebcardDiscoveryLimits
    let cache: WebcardDiscoveryCache

    init(
        limits: WebcardDiscoveryLimits = .standard,
        cache: WebcardDiscoveryCache = WebcardDiscoveryCache()
    ) {
        self.limits = limits
        self.cache = cache
    }

    func immediateContents(at directoryURL: URL) async throws -> WebcardDirectorySnapshot {
        try await runScan {
            try Self.scan(directoryURL, limits: limits, recursively: false)
        }
    }

    func discover(at directoryURL: URL) async throws -> WebcardDirectorySnapshot {
        let standardizedURL = directoryURL.standardizedFileURL
        let modificationDate = try? standardizedURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
        if let cached = await cache.snapshot(
            for: standardizedURL,
            directoryModificationDate: modificationDate
        ) {
            return cached
        }
        let snapshot = try await runScan {
            try Self.scan(standardizedURL, limits: limits, recursively: true)
        }
        await cache.store(
            snapshot,
            for: standardizedURL,
            directoryModificationDate: modificationDate
        )
        return snapshot
    }

    func invalidate(_ directoryURL: URL) async {
        await cache.invalidate(directoryURL)
    }

    private func runScan(
        _ operation: @escaping @Sendable () throws -> WebcardDirectorySnapshot
    ) async throws -> WebcardDirectorySnapshot {
        let task = Task.detached(priority: .userInitiated, operation: operation)
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func scan(
        _ rootURL: URL,
        limits: WebcardDiscoveryLimits,
        recursively: Bool
    ) throws -> WebcardDirectorySnapshot {
        let standardizedRoot = rootURL.standardizedFileURL
        let rootValues = try standardizedRoot.resourceValues(forKeys: resourceKeys)
        guard rootValues.isDirectory == true else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        let root = MutableDirectoryNode(url: standardizedRoot)
        let rootVolume = rootValues.volumeIdentifier.map { String(describing: $0) }
        var queue: [(node: MutableDirectoryNode, depth: Int)] = [(root, 0)]
        var inspectedDirectories = 0
        var discoveredWebcards = 0
        var errors: [String] = []

        while !queue.isEmpty {
            try Task.checkCancellation()
            let current = queue.removeFirst()

            guard inspectedDirectories < limits.maximumDirectories else {
                root.markIncomplete()
                break
            }
            inspectedDirectories += 1

            let enumeration = enumerateDirectory(
                current.node.url,
                limits: limits,
                rootVolume: rootVolume
            )
            if enumeration.wasTruncated {
                current.node.markIncomplete()
            }
            if !enumeration.errors.isEmpty {
                current.node.markIncomplete()
            }
            errors.append(contentsOf: enumeration.errors)

            for entry in enumeration.entries {
                try Task.checkCancellation()
                switch entry {
                case let .webcard(url):
                    guard discoveredWebcards < limits.maximumWebcards else {
                        current.node.markIncomplete()
                        root.markIncomplete()
                        continue
                    }
                    do {
                        current.node.webcards.append(
                            WebcardFolderItem(
                                fileURL: url,
                                file: try WebcardArchive.read(
                                    Data(contentsOf: url, options: .mappedIfSafe)
                                )
                            )
                        )
                        discoveredWebcards += 1
                    } catch {
                        current.node.markIncomplete()
                        errors.append("\(url.path): \(error.localizedDescription)")
                    }

                case let .directory(url):
                    guard recursively else {
                        current.node.markIncomplete()
                        continue
                    }
                    let child = MutableDirectoryNode(url: url)
                    current.node.children.append(child)
                    if current.depth < limits.maximumDepth,
                       inspectedDirectories + queue.count < limits.maximumDirectories {
                        queue.append((child, current.depth + 1))
                    } else {
                        child.discoveryState = .unknown
                        current.node.markIncomplete()
                        root.markIncomplete()
                    }
                }
            }
        }

        return WebcardDirectorySnapshot(
            hierarchy: root.freeze(),
            errors: errors
        )
    }

    private static func enumerateDirectory(
        _ directoryURL: URL,
        limits: WebcardDiscoveryLimits,
        rootVolume: String?
    ) -> DirectoryEnumeration {
        let options: FileManager.DirectoryEnumerationOptions = {
            var result: FileManager.DirectoryEnumerationOptions = [
                .skipsSubdirectoryDescendants
            ]
            if !limits.scansHiddenDirectories {
                result.insert(.skipsHiddenFiles)
            }
            if !limits.scansPackages {
                result.insert(.skipsPackageDescendants)
            }
            return result
        }()

        var errors: [String] = []
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options,
            errorHandler: { url, error in
                errors.append("\(url.path): \(error.localizedDescription)")
                return true
            }
        ) else {
            return DirectoryEnumeration(
                entries: [],
                errors: ["\(directoryURL.path): Directory could not be enumerated."],
                wasTruncated: true
            )
        }

        var entries: [DirectoryEntry] = []
        var inspectedEntries = 0
        var wasTruncated = false

        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled {
                wasTruncated = true
                break
            }
            guard inspectedEntries < limits.maximumEntriesPerDirectory else {
                wasTruncated = true
                break
            }
            inspectedEntries += 1

            do {
                let values = try url.resourceValues(forKeys: resourceKeys)
                if values.isSymbolicLink == true && !limits.followsSymbolicLinks {
                    continue
                }
                if values.isHidden == true && !limits.scansHiddenDirectories {
                    continue
                }
                if values.isPackage == true && !limits.scansPackages {
                    continue
                }
                if values.isDirectory == true {
                    let volume = values.volumeIdentifier.map { String(describing: $0) }
                    if !limits.crossesVolumes, volume != rootVolume {
                        continue
                    }
                    entries.append(.directory(url.standardizedFileURL))
                } else if values.isRegularFile == true,
                          url.pathExtension.lowercased() == "webcard" {
                    entries.append(.webcard(url.standardizedFileURL))
                }
            } catch {
                errors.append("\(url.path): \(error.localizedDescription)")
            }
        }

        entries.sort { lhs, rhs in
            lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent)
                == .orderedAscending
        }
        return DirectoryEnumeration(
            entries: entries,
            errors: errors,
            wasTruncated: wasTruncated
        )
    }
}

private enum DirectoryEntry {
    case directory(URL)
    case webcard(URL)

    var url: URL {
        switch self {
        case let .directory(url), let .webcard(url):
            url
        }
    }
}

private struct DirectoryEnumeration {
    let entries: [DirectoryEntry]
    let errors: [String]
    let wasTruncated: Bool
}

private final class MutableDirectoryNode {
    let url: URL
    var webcards: [WebcardFolderItem] = []
    var children: [MutableDirectoryNode] = []
    var discoveryState: WebcardDiscoveryState = .complete

    init(url: URL) {
        self.url = url
    }

    func markIncomplete() {
        if discoveryState == .complete {
            discoveryState = .incomplete
        }
    }

    func freeze() -> WebcardDirectoryNode {
        WebcardDirectoryNode(
            directoryURL: url,
            directWebcards: webcards,
            children: children
                .map { $0.freeze() }
                .filter { $0.hasDiscoveredContent || $0.discoveryState != .complete },
            discoveryState: discoveryState
        )
    }
}
