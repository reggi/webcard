import CryptoKit
import Foundation
import UniformTypeIdentifiers
import ZIPFoundation

public enum WebcardWebloc {
    public static func suggestedFilename(for url: URL) -> String {
        let readableComponents = [url.host()].compactMap { $0 }
            + url.pathComponents.filter { $0 != "/" }.suffix(3)
        let readableIdentifier = readableComponents.joined(separator: "-")
        let slug = sanitizedFilenameComponent(readableIdentifier) ?? "failed-import"
        let hash = WebcardArchive.sha256(Data(url.absoluteString.utf8)).prefix(10)
        return "\(slug)-\(hash).webloc"
    }

    public static func read(_ data: Data) throws -> URL {
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        guard let dictionary = propertyList as? [String: Any],
              let value = dictionary["URL"] as? String,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw WebcardError.invalidURL
        }
        return url
    }

    public static func write(_ url: URL) throws -> Data {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw WebcardError.invalidURL
        }
        return try PropertyListSerialization.data(
            fromPropertyList: ["URL": url.absoluteString],
            format: .xml,
            options: 0
        )
    }

    private static func sanitizedFilenameComponent(_ value: String) -> String? {
        let folded = value
            .folding(
                options: [.diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
        var slug = ""
        var needsSeparator = false

        for character in folded {
            if character.isLetter || character.isNumber {
                if needsSeparator && !slug.isEmpty {
                    slug.append("-")
                }
                slug.append(character)
                needsSeparator = false
            } else {
                needsSeparator = true
            }
        }

        guard !slug.isEmpty else {
            return nil
        }
        return String(slug.prefix(100)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

public enum WebcardArchive {
    public static let maximumArchiveSize = 20 * 1024 * 1024
    public static let maximumManifestSize = 64 * 1024
    public static let maximumImageSize = 15 * 1024 * 1024

    private struct VersionProbe: Decodable {
        let version: Int
    }

    private struct VersionOneManifest: Codable {
        let version: Int
        let url: URL
        let canonicalUrl: URL
        let title: String
        let description: String
        let siteName: String
        let image: String
        let savedAt: Date
    }

    private struct RootManifest: Codable {
        let version: Int
        let url: URL
        let currentCapture: String
        let captures: [String]
        let lastRefreshedAt: Date?
    }

    private struct CaptureManifest: Codable {
        let canonicalUrl: URL
        let title: String
        let description: String
        let siteName: String
        let image: String
        let imageSHA256: String
        let capturedAt: Date
        let icon: String?
        let iconSHA256: String?
        let socialMetadata: WebcardSocialMetadata?
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
        let rootData = try extract("manifest.json", from: archive, limit: maximumManifestSize)
        let decoder = makeDecoder()
        let version = try decoder.decode(VersionProbe.self, from: rootData).version
        switch version {
        case 1:
            return try readVersionOne(rootData: rootData, archive: archive, decoder: decoder)
        case 2:
            return try readVersionTwo(rootData: rootData, archive: archive, decoder: decoder)
        default:
            throw WebcardError.unsupportedVersion(version)
        }
    }

    public static func write(_ file: WebcardFile) throws -> Data {
        guard let sourceURL = file.sourceURL, !file.captures.isEmpty else {
            throw WebcardError.invalidArchive("A webcard must contain a URL and at least one capture.")
        }
        let currentCaptureID = file.currentCaptureID ?? file.captures.last!.id
        guard file.captures.contains(where: { $0.id == currentCaptureID }) else {
            throw WebcardError.missingCapture
        }
        let archive: Archive
        do {
            archive = try Archive(accessMode: .create)
        } catch {
            throw WebcardError.invalidArchive("The webcard archive could not be created.")
        }
        let encoder = makeEncoder()
        let root = RootManifest(
            version: 2,
            url: sourceURL,
            currentCapture: currentCaptureID,
            captures: file.captures.map(\.id),
            lastRefreshedAt: file.lastRefreshedAt ?? file.currentCapture?.capturedAt
        )
        try add(encoder.encode(root), at: "manifest.json", to: archive)
        var imagesBySHA256: [String: Data] = [:]
        for capture in file.captures {
            try validateCapture(capture)
            let base = "captures/\(capture.id)"
            let sharedImagePath = "images/\(capture.imageSHA256).webp"
            let sharedIconPath = capture.iconSHA256.map { "images/\($0).webp" }
            let manifest = CaptureManifest(
                canonicalUrl: capture.canonicalURL,
                title: capture.title,
                description: capture.summary,
                siteName: capture.siteName,
                image: sharedImagePath,
                imageSHA256: capture.imageSHA256,
                capturedAt: capture.capturedAt,
                icon: sharedIconPath,
                iconSHA256: capture.iconSHA256,
                socialMetadata: capture.socialMetadata.isEmpty ? nil : capture.socialMetadata
            )
            try add(encoder.encode(manifest), at: "\(base)/manifest.json", to: archive)
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
            try add(imageData, at: "images/\(sha256).webp", to: archive)
        }
        guard let data = archive.data else {
            throw WebcardError.invalidArchive("The webcard archive could not be created.")
        }
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

    private static func readVersionOne(
        rootData: Data,
        archive: Archive,
        decoder: JSONDecoder
    ) throws -> WebcardFile {
        let entries = Set(archive.map(\.path))
        guard entries == ["manifest.json", "card.webp"] else {
            throw WebcardError.invalidArchive("Version 1 webcards must contain only manifest.json and card.webp.")
        }
        let manifest = try decoder.decode(VersionOneManifest.self, from: rootData)
        guard manifest.version == 1, manifest.image == "card.webp" else {
            throw WebcardError.invalidArchive("The version 1 manifest is invalid.")
        }
        try validateRemoteURL(manifest.url)
        try validateRemoteURL(manifest.canonicalUrl)
        let imageData = try extract("card.webp", from: archive, limit: maximumImageSize)
        let id = captureID(for: manifest.savedAt)
        let capture = WebcardCapture(
            id: id,
            canonicalURL: manifest.canonicalUrl,
            title: normalized(manifest.title, maximum: 500),
            summary: normalized(manifest.description, maximum: 2_000),
            siteName: normalized(manifest.siteName, maximum: 300),
            imageSHA256: sha256(imageData),
            capturedAt: manifest.savedAt,
            imageData: imageData
        )
        return WebcardFile(sourceURL: manifest.url, captures: [capture], currentCaptureID: id)
    }

    private static func readVersionTwo(
        rootData: Data,
        archive: Archive,
        decoder: JSONDecoder
    ) throws -> WebcardFile {
        let manifest = try decoder.decode(RootManifest.self, from: rootData)
        guard manifest.version == 2, !manifest.captures.isEmpty else {
            throw WebcardError.invalidArchive("The version 2 manifest is invalid.")
        }
        try validateRemoteURL(manifest.url)
        guard Set(manifest.captures).count == manifest.captures.count,
              manifest.captures.contains(manifest.currentCapture) else {
            throw WebcardError.invalidArchive("The capture list is invalid.")
        }
        var expectedEntries = Set(["manifest.json"])
        let captures = try manifest.captures.map { id in
            guard isSafeCaptureID(id) else {
                throw WebcardError.invalidArchive("The webcard contains an invalid capture identifier.")
            }
            let base = "captures/\(id)"
            expectedEntries.insert("\(base)/manifest.json")
            let captureData = try extract("\(base)/manifest.json", from: archive, limit: maximumManifestSize)
            let captureManifest = try decoder.decode(CaptureManifest.self, from: captureData)
            let imagePath: String
            if captureManifest.image == "card.webp" {
                imagePath = "\(base)/card.webp"
            } else if isSharedImagePath(captureManifest.image, sha256: captureManifest.imageSHA256) {
                imagePath = captureManifest.image
            } else {
                throw WebcardError.invalidArchive("The capture image reference is invalid.")
            }
            expectedEntries.insert(imagePath)
            try validateRemoteURL(captureManifest.canonicalUrl)
            let imageData = try extract(imagePath, from: archive, limit: maximumImageSize)
            guard sha256(imageData) == captureManifest.imageSHA256.lowercased() else {
                throw WebcardError.invalidArchive("The capture image checksum does not match.")
            }
            var iconData: Data?
            if let iconPath = captureManifest.icon, let iconSHA256 = captureManifest.iconSHA256 {
                guard isSharedImagePath(iconPath, sha256: iconSHA256) else {
                    throw WebcardError.invalidArchive("The capture icon reference is invalid.")
                }
                expectedEntries.insert(iconPath)
                let extractedIcon = try extract(iconPath, from: archive, limit: maximumImageSize)
                guard sha256(extractedIcon) == iconSHA256.lowercased() else {
                    throw WebcardError.invalidArchive("The capture icon checksum does not match.")
                }
                iconData = extractedIcon
            } else if captureManifest.icon != nil || captureManifest.iconSHA256 != nil {
                throw WebcardError.invalidArchive("The capture icon metadata is incomplete.")
            }
            let capture = WebcardCapture(
                id: id,
                canonicalURL: captureManifest.canonicalUrl,
                title: normalized(captureManifest.title, maximum: 500),
                summary: normalized(captureManifest.description, maximum: 2_000),
                siteName: normalized(captureManifest.siteName, maximum: 300),
                imagePath: captureManifest.image,
                imageSHA256: captureManifest.imageSHA256.lowercased(),
                capturedAt: captureManifest.capturedAt,
                imageData: imageData,
                iconPath: captureManifest.icon,
                iconSHA256: captureManifest.iconSHA256?.lowercased(),
                iconData: iconData,
                socialMetadata: captureManifest.socialMetadata ?? WebcardSocialMetadata()
            )
            try validateCapture(capture)
            return capture
        }
        guard Set(archive.map(\.path)) == expectedEntries else {
            throw WebcardError.invalidArchive("The webcard contains unexpected archive entries.")
        }
        let currentCaptureDate = captures.first { $0.id == manifest.currentCapture }?.capturedAt
        return WebcardFile(
            sourceURL: manifest.url,
            captures: captures,
            currentCaptureID: manifest.currentCapture,
            lastRefreshedAt: manifest.lastRefreshedAt ?? currentCaptureDate
        )
    }

    private static func validateCapture(_ capture: WebcardCapture) throws {
        guard isSafeCaptureID(capture.id),
              (capture.imagePath == "card.webp"
                || isSharedImagePath(capture.imagePath, sha256: capture.imageSHA256)),
              capture.imageData.count <= maximumImageSize,
              capture.imageSHA256 == sha256(capture.imageData),
              capture.title.count <= 500,
              capture.summary.count <= 2_000,
              capture.siteName.count <= 300 else {
            throw WebcardError.invalidArchive("The webcard capture is invalid.")
        }
        if let iconSHA256 = capture.iconSHA256, let iconData = capture.iconData {
            guard capture.iconPath == nil
                    || isSharedImagePath(capture.iconPath!, sha256: iconSHA256),
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

    private static func add(_ data: Data, at path: String, to archive: Archive) throws {
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: .deflate
        ) { position, size in
            let lower = Int(position)
            let upper = min(lower + size, data.count)
            return data.subdata(in: lower..<upper)
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
    static let webcard = UTType(exportedAs: "com.reggi.webcard", conformingTo: .data)
}
