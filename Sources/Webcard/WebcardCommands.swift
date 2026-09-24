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
        }
    }
}

struct WebcardFolderCommands: Commands {
    @ObservedObject private var folderSettings = WebcardFolderSettings.shared
    @ObservedObject private var commandCenter = WebcardFolderCommandCenter.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Create Webcard") {
                WebcardAppDelegate.shared?.showStartWindow()
            }
            .keyboardShortcut("n")

            Button("Open…") {
                presentOpenPanel()
            }
            .keyboardShortcut("o")
        }

        CommandGroup(after: .toolbar) {
            Divider()

            Button(
                folderSettings.isDirectoryDrawerVisible
                    ? "Hide Directory Drawer"
                    : "Show Directory Drawer"
            ) {
                folderSettings.isDirectoryDrawerVisible.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(!commandCenter.hasActiveFolder)

            Divider()

            Menu("Folder Layout") {
                layoutButton(.masonry)
                layoutButton(.grid)
            }
            .disabled(!commandCenter.hasActiveFolder)

            Menu("Folder Presentation") {
                presentationButton(.inline)
                presentationButton(.cards)
            }
            .disabled(!commandCenter.hasActiveFolder)

            Menu("Folder Columns") {
                ForEach(WebcardFolderColumnMode.allCases, id: \.self) { mode in
                    columnButton(mode)
                }
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

    private func presentationButton(
        _ mode: WebcardFolderPresentationMode
    ) -> some View {
        Button {
            folderSettings.presentationMode = mode
        } label: {
            if folderSettings.presentationMode == mode {
                Label(mode.menuTitle, systemImage: "checkmark")
            } else {
                Text(mode.menuTitle)
            }
        }
    }

    private func columnButton(_ mode: WebcardFolderColumnMode) -> some View {
        Button {
            folderSettings.columnMode = mode
        } label: {
            if folderSettings.columnMode == mode {
                Label(mode.menuTitle, systemImage: "checkmark")
            } else {
                Text(mode.menuTitle)
            }
        }
    }

    private func presentOpenPanel() {
        guard let urls = WebcardOpenPanel.selectItems() else {
            return
        }
        WebcardOpenRouter.open(urls)
    }
}
