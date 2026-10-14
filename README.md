# CPA Widget

A native macOS menu-bar app that shows provider status and quota usage for a single [CLIProxyAPI](https://help.router-for.me/management/apiv8.html) instance.

Click the server icon in the menu bar to open the panel. Settings configures the instance, its management key, and whether the menu-bar icon is shown. The app is built with SwiftUI and AppKit only, with no external packages.

## Features

- **Quotas tab**: every provider returned by the instance's credential inventory, with each account shown separately. All quota windows are displayed, including five-hour and weekly usage when the instance reports them.
- **Requests tab**: proxied API requests from the instance's file log, newest first, with time, method, path, status, latency, client IP, and request ID.
- **Passive monitoring**: the app only reads. It never resets quotas, drains the destructive `/observability/usage/queue`, or changes server settings.
- **Stale data labelling**: if a refresh fails, the last successful snapshot is kept and labelled stale.
- **Auth protection**: automatic refresh pauses after HTTP 401/403 until settings are saved, to avoid the server's failure-based IP ban.

Missing quota values are shown as unavailable, never as zero. The app does not infer limits from request counts or average quotas across accounts.

## Requirements

- macOS 15.6 or later
- Xcode 27.0 (used for verification)
- A CLIProxyAPI instance with the v8 management API enabled (remote management must be enabled; home mode does not expose it)
- The instance's **management key**, not an API key for proxy clients

## Build and run

Open `CPA Widget.xcodeproj`, select the `CPA Widget` scheme, choose your signing team, and run.

For an unsigned development build:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project 'CPA Widget.xcodeproj' -scheme 'CPA Widget' \
  -configuration Debug -derivedDataPath /tmp/cpa-widget-build \
  CODE_SIGNING_ALLOWED=NO build
open '/tmp/cpa-widget-build/Build/Products/Debug/CPA Widget.app'
```

## Configuration

1. Launch the app. Settings opens on launch.
2. Enter the instance origin, such as `https://cpa.example.com`, or its full `/v8/management` base.
3. Enter the management key.
4. **Test Connection** checks the current draft without saving it.
5. **Save** stores the URL in UserDefaults and the key in the Keychain. Saving does not run a connection test.
6. Enable or disable the menu-bar icon. Disabling removes the icon only. Reopen the running app from Finder to bring Settings back.

Only one instance is supported. Changing it replaces the key and clears the previous snapshot.

### Transport security

Use HTTPS for any remote instance. Plain HTTP is permitted only for loopback addresses (`localhost`, `127.0.0.1`), where the management key does not leave the machine.

HTTP sends the management key and all traffic unencrypted. Anyone on the network path can read or alter them, so do not use HTTP for a remote host.

URLs with embedded credentials, query strings, fragments, or unrelated base paths are rejected.

> **Known gap:** the current Settings code also accepts HTTP to other hosts, including `100.x` addresses, after an insecure-connection confirmation. This does not match the project rule above, and it is being resolved separately. Until then, treat that confirmation as a warning, not as supported use.

## How quotas are obtained

Each account's quota comes from one of two sources:

1. The instance's **quota plugin** for that provider, when the instance publishes a `quota_plugin_id` for the credential.
2. A **built-in probe** for Codex and Antigravity. The probe asks the instance to forward one provider request with that credential's token and maps the response into the same windows.

A provider with neither source is shown as unavailable.

## Security and privacy

- The management key is stored in the Keychain, device-only.
- The app never logs keys, credential bodies, or HTTP error bodies.
- Signed builds enable app sandboxing and outgoing network access.

## Documentation

- [Docs/Project.md](Docs/Project.md): behavior requirements, settings, build, and verification record
- [Docs/API.md](Docs/API.md): management endpoints, response shapes, and provider probes
- [Docs/Architecture.md](Docs/Architecture.md): ownership, data flow, and change rules

## Limitations

- Signed-build behavior (sandbox, Keychain access) and real-provider quotas are verified only as described in the verification record.
- Support for a given provider depends on the instance and its installed plugins. The management API does not guarantee five-hour or weekly quotas for every provider.
- Menu-bar dismissal was verified with an unsigned Debug build (see the verification record in `Docs/Project.md`).
