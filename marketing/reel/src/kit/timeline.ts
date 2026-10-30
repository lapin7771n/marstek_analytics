export type Easing = (x: number) => number;

export type CueSound = "tick" | "beep" | "whoosh" | "rise" | "chime";

export type Cue = {
  t: number;
  sound: CueSound;
  gain?: number;
  pan?: number;
  dur?: number;
};

export type CueFile = {
  fps: number;
  duration: number;
  track: { start: number; fadeOut: number };
  cues: Cue[];
  // For the Blender shots of a story: its beat and each scene's [t0, t1] in seconds.
  beat?: number;
  scenes?: Record<string, readonly [number, number]>;
  events?: Record<string, number | readonly number[]>;
};

export const clamp = (x: number, lo = 0, hi = 1): number =>
  Math.max(lo, Math.min(hi, x));

export const prog = (t: number, start: number, dur: number): number =>
  clamp((t - start) / dur);

export const lerp = (a: number, b: number, p: number): number =>
  a + (b - a) * p;

export const E = {
  lin: (x: number): number => x,
  outCubic: (x: number): number => 1 - Math.pow(1 - x, 3),
  outQuint: (x: number): number => 1 - Math.pow(1 - x, 5),
  outExpo: (x: number): number => (x >= 1 ? 1 : 1 - Math.pow(2, -10 * x)),
  inQuad: (x: number): number => x * x,
  inCubic: (x: number): number => x * x * x,
  inOut: (x: number): number =>
    x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2,
  outBack: (x: number): number =>
    1 + 2.2 * Math.pow(x - 1, 3) + 1.2 * Math.pow(x - 1, 2),
} as const satisfies Record<string, Easing>;

export const rng = (seed: number): (() => number) => {
  let s = seed;
  return (): number => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
};

export type Grid = {
  beat: number;
  q: (t: number, div?: number) => number;
  seq: (times: number[], div?: number) => number[];
};

export const grid = (bpm: number, speed: number): Grid => {
  const beat = (60 / bpm) * speed;
  const q = (t: number, div = 2): number =>
    Math.max(1, Math.round(t / (beat / div))) * (beat / div);
  const seq = (times: number[], div = 2): number[] =>
    times.reduce<number[]>(
      (out, t) => [...out, Math.max(q(t, div), (out.at(-1) ?? 0) + beat / div)],
      [],
    );
  return { beat, q, seq };
};

export const hold = (words: number): number => 0.8 + 0.3 * words;
