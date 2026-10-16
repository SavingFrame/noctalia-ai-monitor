--!nonstrict
-- AI Monitor background collector: polls local Pi/Claude Code session metadata
-- and provider subscription quotas through Node.js helpers, then publishes UI state.
-- Supports demo mode and retains stale quota readings when refreshes fail.

local model = require("./lib/model.luau")
local demo = noctalia.getConfig("demo")
local pending = false
local quotaPending = false
local nextQuotaAt = 0
local generation = 0

local function publishQuotas(quotas, failure)
  local previous = noctalia.state.get("quotas") or {}
  local cached = {}
  for _, account in ipairs(previous.accounts or {}) do cached[account.provider] = account end
  local accounts = {}
  for _, account in ipairs(quotas and quotas.accounts or previous.accounts or {}) do
    local old = cached[account.provider]
    if (failure or account.status ~= "ok") and old and old.status == "ok" and #(old.windows or {}) > 0 then
      local retained = {}
      for key, value in pairs(old) do retained[key] = value end
      retained.checkedAt = old.checkedAt or previous.updatedAt
      retained.staleReason = failure or account.reason or "Usage refresh failed"
      table.insert(accounts, retained)
    else
      table.insert(accounts, account)
    end
  end
  noctalia.state.set("quotas", {
    accounts = accounts,
    updatedAt = quotas and quotas.updatedAt or previous.updatedAt,
    note = failure or (quotas and quotas.note),
  })
end

local function refreshQuotas()
  if demo then return end
  if not noctalia.getConfig("fetch_quotas") then
    noctalia.state.set("quotas", { accounts = {}, note = "Quota polling disabled" })
    return
  end
  if quotaPending or noctalia.nowMs() < nextQuotaAt then return end
  quotaPending = true
  nextQuotaAt = noctalia.nowMs() + 300000
  local requestGeneration = generation
  local accepted = noctalia.runAsync({ "node", noctalia.pluginDir() .. "/scripts/quotas.mjs" }, function(result)
    quotaPending = false
    if requestGeneration ~= generation then return end
    local quotas = noctalia.json.decode(result.stdout)
    if result.exitCode ~= 0 or result.stdoutTruncated or type(quotas) ~= "table" or type(quotas.accounts) ~= "table" then
      publishQuotas(nil, "Quota helper failed. Check Node.js.")
      return
    end
    publishQuotas(quotas)
  end)
  if not accepted then
    quotaPending = false
    publishQuotas(nil, "Could not start quota helper")
  end
end

local function refresh()
  if demo then
    noctalia.state.set("snapshot", model.demo())
    return
  end
  refreshQuotas()
  if pending then return end
  pending = true
  local requestGeneration = generation
  local accepted = noctalia.runAsync({ "node", noctalia.pluginDir() .. "/scripts/sessions.mjs" }, function(result)
    pending = false
    if requestGeneration ~= generation then return end
    local snapshot, err = noctalia.json.decode(result.stdout)
    if result.exitCode ~= 0 or result.stdoutTruncated or type(snapshot) ~= "table" or type(snapshot.sessions) ~= "table" then
      snapshot = model.empty()
      snapshot.error = "Session scan failed. Check Node.js and plugin logs."
      noctalia.log(result.stderr .. " " .. tostring(err or ""))
    end
    noctalia.state.set("snapshot", snapshot)
  end)
  if not accepted then
    pending = false
    local snapshot = model.empty()
    snapshot.error = "Could not start Node.js session scanner."
    noctalia.state.set("snapshot", snapshot)
  end
end

function update() refresh() end

function onConfigChanged()
  generation = generation + 1
  nextQuotaAt = 0
  demo = noctalia.getConfig("demo")
  noctalia.setUpdateInterval(noctalia.getConfig("refresh_seconds") * 1000)
  refresh()
end

function onIpc(event)
  if event == "demo" or event == "live" then
    generation = generation + 1
    nextQuotaAt = 0
    demo = event == "demo"
    refresh()
  elseif event == "refresh" then
    refresh()
  elseif event == "quotas" then
    nextQuotaAt = 0
    refreshQuotas()
  elseif event == "inspect" then
    noctalia.log(noctalia.json.encode(noctalia.state.get("snapshot") or model.empty()))
  end
end

noctalia.setUpdateInterval(noctalia.getConfig("refresh_seconds") * 1000)
refresh()
