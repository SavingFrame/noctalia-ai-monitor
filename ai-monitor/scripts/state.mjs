import { mkdir, readFile, rename, writeFile, unlink } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";

export function stateDir() {
  return join(
    process.env.XDG_STATE_HOME || join(homedir(), ".local/state"),
    "noctalia-ai-monitor",
    "sessions",
  );
}
export async function processIdentity(pid, root = "/proc") {
  const raw = await readFile(join(root, String(pid), "stat"), "utf8");
  const fields = raw
    .slice(raw.lastIndexOf(")") + 2)
    .trim()
    .split(/\s+/);
  return { ppid: Number(fields[1]), startTime: fields[19] };
}
export function recordPath(provider, pid, dir = stateDir()) {
  return join(dir, provider.toLowerCase() + "-" + pid + ".json");
}
export async function readRecord(provider, pid, dir = stateDir()) {
  try {
    const file = join(dir, provider.toLowerCase() + "-" + pid + ".json");
    const raw = await readFile(file, "utf8");
    if (raw.length > 65536) return null;
    return JSON.parse(raw);
  } catch {
    return null;
  }
}
export async function writeRecord(record, dir = stateDir()) {
  await mkdir(dir, { recursive: true, mode: 0o700 });
  const file = recordPath(record.provider, record.pid, dir);
  const temp = file + "." + randomUUID() + ".tmp";
  try {
    await writeFile(temp, JSON.stringify(record), { mode: 0o600, flag: "wx" });
    await rename(temp, file);
  } finally {
    await unlink(temp).catch(() => {});
  }
}
export async function removeRecord(provider, pid, dir = stateDir()) {
  await unlink(recordPath(provider, pid, dir)).catch(() => {});
}
