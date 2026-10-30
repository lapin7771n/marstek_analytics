# python3 music.py cues.json sfx.wav out.wav — synthesizes the music bed on the beat grid and mixes the effects over it.
# The bed is generated here from sine and noise, so it carries no third-party licence.
# Needs numpy and scipy: uv run --with numpy --with scipy python scripts/music.py ...
import json, sys, wave
import numpy as np
from scipy.signal import butter, lfilter

SR = 48000
spec = json.load(open(sys.argv[1]))
BEAT = spec["beat"]
SC = spec["scenes"]
DUR = spec["duration"]
N = int((DUR + 0.2) * SR)
rng = np.random.default_rng(11)

L = np.zeros(N)
R = np.zeros(N)


def mono_add(t, x, gain=1.0, pan=0.0):
    i = int(t * SR)
    if i >= N or i < 0:
        return
    x = x[: N - i] * gain
    L[i : i + len(x)] += x * (1 - max(0, pan))
    R[i : i + len(x)] += x * (1 + min(0, pan))


def lp(x, hz, order=2):
    b, a = butter(order, hz / (SR / 2), "low")
    return lfilter(b, a, x)


def hp(x, hz, order=2):
    b, a = butter(order, hz / (SR / 2), "high")
    return lfilter(b, a, x)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


NOTE = {"F": 5, "Gb": 6, "G": 7, "Ab": 8, "A": 9, "Bb": 10, "B": 11, "C": 0, "Db": 1, "D": 2, "Eb": 3, "E": 4}


def m(name, octave):
    return 12 * (octave + 1) + NOTE[name]


# chord per scene: bass note, pad notes (midi), brightness (harmonics), pad level
CHORDS = {
    "hook": (m("F", 1), [m("F", 2), m("C", 3), m("Ab", 3)], 2, 0.5),
    "problem": (m("F", 1), [m("F", 2), m("C", 3), m("G", 3)], 2, 0.55),
    "answer": (m("Db", 2), [m("Ab", 2), m("C", 3), m("F", 3), m("Ab", 3)], 5, 0.95),
    "verdict": (m("Eb", 2), [m("Bb", 2), m("G", 3), m("Bb", 3), m("Eb", 4)], 5, 0.85),
    "tension": (m("F", 1), [m("F", 2), m("Ab", 2), m("C", 3), m("E", 3)], 3, 0.7),
    "action": (m("Db", 2), [m("Ab", 2), m("F", 3), m("Ab", 3), m("C", 4)], 5, 0.9),
    "cta": (m("Ab", 1), [m("Eb", 3), m("Ab", 3), m("C", 4), m("Eb", 4), m("Ab", 4)], 6, 1.0),
}


def pad_tone(freq, dur, harmonics):
    t = np.arange(int(dur * SR)) / SR
    out = np.zeros(len(t))
    for detune in (-5.0, 0.0, 5.0):
        f = freq * 2 ** (detune / 1200)
        ph = rng.uniform(0, 2 * np.pi)
        for h in range(1, harmonics + 1):
            out += np.sin(2 * np.pi * f * h * t + ph * h) / h ** 1.4
    return out / 3


for key, (t0, t1) in SC.items():
    bass, notes, harm, level = CHORDS[key]
    release = 0.9
    dur = (t1 - t0) + release + 0.3
    env_t = np.arange(int(dur * SR)) / SR
    env = np.minimum(1, env_t / 0.7) * np.minimum(1, np.maximum(0, (dur - env_t) / (release + 0.3)))
    pad = np.zeros(int(dur * SR))
    for k, n in enumerate(notes):
        pad += pad_tone(midi(n), dur, harm)
    pad = lp(pad, 700 + 900 * harm) * env * 0.045 * level
    mono_add(t0 - 0.2 if t0 > 0 else 0, pad, 1.0, 0.0)
    # stereo width: a second copy delayed by 12 ms, panned
    mono_add((t0 - 0.2 if t0 > 0 else 0) + 0.012, pad * 0.5, 1.0, 0.5)
    # bass: sine an octave under the chord root, enters with the light
    if key not in ("hook", "problem"):
        sub = np.sin(2 * np.pi * midi(bass) * env_t) * env
        mono_add(t0 - 0.05, sub * 0.16 * (0.5 if key == "red" else 1.0), 1.0, 0.0)
    else:
        sub = np.sin(2 * np.pi * midi(bass) * env_t) * env
        mono_add(0.0, sub * 0.07, 1.0, 0.0)


