import { expect, test } from "vitest";

import { formatDuration, Stabiliser } from "./format";

test.each([
	[30, ">24h"],
	[12.4, "12h"],
	[3.66, "3h40"],
	[1, "1h00"],
	[0.74, "45m"],
	[0.1, "6m"],
	[0, "0m"],
])("formats %f h as %s", (hours, text) => {
	expect(formatDuration(hours)).toBe(text);
});

test("the stabiliser holds a value until it moves most of a display step", () => {
	const stable = new Stabiliser();
	expect(stable.next(3.0)).toBe(3.0);
	expect(stable.next(3.05)).toBe(3.0);
	expect(stable.next(2.95)).toBe(3.0);
	expect(stable.next(2.8)).toBe(2.8);
});

test("the stabiliser forgets when there is no estimate", () => {
	const stable = new Stabiliser();
	stable.next(3.0);
	expect(stable.next(null)).toBeNull();
	expect(stable.next(5.0)).toBe(5.0);
});
