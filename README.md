# Webcard

Webcard is a native macOS document app for creating, opening, refreshing, and versioning `.webcard` files.

The portable file format is formally documented under [`spec/`](spec/README.md). The application reads and writes Webcard Format 1.0.0. Legacy prototype archives are intentionally unsupported.

When Webcard opens without a document, it displays only the app start window, with no blank Untitled document alongside it. Enter a public website address there to create a webcard, choose **Choose File or Folder** to open saved webcards, or drag a `.webcard` file or folder of webcards onto the drop area. **File > Create Webcard** returns to the same app start window instead of opening a separate empty document. Use **File > Import URLs** to paste one public URL per line and save many webcards into a chosen folder. Bulk imports run one capture at a time and wait at least eight seconds before starting another capture for the same domain.

Each document window displays one saved card and defaults to a 550 by 550 point window when macOS does not have a restored user size. Use the macOS **Card** menu for **Refresh** (Command-R), **Truncate Text**, and **Versions**. These commands affect the active document window; the window has no control footer or app toolbar. Refresh status appears in the window subtitle. Changed metadata or image content becomes a new dated capture in the document, which can then be saved normally.

Choose **File > Open** (Command-O) to open one or more `.webcard` files, folders, or a mixture of both from the same picker. You can also drag a `.webcard` file or folder onto the Webcard app icon in Finder. Folder windows include an expandable sidebar tree for navigating the opened folder and its discovered subfolders. The gallery renders immediate webcards first, then performs bounded background discovery for nested folders without following symlinks, entering packages, crossing volumes, or scanning hidden directories. Inline presentation appends each discovered directory as a named section after cards in the current directory and shows its path relative to the current visual root. At most two nested directory levels are shown inline; deeper folders become continuation items that open as a new visual root. Use **View > Folder Presentation** to switch between inline sections and folder cards independently of **View > Folder Layout**, which controls masonry or equal-height grid card flow. Grid cards use a consistent cropped image height, share the tallest visible metadata height, and limit descriptions to two lines. Use **View > Folder Columns** to choose Deyn, the default responsive one-to-four-column layout, or a fixed count from one through four. Use the search field to rank discovered cards by filename, title, description, site name, URL, folder path, or social metadata. Search is case and diacritic insensitive, understands quoted phrases and punctuation, and tolerates small spelling mistakes while avoiding broad short-query fuzzy matches. Folder cards and individual document cards use the same renderer. Folder layout changes emit lightweight unified logging entries in the `FolderLayout` category with the active directory name, layout and presentation modes, column count, viewport size, card width, visible webcard count, and discovery state.

**Card > Selectable Metadata** opens the selected version's full, untruncated metadata in a separate read-only window. Text can be selected and copied, and **Copy All** copies the complete metadata and capture date. This is a snapshot of that version, independent of subsequent selection or refresh changes in the document.

Compact windows keep a readable card width and use a centered image crop rather than shrinking the card excessively. Regular windows expand the card to the available width with standard outer insets. The fitted content height is split between the image and metadata using a calibrated ratio, currently about 68% for the image and 32% for metadata. Text is shortened by rendered lines to fit its share while keeping at least one line each of the title and description. The complete URL wraps instead of being truncated, and Open in Browser remains visible whenever the minimum content can fit. Turn off Truncate Text to show the complete image and text with vertical scrolling. If the minimum content still cannot fit, the card scrolls rather than hiding it.

Finder thumbnails and Space bar previews render from the saved archive without network access. Quick Look previews default to the same 550 by 550 point size as document windows and use the shared card layout.

Refresh also captures useful social metadata when a page provides it, including `og:image:alt` or `twitter:image:alt`, Open Graph content type and locale, article author and timestamps, article section, Twitter card type, and declared image type and dimensions. Image alt text becomes the card image's accessibility label. These fields are searchable in folder view and appear in **Card > Selectable Metadata** without cluttering the main card.

## Requirements

macOS 14 or later and Xcode 16 or later.

## Build and test

```sh
python3 scripts/validate-spec.py
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all swift test
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all xcodebuild -project Webcard.xcodeproj -target Webcard -configuration Debug SYMROOT="$PWD/.build/xcode-target" OBJROOT="$PWD/.build/xcode-target/obj" ONLY_ACTIVE_ARCH=YES ARCHS=arm64 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
```

## Open the app

```sh
open .build/xcode-target/Debug/Webcard.app
```

## Rebuild and reinstall

Agents should finish app changes with one command:

```sh
WEBCARD_INSTALL_OWNER="agent or task name" ./scripts/reinstall-app.sh
```

The script runs the tests, rebuilds the app, installs it, and opens the installed build. The `main` worktree safely replaces `/Applications/Webcard.app`. Every other worktree automatically installs an isolated build at `~/Applications/Webcard Worktrees/<worktree>/Webcard.app`, gives it a distinct display name, bundle identifier, and visibly badged app icon, and leaves the main app untouched. Each destination has its own machine-wide per-user lock, so different worktrees can build and install concurrently while agents targeting the same destination receive details about the current lock owner.

To intentionally override the selected destination, set an absolute path ending in `Webcard.app`:

```sh
WEBCARD_INSTALL_PATH="$HOME/Applications/Webcard.app" ./scripts/reinstall-app.sh
```

To test an isolated named build from the `main` worktree, set a variant:

```sh
WEBCARD_INSTALL_VARIANT="experiment" ./scripts/reinstall-app.sh
```
## Releases

Pushes to `main` run Release Please, which maintains a release pull request from Conventional Commit history. Merging that pull request creates a semantic version tag and GitHub release, then builds `Webcard-<version>-macOS-universal.zip` with its SHA-256 checksum. Both files are available from the workflow run, and the release assets are downloadable from the GitHub release.

To rebuild assets for an existing tag, run the **Release Assets** workflow manually and provide a tag such as `v0.2.0`.
