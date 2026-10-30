import type { CSSProperties } from "react";
import { useCurrentFrame, useVideoConfig } from "remotion";
import { E, lerp, prog, type Easing } from "./timeline";

export type Life = {
  in: number;
  din?: number;
  out?: number;
  dout?: number;
  from?: readonly [number, number];
  to?: readonly [number, number];
  s0?: number;
  s1?: number;
  ein?: Easing;
  eout?: Easing;
  fadeIn?: number;
  keep?: boolean;
};

export const mv = (t: number, life: Life): CSSProperties => {
  const din = life.din ?? 0.5;
  const dout = life.dout ?? 0.3;
  const a = (life.ein ?? E.outExpo)(prog(t, life.in, din));
  const b =
    life.out === undefined ? 0 : (life.eout ?? E.inCubic)(prog(t, life.out, dout));
  const on =
    t >= life.in && (life.out === undefined || t < life.out + dout);
  if (!on) return { visibility: "hidden" };
  const x = (life.from?.[0] ?? 0) * (1 - a) + (life.to?.[0] ?? 0) * b;
  const y = (life.from?.[1] ?? 0) * (1 - a) + (life.to?.[1] ?? 0) * b;
  const s = lerp(life.s0 ?? 1, 1, a) * lerp(1, life.s1 ?? 1, b);
  return {
    visibility: "visible",
    opacity:
      Math.min(1, prog(t, life.in, din * (life.fadeIn ?? 0.3))) *
      (1 - (life.keep ? 0 : Math.pow(b, 1.5))),
    transform: `translate(${x.toFixed(2)}px, ${y.toFixed(2)}px) scale(${s.toFixed(4)})`,
  };
};

export const useTime = (speed: number, t0: number): number => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (frame / fps) * speed + t0;
};
