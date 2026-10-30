# python3 sound.py cues.json out.wav — synthesizes the sound effects from a cue file.
# cues.json: { "fps", "duration", "track": { "start", "fadeOut" }, "cues": [{ "t", "sound", "gain", "pan", "dur" }] }
# sound is tick, beep, whoosh, rise or chime; t is in video seconds; dur (optional) is the length of a whoosh or rise.
# The WAV holds the effects only. Music is mixed by the renderer.
import json, sys, wave
import numpy as np

SR = 48000
spec = json.load(open(sys.argv[1]))
n = int(spec["duration"] * SR) + SR // 2
mix = np.zeros((n, 2))
rng = np.random.default_rng(7)


def add(at, mono, gain=1.0, pan=0.0):
    i = int(at * SR)
    if i < 0 or i >= n:
        return
    mono = mono[: n - i] * gain
    mix[i : i + len(mono), 0] += mono * (1 - max(0, pan))
    mix[i : i + len(mono), 1] += mono * (1 + min(0, pan))


def lowpass(x, hz):
    a = np.exp(-2 * np.pi * hz / SR)
    y = np.empty_like(x)
    acc = 0.0
    for k, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[k] = acc
    return y


def tick():  # the kit's impact: a felt mallet on a wooden bar, tuned to E like the chime, no high crack
    t = np.arange(int(0.45 * SR)) / SR
    out = np.zeros(len(t))
    for hz, amp, tau in ((164.81, 0.75, 0.07), (329.63, 0.8, 0.16), (1318.5, 0.18, 0.035), (2965.0, 0.05, 0.012)):
        out += amp * np.sin(2 * np.pi * hz * t) * np.exp(-t / tau)
    felt = lowpass(rng.standard_normal(len(t)) * np.exp(-t / 0.004), 1800)
    return 0.62 * (np.minimum(1, t / 0.002) * out + 0.6 * felt)


def beep():  # shot-timer start signal
    t = np.arange(int(0.22 * SR)) / SR
    env = np.minimum(1, t / 0.004) * np.minimum(1, (t[-1] - t) / 0.02)
    return (np.sin(2 * np.pi * 2300 * t) + 0.3 * np.sin(2 * np.pi * 4600 * t)) * env


def whoosh(dur, rising=False):
    t = np.arange(int(dur * SR)) / SR
    noise = rng.standard_normal(len(t))
    noise = lowpass(noise, 2600) - lowpass(noise, 350)
    p = t / dur
    env = np.sin(np.pi * p) ** 2 * (p if rising else 1)
    return noise * env


def chime():
    t = np.arange(int(1.4 * SR)) / SR
    out = np.zeros(len(t))
    for k, hz in enumerate((659.25, 987.77)):
        d = int(k * 0.11 * SR)
        tt = t[: len(t) - d]
        out[d:] += (np.sin(2 * np.pi * hz * tt) + 0.25 * np.sin(2 * np.pi * 2 * hz * tt)) * np.exp(-tt / 0.38) * np.minimum(1, tt / 0.005)
    return out


TICK = tick()
for cue in spec["cues"]:
    kind = cue["sound"]
    if kind == "tick":
        mono = TICK
    elif kind == "beep":
        mono = beep()
    elif kind == "whoosh":
        mono = whoosh(cue.get("dur", 0.4))
    elif kind == "rise":
        mono = whoosh(cue.get("dur", 0.3), rising=True)
    elif kind == "chime":
        mono = chime()
    else:
        sys.exit(f"unknown sound: {kind}")
    add(cue["t"], mono, cue.get("gain", 1.0), cue.get("pan", 0.0))

mix = np.tanh(mix * 1.1) * 0.95  # fixed gain: two parts of one piece must play at the same level
with wave.open(sys.argv[2], "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((mix * 32767).astype("<i2").tobytes())
