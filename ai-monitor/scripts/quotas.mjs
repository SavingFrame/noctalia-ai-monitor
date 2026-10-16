import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

function percent(value) {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 100
    ? value
    : null;
}
function reset(value) {
  const ms =
    typeof value === "number" ? value * 1000 : typeof value === "string" ? Date.parse(value) : NaN;
  return Number.isFinite(ms) ? new Date(ms).toISOString() : "";
}
export function codexWindows(body) {
  const windows = [];
  for (const [key, fallback] of [
    ["primary_window", "Primary"],
    ["secondary_window", "Secondary"],
  ]) {
    const window = body?.rate_limit?.[key];
    const used = percent(window?.used_percent);
    if (used === null) continue;
    const seconds = window.limit_window_seconds;
    const label = seconds === 18000 ? "5 hours" : seconds === 604800 ? "Weekly" : fallback;
    windows.push({ label, usedPercent: used, resetsAt: reset(window.reset_at) });
  }
  return windows;
}
export function claudeWindows(body) {
  const windows = [];
  for (const [key, label] of [
    ["five_hour", "5 hours"],
    ["seven_day", "Weekly"],
    ["seven_day_sonnet", "Weekly Sonnet"],
    ["seven_day_opus", "Weekly Opus"],
  ]) {
    const window = body?.[key];
    const used = percent(window?.utilization);
    if (used !== null)
      windows.push({ label, usedPercent: used, resetsAt: reset(window.resets_at) });
  }
  return windows;
}

async function readJSON(path) {
  try {
    const raw = await readFile(path, "utf8");
    if (raw.length > 1024 * 1024) return null;
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export async function requestQuota(
  { provider, credential, url, headers, parse },
  fetcher = fetch,
  now = Date.now(),
) {
  const base = { provider, windows: [], checkedAt: new Date(now).toISOString() };
  if (!credential?.token)
    return { ...base, status: "unavailable", reason: "No local subscription login found" };
  if (Number.isFinite(credential.expires) && credential.expires <= now) {
    return {
      ...base,
      status: "unavailable",
      reason: "Login token expired. Sign in or use the agent to refresh it.",
    };
  }
  try {
    const response = await fetcher(url, {
      headers: {
        Accept: "application/json",
        Authorization: "Bearer " + credential.token,
        ...headers,
      },
      signal: AbortSignal.timeout(8000),
      redirect: "error",
    });
    // Never log response bodies, headers, or credentials.
    if (!response.ok) {
      const reason =
        response.status === 401
          ? "Login rejected. Sign in again."
          : response.status === 403
            ? "Usage access denied for this login."
            : response.status === 429
              ? "Usage endpoint rate limited. Will retry later."
              : "Usage endpoint returned HTTP " + response.status;
      return { ...base, status: "unavailable", reason };
    }
    const windows = parse(await response.json());
    return windows.length
      ? { ...base, status: "ok", windows }
      : {
          ...base,
          status: "unavailable",
          reason: "Usage response has no recognized limit windows",
        };
  } catch {
    return { ...base, status: "unavailable", reason: "Usage request failed or timed out" };
  }
}

export async function collectQuotas({
  home = homedir(),
  agentDir = process.env.PI_CODING_AGENT_DIR || join(home, ".pi/agent"),
  claudeDir = process.env.CLAUDE_CONFIG_DIR || join(home, ".claude"),
  fetcher = fetch,
} = {}) {
  const auth = await readJSON(join(agentDir, "auth.json"));
  const claude = (await readJSON(join(claudeDir, ".credentials.json")))?.claudeAiOauth;
  const tasks = [];
  const seen = new Set();
  for (const [key, value] of Object.entries(auth || {})) {
    if (
      !/^openai-codex(?:-|$)/.test(key) ||
      value?.type !== "oauth" ||
      typeof value.access !== "string"
    )
      continue;
    // Aliases for the same account share a quota. Account IDs never enter output.
    const account = value.accountId || value.access;
    if (seen.has(account)) continue;
    seen.add(account);
    tasks.push(
      requestQuota(
        {
          provider: "Codex (" + key + ")",
          credential: { token: value.access, expires: value.expires },
          url: "https://chatgpt.com/backend-api/wham/usage",
          headers: value.accountId ? { "ChatGPT-Account-Id": value.accountId } : {},
          parse: codexWindows,
        },
        fetcher,
      ),
    );
  }
  if (!tasks.length)
    tasks.push(
      Promise.resolve({
        provider: "Codex",
        status: "unavailable",
        windows: [],
        reason: "No Pi Codex OAuth login found",
      }),
    );
  tasks.push(
    requestQuota(
      {
        provider: "Claude subscription",
        credential: { token: claude?.accessToken, expires: claude?.expiresAt },
        url: "https://api.anthropic.com/api/oauth/usage",
        headers: { "anthropic-beta": "oauth-2025-04-20" },
        parse: claudeWindows,
      },
      fetcher,
    ),
  );
  return { accounts: await Promise.all(tasks), updatedAt: new Date().toISOString() };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  collectQuotas()
    .then((value) => console.log(JSON.stringify(value)))
    .catch(() => {
      console.error("Quota collection failed");
      process.exitCode = 1;
    });
}
