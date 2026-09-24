import SwiftUI
import UniformTypeIdentifiers
import WebcardCore

@main
struct WebcardApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: WebcardDocument()) { configuration in
            WebcardDocumentView(document: configuration.$document)
                .frame(minWidth: 360, idealWidth: 460, minHeight: 420, idealHeight: 620)
        }
        .commands {
            WebcardCommands()
        }

        WindowGroup("Selectable Metadata", id: "webcard-metadata", for: MetadataSnapshot.self) { $snapshot in
            if let snapshot {
                MetadataWindow(snapshot: snapshot)
            }
        }
        .defaultSize(width: 560, height: 520)
        .commandsRemoved()
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
                    NSLocalizedDescriptionKey: "Choose Card > Refresh to create the first capture before saving this webcard."
                ]
            )
        }
        return FileWrapper(regularFileWithContents: try WebcardArchive.write(file))
    }
}
