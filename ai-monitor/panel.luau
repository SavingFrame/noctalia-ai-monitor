--!nonstrict
-- AI Monitor overview panel: displays account quota windows and reset times,
-- live Pi/Claude Code sessions, and available context estimates.
-- Provides usage refresh and quota-summary copying.

local model = require("./lib/model.luau")
local format = require("./lib/presentation.luau")
local usage = require("./lib/bar.luau")
local opened = false
local expanded = {}
local view = "usage"
local lastRefresh = 0
local refreshing = false
local render

local function text(value, options)
  local props = { text = value, fontSize = 12, color = "on_surface_variant", maxLines = 1 }
  for key, value in pairs(options or {}) do
    props[key] = value
  end
  return ui.label(props)
end

local function badge(value, color)
  return ui.row({
    paddingH = 7,
    paddingV = 3,
    radius = 5,
    fill = color and string.sub(color, 1, 1) == "#" and color .. "18" or "surface_variant/0.65",
    align = "center",
  }, {
    text(value, { color = color or "on_surface_variant", fontWeight = "medium", fontSize = 11 }),
  })
end

local function iconTile(glyph, accent)
  return ui.row({
    width = 27,
    height = 27,
    radius = 7,
    fill = accent .. "18",
    align = "center",
    justify = "center",
  }, {
    ui.glyph({ name = glyph, size = 16, color = accent }),
  })
end

local function quotaWindow(window, accent, now, stale)
  local title, period = format.windowTitle(window.label)
  local used = math.clamp(window.usedPercent, 0, 100)
  local color = stale and "on_surface_variant"
    or used >= 90 and "#F28C98"
    or used >= 75 and "#E7BA7B"
    or accent
  local titleRow = {
    text(title, { fontSize = 12, color = "on_surface", fontWeight = "medium", flexGrow = 1 }),
    text(period, { fontSize = 10 }),
    badge(string.format("%.0f%%", used), color),
  }
  local countdown = format.countdown(window.resetsAt, now)
  local resetLabel = "Reset time unavailable"
  if countdown then
    resetLabel = countdown
      .. "  ("
      .. noctalia.formatTime("{:%a %H:%M}", format.timestamp(window.resetsAt))
      .. ")"
  end
  return ui.column({ gap = 5, align = "stretch" }, {
    ui.row({ gap = 8, align = "center" }, titleRow),
    ui.progress({
      progress = used / 100,
      height = 4,
      radius = 2,
      fill = color,
      track = accent .. "1C",
    }),
    ui.row({ align = "center" }, {
      ui.row({
        gap = 4,
        paddingH = 5,
        paddingV = 2,
        radius = 4,
        fill = "surface_variant/0.4",
        align = "center",
      }, {
        ui.glyph({ name = "clock", size = 11, color = "on_surface_variant" }),
        text(resetLabel, { fontSize = 10 }),
      }),
      ui.spacer({ flexGrow = 1 }),
    }),
  })
end

local function quotaCard(account, now, quotas, demo)
  local title, subtitle, glyph, accent = format.provider(account.provider)
  local stale, reason = false, nil
  if not demo then
    stale, reason = usage.freshness(account, quotas, now)
  end
  local children = {
    ui.row({ gap = 8, align = "center" }, {
      iconTile(glyph, accent),
      text(title, { color = "on_surface", fontSize = 13, fontWeight = "bold" }),
      text(subtitle, { fontSize = 11, flexGrow = 1 }),
      account.status ~= "ok" and badge("Unavailable")
        or stale and badge("Stale", "#E7BA7B")
        or text(""),
    }),
  }
  if account.status == "ok" then
    if stale then
      table.insert(children, text(reason, { fontSize = 10, maxLines = 2 }))
    end
    for _, window in ipairs(account.windows or {}) do
      table.insert(children, quotaWindow(window, accent, now, stale))
    end
  else
    table.insert(
      children,
      text(account.reason or "Usage unavailable", { maxLines = 3, fontSize = 11 })
    )
  end
  return ui.column({
    key = "quota-" .. account.provider,
    padding = 13,
    gap = 12,
    radius = 12,
    fill = accent .. "0E",
    border = accent .. "1A",
    borderWidth = 1,
    align = "stretch",
  }, children)
end

