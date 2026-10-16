import { readFile, mkdir, rmdir, stat } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { join } from "node:path";
import { processIdentity, readRecord, writeRecord, removeRecord, stateDir } from "./state.mjs";

export const EVENTS = [
  "SessionStart",
  "UserPromptSubmit",
  "PreToolUse",
  "PostToolUse",
  "PostToolUseFailure",
  "PermissionRequest",
  "Notification",
  "Stop",
  "StopFailure",
  "SessionEnd",
  "PostModelSwitch",
  "CwdChanged",
];

export function reduceHook(previous, input, identity, now = Date.now()) {
  if (
    !EVENTS.includes(input.hook_event_name) ||
    typeof input.session_id !== "string" ||
    !input.session_id ||
    input.agent_id
  )
    return null;
  const event = input.hook_event_name;
  const same =
    previous?.sessionId === input.session_id && previous?.startTime === identity.startTime;
  if (event === "SessionEnd") return same ? { remove: true } : null;
  const old = same ? previous : {};
  const tool = typeof input.tool_name === "string" ? input.tool_name.slice(0, 120) : "";
  let status = old.status || "idle";
  let tools = old.tools || [];
  if (event === "UserPromptSubmit") {
    status = "working";
    tools = [];
  }
  if (event === "PreToolUse") {
    status = tool === "AskUserQuestion" ? "waiting for input" : "using tools";
    tools = tool ? [tool] : [];
  }
  if (event === "PermissionRequest") {
    status = "waiting for permission";
    tools = tool ? [tool] : [];
  }
  if (event === "PostToolUse" || event === "PostToolUseFailure") {
    status = "working";
    tools = [];
  }
  if (event === "Stop") {
    status = "idle";
    tools = [];
  }
  if (event === "StopFailure") {
    status = "error";
    tools = [];
  }
  if (event === "Notification") {
    if (input.notification_type === "permission_prompt") status = "waiting for permission";
    else if (input.notification_type === "idle_prompt") {
      status = "idle";
      tools = [];
    } else return null;
  }
  return {
    version: 1,
    provider: "Claude",
    ...identity,
    sessionId: input.session_id.slice(0, 200),
    cwd: typeof input.cwd === "string" ? input.cwd.slice(0, 4096) : old.cwd || "",
    model: (typeof input.model === "string"
      ? input.model
      : typeof input.to_model === "string"
        ? input.to_model
        : old.model || ""
    ).slice(0, 200),
    modelProvider: "anthropic",
    name: "",
    status,
    tools,
    updatedAt: now,
    bridge: "claude-hooks",
    lastEvent: event,
  };
}

export async function findClaudeAncestor(pid = process.ppid, root = "/proc") {
  for (let i = 0; i < 12 && pid > 1; i++) {
    const info = await processIdentity(pid, root);
    const comm = (await readFile(join(root, String(pid), "comm"), "utf8")).trim();
    if (comm === "claude") return { pid, startTime: info.startTime };
    pid = info.ppid;
  }
  return null;
}

export async function handleHook(input, identity, dir = stateDir()) {
  if (!identity || !EVENTS.includes(input.hook_event_name) || input.agent_id) return;
  await mkdir(dir, { recursive: true, mode: 0o700 });
  // Claude may run sibling tool hooks concurrently. Serialize read-modify-write.
  const lock = join(dir, "claude-" + identity.pid + ".lock");
  let acquired = false;
  for (let i = 0; i < 30; i++) {
    try {
      await mkdir(lock);
      acquired = true;
      break;
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
      // Recover a lock left by an interrupted hook. Normal hooks finish well
      // before their 2-second host timeout, so 10 seconds is conservative.
      const info = await stat(lock).catch(() => null);
      if (info && Date.now() - info.mtimeMs > 10000) await rmdir(lock).catch(() => {});
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
  }
  if (!acquired) return; // Monitoring must never block or deny an agent action.
  try {
    const old = await readRecord("Claude", identity.pid, dir);
    const record = reduceHook(old, input, identity);
    if (record?.remove) await removeRecord("Claude", identity.pid, dir);
    else if (record) await writeRecord(record, dir);
  } finally {
    await rmdir(lock).catch(() => {});
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  // Fail open. No output can be mistaken for hook decisions or injected context.
  try {
    let raw = "";
    for await (const chunk of process.stdin) {
      raw += chunk;
      if (raw.length > 4 * 1024 * 1024) throw new Error("Hook input too large");
    }
    await handleHook(JSON.parse(raw), await findClaudeAncestor());
  } catch {
    /* Telemetry failure must not affect Claude. */
  }
}
