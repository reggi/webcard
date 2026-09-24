import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebcardCore

struct WebcardVersionMenuItem: Identifiable {
    let id: String
    let title: String
}

struct WebcardCommandState {
    let truncatesText: Binding<Bool>
    let canChangeTruncation: Bool
    let canRefresh: Bool
    let isRefreshing: Bool
    let versions: [WebcardVersionMenuItem]
    let selectedCaptureID: String?
    let refresh: () -> Void
    let selectCapture: (String) -> Void
    let openLayoutDebug: () -> Void
    let openMetadata: () -> Void
}

private struct WebcardCommandKey: FocusedValueKey {
    typealias Value = WebcardCommandState
}

extension FocusedValues {
    var webcardCommands: WebcardCommandState? {
        get { self[WebcardCommandKey.self] }
        set { self[WebcardCommandKey.self] = newValue }
    }
}

struct WebcardCommands: Commands {
    @FocusedValue(\.webcardCommands) private var state

    var body: some Commands {
        CommandMenu("Card") {
            Button(state?.isRefreshing == true ? "Refreshing…" : "Refresh") {
                state?.refresh()
            }
            .keyboardShortcut("r")
            .disabled(state?.canRefresh != true)

            Toggle("Truncate Text", isOn: state?.truncatesText ?? .constant(true))
                .disabled(state?.canChangeTruncation != true)

            Menu("Versions") {
                if let state {
                    ForEach(state.versions) { version in
                        Button {
                            state.selectCapture(version.id)
                        } label: {
                            if version.id == state.selectedCaptureID {
                                Label(version.title, systemImage: "checkmark")
                            } else {
                                Text(version.title)
                            }
                        }

                    }
                }
            }
            .disabled(state?.versions.isEmpty != false)

            Divider()

            Button("Selectable Metadata…") {
                state?.openMetadata()
            }
            .disabled(state?.selectedCaptureID == nil)

            Button("Layout Debug…") {
                state?.openLayoutDebug()
            }
            .disabled(state?.selectedCaptureID == nil)
        }
    }
}

struct WebcardFolderCommands: Commands {
    @ObservedObject private var folderSettings = WebcardFolderSettings.shared
    @ObservedObject private var commandCenter = WebcardFolderCommandCenter.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Webcard") {
                NSDocumentController.shared.newDocument(nil)
            }
            .keyboardShortcut("n")

            Button("Open…") {
                presentOpenPanel()
            }
            .keyboardShortcut("o")
        }

        CommandGroup(after: .toolbar) {
            Divider()

            Menu("Folder Layout") {
                layoutButton(.masonry)
                layoutButton(.grid)
            }
            .disabled(!commandCenter.hasActiveFolder)
        }
    }

    private func layoutButton(_ mode: WebcardFolderLayoutMode) -> some View {
        Button {
            folderSettings.layoutMode = mode
        } label: {
            if folderSettings.layoutMode == mode {
                Label(mode.menuTitle, systemImage: "checkmark")
            } else {
                Text(mode.menuTitle)
            }
        }
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Webcard or Folder"
        panel.prompt = "Open"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.webcard]
        guard panel.runModal() == .OK else {
            return
        }
        WebcardOpenRouter.open(panel.urls)
    }
}
