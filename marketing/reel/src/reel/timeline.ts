import { E, clamp, prog, type CueFile } from "../kit/timeline";
import { APP, CAPTION, CTA } from "./copy";

export const STORY_ID = "BatteryEtaReel";
export const FPS = 60;
export const BPM = 105;
export const BEAT = 60 / BPM;

// Entry animation settles this long after a scene starts; the exit starts this long before it ends.
export const SETTLE = 0.6;
export const EXIT = 0.3;
const CTA_SETTLE = 1.25;

type BeatDef = {
  texts: readonly string[];
  // A ring state change, a chart or several panels: the eye needs a second to find them.
  change?: boolean;
  settle?: number;
  exit?: number;
};

const lines = (l: readonly string[]): string[] => [...l];

const DEFS = {
  hook: { texts: lines(CAPTION.hook) },
  problem: { texts: [...lines(CAPTION.problem), APP.percent], change: true, settle: 0.85 },
  answer: { texts: [...lines(CAPTION.answer), APP.eta, APP.heroText], change: true },
  verdict: { texts: [...lines(CAPTION.verdict), APP.lasts, APP.lastsLine] },
  tension: { texts: [...lines(CAPTION.tension), APP.runsOutLine], change: true },
  action: { texts: [...lines(CAPTION.action), APP.cut, APP.kyiv], change: true },
  cta: { texts: [CTA.name, CTA.action, CTA.compat], settle: CTA_SETTLE, exit: 0 },
} as const satisfies Record<string, BeatDef>;

export type SceneKey = keyof typeof DEFS;
export const SCENE_KEYS = Object.keys(DEFS) as SceneKey[];

export const countWords = (texts: readonly string[]): number =>
  texts
    .join(" ")
    .split(/\s+/)
    .filter((w) => /[\p{L}\p{N}%]/u.test(w)).length;

export const requiredHold = (def: BeatDef): number =>
  0.8 + 0.3 * countWords(def.texts) + (def.change ? 1 : 0);

const beatsOf = (def: BeatDef): number =>
  Math.ceil(
    (requiredHold(def) + (def.settle ?? SETTLE) + (def.exit ?? EXIT)) / BEAT - 1e-9,
  );

export const BEATS = Object.fromEntries(
  SCENE_KEYS.map((k) => [k, beatsOf(DEFS[k])]),
) as Record<SceneKey, number>;

const bounds = (): Record<SceneKey, readonly [number, number]> => {
  let at = 0;
  const out = {} as Record<SceneKey, readonly [number, number]>;
  for (const key of SCENE_KEYS) {
    const t0 = at;
    at += BEATS[key] * BEAT;
    out[key] = [Number(t0.toFixed(4)), Number(at.toFixed(4))] as const;
  }
  return out;
};

export const SCENES = bounds();
export const DURATION = SCENES.cta[1];
export const FRAMES = Math.round(DURATION * FPS);

export type HoldRow = {
  key: SceneKey;
  words: number;
  required: number;
  actual: number;
};

export const holdTable = (): HoldRow[] =>
  SCENE_KEYS.map((key) => {
    const def: BeatDef = DEFS[key];
    const [t0, t1] = SCENES[key];
    return {
      key,
      words: countWords(def.texts),
      required: Number(requiredHold(def).toFixed(3)),
      actual: Number((t1 - (def.exit ?? EXIT) - (t0 + (def.settle ?? SETTLE))).toFixed(3)),
    };
  });

export const EV = {
  glide: [SCENES.problem[0] - 0.9, SCENES.problem[0] - 0.1] as const,
  fillStart: SCENES.problem[0] + 0.05,
  fillDur: 0.7,
  fillTo: 0.58,
  warm: [SCENES.answer[0], SCENES.answer[0] + 0.7] as const,
  threadStart: SCENES.answer[0] + 0.05,
  red: [SCENES.tension[0], SCENES.tension[0] + 0.35] as const,
  green: [SCENES.action[0], SCENES.action[0] + 0.4] as const,
  ctaFace: [SCENES.cta[0], SCENES.cta[0] + 0.8] as const,
};

export const fillAt = (t: number): number =>
  EV.fillTo * E.outCubic(prog(t, EV.fillStart, EV.fillDur));

export const percentAt = (t: number): number => Math.round(fillAt(t) * 100);

export const review = () => {
  const at = (t: number): number => Math.min(Math.round(t * FPS), FRAMES - 1);
  return [
    ...[0, 1, 2].map((s) => ({ frame: at(s), label: `hook ${s}s` })),
    ...SCENE_KEYS.flatMap((key, i) => {
      const [t0, t1] = SCENES[key];
      const def: BeatDef = DEFS[key];
      return [
        ...(i > 0 ? [{ frame: at(t0 + 0.2), label: `enter ${key}` }] : []),
        { frame: at(t1 - (def.exit ?? EXIT) - 0.05), label: `${key} at rest` },
      ];
    }),
    { frame: FRAMES - 1, label: "last" },
  ];
};

export const cueFile = (): CueFile => {
  const s = SCENES;
  return {
    fps: FPS,
    duration: DURATION,
    track: { start: 0, fadeOut: 0 },
    beat: BEAT,
    scenes: s,
    events: EV,
    cues: [
      { t: s.problem[0] - 0.3, sound: "rise", gain: 0.25, dur: 0.3 },
      { t: EV.fillStart + EV.fillDur, sound: "tick", gain: 0.35 },
      { t: s.answer[0] - 0.5, sound: "rise", gain: 0.32, dur: 0.5 },
      { t: EV.threadStart + 0.1, sound: "whoosh", gain: 0.24, dur: 0.8 },
      { t: s.answer[0] + 0.3, sound: "tick", gain: 0.65 },
      { t: s.answer[0] + 0.3 + BEAT, sound: "chime", gain: 0.5 },
      { t: s.verdict[0], sound: "tick", gain: 0.45 },
      { t: s.verdict[0] + BEAT, sound: "chime", gain: 0.3, pan: 0.2 },
      { t: s.tension[0], sound: "tick", gain: 0.7 },
      { t: s.tension[0] + BEAT * 2, sound: "tick", gain: 0.4 },
      { t: s.action[0] - 0.3, sound: "rise", gain: 0.25, dur: 0.3 },
      { t: s.action[0], sound: "tick", gain: 0.5 },
      { t: s.action[0] + BEAT * 2, sound: "chime", gain: 0.4, pan: -0.2 },
      { t: s.cta[0] - 0.5, sound: "rise", gain: 0.3, dur: 0.5 },
      { t: s.cta[0], sound: "tick", gain: 0.65 },
      { t: s.cta[0] + BEAT, sound: "chime", gain: 0.5 },
    ],
  };
};

export { clamp };
