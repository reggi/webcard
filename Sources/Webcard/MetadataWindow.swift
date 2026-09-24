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

    init(capture: WebcardCapture, usesInsecureHTTP: Bool) {
        captureID = capture.id
        title = capture.title
        summary = capture.summary
        siteName = capture.siteName
        url = capture.canonicalURL
        capturedAt = capture.capturedAt
        self.usesInsecureHTTP = usesInsecureHTTP
    }

    var textCapture: WebcardCapture {
        WebcardCapture(
            id: captureID, canonicalURL: url, title: title, summary: summary,
            siteName: siteName, imageSHA256: "", capturedAt: capturedAt, imageData: Data()
        )
    }

    var plainText: String {
        """
        Site: \(siteName)
        Title: \(title)

        Description: \(summary)

        URL: \(url.absoluteString)
        Captured: \(capturedAt.formatted(.iso8601))
        """
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
