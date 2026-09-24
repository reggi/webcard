import AppKit
import SwiftUI
import WebcardCore

struct WebcardCardLayout: Codable {
    static let detailsHeight: CGFloat = WebcardLayoutMetrics.contentInset * 3
        + WebcardLayoutMetrics.buttonHeight

    let width: CGFloat
    let imageHeight: CGFloat
    let metadataHeight: CGFloat
    let maximumMetadataHeight: CGFloat?
    let paddedHeight: CGFloat

    var verticalPadding: CGFloat {
        max(0, (paddedHeight - imageHeight - metadataHeight - Self.detailsHeight) / 2)
    }

    func masksImage(_ imageSize: CGSize) -> Bool {
        imageHeight < width * imageSize.height / imageSize.width - 0.5
    }
}

enum WebcardLayoutMetrics {
    static let maximumCardWidth: CGFloat = 700
    static let compactCardWidth: CGFloat = 266
    static let compactImageHeight: CGFloat = 180
    static let compactLayoutHeight: CGFloat = 375
    static let imageHeightFraction: CGFloat = 309 / 455
    static let fittedLayoutOverflowAllowance: CGFloat = 3
    static let minimumVerticalPadding: CGFloat = 6
    static let outerPadding: CGFloat = 18
    static let contentInset: CGFloat = 18
    static let buttonHeight: CGFloat = 32

    @MainActor
    static func cardLayout(
        capture: WebcardCapture,
        availableSize: CGSize,
        imageSize: CGSize,
        usesInsecureHTTP: Bool,
        truncatesText: Bool
    ) -> WebcardCardLayout {
        let widthLimit = min(
            maximumCardWidth,
            max(1, availableSize.width - outerPadding * 2)
        )
        let minimumWidth = min(compactCardWidth, widthLimit)
        let heightDrivenWidth = compactCardWidth
            + max(0, availableSize.height - compactLayoutHeight) * 1.9
        let detailsHeight = WebcardCardLayout.detailsHeight
        let imageAspectRatio = imageSize.width / imageSize.height
        let width = max(minimumWidth, min(widthLimit, heightDrivenWidth))
        let naturalImageHeight = width / imageAspectRatio
        guard truncatesText else {
            let metadataHeight = SelectableMetadataView.height(
                for: capture,
                usesInsecureHTTP: usesInsecureHTTP,
                width: width - contentInset * 2
            )
            return WebcardCardLayout(
                width: width,
                imageHeight: naturalImageHeight,
                metadataHeight: metadataHeight,
                maximumMetadataHeight: nil,
                paddedHeight: naturalImageHeight + metadataHeight + detailsHeight + outerPadding * 2
            )
        }

        let minimumMetadataHeight = SelectableMetadataView.minimumHeight(
            for: capture,
            usesInsecureHTTP: usesInsecureHTTP,
            width: width - contentInset * 2
        )
        let fittedContentHeight = max(
            0,
            availableSize.height
                - detailsHeight
                - outerPadding * 2
                + fittedLayoutOverflowAllowance
        )
        let ratioImageHeight = fittedContentHeight * imageHeightFraction
        let availableContentHeight = max(
            0,
            availableSize.height - minimumVerticalPadding * 2 - detailsHeight
        )
        let preferredImageHeight = min(
            naturalImageHeight,
            max(compactImageHeight, ratioImageHeight)
        )
        let imageHeight = min(
            preferredImageHeight,
            max(1, availableContentHeight - minimumMetadataHeight)
        )
        let metadataHeight = max(minimumMetadataHeight, fittedContentHeight - imageHeight)
        let verticalPadding = min(
            outerPadding,
            max(
                minimumVerticalPadding,
                (availableSize.height - imageHeight - minimumMetadataHeight - detailsHeight) / 2
            )
        )
        let fittedVerticalPadding = min(
            verticalPadding,
            max(
                minimumVerticalPadding,
                (availableSize.height - imageHeight - metadataHeight - detailsHeight) / 2
            )
        )
        return WebcardCardLayout(
            width: width,
            imageHeight: imageHeight,
            metadataHeight: metadataHeight,
            maximumMetadataHeight: metadataHeight,
            paddedHeight: imageHeight + metadataHeight + detailsHeight + fittedVerticalPadding * 2
        )
    }
}

