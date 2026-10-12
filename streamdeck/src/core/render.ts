import type { KeyView } from "./views";

const SIZE = 144;
const FONT = "'Helvetica Neue', Helvetica, Arial, sans-serif";

const COLOR = {
	bg: "#17171A",
	track: "#2A2A30",
	label: "#8A8A93",
	value: "#FFFFFF",
	neutral: "#8A8A93",
	good: "#4ADE80",
	warn: "#FBBF24",
	bad: "#F87171",
	stale: "#5A5A61",
} as const;

export function renderKey(view: KeyView): string {
	const ink = view.stale ? COLOR.stale : COLOR.value;
	const accent = view.stale ? COLOR.stale : COLOR[view.tone];
	const size = view.value.length <= 3 ? 52 : view.value.length === 4 ? 42 : view.value.length === 5 ? 36 : 26;

	const bar =
		view.fill === undefined
			? ""
			: `<rect x="20" y="130" width="104" height="6" rx="3" fill="${COLOR.track}" />` +
				`<rect x="20" y="130" width="${(104 * Math.min(1, Math.max(0, view.fill))).toFixed(1)}" height="6" rx="3" fill="${accent}" />`;

	return (
		`<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}">` +
		`<rect width="${SIZE}" height="${SIZE}" rx="18" fill="${COLOR.bg}" />` +
		text(view.label, 32, 13, 600, view.stale ? COLOR.stale : COLOR.label, 1.6) +
		text(view.value, 84, size, 700, ink, 0) +
		text(view.foot, 116, 20, 600, accent, 0) +
		bar +
		(view.stale ? `<circle cx="126" cy="20" r="5" fill="${COLOR.bad}" />` : "") +
		`</svg>`
	);
}

export function toDataUri(markup: string): string {
	return `data:image/svg+xml;charset=utf8,${encodeURIComponent(markup)}`;
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
