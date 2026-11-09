<p align="center">
  <img src="Resources/AppIcon.png" width="144" alt="Separate: two independent image and document windows">
</p>

<h1 align="center">Separate</h1>
<p align="center"><strong>One file. One window.</strong><br>A small native macOS viewer for PDFs and images.</p>
<p align="center">
  <a href="#build-from-source">Build from source</a> ·
  <a href="LICENSE">MIT License</a>
</p>

Separate is for people who want documents in their own windows. Open one file or a whole batch: each gets a fresh window. Reopening the same file creates another independent window. Automatic tabs are disabled in the app and on every window, regardless of your macOS tab preference.

## Why I built Separate

I was frustrated with Preview opening PDFs and images in tabs or grouping multiple images into one window. What I wanted was simple: every file I open should get its own window. That included PDFs, images, opening a batch of files, and opening the same file again.

We tried Preview and macOS window settings, but the grouping behavior still showed up in my workflow. Eventually I thought: if this is the behavior I want, why not make a small viewer that does it by default? That became Separate: **one file, one window**.

I used LLMs to help write the app. It started with that one windowing rule, then gained the everyday features I wanted while using it: pinch-to-zoom, two-finger double-tap zoom, and selecting and copying text from images with Apple's Live Text.

This is a small, opinionated viewer, with a narrower feature set than Preview. I'm sharing the source so you can inspect it, change it, and build your own copy. **I recommend building it yourself using the instructions below.**

## Features

- PDF viewing with continuous scrolling, selectable text, page thumbnails and previous/next navigation.
- Image viewing with zoom, fit and actual size. Common formats are decoded by macOS, including PNG, JPEG, HEIC, TIFF, GIF, BMP and WebP.
- Trackpad pinch-to-zoom for both PDFs and images, anchored at the pointer. Place the pointer over the document and pinch with two fingers to zoom in or out; use ⌘0 to return to Fit.
- Two-finger double-tap zoom for PDFs and images: zoom in at the pointer, then double-tap again to restore the previous zoom or Fit mode.
- Live Text in images: select recognized text directly on the image and copy it with ⌘C or the context menu. Recognition runs locally using Apple's VisionKit and does not require Apple Intelligence.
- Open multiple files from Finder, the Open dialog, or by dragging them onto the app icon or welcome window.
- Native AppKit interface with PDFKit rendering. No web wrapper, account, telemetry or third-party packages.
- Files are opened for viewing; Separate does not save changes to your originals.

## Build from source

### 1. Install Apple's developer tools

You need a Mac running **macOS 13 or later** and a recent version of Apple's Xcode Command Line Tools (or full Xcode). The build produces one universal app for Apple Silicon and Intel. Development and local testing used Swift 6.2 on Apple Silicon; the macOS 13 minimum and Intel runtime have not been independently tested.

Open **Terminal** and run:

```sh
xcode-select --install
```

Finish the installer before continuing. If the tools are already installed, you can skip this step. See [Apple's installation guide](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools) if you need to install or update them.

Check that Terminal can find Swift:

```sh
xcrun swiftc --version
```

### 2. Get the source

Run these commands from the folder where you want to keep the project:

```sh
git clone https://github.com/jiteshdhamaniya/separate.git
cd separate
```

You can inspect the app in `Sources/main.swift` and the build steps in `scripts/build.sh` before running them. There are no third-party packages to install, API keys, or cloud accounts to configure.

### 3. Build and test

From the `separate` folder, run:

```sh
bash scripts/build.sh
bash scripts/test.sh
```

The first command creates **`build/Separate.app`**. It compiles both architectures, creates the app icon, and signs the result with a local ad-hoc signature. **You do not need a paid Apple Developer membership or a signing certificate to build and run your own copy.** This does not produce an Apple-notarized app for distribution.

The tests use generated PDFs and images, including an image containing text. Run them from Terminal while logged in to your Mac's desktop; AppKit tests need a graphical session. Look for `PASS` messages and a successful exit. Live Text checks explicitly report a skip on unsupported devices.

### 4. Open and install

Launch your freshly built app:

```sh
open build/Separate.app
```

Choose **Open Files…**, or drag PDFs and images onto the app. Each file opens in its own window.

To keep it in Applications, quit Separate, run the following command, then drag **Separate.app** from that Finder window into **Applications**:

```sh
open build
```

Open the installed copy from Applications. Building or installing does not automatically change your default apps.

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
| Copy selected PDF or recognized image text | ⌘C |
| Quit | ⌘Q |

For two-finger double tap, enable **Smart zoom** in macOS System Settings → Trackpad → Scroll & Zoom. Live Text starts recognizing images when they open; the status bar shows when text is ready to select. Recognition quality depends on the image and language. If recognition is unavailable or no text is found, image viewing and zoom still work. This feature recognizes text in image files; it does not add OCR to scanned PDF pages.

## Current scope

Separate is a viewer. It does not yet provide annotations, signatures, image editing, printing/export, search, or session restoration. For those tasks, use **Open With → Preview** or another editor. Animated and multipage images use the representation macOS selects; animation playback is not provided. Password-protected PDFs use PDFKit’s password UI.

The universal build is compiled for both architectures. Interactive testing for this release was performed on Apple Silicon running macOS 26.1; Intel and macOS 13 runtime behavior have not been independently verified.

## Update your local build

Quit Separate, open Terminal in your existing `separate` checkout, and run:

```sh
git pull --ff-only
bash scripts/build.sh
bash scripts/test.sh
```

Then copy the rebuilt `build/Separate.app` into Applications again. If Git reports conflicting local changes or a diverged branch, resolve those before updating; these commands do not discard your work.

## Troubleshooting

- **`xcrun` or Swift is missing:** finish installing the Command Line Tools. After a macOS upgrade, check Software Update for a compatible tools update.
- **Compiler or SDK errors:** update the developer tools supported by your macOS version. Include `sw_vers` and `xcrun swiftc --version` output when reporting a build problem.
- **Tests cannot connect to WindowServer:** run them from a Terminal window in a logged-in desktop session instead of a headless environment.
- **Two-finger double tap does nothing:** enable Smart zoom under System Settings → Trackpad → Scroll & Zoom.

## Archived binary release

The [initial 0.1.0 release](https://github.com/jiteshdhamaniya/separate/releases/tag/v0.1.0) remains available, but predates gesture zoom and Live Text. Build the current source for the latest features. That downloaded binary is ad-hoc signed and is not notarized by Apple; macOS may block it. Apple's [per-app opening instructions](https://support.apple.com/102445) explain the system's behavior.

## Test and package

```sh
bash scripts/test.sh
bash scripts/package.sh
```

Tests create their own synthetic PDFs and PNGs, instantiate 24 independent windows without showing them, check the no-tabs policy and repeated file opens, exercise image scaling/PDF navigation, dispatch synthetic pinch and smart-zoom events through each window, recognize and select text in a generated image, reject invalid and missing files, and confirm the input files are unchanged. Live Text checks explicitly report a skip on unsupported devices. AppKit tests require a logged-in macOS graphical session. Packaging produces a universal ZIP and checksum in `dist/`.

The original viewer was also tested interactively by opening 24 mixed PDFs and PNGs from Finder and checking that they remained separate windows.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). Keep one-file-per-window behavior as the default and avoid adding background services or dependencies without a clear need.

## License and artwork

Code and included artwork are provided under the [MIT License](LICENSE). The app icon was created with AI-assisted image generation; its prompt and packaging details are recorded in [docs/branding.md](docs/branding.md).
