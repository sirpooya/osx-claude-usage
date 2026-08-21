# osx-claude-usage

macOS menu bar app showing Claude usage (session window, weekly, per-model) at a glance.

**Not greenfield.** The codebase is [f-is-h/Usage4Claude](https://github.com/f-is-h/Usage4Claude)
(MIT, ~22k LOC Swift), taken as-is on 2026-08-21 and renamed throughout to `ClaudeUsage`. The
goal is to improve that app in place, not to rewrite it. See "Fork status" below.

## Build and run loop (do this after every change)

Non-negotiable. A build that only exists in DerivedData is useless.

1. Rebuild (`xcodebuild` ad hoc signs it for us).
2. Replace `/Applications/ClaudeUsage.app`, then verify the signature rather than re-signing.
3. Launch from `/Applications`, never from DerivedData or a temp path.
4. Update this file with what changed.

```bash
pkill -f "ClaudeUsage.app/Contents/MacOS/ClaudeUsage"
xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -configuration Debug \
  -derivedDataPath <scratch>/dd build CODE_SIGN_IDENTITY="-"
rm -rf /Applications/ClaudeUsage.app
cp -R <scratch>/dd/Build/Products/Debug/ClaudeUsage.app /Applications/ClaudeUsage.app
codesign -v --strict /Applications/ClaudeUsage.app      # do NOT re-sign, see gotchas
codesign -d --entitlements - /Applications/ClaudeUsage.app | grep -A2 app-sandbox   # expect false
open -a /Applications/ClaudeUsage.app
pgrep -lf "/Applications/ClaudeUsage.app"   # confirm it actually came up
```

Gotchas that cost time already:
- Do not launch the binary directly from a backgrounded shell. The process dies when that
  shell exits, which looks exactly like a crash in the log.
- To screenshot a window, get its id from `CGWindowListCopyWindowInfo` and use
  `screencapture -l <id>`. Region captures (`-R`) get occluded by whatever is in front.
- `defaults delete com.claudeusage.ClaudeUsage` resets first-launch onboarding state, but **not**
  the accounts: those live in our own Keychain item via `AccountStore`/`KeychainManager`, so the
  app still has credentials after a defaults wipe.
- Entitlements do not come from `Config/ClaudeUsage.entitlements` alone. Xcode 26 merges
  build-setting-derived keys over that file, so `ENABLE_APP_SANDBOX` in `project.pbxproj` wins.
  Editing only the plist left `app-sandbox = true` in the signature (the giveaway was a
  `files.user-selected.read-write` key that appears in no file we own). Both configs are now `NO`.
- The `codesign --force --deep --sign -` step in the loop above **strips all entitlements**.
  `xcodebuild` with `CODE_SIGN_IDENTITY="-"` already ad hoc signs the product correctly, so
  prefer `cp -R` plus `codesign -v --strict` to verify, and re-sign only if verification fails.
  Every `/Applications` build installed before this was discovered had therefore been running
  with no entitlements at all, which is why its data sits outside `~/Library/Containers`.
- `sips -c H W --cropOffset Y X` measures the offset **from the image centre**, not the top left,
  which makes menu bar crops land in the middle of the screen. `screencapture -x -R x,y,w,h`
  against the real menu bar strip is the reliable way to photograph the status items.
- Changing the bundle id can make Control Center hide the menu bar icon. See the
  `menubar-fix` skill.

## Goal

Beat the existing crowd of ~20 menu bar usage trackers on the two things they all get wrong:
authoritative data and history. Native, menu-bar-only, no telemetry, no account.

## Data sources (all three verified working on this machine, 2026-08-21)

### 1. Primary: OAuth usage endpoint (authoritative, server-side, cross-device)

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <accessToken>
anthropic-beta: oauth-2025-04-20
Content-Type: application/json
User-Agent: claude-cli/2.0.0 (external, cli)
```

**The User-Agent header is mandatory.** Without it the endpoint returns an instant, persistent
429 `rate_limit_error` even with a valid token. This is the single blocker that
[anthropics/claude-code#31021](https://github.com/anthropics/claude-code/issues/31021) hit and
that made most competing apps fall back to fragile cookie scraping. Verified HTTP 200 with it.

Token comes from the macOS Keychain, not a file:

```
security find-generic-password -s "Claude Code-credentials" -w
```

Returns JSON; the token is at `.claudeAiOauth.accessToken` (also `refreshToken`, `expiresAt`).
`~/.claude/.credentials.json` does **not** exist on macOS (that path is Linux/Windows only).
Access tokens expire ~60 min; refresh via the OAuth refresh token, and expect Claude Code itself
to rotate the Keychain entry underneath us. Re-read the Keychain on every poll, never cache the
token in memory across polls.

Response shape (verified):

```jsonc
{
  "five_hour": { "utilization": 44.0, "resets_at": "...", "limit_dollars": null, "used_dollars": null, "remaining_dollars": null },
  "seven_day": { "utilization": 52.0, "resets_at": "..." },
  "seven_day_opus": null, "seven_day_sonnet": null, "seven_day_cowork": null,
  "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null, "daily": null, "weekly": null },
  "limits": [                       // <- PREFER THIS. Flat, stable, self-describing.
    { "kind": "session",       "group": "session", "percent": 44, "severity": "normal", "resets_at": "...", "scope": null, "is_active": false },
    { "kind": "weekly_all",    "group": "weekly",  "percent": 52, "severity": "normal", "resets_at": "...", "scope": null, "is_active": true },
    { "kind": "weekly_scoped", "group": "weekly",  "percent": 38, "severity": "normal", "resets_at": "...",
      "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null }, "is_active": false }
  ],
  "spend": { "used": { "amount_minor": 0, "currency": "USD", "exponent": 2 }, "limit": null, "percent": 0, "enabled": false },
  "member_dashboard_available": false
}
```

Parsing rules:
- Drive the UI off `limits[]`, not the top-level `five_hour`/`seven_day` blocks. It is flat,
  carries `severity` and `is_active`, and new limit kinds appear there without a schema change.
- The top level contains codenamed keys (`nimbus_quill`, `tangelo`, `iguana_necktie`,
  `cinder_cove`, `amber_ladder`, `omelette_promotional`). These are unreleased/internal limit
  buckets, usually null. **Never hardcode or display them.** Ignore unknown keys.
- `limit_dollars` / `used_dollars` are null on subscription plans. Do not render dollar figures
  from this endpoint unless non-null.
- Money is minor units: `amount_minor` with an `exponent`, so 0 USD exponent 2 means $0.00.
- `is_active: true` marks the limit currently binding. That is the one to show in the menu bar
  when collapsed to a single number.

### 2. Secondary: local session logs (offline, per-project, historical)

`~/.claude/projects/<url-encoded-cwd>/<sessionId>.jsonl` (488 files on this machine).
One JSON object per line. Records where `type == "assistant"` carry `message.model` and
`message.usage`:

```jsonc
{
  "model": "claude-opus-5",
  "usage": {
    "input_tokens": 2,
    "cache_creation_input_tokens": 12386,
    "cache_read_input_tokens": 21212,
    "output_tokens": 100,
    "server_tool_use": { "web_search_requests": 0, "web_fetch_requests": 0 },
    "service_tier": "standard",
    "cache_creation": { "ephemeral_1h_input_tokens": 12386, "ephemeral_5m_input_tokens": 0 },
    "iterations": [ /* per-turn breakdown, same fields */ ]
  }
}
```

Other line `type` values seen: `user`, `assistant`, `attachment`, `ai-title`, `last-prompt`,
`queue-operation`, `file-history-snapshot`, `file-history-delta`. Useful sibling fields on the
envelope: `cwd`, `gitBranch`, `sessionId`, `timestamp`, `version`, `requestId`, `model`, `effort`.

Parsing rules:
- Never sum `iterations[]` on top of the parent `usage` block. The parent is already the total.
- Cache reads are billed differently from fresh input. Keep the four token classes separate all
  the way to the UI; collapsing them makes cost estimates wrong by an order of magnitude.
- Dedupe by `requestId`. The same request can appear across resumed sessions.
- Tail incrementally (track file offset + inode). Never re-parse 488 files on a poll.
- The directory name is the cwd with `/` replaced by `-`, which is lossy. Prefer the `cwd` field
  inside the records for project attribution.

### 3. Fallback: PTY scrape of `claude` + `/usage`

`claude --help` exposes no usage/limits subcommand as of 2.1.220, so the only CLI route is
spawning a PTY and sending `/usage`, as [cc-usage-bar](https://github.com/lionhylra/cc-usage-bar)
does. Zero credential handling, but slow and brittle. Keep as last resort only.

## Architecture

Fuse source 1 and source 2. Nobody in the field does this well, and it is the whole differentiator.

- **Source 1 = truth.** Percentages, reset times, which limit binds. Cross-device accurate.
- **Source 2 = detail and history.** Per-model, per-project, per-branch tokens; cache hit rates;
  real-time movement between polls; unlimited retention.
- Source 1 has no history (the endpoint only reports now). Persist every poll locally so trends
  exist. Source 2 has no server truth (misses usage from other devices, web, mobile).
- Poll adaptively: ~60s while a session is active, back off to 5 to 10 min when idle. Respect
  429s with real backoff. Never poll faster than 30s.
- Menu bar collapsed state shows the `is_active` limit. Popover shows all limits plus history.

### Differentiators to build (ranked)

1. **History and trends.** Every competitor lists this as "planned" and none shipped it.
2. **Burn-rate forecast.** "Weekly cap Thursday ~3pm at this pace" beats a raw percentage.
   Only AIQuotaBar attempts it.
3. **Attribution.** Cost and tokens per project / repo / branch / model, from source 2's `cwd`
   and `gitBranch`. Zero apps do this.
4. **macOS 26 polish.** Liquid Glass popover, LSUIElement agent, Sparkle updates, Homebrew cask.

## Competitive landscape (researched 2026-08-21)

| Repo | Stars | Stack | Data source | Note |
|---|---|---|---|---|
| [hamed-elfayome/Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker) | 3.3k | Swift, MIT | claude.ai `sessionKey` cookie + Console API key | Best UI. Dynamic Island, multi-profile. Cookie auth expires constantly |
| [tddworks/ClaudeBar](https://github.com/tddworks/ClaudeBar) | 1.4k | Swift 6.2, Tuist, Sparkle | per-provider CLIs + cookies + SQLite | 12 providers. Most active. No license file |
| [Iamshankhadeep/ccseva](https://github.com/Iamshankhadeep/ccseva) | 800 | TypeScript | local logs | Electron weight |
| [Nanako0129/TokenBar](https://github.com/Nanako0129/TokenBar) | 257 | Rust core + SwiftUI, MIT | local logs only | Best local-parsing design. No server truth. Apple Silicon only |
| [f-is-h/Usage4Claude](https://github.com/f-is-h/Usage4Claude) | 364 | Swift, MVVM | browser OAuth + cookie | **This is now our base, see "Fork status".** Not cookie-only any more: it does call `/api/oauth/usage`, just without the User-Agent fix |
| [aqua5230/usage](https://github.com/aqua5230/usage) | 287 | Python, AGPL | local logs | Cross-platform. AGPL, so do not copy code |
| [lionhylra/cc-usage-bar](https://github.com/lionhylra/cc-usage-bar) | 16 | Swift, MIT | PTY scrape of `/usage` | Novel approach, cited above |
| [SessionWatcher](https://sessionwatcher.com/) | paid | native | mixed | $6.99 one-time. Only commercial one with traction |

Takeaway: the entire field splits into cookie-scrapers (fragile) and local-log-parsers
(incomplete). The OAuth endpoint plus the User-Agent fix skips both traps.

## Fork status

Base commit: `f-is-h/Usage4Claude` main, downloaded 2026-08-21 (never cloned, so no upstream git
history). MIT, so forking and renaming is fine, but `LICENSE` keeps f-is-h's copyright notice.

Layout: app source in `ClaudeUsage/`, Xcode project `ClaudeUsage.xcodeproj`, tests in
`Tests/ClaudeUsageCoreTests` (128 tests, `swift test`). `Package.swift` is a thin manifest that
points at a handful of pure-logic files in place so they can be unit tested without Xcode. The
Xcode project is the authoritative app build.

The target uses a `PBXFileSystemSynchronizedRootGroup` over the `ClaudeUsage/` folder, so new
files are compiled automatically with no `project.pbxproj` editing.

What has been changed from upstream so far:

- Renamed everything to `ClaudeUsage`, bundle id `com.claudeusage.ClaudeUsage`.
- Every GitHub URL now points at this fork's own repo, `sirpooya/osx-claude-usage`. The rename
  pass had left two broken families behind: `f-is-h/ClaudeUsage`, a repo that never existed
  (203 references, all 404), and `f-is-h/Usage4Claude`, which resolved but documented upstream
  rather than this fork (15 references). Both are gone. Touched app code, all 7 locale files,
  `README.md`, the 6 localized `docs/README.*.md`, `CHANGELOG.md`, `CONTRIBUTING.md`,
  `appcast.xml`, `Config/Info.plist` (`SUFeedURL`), the whole `website/` tree,
  `.github/RELEASE_TEMPLATE.md`, `.agents/skills/release/SKILL.md`, `scripts/build.sh` and
  `docs/archive/`. Verified HTTP 200 for the repo root, `/issues`, `/releases`,
  `/releases/latest`, `/pulls`, `/blob/main/LICENSE`, both issue templates, the raw appcast
  feed, and all 7 localized `#initial-setup` anchors (the anchor headings are real in our own
  README copies, checked line by line).
  - The Sparkle appcast URL now resolves. Its `<enclosure>` entries still name upstream's DMG
    assets, which do not exist under this repo's releases, so the feed is reachable but not yet
    servable. Fix that before shipping any update.
  - `/discussions` returns 404 because Discussions is not enabled on the repo. It is linked from
    `README.md`, `CONTRIBUTING.md`, `website/`, and the localized READMEs. Enable the tab or
    drop those links.
  - Deliberately **not** rewritten, because they are attribution, not navigation: f-is-h's
    `LICENSE` copyright, the `Copyright (c) 2025-2026 f-is-h` and `Created by f-is-h` headers in
    the Swift and `.strings` files, `github.com/sponsors/f-is-h` (About window, menu bar menu,
    `website/`, READMEs), `.github/FUNDING.yml`, the `@f-is-h` profile links in the README
    Contact sections, and the two upstream-attribution rows near the top of this file.
  - Still stale and unrelated to links: `DiagnosticLogger.swift` uses `com.f-is-h.ClaudeUsage`
    as its `Logger` subsystem and dispatch queue label, which no longer matches the bundle id.
- Replaced both icon assets with our own artwork. See "App icon".
- Onboarding is now a single window with one path: sign in with a claude.ai account.
  - Removed upstream's first page, then the manual Session Key field, the Display Options
    block (theme, display content, smart/custom limits), the Skip button and the Finish bar.
    Display settings live in Settings; nothing here needs a "later" escape hatch.
  - Window is titled **Login** (new `window.login_title` key), 300x400, and shows app icon,
    app name, tagline and a note under the button (`welcome.tagline`, `welcome.sign_in_note`).
  - The CTA is brand-coloured via `UsageColorScheme.brand` (#D97757, display-p3, same value as
    the icon artwork).
  - `ClaudeOAuthCoordinator` already calls `addAccount` before its callback, so `WelcomeView`
    no longer re-fetches organizations. That removed the org-fetch spinner and error row.
  - With no Finish button, `willCloseNotification` sets `isFirstLaunch = false`, otherwise
    closing the window would reopen it on every launch.
- Fixed the welcome window not opening centred. See "Centring an NSWindow around SwiftUI".
- Default menu bar theme is now `.monochrome` (was `.colorTranslucent`), in `UserSettings`.
- Fixed colour-mode menu bar icons. See "Menu bar icon colour modes".
- Fixed `NSImage(named: "AppIcon")` always returning nil. See "App icon".
- Reworked the popover's no-credentials and error states, in `UsageDetailView`:
  - Upstream branched on `error.contains("Authentication") || error.contains("configured")`,
    but the actual string is "Please **configure** authentication information in settings
    first", so both tests failed and the Go to Settings button was suppressed.
  - Worse, both buttons called `onMenuAction?(.authSettings)` while one was labelled "Run
    Diagnostic". The same duplicated pair existed in the Codex block. Real diagnostics live in
    Settings > Auth > Help (`DiagnosticsView`), not here.
  - Now keyed off `UserSettings.shared.hasValidCredentials`, not string sniffing. Signed-out is
    an empty state (`usage.sign_in_prompt`) with one button that opens the login window and
    then refreshes; genuine errors get Refresh plus Go to Settings. Error text uses
    `fixedSize` so it wraps instead of truncating to "...information in...".
- Replaced the popover's ring with a list of full-width bars, one per limit, in
  `UsageDetailView` / `UsageRowComponents` / `CodexColumnView`:
  - A row is title on the left, `NN% · <countdown>` on the right, and a 5pt capsule bar
    under both. `UsageLimitBarRow` + `UsageLimitBar` are the new components; `UnifiedLimitRow`
    keeps all the per-type label / percentage / reset-time logic and now just feeds them.
  - Bar colour still comes from the per-limit palette in `UsageColorScheme` and still escalates
    with the percentage, so the colour says both which limit it is and how close it is.
  - `showRemainingMode` now defaults to **true**, so rows read "2d 7h left", not "Aug 24 2 AM".
    Read the default with `object(forKey:) as? Bool ?? true`; `UserDefaults.bool(forKey:)`
    returns false for a missing key and would silently flip it back. Tapping the list still
    toggles to absolute reset times. Percentages always read as used, never as remaining.
  - Countdowns are two units everywhere (`3h 41m left`, `2d 7h left`). `codexSecondary` used
    `formattedCompactRemainingWithMinutes` and printed a third unit (`3d 4h 48m left`); it now
    uses `formattedCompactRemaining` like every other row. No week unit: no limit window is
    longer than 7 days, so days is the largest useful one.
  - Both columns use the same rows, so Claude and Codex line up in two-provider mode.
  - Popover height is computed in `PopoverMetrics` (row 26, row spacing 12, chrome 18 + 20 + 10,
    empty states 210) plus `contentSpacing`, the fixed 16 between the title row and the bars.
    The bottom is deliberately the tightest of the three gaps: leftover slack lands there and
    reads as dead space, while the bars need air under the title. `contentSpacing` used to
    tighten to 10 for two or more limits, which only made sense while a 114pt ring sat under the
    title. `claudeRowCount` also counts the third-and-later model rows, which the old ring-era
    math left out, so a Fable + Opus + Sonnet account no longer gets its last row clipped.
  - Deleted with the ring: `MiniProgressIcon`, `DetailUsageRingCenterText`,
    `DetailUsageRingSweep`, `AnimationTypeHintView`, the ring trim helpers, every ring loading
    animation in `UsageDetailView+Helpers.swift` and `CodexColumnView`, and the long-press
    `LoadingAnimationType` switcher that only existed to pick between those animations. Bars
    breathe while refreshing instead. The `loading_animation.*` keys are now unused in all 7
    locale files.
  - `usage.title` is just "Claude" in all 7 locales, not "Claude Usage". The header already has
    the app icon next to it, so the word was redundant. `usage.codex_title` is still
    "Codex Usage".
- Trimmed the status item menu, in `MenuBarUI.createStandardMenu` and the matching SwiftUI
  `Menu` in `UsageDetailView`. Both have to change together or the right-click menu and the
  popover's three-dot menu disagree.
  - General Settings and Authentication Settings collapsed into one **Settings** item
    (new `menu.settings` key, all 7 locales) wired to `openSettings` / `.generalSettings`,
    which opens tab 0. The Auth tab is one click away inside the window, and the popover's
    "Go to Settings" buttons still deep-link to tab 1 via `.authSettings`, so both
    `L.Menu.generalSettings` and `L.Menu.authSettings` are now unused but their keys and the
    `MenuAction` cases stay.
  - Check for Updates is disabled (`isEnabled = false`, `.disabled(true)`) until the Sparkle
    appcast URL is repointed. This also required `menu.autoenablesItems = false`, otherwise
    AppKit re-enables any item that has a target and an action.
  - `menu.quit` is now just "Quit", not "Quit ClaudeUsage", and the item carries no icon.
- A failed refresh can no longer blank the popover. This is the "Too many requests, please try
  again later" screen that replaced perfectly good numbers on any transient 429:
  - Root cause of the errors themselves: `ClaudeOAuthService.post` (the token endpoint at
    `console.anthropic.com/v1/oauth/token`, used by both the initial exchange and every refresh)
    was the one request in the app **not** sending `User-Agent`. The usage and profile calls both
    set it. Without it this endpoint family answers a valid token with an instant 429, so once an
    access token expired (~60 min) every fetch failed. Fixed; see "Data sources" above.
  - The 429 actually observed on 2026-08-21 was a genuine server side limit from restarting the
    app in a tight loop (two agent sessions doing install-and-run at once), not the header bug.
    Verified by probing `/api/oauth/usage` directly with the app's exact headers: HTTP 200 while
    the popover was showing the error. Both causes are now handled the same way.
  - What the UI does now, which is what [hamed-elfayome/Claude-Usage-Tracker] does structurally:
    its `UsageRefreshCoordinator` only ever calls `dataStore.saveUsage(...)` on success and its
    `catch` blocks just log, so its views render the last saved snapshot and a failed request
    cannot produce a visible state. Ours had `errorMessage` as a UI state that took priority over
    the data, which is the whole difference.
  - So: `usageData` is never cleared on failure (it already was not, but `claudeMainContent`
    checked `errorMessage` **first**, so the error won anyway). Data now wins; the error branch is
    only reached with nothing cached at all.
  - Transient errors (429, network blip, 5xx, decode) never get a screen. `RefreshState`
    `claudeErrorIsTransient` gates that: transient means bars, or the loading state, never an
    error. Only actionable auth errors (no credentials, unauthorized, session expired, Cloudflare)
    still get the signed-out or error state, because the user has to do something about those.
  - The last good fetch is persisted (`cachedClaudeUsage` / `cachedClaudeUsageAt` in UserDefaults,
    which is why `UsageData` and friends are now `Codable`) and restored in `DataRefreshManager.init`,
    so a cold start shows real numbers instead of a spinner. Percentages and reset times only, no
    credentials.
  - When stale data is on screen, a one line note under the bars says so:
    "Couldn't refresh · showing 9:20 PM" (`usage.stale_notice`, 7 locales). `PopoverMetrics`
    `staleNoticeHeight` reserves its height (text 13 + row spacing 12 + `staleNoticeTopGap` 8:
    it is not a limit row, so it does not sit at the same rhythm as one), and `claudeColumnHeight`
    is now the single place that decides the Claude column's height, so the height rule and the
    render rule cannot drift apart.
  - A 429 also arms a 10 minute backoff (`claudeBackoffUntil`): automatic polls sit it out, the
    Refresh button ignores it because the user asked. Skipping a poll never clears the cached data.
  - A Codex failure keeps its last data too (it used to call `clearCodexUsageState`).
- The popover header's ellipsis menu is now a gear that opens Settings directly. Everything that
  menu carried (account switching, check for updates, About, status pages, Buy me a coffee, Quit)
  is still on the status item's right click menu, `MenuBarUI.createStandardMenu`. The update dot
  moved onto the gear so the signal is not lost.
- Translated all hardcoded Chinese in UI strings and the 148 logger messages to English.
- **CLI Account Sync**: the app now logs itself in from Claude Code's own Keychain entry, so a
  fresh install needs no pasted session key and no browser round trip. This is the login method
  the 3.3k-star `hamed-elfayome/Claude-Usage-Tracker` uses (its `CLI Account` credential row,
  alongside `Claude.ai` cookie and `API Console`), and the reason it feels zero-setup next to
  everything else in the field. New and changed pieces:
  - `Services/ClaudeCodeCredentials.swift` reads the entry with the Security framework, never by
    shelling out to `security(1)` (which would put the plaintext token in another process's
    pipe). It enumerates *attributes* first to find every `Claude Code-credentials*` service
    (suffixed variants exist per `CLAUDE_CONFIG_DIR`), and only reads secret data for the chosen
    one, so the authorization prompt happens once rather than per candidate.
  - `Services/ClaudeCodeSyncService.swift` turns that entry into a normal Claude account, pulling
    `/api/oauth/profile` for the display name. `pinnedService` (persisted at
    `cliSync.pinnedService`) lets a multi-config user nail the sync to one entry.
  - `Account` gained `credentialSource` (`.manual` / `.claudeCodeCLI`) and `keychainService`, both
    `decodeIfPresent` so existing stored accounts migrate untouched.
  - `ClaudeAPIService.fetchCLISyncedUsage` re-reads the Keychain on **every** poll and uses the
    CLI's `accessToken` directly while it is still valid, which costs zero extra requests and
    leaves the CLI's refresh token alone. Only when it has actually expired do we run the refresh
    grant ourselves, and then we **write the rotated pair back into Claude Code's Keychain entry**
    (preserving the entry's other fields). That write-back is not optional: refresh tokens are
    single use, so skipping it would silently log the user out of their own CLI on our next poll.
  - Startup gate in `ClaudeUsageMonitorApp.applicationDidFinishLaunching` tries the sync before
    deciding whether to show the welcome window, and marks first launch complete when it lands.
    It deliberately backs off when accounts already exist, so it never overrides a manual login.
  - `AuthSettingsView+CLIAccount.swift` is the settings card: sync status, masked access token,
    subscription type, scopes, Re-sync / Remove, plus the Keychain entry picker (shown only when
    more than one entry exists). Only the masked token is ever displayed.
- **App Sandbox is now off** (`ENABLE_APP_SANDBOX = NO` in both configs, and the entitlements
  file documents why). Inside the sandbox, Keychain access is confined to the app's own access
  group, so reading Claude Code's entry is impossible no matter what else is granted. The
  competitor ships unsandboxed for exactly this reason. Cost: no Mac App Store, which the
  Homebrew cask plan never wanted anyway.
- Added the mandatory `User-Agent: claude-cli/2.0.0 (external, cli)` header to both
  `/api/oauth/usage` and `/api/oauth/profile` (`ClaudeOAuthConfig.userAgent`). Upstream omitted
  it, which is the instant-persistent-429 trap documented under "Data sources" above.
- Dropped the "Advanced:" prefix from the manual session key label in all 7 locales
  (`welcome.manual_session_key`). It is a plain alternative input, not a hazardous setting.
- New `L.CLISync` localization namespace. The 21 keys carry English copy in all 7 locale files;
  de / fr / ja / ko / zh-Hans / zh-Hant still need real translations.
- **Credentials settings rebuilt as a two pane sidebar**, replacing the single scroll Auth tab.
  Sidebar rows are Claude.ai, API Console, CLI Account and Codex under CREDENTIALS, plus
  Diagnostics under TOOLS, each credential row carrying its own connected dot. Settings window
  went from 500x550 to 720x600 to fit it. `AuthSettingsView+Sidebar.swift` owns the shell;
  `legacyStackedBody` keeps the old layout around for reference only.
- **API Console is new functionality, not just a row.** `Services/ConsoleAPIService.swift` talks
  to `console.anthropic.com/api`: `/organizations` to validate a pasted console session key,
  `/organizations/<id>/current_spend` and `/organizations/<id>/prepaid/credits` for the figures.
  Money arrives in cents. The session key and chosen organization live in our Keychain item
  through three new named accessors on `KeychainManager` (`saveConsoleValue` and friends), so
  every credential in the app still enters through that class rather than touching `storage`.
- The three panes follow the competitor's design, which is deliberate and worth preserving:
  filled `.borderedProminent` for a card's primary action, bordered red tint for destructive,
  quiet bordered for Refresh and Back, title case card headers with a secondary subtitle line,
  hairline separated detail rows with accent colored icons, and a 1-2-3 stepper whose connectors
  stretch full width. All of it lives in `Views/Settings/Credentials/CredentialsChrome.swift`,
  which carries that contract as a comment so the panes cannot drift apart.
  - One intentional divergence: their label reads "Advanced: Manual Session Key", ours is just
    "Manual Session Key". It is a plain alternative input, not a hazardous setting.
- The CLI Account status card shows elapsed time since the last sync. `lastSyncedAt` persists in
  `UserDefaults` under `cliSync.lastSyncedAt`, and the pane re-renders on a 30s timer, otherwise
  the line sits frozen at whatever it said when the window opened.
- **Menu bar icon style is one switch now, not three radios.** `iconStyleMode` keeps all three
  cases for stored prefs, but the UI offers only Monochrome on or off (off maps to
  `.colorTranslucent`). The default flipped from `.monochrome` to `.colorTranslucent`, so the
  status colors carry the information and monochrome is the opt in. Per the
  `menubar-icon-theming` skill, which encodes this preference.
  New keys added by this fork are written in all 7 locales, not English-only.
- Dead code left behind by the above: `MenuBarIconPreview` and `HorizontalRadioGroup` in
  `WelcomeSupportingViews.swift` now have no callers.
- About page: GitHub Sponsor button removed, and Buy Me A Coffee now opens `ko-fi.com/pooya`
  (was upstream's `ko-fi.com/1atte`) in both `AboutView.swift` and the two `MenuBarManager.swift`
  menu actions. The `website/` pages still carry the old ko-fi link.
- **Relicensed to Pooya Kamel.** `LICENSE` now leads with `Copyright (c) 2026 Pooya Kamel` and
  keeps f-is-h's line (MIT requires retaining it, annotated "original Usage4Claude"). About page
  Developer row reads "Pooya Kamel"; `settings.about.copyright` is "© 2026 Pooya Kamel" in all
  7 locales (a name, so not translated). The `Created by f-is-h` / `Copyright f-is-h` headers in
  Swift files stay, per the attribution rows above.
- **Version reset to 1.0.0** (`MARKETING_VERSION` in both configs; `CURRENT_PROJECT_VERSION`
  tracks it). This fork versions independently of upstream's 3.x line.
- **Settings tab bar restyled** to the icon-toolbar shared by osx-download-manager /
  osx-launchpad: `ToolbarButton` is now glyph (18pt hierarchical, filled variants) over an 11pt
  caption, accent-tinted when selected over a 0.05 primary pill (0.035 on hover), intrinsic width
  with `minWidth: 52`, radius-9 continuous pill. Items sit centred with 2pt spacing instead of
  splitting the bar into thirds; `TabDivider.swift` deleted (no other callers). The divider under
  the bar is softened with `.overlay(Color.primary.opacity(0.03))`. The English
  `settings.tab.auth` label is "Authentication", not "Authentication Settings" (other locales
  already had the short form). The settings window now carries no titlebar text at all,
  download-manager style: `titleVisibility = .hidden`, `titlebarAppearsTransparent`,
  `.fullSizeContentView` (tab bar at the very top, close button floating over its left end),
  miniaturize/zoom hidden, `isMovableByWindowBackground = true` so the window still drags. The
  `.languageChanged` observer that re-set the title is gone. `window.settings_title` says just
  "Settings" in all 7 locales but is currently unused. Tab items share one fixed 96pt width
  (fits fr "Authentification" at 11pt) so the pills line up evenly.
- **About tab rebuilt in the osx-launchpad layout** (icon 104pt, 22pt semibold name, version
  pill, grouped rounded cards of 36pt rows, tertiary copyright): an info card (Developer,
  License) and a links card (GitHub, Report Issue, Buy Me A Coffee; `settings.about.report_issue`
  is a new key, translated in all 7 locales, opening the repo's /issues) with fully tappable rows, accent arrow,
  hover underline and pointing-hand cursor. Content column capped at 420pt inside the 720pt
  window. The card/row/divider/pill pieces are private to `AboutView.swift` and copy launchpad's
  `SettingsComponents` metrics (radius 12 continuous, labelColor 0.05 fill, hairline 0.06,
  row padding 12). `AboutInfoRow.swift` in Components is now dead code.
- **SettingCard header glyphs removed** on the General tab: the card renders title only; the
  `icon`/`iconColor` parameters are still accepted but ignored so no call site changed, and the
  32pt content indent that existed to align under the glyph is gone.
- **Sparkle updates are live again.** `SUPublicEDKey` in `Config/Info.plist` is now this
  machine's own Sparkle keypair (public `XPeIzL4GHFXBMLCP+A/vxqQE4Bn8tGi7jkw9sRBHXSc=`, private
  key in the login Keychain, shared with the other osx-* apps; `generate_keys -p` prints it).
  `appcast.xml` dropped upstream's six 3.x items, whose DMGs do not exist under this repo and
  whose signatures were f-is-h's; the channel is valid but empty until the first v1.x release is
  cut per `docs/SPARKLE_SETUP.md` (sign_update lives in the SPM artifact,
  `SourcePackages/artifacts/sparkle/Sparkle/bin/`). Check for Updates re-enabled in
  `MenuBarUI.createStandardMenu`. ⚠️ Until the cleaned appcast is pushed to main, the raw
  feed URL still serves the old committed appcast listing v3.3.0, which the new public key
  would refuse anyway; push before testing an update check.

Deliberately **not** translated, because doing so breaks non-English locales:

- CJK date format patterns in `TimeFormatHelper.swift` and `UsageData+Formatting.swift`
  (`"M月d日"`, `"H时"`, `"H時"`, `"M월d일"`). These are format strings, not copy.
- The zh/ja/ko AM/PM marker list used for parsing in `TimeFormatHelper.swift`.
- Localized documentation URL anchors in `SetupStepView.swift` (`#首次配置` and friends).
- ~~`error.contains("认证")` in `UsageDetailView.swift`~~ removed. Classifying by error string
  was the bug described above; the popover now checks `hasValidCredentials` instead.
- `zh-Hans.lproj` / `zh-Hant.lproj`, and the language endonyms (`日本語`, `中文（简体）`) that
  every locale file carries. Those are correct as they are.
- The doc-comment `- Returns:` / `- Examples:` lines in `TimeFormatHelper.swift` and
  `UsageData+Formatting.swift` that quote sample output of those CJK patterns (`"12月16日 15:42"`,
  `"15时"`). The prose around them is English; the quoted samples have to match what the formatter
  actually prints, so translating them would make the doc comment wrong.

All Chinese code comments and doc comments are now English: 2,573 line comments across 94 Swift
files (including the two tests-only files), plus the `/* */` block holding the alternative colour
schemes in `ColorScheme.swift`, the OSLog levels doc block in `LoggerExtension.swift`, and the one
Chinese `XCTAssert` message in `NotificationDecisionEngineTests.swift`. Translated by extracting
every unique comment payload (2,366 of them), translating each once, and rewriting only the comment
side of each line, so string literals could not be touched by accident. Verified with a CJK sweep
over `ClaudeUsage/` and `Tests/`: the only characters left are the ones listed above as deliberately
kept. `swift test` still passes 128/128.

Still upstream's, still Chinese: `scripts/build.sh` and parts of `README.md`, `CHANGELOG.md`,
`docs/`, and `website/`.

## Menu bar icon colour modes

Two modes, and one rule that explains every bug here:

| Mode | Flag | What AppKit does |
|---|---|---|
| Monochrome | `image.isTemplate = true` | **Discards RGB, keeps alpha.** AppKit re-tints to match the bar. |
| Colour | `isTemplate = false` | **Every colour is literal.** You own all contrast. |

Upstream drew both modes with the same hardcoded colours, so monochrome looked correct by
accident while colour mode rendered the literal values: a black glyph (the unreadable dark "0"
on a dark bar), a `gray 0.5` track ring (the stray grey border) and a `white 0.5` backing disc
(the milky wash). Monochrome was not working, it was hiding the bug.

- `UsageColorScheme.menuBarForeground(for:)` / `menuBarTrack(for:)` resolve white on a dark bar
  and near-black on a light one. Use them for every glyph, track and disc in colour mode.
- Probe appearance from `button.effectiveAppearance.bestMatch(from:)`, never `NSApp`. The bar
  goes dark under a dark desktop picture even in light mode. `UsageColorScheme.isDarkMode(for:)`
  already does this; pass the `NSStatusBarButton` through.
- Dynamic colours (`labelColor`, `secondaryLabelColor`) resolve against whatever appearance is
  current inside `lockFocus()`, which is the app's, not the bar's. Resolve explicitly instead.
- The same glyph bug existed four times: `MenuBarIconRenderer.createCircleImage` plus the
  rounded-square, diamond and hexagon shapes in `ShapeIconRenderer`. Each adapted its stroke
  correctly and then drew its number in `NSColor.black`.
- `createCircleTemplateImage` still draws black on purpose. It is a template, so only alpha
  survives. Do not "fix" it.

The competing app (`HamedElfayome.Claude-Usage`, MIT) sidesteps the problem differently: it
fills the shape with the saturated status colour and knocks the glyph out in white, so contrast
comes from its own fill rather than the backdrop. Its setting is a single `Monochrome` toggle
subtitled "Use adaptive color instead of status colors (green/orange/red)". Full write-up in the
`menubar-icon-theming` skill.

### Per-display appearance (two monitors, opposite wallpapers)

Each display's menu bar picks its own appearance from the wallpaper behind it, so a colour icon
whose greys were resolved against one bar renders wrong on the other monitor. Template icons
never had the problem (AppKit re-tints and also dims them per bar); `button.effectiveAppearance`
is a single value, so probe-then-recolour can only ever match one display. Fixed 2026-08-21 and
verified live in both directions (light bar active with dark bar dimmed, and the reverse).

Everything lives in `MenuBarPerDisplayIcon.swift` plus the colour path of
`MenuBarUI.updateMenuBarIcon`:

- The icon is a dynamic image, `NSImage(size:flipped:drawingHandler:)`. The handler runs once
  per bar appearance (NSImage caches variants per appearance since 10.14), reads
  `NSAppearance.currentDrawing()` (the Swift spelling; `currentDrawingAppearance` does not
  compile), pins `UsageColorScheme.drawingIsDarkOverride` (Method 0 in `isDarkMode(for:)`, wins
  over the button probe) and re-renders, so tonal parts resolve per display while accent
  colours stay literal. The render closure passes `button: nil` and captures `iconRenderer`,
  not `self`. A probe render fixes the wrapper's size up front (geometry is
  appearance-independent).
- Inactive-bar dimming happens inside the same handler. macOS dims menu bar items on the
  inactive display's bar, but only through the template tint (measured live with lldb:
  `appearsDisabled` is NO on every button, every window's alpha is 1), so colour icons must
  dim themselves. The active display comes from private SkyLight,
  `SLSCopyActiveMenuBarDisplayIdentifier(SLSMainConnectionID())`, dlsym'd and runtime-guarded
  (unavailable = full brightness everywhere). The handler maps the appearance it is drawing
  for back to the bars that have it: when every such bar is inactive, the draw is dimmed to
  `inactiveDimAlpha` (0.01). When both bars share one appearance the mapping is ambiguous and
  nothing dims; full brightness is the safe wrong answer.
- The dim state is baked into the per-appearance cached variant, so `refreshDimIfNeeded()`
  rebuilds the wrapper (a new NSImage instance, one write to the main button) whenever the
  active-display UUID changes. Watchers: a 2s heartbeat (no event fires when focus moves
  between displays within one app; the check is one string compare), the undocumented
  `NSWorkspaceActiveDisplayDidChangeNotification`, `didActivateApplicationNotification`,
  `activeSpaceDidChangeNotification`, and `didChangeScreenParametersNotification`.
- Colour icons bypass the icon cache (wrapper creation is free, rendering is lazy per draw);
  only template icons are cached. Template mode needs none of this, AppKit tints and dims
  templates per bar natively.

Dim status as of 2026-08-21 night: colours per display are solid and verified in both focus
directions. The dim is solid on the bar hosting the real item; on the replicant bar it only
takes effect when macOS re-snapshots the item, because a replicant's bitmap refreshes ONLY at
item (re)creation. Verified immune to: image reassignment, length nudges,
contentView.setNeedsDisplay, pixel-changing beacons, 28s waits. Current levers: the dim
decision is anchored on the main window only (replicant windows lie: zero frames, nil screens
mid-lifecycle, a phantom third per-Space window), and `refreshDimIfNeeded` blips
`statusItem.isVisible` off/on (public API, rate-limited to one per 5s) on focus-display change
to force a re-snapshot. OPEN ISSUE: the launch-time snapshot of the secondary bar still
sometimes renders undimmed; if the blip proves insufficient, the next lever is blipping at
first-data rather than only on flips.

Hard-won negative knowledge. Do not retry these:

- **Writing images into the replicant status bar windows** (the private
  `NSStatusItemReplicant` machinery; the app hosts one `NSStatusBarWindow` per display and
  per Space, all in `NSApp.windows`) works briefly, then AppKit recreates and re-syncs those
  windows behind us, and repeated writes make Control Center pull the item from EVERY bar
  while `menubar-fix.sh list` still says allowed. `killall ControlCenter` brings it back
  instantly. The bar windows also report a bogus `windowNumber` (0x100000000), they are not
  really ours to drive.
- **`SLSSetWindowAlpha` on those windows**: same vanish, same heal.
- `nm -gU` on SkyLight finds nothing because the binary lives in the dyld shared cache; probe
  with `dlopen`/`dlsym` (that is how `SLSCopyActiveMenuBarDisplayIdentifier` was verified).
- Item exists with a valid image but invisible on every bar = Control Center suppression, not
  a rendering bug. Heal with `killall ControlCenter`; rule out the blocklist with the
  `menubar-fix` skill.

## Centring an NSWindow around SwiftUI

`welcomeWindow.center()` does not work here and neither does `setContentSize` before it. A
SwiftUI fixed `.frame` reaches the window through Auto Layout **after** the creating method
returns, so `center()` runs against the pre-layout intrinsic size (518x664 for this view), then
the window shrinks to its real size from the top-left and keeps the wrong origin. The result
was 146pt too high.

Things that did **not** fix it: `setContentSize` then `center()`, `hostingController.sizingOptions = []`,
and `contentView?.layoutSubtreeIfNeeded()` before `center()`.

What works is skipping `center()` and setting size and position in one `setFrame`, computed from
a size known up front:

- `WelcomeView.contentSize` is the single source of truth, used by both the view's `.frame` and
  the window. If those two disagree the centring is wrong again.
- `frameRect(forContentRect:)` converts content size to frame size (title bar included).
- Centre horizontally on `screen.frame` for true optical centre, vertically on
  `screen.visibleFrame` so the menu bar does not bias it upward.

Beware when verifying: with a right-hand Dock, centring a 518pt-wide window on the full screen
and centring a 460pt-wide one in `visibleFrame` land within 2pt of each other, so three
different wrong fixes all produced byte-identical coordinates. Measure with
`CGWindowListCopyWindowInfo` and compare against `(screen.width - window.width) / 2`.

## Conventions

- Swift 6 + SwiftUI, AppKit `NSStatusItem` for the menu bar. Deployment target is macOS 13.0
  (upstream's), project setting 26.0. The CLAUDE.md goal of "macOS 14 minimum" is not what the
  project file currently says.
- Upstream code comments are in Chinese. When editing their files, match the surrounding style.
- `LSUIElement` true. No Dock icon, no main window.
- App Sandbox off, deliberately, so CLI Account Sync can read Claude Code's Keychain entry.
  See "Fork status". Do not re-enable it without removing that feature first.
- MIT license.
- No telemetry, no analytics, no account, no network calls except `api.anthropic.com`.
- Never write, log, or display the access token. Read from Keychain at point of use only.
  Known violation to fix: the app persists the account's session key in plain UserDefaults
  under `DEBUG_accounts` (seen 2026-08-21 via `defaults read`). It belongs in the Keychain.
  The CLI Account settings card shows a masked token only (`ClaudeCodeCredentials.maskedAccessToken`),
  and there is deliberately no reveal or copy affordance for it.
- Never bundle an API key or ship credentials.
- No em dashes in any UI copy, comments, commits, or docs.

## App icon

An Icon Composer bundle (Xcode 26 native format), authored from a single 1024pt SVG of the
Claude-orange pixel glyph. Source of truth for the artwork is `Assets/appicon.svg`, fill
`#D97757` (display-p3 0.8510 0.4667 0.3412).

Two distinct assets, and both have to be updated or the logo changes in half the app:

1. **`ClaudeUsage/Resources/appicon.icon`** is the real app icon: Finder, Get Info, Spotlight,
   notification banners, the DMG. `LSUIElement` is true so there is no Dock icon.
   - `icon.json` config: fill `system-light`, `glass: false`, neutral shadow at 0.5,
     translucency 0.5. Glyph scaled 0.9 with a +26.48pt y translation so it sits optically
     centred inside the squircle. Squares shared across platforms, circles for watchOS.
   - Wired via `ASSETCATALOG_COMPILER_APPICON_NAME = appicon` in both build configs. The name
     is lowercase `appicon`, **not** `AppIcon`, because the inherited asset catalog already has
     an `AppIcon` image set (see below) and two assets cannot share a name.
   - `actool` emits `CFBundleIconName` and `CFBundleIconFile` into the partial plist, so never
     hand-write those keys in `Info.plist`.
   - The `.icon` lives inside the `ClaudeUsage/` folder because the Xcode target uses a
     `PBXFileSystemSynchronizedRootGroup`, so anything dropped there is compiled automatically.

2. **`ClaudeUsage/Resources/Assets.xcassets/AppIcon.appiconset`** is the *in-app* logo. It
   appears in the login window, the popover header, About, account rows, and the colour menu
   bar theme. Changing only the `.icon` leaves this one stale, which is exactly the bug that
   shipped once already.
   - **`NSImage(named: "AppIcon")` always returns nil.** An `.appiconset` is compiled as icon
     data, never as a named image, so every call site silently fell back to a placeholder: a
     blue `chart.pie.fill` in the popover header, a plain circle for the colour menu bar theme,
     and nothing at all in the login window. Verified with
     `assetutil --info .../Assets.car`, which lists `AppIconReverse`, `CodexIcon` and
     `CodexIconReverse` but no `AppIcon`.
   - `ImageHelper.namedImage(_:)` is the single fallback: it tries `NSImage(named:)` first, then
     `NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)` for the `AppIcon` name only.
     `createAppIcon` and `createSquareIcon` both route through it, so do not reintroduce a bare
     `NSImage(named: "AppIcon")`.
   - Regenerate it from the composed system icon rather than from the raw SVG, so it matches the
     real app icon including Apple's squircle and material. Install the app, then extract with
     `NSWorkspace.shared.icon(forFile:)` drawn into a 1024 `NSBitmapImageRep`, and `sips -Z` that
     down to 16, 32, 64, 128, 256, 512, 1024.
   - `AppIconReverse.imageset` is the monochrome sibling used by the Monochrome menu bar theme.
     It is `template-rendering-intent: template`, so only alpha matters. Generate it as a tight
     square-cropped glyph: `rsvg-convert -w 1024 -h 1024`, then
     `magick ... -trim +repage -background none -gravity center -extent square -resize 512x512`.

## Verified environment

- `claude` 2.1.220 at `/opt/homebrew/bin/claude`
- Keychain service `Claude Code-credentials`, account = macOS username
- 488 session JSONL files under `~/.claude/projects/`
- Current account: subscription plan, `limit_dollars` null, `member_dashboard_available` false
