# ClaudeUsageBar

A macOS menu bar app that polls Anthropic's undocumented usage endpoint and
shows session/weekly consumption at a glance, without opening claude.ai or
Claude Code.

## What this actually is

This is **not** built on any published Anthropic API. It calls the same
endpoint (`GET https://api.anthropic.com/api/oauth/usage`) that powers
claude.ai's Settings → Usage page and Claude Code's `/usage` command,
authenticated with the OAuth token Claude Code stores locally after you sign
in with a Pro/Max/Team account. This is how several existing open-source
tools (ccusage, Claude-Code-Usage-Monitor, claudeusage-mcp) already work.

Because it's unofficial:
- Field names in the response are guessed in `UsageModels.swift` and may not
  match what your account actually returns. See "First run / debugging"
  below — you will very likely need to adjust the key paths there.
- The endpoint, auth scheme, or its very existence could change without
  notice. There's no SLA on any of this.
- It only reflects the personal OAuth-token view. On Team/Enterprise seats,
  admins may see usage differently (org console), so check whether this
  endpoint returns anything meaningful for your seat before relying on it.
- Pro/Max plans share one usage pool across claude.ai chat, Desktop,
  mobile, and Claude Code, so this token's numbers should reflect your
  whole-account usage, not just Claude Code activity.
- This only reads status; it doesn't send prompts, so polling it doesn't
  itself burn into your plan's usage.

## Prerequisites

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`) for the Swift
  toolchain
- Claude Code installed and logged in **at least once** with your
  Pro/Max/Team account, so the `Claude Code-credentials` Keychain item
  exists. You don't need to keep using Claude Code day to day.

## Build & run

```bash
cd ClaudeUsageBar
swift run
```

## Terminating
Run one of these on your Mac (not in this sandbox):

1) If the Terminal tab that ran 'swift run' is still open:
   fg
   (press Enter, then Ctrl+C to quit it properly)

2) If that tab is gone or fg doesn't respond:
   pkill -x ClaudeUsageBar

3) If it still won't die:
   ps aux | grep ClaudeUsageBar
   kill -9 <the PID>

The first run will trigger a macOS Keychain prompt ("ClaudeUsageBar wants
to access key 'Claude Code-credentials'"). Choose **Always Allow** so
future polls don't prompt again.

You should see a menu bar item like `S 12% · W 4%`. Click it for reset
countdowns, a manual refresh, and quit.

## First run / debugging the response shape

The exact JSON that `/api/oauth/usage` returns isn't documented, so
`UsageModels.swift` tries several plausible key names and may come up
empty (you'll see `?%` in the menu bar). To find the real field names:

```bash
CLAUDE_USAGE_DEBUG=1 swift run
```

This prints the raw JSON payload to the console on every fetch. Match its
actual structure against the `paths` arrays in `UsageSnapshot` (in
`UsageModels.swift`) and adjust them accordingly.

## Running it permanently without a terminal window open

`swift run` is fine for development but keeps a terminal attached. For
day-to-day use:

```bash
swift build -c release
```

This produces a standalone binary at `.build/release/ClaudeUsageBar`. Add
that binary to **System Settings → General → Login Items** to launch it at
login. It already calls `setActivationPolicy(.accessory)` at runtime, so it
won't show a Dock icon or app-switcher entry even as a bare binary — you
don't need to wrap it in a full `.app` bundle unless you want a custom icon
or want to distribute it to someone else.

## Tuning

- `StatusBarController.pollInterval` — how often the UI asks for fresh data
  (default 60s).
- `UsageAPI.minimumPollInterval` — hard floor under that, regardless of UI
  requests (default 45s), to avoid tripping the endpoint's rate limiting.
