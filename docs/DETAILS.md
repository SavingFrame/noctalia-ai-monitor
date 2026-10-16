# Technical details

Noctalia v5 bar widget and panel for Pi and Claude Code activity and account quotas.

## Features

- Circular account-usage meters on the bar, with provider icons and percentages.
  Each meter shows the 5-hour window (weekly fallback is labeled `7d`). Different
  Codex accounts stay separate. Missing usage is `?`, never a fake zero.
- Short lifecycle badges such as `Pi working` or `Claude needs input`. Concurrent
  states remain visible; identical states are grouped. Idle badges are hidden
  while any provider is busy or needs attention. No agents means no status badge,
  not a placeholder. Unconnected agents remain
  `running` rather than being guessed idle.
- Weekly usage at 90% or above gets a compact `7d 95%` warning, including
  model-specific Claude windows. Expired windows do not keep warning.
- Observed working-to-idle transitions show a green `done` badge for 10 seconds,
  fading during the last 2 seconds. Waits, errors, session switches and vanished
  processes are not completion. This is a polling-based cue, so turns entirely
  between scans can be missed.
- Successful quota readings older than 10 minutes are dimmed and labeled `stale`.
  Missing/invalid check times and reset windows with nonzero usage also get a
  freshness warning. Per-account check times take precedence over collection
  time. The panel and copied summaries identify stale readings too.
- Click a meter for Usage or an activity badge for Sessions. Hover for all quota
  windows and session states. Layout adapts to horizontal and vertical bars.
- Separate Usage and Sessions tabs. Provider cards show usage bars, percentage
  badges, and live reset countdowns in local time. Session rows expand for details.
- Header actions copy a quota summary or refresh usage (30-second UI cooldown).
- Pi extension: session identity/name, model/provider, working/idle/error,
  parallel tool activity, blocking UI prompts, estimated context usage.
- Claude hooks: session identity/model, working/idle/error, tool activity,
  questions and permission prompts. Hooks never return decisions or modify actions.
- Real Codex and Claude subscription usage windows and reset timestamps.
- Codex aliases for the same account are deduplicated. Different accounts get
  separate quota sections.
- Process discovery works without either bridge, but reports only `running`.
- Configurable local activity polling (default 1 second), 10-second Pi heartbeat,
  5-minute quota polling, and clearly labelled demo mode.

Requires Linux, Node.js 22+, Noctalia v5 with plugin API 24+, and Pi and/or
Claude Code. Pi uses its normal TypeScript extension loader. There are no npm
dependencies to install.

## Installation

Clone this repository into a permanent location:

```sh
git clone https://github.com/SavingFrame/noctalia-ai-monitor.git ~/.local/share/noctalia-ai-monitor
cd ~/.local/share/noctalia-ai-monitor
noctalia plugins lint ai-monitor
noctalia msg plugins source add ai-monitor-dev path "$PWD"
noctalia msg plugins enable archie/ai-monitor
npm run install:integrations
```

The source name `ai-monitor-dev` is just a local label, not a development-mode
requirement. This checkout-based installation works without a plugin registry.

`npm run install:integrations` configures both Pi and Claude Code. Skip it if
you only want process discovery and quotas without detailed lifecycle status.

The integration installer:

1. Symlinks `~/.pi/agent/extensions/noctalia-ai-monitor` to `integrations/pi`.
2. Backs up `~/.claude/settings.json` before adding hooks.
3. Preserves existing settings/hooks and avoids duplicate entries on reruns.

It respects `PI_CODING_AGENT_DIR` and `CLAUDE_CONFIG_DIR`.

**Run `/reload` in existing Pi sessions and restart existing Claude sessions.**
New sessions discover the bridges automatically. Keep this checkout in place:
both the Pi symlink and Claude hook commands reference its absolute path.

Add the Sessions widget from Noctalia's bar settings, or configure an instance:

```toml
[widget.ai-monitor]
type = "archie/ai-monitor:sessions"
```

Include `"ai-monitor"` in an existing bar's `start`, `center`, or `end` list.

Open the panel directly:

```sh
noctalia msg panel-open archie/ai-monitor:overview
# Open a specific tab:
noctalia msg panel-open archie/ai-monitor:overview sessions
```

## Updating

From your checkout:

```sh
git pull --ff-only
npm run install:integrations
```

Run `/reload` in existing Pi sessions and restart existing Claude sessions.
Luau files hot-reload. Manifest changes can require re-enabling the plugin.
During testing on Noctalia v5.2.1, disabling the plugin once caused Noctalia to
exit. Avoid unnecessary toggling while a plugin subprocess is active.

