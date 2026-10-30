import type { CSSProperties, ReactElement } from "react";
import { AbsoluteFill, Img, staticFile, useCurrentFrame } from "remotion";
import { E, lerp, prog, rng } from "../kit/timeline";
import { useTime } from "../kit/motion";
import { COL_L, COL_W, H, RING, SAFE_BOTTOM, SAFE_TOP, W, colors, fontStack } from "./brand";
import { APP, CAPTION, CTA, NBSP } from "./copy";
import type { StoryProps } from "./props";
import { EV, EXIT, FRAMES, SCENES } from "./timeline";
import { AlertDisc, BoltDisc, Caption, CheckDisc, Eyebrow, Glass, Value } from "./ui";

export { storyProps, defaultProps } from "./props";

const frameFile = (frame: number): string =>
  `3d/ring/f_${String(Math.min(FRAMES, frame + 1)).padStart(4, "0")}.jpg`;

const Backdrop = ({ bloom }: { bloom: boolean }): ReactElement => {
  const frame = useCurrentFrame();
  const src = staticFile(frameFile(frame));
  const fill: CSSProperties = { position: "absolute", left: 0, top: 0, width: W, height: H };
  return (
    <>
      <Img src={src} style={fill} />
      {bloom ? (
        <Img
          src={src}
          style={{ ...fill, filter: "blur(46px) brightness(1.5) saturate(1.25)", mixBlendMode: "screen", opacity: 0.38 }}
        />
      ) : null}
    </>
  );
};

// Percent only: what the battery's own app shows.
const Readout = ({ t }: { t: number }): ReactElement => {
  const s = SCENES.problem;
  const tin = s[0] + 0.35;
  const tout = s[1] - EXIT;
  const a = E.outExpo(prog(t, tin, 0.45));
  const b = E.inCubic(prog(t, tout, 0.3));
  const on = t >= tin && t < tout + 0.3;
  return (
    <div
      style={{
        position: "absolute",
        left: RING.x - 220,
        width: 440,
        top: RING.y - 100,
        height: 200,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        fontFamily: fontStack,
        color: "rgba(255,255,255,0.86)",
        visibility: on ? "visible" : "hidden",
        opacity: Math.min(1, prog(t, tin, 0.2)) * (1 - b),
        transform: `translateY(${((1 - a) * 24 + b * 10).toFixed(2)}px)`,
        textShadow: "0 4px 30px rgba(0,0,0,0.55)",
      }}
    >
      <div style={{ display: "flex", alignItems: "baseline", lineHeight: 1 }}>
        <span style={{ fontSize: 176, fontWeight: 700, letterSpacing: "-0.02em" }}>58</span>
        <span style={{ fontSize: 76, fontWeight: 600, color: colors.unit, marginLeft: 10 }}>{NBSP}%</span>
      </div>
    </div>
  );
};

const HeroPanel = ({ t }: { t: number }): ReactElement => {
  const s = SCENES.answer;
  const pop = E.outBack(prog(t, s[0] + 0.1, 0.5));
  return (
    <Glass
      t={t} tin={s[0]} tout={s[1] - EXIT}
      x={COL_L} y={1150} w={COL_W} h={400} tilt={[7, -7]} glow="rgba(61,220,151,0.34)" pad={52}
    >
      <div style={{ display: "flex", flexDirection: "column", gap: 14, height: "100%", justifyContent: "center" }}>
        <Eyebrow size={44}>{APP.eta}</Eyebrow>
        <div style={{ transform: `scale(${lerp(0.9, 1, pop).toFixed(4)})`, transformOrigin: "0% 50%" }}>
          <Value parts={APP.hero} size={206} unit={92} />
        </div>
      </div>
    </Glass>
  );
};

const Divider = (): ReactElement => <div style={{ height: 2, background: "rgba(255,255,255,0.14)" }} />;

