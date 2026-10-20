# NS Train Monitor — native macOS app

This version is written entirely with Apple technologies: Swift, SwiftUI, AppKit, URLSession, UserDefaults, and Keychain. It does not use .NET and does not run a local web server.

Each monitor has its own departure and destination station, departure window, checking schedule, interval, and maximum result count. Stations are loaded from NS and cached locally. All times use native macOS time pickers, and the default maximum is five journeys.

Connections also offers optional experimental NDOV InfoPlus DVS live updates. Live station events trigger a fresh NS journey check for matching active monitors. If the feed is unavailable, the monitor automatically uses its normal check interval. ZeroMQ is included inside the app, so Homebrew and separate runtime files are not required.

## Run

Double-click **NS Train Monitor.app**. The app imports the adjacent legacy `config.json` on its first launch when one is present. You can also enter or change all values in Settings; the NS API key is stored in macOS Keychain.

## Rebuild

Run `bash build-app.sh`. Xcode Command Line Tools are required.

The repository includes the ZeroMQ headers and static library needed for the optional NDOV connection, so no Homebrew packages are required.

The monitor operates while the app is open. The Mac must remain awake for scheduled checks.
