# CPA Widget

Native macOS menu-bar status app for a single CLIProxyAPI instance. AppKit's retained `AppPresentation` owns the status item, transient popover, and recoverable Settings window; SwiftUI supplies both surfaces. The opt-in Atoll integration publishes a notch dashboard and compact live-activity summary using the pinned AtollExtensionKit SDK.

## Requirements and behavior

- Click the server icon in the macOS menu bar to open the widget panel. The panel opens at least two thirds of the screen height and closes when the user clicks outside it. Provider categories stack vertically and the accounts inside one category flow into a two-column grid.
- The panel header is one row: title, a connection-status chip (green when connected, orange when awaiting a connection or showing a stale snapshot), the refresh age, and the refresh action.
- List every provider returned by the instance's credential inventory, with every account kept separate. Only providers present on the instance are displayed, not a hard-coded catalog.
- Show only enabled credentials; a credential the instance reports as disabled is not fetched and not displayed. Within a provider, accounts are ordered the way the instance routes: priority tier descending, then weight descending, then inventory order.
- Display account status, success/failure request counters when supplied, plan, provider-defined summary metrics, and all quota groups/windows.
- Display five-hour and weekly usage when the instance's quota plugin returns those windows. Other window names are retained exactly as supplied.
- Take each account's quota from its instance quota plugin when the instance publishes one for that provider. Otherwise use a built-in provider probe for Codex and Antigravity, which forwards one provider request through the instance with that credential's token and maps the provider's own response into the same windows. A provider with neither source is shown unavailable; the app never invents a limit from request counters.
- Usage means `1 - remainingFraction`; values are bounded to 0–100%. Missing values are unavailable, never interpreted as zero use. Reset dates are displayed in local time.
- Each quota window is drawn as a ring that fills with the *remaining* quota and prints that percentage, so a small ring always means a nearly exhausted window. The ring is red below 30% left, orange below 70%, and green otherwise; the accessibility value states remaining and used together.
- Do not average quotas across accounts or manufacture limits from request counts.
- The menu-bar panel and enabled Atoll integration share one 60-second refresh scheduler; Atoll remains refreshed while the panel is closed.
- Preserve the last successful snapshot after connection failures and label it stale. Individual quota failures do not hide other accounts.
- Stop subsequent automatic calls after HTTP 401/403 until settings are saved. The server can ban an IP after five consecutive authentication failures.

## Settings

1. Launch the app; Settings opens on launch, alongside the menu-bar icon when enabled. The window opens centered on the usable screen area and returns to that center every time it is shown.
2. Enter an instance origin, such as `http://localhost:8317`, or its full `/v8/management` base.
3. Enter the **management key**, not an API key issued to proxy clients.
4. Choose **Test Connection** to test the current URL/key draft without saving it.
5. Choose **Save** to store the URL and key. Saving does not run a connection test.
6. Choose **Close**, or the window's own close control, to dismiss Settings. The process keeps running; reopening the app from Finder brings the same window back, centered.
7. Enable or disable the status widget. Disabling removes its menu-bar icon, not the process or Settings window. Reopen CPA Widget from Finder to recover Settings after closing it.
8. Enable **Show quotas in Atoll** to authorize CPA Widget in Atoll. Atoll must be running. In Atoll Settings → Extensions, enable extensions, notch experiences/tabs, live activities, and **Allow interactive web content**. The dashboard is read-only and the app never changes Atoll settings. The compact summary picker selects one account/window; its choice is stored without saving quota data.
9. Atoll authorization is checked again at app launch without prompting. Use **Connect / Show in Atoll** to authorize or resume after dismissal. Disabling the integration removes both Atoll surfaces and stops its refresh lease.

The instance URL and widget preference are stored in UserDefaults. The active management key is stored in Keychain, device-only and available when unlocked. The Atoll preference and compact account/window key are also stored in UserDefaults; Atoll authorization, quota snapshots, keys, tokens, and rendered HTML are not persisted. There is one active instance; changing it replaces the key and clears the previous snapshot.

HTTPS is recommended. HTTP is accepted without confirmation for `localhost`, loopback, and IPv4 addresses in `100.0.0.0/8` (including Tailscale/NetBird addresses). Other HTTP hosts require explicit confirmation before testing or saving. HTTP sends the management key and traffic unencrypted; anyone on the network path may read or alter them. Use HTTP only on trusted networks. URLs containing embedded credentials, query strings, fragments, or unrelated base paths are rejected. Remote server management must be enabled. Home mode does not expose the management API.

## Build and run

Open `CPA Widget.xcodeproj`, select the `CPA Widget` scheme, select your macOS destination and signing team, and Run. The app target deployment target is macOS 15.6; Swift language mode is 6. Xcode 27.0 was used for verification.

