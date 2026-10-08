# Security Policy

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please report security issues privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**. Don't open a public issue for security problems.

You can expect a reply within a week. Once a fix is released, the report can be made public.

## What the app can access

- **Accessibility:** used only to read the titles and states of Screen Sharing's menu items and to press them.
- **Screen Sharing's preferences:** read with `defaults export com.apple.ScreenSharing` to learn the toolbar layout.
- **No network access, no analytics, no screen recording, no keystroke monitoring.**
