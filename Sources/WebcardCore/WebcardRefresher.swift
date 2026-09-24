import CoreGraphics
import CoreText
import Darwin
import Foundation
import ImageIO
import WebKit
import WebP

public enum WebcardCaptureProgress: Sendable, Equatable {
    case loadingPage
    case readingMetadata
    case loadingImage
    case creatingPreview
    case loadingIcon
    case buildingCard
    case retryingWithoutTLS
}

public actor WebcardRefresher {
    private static let maximumHTMLSize = 2 * 1024 * 1024
    private static let maximumImageSize = 15 * 1024 * 1024

    public init() {}

    public func capture(
        plan: WebcardRequestPlan,
        at date: Date = Date(),
        progress: (@MainActor @Sendable (WebcardCaptureProgress) -> Void)? = nil
    ) async throws -> WebcardRefreshResult {
        do {
            return try await capture(url: plan.preferredURL, at: date, progress: progress)
        } catch let secureError {
            guard let fallbackURL = plan.fallbackURL else {
                throw secureError
            }
            do {
                await progress?(.retryingWithoutTLS)
                return try await capture(url: fallbackURL, at: date, progress: progress)
            } catch {
                throw WebcardError.invalidArchive(
                    "HTTPS failed: \(secureError.localizedDescription) HTTP fallback failed: \(error.localizedDescription)"
                )
            }
        }
    }

    private func capture(
        url: URL,
        at date: Date,
        progress: (@MainActor @Sendable (WebcardCaptureProgress) -> Void)?
    ) async throws -> WebcardRefreshResult {
        let normalizedURL = try PublicURLValidator.normalized(url)
        try PublicURLValidator.validate(normalizedURL)

        await progress?(.loadingPage)
        let page = try await BrowserPageLoader.load(
            url: normalizedURL,
            maximumSize: Self.maximumHTMLSize
        )
        let finalURL = try PublicURLValidator.normalized(page.url)
        try PublicURLValidator.validate(finalURL)
        await progress?(.readingMetadata)
        let metadata = HTMLMetadata.parse(page.html, pageURL: finalURL)

        let imageData: Data
        if let imageURL = metadata.imageURL {
            await progress?(.loadingImage)
            try PublicURLValidator.validate(imageURL)
            let imageRequest = request(url: imageURL, accept: "image/*", referer: finalURL.absoluteString)
            let imageResponse = try await fetch(imageRequest, maximumSize: Self.maximumImageSize)
            guard imageResponse.response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("image/") == true else {
                throw WebcardError.invalidImage
            }
            imageData = try WebcardImageEncoder.encode(imageResponse.data)
        } else {
            await progress?(.creatingPreview)
            imageData = try WebcardImageEncoder.fallback(title: metadata.title, siteName: metadata.siteName)
        }
        let iconData: Data?
        if let iconURL = metadata.iconURL {
            await progress?(.loadingIcon)
            try PublicURLValidator.validate(iconURL)
            let iconRequest = request(url: iconURL, accept: "image/*", referer: nil)
            let iconResponse = try await fetch(iconRequest, maximumSize: Self.maximumImageSize)
            guard iconResponse.response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("image/") == true else {
                throw WebcardError.invalidImage
            }
            iconData = try WebcardImageEncoder.encode(iconResponse.data, maximumWidth: 512, maximumHeight: 512)
        } else {
            iconData = nil
        }
        let iconSHA256 = iconData.map(WebcardArchive.sha256)

        await progress?(.buildingCard)
        return WebcardRefreshResult(
            sourceURL: normalizedURL,
            capture: WebcardCapture(
                id: WebcardArchive.captureID(for: date),
                canonicalURL: metadata.canonicalURL,
                title: metadata.title,
                summary: metadata.summary,
                siteName: metadata.siteName,
                imageSHA256: WebcardArchive.sha256(imageData),
                capturedAt: date,
                imageData: imageData,
                iconSHA256: iconSHA256,
                iconData: iconData,
                socialMetadata: metadata.socialMetadata
            )
        )
    }

    private func request(url: URL, accept: String, referer: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("max-age=0", forHTTPHeaderField: "Cache-Control")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }

        return request
    }

    private func fetch(_ request: URLRequest, maximumSize: Int) async throws -> (data: Data, response: HTTPURLResponse) {
        let delegate = RedirectGuard()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw WebcardError.invalidArchive("The website returned an invalid response.")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw WebcardError.invalidArchive("The website returned HTTP \(response.statusCode).")
        }
        let declaredLength = response.expectedContentLength
        guard declaredLength <= 0 || declaredLength <= maximumSize, data.count <= maximumSize else {
            throw WebcardError.resourceTooLarge
        }
        return (data, response)
    }
}

