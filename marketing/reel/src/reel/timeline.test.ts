import assert from "node:assert/strict";
import { test } from "node:test";
import { BEAT, DURATION, SCENES, SCENE_KEYS, holdTable } from "./timeline";

test("every beat holds long enough to read what it shows", () => {
  for (const row of holdTable()) {
    assert.ok(
      row.actual >= row.required,
      `${row.key}: holds ${row.actual} s, needs ${row.required} s for ${row.words} words`,
    );
  }
});

test("scenes sit on the beat grid and the reel stays under 40 s", () => {
  for (const key of SCENE_KEYS) {
    const beats = (SCENES[key][1] - SCENES[key][0]) / BEAT;
    assert.ok(Math.abs(beats - Math.round(beats)) < 0.01, `${key} is off the grid`);
  }
  assert.ok(DURATION < 40, `${DURATION} s`);
});
