# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This project uses an Xcode workspace with a local SPM package. Build using:

```bash
xcodebuild -workspace BeerTempWorkspace.xcworkspace -scheme BeerTemp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build -skipMacroValidation
```

For physical devices (e.g. iPhone 15):

```bash
xcodebuild -workspace BeerTempWorkspace.xcworkspace -scheme BeerTemp -destination 'platform=iOS,name=iPhone 15 von Konstantin' build -skipMacroValidation -allowProvisioningUpdates -allowProvisioningDeviceRegistration
```

Deployment targets: iOS 17+, macOS 14+. Swift 6 strict concurrency. No test targets are configured.

## Architecture

BeerTemp is a SwiftUI app for monitoring BLE temperature sensors (beer fermentation). Users discover nearby sensors, view real-time temperatures with charts, set target temperatures, and receive notifications when targets are reached.

Built with **The Composable Architecture (TCA)** using unidirectional data flow, controlled dependencies, and reducers.

**Project structure:**
- `BeerTempWorkspace.xcworkspace` — workspace linking Xcode project + local SPM package
- `BeerTempPackage/` — local SPM package containing all feature logic (depends on `swift-composable-architecture` 1.17.0+)
- `BeerTemp/` — Xcode app target with views, live dependency implementations, and CoreBluetooth code

**TCA features (in `BeerTempPackage/Sources/BeerTempFeatures/`):**
- `AppFeature.swift` — Root reducer, scopes to SensorList
- `SensorListFeature.swift` — Main workhorse: scanning, discovery, connection, temperature/progress stream subscriptions, notifications
- `SensorCardFeature.swift` — Per-sensor card state (temp, progress, chart data, log export)
- `SensorDetailFeature.swift` — Connected sensor detail with target value alert flow
- `Models.swift` — Shared value types: `ConnectionState`, `TargetValueProgress`, `LogValue`, `DiscoveredSensor`

**Dependency clients (in `BeerTempPackage/Sources/BeerTempFeatures/`):**
- `BluetoothClient.swift` — `@DependencyClient` for BLE operations (scan, connect, temp/progress streams, target value read/write)
- `LoggerClient.swift` — `@DependencyClient` for CSV logging
- `NotificationClient.swift` — `@DependencyClient` for local notifications

**Live implementations (in `BeerTemp/Dependencies/`):**
- `BluetoothClient+Live.swift` — CoreBluetooth integration using `LockIsolated<LockedState>` for thread-safe state, `CentralManagerDelegate`/`PeripheralDelegate` async stream adapters
- `LoggerClient+Live.swift` — Wraps `CsvLogger`
- `NotificationClient+Live.swift` — Wraps `UNUserNotificationCenter`

**Other app target files:**
- `BeerTempApp.swift` — Entry point, creates root `Store`
- `Bluetooth/CentralManagerDelegate.swift`, `PeripheralDelegate.swift` — Async stream adapters for CoreBluetooth delegates
- `Bluetooth/Logger.swift` — CSV file writer (temp directory, 30-min rolling window)
- Views: `TemperatureSensorListView` → `TemperatureSensorCardView` → `TemperatureSensorDetailView`

**Key patterns:**
- BLE delegate callbacks wrapped in `AsyncStream` for async/await integration
- `UnsafeContinuation` bridges one-shot BLE request/response pairs
- Temperature data is Float32 little-endian from BLE characteristics
- All BLE state is thread-safe via `LockIsolated` (from ConcurrencyExtras)
- `@preconcurrency import CoreBluetooth` for Sendable compliance

**BLE UUIDs:**
- Service: `4fafc201-1fb5-459e-8fcc-c5c9c331914b`
- Temperature characteristic: `beb5483e-36e1-4688-b7f5-ea07361b26a8` (read/notify)
- Target value characteristic: `44e7fcba-4db0-4c41-b0a8-a34fc66afd74` (read/write)
- Target progress characteristic: `6d913149-d0fc-4d85-9dd5-615248f2bee0` (read/notify)

## Simulator & MCP

Use **XcodeBuildMCP** (configured in `.xcodebuildmcp/config.yaml`) for all simulator interactions:
- Build/run: `build_sim`, `build_run_sim`
- Screenshots: `screenshot` (use `returnFormat: "base64"` to view inline)
- UI inspection: `snapshot_ui` to get the accessibility hierarchy with coordinates
- UI automation: `tap_coordinate`, `swipe`, `type_text` etc. (requires `ui-automation` workflow)
- Logs: `start_sim_log_cap` / `stop_sim_log_cap`

Session defaults (workspace, scheme, simulator, bundleId) are persisted in `.xcodebuildmcp/config.yaml`. Prefer MCP tools over raw `xcrun simctl` or `xcodebuild` commands.

Save screenshots to the local `tmp/` folder (gitignored).

## Frameworks

- **TCA**: swift-composable-architecture (1.17.0+) via local SPM package
- **Apple**: CoreBluetooth, SwiftUI, Charts, UserNotifications
