import type { CSSProperties, ReactElement } from "react";
import { Img, staticFile, useCurrentFrame } from "remotion";

export type Layer3DProps = {
  story: string;
  shot: string;
  from: number;
  frames: number;
  style?: CSSProperties;
};

export const layerFile = (
  story: string,
  shot: string,
  frame: number,
  from: number,
  frames: number,
): string | null => {
  const n = frame - from + 1;
  if (n < 1 || n > frames) return null;
  return `3d/${story}/${shot}/f_${String(n).padStart(4, "0")}.png`;
};

export const Layer3D = ({ story, shot, from, frames, style }: Layer3DProps): ReactElement | null => {
  const frame = useCurrentFrame();
  const file = layerFile(story, shot, frame, from, frames);
  if (file === null) return null;
  return (
    <Img
      src={staticFile(file)}
      style={{ position: "absolute", left: 0, top: 0, width: "100%", height: "100%", ...style }}
    />
  );
};