## Quota behavior and credentials

Quota polling is enabled by default and can be disabled in plugin settings.

- Codex: reads OAuth profiles named `openai-codex` or `openai-codex-*` from
  Pi's `auth.json`. API-key billing is not treated as subscription quota.
- Claude: reads `claudeAiOauth` from Claude Code's `.credentials.json`.
- Only allowlisted percentages, window names, reset dates, and safe status text
  reach Noctalia. Tokens and account IDs do not enter plugin state or logs.
- Requests go only to fixed HTTPS provider endpoints, without redirects.
- The plugin **never refreshes, rotates, or writes credentials**. Expired login
  tokens show unavailable until the agent refreshes them or you sign in again.
- Network failures, denied access, and unknown response shapes show unavailable,
  never a fake zero. A real reported zero is displayed as zero.
- These usage endpoints are undocumented and may change:
  `https://chatgpt.com/backend-api/wham/usage` and
  `https://api.anthropic.com/api/oauth/usage`.
- Quotas belong to accounts, not sessions. Pi's context percentage is a separate
  estimate. Claude context usage is not implemented. The panel displays reset
  countdowns and local weekday/time; helpers retain UTC timestamps internally.
- No credentials are sent to the other provider. No transcript parsing is used.

## Lifecycle data and limitations

Metadata is stored in `$XDG_STATE_HOME/noctalia-ai-monitor/sessions/`, defaulting
to `~/.local/state/noctalia-ai-monitor/sessions/`. New directories use mode
0700, files mode 0600, with atomic replacement.

Records contain session ID, process identity, working directory, model, status,
tool names, timestamps, and Pi context estimates. They never contain prompts,
tool arguments/results, assistant responses, or credentials.

The collector only joins records to same-user, live agent processes with a
matching Linux process start time. PID reuse and exited processes cannot
resurrect old sessions. Graceful session shutdown deletes records; crash
leftovers may remain on disk but are ignored.

- Pi heartbeat older than 40 seconds: `activity unconfirmed`.
- Claude active/waiting event older than 2 minutes: `activity unconfirmed`,
  because Claude hooks have no heartbeat.
- Claude interruptions and other Stop hooks that continue a turn can leave the
  last event ambiguous. Its status is best-effort hook telemetry, not a direct
  query of the agent. The last update is visible.
- Claude tool names reflect the latest hook, not a complete parallel-tool list.
- Subagent hooks do not overwrite the main Claude session.
- One live process is one row; historical sessions and terminal focus are not
  implemented.

## Diagnostics

```sh
npm run scan
npm run quotas
noctalia plugins lint ai-monitor

noctalia msg plugin archie/ai-monitor:collector all demo
noctalia msg plugin archie/ai-monitor:collector all live
noctalia msg plugin archie/ai-monitor:collector all refresh
noctalia msg plugin archie/ai-monitor:collector all quotas
noctalia msg plugin archie/ai-monitor:collector all inspect
```

`demo` and `live` are temporary service overrides; persistent demo mode is in
plugin settings. `inspect` logs the current session snapshot, never credentials.

`scan` and `inspect` include local session metadata such as working directories
and session names. Review their output before sharing it publicly. `quotas`
contacts the provider endpoints using your local login credentials.

## Structure

- `ai-monitor/`: installable Noctalia plugin and Node helper scripts.
- `integrations/pi/index.ts`: Pi lifecycle extension.
- `scripts/install-integrations.mjs`: user integration installer.
- `catalog.toml`: local source catalog.

## Uninstalling

Claude hook installation creates a timestamped
`settings.json.before-ai-monitor-*` backup alongside Claude's settings file.

To uninstall, remove the named widget from the bar, disable the plugin, and
remove its source. Remove the Pi extension symlink and only those Claude hook
entries whose command references this checkout's `claude-hook.mjs`. Reload Pi
and restart Claude. Do not restore an old settings backup over unrelated edits.

## License

MIT. See [LICENSE](../LICENSE). Third-party icon attribution is in
[THIRD_PARTY_NOTICES.md](../ai-monitor/THIRD_PARTY_NOTICES.md).

## References

- https://docs.noctalia.dev/noctalia/plugins/development/
- https://github.com/noctalia-dev/official-plugins/tree/main/example
- Pi's installed extension API and event declarations.
- https://code.claude.com/docs/en/hooks
