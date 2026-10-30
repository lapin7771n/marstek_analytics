import type { CSSProperties, ReactElement, ReactNode } from "react";
import { COL_L, COL_W, colors, fontStack } from "./brand";
import { E, lerp, prog } from "../kit/timeline";

export type Rect = { x: number; y: number; w: number; h: number };

type Tilt = readonly [number, number];

export type GlassProps = Rect & {
  t: number;
  tin: number;
  tout?: number;
  tilt?: Tilt;
  glow?: string;
  radius?: number;
  pad?: number;
  din?: number;
  dout?: number;
  rise?: number;
  children?: ReactNode;
  style?: CSSProperties;
};

// A tilted Liquid Glass panel: white gradient 18% to 4%, thin white border, bright top edge, deep shadow.
export const Glass = ({
  t, tin, tout, x, y, w, h, tilt = [7, -8], glow, radius = 52, pad = 44,
  din = 0.5, dout = 0.36, rise = 230, children, style,
}: GlassProps): ReactElement => {
  const a = E.outCubic(prog(t, tin, din));
  const b = tout === undefined ? 0 : E.inCubic(prog(t, tout, dout));
  const on = t >= tin && (tout === undefined || t < tout + dout);
  const dy = (1 - a) * rise + b * 210;
  const rx = tilt[0] + (1 - a) * 16 + b * 10;
  const s = lerp(0.97, 1, a);
  const opacity = Math.min(1, prog(t, tin, din * 0.5)) * (1 - Math.pow(b, 1.5));
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        width: w,
        height: h,
        boxSizing: "border-box",
        visibility: on ? "visible" : "hidden",
        opacity,
        transform: `perspective(1900px) translateY(${dy.toFixed(2)}px) rotateX(${rx.toFixed(3)}deg) rotateY(${tilt[1]}deg) scale(${s.toFixed(4)})`,
        transformOrigin: "50% 60%",
        borderRadius: radius,
        padding: pad,
        background:
          "linear-gradient(135deg, rgba(255,255,255,0.18) 0%, rgba(255,255,255,0.075) 45%, rgba(255,255,255,0.04) 100%)",
        backdropFilter: "blur(34px) saturate(1.5)",
        WebkitBackdropFilter: "blur(34px) saturate(1.5)",
        border: "1.5px solid rgba(255,255,255,0.22)",
        boxShadow: [
          "inset 0 2px 0 rgba(255,255,255,0.42)",
          "inset 0 -2px 0 rgba(255,255,255,0.05)",
          "inset 0 0 40px rgba(255,255,255,0.03)",
          "0 60px 90px -30px rgba(0,0,0,0.7)",
          "0 18px 40px -12px rgba(0,0,0,0.45)",
          glow ? `0 0 110px -10px ${glow}` : "0 0 0 0 transparent",
        ].join(", "),
        color: colors.white,
        fontFamily: fontStack,
        ...style,
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: radius,
          background:
            "linear-gradient(112deg, rgba(255,255,255,0.16) 0%, rgba(255,255,255,0) 32%)",
          pointerEvents: "none",
        }}
      />
      <div style={{ position: "relative", width: "100%", height: "100%" }}>{children}</div>
    </div>
  );
};

export type Span = { text: string; color?: string };

export const Caption = ({
  t, tin, tout, lines, top = 300, size = 84, accent,
}: {
  t: number;
  tin: number;
  tout: number;
  lines: readonly string[];
  top?: number;
  size?: number;
  accent?: { line: number; color: string };
}): ReactElement => {
  const a = E.outExpo(prog(t, tin, 0.42));
  const b = E.inCubic(prog(t, tout, 0.3));
  const on = t >= tin && t < tout + 0.3;
  return (
    <div
      style={{
        position: "absolute",
        left: COL_L,
        width: COL_W,
        top,
        textAlign: "center",
        fontFamily: fontStack,
        fontWeight: 700,
        fontSize: size,
        lineHeight: 1.16,
        letterSpacing: "-0.012em",
        color: colors.white,
        visibility: on ? "visible" : "hidden",
        opacity: Math.min(1, prog(t, tin, 0.14)) * (1 - Math.pow(b, 1.5)),
        transform: `translateY(${((1 - a) * 44 - b * 56).toFixed(2)}px)`,
        textShadow: "0 6px 40px rgba(0,0,0,0.6)",
      }}
    >
      {lines.map((line, i) => (
        <div key={i} style={{ color: accent?.line === i ? accent.color : undefined }}>
          {line}
        </div>
      ))}
    </div>
  );
};

