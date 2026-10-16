--!nonstrict
-- AI Monitor bar widget: shows per-account Codex/Claude subscription usage,
-- Pi and Claude Code activity badges, weekly-limit warnings, and completion cues.
-- Clicking opens the Usage or Sessions tab in the overview panel.

local model = require("./lib/model.luau")
local format = require("./lib/presentation.luau")
local bar = require("./lib/bar.luau")
local images = {}
local dataDir
local tracker = bar.newTracker()

local function openTab(tab)
  noctalia.runAsync({ "noctalia", "msg", "panel-open", "archie/ai-monitor:overview", tab })
end

local function meterImage(provider, used, light)
  -- Immutable filenames make the native image cache safe. At most 408 tiny SVGs
  -- across two providers, integer percentages/unknown, and light/dark themes.
  local key = string.lower(provider)
    .. "-"
    .. (light and "light" or "dark")
    .. "-"
    .. (used == nil and "unknown" or tostring(used))
  if images[key] then
    return images[key]
  end
  dataDir = dataDir or noctalia.pluginDataDir()
  if not dataDir then
    return nil
  end
  local path = dataDir .. "/usage-v1-" .. key .. ".svg"
  local svg = bar.ringSvg(provider, used, light)
  if noctalia.readFile(path) ~= svg and not noctalia.writeFile(path, svg) then
    return nil
  end
  images[key] = path
  return path
end

