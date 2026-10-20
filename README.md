# NS Train Monitor — native macOS app

This version is written entirely with Apple technologies: Swift, SwiftUI, AppKit, URLSession, UserDefaults, and Keychain. It does not use .NET and does not run a local web server.

Each monitor has its own departure and destination station, departure window, checking schedule, interval, and maximum result count. Stations are loaded from NS and cached locally. All times use native macOS time pickers, and the default maximum is five journeys.

Connections also offers optional experimental NDOV InfoPlus DVS live updates. Live station events trigger a fresh NS journey check for matching active monitors. If the feed is unavailable, the monitor automatically uses its normal check interval. ZeroMQ is included inside the app, so Homebrew and separate runtime files are not required.

## Run

Double-click **NS Train Monitor.app**. The app imports the adjacent legacy `config.json` on its first launch when one is present. You can also enter or change all values in Settings; the NS API key is stored in macOS Keychain.

## Rebuild

### Xcode

Open `NS Train Monitor.xcodeproj`, select the **NS Train Monitor** scheme and **My Mac**, then press **⌘R** to build and run. The project requires macOS 27 or later and currently targets Apple silicon because the bundled ZeroMQ static library is arm64-only.

The project includes the Swift app, C bridge, ZeroMQ library, app icon, and dependency license. It uses local ad-hoc signing, so a developer team is not required for local builds. The bundle identifier and version match the existing app, preserving its saved settings and Keychain lookup. App Sandbox is disabled, matching the script-built app.

Xcode places the built app in its DerivedData folder under `Build/Products/Debug/` (or `Release/`). Find it under **Products → NS Train Monitor.app → Show in Finder**. To create a release archive, choose **Product → Archive**. Distribution signing and notarization require separate configuration.

For a command-line Xcode build:

```sh
xcodebuild -project "NS Train Monitor.xcodeproj" -scheme "NS Train Monitor" -configuration Release build
```

When running from Xcode, enter the NS API key and monitor settings in the app if they have not already been saved. Legacy `config.json` import only looks beside the built `.app`; the project does not copy credentials into the bundle.

### Build script

Run `bash build-app.sh`. Xcode Command Line Tools are required. This builds `NS Train Monitor.app` directly in the repository folder.

The script reads the minimum macOS version from `Info.plist` and applies it to the Swift compiler, C compiler, and asset compiler.

The repository includes the ZeroMQ headers and static library needed for the optional NDOV connection, so no Homebrew packages are required.

The monitor operates while the app is open. The Mac must remain awake for scheduled checks.