struct SelectableMetadataView: NSViewRepresentable {
    enum Field: String {
        case title
        case description
    }

    private static let fieldAttribute = NSAttributedString.Key("WebcardMetadataField")

    private struct CacheKey: Equatable {
        let capture: WebcardCapture
        let usesInsecureHTTP: Bool
        let width: CGFloat
        let maximumHeight: CGFloat?
        let titleLineLimit: Int?
        let descriptionLineLimit: Int?
    }

    private struct CachedMetadata {
        let key: CacheKey
        let text: NSAttributedString
        let height: CGFloat
    }

    @MainActor private static var metadataCache: [CachedMetadata] = []

    let capture: WebcardCapture
    let usesInsecureHTTP: Bool
    let layoutWidth: CGFloat
    let maximumHeight: CGFloat?
    var titleLineLimit: Int? = nil
    var descriptionLineLimit: Int? = nil

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        textView.isVerticallyResizable = maximumHeight == nil
        let size = CGSize(
            width: layoutWidth,
            height: .greatestFiniteMagnitude
        )
        if textView.textContainer?.containerSize != size {
            textView.textContainer?.containerSize = size
        }
        let text = Self.attributedString(
            capture: capture,
            usesInsecureHTTP: usesInsecureHTTP,
            width: layoutWidth,
            maximumHeight: maximumHeight,
            titleLineLimit: titleLineLimit,
            descriptionLineLimit: descriptionLineLimit
        )
        if textView.textStorage?.isEqual(to: text) != true {
            textView.textStorage?.setAttributedString(text)
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView textView: NSTextView,
        context: Context
    ) -> CGSize? {
        let width = proposal.width ?? layoutWidth
        return CGSize(
            width: width,
            height: maximumHeight ?? Self.height(
                for: capture,
                usesInsecureHTTP: usesInsecureHTTP,
                width: width,
                titleLineLimit: titleLineLimit,
                descriptionLineLimit: descriptionLineLimit
            )
        )
    }

    static func height(
        for capture: WebcardCapture,
        usesInsecureHTTP: Bool,
        width: CGFloat,
        maximumHeight: CGFloat? = nil,
        titleLineLimit: Int? = nil,
        descriptionLineLimit: Int? = nil
    ) -> CGFloat {
        metadata(
            for: capture,
            usesInsecureHTTP: usesInsecureHTTP,
            width: width,
            maximumHeight: maximumHeight,
            titleLineLimit: titleLineLimit,
            descriptionLineLimit: descriptionLineLimit
        ).height
    }

    private static func measuredHeight(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        measuredLayout(of: text, width: width).height
    }