const VerdictPanel = ({ t }: { t: number }): ReactElement => {
  const s = SCENES.verdict;
  return (
    <Glass t={t} tin={s[0]} tout={s[1] - EXIT} x={COL_L} y={1210} w={COL_W} h={330} tilt={[7, -8]} glow="rgba(61,220,151,0.26)" pad={48}>
      <div style={{ display: "flex", alignItems: "center", gap: 34, height: "100%" }}>
        <CheckDisc size={120} />
        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          <Eyebrow color={colors.good} size={44}>{APP.lasts}</Eyebrow>
          <div style={{ fontSize: 52, fontWeight: 600, lineHeight: 1.2 }}>{APP.lastsLine}</div>
        </div>
      </div>
    </Glass>
  );
};

const TensionPanel = ({ t }: { t: number }): ReactElement => {
  const s = SCENES.tension;
  return (
    <Glass t={t} tin={s[0]} tout={s[1] - EXIT} x={COL_L} y={1210} w={COL_W} h={330} tilt={[7, 8]} glow="rgba(255,107,94,0.4)" pad={48}>
      <div style={{ display: "flex", alignItems: "center", gap: 34, height: "100%" }}>
        <AlertDisc size={120} />
        <div style={{ fontSize: 64, fontWeight: 700, lineHeight: 1.16, color: colors.white }}>{APP.runsOutLine}</div>
      </div>
    </Glass>
  );
};

const ActionPanel = ({ t }: { t: number }): ReactElement => {
  const s = SCENES.action;
  return (
    <Glass t={t} tin={s[0]} tout={s[1] - EXIT} x={COL_L} y={1170} w={COL_W} h={380} tilt={[7, -8]} glow="rgba(255,181,71,0.3)" pad={48}>
      <div style={{ display: "flex", flexDirection: "column", justifyContent: "space-between", height: "100%" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 32 }}>
          <BoltDisc size={120} />
          <div style={{ fontSize: 62, fontWeight: 700, lineHeight: 1.16 }}>{APP.cut}</div>
        </div>
        <Divider />
        <div style={{ fontSize: 44, fontWeight: 500, color: "rgba(255,255,255,0.72)" }}>{APP.kyiv}</div>
      </div>
    </Glass>
  );
};

const Cta = ({ t }: { t: number }): ReactElement => {
  const t0 = SCENES.cta[0];
  const tile = E.outBack(prog(t, t0 + 0.18, 0.6));
  const name = E.outExpo(prog(t, t0 + 0.45, 0.45));
  const go = E.outExpo(prog(t, t0 + 0.65, 0.45));
  const small = E.outExpo(prog(t, t0 + 0.8, 0.45));
  const text: CSSProperties = { position: "absolute", left: COL_L, width: COL_W, textAlign: "center", fontFamily: fontStack, color: colors.white };
  return (
    <>
      <div
        style={{
          position: "absolute",
          left: RING.x - 150,
          top: RING.y - 150,
          width: 300,
          height: 300,
          borderRadius: 67,
          overflow: "hidden",
          visibility: t >= t0 + 0.18 ? "visible" : "hidden",
          opacity: Math.min(1, tile * 1.6),
          transform: `scale(${lerp(0.6, 1, tile).toFixed(4)})`,
          boxShadow: "0 40px 80px -10px rgba(0,0,0,0.7), 0 0 0 1.5px rgba(255,255,255,0.18), inset 0 2px 0 rgba(255,255,255,0.3)",
        }}
      >
        <Img src={staticFile("brand/battery-eta-icon.svg")} style={{ width: 300, height: 300, display: "block" }} />
      </div>
      <div style={{ ...text, top: 1178, fontSize: 118, fontWeight: 750, letterSpacing: "-0.02em", lineHeight: 1.12, opacity: name, transform: `translateY(${((1 - name) * 40).toFixed(2)}px)`, visibility: t >= t0 + 0.45 ? "visible" : "hidden" }}>
        {CTA.name}
      </div>
      <div
        style={{
          position: "absolute", left: 540 - 330, width: 660, top: 1336, height: 104, display: "flex", alignItems: "center", justifyContent: "center",
          borderRadius: 52, fontFamily: fontStack, fontSize: 54, fontWeight: 700, color: "#06150E", background: colors.good,
          boxShadow: "0 0 90px -10px rgba(61,220,151,0.55), 0 24px 40px -14px rgba(0,0,0,0.6)",
          opacity: go, transform: `translateY(${((1 - go) * 40).toFixed(2)}px)`, visibility: t >= t0 + 0.65 ? "visible" : "hidden",
        }}
      >
        {CTA.action}
      </div>
      <div style={{ ...text, top: 1472, fontSize: 44, fontWeight: 500, color: "rgba(255,255,255,0.72)", opacity: small, visibility: t >= t0 + 0.8 ? "visible" : "hidden" }}>
        {CTA.compat}
      </div>
    </>
  );
};

