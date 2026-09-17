# Optional Codex quota indicator

Settings → App Icon → Bottom dots lets users keep **Volume** (the default), or choose **Codex · 5 hours** / **Codex · Weekly**. The menu bar, Dock, and both settings previews show the same quota dots. The volume controls keep their existing behavior. The audio dot/arc style applies only in Volume mode; Codex always uses quota dots.

The four dots represent **remaining**, not consumed, usage. Zero remaining shows four dim filled tracks; positive values up to 25%, 50%, 75%, and 100% light one, two, three, and four dots respectively. Hollow dots mean unavailable, expired, or not yet loaded. The popup and settings show both supported windows, reset dates, the last successful update time, and a refresh button.

## Data source and credentials

The read-only OAuth approach is informed by [CodexBar's Codex provider documentation](https://github.com/steipete/CodexBar/blob/5e119a9ad76e3453058dab323f98e480f478d049/docs/codex.md) and its `CodexOAuthUsageFetcher` request/response schema. This is a small independent implementation; Status Trio does not depend on or bundle CodexBar.

- No credentials are read and no usage requests are sent in the default Volume mode.
- When enabled, read the native Codex ChatGPT login from `$CODEX_HOME/auth.json`, or `~/.codex/auth.json` if `CODEX_HOME` is unset. GUI apps only see environment variables inherited at launch.
- Send the access token and optional account identifier only to `https://chatgpt.com/backend-api/wham/usage`. Use an ephemeral session without persistent cookies/cache; refuse HTTP redirects and bound requests to 20 seconds.
- Never read browser cookies or session transcripts; never write, refresh, persist, or log credentials or response bodies. Native credentials are owned by Codex.
- Missing/unreadable credentials, API-key logins, Keychain-only logins, and 401/403 responses show sign-in guidance. Run `codex login` with the intended Codex home and refresh. This first version does not implement CLI RPC fallback or a separate login flow.
- Verify credentials still match after each request. Changed credentials discard that response. Previously displayed usage is held only in memory and replaced at the next refresh (at most the normal 60-second polling interval).

The `wham/usage` endpoint is **not a documented stable third-party API**. It can change or reject requests. This feature is optional and fails visibly without affecting system status.

## Refresh and interpretation

Fetch immediately on enable, then every 60 seconds independently of the 5–60-second system-status interval. Refresh on wake; deduplicate concurrent refreshes; cancel pending work on disable or app shutdown. Late results from an old mode cannot restore disabled state. Failed requests clear quota rather than retaining a misleading value.

Identify the 5-hour and weekly windows by `limit_window_seconds` (18000 / 604800), not by primary/secondary slot. Missing, malformed, unsupported-duration, reset-expired, and readings older than two minutes are unavailable, never an implicit 0% or 100%. Model-specific buckets, reset-credit inventory, API balances, and context-window usage are intentionally out of scope.

## Validation

`swift test` covers parsing and boundaries, weekly-only plans, stale/reset readings, credential selection, HTTP failures, account switches, opt-out/cancellation, settings persistence, rendering, accessibility, and localization. Network tests use fake credentials and an injected transport; the default test suite never reads a real login or contacts OpenAI.

## Fork maintenance

This fork tracks the upstream icon and system-status improvements, including the native Wi-Fi symbol, symbol scale, connected-power plug, and compact audio controls. Quota rendering and cache invalidation cover both menu bar and Dock.

`release.json` and `Support/Info.plist` target this fork's separate `fork-appcast.xml`. It is intentionally empty until fork-signed automatic updates are configured; do not add upstream releases to it. The inherited public update key is not a fork signing identity. A future auto-update release requires a fork-owned Sparkle key pair and matching public key before publishing. Current builds use `publish=false` CI artifacts and manual installation.
