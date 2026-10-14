# CPA Widget

Native macOS menu-bar status app for a single CLIProxyAPI instance. AppKit's retained `AppPresentation` owns the status item, transient popover, and recoverable Settings window; SwiftUI supplies both surfaces. No external frameworks.

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
- Refresh on panel task startup, then every 60 seconds while its task is active; manual refresh is available. Settings can test the current URL/key draft before saving.
- Preserve the last successful snapshot after connection failures and label it stale. Individual quota failures do not hide other accounts.
- Stop subsequent automatic calls after HTTP 401/403 until settings are saved. The server can ban an IP after five consecutive authentication failures.

## Settings

1. Launch the app; Settings opens on launch, alongside the menu-bar icon when enabled. The window opens centered on the usable screen area and returns to that center every time it is shown.
2. Enter an instance origin, such as `http://localhost:8317`, or its full `/v8/management` base.
3. Enter the **management key**, not an API key issued to proxy clients.
4. Choose **Test Connection** to test the current URL/key draft without saving it.
5. Choose **Save** to store the URL and key. Saving does not run a connection test.
6. Choose **Close**, or the window's own close control, to dismiss Settings. The process keeps running; reopening the app from Finder brings the same window back, centered.
7. Enable or disable the status widget. Disabling removes its menu-bar icon, not the process or Settings window. Reopen the already-running app from Finder to recover Settings after closing it.

The instance URL and widget preference are stored in UserDefaults. The active management key is stored in Keychain, device-only and available when unlocked. There is one active instance; changing it replaces the key and clears the previous snapshot.

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

Normal signed builds enable app sandboxing, outgoing network connections, and the hardened runtime. `LSUIElement` makes this a menu-bar utility rather than a Dock app. `AppInfo.plist` permits arbitrary HTTP at the ATS layer so confirmed HTTP endpoints work; the Settings flow warns before testing or saving non-private HTTP hosts. This broad exception increases transport risk, so HTTPS remains recommended.

## Verification record

- The signed Debug app plist sets `NSAllowsArbitraryLoads=true` and omits `NSAllowsLocalNetworking`; on macOS, the latter would cause `NSAllowsArbitraryLoads` to be ignored.
- Signed Debug build succeeded with app sandboxing and `com.apple.security.network.client` enabled.
- An isolated signed sandbox probe compiled from the production `AppModel`/`ManagementClient` sources completed `testConnection` over HTTP to the non-loopback LAN fixture `192.168.10.4`. It used a temporary in-memory Keychain adapter and a fixture-only key; no app Keychain value was changed.
- URL policy smoke checks passed for HTTPS, loopback, the full IPv4 `100.0.0.0/8`, and warning-required other HTTP hosts. The Settings dialog itself and the shipped app's UI-driven confirmation path were not exercised interactively.
- The eight-account loopback fixture also verified stable ordering, 5h/Weekly windows, unsupported quota isolation, maximum six active requests, 401 snapshot retention, and pause of subsequent refreshes.
- The panel was opened from the status item against a loopback fixture: the header rendered on one row with a green "Connected" chip, the provider list scrolled inside a panel sized 786 pt against a 1169 pt screen (two thirds), and clicking outside the panel closed it. The stale-snapshot chip rendered orange in the same position. The fixture instance URL was restored afterwards and no Keychain value was read or written.
- A probe fixture served five credentials and drove the production `AppModel.refresh()` path. Verified: Codex mapped `used_percent` 28/59 into `5h`/`Weekly` windows with remaining fractions 0.72/0.41 and a computed reset time plus the `plus` plan; Antigravity collapsed three models into two windows, tightest first, with the shared-limit window labelled `2 models` and its model ids listed; a credential with a published plugin still used the plugin route and produced zero forwarded requests; a Codex credential without `chatgpt_account_id` reported the missing metadata; a provider with neither source reported quota unavailable. Exactly two forwarded requests were recorded, both carrying `Authorization: Bearer $TOKEN$` and the credential's `auth_index`.
- Earlier render attempts were inconclusive: `NSHostingView`/`ImageRenderer` produced the quota tracks but no text or blank scroll content, and desktop capture returned black frames while the main display was asleep. The on-screen window capture below replaced both.
- A routing fixture exercised display filtering and order: a credential with `disabled: true` and the highest priority and weight was absent from the panel and received no quota request, and the remaining Codex accounts published as priority 9 first, then the two priority 5 / weight 9 accounts in inventory order, then the priority 5 / weight 1 account. The same render showed the two-column grid, stacked provider categories, and ring colours at 12% and 15% red, 45% and 52% orange, and 85% and 90% green. This used an on-screen window rendered from the production views and captured with `screencapture`; off-screen hosting rendered blank scroll content.
- Cards in one grid row were verified to end at the same height: a fixture paired a two-window account with a one-window account, and the shorter card's background stretched to the taller card's height. Off-screen hosting rendered blank scroll content, so this used the same on-screen window capture.
- The Settings window was verified centered and dismissible on a 1800x1169 pt display with a visible `(0, 78, 1800, 1052)` usable area: it opened at `(640, 219, 520, 692)`, whose centre `(900, 604)` equals the usable area's centre; pressing its **Close** button ordered it out (`onscreen=false`) and a Finder reopen restored the same window at the same centered frame. The same run captured the window: Close on the left, Save on the right of one row.
- In-app logging found the cause of the earlier off-centre placement: the SwiftUI hosting controller leaves the window at `0 x 32` until its first layout pass, so centring had to move to the next run-loop turn after the size settles.
- Real-provider quotas and Keychain behavior remain unverified.

See [API.md](API.md) for endpoint contracts and [Architecture.md](Architecture.md) for ownership and change rules.
