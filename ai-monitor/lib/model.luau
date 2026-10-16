--!nonstrict
local M = {}

function M.empty()
  return { sessions = {}, source = "live", updatedAt = "", error = "", limits = "Not connected" }
end

function M.demo()
  return {
    source = "demo",
    updatedAt = "Simulated data",
    error = "",
    limits = "Simulated subscription usage",
    sessions = {
      {
        id = "demo-pi",
        provider = "Pi",
        project = "noctalia-ai-monitor",
        cwd = "~/Projects/noctalia-ai-monitor",
        status = "working",
        pid = 1001,
      },
      {
        id = "demo-claude",
        provider = "Claude",
        project = "website",
        cwd = "~/Projects/website",
        status = "waiting for input",
        pid = 1002,
      },
    },
  }
end

function M.demoQuotas(now)
  local function reset(seconds)
    return noctalia.formatTime("{:%Y-%m-%dT%H:%M:%SZ}", now + seconds, "UTC")
  end
  return {
    accounts = {
      {
        provider = "Codex (openai-codex)",
        status = "ok",
        windows = {
          { label = "5 hours", usedPercent = 45, resetsAt = reset(13200) },
          { label = "Weekly", usedPercent = 28, resetsAt = reset(180000) },
        },
      },
      {
        provider = "Claude subscription",
        status = "ok",
        windows = {
          { label = "5 hours", usedPercent = 72, resetsAt = reset(4800) },
          { label = "Weekly", usedPercent = 36, resetsAt = reset(370000) },
        },
      },
    },
  }
end

function M.counts(snapshot)
  local pi, claude = 0, 0
  for _, session in ipairs(snapshot.sessions or {}) do
    if session.provider == "Pi" then
      pi = pi + 1
    else
      claude = claude + 1
    end
  end
  return pi, claude
end

return M
