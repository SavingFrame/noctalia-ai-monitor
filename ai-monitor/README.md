# AI Monitor

Noctalia v5 bar widget and panel for Pi and Claude Code session activity,
Pi context estimates, and Codex/Claude subscription quotas.

The bar shows circular 5-hour usage meters per account, plus short lifecycle
badges for active agents. Weekly-only fallback meters are labeled `7d`.
Local session records are polled every second by default, independently of
network quotas. With no agents, only the usage meters remain.
Click a meter for Usage or an activity badge for Sessions; hover for details.
Weekly usage at 90% gets a warning. Idle badges hide while any agent is active.
Observed working-to-idle transitions show `done` for 10 seconds, with a short
fade. Quotas older than 10 minutes or with unknown freshness are labeled `stale`
and dimmed; the panel and copied summaries also flag stale readings.

Requires Linux, Node.js 22+, and Noctalia v5 with plugin API 24+. Install the Pi extension and Claude hooks
from the repository to enable lifecycle status. Unconnected processes still
appear as `running`.

```sh
noctalia msg panel-open archie/ai-monitor:overview
```

Quota polling uses local OAuth tokens with fixed provider usage endpoints every
5 minutes. It can be disabled in plugin settings. Tokens are never refreshed,
saved, or passed to the UI. Unsupported/expired logins show unavailable.

See the repository README for installation, updates, privacy, and limitations.

MIT licensed. See the repository LICENSE and THIRD_PARTY_NOTICES.md.
