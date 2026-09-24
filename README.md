# Webcard

Webcard is a native macOS document app for creating, opening, refreshing, and versioning `.webcard` files.

Each document window displays one saved card. Use the macOS **Card** menu for **Refresh** (Command-R), **Truncate Text**, and the **Versions** selector. These commands affect the active document window; the window has no control footer or app toolbar. Refresh status appears in the window subtitle. Changed metadata or image content becomes a new dated capture in the document, which can then be saved normally.

**Card > Selectable Metadata** opens the selected version's full, untruncated metadata in a separate read-only window. Text can be selected and copied, and **Copy All** copies the complete metadata and capture date. This is a snapshot of that version, independent of subsequent selection or refresh changes in the document.

Compact windows keep a readable card width and use a centered image crop rather than shrinking the card excessively. Regular windows expand the card to the available width with standard outer insets. The fitted content height is split between the image and metadata using a calibrated ratio, currently about 68% for the image and 32% for metadata. Text is shortened by rendered lines to fit its share while keeping at least one line each of the title and description. The complete URL wraps instead of being truncated, and Open in Browser remains visible whenever the minimum content can fit. Turn off Truncate Text to show the complete image and text with vertical scrolling. If the minimum content still cannot fit, the card scrolls rather than hiding it.

Finder thumbnails and Space bar previews render from the saved archive without network access.

## Layout debugging

Choose **Card > Layout Debug** to open a separate Layout Debug window, then enable **Preview my desired layout**. Set **Desired card width** in points independently of the automatic layout, or choose **Use Window Width**. Wider cards scroll horizontally rather than being silently narrowed. Set the maximum rendered **Title lines** and **Description lines** separately. Text is measured at your selected width and shortened with an ellipsis only when it exceeds its line limit; zero lines hides that section. Enable **Mask (crop) image** to adjust image height and top, center, or bottom cropping. The URL stays complete. These per-window overrides do not change the saved document or the default algorithm; turn off the preview to return to the automatic layout.

Add optional **What it is** and **What it should be** notes, then choose **Capture JSON**. This saves a plain `.json` file with separate `current` and `desired` objects. Each contains card width, image height and masking, title and description line limits, measured line counts, visible text, overflow, and notes. The surrounding context includes viewport and image dimensions, original text, URL, and app version so the case can be reproduced. `current` always describes the unmodified automatic layout, even while the desired preview is enabled.

Share the JSON file or paste its contents. No PNG, screenshot, or image data is captured. The file is saved locally; nothing is uploaded automatically.

The debug preview updates live. Text measurements are reused while settings are unchanged, and line-limited text measures only the visible prefix so long descriptions do not stall the controls.

To generate a local sample comparison from the regression fixture:

```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all WEBCARD_DEBUG_CAPTURE_OUTPUT=/tmp/webcard-layout-sample.json swift test --filter LayoutDebugTests/testCaptureJSONContainsCurrentAndDesiredSettings
```

To replay the compact calibration against a captured case and save a before/after JSON comparison, supply the input capture and a new output path. The replay uses the captured text and image dimensions with an 18 pt placeholder favicon, without fetching the website or image:

```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all WEBCARD_LAYOUT_REGRESSION_INPUT=/path/to/capture.json WEBCARD_LAYOUT_REGRESSION_OUTPUT=/tmp/webcard-layout-before-after.json swift test --filter LayoutDebugTests/testCompactCalibrationAndBeforeAfterCapture
```

## Requirements

macOS 14 or later and Xcode 16 or later.

## Build and test

```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all swift test
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all xcodebuild -project 2026-09-23-Webcard.xcodeproj -target Webcard -configuration Debug SYMROOT="$PWD/.build/xcode-target" OBJROOT="$PWD/.build/xcode-target/obj" ONLY_ACTIVE_ARCH=YES ARCHS=arm64 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
```

## Open the app

```sh
open .build/xcode-target/Debug/Webcard.app
```