export const Eyebrow = ({ children, color = colors.label, size = 38 }: { children: ReactNode; color?: string; size?: number }): ReactElement => (
  <div style={{ fontSize: size, fontWeight: 650, letterSpacing: "0.16em", color, lineHeight: 1.2 }}>{children}</div>
);

// Digits big and white, units small and grey, as in the app's ValueText.
export const Value = ({ parts, size, unit }: { parts: readonly string[]; size: number; unit?: number }): ReactElement => (
  <div style={{ display: "flex", alignItems: "baseline", fontFamily: fontStack, lineHeight: 1.1 }}>
    {parts.map((p, i) => {
      const digits = /^\d+$/.test(p);
      return (
        <span
          key={i}
          style={{
            fontSize: digits ? size : (unit ?? size * 0.42),
            fontWeight: digits ? 700 : 600,
            color: digits ? colors.white : colors.unit,
            marginRight: digits ? size * 0.1 : size * 0.16,
            fontVariantNumeric: "tabular-nums",
          }}
        >
          {p}
        </span>
      );
    })}
  </div>
);

export const CheckDisc = ({ size, color = colors.good }: { size: number; color?: string }): ReactElement => (
  <svg viewBox="0 0 96 96" style={{ width: size, height: size, flex: "none" }}>
    <circle cx="48" cy="48" r="48" fill={color} opacity="0.2" />
    <path d="M27 49l14 14 29-31" fill="none" stroke={color} strokeWidth="8" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

export const AlertDisc = ({ size, color = colors.bad }: { size: number; color?: string }): ReactElement => (
  <svg viewBox="0 0 96 96" style={{ width: size, height: size, flex: "none" }}>
    <circle cx="48" cy="48" r="48" fill={color} opacity="0.2" />
    <path d="M48 26v30" fill="none" stroke={color} strokeWidth="9" strokeLinecap="round" />
    <circle cx="48" cy="70" r="5.5" fill={color} />
  </svg>
);

export const BoltDisc = ({ size, color = colors.warn }: { size: number; color?: string }): ReactElement => (
  <svg viewBox="0 0 96 96" style={{ width: size, height: size, flex: "none" }}>
    <circle cx="48" cy="48" r="48" fill={color} opacity="0.2" />
    <path d="M52 20L30 54h16l-4 22 24-36H50z" fill={color} />
  </svg>
);

// The gauge used by the widgets: 270 degree track with a coloured arc, as in the app icon.
export const Gauge = ({ size, fill, color, stroke = 11, children }: { size: number; fill: number; color: string; stroke?: number; children?: ReactNode }): ReactElement => {
  const r = 50;
  const c = 2 * Math.PI * r;
  const sweep = c * 0.75;
  return (
    <div style={{ position: "relative", width: size, height: size, flex: "none" }}>
      <svg viewBox="0 0 144 144" style={{ position: "absolute", inset: 0, width: "100%", height: "100%" }}>
        <circle cx="72" cy="74" r={r} fill="none" stroke={colors.track} strokeWidth={stroke} strokeLinecap="round" strokeDasharray={`${sweep} 999`} transform="rotate(135 72 74)" />
        <circle cx="72" cy="74" r={r} fill="none" stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeDasharray={`${sweep * fill} 999`} transform="rotate(135 72 74)" />
      </svg>
      <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center" }}>{children}</div>
    </div>
  );
};
