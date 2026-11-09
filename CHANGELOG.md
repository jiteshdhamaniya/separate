# Changelog

## 0.1.2 — 2026-11-09

- Two-finger double-tap zoom in PDFs and images, toggling back to the previous zoom or Fit mode.
- Native Live Text selection and copying in images using VisionKit, with asynchronous on-device recognition and status feedback.
- Regression checks for smart zoom, real text recognition, selection and overlay alignment after zoom.

## 0.1.1 — 2026-11-09

- Trackpad pinch-to-zoom in PDF and image windows, keeping the content under the pointer stationary where scroll bounds permit.
- Image toolbar zoom now preserves the viewport center.
- Regression checks for pinch direction, zoom limits, pointer anchoring and returning to Fit.

## 0.1.0 — 2026-11-09

First public release.

- Independent windows for every PDF and image, including repeated file opens.
- PDF thumbnails, page navigation and selectable text.
- Image zoom, fit-to-window and actual-size controls.
- Finder file opening and drag-and-drop support.
- New Separate icon in the Dock, Finder, About panel and welcome screen.
- Universal Apple Silicon/Intel build, synthetic regression fixtures and packaging scripts.

This release is a viewer and is not notarized by Apple. See the README for its current feature and compatibility limits.
