# Separate artwork

`Resources/AppIcon.png` is the high-resolution source artwork. The build generates 16, 32, 128, 256 and 512-point icons at standard and Retina resolutions, then packages them into `AppIcon.icns`. Alpha transparency is preserved during resizing.

The icon was generated with the built-in OpenAI image-generation tool on 2026-11-09. The generated bitmap was inspected, copied into this repository, and resized only for macOS icon packaging. It is included under the repository's MIT License.

## Generation prompt

Use case: logo-brand. Asset type: production macOS app icon for an open-source PDF and image viewer named Separate. Primary request: an elegant, distinctive icon communicating one file per independent window, calm and effortless. Create a single centered rounded-square macOS icon with a deep midnight-blue to indigo subtle gradient tile and two crisp luminous ivory application-window shapes, separated diagonally by a clearly visible band of negative space. Each window is a simple rounded rectangular frame with a minimal title-bar line; one contains a tiny abstract mountain image glyph, the other a few document lines. Balanced bold geometry, restrained soft dimensional highlights, beautiful at small Dock sizes, high-end native macOS utility aesthetic. Front-on orthographic design, strong silhouette, no perspective mockup, no lettering, no text, no watermarks, no Apple logos, no extra objects. The icon occupies about 86 percent of a square canvas with truly transparent outside corners and margins. Deliver one finished icon, not a grid or variations.
