--!nonstrict
-- Pure presentation helpers. Quota timestamps arrive normalized to UTC by Node.
local M = {}

function M.timestamp(value)
  if type(value) ~= "string" then return nil end
  local y, m, d, h, minute, second = string.match(value, "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")
  if not y or string.sub(value, -1) ~= "Z" then return nil end
  y, m, d, h, minute, second = tonumber(y), tonumber(m), tonumber(d), tonumber(h), tonumber(minute), tonumber(second)
  if m < 1 or m > 12 or d < 1 or d > 31 or h > 23 or minute > 59 or second > 59 then return nil end
  local offsets = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 }
  local leap = y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)
  local monthDays = { 31, leap and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  if y < 1 or d > monthDays[m] then return nil end
  local days = 365 * (y - 1970)
    + math.floor((y - 1) / 4) - math.floor(1969 / 4)
    - math.floor((y - 1) / 100) + math.floor(1969 / 100)
    + math.floor((y - 1) / 400) - math.floor(1969 / 400)
    + offsets[m] + d - 1 + ((leap and m > 2) and 1 or 0)
  return days * 86400 + h * 3600 + minute * 60 + second
end

function M.countdown(resetsAt, nowSeconds)
  local target = M.timestamp(resetsAt)
  if not target then return nil end
  local remaining = math.ceil((target - nowSeconds) / 60)
  if remaining <= 0 then return "Reset due" end
  if remaining >= 1440 then
    return string.format("%dd %dh", math.floor(remaining / 1440), math.floor((remaining % 1440) / 60))
  elseif remaining >= 60 then
    return string.format("%dh %02dm", math.floor(remaining / 60), remaining % 60)
  end
  return string.format("%dm", remaining)
end

function M.tokens(value)
  if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then return nil end
  if value >= 1000000 then return string.format("%.1fm", value / 1000000) end
  if value >= 1000 then return string.format("%.1fk", value / 1000) end
  return string.format("%.0f", value)
end

function M.provider(value)
  value = value or ""
  if string.sub(value, 1, 5) == "Codex" then
    local profile = string.match(value, "%((.-)%)")
    local account = profile and string.match(profile, "^openai%-codex%-(.+)$") or nil
    if account then account = string.upper(string.sub(account, 1, 1)) .. string.sub(account, 2) end
    return "Codex", account or "Default account", "brand-openai", "#91AEFF"
  end
  return "Claude", "Subscription", "asterisk", "#C3A2F0"
end

function M.windowTitle(value)
  if value == "5 hours" then return "Session", "5h window" end
  if value == "Weekly" then return "Weekly", "7d window" end
  return value or "Usage", ""
end

function M.status(value)
  if value == "waiting for permission" then return "Approval", "#E7BA7B" end
  if value == "waiting for input" then return "Needs input", "#E7BA7B" end
  if value == "using tools" then return "Using tools", "#91AEFF" end
  if value == "working" then return "Working", "#91AEFF" end
  if value == "error" then return "Error", "#F28C98" end
  if value == "idle" then return "Idle", "#9AC7AA" end
  if value == "activity unconfirmed" then return "Unconfirmed", "on_surface_variant" end
  return "Running", "on_surface_variant"
end

return M