local function sessionCard(session, demo)
  local status, statusColor = format.status(session.status)
  local isExpanded = expanded[session.id] == true
  local accent = session.provider == "Pi" and "#91AEFF" or "#C3A2F0"
  local rows = {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({
        name = session.provider == "Pi" and "terminal-2" or "asterisk",
        size = 14,
        color = accent,
      }),
      text(session.name ~= nil and session.name ~= "" and session.name or session.project, {
        fontSize = 12,
        fontWeight = "medium",
        color = "on_surface",
        flexGrow = 1,
      }),
      badge(status, statusColor),
      ui.glyph({
        name = isExpanded and "chevron-up" or "chevron-down",
        size = 13,
        color = "on_surface_variant",
      }),
    }),
  }
  local modelName = session.model and session.model ~= "" and session.model or "Model unavailable"
  table.insert(rows, text(session.provider .. " · " .. modelName, { fontSize = 10 }))
  if session.name and session.name ~= "" and session.name ~= session.project then
    table.insert(rows, text("Project · " .. session.project, { fontSize = 10 }))
  end
  if session.tools and #session.tools > 0 then
    table.insert(
      rows,
      text("Tools · " .. table.concat(session.tools, ", "), { fontSize = 10, maxLines = 2 })
    )
  end
  if session.context then
    local tokens = format.tokens(session.context.tokens)
    local window = format.tokens(session.context.window)
    table.insert(
      rows,
      ui.row({ gap = 8, align = "center" }, {
        text(string.format("Context %.0f%%", session.context.percent), { fontSize = 10 }),
        ui.progress({
          progress = math.clamp(session.context.percent / 100, 0, 1),
          height = 3,
          flexGrow = 1,
          radius = 2,
          fill = accent,
          track = "outline/0.18",
        }),
        tokens
            and text(tokens .. (window and " / " .. window or "") .. " tokens", { fontSize = 10 })
          or text(""),
      })
    )
  else
    table.insert(
      rows,
      text(
        session.provider == "Claude" and "Context · not supported for Claude"
          or "Context · unavailable",
        { fontSize = 10 }
      )
    )
  end
  if not session.bridge and not demo then
    table.insert(
      rows,
      text(
        session.provider == "Pi" and "Activity not connected · run /reload in this Pi session"
          or "Activity not connected · restart Claude Code",
        { fontSize = 10, color = "#E7BA7B", maxLines = 2 }
      )
    )
  elseif session.lastEventAt then
    local timestamp = format.timestamp(session.lastEventAt)
    if timestamp then
      local age = math.max(0, math.floor(noctalia.nowMs() / 1000) - timestamp)
      local ageText = age < 60 and "just now"
        or age < 3600 and tostring(math.floor(age / 60)) .. "m ago"
        or age < 86400 and tostring(math.floor(age / 3600)) .. "h ago"
        or tostring(math.floor(age / 86400)) .. "d ago"
      table.insert(rows, text("Updated " .. ageText, { fontSize = 10 }))
    end
  end
  if isExpanded then
    table.insert(rows, ui.separator({ color = "outline/0.15", spacing = 2 }))
    table.insert(rows, text(session.cwd, { fontSize = 10, maxLines = 2 }))
    local identity = "PID " .. tostring(session.pid)
    if session.sessionId then
      identity = identity .. " · " .. string.sub(session.sessionId, 1, 8)
    end
    table.insert(rows, text(identity, { fontSize = 10 }))
    if session.modelProvider and session.modelProvider ~= "" then
      table.insert(rows, text("Model provider · " .. session.modelProvider, { fontSize = 10 }))
    end
    if session.bridge then
      table.insert(rows, text("Connection · " .. session.bridge, { fontSize = 10 }))
    end
    if session.lastEventAt then
      local timestamp = format.timestamp(session.lastEventAt)
      if timestamp then
        table.insert(
          rows,
          text(
            "Last update · " .. noctalia.formatTime("{:%a %H:%M:%S}", timestamp),
            { fontSize = 10 }
          )
        )
      end
    end
  end
  return ui.column({
    key = session.id,
    gap = 5,
    paddingH = 12,
    paddingV = 10,
    radius = 10,
    fill = "surface_variant/0.2",
    align = "stretch",
    onClick = function()
      expanded[session.id] = not isExpanded
      render()
    end,
  }, rows)
end

