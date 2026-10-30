import type { ReactElement } from "react";
import { Composition } from "remotion";
import { BatteryEtaReel } from "./reel";
import { defaultProps, storyProps } from "./reel/props";
import { FPS, FRAMES, STORY_ID } from "./reel/timeline";

export const Root = (): ReactElement => (
  <Composition
    id={STORY_ID}
    component={BatteryEtaReel}
    schema={storyProps}
    defaultProps={defaultProps}
    width={1080}
    height={1920}
    fps={FPS}
    durationInFrames={FRAMES}
  />
);
