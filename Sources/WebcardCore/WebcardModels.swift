import Foundation

public enum WebcardJSONValue: Codable, Hashable, Sendable {
    case array([WebcardJSONValue])
    case boolean(Bool)
    case number(Double)
    case object([String: WebcardJSONValue])
    case string(String)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([WebcardJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: WebcardJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .array(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public struct WebcardRequestPlan: Sendable, Equatable {
    public let preferredURL: URL
    public let fallbackURL: URL?

    public init(url: URL) {
        if url.scheme?.lowercased() == "http" {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            preferredURL = components?.url ?? url
            fallbackURL = url
        } else {
            preferredURL = url
            fallbackURL = nil
        }
    }
}

public enum WebcardAddress {
    public static func requestPlan(from input: String) -> WebcardRequestPlan? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        let hasScheme = value.contains("://")
        let candidate = hasScheme ? value : "https://\(value)"
        guard let url = URL(string: candidate),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else {
            return nil
        }
        if !hasScheme {
            var fallbackComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
            fallbackComponents?.scheme = "http"
            return WebcardRequestPlan(
                preferredURL: url,
                fallbackURL: fallbackComponents?.url
            )
        }
        return WebcardRequestPlan(url: url)
    }
}

public struct WebcardBulkImportBatch: Sendable, Equatable {
    public let plans: [WebcardRequestPlan]
    public let invalidInputs: [String]
    public let duplicateCount: Int

    public static func parse(_ input: String) -> WebcardBulkImportBatch {
        var plans: [WebcardRequestPlan] = []
        var invalidInputs: [String] = []
        var seenURLs: Set<String> = []
        var duplicateCount = 0

        for line in input.components(separatedBy: .newlines) {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                continue
            }
            guard let plan = WebcardAddress.requestPlan(from: value) else {
                invalidInputs.append(value)
                continue
            }
            let key = plan.preferredURL.absoluteString
            guard seenURLs.insert(key).inserted else {
                duplicateCount += 1
                continue
            }
            plans.append(plan)
        }

        return WebcardBulkImportBatch(
            plans: plans,
            invalidInputs: invalidInputs,
            duplicateCount: duplicateCount
        )
    }
}

public actor WebcardDomainRateLimiter {
    public static let defaultMinimumInterval: Duration = .seconds(8)

    private let minimumInterval: Duration
    private let clock = ContinuousClock()
    private var lastStartByDomain: [String: ContinuousClock.Instant] = [:]

    public init(minimumInterval: Duration = defaultMinimumInterval) {
        self.minimumInterval = minimumInterval
    }

    public func wait(for url: URL) async throws {
        guard let domain = url.host()?.lowercased(), !domain.isEmpty else {
            return
        }

        if let previousStart = lastStartByDomain[domain] {
            let elapsed = previousStart.duration(to: clock.now)
            if elapsed < minimumInterval {
                try await clock.sleep(for: minimumInterval - elapsed)
            }
        }
        lastStartByDomain[domain] = clock.now
    }
}

private extension WebcardRequestPlan {
    init(preferredURL: URL, fallbackURL: URL?) {
        self.preferredURL = preferredURL
        self.fallbackURL = fallbackURL
    }
}

public enum WebcardError: LocalizedError, Equatable {
    case invalidArchive(String)
    case unsupportedVersion(Int)
    case invalidURL
    case privateURL
    case missingCapture
    case resourceTooLarge
    case invalidImage
    case noChanges

    public var errorDescription: String? {
        switch self {
        case .invalidArchive(let message):
            message
        case .unsupportedVersion(let version):
            "Webcard format version \(version) is not supported."
        case .invalidURL:
            "Enter a valid HTTP or HTTPS address."
        case .privateURL:
            "Local and private network addresses cannot be saved as webcards."
        case .missingCapture:
            "The selected capture is missing."
        case .resourceTooLarge:
            "The downloaded webcard resource is too large."
        case .invalidImage:
            "The webcard image could not be decoded."
        case .noChanges:
            "This webcard is current."
        }
    }
}

public struct WebcardSocialMetadata: Codable, Hashable, Sendable {
    public let imageAlt: String?
    public let contentType: String?
    public let locale: String?
    public let author: String?
    public let publishedTime: String?
    public let modifiedTime: String?
    public let section: String?
    public let twitterCard: String?
    public let imageMIMEType: String?
    public let imageWidth: Int?
    public let imageHeight: Int?

    public init(
        imageAlt: String? = nil,
        contentType: String? = nil,
        locale: String? = nil,
        author: String? = nil,
        publishedTime: String? = nil,
        modifiedTime: String? = nil,
        section: String? = nil,
        twitterCard: String? = nil,
        imageMIMEType: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil
    ) {
        self.imageAlt = imageAlt
        self.contentType = contentType
        self.locale = locale
        self.author = author
        self.publishedTime = publishedTime
        self.modifiedTime = modifiedTime
        self.section = section
        self.twitterCard = twitterCard
        self.imageMIMEType = imageMIMEType
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    public var isEmpty: Bool {
        imageAlt == nil
            && contentType == nil
            && locale == nil
            && author == nil
            && publishedTime == nil
            && modifiedTime == nil
            && section == nil
            && twitterCard == nil
            && imageMIMEType == nil
            && imageWidth == nil
            && imageHeight == nil
    }

    public var searchableValues: [String] {
        [
            imageAlt,
            contentType,
            locale,
            author,
            publishedTime,
            modifiedTime,
            section,
            twitterCard,
            imageMIMEType,
            imageWidth.map(String.init),
            imageHeight.map(String.init)
        ].compactMap { $0 }
    }
}

public struct WebcardCapture: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let canonicalURL: URL
    public let title: String
    public let summary: String
    public let siteName: String
    public let imagePath: String
    public let imageSHA256: String
    public let capturedAt: Date
    public let imageData: Data
    public let iconPath: String?
    public let iconSHA256: String?
    public let iconData: Data?
    public let socialMetadata: WebcardSocialMetadata
    public let extensions: [String: WebcardJSONValue]
    public let additionalProperties: [String: WebcardJSONValue]

    public init(
        id: String,
        canonicalURL: URL,
        title: String,
        summary: String,
        siteName: String,
        imagePath: String = "card.webp",
        imageSHA256: String,
        capturedAt: Date,
        imageData: Data,
        iconPath: String? = nil,
        iconSHA256: String? = nil,
        iconData: Data? = nil,
        socialMetadata: WebcardSocialMetadata = WebcardSocialMetadata(),
        extensions: [String: WebcardJSONValue] = [:],
        additionalProperties: [String: WebcardJSONValue] = [:]
    ) {
        self.id = id
        self.canonicalURL = canonicalURL
        self.title = title
        self.summary = summary
        self.siteName = siteName
        self.imagePath = imagePath
        self.imageSHA256 = imageSHA256
        self.capturedAt = capturedAt
        self.imageData = imageData
        self.iconPath = iconPath
        self.iconSHA256 = iconSHA256
        self.iconData = iconData
        self.socialMetadata = socialMetadata
        self.extensions = extensions
        self.additionalProperties = additionalProperties
    }

    public func hasSameContent(as other: WebcardCapture) -> Bool {
        canonicalURL == other.canonicalURL
            && title == other.title
            && summary == other.summary
            && siteName == other.siteName
            && imageSHA256 == other.imageSHA256
            && iconSHA256 == other.iconSHA256
            && socialMetadata == other.socialMetadata
            && extensions == other.extensions
            && additionalProperties == other.additionalProperties
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case canonicalURL
        case title
        case summary = "description"
        case siteName
        case imagePath = "image"
        case imageSHA256
        case capturedAt
        case imageData
        case iconPath = "icon"
        case iconSHA256
        case iconData
        case socialMetadata
        case extensions
        case additionalProperties
    }
}

public struct WebcardFile: Hashable, Sendable {
    public var sourceURL: URL?
    public var captures: [WebcardCapture]
    public var currentCaptureID: String?
    public var lastRefreshedAt: Date?
    public var extensions: [String: WebcardJSONValue]
    public var additionalProperties: [String: WebcardJSONValue]
    public var extensionEntries: [String: Data]

    public init(
        sourceURL: URL? = nil,
        captures: [WebcardCapture] = [],
        currentCaptureID: String? = nil,
        lastRefreshedAt: Date? = nil,
        extensions: [String: WebcardJSONValue] = [:],
        additionalProperties: [String: WebcardJSONValue] = [:],
        extensionEntries: [String: Data] = [:]
    ) {
        self.sourceURL = sourceURL
        self.captures = captures
        self.currentCaptureID = currentCaptureID ?? captures.last?.id
        self.lastRefreshedAt = lastRefreshedAt ?? captures.last?.capturedAt
        self.extensions = extensions
        self.additionalProperties = additionalProperties
        self.extensionEntries = extensionEntries
    }

    public var currentCapture: WebcardCapture? {
        guard let currentCaptureID else {
            return captures.last
        }
        return captures.first { $0.id == currentCaptureID } ?? captures.last
    }

    public var suggestedFilename: String {
        let title = currentCapture.flatMap {
            Self.conciseTitle($0.title, siteName: $0.siteName)
        }
        let candidates = [
            title,
            currentCapture?.siteName,
            currentCapture?.canonicalURL.host(),
            sourceURL?.host()
        ]

        let basename = candidates
            .compactMap { $0 }
            .lazy
            .compactMap(Self.sanitizedFilenameComponent)
            .first ?? "webcard"

        return "\(basename).webcard"
    }

    public mutating func append(_ capture: WebcardCapture) {
        captures.append(capture)
        currentCaptureID = capture.id
        lastRefreshedAt = capture.capturedAt
    }

    private static func sanitizedFilenameComponent(_ value: String) -> String? {
        guard let normalized = normalizedText(value) else {
            return nil
        }

        let folded = normalized
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

        let maximumLength = 60
        guard slug.count > maximumLength else {
            return slug
        }

        let endIndex = slug.index(slug.startIndex, offsetBy: maximumLength)
        let prefix = slug[..<endIndex]
        let wordBoundary = prefix.lastIndex(of: "-") ?? endIndex
        let shortened = slug[..<wordBoundary]
        return shortened.isEmpty ? nil : String(shortened)
    }

    private static func conciseTitle(_ title: String, siteName: String) -> String? {
        guard var normalizedTitle = normalizedText(title) else {
            return nil
        }

        if let normalizedSiteName = normalizedText(siteName) {
            for separator in [" | ", " - ", " – ", " — "] {
                let suffix = separator + normalizedSiteName
                if normalizedTitle.range(
                    of: suffix,
                    options: [.caseInsensitive, .anchored, .backwards]
                ) != nil {
                    normalizedTitle.removeLast(suffix.count)
                    break
                }
            }
        }

        if let comma = normalizedTitle.firstIndex(of: ","),
           normalizedTitle.distance(from: normalizedTitle.startIndex, to: comma) >= 12 {
            normalizedTitle = String(normalizedTitle[..<comma])
        }

        return sanitizedFilenameComponent(normalizedTitle)
    }

    private static func normalizedText(_ value: String) -> String? {
        let normalized = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return normalized.isEmpty ? nil : normalized
    }
}
