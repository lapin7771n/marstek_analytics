import { loadFont } from "@remotion/fonts";
import { staticFile } from "remotion";

export const colors = {
  bg: "#0F0F12",
  card: "#18181C",
  edge: "#2A2A30",
  track: "#24242A",
  label: "#8E8E93",
  unit: "#8E8E97",
  good: "#3DDC97",
  warn: "#FFB547",
  bad: "#FF6B5E",
  white: "#FFFFFF",
} as const;

export const FONT = "Onest";
export const fontStack = `"${FONT}", system-ui, sans-serif`;

void loadFont({
  family: FONT,
  url: staticFile("fonts/onest-cyrillic-wght-normal.woff2"),
  format: "woff2",
  weight: "100 900",
  unicodeRange: "U+0301,U+0400-045F,U+0490-0491,U+04B0-04B1,U+2116",
});
void loadFont({
  family: FONT,
  url: staticFile("fonts/onest-latin-wght-normal.woff2"),
  format: "woff2",
  weight: "100 900",
  unicodeRange:
    "U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD",
});

export const W = 1080;
export const H = 1920;
export const COL_L = 96;
export const COL_W = 888;
export const SAFE_TOP = 250;
export const SAFE_BOTTOM = 1580;
export const RING = { x: 540, y: 880 } as const;
