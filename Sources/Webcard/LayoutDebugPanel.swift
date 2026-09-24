import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ImageCropPosition: String, CaseIterable, Codable {
    case top
    case center
    case bottom

    var alignment: Alignment {
        switch self {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        }
    }

    var fraction: CGFloat {
        switch self {
        case .top: 0
        case .center: 0.5
        case .bottom: 1
        }
    }
}

struct WebcardDebugSettings: Codable {
    var enabled = false
    var titleLines = 2
    var descriptionLines = 4
    var cardWidth: Double = 500
    var maskImage = false
    var imageHeight: Double = 180
    var cropPosition: ImageCropPosition = .center
    var actualNotes = ""
    var desiredNotes = ""
}

struct LayoutDebugPanel: View {
    @Binding var viewport: CGSize
    @Binding var settings: WebcardDebugSettings
    let makeCapture: () throws -> Data

    @State private var errorMessage: String?
    @State private var savedURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                controls
            }
            .frame(height: 500)

            HStack {
                Button("Reset") {
                    settings = WebcardDebugSettings()
                    savedURL = nil
                }
                Spacer()
                Button("Capture JSON…", action: saveCapture)
                    .buttonStyle(.borderedProminent)
                    .disabled(viewport.width <= 0 || viewport.height <= 0)
            }
            if let savedURL {
                Button("Show Saved Capture in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                }
                .font(.caption)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(18)
        .frame(minWidth: 360, idealWidth: 380, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .alert("Layout Debug", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "The debug capture could not be saved.")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Layout Debug").font(.headline)
            Text("Adjust the desired result without changing the saved card.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Preview my desired layout", isOn: $settings.enabled)

            HStack {
                Text("Desired card width")
                Spacer()
                TextField("Points", value: Binding(
                    get: { settings.cardWidth },
                    set: { value in
                        if value.isFinite && (180...4000).contains(value) {
                            settings.cardWidth = value
                        } else {
                            errorMessage = "Enter a card width between 180 and 4000 points."
                        }
                    }
                ), format: .number.precision(.fractionLength(0)))
                    .frame(width: 70)
                Text("pt").foregroundStyle(.secondary)
            }
            Slider(
                value: $settings.cardWidth,
                in: 180...min(4000, max(1200, viewport.width, settings.cardWidth)),
                step: 1
            )
            Button("Use Window Width") {
                settings.cardWidth = min(4000, max(180, viewport.width - 36))
            }
            .font(.caption)
            Text("This width is independent of the automatic layout. Wider cards scroll horizontally instead of shrinking.")
                .font(.caption)
                .foregroundStyle(.secondary)

            lineControl("Title", value: $settings.titleLines)
            lineControl("Description", value: $settings.descriptionLines)

            Toggle("Mask (crop) image", isOn: $settings.maskImage)
            if settings.maskImage {
                HStack {
                    Text("Image height")
                    Spacer()
                    TextField("Points", value: Binding(
                        get: { settings.imageHeight },
                        set: { value in
                            if value.isFinite && (1...max(1000, viewport.height)).contains(value) {
                                settings.imageHeight = value
                            } else {
                                errorMessage = "Enter an image height between 1 and \(Int(max(1000, viewport.height))) points."
                            }
                        }
                    ), format: .number.precision(.fractionLength(0)))
                        .frame(width: 70)
                    Text("pt").foregroundStyle(.secondary)
                }
                Slider(value: $settings.imageHeight, in: 1...max(1000, viewport.height), step: 1)
                Picker("Crop position", selection: $settings.cropPosition) {
                    ForEach(ImageCropPosition.allCases, id: \.self) { position in
                        Text(position.rawValue.capitalized).tag(position)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                Text("The complete image keeps its original proportions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            TextField("What it is (optional notes)", text: $settings.actualNotes, axis: .vertical)
                .lineLimit(2...4)
            TextField("What it should be (optional notes)", text: $settings.desiredNotes, axis: .vertical)
                .lineLimit(2...4)

            Text("Capture saves a JSON object with current and desired settings, dimensions, measured line counts, and notes. It includes the card's text and URL, but no image or screenshot. Nothing is uploaded.")
                .font(.caption)
                .foregroundStyle(.secondary)

        }
    }

    private func lineControl(_ title: String, value: Binding<Int>) -> some View {
        let checked = Binding(
            get: { value.wrappedValue },
            set: { count in
                if (0...100).contains(count) {
                    value.wrappedValue = count
                } else {
                    errorMessage = "Enter a \(title.lowercased()) line limit between 0 and 100."
                }
            }
        )
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(title) lines")
                Spacer()
                TextField("Lines", value: checked, format: .number)
                    .frame(width: 70)
                Stepper("", value: checked, in: 0...100)
                    .labelsHidden()
            }
            Text("Maximum rendered lines at the desired width. Overflow ends with an ellipsis; 0 hides this section.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func saveCapture() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "webcard-layout-\(Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-"))"
        panel.title = "Save Layout Comparison JSON"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try makeCapture().write(to: url, options: .atomic)
            savedURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
