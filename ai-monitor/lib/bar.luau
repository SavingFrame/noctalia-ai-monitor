--!nonstrict
local M = {}
local format = require("./presentation.luau")

M.staleAfterSeconds = 600
M.doneDurationMs = 10000

local function validPercent(value)
  return type(value) == "number" and value == value and value >= 0 and value <= 100
end

local function sessionKey(session)
  if not session.id then return nil end
  return session.id .. ":" .. tostring(session.sessionId or "")
end

local function isWorking(status)
  return status == "working" or status == "using tools"
end

function M.newTracker()
  return { previous = {}, done = {}, source = nil }
end

-- Call on scanner snapshots, not on render ticks or quota updates. Missing
-- sessions, permission/input waits, errors and session switches are not success.
function M.observe(tracker, snapshot, nowMs)
  if tracker.source ~= snapshot.source or (snapshot.error and snapshot.error ~= "") then
    tracker.previous, tracker.done = {}, {}
  end
  tracker.source = snapshot.source
  local previous, done = {}, {}
  if not snapshot.error or snapshot.error == "" then
    for _, session in ipairs(snapshot.sessions or {}) do
      local key = sessionKey(session)
      if key then
        previous[key] = session.status
        if session.status == "idle" then
          if isWorking(tracker.previous[key]) then
            done[key] = nowMs + M.doneDurationMs
          elseif tracker.done[key] and tracker.done[key] > nowMs then
            done[key] = tracker.done[key]
          end
        end
      end
    end
  end
  tracker.previous, tracker.done = previous, done
end

function M.freshness(account, quotas, nowSeconds)
  if account.status ~= "ok" then return false, nil end
  local timestamp = format.timestamp(account.checkedAt or (quotas or {}).updatedAt)
  if not timestamp or timestamp > nowSeconds + 60 then return true, "Check time unavailable or invalid" end
  local age = math.max(0, nowSeconds - timestamp)
  if account.staleReason then
    return true, string.format("%s. Last updated %dm ago", account.staleReason, math.floor(age / 60))
  end
  if age >= M.staleAfterSeconds then return true, string.format("Last checked %dm ago", math.floor(age / 60)) end
  for _, window in ipairs(account.windows or {}) do
    local reset = format.timestamp(window.resetsAt)
    if reset and reset <= nowSeconds and validPercent(window.usedPercent) and window.usedPercent > 0 then
      return true, "A quota window reset; awaiting a fresh reading"
    end
  end
  return false, nil
end

function M.weeklyWarning(account, nowSeconds)
  if account.status ~= "ok" then return nil end
  local highest
  for _, window in ipairs(account.windows or {}) do
    local reset = format.timestamp(window.resetsAt)
    if string.match(window.label or "", "^Weekly") and validPercent(window.usedPercent)
        and window.usedPercent >= 90 and (not reset or reset > nowSeconds)
        and (not highest or window.usedPercent > highest.usedPercent) then
      highest = window
    end
  end
  return highest
end

-- Group real lifecycle states, never infer activity from process presence.
local states = {
  ["waiting for permission"] = { "approval", "hand-stop", "#E7BA7B", 1 },
  ["waiting for input"] = { "needs input", "message-circle", "#E7BA7B", 2 },
  error = { "error", "alert-circle", "#F28C98", 3 },
  working = { "working", "circle-filled", "#91AEFF", 4 },
  ["using tools"] = { "working", "circle-filled", "#91AEFF", 4 },
  done = { "done", "check", "#9AC7AA", 5 },
  idle = { "idle", "circle", "on_surface_variant", 6 },
  ["activity unconfirmed"] = { "unconfirmed", "circle-dashed", "on_surface_variant", 7 },
  running = { "running", "circle-dashed", "on_surface_variant", 8 },
}

