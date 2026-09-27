"""Synthesise the mokugyo (wooden fish) strike sound.

Run with:
  blender --background --factory-startup --python tools/build_audio.py

Produces a few round-robin variations of a short, hollow, wooden "tok":
a bright inharmonic attack that collapses quickly into a hollow body tone,
which is what a struck mokugyo sounds like.
"""

import math
import os
import struct
import wave

import numpy as np

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(PROJECT, "assets", "audio")

SR = 44100
DUR = 0.55

# (frequency ratio, amplitude, decay tau, phase)
PARTIALS = [
    (1.00, 1.00, 0.052, 0.00),
    (1.59, 0.60, 0.042, 0.70),
    (2.31, 0.38, 0.033, 1.90),
    (3.16, 0.24, 0.026, 0.40),
    (4.07, 0.15, 0.020, 2.60),
    (5.14, 0.09, 0.016, 1.20),
    (6.42, 0.05, 0.012, 3.00),
]


def one_tok(rng, f0):
    n = int(SR * DUR)
    t = np.arange(n) / SR

    # Wooden block: the pitch bends down slightly as the strike settles.
    bend = 1.0 + 0.055 * np.exp(-t / 0.007)
    phase = 2.0 * math.pi * f0 * np.cumsum(bend) / SR

    tone = np.zeros(n)
    for ratio, amp, tau, phi in PARTIALS:
        tone += amp * np.exp(-t / tau) * np.sin(ratio * phase + phi)

    # hollow body resonance
    tone += 0.28 * np.exp(-t / 0.030) * np.sin(2.0 * math.pi * 188.0 * t + 0.9)

    # attack: filtered noise click
    noise = rng.normal(0.0, 1.0, n)
    noise = np.diff(np.concatenate([[0.0], noise]))  # crude high pass
    click = noise * np.exp(-t / 0.0018)
    click *= 0.9 / (np.max(np.abs(click)) + 1e-9)

    # second, softer scrape a couple of ms later
    t2 = np.clip(t - 0.0035, 0.0, None)
    scrape = rng.normal(0.0, 1.0, n) * np.exp(-t2 / 0.006) * (t > 0.0035)
    scrape *= 0.25 / (np.max(np.abs(scrape)) + 1e-9)

    sig = 0.95 * tone / (np.max(np.abs(tone)) + 1e-9) + 0.45 * click + 0.20 * scrape

    # gentle low-pass to take the fizz off the synthetic click
    alpha = 0.55
    out = np.empty_like(sig)
    acc = 0.0
    for i in range(n):
        acc += alpha * (sig[i] - acc)
        out[i] = acc
    sig = 0.45 * sig + 0.75 * out

    # soft clip, then tidy the ends
    sig = np.tanh(sig * 1.25)
    sig /= np.max(np.abs(sig)) + 1e-9
    sig *= 0.92

    ramp = int(SR * 0.0012)
    sig[:ramp] *= np.linspace(0.0, 1.0, ramp)
    tail = int(SR * 0.05)
    sig[-tail:] *= np.linspace(1.0, 0.0, tail) ** 2
    return sig


def write_wav(path, samples):
    data = np.clip(samples, -1.0, 1.0)
    pcm = (data * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    rng = np.random.default_rng(20240926)
    bases = [520.0, 548.0, 497.0, 566.0]
    for i, f0 in enumerate(bases):
        sig = one_tok(rng, f0)
        path = os.path.join(OUT_DIR, "mokugyo_%02d.wav" % (i + 1))
        write_wav(path, sig)
        print("WROTE", path, "peak", round(float(np.max(np.abs(sig))), 3))


main()
