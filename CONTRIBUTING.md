# Contributing

Thanks for helping improve Screen Sharing Touch Bar.

## Reporting bugs and missing toolbar items

Use the [issue templates](https://github.com/nabeelbaghoor/screen-sharing-touch-bar/issues/new/choose). For a toolbar item that shows a dashed icon, include its identifier. You can find it with:

```bash
defaults read com.apple.ScreenSharing | grep -A30 "TB Item Identifiers"
```

## Building

```bash
./build.sh            # universal build, installs to ~/Applications
./build.sh --no-install
./package.sh          # DMG and zip in dist/
```

Each build has a new ad-hoc signature, so macOS treats it as a new app: remove the old entry from Privacy & Security > Accessibility, relaunch, and allow it again.

## Testing a change

There are no automated UI tests (the Touch Bar and Screen Sharing can't run in CI), so please check by hand:

1. Build, launch, allow Accessibility and relaunch.
2. Open Screen Sharing and connect to a Mac. The Touch Bar should match the toolbar.
3. Tap each button and check that it does the same as the toolbar button, and that blue/dimmed states follow.
4. Change the toolbar (View > Customize Toolbar) and check the Touch Bar updates.
5. Switch to another app and check the normal Touch Bar returns.

You can capture the Touch Bar for a pull request with `screencapture -b touchbar.png`.

## Adding a toolbar item

Add an entry to `KnownItems()` in `main.m` with its label, SF Symbol names (first available wins), the menu titles it presses, and how its state is read (`check` for a checkmark, `onTitle` for items whose menu title changes).

## Code style

- Objective-C with ARC, kept in a single `main.m` so the project stays easy to read and build without Xcode projects.
- No new dependencies.
- Match the surrounding naming and comment style.

## Pull requests

- Keep each pull request focused on one change.
- Describe what you tested and on which macOS version and Mac.
- Add a line under `[Unreleased]` in `CHANGELOG.md`.

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
