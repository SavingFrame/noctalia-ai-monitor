import { realpathSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

// Only allowlisted metadata crosses the bridge. Never prompts, arguments, or results.
export default async function (pi: ExtensionAPI) {
  // Pi loads the installed symlink path. Resolve its real location before
  // importing shared code so both direct and auto-discovered loads work.
  const entryDir = dirname(realpathSync(fileURLToPath(import.meta.url)));
  const { processIdentity, writeRecord, removeRecord } = await import(
    pathToFileURL(resolve(entryDir, "../../ai-monitor/scripts/state.mjs")).href
  );
  let timer: ReturnType<typeof setInterval> | undefined;
  let context: ExtensionContext | undefined;
  let startTime = "";
  let enabled = false;
  let working = false;
  let prompts = 0;
  let failed = false;
  const tools = new Map<string, string>();
  let queue = Promise.resolve();

  function publish(ctx = context) {
    if (!enabled || !ctx) return queue;
    context = ctx;
    const usage = ctx.getContextUsage();
    const record = {
      version: 1,
      provider: "Pi",
      pid: process.pid,
      startTime,
      sessionId: ctx.sessionManager.getSessionId(),
      name: ctx.sessionManager.getSessionName() || "",
      cwd: ctx.cwd,
      model: ctx.model?.id || "",
      modelProvider: ctx.model?.provider || "",
      status:
        prompts > 0
          ? "waiting for input"
          : working
            ? tools.size
              ? "using tools"
              : "working"
            : failed
              ? "error"
              : "idle",
      tools: [...new Set(tools.values())].slice(0, 8),
      context: usage
        ? {
            tokens: usage.tokens,
            window: usage.contextWindow,
            percent: usage.percent,
          }
        : null,
      updatedAt: Date.now(),
      bridge: "pi-extension",
    };
    // Serialize writes so a heartbeat cannot overwrite a later event.
    queue = queue.then(() => writeRecord(record)).catch(() => {});
    return queue;
  }

  pi.on("session_start", async (_event, ctx) => {
    if (timer) clearInterval(timer);
    enabled = false;
    await queue;
    startTime = (await processIdentity(process.pid)).startTime;
    enabled = true;
    context = ctx;
    working = !ctx.isIdle();
    prompts = 0;
    failed = false;
    tools.clear();
    await publish(ctx);
    timer = setInterval(() => {
      void publish();
    }, 10000);
    timer.unref();
  });
  pi.on("before_agent_start", async (_event, ctx) => {
    working = true;
    failed = false;
    await publish(ctx);
  });
  pi.on("agent_start", async (_event, ctx) => {
    working = true;
    failed = false;
    await publish(ctx);
  });
  pi.on("tool_execution_start", async (event, ctx) => {
    tools.set(event.toolCallId, event.toolName);
    await publish(ctx);
  });
  pi.on("tool_execution_end", async (event, ctx) => {
    tools.delete(event.toolCallId);
    await publish(ctx);
  });
  pi.on("ui_prompt_start", async (_event, ctx) => {
    prompts++;
    await publish(ctx);
  });
  pi.on("ui_prompt_end", async (_event, ctx) => {
    prompts = Math.max(0, prompts - 1);
    await publish(ctx);
  });
  pi.on("message_end", async (event, ctx) => {
    if (event.message.role === "assistant") failed = event.message.stopReason === "error";
    await publish(ctx);
  });
  pi.on("agent_settled", async (event, ctx) => {
    working = false;
    tools.clear();
    prompts = 0;
    if (event.aborted) failed = false;
    await publish(ctx);
  });
  for (const event of [
    "model_select",
    "session_info_changed",
    "session_tree",
    "session_compact",
    "session_compact_failed",
  ] as const) {
    pi.on(event, async (_event, ctx) => {
      await publish(ctx);
    });
  }
  pi.on("session_shutdown", async () => {
    enabled = false;
    if (timer) clearInterval(timer);
    timer = undefined;
    await queue;
    await removeRecord("Pi", process.pid);
    context = undefined;
  });
}
