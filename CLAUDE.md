# osx-claude-usage

macOS menu bar app showing Claude usage (session window, weekly, per-model) at a glance.
Greenfield. Nothing built yet.

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
| [f-is-h/Usage4Claude](https://github.com/f-is-h/Usage4Claude) | 364 | Swift, MVVM | cookie only | Clean small codebase, 8 languages, no history |
| [aqua5230/usage](https://github.com/aqua5230/usage) | 287 | Python, AGPL | local logs | Cross-platform. AGPL, so do not copy code |
| [lionhylra/cc-usage-bar](https://github.com/lionhylra/cc-usage-bar) | 16 | Swift, MIT | PTY scrape of `/usage` | Novel approach, cited above |
| [SessionWatcher](https://sessionwatcher.com/) | paid | native | mixed | $6.99 one-time. Only commercial one with traction |

Takeaway: the entire field splits into cookie-scrapers (fragile) and local-log-parsers
(incomplete). The OAuth endpoint plus the User-Agent fix skips both traps.

## Conventions

- Swift 6 + SwiftUI, AppKit `NSStatusItem` for the menu bar. macOS 14 minimum, target 26.
- `LSUIElement` true. No Dock icon, no main window.
- MIT license.
- No telemetry, no analytics, no account, no network calls except `api.anthropic.com`.
- Never write, log, or display the access token. Read from Keychain at point of use only.
- Never bundle an API key or ship credentials.
- No em dashes in any UI copy, comments, commits, or docs.

## Verified environment

- `claude` 2.1.220 at `/opt/homebrew/bin/claude`
- Keychain service `Claude Code-credentials`, account = macOS username
- 488 session JSONL files under `~/.claude/projects/`
- Current account: subscription plan, `limit_dollars` null, `member_dashboard_available` false
