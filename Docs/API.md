# Management API integration

Primary reference: [CLIProxyAPI Management API v8](https://help.router-for.me/management/apiv8.html).

## Requests used

Base: `<instance>/v8/management`. Every request carries `Authorization: Bearer <management-key>` and `Accept: application/json`; timeout is 15 seconds.

| Request | Purpose |
| --- | --- |
| `GET /credentials` | Provider/account inventory and available quota plugin metadata |
| `GET /plugins/:id/quota?auth_index=...` | Normalized quotas for one account through an installed quota plugin |
| `POST /requests/api-call` | One forwarded provider request used by the built-in quota probes |

These are read operations. The app does not change server configuration, reset quotas, refresh OAuth tokens, download credentials, or drain `/observability/usage/queue`. That queue is destructive and unsuitable for a passive status widget.

## Credential inventory

The response is `{ "files": [...] }`. Each record requires `id` and `provider`; the app reads optional `name`, `status`, `disabled`, `unavailable`, `auth_index`, `quota_plugin_id`, `project_id`, `id_token`, `priority`, `weight`, `success`, and `failed`.

`priority` and `weight` drive display order because they drive the instance's own routing: `selector.go` keeps the highest priority tier and reports a credential as higher priority when its value is greater, and `credentialweight` treats weight as a proportional share within that tier with a default of 1. A record the instance marks `disabled: true` is skipped entirely.

`project_id` (Antigravity) and `id_token.chatgpt_account_id` (Codex) are the credential metadata the provider probes need; the app reports them as missing rather than substituting a default.

`quota_plugin_id` selects the plugin path and `auth_index` selects the credential. Missing either yields an explicit quota-unavailable state. API-key and runtime credentials are displayed when returned by this inventory; an instance must expose a quota plugin to provide their limit windows.

The guide's credential example does not enumerate all runtime fields. Plugin selection is grounded in the upstream implementation:

- [Credential response construction](https://github.com/router-for-me/CLIProxyAPI/blob/main/internal/api/handlers/management/auth_files.go): v8 emits `quota_plugin_id` for a provider with an active quota plugin.
- [Plugin quota handlers](https://github.com/router-for-me/CLIProxyAPI/blob/main/internal/api/handlers/management/plugin_quota.go).
- [v8 route registration](https://github.com/router-for-me/CLIProxyAPI/blob/main/internal/api/server_management_v8.go).

## Normalized quota response

Schema source: [sdk/pluginapi/types.go](https://github.com/router-for-me/CLIProxyAPI/blob/main/sdk/pluginapi/types.go), especially `QuotaFetchResponse`, `QuotaGroup`, `QuotaBucket`, and `QuotaMetric`.

```json
{
  "subscription": { "plan": "Pro", "tierName": "Example tier" },
  "summary": [
    { "key": "credits", "label": "Credits", "value": 12.5,
      "format": "currency", "currency": "USD" }
  ],
  "groups": [
    { "displayName": "Usage limits", "buckets": [
      { "window": "5h", "remainingFraction": 0.75,
        "resetTime": "2026-10-14T03:00:00Z" },
      { "window": "Weekly", "remainingFraction": 0.4 }
    ] }
  ]
}
```

This is a schema illustration, not live usage. The app consumes the normalized server's camelCase output. Optional arrays and fields can be omitted. Percent used is `1 - clamp(remainingFraction, 0, 1)`. Neither missing values nor absent windows are fabricated. Date parsing supports ISO 8601 with and without fractional seconds; unparseable reset strings are shown literally.

Summary values support numeric/unit and currency rendering. Subscription plan/tier names are shown when present. Server clock-offset metadata is not used because the UI displays absolute reset timestamps rather than a countdown.

## Provider quota probes

`GET /credentials` publishes `quota_plugin_id` only when an enabled quota-provider plugin maps that provider (`ListAuthFiles` sets it from the host's quota plugin ids). When no plugin covers the provider, the instance offers no v8 quota route at all: the declarative `quota_probe` fallback exists on the v0 route only, and v8 hides it deliberately.

For the two providers the app has verified probe definitions for, it reads quota directly from the provider, asking the instance to forward one request with that credential's own access token. `$TOKEN$` in a forwarded header is replaced by the instance with the credential's access token or API key. An installed plugin always wins; a probe runs only when no plugin covers the credential.

| Provider | Request | Quota source | Mapping |
| --- | --- | --- | --- |
| `codex` | `GET https://chatgpt.com/backend-api/wham/usage` with `Chatgpt-Account-Id` from the credential's `id_token` | `rate_limit.primary_window` / `secondary_window` with `used_percent` and `reset_after_seconds` | Windows labelled `5h` and `Weekly`; remaining fraction is `1 - used_percent/100`; `resetTime` is the current time plus the reported seconds; `plan_type` becomes the subscription plan |
| `antigravity` | `POST <cloudcode-pa host>/v1internal:fetchAvailableModels` with `{"project": ...}` from the credential's `project_id`; hosts are tried in order (`daily`, `daily.sandbox`, `cloudcode`) | `models.<id>.quotaInfo.remainingFraction` and `quotaInfo.resetTime`, with snake_case spellings also accepted | Models sharing one reading collapse into one window: a single model names the window itself, several become `N models` with their ids in the description. The tightest window sorts first |

Field names, headers, and endpoints follow the CLIProxyAPI Management Center probe: `internal/api/handlers/management/auth_files.go`, `plugin_quota.go`, `api_tools.go`, `internal/runtime/executor/helps/codex_quota.go`, and `sdk/cliproxy/antigravity_models.go`.

Probe cost and failure handling:

- One forwarded request per credential per refresh cycle; antigravity stops at the first host that answers and abandons the remaining hosts on 401/403.
- A probe failure belongs to its account. It never pauses automatic refresh, because the project's 401/403 pause protects the management API's failure-based IP ban, not a provider's expired token.
- Missing `id_token.chatgpt_account_id` or `project_id` means the instance did not publish the metadata the probe needs; the account reports that instead of guessing.

## Failures

- 401/403: actionable auth/access error; stop automatic calls until Save & Test resets the pause.
- 404: management disabled, unsupported v8 endpoint, or unavailable quota plugin. No v0 fallback.
- Other HTTP failures: report status code without exposing the server response body, which could contain secrets.
- Invalid JSON: decoding error; retain the previous successful snapshot on inventory failure.
- Per-account quota failure: show the error on that account and continue the inventory.
- Cancellation: discard an interrupted refresh rather than publish a partial snapshot.

The v8 API is required. Support for a provider is determined by the running instance and its plugins; the management API does not guarantee five-hour or weekly quota support for every provider.
