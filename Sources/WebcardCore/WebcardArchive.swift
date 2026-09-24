import CryptoKit
import Foundation
import UniformTypeIdentifiers
import ZIPFoundation

public enum WebcardArchive {
    public static let formatVersion = "1.0.0"
    public static let mediaType = "application/vnd.everything.webcard+zip"
    public static let maximumArchiveSize = 20 * 1024 * 1024
    public static let maximumExpandedSize = 64 * 1024 * 1024
    public static let maximumEntryCount = 1_024
    public static let maximumManifestSize = 64 * 1024
    public static let maximumImageSize = 15 * 1024 * 1024

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    private struct PublicRoot: Codable {
        let formatVersion: String
        let sourceURL: URL
        let currentCapture: String
        let captures: [String]
        let lastRefreshedAt: Date?
        let extensions: [String: WebcardJSONValue]?
        let additionalProperties: [String: WebcardJSONValue]

        private static let knownKeys = Set([
            "formatVersion",
            "sourceURL",
            "currentCapture",
            "captures",
            "lastRefreshedAt",
            "extensions"
        ])

        init(
            formatVersion: String,
            sourceURL: URL,
            currentCapture: String,
            captures: [String],
            lastRefreshedAt: Date?,
            extensions: [String: WebcardJSONValue]?,
            additionalProperties: [String: WebcardJSONValue]
        ) {
            self.formatVersion = formatVersion
            self.sourceURL = sourceURL
            self.currentCapture = currentCapture
            self.captures = captures
            self.lastRefreshedAt = lastRefreshedAt
            self.extensions = extensions
            self.additionalProperties = additionalProperties
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            formatVersion = try container.decode(String.self, forKey: key("formatVersion"))
            sourceURL = try container.decode(URL.self, forKey: key("sourceURL"))
            currentCapture = try container.decode(String.self, forKey: key("currentCapture"))
            captures = try container.decode([String].self, forKey: key("captures"))
            lastRefreshedAt = try container.decodeIfPresent(Date.self, forKey: key("lastRefreshedAt"))
            extensions = try container.decodeIfPresent(
                [String: WebcardJSONValue].self,
                forKey: key("extensions")
            )
            additionalProperties = try container.allKeys.reduce(into: [:]) { result, codingKey in
                guard !Self.knownKeys.contains(codingKey.stringValue) else {
                    return
                }
                result[codingKey.stringValue] = try container.decode(
                    WebcardJSONValue.self,
                    forKey: codingKey
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            try container.encode(formatVersion, forKey: key("formatVersion"))
            try container.encode(sourceURL, forKey: key("sourceURL"))
            try container.encode(currentCapture, forKey: key("currentCapture"))
            try container.encode(captures, forKey: key("captures"))
            try container.encodeIfPresent(lastRefreshedAt, forKey: key("lastRefreshedAt"))
            try container.encodeIfPresent(extensions, forKey: key("extensions"))
            for (name, value) in additionalProperties where !Self.knownKeys.contains(name) {
                try container.encode(value, forKey: key(name))
            }
        }
    }

    private struct AssetReference: Codable {
        let path: String
        let mediaType: String
        let sha256: String
        let byteLength: Int
    }

    private struct PublicCapture: Codable {
        let id: String
        let canonicalURL: URL
        let title: String
        let description: String
        let siteName: String
        let capturedAt: Date
        let image: AssetReference
        let icon: AssetReference?
        let sourceMetadata: WebcardSocialMetadata?
        let extensions: [String: WebcardJSONValue]?
        let additionalProperties: [String: WebcardJSONValue]

        private static let knownKeys = Set([
            "id",
            "canonicalURL",
            "title",
            "description",
            "siteName",
            "capturedAt",
            "image",
            "icon",
            "sourceMetadata",
            "extensions"
        ])

        init(
            id: String,
            canonicalURL: URL,
            title: String,
            description: String,
            siteName: String,
            capturedAt: Date,
            image: AssetReference,
            icon: AssetReference?,
            sourceMetadata: WebcardSocialMetadata?,
            extensions: [String: WebcardJSONValue]?,
            additionalProperties: [String: WebcardJSONValue]
        ) {
            self.id = id
            self.canonicalURL = canonicalURL
            self.title = title
            self.description = description
            self.siteName = siteName
            self.capturedAt = capturedAt
            self.image = image
            self.icon = icon
            self.sourceMetadata = sourceMetadata
            self.extensions = extensions
            self.additionalProperties = additionalProperties
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            id = try container.decode(String.self, forKey: key("id"))
            canonicalURL = try container.decode(URL.self, forKey: key("canonicalURL"))
            title = try container.decode(String.self, forKey: key("title"))
            description = try container.decode(String.self, forKey: key("description"))
            siteName = try container.decode(String.self, forKey: key("siteName"))
            capturedAt = try container.decode(Date.self, forKey: key("capturedAt"))
            image = try container.decode(AssetReference.self, forKey: key("image"))
            icon = try container.decodeIfPresent(AssetReference.self, forKey: key("icon"))
            sourceMetadata = try container.decodeIfPresent(
                WebcardSocialMetadata.self,
                forKey: key("sourceMetadata")
            )
            extensions = try container.decodeIfPresent(
                [String: WebcardJSONValue].self,
                forKey: key("extensions")
            )
            additionalProperties = try container.allKeys.reduce(into: [:]) { result, codingKey in
                guard !Self.knownKeys.contains(codingKey.stringValue) else {
                    return
                }
                result[codingKey.stringValue] = try container.decode(
                    WebcardJSONValue.self,
                    forKey: codingKey
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            try container.encode(id, forKey: key("id"))
            try container.encode(canonicalURL, forKey: key("canonicalURL"))
            try container.encode(title, forKey: key("title"))
            try container.encode(description, forKey: key("description"))
            try container.encode(siteName, forKey: key("siteName"))
            try container.encode(capturedAt, forKey: key("capturedAt"))
            try container.encode(image, forKey: key("image"))
            try container.encodeIfPresent(icon, forKey: key("icon"))
            try container.encodeIfPresent(sourceMetadata, forKey: key("sourceMetadata"))
            try container.encodeIfPresent(extensions, forKey: key("extensions"))
            for (name, value) in additionalProperties where !Self.knownKeys.contains(name) {
                try container.encode(value, forKey: key(name))
            }
        }
    }

    public static func read(_ data: Data) throws -> WebcardFile {
        guard data.count <= maximumArchiveSize else {
            throw WebcardError.resourceTooLarge
        }
        let archive: Archive
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw WebcardError.invalidArchive("The webcard is not a valid ZIP archive.")
        }
        try validateEntryNames(in: archive)
        guard archive["webcard.json"] != nil || archive["mimetype"] != nil else {
            throw WebcardError.invalidArchive(
                "This legacy prototype webcard is not supported. Webcard Format 1.0.0 is required."
            )
        }
        return try readPublicFormat(archive: archive)
    }

    public static func write(_ file: WebcardFile) throws -> Data {
        guard let sourceURL = file.sourceURL, !file.captures.isEmpty else {
            throw WebcardError.invalidArchive("A webcard must contain a URL and at least one capture.")
        }
        let selectedCaptureID = file.currentCaptureID ?? file.captures.last!.id
        guard file.captures.contains(where: { $0.id == selectedCaptureID }) else {
            throw WebcardError.missingCapture
        }
        let encoder = makeEncoder()
        var entries: [(path: String, data: Data)] = [
            ("mimetype", Data(mediaType.utf8))
        ]

        var usedCaptureIDs: [String: Int] = [:]
        let orderedCaptures = file.captures.enumerated().sorted {
            if $0.element.capturedAt == $1.element.capturedAt {
                return $0.offset < $1.offset
            }
            return $0.element.capturedAt < $1.element.capturedAt
        }.map(\.element)
        let publicCaptures = orderedCaptures.map { capture -> (capture: WebcardCapture, id: String, path: String) in
            let baseID = publicCaptureID(for: capture.capturedAt)
            let occurrence = usedCaptureIDs[baseID, default: 0]
            usedCaptureIDs[baseID] = occurrence + 1
            let id = occurrence == 0 ? baseID : "\(baseID)-\(occurrence + 1)"
            return (capture, id, "captures/\(id).json")
        }
        guard let currentCapturePath = publicCaptures.first(where: { $0.capture.id == selectedCaptureID })?.path else {
            throw WebcardError.missingCapture
        }
        let root = PublicRoot(
            formatVersion: formatVersion,
            sourceURL: sourceURL,
            currentCapture: currentCapturePath,
            captures: publicCaptures.map(\.path),
            lastRefreshedAt: file.lastRefreshedAt ?? file.currentCapture?.capturedAt,
            extensions: file.extensions.isEmpty ? nil : file.extensions,
            additionalProperties: file.additionalProperties
        )
        entries.append(("webcard.json", try encoder.encode(root)))
        var imagesBySHA256: [String: Data] = [:]
        for item in publicCaptures {
            let capture = item.capture
            try validateCapture(capture)
            let sharedImagePath = "assets/sha256/\(capture.imageSHA256).webp"
            let image = AssetReference(
                path: sharedImagePath,
                mediaType: "image/webp",
                sha256: capture.imageSHA256,
                byteLength: capture.imageData.count
            )
            let icon = capture.iconSHA256.flatMap { sha256 in
                capture.iconData.map {
                    AssetReference(
                        path: "assets/sha256/\(sha256).webp",
                        mediaType: "image/webp",
                        sha256: sha256,
                        byteLength: $0.count
                    )
                }
            }
            let manifest = PublicCapture(
                id: item.id,
                canonicalURL: capture.canonicalURL,
                title: capture.title,
                description: capture.summary,
                siteName: capture.siteName,
                capturedAt: capture.capturedAt,
                image: image,
                icon: icon,
                sourceMetadata: capture.socialMetadata.isEmpty ? nil : capture.socialMetadata,
                extensions: capture.extensions.isEmpty ? nil : capture.extensions,
                additionalProperties: capture.additionalProperties
            )
            entries.append((item.path, try encoder.encode(manifest)))
            if let existing = imagesBySHA256[capture.imageSHA256], existing != capture.imageData {
                throw WebcardError.invalidArchive("Two different images have the same SHA256.")
            }
            imagesBySHA256[capture.imageSHA256] = capture.imageData
            if let iconSHA256 = capture.iconSHA256, let iconData = capture.iconData {
                if let existing = imagesBySHA256[iconSHA256], existing != iconData {
                    throw WebcardError.invalidArchive("Two different images have the same SHA256.")
                }
                imagesBySHA256[iconSHA256] = iconData
            }
        }
        for (sha256, imageData) in imagesBySHA256.sorted(by: { $0.key < $1.key }) {
            entries.append(("assets/sha256/\(sha256).webp", imageData))
        }
        for (path, entryData) in file.extensionEntries.sorted(by: { $0.key < $1.key }) {
            guard isExtensionPath(path) else {
                throw WebcardError.invalidArchive("Extension entries must be under extensions/ or signatures/.")
            }
            entries.append((path, entryData))
        }
        let data = try createStoredArchive(entries: entries)
        guard data.count <= maximumArchiveSize else {
            throw WebcardError.resourceTooLarge
        }
        return data
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func captureID(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    public static func publicCaptureID(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return formatter.string(from: date)
    }

    private static func readPublicFormat(archive: Archive) throws -> WebcardFile {
        let mimetype = try extract("mimetype", from: archive, limit: 128)
        guard mimetype == Data(mediaType.utf8) else {
            throw WebcardError.invalidArchive("The webcard mimetype entry is invalid.")
        }
        guard archive.first(where: { _ in true })?.path == "mimetype",
              archive["mimetype"]?.isCompressed == false else {
            throw WebcardError.invalidArchive("The mimetype entry must be first and uncompressed.")
        }

        let decoder = makeDecoder()
        let rootData = try extract("webcard.json", from: archive, limit: maximumManifestSize)
        let root = try decoder.decode(PublicRoot.self, from: rootData)
        guard root.formatVersion == formatVersion else {
            throw WebcardError.invalidArchive("Webcard format \(root.formatVersion) is not supported.")
        }
        try validateRemoteURL(root.sourceURL)
        guard !root.captures.isEmpty,
              Set(root.captures).count == root.captures.count,
              root.captures.contains(root.currentCapture) else {
            throw WebcardError.invalidArchive("The capture list is invalid.")
        }

        var expectedEntries = Set(["mimetype", "webcard.json"])
        let captures = try root.captures.map { path in
            guard let id = publicCaptureID(fromPath: path) else {
                throw WebcardError.invalidArchive("The webcard contains an invalid capture path.")
            }
            expectedEntries.insert(path)
            let captureData = try extract(path, from: archive, limit: maximumManifestSize)
            let manifest = try decoder.decode(PublicCapture.self, from: captureData)
            guard manifest.id == id,
                  publicCaptureID(for: manifest.capturedAt) == id.components(separatedBy: "-").first else {
                throw WebcardError.invalidArchive("The capture identifier and timestamp do not match.")
            }
            try validateRemoteURL(manifest.canonicalURL)
            let imageData = try readAsset(manifest.image, archive: archive, expectedEntries: &expectedEntries)
            var iconData: Data?
            if let icon = manifest.icon {
                iconData = try readAsset(icon, archive: archive, expectedEntries: &expectedEntries)
            }
            let capture = WebcardCapture(
                id: manifest.id,
                canonicalURL: manifest.canonicalURL,
                title: normalized(manifest.title, maximum: 500),
                summary: normalized(manifest.description, maximum: 2_000),
                siteName: normalized(manifest.siteName, maximum: 300),
                imagePath: manifest.image.path,
                imageSHA256: manifest.image.sha256,
                capturedAt: manifest.capturedAt,
                imageData: imageData,
                iconPath: manifest.icon?.path,
                iconSHA256: manifest.icon?.sha256,
                iconData: iconData,
                socialMetadata: manifest.sourceMetadata ?? WebcardSocialMetadata(),
                extensions: manifest.extensions ?? [:],
                additionalProperties: manifest.additionalProperties
            )
            try validateCapture(capture, allowPublicAssetPath: true)
            return capture
        }
        guard zip(captures, captures.dropFirst()).allSatisfy({
            $0.0.capturedAt <= $0.1.capturedAt
        }) else {
            throw WebcardError.invalidArchive("Captures must be ordered chronologically.")
        }

        var extensionEntries: [String: Data] = [:]
        for entry in archive where isExtensionPath(entry.path) {
            extensionEntries[entry.path] = try extract(entry.path, from: archive, limit: maximumArchiveSize)
            expectedEntries.insert(entry.path)
        }
        guard Set(archive.map(\.path)) == expectedEntries else {
            throw WebcardError.invalidArchive("The webcard contains unexpected archive entries.")
        }
        let currentID = publicCaptureID(fromPath: root.currentCapture)
        return WebcardFile(
            sourceURL: root.sourceURL,
            captures: captures,
            currentCaptureID: currentID,
            lastRefreshedAt: root.lastRefreshedAt,
            extensions: root.extensions ?? [:],
            additionalProperties: root.additionalProperties,
            extensionEntries: extensionEntries
        )
    }

    private static func readAsset(
        _ reference: AssetReference,
        archive: Archive,
        expectedEntries: inout Set<String>
    ) throws -> Data {
        guard reference.mediaType == "image/webp",
              reference.path == "assets/sha256/\(reference.sha256).webp",
              reference.sha256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
              reference.byteLength >= 0,
              reference.byteLength <= maximumImageSize else {
            throw WebcardError.invalidArchive("The asset reference is invalid.")
        }
        expectedEntries.insert(reference.path)
        let data = try extract(reference.path, from: archive, limit: maximumImageSize)
        guard data.count == reference.byteLength,
              sha256(data) == reference.sha256 else {
            throw WebcardError.invalidArchive("The asset integrity check failed.")
        }
        return data
    }

    private static func validateCapture(
        _ capture: WebcardCapture,
        allowPublicAssetPath: Bool = false
    ) throws {
        guard isSafeCaptureID(capture.id),
              (allowPublicAssetPath
                || capture.imagePath == "card.webp"
                || isSharedImagePath(capture.imagePath, sha256: capture.imageSHA256)
                || isPublicAssetPath(capture.imagePath, sha256: capture.imageSHA256)),
              capture.imageData.count <= maximumImageSize,
              capture.imageSHA256 == sha256(capture.imageData),
              capture.title.count <= 500,
              capture.summary.count <= 2_000,
              capture.siteName.count <= 300 else {
            throw WebcardError.invalidArchive("The webcard capture is invalid.")
        }
        if let iconSHA256 = capture.iconSHA256, let iconData = capture.iconData {
            guard allowPublicAssetPath
                    || capture.iconPath == nil
                    || isSharedImagePath(capture.iconPath!, sha256: iconSHA256)
                    || isPublicAssetPath(capture.iconPath!, sha256: iconSHA256),
                  iconData.count <= maximumImageSize,
                  iconSHA256 == sha256(iconData) else {
                throw WebcardError.invalidArchive("The webcard capture icon is invalid.")
            }
        } else if capture.iconPath != nil || capture.iconSHA256 != nil || capture.iconData != nil {
            throw WebcardError.invalidArchive("The webcard capture icon metadata is incomplete.")
        }
        try validateRemoteURL(capture.canonicalURL)
    }

    private static func isSharedImagePath(_ path: String, sha256: String) -> Bool {
        let normalizedSHA256 = sha256.lowercased()
        guard normalizedSHA256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
            return false
        }
        return path == "images/\(normalizedSHA256).webp"
    }

    private static func isPublicAssetPath(_ path: String, sha256: String) -> Bool {
        let normalizedSHA256 = sha256.lowercased()
        guard normalizedSHA256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
            return false
        }
        return path == "assets/sha256/\(normalizedSHA256).webp"
    }

    private static func validateRemoteURL(_ url: URL) throws {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil,
              url.user == nil,
              url.password == nil else {
            throw WebcardError.invalidURL
        }
    }

    private static func isSafeCaptureID(_ id: String) -> Bool {
        !id.isEmpty
            && id.count <= 80
            && id.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
            && id != "."
            && id != ".."
    }

    private static func publicCaptureID(fromPath path: String) -> String? {
        guard path.range(
            of: #"^captures/([0-9]{8}T[0-9]{6}\.[0-9]{3}Z(?:-[0-9]+)?)\.json$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }
        return String(path.dropFirst("captures/".count).dropLast(".json".count))
    }

    private static func isExtensionPath(_ path: String) -> Bool {
        path.range(
            of: #"^(extensions/[^/]+/.+|signatures/.+)$"#,
            options: .regularExpression
        ) != nil
    }

    private static func validateEntryNames(in archive: Archive) throws {
        let entries = Array(archive)
        let paths = entries.map(\.path)
        guard entries.count <= maximumEntryCount else {
            throw WebcardError.resourceTooLarge
        }
        guard Set(paths).count == paths.count else {
            throw WebcardError.invalidArchive("The webcard contains duplicate archive entries.")
        }
        var expandedSize: UInt64 = 0
        for entry in entries {
            let path = entry.path
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard entry.type == .file,
                  !path.isEmpty,
                  !path.hasPrefix("/"),
                  !path.contains("\\"),
                  !path.contains("\0"),
                  !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
                throw WebcardError.invalidArchive("The webcard contains an unsafe archive path.")
            }
            expandedSize += entry.uncompressedSize
            guard expandedSize <= UInt64(maximumExpandedSize) else {
                throw WebcardError.resourceTooLarge
            }
        }
    }

    private static func normalized(_ value: String, maximum: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximum))
    }

    private static func extract(_ path: String, from archive: Archive, limit: Int) throws -> Data {
        guard let entry = archive[path], entry.uncompressedSize <= UInt32(limit) else {
            throw WebcardError.invalidArchive("The webcard is missing \(path) or it is too large.")
        }
        var output = Data()
        _ = try archive.extract(entry, bufferSize: 32 * 1024) { chunk in
            output.append(chunk)
            if output.count > limit {
                throw WebcardError.resourceTooLarge
            }
        }
        return output
    }

    private static func createStoredArchive(entries: [(path: String, data: Data)]) throws -> Data {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("webcard-\(UUID().uuidString)", isDirectory: true)
        let archiveURL = temporaryDirectory.appendingPathComponent("archive.zip")
        defer {
            try? fileManager.removeItem(at: temporaryDirectory)
        }

        do {
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            for entry in entries {
                let fileURL = temporaryDirectory.appendingPathComponent(entry.path)
                try fileManager.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try entry.data.write(to: fileURL, options: .atomic)
            }
            try runCommand(
                executablePath: "/usr/bin/touch",
                arguments: ["-t", "198001010000"] + entries.map(\.path),
                currentDirectoryURL: temporaryDirectory,
                failureMessage: "The webcard timestamps could not be normalized."
            )
            try runCommand(
                executablePath: "/usr/bin/zip",
                arguments: ["-q", "-0", archiveURL.path, "mimetype"],
                currentDirectoryURL: temporaryDirectory,
                failureMessage: "The system ZIP utility could not create the webcard."
            )
            let remainingPaths = entries.map(\.path)
                .filter { $0 != "mimetype" }
                .sorted()
            if !remainingPaths.isEmpty {
                try runCommand(
                    executablePath: "/usr/bin/zip",
                    arguments: ["-q", "-0", archiveURL.path] + remainingPaths,
                    currentDirectoryURL: temporaryDirectory,
                    failureMessage: "The system ZIP utility could not create the webcard."
                )
            }
            return try Data(contentsOf: archiveURL)
        } catch let error as WebcardError {
            throw error
        } catch {
            throw WebcardError.invalidArchive("The webcard archive could not be created.")
        }
    }

    private static func runCommand(
        executablePath: String,
        arguments: [String],
        currentDirectoryURL: URL,
        failureMessage: String
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw WebcardError.invalidArchive(failureMessage)
        }
        guard process.terminationStatus == 0 else {
            throw WebcardError.invalidArchive(failureMessage)
        }
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }

            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Expected an ISO 8601 date."
            )
        }
        return decoder
    }

    private static func key(_ value: String) -> DynamicCodingKey {
        DynamicCodingKey(stringValue: value)!
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

public extension UTType {
    static let webcard = UTType(exportedAs: "com.reggi.webcard", conformingTo: .zip)
}
