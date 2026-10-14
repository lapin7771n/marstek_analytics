import type { KeyView } from "./views";

const SIZE = 144;
const FONT = "'Helvetica Neue', Helvetica, Arial, sans-serif";
const RING = { cx: 72, cy: 74, r: 50, width: 9, arc: 235.62 } as const;

const COLOR = {
	bg: "#0F0F12",
	track: "#24242A",
	label: "#8E8E93",
	value: "#FFFFFF",
	unit: "#8E8E97",
	neutral: "#A3A3AD",
	good: "#3DDC97",
	warn: "#FFB547",
	bad: "#FF6B5E",
	stale: "#55555C",
} as const;

type Ink = { accent: string; value: string; muted: string };

export function renderKey(view: KeyView): string {
	const ink: Ink = view.stale
		? { accent: COLOR.stale, value: COLOR.stale, muted: COLOR.stale }
		: { accent: COLOR[view.tone], value: COLOR.value, muted: COLOR.unit };
	const body = view.fill === undefined ? etaBody(view, ink) : levelBody(view, view.fill, ink);
	const failed = view.stale && /\d/.test(view.value);

	return (
		`<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}">` +
		`<rect width="${SIZE}" height="${SIZE}" rx="20" fill="${COLOR.bg}" />` +
		body +
		(failed ? `<circle cx="124" cy="20" r="5" fill="${COLOR.bad}" />` : "") +
		`</svg>`
	);
}

export function toDataUri(markup: string): string {
	return `data:image/svg+xml;charset=utf8,${encodeURIComponent(markup)}`;
}

function levelBody(view: KeyView, fill: number, ink: Ink): string {
	const share = Math.min(1, Math.max(0, fill));
	const ring = (color: string, length: number) =>
		`<circle cx="${RING.cx}" cy="${RING.cy}" r="${RING.r}" fill="none" stroke="${color}" stroke-width="${RING.width}" ` +
		`stroke-linecap="round" stroke-dasharray="${length.toFixed(1)} 999" transform="rotate(135 ${RING.cx} ${RING.cy})" />`;
	const word = !/^\d/.test(view.value);

	return (
		ring(COLOR.track, RING.arc) +
		(share > 0 ? ring(ink.accent, RING.arc * share) : "") +
		(view.bolt && !view.stale ? `<path d="M75 30 L66 43 H72 L69 53 L78 39 H72 Z" fill="${ink.accent}" />` : "") +
		(word
			? text(view.value, 80, 17, 700, ink.value, 1)
			: value(view.value, 88, view.value.length > 3 ? 34 : 40, 18, ink, -1)) +
		text(view.foot, 129, 15, 700, ink.accent, 0.3)
	);
}

function etaBody(view: KeyView, ink: Ink): string {
	const word = !/^\d/.test(view.value);
	return (
		text(view.label, 34, 12, 700, view.stale ? COLOR.stale : COLOR.label, 1.8) +
		`<rect x="62" y="44" width="20" height="3" rx="1.5" fill="${ink.accent}" />` +
		(word
			? text(view.value, view.value.length <= 4 ? 96 : 92, view.value.length <= 4 ? 34 : 20, 700, ink.value, 1)
			: value(view.value, 98, 46, 22, ink, -1.5)) +
		text(view.foot, 129, 15, 700, ink.accent, 0.3)
	);
}

function value(content: string, y: number, size: number, unitSize: number, ink: Ink, spacing: number): string {
	const runs = (content.match(/\d+|\D+/g) ?? []).map((run) =>
		/\d/.test(run)
			? `<tspan font-size="${size}" fill="${ink.value}">${escapeXml(run)}</tspan>`
			: `<tspan font-size="${unitSize}" font-weight="600" fill="${ink.muted}" dx="1">${escapeXml(run)}</tspan>`,
	);
	return (
		`<text x="72" y="${y}" text-anchor="middle" font-family="${FONT}" font-weight="700" letter-spacing="${spacing}">` +
		runs.join("") +
		`</text>`
	);
}

function text(content: string, y: number, size: number, weight: number, fill: string, spacing: number): string {
	if (content === "") return "";
	return (
		`<text x="72" y="${y}" text-anchor="middle" font-family="${FONT}" font-size="${size}" ` +
		`font-weight="${weight}" letter-spacing="${spacing}" fill="${fill}">${escapeXml(content)}</text>`
	);
}

function escapeXml(content: string): string {
	return content.replace(/[<>&]/g, (char) => (char === "<" ? "&lt;" : char === ">" ? "&gt;" : "&amp;"));
}
