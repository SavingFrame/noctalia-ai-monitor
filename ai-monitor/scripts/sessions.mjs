import { readdir, readFile, readlink, stat } from "node:fs/promises";
import { basename } from "node:path";
import { pathToFileURL } from "node:url";
import { processIdentity, readRecord, stateDir } from "./state.mjs";

export function enrich(session, record, startTime, now = Date.now()) {
  if (record?.version !== 1 || !startTime || record.startTime !== startTime ||
      record.provider !== session.provider || record.pid !== session.pid ||
      typeof record.sessionId !== "string" || !Number.isFinite(record.updatedAt) || record.updatedAt > now + 5000) return session;
  const age = now - record.updatedAt;
  const stale = session.provider === "Pi" ? age > 40000 : age > 120000 && !["idle", "error"].includes(record.status);
  const statuses = ["idle", "working", "using tools", "waiting for input", "waiting for permission", "error"];
  return {
    ...session, sessionId: record.sessionId,
    cwd: typeof record.cwd === "string" && record.cwd ? record.cwd : session.cwd,
    project: typeof record.cwd === "string" && record.cwd ? basename(record.cwd) || record.cwd : session.project,
    name: typeof record.name === "string" ? record.name.slice(0, 200) : "",
    model: typeof record.model === "string" ? record.model.slice(0, 200) : "",
    modelProvider: typeof record.modelProvider === "string" ? record.modelProvider.slice(0, 100) : "",
    status: stale ? "activity unconfirmed" : statuses.includes(record.status) ? record.status : "running",
    tools: !stale && Array.isArray(record.tools) ? record.tools.filter(t => typeof t === "string").slice(0, 8) : [],
    context: !stale && record.context && Number.isFinite(record.context.percent) && record.context.percent >= 0 && record.context.percent <= 100
      ? { percent: record.context.percent, tokens: record.context.tokens, window: record.context.window } : null,
    bridge: record.bridge, lastEventAt: new Date(record.updatedAt).toISOString(),
  };
}

// Process presence is not agent activity. Never infer working/idle from CPU use.
export function classify(comm, argv) {
  if (comm === "pi") return "Pi";
  if (comm === "claude") return "Claude";
  if (!/^(node|bun)(?:[0-9.]*)?$/.test(comm)) return null;
  const script = argv[1] ?? "";
  if (/(?:^|\/)@earendil-works\/pi-coding-agent\/.*\/cli\.js$/.test(script) ||
      /(?:^|\/)@mariozechner\/pi-coding-agent\/.*\/cli\.js$/.test(script)) return "Pi";
  if (/(?:^|\/)@anthropic-ai\/claude-code\/cli\.js$/.test(script)) return "Claude";
  return null;
}

export async function scan(procRoot = "/proc", uid = process.getuid(), recordsDir = stateDir()) {
  const entries = await readdir(procRoot, { withFileTypes: true });
  const sessions = (await Promise.all(entries.filter(e => e.isDirectory() && /^\d+$/.test(e.name)).map(async entry => {
    const dir = procRoot + "/" + entry.name;
    try {
      if ((await stat(dir)).uid !== uid) return null;
      const comm = (await readFile(dir + "/comm", "utf8")).trim();
      if (!["pi", "claude"].includes(comm) && !/^(node|bun)(?:[0-9.]*)?$/.test(comm)) return null;
      const argv = (await readFile(dir + "/cmdline", "utf8")).split("\0").filter(Boolean);
      // An empty command line usually indicates a zombie or a process exiting.
      if (!argv.length) return null;
      const provider = classify(comm, argv);
      if (!provider) return null;
      const cwd = await readlink(dir + "/cwd").catch(() => "");
      const session = {
        id: provider.toLowerCase() + ":" + entry.name,
        provider, pid: Number(entry.name), cwd: cwd || "(unavailable)",
        project: cwd ? basename(cwd) || cwd : "(unavailable)",
        status: "running",
      };
      const identity = await processIdentity(session.pid, procRoot).catch(() => null);
      return enrich(session, await readRecord(provider, session.pid, recordsDir), identity?.startTime);
    } catch {
      // Processes can exit or become inaccessible between reads.
      return null;
    }
  }))).filter(Boolean).sort((a, b) => a.provider.localeCompare(b.provider) || a.pid - b.pid);
  return {
    sessions, source: "live", updatedAt: new Date().toISOString(),
    error: "", limits: "Not connected",
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  scan().then(snapshot => console.log(JSON.stringify(snapshot))).catch(error => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
