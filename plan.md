# Native macOS Webcard App Plan

## Goal

Build a native macOS app for opening, viewing, refreshing, and saving `.webcard` files. This app replaces the Electron direction with a focused native experience built for one webcard per window.

The app must never refresh or update a webcard in the background. A new capture is created only when the user presses Refresh.

## Core experience

Each window displays one webcard in a small resizable window.

The card shows its cached image, title, description, site name, and original URL. The footer contains a Refresh button. The interface also shows the number of saved captures and provides a history view where the user can move between captures by date.

Opening an existing `.webcard` must render entirely from the file without contacting the original website. Network access occurs only after the user explicitly presses Refresh.

## Native macOS implementation

Use Swift and SwiftUI for the application and AppKit where macOS document or window behavior requires it.

The app should register `.webcard` as a document type so files can be opened from Finder, dragged onto the app, or selected through the standard Open panel.

Each document window owns one webcard file. Normal macOS document behavior should handle opening, saving, Save As, unsaved change state, and window restoration.

## Finder and Quick Look

Include a Quick Look Thumbnail Extension that reads the current capture image from the local `.webcard` archive and uses it as the file thumbnail in Finder.

Include a Quick Look Preview Extension that displays the current saved card when the user presses Space in Finder. Its layout should match the main app with a centered proportional image and attached metadata inside one unified card.

Both extensions must render only saved archive content. They must never contact the original website, refresh metadata, modify the file, or create a new capture.

If the archive is invalid or unsupported, Finder should fall back to the application document icon instead of displaying partial or unvalidated content.

## Webcard format

Keep the `.webcard` extension and ZIP archive format from the existing specification.

The current version 1 format contains exactly `manifest.json` and `card.webp`, so storing history requires a new format version. Version 2 should store an ordered collection of immutable captures inside the same archive.

```text
example.webcard
├── manifest.json
├── captures
│   ├── 2026-09-23T21-54-49-256Z
│   │   └── manifest.json
│   └── 2026-09-24T14-10-00-000Z
│       └── manifest.json
└── images
    └── 4b2f7d8c...a13e.webp
```

The root manifest identifies format version 2, the original URL, the current capture, and the ordered capture identifiers.

Each capture manifest stores the normalized canonical URL, title, description, site name, shared card image path, image SHA256, optional shared site icon path, optional icon SHA256, and capture date. A capture is immutable after it is written.

Images are stored once under `images/<sha256>.webp`. Captures with changed text but unchanged image content reference the existing image path instead of duplicating the image bytes.

Refresh prefers an Apple touch icon and falls back to a declared favicon. The icon is normalized to WebP, stored by SHA256 in the shared images directory, and displayed with the saved card in the app and Quick Look.

When multiple icons are declared, the highest resolution Apple touch icon is preferred, followed by the highest resolution favicon. Icons are shown at favicon scale directly beside the site name and are never enlarged beyond their saved dimensions.

Version 1 files remain readable. When a version 1 file is refreshed and saved, its existing manifest and image become the first capture in a version 2 archive.

## Refresh behavior

Refresh is always initiated by the user.

When Refresh is pressed, the app fetches the original URL, follows the existing metadata selection rules, creates the normalized WebP image, and calculates its SHA256.

The address field accepts explicit HTTP and HTTPS URLs. An address entered without a scheme defaults to HTTPS.

Plain and HTTP addresses are promoted to HTTPS for the first request. If HTTPS succeeds, the secure source URL is stored in the webcard. If the secure request fails, the app may retry the same validated public address over HTTP. HTTP fallback occurs only after the user presses Refresh and never bypasses private network rejection.

The refreshed title, description, site name, canonical URL, and image SHA256 are compared with the current capture.

If any compared text value or the image SHA256 changed, the app appends a new dated capture and marks the document as modified. The user then saves through normal macOS document behavior.

If nothing changed, the app reports that the webcard is current and does not add a duplicate capture. Only the last refreshed timestamp changes.

Every successful refresh updates the root `lastRefreshedAt` timestamp. An unchanged refresh updates this date without creating a duplicate capture or image.

Refreshing must not silently write to disk. Pressing Refresh adds a changed capture to the open document, and the file is updated through normal macOS document saving.

## Capture history

Show one capture history dropdown near the bottom of the window. Its label combines the selected capture number and date.

The dropdown lists every saved version as `Capture N · date`, ordered with the newest first. Choosing an item displays that capture without changing or deleting any saved data.

The current capture is the newest saved capture unless the user is previewing an older one. The interface must clearly show when an older capture is being viewed.

## Window layout

The primary content is the singular card.

The card image and metadata remain inside one centered card with a shared width and clear boundary. The text is always attached directly below the image. The image preserves its aspect ratio and shrinks before the metadata, so the title, description, and link remain visible as the window changes size.

The card includes a clear blue Open in Browser button below its metadata. The footer contains Refresh, the last capture date, and access to capture history. Refresh progress and errors appear in the window and must not replace the saved card.

All metadata beneath the image is rendered as one continuous selectable and copyable text region, including the site name, warning, title, description, canonical URL, and date where shown.

Right clicking the card image provides a Copy Image action using the saved local image.

The viewer uses one canonical card layout with a preferred width of 700 points. The image always uses a 1.91 to 1 aspect ratio with aspect fill cropping. The metadata uses stable typography and preview limits of two title lines, four description lines, and one URL line with trailing truncation. Complete metadata remains stored in the archive.

Card height is determined naturally by the image, visible metadata, an 18 point gap, the browser button, and bottom padding. The card and metadata section do not use fixed heights, minimum heights, internal spacers, or bottom pinning.

When the content area is smaller than the canonical card, the complete card scales down proportionally without reflowing its internal typography. The card remains centered horizontally and vertically. Scrolling is used only when the window is too small to display the card at its minimum usable scale of 560 points wide.

If the complete card is taller than the available window, the card scrolls as one unit so no metadata or controls are clipped by the footer.

When HTTPS promotion fails and a card uses HTTP fallback, the card and its Quick Look preview show a visible warning that refresh traffic is unencrypted.

## Safety and limits

Retain the existing URL validation, private network rejection, redirect limit, response size limits, image conversion rules, and archive validation.

Do not extract archive entries to arbitrary filesystem paths. Validate every entry name, manifest, image size, and SHA256 before displaying a capture.

A failed refresh must leave the open document and every saved capture unchanged.

## Implementation order

1. Create the native macOS document app and register the `.webcard` file type.
2. Implement version 1 archive reading and offline card display.
3. Define and implement the version 2 archive reader, writer, and capture validation.
4. Add the small resizable single card window and footer controls.
5. Add explicit Refresh with metadata fetching, image conversion, SHA256 comparison, and pending update state.
6. Add capture count, dated history list, and switching between saved captures.
7. Add the Finder thumbnail and Quick Look preview extensions using the shared archive reader.
8. Add version 1 to version 2 conversion on the first changed refresh.
9. Verify opening, refreshing, saving, Save As, reopening, Finder thumbnails, Quick Look previews, offline display, unchanged refreshes, changed text, changed images, and failed refreshes.

## Completion criteria

The app is fully native and does not depend on Electron.

A `.webcard` opens as one card in a small resizable macOS window.

No network request or update occurs without the user pressing Refresh.

Changed text or image SHA256 creates a dated capture inside the same `.webcard` file.

An unchanged refresh creates no duplicate capture.

The user can see the capture count, list captures by date, and view any saved capture.

Finder displays the current saved card image as the `.webcard` thumbnail, and Quick Look displays the saved card without network access.

All saved captures remain available after closing and reopening the file.
