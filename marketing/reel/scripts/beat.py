# python3 beat.py track.mp3            tempo, the time of every beat, and the level per bar: the values for MUSIC in a story's timeline.ts
# python3 beat.py out.mp4 --check BPM  how far the strongest hit near each beat of a rendered file sits from the beat grid
# Beats are placed on the sharp broadband attack. The low-band envelope swells ~50 ms after the hit; cues timed to it sound late.
import subprocess, sys
import numpy as np

SR = 44100


def decode(path, seconds=None):
    cmd = ["ffmpeg", "-v", "error", "-i", path] + (["-t", str(seconds)] if seconds else []) + ["-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    return np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, dtype=np.float32).astype(np.float64)


def attack(x):  # rise of the broadband envelope, sample-accurate
    env = np.sqrt(np.convolve(x**2, np.ones(128) / 128, "same"))
    return np.maximum(0, np.diff(env, prepend=env[0]))


def phase(d, per, t0, t1):  # where in the beat period the attacks concentrate, and how strongly
    t = np.arange(len(d)) / SR
    m = (t >= t0) & (t < t1)
    z = (d[m] * np.exp(2j * np.pi * ((t[m] % per) / per))).sum()
    return (np.angle(z) % (2 * np.pi)) / (2 * np.pi) * per, abs(z) / d[m].sum()


if "--check" in sys.argv:
    per = 60 / float(sys.argv[sys.argv.index("--check") + 1])
    x = decode(sys.argv[1]); d = attack(x)
    off = []
    for k in range(1, int(len(x) / SR / per) - 1):
        i0, i1 = int((k * per - 0.1) * SR), int((k * per + 0.1) * SR)
        off.append((i0 + np.argmax(d[i0:i1])) / SR - k * per)
    off = np.array(off) * 1000
    print(f"strongest hit vs beat grid: median {np.median(off):+.1f} ms, within 5 ms on {(abs(off) < 5).sum()} of {len(off)} beats")
    sys.exit()

x = decode(sys.argv[1], 120); d = attack(x)
coarse = d[::32]  # tempo search on a decimated copy
tc = np.arange(len(coarse)) * 32 / SR
best = max(((abs((coarse * np.exp(2j * np.pi * ((tc % (60 / b)) / (60 / b)))).sum()), b) for b in np.arange(70, 180.001, 0.02)))[1]
bpm = round(best) if abs(best - round(best)) < 0.2 else round(best, 2)  # produced tracks sit on whole tempos
per = 60 / bpm
print(f"tempo: {bpm} bpm (raw estimate {best:.2f})")
for t0 in range(0, int(len(x) / SR) - 14, 15):
    ph, strength = phase(d, per, t0, t0 + 15)
    print(f"  {t0:3d}-{t0 + 15:3d} s: beat phase {ph:.3f} s, strength {strength:.2f}")  # phase must hold steady; drift means the tempo is off
ph, _ = phase(d, per, 15, min(90, len(x) / SR))  # coarse: the envelope's centre of mass, which trails the hit
hits = []
for k in range(int(15 / per), int(min(90, len(x) / SR - 1) / per)):  # refine: the steepest rise near each coarse beat
    i0, i1 = int((ph + k * per - 0.1) * SR), int((ph + k * per + 0.1) * SR)
    hits.append((i0 + np.argmax(d[i0:i1])) / SR - k * per)
print(f"attack sits {1000 * (ph - np.median(hits)):.0f} ms before the envelope phase (spread {1000 * np.std(hits):.1f} ms)")
ph = float(np.median(hits))
env = np.sqrt(np.convolve(x**2, np.ones(2048) / 2048, "same"))
level = [20 * np.log10(env[max(0, int((ph + k * per) * SR)):int((ph + (k + 1) * per) * SR)].mean() + 1e-9) for k in range(int((len(x) / SR - 1) / per))]
print("level per 4 beats, to pick where the full beat enters (start the video on that beat):")
for k in range(0, min(96, len(level) - 4), 4):
    print(f"  beat {k:3d} at {ph + k * per:7.3f} s: {np.mean(level[k:k + 4]):6.1f} dB")
print(f"beat k starts at {ph:.3f} + k * {per:.5f} s")
