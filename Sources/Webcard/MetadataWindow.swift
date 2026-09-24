import AppKit
import SwiftUI
import WebcardCore

struct MetadataSnapshot: Codable, Hashable {
    let captureID: String
    let title: String
    let summary: String
    let siteName: String
    let url: URL
    let capturedAt: Date
    let usesInsecureHTTP: Bool
    let socialMetadata: WebcardSocialMetadata

    init(capture: WebcardCapture, usesInsecureHTTP: Bool) {
        captureID = capture.id
        title = capture.title
        summary = capture.summary
        siteName = capture.siteName
        url = capture.canonicalURL
        capturedAt = capture.capturedAt
        self.usesInsecureHTTP = usesInsecureHTTP
        socialMetadata = capture.socialMetadata
    }

    var textCapture: WebcardCapture {
        WebcardCapture(
            id: captureID, canonicalURL: url, title: title, summary: summary,
            siteName: siteName, imageSHA256: "", capturedAt: capturedAt, imageData: Data(),
            socialMetadata: socialMetadata
        )
    }

    var plainText: String {
        var value = """
        Site: \(siteName)
        Title: \(title)

        Description: \(summary)

        URL: \(url.absoluteString)
        Captured: \(capturedAt.formatted(.iso8601))
        """
        if !socialMetadata.isEmpty {
            value += "\n\nSocial Metadata:\n\(socialMetadataText)"
        }
        return value
    }

    var socialMetadataText: String {
        [
            labeled("Image alt", socialMetadata.imageAlt),
            labeled("Content type", socialMetadata.contentType),
            labeled("Locale", socialMetadata.locale),
            labeled("Author", socialMetadata.author),
            labeled("Published", socialMetadata.publishedTime),
            labeled("Modified", socialMetadata.modifiedTime),
            labeled("Section", socialMetadata.section),
            labeled("Twitter card", socialMetadata.twitterCard),
            labeled("Image type", socialMetadata.imageMIMEType),
            labeled("Image width", socialMetadata.imageWidth.map(String.init)),
            labeled("Image height", socialMetadata.imageHeight.map(String.init))
        ].compactMap { $0 }.joined(separator: "\n")
    }

    private func labeled(_ label: String, _ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return "\(label): \(value)"
    }
}

struct MetadataWindow: View {
    let snapshot: MetadataSnapshot

    var body: some View {
        VStack(spacing: 0) {
            Text("Captured \(snapshot.capturedAt.formatted(date: .abbreviated, time: .standard))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            GeometryReader { geometry in
                ScrollView {
                    SelectableMetadataView(
                        capture: snapshot.textCapture,
                        usesInsecureHTTP: snapshot.usesInsecureHTTP,
                        layoutWidth: max(1, geometry.size.width - 40),
                        maximumHeight: nil
                    )
                    .padding(20)

                    if !snapshot.socialMetadata.isEmpty {
                        Divider()
                            .padding(.horizontal, 20)
                        Text(snapshot.socialMetadataText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 280)
        .navigationTitle(snapshot.title.isEmpty ? "Selectable Metadata" : snapshot.title)
        .navigationSubtitle("Selectable Metadata")
        .toolbar {
            Button("Copy All", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(snapshot.plainText, forType: .string)
            }
        }
    }
}