local function render()
  local snapshot = noctalia.state.get("snapshot") or model.empty()
  local demo = snapshot.source == "demo"
  local nowMs = noctalia.nowMs()
  local now = math.floor(nowMs / 1000)
  local quotas = demo and model.demoQuotas(now) or noctalia.state.get("quotas")
  local vertical = barWidget.isVertical()
  local container = vertical and ui.column or ui.row
  local light = bar.lightTheme(noctalia.getColor("on_surface"))
  local children, tooltip = {}, {}
  if demo then
    table.insert(children, ui.label({ text = "DEMO", fontSize = 9, color = "on_surface_variant" }))
    table.insert(tooltip, { key = "Source", value = "Simulated data" })
  end
  for _, account in ipairs((quotas or {}).accounts or {}) do
    local provider, subtitle, glyph = format.provider(account.provider)
    local window = bar.primaryWindow(account)
    local used = window and math.floor(window.usedPercent + 0.5) or nil
    local stale, staleReason = false, nil
    if not demo then
      stale, staleReason = bar.freshness(account, quotas, now)
    end
    local weekly = bar.weeklyWarning(account, now)
    local color = used and not stale and bar.color(provider, used, light) or "on_surface_variant"
    local caption = provider
    if provider == "Codex" and subtitle ~= "Default account" then
      caption = subtitle
    end
    if window and window.label ~= "5 hours" then
      caption = caption .. " 7d"
    end
    if stale then
      caption = caption .. " · stale"
    end
    local image = meterImage(provider, used, light)
    local labels = ui.column({ gap = 0, align = vertical and "center" or "start" }, {
      ui.label({
        text = used == nil and "?" or tostring(used) .. "%",
        fontSize = 11,
        fontWeight = "bold",
        color = color,
      }),
      ui.label({
        text = caption,
        fontSize = 8,
        color = "on_surface_variant",
        maxLines = vertical and 2 or 1,
        maxWidth = vertical and 32 or nil,
      }),
    })
    local meterChildren = {
      image and ui.image({
        path = image,
        width = 26,
        height = 26,
        fit = "contain",
        opacity = stale and 0.45 or 1,
      }) or ui.glyph({ name = glyph, size = 20, color = color }),
      labels,
    }
    if weekly and weekly ~= window then
      local warningColor = stale and "on_surface_variant"
        or bar.color(provider, weekly.usedPercent, light)
      table.insert(
        meterChildren,
        container({
          gap = 3,
          paddingH = 4,
          paddingV = 2,
          radius = 4,
          align = "center",
          fill = "surface_variant/0.35",
        }, {
          ui.glyph({ name = "alert-triangle", size = 10, color = warningColor }),
          ui.label({
            text = string.format("7d %.0f%%", weekly.usedPercent),
            fontSize = 9,
            color = warningColor,
            maxLines = vertical and 2 or 1,
            maxWidth = vertical and 32 or nil,
          }),
        })
      )
    end
    table.insert(
      children,
      container({
        key = account.provider,
        gap = vertical and 2 or 6,
        align = "center",
        onClick = function()
          openTab("usage")
        end,
      }, meterChildren)
    )
    local details = {}
    for _, item in ipairs(account.windows or {}) do
      table.insert(details, string.format("%s: %.0f%% used", item.label, item.usedPercent))
    end
    table.insert(tooltip, {
      key = provider .. " · " .. subtitle,
      value = account.status == "ok" and table.concat(details, ", ")
        or account.reason
        or "Usage unavailable",
    })
    if weekly then
      table.insert(tooltip, {
        key = provider .. " weekly warning",
        value = string.format(
          "%s: %.0f%% used%s",
          weekly.label,
          weekly.usedPercent,
          stale and " (stale reading)" or ""
        ),
      })
    end
    if stale then
      table.insert(tooltip, { key = provider .. " freshness", value = staleReason })
    end
  end
  if #((quotas or {}).accounts or {}) == 0 then
    table.insert(
      children,
      container({ gap = 5, align = "center" }, {
        ui.glyph({ name = "chart-donut", size = 16, color = "on_surface_variant" }),
        ui.label({
          text = vertical and "Usage ?" or quotas and "Usage unavailable" or "Loading usage",
          fontSize = 10,
          color = "on_surface_variant",
          maxLines = vertical and 2 or 1,
          maxWidth = vertical and 32 or nil,
        }),
      })
    )
    if quotas and quotas.note then
      table.insert(tooltip, { key = "Usage", value = quotas.note })
    end
  end
  local activity = bar.activity(snapshot.sessions, tracker, nowMs)
  for _, group in ipairs(activity) do
    local label = group.provider
      .. (vertical and "\n" or " ")
      .. group.label
      .. (group.count > 1 and " ×" .. tostring(group.count) or "")
    local color = group.color
    if light and color == "#91AEFF" then
      color = "#4062B0"
    elseif light and color == "#E7BA7B" then
      color = "#956211"
    elseif light and color == "#F28C98" then
      color = "#B6354B"
    elseif light and color == "#9AC7AA" then
      color = "#39754B"
    end
    table.insert(
      children,
      container({
        key = group.key,
        gap = vertical and 3 or 5,
        align = "center",
        paddingH = vertical and 0 or 4,
        paddingV = 3,
        opacity = group.label == "done"
            and math.max(0, math.min(1, (group.expiresAt - nowMs) / 2000))
          or 1,
        radius = 6,
        fill = (group.priority <= 4 or group.label == "done") and color .. "15"
          or "surface_variant/0.2",
        onClick = function()
          openTab("sessions")
        end,
      }, {
        ui.glyph({ name = group.glyph, size = group.label == "working" and 7 or 12, color = color }),
        ui.label({
          text = label,
          fontSize = vertical and 9 or 10,
          color = color,
          maxLines = vertical and 3 or 1,
          maxWidth = vertical and 32 or nil,
        }),
      })
    )
  end
  for _, session in ipairs(snapshot.sessions or {}) do
    table.insert(
      tooltip,
      { key = session.provider .. " · " .. session.project, value = session.status }
    )
  end
  if snapshot.error and snapshot.error ~= "" then
    table.insert(children, ui.glyph({ name = "alert-triangle", size = 14, color = "error" }))
    table.insert(tooltip, { key = "Session scan", value = snapshot.error })
  end
  table.insert(tooltip, {
    key = "Meters",
    value = "5h account usage; other windows in panel. Click a meter for usage, activity for sessions.",
  })
  barWidget.setTooltip(tooltip)
  barWidget.render(container({ gap = vertical and 10 or 4, align = "center" }, children))
end

bar.observe(tracker, noctalia.state.get("snapshot") or model.empty(), noctalia.nowMs())
noctalia.state.watch("snapshot", function()
  bar.observe(tracker, noctalia.state.get("snapshot") or model.empty(), noctalia.nowMs())
  render()
end)
noctalia.state.watch("quotas", function()
  render()
end)
noctalia.setUpdateInterval(1000)

function update()
  render()
end
function onClick()
  noctalia.togglePanel("archie/ai-monitor:overview")
end
render()
