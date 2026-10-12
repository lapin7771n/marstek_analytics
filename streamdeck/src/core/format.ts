export function formatDuration(hours: number): string {
	const minutes = hours * 60;
	if (minutes >= 24 * 60) return ">24h";
	if (minutes >= 600) return `${Math.round(minutes / 60)}h`;
	if (minutes >= 60) {
		const rounded = Math.round(minutes / 10) * 10;
		return `${Math.floor(rounded / 60)}h${String(rounded % 60).padStart(2, "0")}`;
	}
	if (minutes >= 10) return `${Math.round(minutes / 5) * 5}m`;
	return `${Math.max(0, Math.round(minutes))}m`;
}

export class Stabiliser {
	#shown: number | null = null;

	next(hours: number | null): number | null {
		if (hours === null || hours === 0 || this.#shown === null || Math.abs(hours - this.#shown) >= 0.75 * stepHours(hours)) {
			this.#shown = hours;
		}
		return this.#shown;
	}
}

function stepHours(hours: number): number {
	const minutes = hours * 60;
	return (minutes >= 600 ? 60 : minutes >= 60 ? 10 : minutes >= 10 ? 5 : 1) / 60;
}
