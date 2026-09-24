import Foundation

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
        iconData: Data? = nil
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
    }

    public func hasSameContent(as other: WebcardCapture) -> Bool {
        canonicalURL == other.canonicalURL
            && title == other.title
            && summary == other.summary
            && siteName == other.siteName
            && imageSHA256 == other.imageSHA256
            && iconSHA256 == other.iconSHA256
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
    }
}

public struct WebcardFile: Hashable, Sendable {
    public var sourceURL: URL?
    public var captures: [WebcardCapture]
    public var currentCaptureID: String?
    public var lastRefreshedAt: Date?

    public init(
        sourceURL: URL? = nil,
        captures: [WebcardCapture] = [],
        currentCaptureID: String? = nil,
        lastRefreshedAt: Date? = nil
    ) {
        self.sourceURL = sourceURL
        self.captures = captures
        self.currentCaptureID = currentCaptureID ?? captures.last?.id
        self.lastRefreshedAt = lastRefreshedAt ?? captures.last?.capturedAt
    }

    public var currentCapture: WebcardCapture? {
        guard let currentCaptureID else {
            return captures.last
        }
        return captures.first { $0.id == currentCaptureID } ?? captures.last
    }

    public mutating func append(_ capture: WebcardCapture) {
        captures.append(capture)
        currentCaptureID = capture.id
        lastRefreshedAt = capture.capturedAt
    }
}
