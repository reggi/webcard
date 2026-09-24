import SwiftUI
import UniformTypeIdentifiers
import WebcardCore

enum WebcardDocumentWindowMetrics {
    static let minimumWidth: CGFloat = 360
    static let minimumHeight: CGFloat = 420
    static let defaultWidth: CGFloat = 550
    static let defaultHeight: CGFloat = 550
}

@main
struct WebcardApp: App {
    @NSApplicationDelegateAdaptor(WebcardAppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: WebcardDocument()) { configuration in
            WebcardDocumentView(document: configuration.$document)
                .frame(
                    minWidth: WebcardDocumentWindowMetrics.minimumWidth,
                    idealWidth: WebcardDocumentWindowMetrics.defaultWidth,
                    minHeight: WebcardDocumentWindowMetrics.minimumHeight,
                    idealHeight: WebcardDocumentWindowMetrics.defaultHeight
                )
        }
        .defaultSize(
            width: WebcardDocumentWindowMetrics.defaultWidth,
            height: WebcardDocumentWindowMetrics.defaultHeight
        )
        .commands {
            WebcardCommands()
            WebcardFolderCommands()
        }
    }
}

struct WebcardDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.webcard]
    }

    var file: WebcardFile

    init(file: WebcardFile = WebcardFile()) {
        self.file = file
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw WebcardError.invalidArchive("The webcard file could not be read.")
        }
        file = try WebcardArchive.read(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard file.sourceURL != nil, !file.captures.isEmpty else {
            throw CocoaError(
                .fileWriteUnknown,
                userInfo: [
                    NSLocalizedDescriptionKey: "Create the first capture from the app start window before saving this webcard."
                ]
            )
        }
        return FileWrapper(regularFileWithContents: try WebcardArchive.write(file))
    }
}
