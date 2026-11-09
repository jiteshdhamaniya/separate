<p align="center">
  <img src="Resources/AppIcon.png" width="144" alt="Separate: two independent image and document windows">
</p>

<h1 align="center">Separate</h1>
<p align="center"><strong>One file. One window.</strong><br>A small native macOS viewer for PDFs and images.</p>
<p align="center">
  <a href="https://github.com/jiteshdhamaniya/separate/releases/latest">Download</a> ·
  <a href="#build-from-source">Build from source</a> ·
  <a href="LICENSE">MIT License</a>
</p>

Separate is for people who want documents in their own windows. Open one file or a whole batch: each gets a fresh window. Reopening the same file creates another independent window. Automatic tabs are disabled in the app and on every window, regardless of your macOS tab preference.

## Features

- PDF viewing with continuous scrolling, selectable text, page thumbnails and previous/next navigation.
- Image viewing with zoom, fit and actual size. Common formats are decoded by macOS, including PNG, JPEG, HEIC, TIFF, GIF, BMP and WebP.
- Open multiple files from Finder, the Open dialog, or by dragging them onto the app icon or welcome window.
- Native AppKit interface with PDFKit rendering. No web wrapper, account, telemetry or third-party packages.
- Files are opened for viewing; Separate does not save changes to your originals.

## Download and install

Requires **macOS 13 or later**. The release ZIP contains a universal app for Apple Silicon and Intel.

1. Download `Separate-0.1.0-macos-universal.zip` from [Releases](https://github.com/jiteshdhamaniya/separate/releases/latest).
2. Unzip it and drag **Separate.app** into **Applications**.
3. Launch Separate and choose **Open Files…**, or use Finder → **Open With → Separate**.

The initial release is **ad-hoc signed, not Developer ID signed or notarized by Apple**. macOS may block a downloaded copy. Review the source or build it yourself; if you choose to trust the downloaded app, follow [Apple’s per-app opening instructions](https://support.apple.com/102445). Do not disable Gatekeeper globally.

SHA-256 checksums are included with each release. Compare the ZIP using `shasum -a 256 Separate-0.1.0-macos-universal.zip`.

### Make Separate the default

In Finder, select a PDF or image → **Get Info** → **Open with: Separate** → **Change All…**. Repeat for the file types you want. Installing Separate does not change your default apps automatically.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Open files | ⌘O |
| Close the current window | ⌘W |
| Fit to window | ⌘0 |
| Actual size | ⌘1 |
| Zoom in / out | ⌘+ / ⌘− |
| Copy selected PDF text | ⌘C |
| Quit | ⌘Q |

## Scope of this first release

Separate is a viewer. It does not yet provide annotations, signatures, image editing, printing/export, search, or session restoration. For those tasks, use **Open With → Preview** or another editor. Animated and multipage images use the representation macOS selects; animation playback is not provided. Password-protected PDFs use PDFKit’s password UI.

The universal build is compiled for both architectures. Interactive testing for this release was performed on Apple Silicon running macOS 26.1; Intel and macOS 13 runtime behavior have not been independently verified.

## Build from source

Install Apple’s Xcode Command Line Tools, then:

```sh
git clone https://github.com/jiteshdhamaniya/separate.git
cd separate
bash scripts/build.sh
open build/Separate.app
```

The build compiles both architectures, creates a multi-resolution `.icns` from the committed icon artwork, combines the executables, and ad-hoc signs the app. It needs no package downloads. The source uses Swift 5 language mode with a modern Swift compiler; Swift 6.2 was used for the initial local release build.

## Test and package

```sh
bash scripts/test.sh
bash scripts/package.sh
```

Tests create their own synthetic PDFs and PNGs, instantiate 24 independent windows without showing them, check the no-tabs policy and repeated file opens, exercise image scaling/PDF navigation, reject invalid and missing files, and confirm the input files are unchanged. AppKit tests require a logged-in macOS graphical session. Packaging produces a universal ZIP and checksum in `dist/`.

The original viewer was also tested interactively by opening 24 mixed PDFs and PNGs from Finder and checking that they remained separate windows.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). Keep one-file-per-window behavior as the default and avoid adding background services or dependencies without a clear need.

## License and artwork

Code and included artwork are provided under the [MIT License](LICENSE). The app icon was created with AI-assisted image generation; its prompt and packaging details are recorded in [docs/branding.md](docs/branding.md).