private struct BrowserPage: Sendable {
    let url: URL
    let html: String
}

@MainActor
private final class BrowserPageLoader: NSObject, WKNavigationDelegate {
    private static let timeout: Duration = .seconds(12)

    private let maximumSize: Int
    private var continuation: CheckedContinuation<BrowserPage, Error>?
    private var navigationCount = 0
    private var responseError: Error?
    private var timeoutTask: Task<Void, Never>?
    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.applicationNameForUserAgent = Self.safariApplicationName
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        return webView
    }()

    private static var safariApplicationName: String {
        let version = Bundle(path: "/Applications/Safari.app")?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "Version/\(version ?? "17.6") Safari/605.1.15"
    }

    private init(maximumSize: Int) {
        self.maximumSize = maximumSize
    }

    static func load(url: URL, maximumSize: Int) async throws -> BrowserPage {
        let loader = BrowserPageLoader(maximumSize: maximumSize)
        return try await loader.load(url: url)
    }

    private func load(url: URL) async throws -> BrowserPage {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            var request = URLRequest(url: url)
            request.timeoutInterval = Self.timeout.timeInterval
            request.cachePolicy = .useProtocolCachePolicy
            webView.load(request)
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Self.timeout)
                self?.finish(
                    throwing: WebcardError.invalidArchive("The website request timed out.")
                )
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.targetFrame?.isMainFrame != false,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        navigationCount += 1
        guard navigationCount <= 6,
              (try? PublicURLValidator.validate(url)) != nil else {
            responseError = navigationCount > 6
                ? WebcardError.invalidArchive("The website redirected too many times.")
                : WebcardError.privateURL
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        guard navigationResponse.isForMainFrame,
              let response = navigationResponse.response as? HTTPURLResponse else {
            decisionHandler(.allow)
            return
        }

        guard (200..<300).contains(response.statusCode) else {
            responseError = WebcardError.invalidArchive(
                "The website returned HTTP \(response.statusCode)."
            )
            decisionHandler(.cancel)
            return
        }
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard contentType.contains("text/html") || contentType.contains("application/xhtml+xml") else {
            responseError = WebcardError.invalidArchive("The URL did not return an HTML page.")
            decisionHandler(.cancel)
            return
        }
        let declaredLength = response.expectedContentLength
        guard declaredLength <= 0 || declaredLength <= maximumSize else {
            responseError = WebcardError.resourceTooLarge
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task {
            do {
                guard let url = webView.url else {
                    throw WebcardError.invalidArchive("The website returned an invalid response.")
                }
                let result = try await webView.evaluateJavaScript(
                    "document.documentElement.outerHTML"
                )
                guard let html = result as? String else {
                    throw WebcardError.invalidArchive("The website returned an invalid HTML page.")
                }
                guard html.utf8.count <= maximumSize else {
                    throw WebcardError.resourceTooLarge
                }
                finish(returning: BrowserPage(url: url, html: html))
            } catch {
                finish(throwing: error)
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(throwing: responseError ?? error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(throwing: responseError ?? error)
    }

    private func finish(returning page: BrowserPage) {
        guard let continuation else {
            return
        }
        self.continuation = nil
        timeoutTask?.cancel()
        webView.stopLoading()
        continuation.resume(returning: page)
    }

    private func finish(throwing error: Error) {
        guard let continuation else {
            return
        }
        self.continuation = nil
        timeoutTask?.cancel()
        webView.stopLoading()
        continuation.resume(throwing: error)
    }
}

public struct WebcardRefreshResult: Sendable {
    public let sourceURL: URL
    public let capture: WebcardCapture

    public init(sourceURL: URL, capture: WebcardCapture) {
        self.sourceURL = sourceURL
        self.capture = capture
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private var redirectCount = 0

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirectCount += 1
        guard redirectCount <= 5,
              let url = request.url,
              (try? PublicURLValidator.validate(url)) != nil else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

private enum PublicURLValidator {
    static func normalized(_ input: URL) throws -> URL {
        guard var components = URLComponents(url: input, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host != nil else {
            throw WebcardError.invalidURL
        }
        components.user = nil
        components.password = nil
        guard let url = components.url else {
            throw WebcardError.invalidURL
        }
        return url
    }

    static func validate(_ url: URL) throws {
        let normalized = try normalized(url)
        guard let host = normalized.host?.lowercased(),
              host != "localhost",
              !host.hasSuffix(".localhost") else {
            throw WebcardError.privateURL
        }

        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let result else {
            throw WebcardError.invalidURL
        }
        defer { freeaddrinfo(result) }

        var cursor: UnsafeMutablePointer<addrinfo>? = result
        var foundAddress = false
        while let info = cursor?.pointee {
            foundAddress = true
            if isPrivate(info.ai_addr, family: info.ai_family) {
                throw WebcardError.privateURL
            }
            cursor = info.ai_next
        }
        guard foundAddress else {
            throw WebcardError.invalidURL
        }
    }

    private static func isPrivate(_ address: UnsafeMutablePointer<sockaddr>?, family: Int32) -> Bool {
        guard let address else {
            return true
        }
        if family == AF_INET {
            let value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            let first = UInt8((value >> 24) & 0xff)
            let second = UInt8((value >> 16) & 0xff)
            return first == 0
                || first == 10
                || first == 127
                || (first == 169 && second == 254)
                || (first == 172 && (16...31).contains(second))
                || (first == 192 && second == 168)
                || first >= 224
        }
        if family == AF_INET6 {
            let bytes = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) }
            }
            let allZero = bytes.allSatisfy { $0 == 0 }
            let loopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
            let uniqueLocal = bytes.first.map { $0 == 0xfc || $0 == 0xfd } ?? true
            let linkLocal = bytes.count > 1 && bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80
            let mappedIPv4 = bytes.prefix(10).allSatisfy { $0 == 0 } && bytes[10] == 0xff && bytes[11] == 0xff
            return allZero || loopback || uniqueLocal || linkLocal || mappedIPv4
        }
        return true
    }
}

struct HTMLMetadata {
    let canonicalURL: URL
    let title: String
    let summary: String
    let siteName: String
    let imageURL: URL?
    let iconURL: URL?
    let socialMetadata: WebcardSocialMetadata

    static func parse(_ html: String, pageURL: URL) -> HTMLMetadata {
        var metadata: [String: String] = [:]
        for tag in matches(#"<meta\b[^>]*>"#, in: html) {
            let attributes = attributes(in: tag)
            let key = (attributes["property"] ?? attributes["name"] ?? "").lowercased()
            if !key.isEmpty, metadata[key] == nil, let content = attributes["content"] {
                metadata[key] = decoded(content)
            }
        }

        var canonicalURL = pageURL
        var iconCandidates: [(url: URL, score: Int)] = []
        for tag in matches(#"<link\b[^>]*>"#, in: html) {
            let attributes = attributes(in: tag)
            let relationships = (attributes["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace)
            if relationships.contains("canonical"),
               let href = attributes["href"],
               let url = URL(string: href, relativeTo: pageURL)?.absoluteURL,
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                canonicalURL = url
            }
            if let href = attributes["href"],
               let url = URL(string: href, relativeTo: pageURL)?.absoluteURL {
                let declaredSize = iconSize(attributes["sizes"] ?? "")
                if relationships.contains("apple-touch-icon") || relationships.contains("apple-touch-icon-precomposed") {
                    iconCandidates.append((url, 10_000 + declaredSize))
                } else if relationships.contains("icon") || relationships.contains("shortcut") {
                    iconCandidates.append((url, declaredSize))
                }
            }
        }

        let titleElement = firstCapture(#"<title\b[^>]*>([\s\S]*?)</title>"#, in: html)
        let title = limited(
            metadata["og:title"] ?? metadata["twitter:title"] ?? decoded(titleElement ?? "").nilIfEmpty ?? pageURL.host ?? "",
            maximum: 500
        )
        let summary = limited(
            metadata["og:description"] ?? metadata["twitter:description"] ?? metadata["description"] ?? "",
            maximum: 2_000
        )
        let siteName = limited(
            metadata["og:site_name"] ?? pageURL.host?.replacingOccurrences(of: "www.", with: "", options: .anchored) ?? "",
            maximum: 300
        )
        let imageValue = metadata["og:image:secure_url"] ?? metadata["og:image"] ?? metadata["twitter:image"]
        let imageURL = imageValue.flatMap { URL(string: $0, relativeTo: pageURL)?.absoluteURL }
        let socialMetadata = WebcardSocialMetadata(
            imageAlt: optionalLimited(
                metadata["og:image:alt"] ?? metadata["twitter:image:alt"],
                maximum: 2_000
            ),
            contentType: optionalLimited(metadata["og:type"], maximum: 200),
            locale: optionalLimited(metadata["og:locale"], maximum: 100),
            author: optionalLimited(metadata["article:author"] ?? metadata["author"], maximum: 500),
            publishedTime: optionalLimited(metadata["article:published_time"], maximum: 200),
            modifiedTime: optionalLimited(
                metadata["article:modified_time"] ?? metadata["og:updated_time"],
                maximum: 200
            ),
            section: optionalLimited(metadata["article:section"], maximum: 300),
            twitterCard: optionalLimited(metadata["twitter:card"], maximum: 100),
            imageMIMEType: optionalLimited(metadata["og:image:type"], maximum: 100),
            imageWidth: positiveInteger(metadata["og:image:width"]),
            imageHeight: positiveInteger(metadata["og:image:height"])
        )

        return HTMLMetadata(
            canonicalURL: canonicalURL,
            title: title.isEmpty ? pageURL.host ?? "Webcard" : title,
            summary: summary,
            siteName: siteName,
            imageURL: imageURL,
            iconURL: iconCandidates.max(by: { $0.score < $1.score })?.url,
            socialMetadata: socialMetadata
        )
    }

    private static func matches(_ pattern: String, in value: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        }
    }

    private static func firstCapture(_ pattern: String, in value: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[range])
    }

    private static func attributes(in tag: String) -> [String: String] {
        guard let expression = try? NSRegularExpression(
            pattern: #"([^\s=/>]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#,
            options: []
        ) else {
            return [:]
        }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        var output: [String: String] = [:]
        for match in expression.matches(in: tag, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: tag) else {
                continue
            }
            let value = (2...4).compactMap { index -> String? in
                guard match.range(at: index).location != NSNotFound,
                      let range = Range(match.range(at: index), in: tag) else {
                    return nil
                }
                return String(tag[range])
            }.first ?? ""
            output[String(tag[keyRange]).lowercased()] = decoded(value)
        }
        return output
    }

    private static func decoded(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func limited(_ value: String, maximum: Int) -> String {
        String(decoded(value).prefix(maximum))
    }

    private static func optionalLimited(_ value: String?, maximum: Int) -> String? {
        guard let value else {
            return nil
        }
        return limited(value, maximum: maximum).nilIfEmpty
    }

    private static func positiveInteger(_ value: String?) -> Int? {
        guard let value, let number = Int(decoded(value)), number > 0 else {
            return nil
        }
        return number
    }

    private static func iconSize(_ value: String) -> Int {
        value.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .compactMap { size -> Int? in
                let parts = size.split(separator: "x", maxSplits: 1).compactMap { Int($0) }
                guard parts.count == 2 else {
                    return nil
                }
                return parts[0] * parts[1]
            }
            .max() ?? 0
    }
}

private enum WebcardImageEncoder {
    static func encode(
        _ sourceData: Data,
        maximumWidth: CGFloat = 1_600,
        maximumHeight: CGFloat = 900
    ) throws -> Data {
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let sourceWidth = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let sourceHeight = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              sourceWidth > 0,
              sourceHeight > 0 else {
            throw WebcardError.invalidImage
        }
        let scale = min(1, maximumWidth / sourceWidth, maximumHeight / sourceHeight)
        let width = max(1, Int((sourceWidth * scale).rounded()))
        let height = max(1, Int((sourceHeight * scale).rounded()))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw WebcardError.invalidImage
        }
        return try encode(image, width: width, height: height)
    }

    static func fallback(title: String, siteName: String) throws -> Data {
        let width = 1_200
        let height = 630
        guard let context = makeContext(width: width, height: height) else {
            throw WebcardError.invalidImage
        }
        context.setFillColor(CGColor(red: 0.125, green: 0.141, blue: 0.165, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(siteName, in: context, x: 72, y: 520, size: 32, color: .init(gray: 0.7, alpha: 1))
        draw(title, in: context, x: 72, y: 250, size: 58, color: .init(gray: 1, alpha: 1))
        guard let image = context.makeImage() else {
            throw WebcardError.invalidImage
        }
        return try encode(image, width: width, height: height)
    }

    private static func encode(_ image: CGImage, width: Int, height: Int) throws -> Data {
        guard let context = makeContext(width: width, height: height) else {
            throw WebcardError.invalidImage
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let bytes = context.data else {
            throw WebcardError.invalidImage
        }
        let encoder = WebPEncoder()
        return try encoder.encode(
            RGBA: bytes.assumingMemoryBound(to: UInt8.self),
            config: .preset(.picture, quality: 82),
            originWidth: width,
            originHeight: height,
            stride: width * 4
        )
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func draw(
        _ value: String,
        in context: CGContext,
        x: CGFloat,
        y: CGFloat,
        size: CGFloat,
        color: CGColor
    ) {
        let font = CTFontCreateWithName("SF Pro Display" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
    }
}

private extension URL {
    var originRoot: String? {
        guard let scheme, let host else {
            return nil
        }
        var value = "\(scheme)://\(host)"
        if let port {
            value += ":\(port)"
        }
        return value + "/"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
