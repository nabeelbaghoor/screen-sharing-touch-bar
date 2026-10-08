# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.0] - 2026-10-08

### Added
- The Touch Bar now mirrors Screen Sharing's current toolbar, read from its saved layout, and updates within a couple of seconds when the toolbar is customized.
- Buttons for App Windows (App Exposé), Displays, Zoom In/Out and Scale to Fit; toolbar spaces and flexible spaces are kept.
- Unknown toolbar items appear in place with a placeholder icon and try the menu command with the same name.
- Labels are kept where they fit; the widest buttons switch to icon-only when the bar is full.
- App icon.
- Universal binary (Apple silicon and Intel) and macOS 12 support.
- `package.sh` builds a shareable DMG and zip.

### Fixed
- Accessibility attribute values are released correctly when reading menu titles.

## 1.0.0 - 2026-10-08 (not published)

### Added
- First version: Control, Dynamic, HDR, Launchpad, Mission Control and Desktop on the Touch Bar while Screen Sharing is in front, with live on/off state.
- Menu bar icon with Accessibility status, Open at Login and Quit.

[Unreleased]: https://github.com/nabeelbaghoor/screen-sharing-touch-bar/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/nabeelbaghoor/screen-sharing-touch-bar/releases/tag/v1.1.0
