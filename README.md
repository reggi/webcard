<p align="center">
  <img src="Assets/AppIcon.png" width="160" height="160" alt="Webcard app icon">
</p>

<h1 align="center">Webcard</h1>

<p align="center"><strong>A native macOS home for portable, versioned web bookmarks.</strong></p>

<p align="center">Capture a public webpage as a beautiful card, keep its history, and carry it as a file you control.</p>

Webcard turns a website address into a `.webcard` document containing the page's preview image, title, description, URL, social metadata, and capture history. Each card opens as a native Mac document, can be refreshed as the page changes, and remains useful in Finder through thumbnails and Quick Look previews.

Instead of keeping bookmarks inside a browser or account, Webcard saves them as portable files. Open a single card, organize a folder into a visual collection, search across saved metadata, or share the file like any other document.

## What you can do

| | |
| --- | --- |
| **Capture** | Create a webcard from any public website address. |
| **Refresh** | Save new dated captures when a page's metadata or image changes. |
| **Collect** | Open folders as searchable visual galleries with flexible layouts. |
| **Inspect** | View and copy the complete metadata stored with any saved version. |
| **Preview** | See Finder thumbnails and Quick Look previews without network access. |
| **Own** | Keep each bookmark as a portable, open format file on your Mac. |

## The Webcard format

The portable file format is documented under [`spec/`](spec/README.md). Webcard reads and writes [Webcard Format 1.0.0](spec/1.0.0/README.md), an open ZIP based container designed for bookmarks, link previews, capture history, and interoperable extensions. Legacy prototype archives are intentionally unsupported.

## Using the app

### Create and open

* Enter a public website address in the start window to create a webcard.
* Choose **Choose File or Folder**, use **File > Open** (Command-O), or drag `.webcard` files and folders into Webcard.
* Use **File > Create Webcard** to return to the start window at any time.
* Use **File > Import URLs** to paste one public URL per line and save a collection into a chosen folder. Imports run sequentially and pause between captures from the same domain.

### Refresh and explore history

* Use **Card > Refresh** (Command-R) to capture the latest image and metadata. Changes become a new dated version.
* Use **Card > Versions** to move through saved captures.
* Use **Card > Selectable Metadata** to view and copy the selected version's complete metadata and capture date.
* Webcard preserves useful social metadata such as image descriptions, content type, locale, author, timestamps, article section, and declared image dimensions.

### Browse collections

* Open a folder to browse its webcards as a visual gallery with an expandable navigation sidebar.
* Use **View > Folder Presentation** to choose inline sections or folder cards.
* Use **View > Folder Layout** to choose masonry or an equal height grid.
* Use **View > Folder Columns** to choose the responsive Deyn layout or a fixed count from one through four.
* Search by filename, title, description, site name, URL, folder path, or social metadata. Search supports quoted phrases, punctuation, diacritics, and small spelling mistakes.
* Nested folders are discovered safely in the background without following symlinks, entering packages, crossing volumes, or scanning hidden directories.

### Read and preview

* Document windows default to 550 by 550 points and adapt the card layout as the window changes size.
* Use **Card > Truncate Text** to switch between a fitted card and the complete scrollable content.
* Full URLs wrap instead of being cut off, and **Open in Browser** remains available whenever the minimum content fits.
* Finder thumbnails and Quick Look previews render from the saved archive without network access.

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