def kick():
    t = np.arange(int(0.34 * SR)) / SR
    f = 42 + 70 * np.exp(-t / 0.035)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t / 0.11) * np.minimum(1, t / 0.002)


def tick_hat():
    x = hp(rng.standard_normal(int(0.07 * SR)), 6500)
    return x * np.exp(-np.arange(len(x)) / SR / 0.012)


def pluck(freq):
    t = np.arange(int(1.1 * SR)) / SR
    mod = np.sin(2 * np.pi * freq * 2 * t) * 1.3 * np.exp(-t / 0.08)
    x = np.sin(2 * np.pi * freq * t + mod) * np.exp(-t / 0.42)
    return x * np.minimum(1, t / 0.003)


KICK = kick()
HAT = tick_hat()

fill0 = SC["answer"][0]
red0, red1 = SC["tension"]
n_beats = int((DUR - fill0) / BEAT)
for b in range(n_beats):
    t = fill0 + b * BEAT
    in_red = red0 <= t < red1
    if t >= SC["cta"][0] + BEAT * 4:
        continue
    if in_red:
        if abs(t - red0) < 1e-6 or abs(t - red0 - 2 * BEAT) < 1e-6:
            mono_add(t, KICK, 0.42)
    elif b % 2 == 0:
        mono_add(t, KICK, 0.55)
    else:
        mono_add(t, KICK, 0.22)

# hats on the off-beat 8ths, silent in the hook and the red scene
for b in range(int(DUR / BEAT * 2)):
    t = b * BEAT / 2
    if t < SC["answer"][0] or red0 <= t < red1 or t >= SC["cta"][0] + BEAT * 3:
        continue
    accent = 1.0 if b % 2 == 1 else 0.0
    if accent:
        mono_add(t, HAT, 0.1, 0.25)

# bell plucks: chord tones on the 8th grid, from the "now" scene
ARP = [0, 2, 1, 3, 2, 1, 3, 2]
for key in ("answer", "verdict", "action", "cta"):
    t0, t1 = SC[key]
    notes = CHORDS[key][1]
    steps = int((t1 - t0) / (BEAT / 2))
    for s in range(steps):
        t = t0 + s * BEAT / 2
        n = notes[ARP[s % len(ARP)] % len(notes)] + 12
        mono_add(t, pluck(midi(n)), 0.05, ((s % 4) - 1.5) * 0.18)

# tension: a quiet rising noise band under the red scene
tdur = red1 - red0 + 0.2
noise = rng.standard_normal(int(tdur * SR))
sweep = hp(lp(noise, 2600), 300) * np.linspace(0, 1, len(noise)) ** 2
mono_add(red0, sweep, 0.05)

# a held, slightly sour high note in the red scene
t = np.arange(int(tdur * SR)) / SR
sour = np.sin(2 * np.pi * midi(m("E", 5)) * t) * np.minimum(1, t / 0.5) * np.minimum(1, (tdur - t) / 0.4)
mono_add(red0, sour, 0.012, 0.3)

music = np.stack([L, R], axis=1)
peak = np.max(np.abs(music))
music = music / peak * 0.62

sfx_wav = wave.open(sys.argv[2], "rb")
frames = np.frombuffer(sfx_wav.readframes(sfx_wav.getnframes()), dtype="<i2").astype(np.float64) / 32768
sfx = frames.reshape(-1, 2)
sfx_wav.close()
mix = music.copy()
n = min(len(mix), len(sfx))
mix[:n] += sfx[:n] * 0.62

# end: fade the bed over the last 0.9 s
fade = np.ones(len(mix))
tail = int(0.9 * SR)
end = int(DUR * SR)
fade[end - tail : end] = np.linspace(1, 0, tail) ** 1.5
fade[end:] = 0
mix = mix * fade[:, None]
mix = np.tanh(mix * 1.15) / np.tanh(1.15) * 0.9
mix = mix[:end]
with wave.open(sys.argv[3], "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((mix * 32767).astype("<i2").tobytes())
print("peak", float(np.max(np.abs(mix))))
