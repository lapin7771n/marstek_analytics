// tsx scripts/sheet.ts <out.png> [--props JSON] — the beat sheet: hook, each scene entering and at rest, last frame. Runs on the PC.
import { bundle } from "@remotion/bundler";
import { openBrowser, renderStill, selectComposition } from "@remotion/renderer";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { STORY_ID, review } from "../src/reel/timeline";

const [out, ...rest] = process.argv.slice(2);
if (out === undefined) {
  console.error("usage: sheet.ts <out.png> [--props JSON]");
  process.exit(2);
}
const at = rest.indexOf("--props");
const userProps: Record<string, string | number | boolean> = at >= 0 ? JSON.parse(rest[at + 1] ?? "{}") : {};

const tmp = mkdtempSync(path.join(tmpdir(), "reel-sheet-"));
const browser = await openBrowser("chrome", { chromiumOptions: { gl: null } });
let serveUrl: string | undefined;
try {
  serveUrl = await bundle({ entryPoint: path.resolve("src/index.ts") });
  const inputProps = { guides: true, ...userProps };
  const composition = await selectComposition({ serveUrl, id: STORY_ID, inputProps, puppeteerInstance: browser });
  const frames = review();
  for (const [i, f] of frames.entries()) {
    await renderStill({
      composition, serveUrl, inputProps, puppeteerInstance: browser, frame: f.frame,
      output: path.join(tmp, `tile-${String(i + 1).padStart(3, "0")}.png`),
    });
  }
  mkdirSync(path.dirname(path.resolve(out)), { recursive: true });
  execFileSync("ffmpeg", [
    "-y", "-loglevel", "error", "-framerate", "1", "-i", path.join(tmp, "tile-%03d.png"),
    "-vf", `scale=270:-1,tile=6x${Math.ceil(frames.length / 6)}`, "-frames:v", "1", path.resolve(out),
  ]);
  for (const [i, f] of frames.entries()) {
    console.log(`${String(i + 1).padStart(2, "0")}  ${(f.frame / composition.fps).toFixed(3)} s  frame ${f.frame}  ${f.label}`);
  }
} finally {
  await browser.close({ silent: true });
  rmSync(tmp, { recursive: true, force: true });
  if (serveUrl) rmSync(serveUrl, { recursive: true, force: true });
}
