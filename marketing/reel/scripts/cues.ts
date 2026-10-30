import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { STORY_ID, cueFile } from "../src/reel/timeline";

const out = path.join("public/audio", `${STORY_ID}.cues.json`);
mkdirSync(path.dirname(out), { recursive: true });
writeFileSync(out, JSON.stringify(cueFile()));
console.log(out);