For an unsigned development build:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project 'CPA Widget.xcodeproj' -scheme 'CPA Widget' \
  -configuration Debug -derivedDataPath /tmp/cpa-widget-build \
  CODE_SIGNING_ALLOWED=NO build
open '/tmp/cpa-widget-build/Build/Products/Debug/CPA Widget.app'
```

Normal signed builds enable app sandboxing, outgoing network connections, the hardened runtime, and the narrowly scoped Atoll XPC mach-lookup exception. `LSUIElement` makes this a menu-bar utility rather than a Dock app. `AppInfo.plist` permits arbitrary HTTP at the ATS layer so confirmed HTTP endpoints work; the Settings flow warns before testing or saving non-private HTTP hosts. This broad exception increases transport risk, so HTTPS remains recommended.

## Verification record

Existing CLIProxyAPI verification predating the Atoll integration:

- The signed Debug app plist sets `NSAllowsArbitraryLoads=true` and omits `NSAllowsLocalNetworking`; on macOS, the latter would cause `NSAllowsArbitraryLoads` to be ignored.
- An isolated signed sandbox probe compiled from production `AppModel`/`ManagementClient` sources completed `testConnection` over HTTP to the non-loopback LAN fixture `192.168.10.4`, using a temporary in-memory Keychain adapter and fixture-only key; no app Keychain value was changed.
- URL policy smoke checks covered HTTPS, loopback, IPv4 `100.0.0.0/8`, and warning-required other HTTP hosts. The Settings dialog and shipped app UI confirmation path were not exercised.
- An eight-account loopback fixture verified stable ordering, 5h/Weekly windows, unsupported quota isolation, six-account concurrency, 401 snapshot retention, and pausing subsequent refreshes. Separate fixture runs verified Codex/Antigravity probe mappings, plugin precedence, credential metadata requirements, and unavailable quota behavior.
- The panel was opened from the status item against a loopback fixture. Header layout, two-thirds-height scrolling panel, outside-click dismissal, stale snapshot status, disabled credential filtering, routing order, two-column cards, and threshold ring colours were checked in on-screen captures.
- A Settings window was verified centered and dismissible on a 1800×1169 pt display; Finder reopen restored the same centered frame. The Close and Save buttons remained on one row.
- Real-provider quotas and shipped app Keychain behavior remain unverified.

Atoll integration verification:

- AtollExtensionKit is pinned at revision `23d843ef1b715bb0c2b6debca8399ab9cee306d3`.
- The unsigned Debug build succeeded after adding the Atoll transport, shared scheduler, Settings lifecycle, dashboard, and compact summary. The final build command used the selected Xcode at `/Applications/Xcode.app/Contents/Developer` and `/tmp/cpa-widget-atoll-build`.
- `xcodebuild -list` reports the `CPA Widget` target and scheme after restoring the target name and adding the package reference to the PBXProject.
- The signed Debug build succeeded with the configured Development Team `832V4PV6C6`, using `/tmp/cpa-widget-atoll-signed`. `codesign --verify --deep --strict` succeeded. The signed entitlements retain app sandboxing and outgoing network access; the temporary mach-lookup array contains exactly `com.ebullioscopic.Atoll.xpc`.
- The installed host metadata reports bundle identifier `com.Ebullioscopic.Atoll`, version `2.3.3`. The signed app process launched. No Atoll preference, authorization, management key, or Keychain value was changed.
- A temporary standalone descriptor/dashboard fixture exercised eight accounts and 24 windows across six pages. Assertions passed for descriptor validity and the 20,000-byte page cap, full-window retention, HTML escaping, 0/29/30/69/70/100% threshold colours, unavailable quotas, stale banner, no-account state, compact-summary unavailable/stale handling, and omission of arbitrary account errors/auth metadata. It did not exercise `AppModel.refresh()`, disabled credential filtering, XPC transport, or Atoll rendering.
- A temporary anonymous-listener XPC harness could not complete even `checkAuthorization()`; the transport returned `disconnected` before listener acceptance. Cancellation and invalidation behavior therefore remain unverified.
- Unsigned and signed builds passed after restoring the `WidgetPanel` 410-point width and computed panel height. `WidgetPanel` source inspection confirms the `.frame(width: 410, height: panelHeight)` modifier is restored. No interactive desktop capture or click inspection was obtained.
- Atoll authorization/XPC/rendering, menu-bar interaction, extended refresh timing, signed sandbox XPC access, and light/dark/reduced-motion rendering remain unverified. Atoll's interactive web-content permission and Extensions configuration were not changed.
- The project file's native target has a filesystem synchronized group; Xcode's successful builds compiled all new Swift files.

See [API.md](API.md) for endpoint contracts and [Architecture.md](Architecture.md) for ownership and change rules.