render = function()
  if not opened then
    return
  end
  local snapshot = noctalia.state.get("snapshot") or model.empty()
  local now = math.floor(noctalia.nowMs() / 1000)
  if refreshing and now - lastRefresh >= 15 then
    refreshing = false
  end
  local demo = snapshot.source == "demo"
  local quotas = demo and model.demoQuotas(now) or noctalia.state.get("quotas")
  local rows = {}
  if snapshot.error ~= "" then
    table.insert(rows, text(snapshot.error, { color = "error", maxLines = 3 }))
  end
  if view == "usage" then
    if quotas then
      if quotas.note then
        table.insert(rows, text(quotas.note, { maxLines = 2 }))
      end
      for _, account in ipairs(quotas.accounts or {}) do
        table.insert(rows, quotaCard(account, now, quotas, demo))
      end
    else
      table.insert(
        rows,
        ui.column({ padding = 16, radius = 12, fill = "surface_variant/0.28" }, {
          text("Loading subscription usage…", { fontSize = 12 }),
        })
      )
    end
  else
    table.insert(
      rows,
      ui.row({ paddingH = 2, gap = 8, align = "center" }, {
        text("SESSIONS", { fontSize = 10, fontWeight = "bold", flexGrow = 1 }),
        text(
          tostring(#snapshot.sessions) .. (#snapshot.sessions == 1 and " process" or " processes"),
          { fontSize = 10 }
        ),
      })
    )
    if #snapshot.sessions == 0 then
      table.insert(rows, text("No active sessions", { fontSize = 11 }))
    else
      for _, session in ipairs(snapshot.sessions) do
        table.insert(rows, sessionCard(session, demo))
      end
    end
  end
  local updated =
    format.timestamp(view == "sessions" and snapshot.updatedAt or quotas and quotas.updatedAt)
  local updatedText = view == "usage" and refreshing and "Refreshing…"
    or updated and (view == "sessions" and "Activity synced " or "Updated ") .. noctalia.formatTime(
      "{:%H:%M}",
      updated
    )
    or view == "sessions" and "Session activity"
    or "Subscription usage"
  panel.render(ui.column({ gap = 12, flexGrow = 1, align = "stretch" }, {
    ui.row({ gap = 6, align = "center" }, {
      ui.column({ gap = 3, flexGrow = 1, align = "start" }, {
        text("AI Monitor", { fontSize = 16, color = "on_surface", fontWeight = "bold" }),
        ui.row({ gap = 5, align = "center" }, {
          ui.glyph({ name = "clock", size = 11, color = "on_surface_variant" }),
          text(demo and "Demo data" or updatedText, { fontSize = 10 }),
        }),
      }),
      ui.button({
        glyph = "copy",
        glyphSize = 15,
        variant = "ghost",
        controlSize = "sm",
        tooltip = "Copy usage summary",
        onClick = "onCopySummary",
      }),
      ui.button({
        glyph = "refresh",
        glyphSize = 15,
        variant = "ghost",
        controlSize = "sm",
        tooltip = "Refresh usage",
        enabled = not demo and not refreshing and now - lastRefresh >= 30,
        onClick = "onRefresh",
      }),
      ui.button({
        glyph = "x",
        glyphSize = 16,
        variant = "ghost",
        controlSize = "sm",
        tooltip = "Close",
        onClick = "onCloseClicked",
      }),
    }),
    ui.row({ gap = 6, align = "center" }, {
      ui.button({
        text = "Usage",
        fontSize = 11,
        controlSize = "sm",
        variant = view == "usage" and "secondary" or "ghost",
        onClick = function()
          view = "usage"
          render()
        end,
      }),
      ui.button({
        text = "Sessions  " .. tostring(#snapshot.sessions),
        fontSize = 11,
        controlSize = "sm",
        variant = view == "sessions" and "secondary" or "ghost",
        onClick = function()
          view = "sessions"
          render()
        end,
      }),
      ui.spacer({ flexGrow = 1 }),
    }),
    ui.scroll({ key = "body-" .. view, flexGrow = 1, gap = 10, align = "stretch" }, rows),
    text(
      demo and "SIMULATED DATA"
        or view == "usage" and "Account usage · reset times are local"
        or "Click a session for details · context usage is estimated",
      { fontSize = 9 }
    ),
  }))
end

noctalia.state.watch("snapshot", function()
  render()
end)
noctalia.state.watch("quotas", function()
  refreshing = false
  render()
end)

function onOpen(context)
  if context == "usage" or context == "sessions" then
    view = context
  end
  opened = true
  panel.setWantsSecondTicks(true)
  render()
end
function onClose()
  opened = false
end
function update()
  render()
end
function onCloseClicked()
  panel.close()
end

function onRefresh()
  local now = math.floor(noctalia.nowMs() / 1000)
  if refreshing or now - lastRefresh < 30 then
    return
  end
  lastRefresh = now
  refreshing = true
  local accepted = noctalia.runAsync(
    { "noctalia", "msg", "plugin", "archie/ai-monitor:collector", "all", "quotas" },
    function(result)
      if result.exitCode ~= 0 then
        refreshing = false
        render()
      end
    end
  )
  if not accepted then
    refreshing = false
  end
  render()
end

function onCopySummary()
  local snapshot = noctalia.state.get("snapshot") or model.empty()
  local quotas = snapshot.source == "demo" and model.demoQuotas(math.floor(noctalia.nowMs() / 1000))
    or noctalia.state.get("quotas")
  local lines = { snapshot.source == "demo" and "AI Monitor (demo)" or "AI Monitor" }
  for _, account in ipairs((quotas or {}).accounts or {}) do
    local title, subtitle = format.provider(account.provider)
    local stale, reason = false, nil
    if snapshot.source ~= "demo" then
      stale, reason = usage.freshness(account, quotas, math.floor(noctalia.nowMs() / 1000))
    end
    table.insert(lines, title .. " · " .. subtitle .. (stale and " (stale)" or ""))
    if stale then
      table.insert(lines, "  " .. reason)
    end
    for _, window in ipairs(account.windows or {}) do
      table.insert(lines, string.format("  %s: %.0f%% used", window.label, window.usedPercent))
    end
    if account.reason then
      table.insert(lines, "  " .. account.reason)
    end
  end
  noctalia.copyToClipboard(table.concat(lines, "\n"), "text/plain")
end
