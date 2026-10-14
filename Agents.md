# Agent instructions — CPA Widget

## Mission

Maintain a native macOS SwiftUI menu-bar app for CLIProxyAPI. Clicking the menu-bar icon opens provider status/usage. Keep exactly two primary surfaces: widget panel and settings window. Settings configures a single active instance, its management authentication, and widget enablement.

Read `Docs/Project.md`, `Docs/API.md`, and `Docs/Architecture.md` before changing behavior. The API reference is https://help.router-for.me/management/apiv8.html. Verify new transport fields against the current reference and upstream implementation; do not invent quota endpoints or schemas.

## Required conventions

- Use SwiftUI and Apple frameworks. AppKit is appropriate for macOS lifecycle/activation; no web UI or third-party packages without approval.
- Use `@Observable` main-actor shared state and local settings drafts. Keep transport, persistence, and views separate; one named type per Swift file.
- Preserve the existing synchronized Xcode source group and macOS deployment target unless a target change is requested.
- Use v8 paths only; no deprecated v0 adapters or silent fallbacks.
- Discover all providers from the instance inventory. Keep all accounts visible and their quotas separate. No hard-coded provider allowlist.
- Fetch normalized quotas via each credential's `quota_plugin_id` and `auth_index`. Show all returned windows, including five-hour and weekly when supported.
- Missing quotas/fractions are unavailable, never zero. Never infer quota percentages from request counters, average account limits, or populate the production widget with sample data.
- This is a passive monitor. Never consume the destructive usage queue, reset quotas, or mutate server settings to enable statistics.
- Store management keys in Keychain only. Never log keys, credential bodies, or arbitrary HTTP error bodies. Require HTTPS for remote instances and allow HTTP only for loopback.
- Keep stale snapshots explicitly labeled. Prevent overlapping refreshes and reject results from an obsolete settings revision.
- Pause automatic refresh after 401/403 until settings are saved; repeated auth failures can ban the user's IP.
- Disabling the icon must not strand the user: retain independent Settings and app-reopen recovery.
- Use native accessible controls, meaningful icon labels, locale-aware numbers, and readable errors. Maintain light/dark appearance.

## Completion checks

1. Build the `CPA Widget` scheme with Xcode. A command-line unsigned build is documented in `Docs/Project.md`; signed sandbox and Keychain behavior must be checked separately.
2. Exercise changed API behavior against a local fixture or a user-provided instance without persisting fixture credentials over the user's key.
3. Check missing/unsupported quotas, multiple providers/accounts, auth failures, stale snapshots, and settings changes when relevant.
4. Launch the actual app. In an interactive session, click the icon, open Settings, save/test, disable/re-enable the icon, close/reopen Settings, and confirm quitting.
5. Inspect the native surface. ImageRenderer does not capture every AppKit-backed control; use NSHostingView snapshots or an actual desktop screenshot as appropriate. Report permission-related visual limits rather than claiming interactive verification.
6. Keep permanent tests only for consumer-visible behavior. Remove throwaway fixtures/scripts after smoke checks.
7. Update Docs for permanent behavioral/API/architecture changes and record actual verification with its limitations.

Do not add unrelated features, compatibility shims, telemetry, or speculative provider-specific upstream calls. If a provider has no supported quota plugin, finish its status presentation and state that dependency explicitly.
