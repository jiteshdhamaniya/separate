# Contributing to Separate

Use a Mac with Apple's command-line developer tools. Run `bash scripts/build.sh` and `bash scripts/test.sh` before opening a pull request. Keep changes focused and describe the behavior changed, how it was tested, and any remaining limitations.

For UI changes, check the app with both PDFs and images, small and large windows, and multiple files opened from Finder. Include screenshots using synthetic or public-domain documents only.

Preserve these principles:

- Each file-open request creates an independent window, with automatic tabbing disabled.
- Viewing must not modify source documents.
- No telemetry, accounts or background network access.
- Do not commit local preferences, signing credentials, personal documents, compiled apps or test outputs.

File a bug with your macOS version, Mac architecture, app version, reproduction steps, and expected behavior. Never attach private documents; use a minimal synthetic example when possible.

By contributing, you agree that your contributions are licensed under the project's MIT License.
