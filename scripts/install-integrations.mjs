import { lstat, mkdir, readFile, symlink, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { EVENTS } from "../ai-monitor/scripts/claude-hook.mjs";

export function mergeHooks(settings, command) {
  if (
    settings.hooks != null &&
    (typeof settings.hooks !== "object" || Array.isArray(settings.hooks))
  )
    throw new Error("Invalid existing hooks configuration");
  const next = structuredClone(settings);
  next.hooks ||= {};
  for (const event of EVENTS) {
    if (next.hooks[event] != null && !Array.isArray(next.hooks[event]))
      throw new Error("Invalid hook event: " + event);
    const groups = (next.hooks[event] ||= []);
    if (
      groups.some((group) =>
        group.hooks?.some((hook) => hook.command === command),
      )
    )
      continue;
    groups.push({ hooks: [{ type: "command", command, timeout: 2 }] });
  }
  return next;
}
function quote(value) {
  return "'" + value.replaceAll("'", "'\\''") + "'";
}

export async function install({
  home = homedir(),
  root = resolve(dirname(fileURLToPath(import.meta.url)), ".."),
} = {}) {
  const agent = process.env.PI_CODING_AGENT_DIR || join(home, ".pi/agent");
  const extension = join(agent, "extensions", "noctalia-ai-monitor");
  await mkdir(dirname(extension), { recursive: true });
  const existing = await lstat(extension).catch((error) => {
    if (error.code !== "ENOENT") throw error;
    return null;
  });
  if (!existing) await symlink(join(root, "integrations/pi"), extension, "dir");
  else {
    const { realpath } = await import("node:fs/promises");
    if (
      (await realpath(extension)) !==
      (await realpath(join(root, "integrations/pi")))
    )
      throw new Error("Pi extension path already exists; not overwritten");
  }
  const settingsFile = join(
    process.env.CLAUDE_CONFIG_DIR || join(home, ".claude"),
    "settings.json",
  );
  await mkdir(dirname(settingsFile), { recursive: true });
  const original = await readFile(settingsFile, "utf8").catch((error) => {
    if (error.code !== "ENOENT") throw error;
    return null;
  });
  const settings = original === null ? {} : JSON.parse(original);
  // exec avoids a lingering shell; the helper still walks ancestors defensively.
  const command =
    "exec " +
    quote(process.execPath) +
    " " +
    quote(join(root, "ai-monitor/scripts/claude-hook.mjs"));
  const updated = mergeHooks(settings, command);
  if (JSON.stringify(updated) !== JSON.stringify(settings)) {
    if (original !== null) {
      const backup = settingsFile + ".before-ai-monitor-" + Date.now();
      await writeFile(backup, original, { mode: 0o600, flag: "wx" });
      console.log("Claude settings backup: " + backup);
    }
    // Config is changed once during installation, not by the running plugin.
    await writeFile(settingsFile, JSON.stringify(updated, null, 2) + "\n", {
      mode: 0o600,
    });
  }
  console.log("Pi extension: " + extension);
  console.log("Claude hooks: " + settingsFile);
  console.log(
    "Run /reload in existing Pi sessions. Restart existing Claude sessions.",
  );
}
if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  install().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
