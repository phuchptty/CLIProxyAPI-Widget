# Architecture

## Ownership

- `App/`: app entry point, lifecycle delegate, `AppPresentation` status-item/popover/window ownership, and shared `AppModel` state.
- `Features/Widget/`: panel, account card, and quota-window row. Presentation only; no server mutation.
- `Models/`: typed credential, provider, and quota snapshots/responses.
- `Services/ManagementAPI/`: URL validation, authenticated URLSession requests, and status-code errors.
- `Services/QuotaProbe/`: provider-specific quota probes for credentials the instance exposes without a quota plugin. Each probe asks the instance to forward one provider request with that credential's token, then maps the provider's own response into the shared quota shape.
- `Services/Security/`: Security-framework Keychain persistence.
- `AppInfo.plist`: ATS allows arbitrary HTTP transport; Settings requires explicit confirmation before testing or saving non-private HTTP endpoints.

The Xcode project uses a file-system synchronized source group. New Swift files under `CPA Widget/` are discovered without individually editing source build phases.

## Data flow

Settings drafts are local view state. Test Connection validates the current URL/key draft and requests credential inventory without persisting either value. HTTP hosts outside loopback and IPv4 `100.0.0.0/8` require explicit confirmation before test or save because HTTP exposes the management key and traffic. Save validates the URL/key, writes Keychain first, then commits the URL to UserDefaults, increments the configuration revision, clears data, and resets authentication pause.

Refresh captures a configuration revision and prevents concurrent refreshes. It reads credential inventory, fetches quotas with at most six in-flight account requests, restores credential order before provider grouping, then publishes only if the configuration revision is unchanged. Cancellation does not publish partial data. Each account's quota comes from its published quota plugin when the instance has one for that provider, otherwise from a registered provider probe; a provider with neither stays explicitly unavailable rather than being inferred from request counters.

A top-level connection failure leaves the prior snapshot intact and exposes an error. Quota failures belong to their account. Authentication failures abort the refresh and pause later calls to reduce the risk of the API's failure-based IP ban.

## UI boundaries

`AppPresentation` owns a transient menu-bar popover and a separately recoverable Settings window. It creates a fresh SwiftUI panel hierarchy for each opening and releases it on close, bounding its 60-second polling task to visible presentation. The panel opens at least two thirds of the screen height and dismisses when the user clicks outside it. Its header is a single row: title, connection-status chip, refresh age, and refresh action. Account limits remain separate because their reset times and plans can differ.

SwiftUI uses shared `@Observable` main-actor state through environment injection, with `@Bindable` for the widget toggle. Keys never belong in UserDefaults, fixture data never belongs in the production refresh path, and view bodies must not contain transport or quota aggregation logic.

## Known verification boundaries

See Project.md for exercised checks. Native snapshots do not prove status-item interaction, disabled-widget recovery, or signed Keychain/sandbox access. Those require an interactive macOS session and an appropriately signed build. Real quota availability requires a v8 instance with compatible provider plugins.