const Guides = (): ReactElement => {
  const band: CSSProperties = {
    position: "absolute", left: 0, right: 0, display: "flex", alignItems: "center", justifyContent: "center",
    background: "repeating-linear-gradient(45deg, rgba(243,98,93,.38) 0 18px, rgba(243,98,93,.2) 18px 36px)",
    color: "#fff", fontFamily: fontStack, fontSize: 30, fontWeight: 600,
  };
  return (
    <div style={{ position: "absolute", inset: 0, zIndex: 9 }}>
      <div style={{ ...band, top: 0, height: SAFE_TOP }}>БЕЗПЕЧНА ЗОНА · 250 px</div>
      <div style={{ ...band, top: SAFE_BOTTOM, height: H - SAFE_BOTTOM }}>БЕЗПЕЧНА ЗОНА · 1580 px</div>
    </div>
  );
};

export const BatteryEtaReel = (props: StoryProps): ReactElement => {
  const t = useTime(1, 0);
  const frame = useCurrentFrame();
  const r = rng(frame * 7919 + 13);
  const jitter = { x: Math.floor(r() * 256), y: Math.floor(r() * 256) };
  const redVig = E.inOut(prog(t, SCENES.tension[0], 0.35)) * (1 - E.inOut(prog(t, SCENES.action[0], 0.4)));
  const cap = (
    key: keyof typeof CAPTION,
    scene: readonly [number, number],
    extra?: { accent?: { line: number; color: string }; size?: number; tin?: number },
  ): ReactElement => (
    <Caption
      t={t} tin={extra?.tin ?? scene[0] + 0.1} tout={scene[1] - EXIT}
      lines={CAPTION[key]} size={extra?.size} accent={extra?.accent}
    />
  );
  return (
    <AbsoluteFill style={{ background: colors.bg, fontFamily: fontStack, overflow: "hidden" }}>
      <Backdrop bloom={props.bloom} />
      <div style={{ position: "absolute", inset: 0, background: "radial-gradient(ellipse 80% 60% at 50% 45%, rgba(255,107,94,0.30), rgba(255,107,94,0) 70%)", opacity: redVig }} />
      {cap("hook", SCENES.hook, { tin: 0.1, size: 76 })}
      {cap("problem", SCENES.problem, { size: 76 })}
      {cap("answer", SCENES.answer, { size: 100 })}
      {cap("verdict", SCENES.verdict)}
      {cap("tension", SCENES.tension, { accent: { line: 1, color: colors.bad } })}
      {cap("action", SCENES.action)}
      <Readout t={t} />
      <HeroPanel t={t} />
      <VerdictPanel t={t} />
      <TensionPanel t={t} />
      <ActionPanel t={t} />
      <Cta t={t} />
      <div style={{ position: "absolute", inset: 0, background: "radial-gradient(ellipse 90% 75% at 50% 48%, rgba(0,0,0,0) 55%, rgba(0,0,0,0.5) 100%)" }} />
      <div
        style={{
          position: "absolute", left: -256, top: -256, width: W + 512, height: H + 512,
          backgroundImage: `url(${staticFile("brand/grain.png")})`, backgroundSize: "540px 960px",
          backgroundPosition: `${jitter.x}px ${jitter.y}px`, mixBlendMode: "overlay", opacity: 0.1,
        }}
      />
      {props.guides ? <Guides /> : null}
    </AbsoluteFill>
  );
};

void EV;