function M.activity(sessions, tracker, nowMs)
  local groups, busy = {}, false
  for _, session in ipairs(sessions or {}) do
    local state = states[session.status] or states.running
    local identity = sessionKey(session)
    if session.status == "idle" and tracker and identity and tracker.done[identity] and tracker.done[identity] > nowMs then
      state = states.done
    end
    local provider = session.provider or "Agent"
    local key = provider .. ":" .. state[1]
    if not groups[key] then
      groups[key] = { key = key, provider = provider, label = state[1], glyph = state[2], color = state[3], priority = state[4], count = 0 }
    end
    groups[key].count = groups[key].count + 1
    if state[1] == "done" then groups[key].expiresAt = math.max(groups[key].expiresAt or 0, tracker.done[identity]) end
    if state[4] <= 5 then busy = true end
  end
  local result = {}
  for _, group in pairs(groups) do
    -- Busy/attention/completion badges suppress idle across all providers.
    -- Unknown activity remains visible rather than being guessed idle.
    if group.label ~= "idle" or not busy then table.insert(result, group) end
  end
  table.sort(result, function(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.provider < b.provider
  end)
  return result
end

function M.primaryWindow(account)
  if account.status ~= "ok" then return nil end
  local first
  for _, window in ipairs(account.windows or {}) do
    if validPercent(window.usedPercent) then
      first = first or window
      if window.label == "5 hours" then return window end
    end
  end
  return first
end

function M.lightTheme(foreground)
  local r, g, b = string.match(foreground or "", "^#(%x%x)(%x%x)(%x%x)")
  return r ~= nil and (tonumber(r, 16) * 0.2126 + tonumber(g, 16) * 0.7152 + tonumber(b, 16) * 0.0722) < 128
end

function M.color(provider, used, light)
  if used and used >= 90 then return light and "#B6354B" or "#F28C98" end
  if used and used >= 75 then return light and "#956211" or "#E7BA7B" end
  if provider == "Codex" then return light and "#4062B0" or "#91AEFF" end
  return light and "#7952A1" or "#C3A2F0"
end

-- OpenAI icon paths from Tabler Icons (MIT). See THIRD_PARTY_NOTICES.md.
local openai = [[
<path d="M11.217 19.384a3.501 3.501 0 0 0 6.783 -1.217v-5.167l-6 -3.35"/>
<path d="M5.214 15.014a3.501 3.501 0 0 0 4.446 5.266l4.34 -2.534v-6.946"/>
<path d="M6 7.63c-1.391 -.236 -2.787 .395 -3.534 1.689a3.474 3.474 0 0 0 1.271 4.745l4.263 2.514l6 -3.348"/>
<path d="M12.783 4.616a3.501 3.501 0 0 0 -6.783 1.217v5.067l6 3.45"/>
<path d="M18.786 8.986a3.501 3.501 0 0 0 -4.446 -5.266l-4.34 2.534v6.946"/>
<path d="M18 16.302c1.391 .236 2.787 -.395 3.534 -1.689a3.474 3.474 0 0 0 -1.271 -4.745l-4.308 -2.514l-5.955 3.42"/>
]]

function M.ringSvg(provider, used, light)
  local color = M.color(provider, used, light)
  local foreground = light and "#333333" or "#DDDDDD"
  local parts = {
    '<svg xmlns="http://www.w3.org/2000/svg" width="36" height="36" viewBox="0 0 36 36">',
    '<circle cx="18" cy="18" r="15" fill="none" stroke="#888888" stroke-opacity="0.3" stroke-width="3"'
      .. (used == nil and ' stroke-dasharray="3 3"' or '') .. '/>',
  }
  -- No round-cap dot at zero and no seam at 100%.
  if used and used > 0 then
    local circumference = 2 * math.pi * 15
    table.insert(parts, string.format('<circle cx="18" cy="18" r="15" fill="none" stroke="%s" stroke-width="3" stroke-linecap="round" stroke-dasharray="%.4f %.4f" transform="rotate(-90 18 18)"/>', color, circumference * used / 100, circumference))
  end
  table.insert(parts, '<g transform="translate(8 8) scale(0.833333)" fill="none" stroke="' .. foreground .. '" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">')
  if provider == "Codex" then
    table.insert(parts, openai)
  else
    for i = 0, 11 do
      local angle = i * math.pi / 6
      table.insert(parts, string.format('<path d="M%.3f %.3fL%.3f %.3f"/>',
        12 + math.cos(angle) * 2, 12 + math.sin(angle) * 2, 12 + math.cos(angle) * 8, 12 + math.sin(angle) * 8))
    end
  end
  table.insert(parts, '</g></svg>')
  return table.concat(parts)
end

return M