    private static func measuredLayout(of text: NSAttributedString, width: CGFloat) -> (height: CGFloat, lines: Int) {
        guard text.length > 0 else { return (0, 0) }
        let textStorage = NSTextStorage(attributedString: text)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            containerSize: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        var lines = 0
        layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)) { _, _, _, _, _ in
            lines += 1
        }
        return (ceil(layoutManager.usedRect(for: textContainer).height), lines)
    }

    static func urlHeight(for capture: WebcardCapture, width: CGFloat) -> CGFloat {
        measuredHeight(of: urlText(for: capture), width: width)
    }

    static func minimumHeight(for capture: WebcardCapture, usesInsecureHTTP: Bool, width: CGFloat) -> CGFloat {
        height(for: capture, usesInsecureHTTP: usesInsecureHTTP, width: width, maximumHeight: 0)
    }

    private static func urlText(for capture: WebcardCapture) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        return NSAttributedString(
            string: capture.canonicalURL.absoluteString,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]
        )
    }

    static func attributedString(
        capture: WebcardCapture,
        usesInsecureHTTP: Bool,
        width: CGFloat,
        maximumHeight: CGFloat?,
        titleLineLimit: Int? = nil,
        descriptionLineLimit: Int? = nil
    ) -> NSAttributedString {
        metadata(
            for: capture, usesInsecureHTTP: usesInsecureHTTP, width: width,
            maximumHeight: maximumHeight, titleLineLimit: titleLineLimit,
            descriptionLineLimit: descriptionLineLimit
        ).text
    }

    private static func metadata(
        for capture: WebcardCapture,
        usesInsecureHTTP: Bool,
        width: CGFloat,
        maximumHeight: CGFloat?,
        titleLineLimit: Int?,
        descriptionLineLimit: Int?
    ) -> CachedMetadata {
        let key = CacheKey(
            capture: capture, usesInsecureHTTP: usesInsecureHTTP, width: width,
            maximumHeight: maximumHeight, titleLineLimit: titleLineLimit,
            descriptionLineLimit: descriptionLineLimit
        )
        if let cached = metadataCache.last(where: { $0.key == key }) {
            return cached
        }
        let text = buildAttributedString(
            capture: capture, usesInsecureHTTP: usesInsecureHTTP, width: width,
            maximumHeight: maximumHeight, titleLineLimit: titleLineLimit,
            descriptionLineLimit: descriptionLineLimit
        )
        let result = CachedMetadata(key: key, text: text, height: measuredHeight(of: text, width: width))
        if metadataCache.count == 12 {
            metadataCache.removeFirst()
        }
        metadataCache.append(result)
        return result
    }

    private static func buildAttributedString(
        capture: WebcardCapture,
        usesInsecureHTTP: Bool,
        width: CGFloat,
        maximumHeight: CGFloat?,
        titleLineLimit: Int?,
        descriptionLineLimit: Int?,
        compactHeader: Bool = false
    ) -> NSAttributedString {
        if let maximumHeight {
            return automaticMetadata(
                capture: capture, usesInsecureHTTP: usesInsecureHTTP,
                width: width, maximumHeight: maximumHeight
            )
        }
        let output = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 8
        let siteFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let warningFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let titleFont = NSFont.systemFont(ofSize: 22, weight: .semibold)
        let descriptionFont = NSFont.systemFont(ofSize: 14)

        if !capture.siteName.isEmpty {
            var siteWidth = width
            if let iconData = capture.iconData, let icon = NSImage(data: iconData) {
                let iconSide = min(18, icon.size.width, icon.size.height)
                let attachment = NSTextAttachment()
                let cell = NSTextAttachmentCell(imageCell: icon)
                cell.image?.size = NSSize(width: iconSide, height: iconSide)
                attachment.attachmentCell = cell
                attachment.bounds = NSRect(
                    x: 0,
                    y: (siteFont.capHeight - iconSide) / 2,
                    width: iconSide,
                    height: iconSide
                )
                output.append(NSAttributedString(attachment: attachment))
                output.append(NSAttributedString(string: "  "))
                siteWidth -= iconSide + 8
            }
            output.append(line(
                limited(capture.siteName.uppercased(), toLines: compactHeader ? 1 : nil, font: siteFont, width: siteWidth),
                font: siteFont,
                color: .secondaryLabelColor,
                paragraph: paragraph
            ))
        }

        if usesInsecureHTTP {
            output.append(line(
                limited(
                    "⚠ HTTPS is unavailable. This card refreshes over an unencrypted HTTP connection.",
                    toLines: compactHeader ? 2 : nil, font: warningFont, width: width
                ),
                font: warningFont,
                color: .systemOrange,
                paragraph: paragraph
            ))
        }

        if (titleLineLimit ?? 1) > 0 {
            output.append(line(
                limited(capture.title, toLines: titleLineLimit, font: titleFont, width: width),
                font: titleFont,
                color: .labelColor,
                paragraph: paragraph,
                field: .title
            ))
        }

        if !capture.summary.isEmpty, (descriptionLineLimit ?? 1) > 0 {
            output.append(line(
                limited(capture.summary, toLines: descriptionLineLimit, font: descriptionFont, width: width),
                font: descriptionFont,
                color: .secondaryLabelColor,
                paragraph: paragraph,
                field: .description
            ))
        }

        output.append(urlText(for: capture))
        return output
    }

    private static func automaticMetadata(
        capture: WebcardCapture,
        usesInsecureHTTP: Bool,
        width: CGFloat,
        maximumHeight: CGFloat
    ) -> NSAttributedString {
        func candidate(titleLines: Int?, descriptionLines: Int?) -> NSAttributedString {
            buildAttributedString(
                capture: capture, usesInsecureHTTP: usesInsecureHTTP, width: width,
                maximumHeight: nil, titleLineLimit: titleLines,
                descriptionLineLimit: descriptionLines, compactHeader: true
            )
        }
        var titleLines = 1
        var result = candidate(titleLines: 1, descriptionLines: 1)
        guard maximumHeight > 0, measuredHeight(of: result, width: width) <= maximumHeight else {
            return result
        }
        let full = candidate(titleLines: nil, descriptionLines: nil)
        if measuredHeight(of: full, width: width) <= maximumHeight {
            return full
        }
        let twoLineTitle = candidate(titleLines: 2, descriptionLines: 1)
        if measuredHeight(of: twoLineTitle, width: width) <= maximumHeight {
            titleLines = 2
            result = twoLineTitle
        }
        var lower = 1
        var upper = max(1, Int(maximumHeight / NSLayoutManager().defaultLineHeight(for: NSFont.systemFont(ofSize: 14))))
        while lower < upper {
            let middle = (lower + upper + 1) / 2
            let expanded = candidate(titleLines: titleLines, descriptionLines: middle)
            if measuredHeight(of: expanded, width: width) <= maximumHeight {
                lower = middle
                result = expanded
            } else {
                upper = middle - 1
            }
        }
        if displayedText(for: .description, in: result) == normalized(capture.summary) {
            let descriptionLines = lower
            lower = titleLines
            upper = max(lower, Int(maximumHeight / NSLayoutManager().defaultLineHeight(for: NSFont.systemFont(ofSize: 22))))
            while lower < upper {
                let middle = (lower + upper + 1) / 2
                let expanded = candidate(titleLines: middle, descriptionLines: descriptionLines)
                if measuredHeight(of: expanded, width: width) <= maximumHeight {
                    lower = middle
                    result = expanded
                } else {
                    upper = middle - 1
                }
            }
        }
        return result
    }

    private static func line(
        _ value: String,
        font: NSFont,
        color: NSColor,
        paragraph: NSParagraphStyle,
        field: Field? = nil
    ) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: "\(value)\n",
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
        if let field {
            text.addAttribute(fieldAttribute, value: field.rawValue, range: NSRange(location: 0, length: text.length))
        }
        return text
    }

    static func displayedText(for field: Field, in text: NSAttributedString) -> String {
        displayedAttributedText(for: field, in: text).string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func displayedLineCount(for field: Field, in text: NSAttributedString, width: CGFloat) -> Int {
        measuredLayout(of: displayedAttributedText(for: field, in: text), width: width).lines
    }

    private static func displayedAttributedText(for field: Field, in text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString()
        text.enumerateAttribute(fieldAttribute, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if value as? String == field.rawValue {
                result.append(text.attributedSubstring(from: range))
            }
        }
        while result.string.hasSuffix("\n") {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }
        return result
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func limited(_ value: String, toLines limit: Int?, font: NSFont, width: CGFloat) -> String {
        let text = normalized(value)
        guard let limit else { return text }
        guard limit > 0 else { return "" }
        func fits(_ candidate: String) -> Bool {
            measuredLayout(
                of: NSAttributedString(string: candidate, attributes: [.font: font]),
                width: width
            ).lines <= limit
        }
        // Grow only the visible prefix instead of laying out the entire description.
        var upper = 64
        var prefix = String(text.prefix(upper))
        while fits(prefix + "…") {
            if prefix == text { return text }
            upper *= 2
            prefix = String(text.prefix(upper))
        }
        if prefix == text, fits(text) { return text }
        let boundaries = Array(prefix.indices) + [prefix.endIndex]
        func candidate(_ count: Int) -> String {
            prefix[..<boundaries[count]].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        var lower = 0
        upper = max(0, boundaries.count - 1)
        while lower < upper {
            let middle = (lower + upper + 1) / 2
            if fits(candidate(middle)) {
                lower = middle
            } else {
                upper = middle - 1
            }
        }
        return candidate(lower)
    }
}
