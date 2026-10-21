#!/usr/bin/env python3
"""Offline sound synthesis for Sandblood. Writes 16-bit 44.1 kHz mono WAV files into assets/audio/<category>/.

Needs numpy. Usage: tools/gen_sfx.py [category/name_prefix ...]   (no args = every sound)
Deterministic: every sound seeds its own RNG from its name and variant index.
Also writes assets/audio/manifest.json (category -> name -> variant count) and checks every file
(format, peak, RMS, DC, clipping, edge clicks, length). Prints failures and one summary line.
"""
import json
import os
import sys
import wave
import zlib

import numpy as np

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
PEAK = 0.89  # -1 dBFS


# ---------------------------------------------------------------- helpers
def ns(dur):
    return int(round(dur * SR))


def tt(dur):
    return np.arange(ns(dur)) / SR


def silence(dur):
    return np.zeros(ns(dur))


def expd(t, t60):
    """Exponential decay reaching -60 dB at t60 seconds."""
    return np.exp(-6.9078 * t / t60)


def place(dst, src, at, gain=1.0):
    i = int(at * SR)
    if i >= len(dst) or i < 0:
        return
    n = min(len(src), len(dst) - i)
    dst[i:i + n] += src[:n] * gain


def fft_shape(x, fn):
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    return np.fft.irfft(X * fn(f), n)


def bandpass(x, lo, hi, order=2):
    def fn(f):
        h = 1.0 / np.sqrt(1.0 + (np.maximum(lo, 1e-3) / np.maximum(f, 1e-3)) ** (2 * order))
        return h / np.sqrt(1.0 + (f / hi) ** (2 * order))
    return fft_shape(x, fn)


def lowpass(x, fc, order=2):
    return fft_shape(x, lambda f: 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order)))


def highpass(x, fc, order=2):
    return fft_shape(x, lambda f: 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-3)) ** (2 * order)))


def stft_filter(x, resp):
    """Time-varying spectral filter. resp(times_s, freqs_hz) -> (frames, bins) gain matrix."""
    N, H = 2048, 512
    pad = np.concatenate([np.zeros(N), x, np.zeros(N)])
    win = np.hanning(N + 1)[:N]
    nfr = (len(pad) - N) // H + 1
    idx = np.arange(N)[None, :] + H * np.arange(nfr)[:, None]
    frames = pad[idx] * win[None, :]
    X = np.fft.rfft(frames, axis=1)
    f = np.fft.rfftfreq(N, 1.0 / SR)
    times = (H * np.arange(nfr) + N / 2 - N) / SR
    X *= resp(times, f)
    y = np.fft.irfft(X, N, axis=1)
    out = np.zeros(len(pad))
    for i in range(nfr):
        out[H * i:H * i + N] += y[i]
    out /= 2.0  # hann at 75 % overlap sums to 2
    return out[N:N + len(x)]


def lorentz(f, fc, bw):
    return 1.0 / (1.0 + ((f - fc) / (bw * 0.5)) ** 2)


def noise(rng, dur):
    return rng.standard_normal(ns(dur))


def smooth_noise(rng, dur, rate_hz):
    """Slowly varying noise in about -1..1 (control curve)."""
    n = ns(dur)
    k = max(2, int(dur * rate_hz) + 2)
    pts = rng.standard_normal(k)
    return np.interp(np.linspace(0, k - 1, n), np.arange(k), pts) / 1.5


def env_ad(t, att, dec):
    return (1 - np.exp(-t / max(att, 1e-5))) * np.exp(-t / max(dec, 1e-5))


def modal(rng, freqs, t60s, amps, dur, detune=0.0015, shimmer=True):
    """Sum of decaying sinusoids; each partial optionally doubled with a slight detune (beating shimmer)."""
    t = tt(dur)
    y = np.zeros_like(t)
    for f, d, a in zip(freqs, t60s, amps):
        if f * 2.2 > SR:
            continue
        env = expd(t, d)
        ph = rng.uniform(0, 2 * np.pi)
        if shimmer:
            f2 = f * (1.0 + rng.uniform(0.3, 1.0) * detune * rng.choice([-1, 1]) * 4)
            y += a * env * (0.6 * np.sin(2 * np.pi * f * t + ph) + 0.4 * np.sin(2 * np.pi * f2 * t + ph * 1.7))
        else:
            y += a * env * np.sin(2 * np.pi * f * t + ph)
    return y


BAR_RATIOS = np.array([1.0, 2.756, 5.404, 8.933, 13.34, 18.64, 24.81])  # free bar
PLATE_RATIOS = np.array([1.0, 1.59, 2.14, 2.30, 2.65, 2.92, 3.50, 4.06, 4.64, 5.43, 6.35])  # rough plate


def steel_partials(rng, f0, ring, n_extra=16, plate=False):
    """Frequencies, t60s, amps for a struck steel object. ring = t60 of the fundamental (s)."""
    base = PLATE_RATIOS if plate else BAR_RATIOS
    ratios = list(base * rng.uniform(0.985, 1.015, len(base)))
    freqs = [f0 * r for r in ratios]
    amps = [1.0 / (1 + 0.35 * i) for i in range(len(freqs))]
    t60 = [ring * (f0 / f) ** 0.55 for f in freqs]  # damping rises with frequency
    for _ in range(n_extra):  # metallic sheen: dense short high partials
        freqs.append(rng.uniform(2200, 9500))
        t60.append(ring * rng.uniform(0.04, 0.2))
        amps.append(rng.uniform(0.05, 0.22))
    return freqs, t60, amps


def click(rng, dur=0.004, lo=1500, hi=9000, decay=0.0012):
    t = tt(dur)
    return bandpass(noise(rng, dur), lo, hi, 1) * np.exp(-t / decay)


def thump(rng, f0=80, f1=45, dur=0.25, t60=0.14):
    t = tt(dur)
    f = f1 + (f0 - f1) * np.exp(-t / 0.03)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * expd(t, t60) * (1 - np.exp(-t / 0.002))


def bubble(rng, f0, dur=0.03, rise=0.7):
    t = tt(dur)
    f = f0 * (1 + rise * t / dur)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / (dur * 0.35)) * (1 - np.exp(-t / 0.001))


def bubbles(rng, dur, count, flo=300, fhi=1400, dens_decay=None):
    y = silence(dur)
    for _ in range(int(count)):
        at = rng.exponential(dens_decay) if dens_decay else rng.uniform(0, dur * 0.9)
        if at > dur * 0.95:
            continue
        b = bubble(rng, rng.uniform(flo, fhi), rng.uniform(0.012, 0.04), rng.uniform(0.3, 1.2))
        place(y, b, at, rng.uniform(0.2, 1.0))
    return y


def grains(rng, dur, count, lo=1200, hi=6000, decay_t=None, glen=(0.001, 0.006)):
    """Granular texture: tiny filtered noise grains scattered in time (exponential density when decay_t)."""
    y = silence(dur)
    for _ in range(int(count)):
        at = rng.exponential(decay_t) if decay_t else rng.uniform(0, dur)
        if at > dur - 0.01:
            continue
        gl = rng.uniform(*glen)
        g = bandpass(noise(rng, gl + 0.002), rng.uniform(lo, hi * 0.5), rng.uniform(hi * 0.5, hi), 1)
        g *= np.hanning(len(g))
        place(y, g, at, rng.uniform(0.3, 1.0))
    return y


def fade(x, a=0.001, b=0.006):
    n = len(x)
    ia, ib = min(int(a * SR), n // 2), min(int(b * SR), n // 2)
    x = x.copy()
    if ia:
        x[:ia] *= np.linspace(0, 1, ia)
    if ib:
        x[-ib:] *= np.linspace(1, 0, ib)
    return x


def soft(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def fit(x, dur):
    """Pad or crop x to exactly dur seconds."""
    n = ns(dur)
    return np.pad(x, (0, max(0, n - len(x))))[:n]


# ---------------------------------------------------------------- voices (formant synthesis)
VOWELS = {  # F1, F2, F3 (male-ish)
    "a": (800, 1200, 2500), "o": (500, 900, 2400), "u": (320, 800, 2400), "e": (500, 1800, 2500),
    "ae": (700, 1650, 2500), "uh": (640, 1190, 2390), "i": (300, 2300, 3000), "aw": (600, 1000, 2400),
}


def glottal(phase):
    """Radiated glottal pulse (derivative of a Rosenberg pulse) from phase in cycles."""
    p = phase % 1.0
    g = np.where(p < 0.55, 0.5 * (1 - np.cos(np.pi * p / 0.55)),
                 np.where(p < 0.75, np.cos(0.5 * np.pi * (p - 0.55) / 0.2), 0.0))
    return np.diff(g, prepend=g[0]) * 60.0


def f0_curve(rng, dur, f0a, f0b, vib=(5.0, 0.012), wobble=0.01, shape=1.0):
    t = tt(dur)
    f = f0a + (f0b - f0a) * (t / dur) ** shape
    f = f * (1 + vib[1] * np.sin(2 * np.pi * vib[0] * t + rng.uniform(0, 6.28)))
    return f * (1 + wobble * smooth_noise(rng, dur, 9))


def voice_src(rng, f0, breath=0.05, jitter=0.004, rough=0.0):
    n = len(f0)
    f = f0 * (1 + jitter * smooth_noise(rng, n / SR, 80))
    ph = np.cumsum(f) / SR
    s = glottal(ph)
    if rough > 0:  # sub-harmonic amplitude modulation gives a growl
        s = s * (1 + rough * np.sin(2 * np.pi * np.cumsum(f * 0.5) / SR))
    return s + breath * np.std(s) * rng.standard_normal(n)


def formant_filter(x, va, vb=None, bw=(90, 110, 160), amps=(1.0, 0.7, 0.35)):
    va = np.array(va, float)
    vb = va if vb is None else np.array(vb, float)
    n = len(x)

    def resp(times, f):
        u = np.clip(times / (n / SR), 0, 1)[:, None]
        r = np.zeros((len(times), len(f)))
        for k in range(3):
            r += amps[k] * lorentz(f[None, :], va[k] + (vb[k] - va[k]) * u, bw[k])
        return r + 0.02
    return stft_filter(x, resp)


def vox(rng, dur, f0a, f0b, vowel_a, vowel_b=None, env=None, breath=0.05, rough=0.0, vib=(5.0, 0.012), shape=1.0,
        drive=1.0):
    f0 = f0_curve(rng, dur, f0a, f0b, vib=vib, shape=shape)
    s = voice_src(rng, f0, breath, rough=rough)
    y = formant_filter(s, VOWELS[vowel_a], VOWELS[vowel_b] if vowel_b else None)
    if drive != 1.0:
        y = soft(y / (np.max(np.abs(y)) + 1e-9), drive)
    t = tt(dur)
    if env is None:
        env = np.minimum(1, t / 0.02) * np.minimum(1, (dur - t) / 0.06)
    return y * env


# ---------------------------------------------------------------- crowd building blocks
def crowd_voices(rng, dur, n, f0_range, vowels, onset=(0.0, 0.3), length=None, glide=(-0.05, 0.05), vib_depth=0.015,
                 group_breath=0.15):
    """Sum n detuned voices (random onset, length, pitch, glide), grouped by vowel and formant-filtered per group."""
    total = ns(dur)
    groups = {v: np.zeros(total) for v in vowels}
    names = list(vowels)
    for i in range(n):
        v = names[i % len(names)]
        st = rng.uniform(*onset)
        ln = rng.uniform(*(length or (dur * 0.5, dur * 0.95)))
        ln = min(ln, dur - st)
        if ln < 0.05:
            continue
        m = int(ln * SR)
        t = np.arange(m) / SR
        f0 = rng.uniform(*f0_range) * np.exp(rng.uniform(*glide) * t / ln)
        f0 = f0 * (1 + vib_depth * np.sin(2 * np.pi * rng.uniform(4.5, 6.5) * t + rng.uniform(0, 6.28)))
        f0 = f0 * (1 + 0.012 * np.interp(np.linspace(0, 5, m), np.arange(6), rng.standard_normal(6)))
        s = glottal(np.cumsum(f0) / SR + rng.uniform())
        e = np.minimum(1, t / 0.06) * np.minimum(1, (ln - t) / 0.1)
        place(groups[v], s * e, st, rng.uniform(0.3, 1.0))
    out = np.zeros(total)
    for v, g in groups.items():
        g = g + group_breath * np.std(g) * rng.standard_normal(total)
        sc = rng.uniform(0.92, 1.12)
        out += formant_filter(g, [x * sc for x in VOWELS[v]], None, bw=(130, 160, 220))
    return out


def claps(rng, dur, count, env, lo=900, hi=4500):
    """Hand claps: short bandpassed noise bursts, density follows env."""
    y = silence(dur)
    prob = np.maximum(env, 0) + 1e-6
    prob = prob / prob.sum()
    times = rng.choice(len(prob), size=int(count), p=prob) / SR
    for at in times:
        g = bandpass(noise(rng, 0.03), rng.uniform(lo, lo * 1.6), rng.uniform(hi * 0.6, hi), 1)
        g = g * np.exp(-tt(0.03) / rng.uniform(0.004, 0.009))
        place(y, g, at, rng.uniform(0.3, 1.0))
    return y


def murmur(rng, dur, lo=180, hi=3200):
    n = bandpass(noise(rng, dur), lo, hi, 2)
    return n * (0.6 + 0.4 * np.clip(smooth_noise(rng, dur, 6), -1, 1))


def unit(x):
    return x / (np.std(x) + 1e-9)


# ---------------------------------------------------------------- sound definitions
SOUNDS = {}   # (category, name) -> (variants, fn, level)


def reg(cat, name, variants, level=1.0):
    def deco(fn):
        SOUNDS[(cat, name)] = (variants, fn, level)
        return fn
    return deco


# ---- impact
@reg("impact", "clang_steel", 5)
def clang_steel(rng, i):
    f0 = rng.uniform(650, 1500)
    fr, d, a = steel_partials(rng, f0, rng.uniform(0.35, 0.7))
    y = modal(rng, fr, d, a, 1.2)
    c = click(rng, 0.006, 2500, 12000, 0.0015) * 1.4
    y[:len(c)] += c
    t = tt(1.2)
    return y + bandpass(noise(rng, 1.2), 1500, 6000, 1) * np.exp(-t / 0.04) * 0.25


@reg("impact", "ring_steel", 3)
def ring_steel(rng, i):
    """Sword ring: long ringing bar, strong fundamental plus a sparkling top."""
    f0 = rng.uniform(520, 980)
    fr, d, a = steel_partials(rng, f0, rng.uniform(1.6, 2.4))
    y = modal(rng, fr, d, a, 2.8, detune=0.0022)
    c = click(rng, 0.005, 2000, 10000, 0.0015)
    y[:len(c)] += c
    return y


@reg("impact", "thunk_wood", 4)
def thunk_wood(rng, i):
    """Anything on wood or shield boards: dull knock with a short bark."""
    f0 = rng.uniform(140, 260)
    y = modal(rng, [f0, f0 * 2.1, f0 * 3.4, f0 * 5.2, rng.uniform(700, 1100)], [0.14, 0.09, 0.06, 0.04, 0.05],
              [1.0, 0.7, 0.5, 0.35, 0.3], 0.5, shimmer=False)
    c = lowpass(click(rng, 0.02, 600, 5000, 0.005), 4000) * 1.2
    y[:len(c)] += c
    return y + thump(rng, 120, 70, 0.5, 0.1) * 0.8


@reg("impact", "bat_crack", 4)
def bat_crack(rng, i):
    """Wooden bat or club on body or wood: sharp crack over a thud."""
    t = tt(0.5)
    crack = bandpass(noise(rng, 0.5), 1200, 5500, 2) * np.exp(-t / 0.012) * 1.6
    ring = modal(rng, [rng.uniform(550, 800), rng.uniform(1400, 1900), rng.uniform(2600, 3300)], [0.07, 0.04, 0.025],
                 [0.6, 0.35, 0.2], 0.5, shimmer=False)
    return crack + ring + thump(rng, 110, 55, 0.5, 0.16) * 1.1


@reg("impact", "bat_tink", 4)
def bat_tink(rng, i):
    """Aluminium bat: bright thin tink with a short hollow shell ring (2-5 kHz)."""
    f0 = rng.uniform(1900, 2900)
    y = modal(rng, [f0, f0 * 1.62, f0 * 2.35, f0 * 3.2, f0 * 0.52], [0.35, 0.22, 0.14, 0.08, 0.12],
              [1.0, 0.55, 0.4, 0.25, 0.5], 0.7, detune=0.002)
    c = click(rng, 0.004, 3500, 14000, 0.001) * 1.2
    y[:len(c)] += c
    return y + thump(rng, 150, 90, 0.7, 0.05) * 0.35


@reg("impact", "body_thud", 5)
def body_thud(rng, i):
    t = tt(0.6)
    skin = bandpass(noise(rng, 0.6), 700, 2800, 2) * np.exp(-t / 0.012) * 0.9
    flesh = lowpass(noise(rng, 0.6), rng.uniform(250, 420), 2) * env_ad(t, 0.003, 0.07) * 4
    return thump(rng, 95, 48, 0.6, 0.18) * 1.5 + skin + flesh


@reg("impact", "fist_punch", 4)
def fist_punch(rng, i):
    t = tt(0.4)
    slap = bandpass(noise(rng, 0.4), 500, 3200, 2) * np.exp(-t / 0.018) * 1.2
    return thump(rng, 120, 60, 0.4, 0.1) * 1.3 + slap + lowpass(noise(rng, 0.4), 300) * env_ad(t, 0.002, 0.04) * 3


@reg("impact", "flesh_cut", 5)
def flesh_cut(rng, i):
    """Blade through flesh: a quick swish of mid noise, wet bubbling, a soft low body."""
    dur = 0.55
    t = tt(dur)
    slice_ = stft_filter(noise(rng, dur), lambda tm, f: lorentz(f[None, :], (2800 - 1800 * np.clip(tm / 0.12, 0, 1))[:, None], 1800))
    slice_ = slice_ * env_ad(t, 0.004, 0.05)
    wet = bubbles(rng, dur, rng.integers(10, 20), 250, 1300, dens_decay=0.12) * 0.7
    wetnoise = bandpass(noise(rng, dur), 900, 3500, 1) * env_ad(t, 0.01, 0.1) * 0.25
    return slice_ + wet + wetnoise + thump(rng, 100, 55, dur, 0.1) * 0.5


@reg("impact", "flesh_pierce", 4)
def flesh_pierce(rng, i):
    dur = 0.5
    t = tt(dur)
    stab = bandpass(noise(rng, dur), 400, 2500, 2) * np.exp(-t / 0.03)
    wet = bubbles(rng, dur, rng.integers(5, 10), 200, 900, dens_decay=0.09) * 0.7
    return stab + wet + thump(rng, 140, 60, dur, 0.09) * 1.2


@reg("impact", "bone_crack", 4)
def bone_crack(rng, i):
    dur = 0.6
    y = silence(dur)
    at = 0.0
    for k in range(rng.integers(4, 9)):
        c = click(rng, 0.012, rng.uniform(900, 2500), rng.uniform(4000, 9000), rng.uniform(0.0015, 0.004))
        place(y, c, at, 1.6 if k == 0 else rng.uniform(0.3, 1.0))
        at += rng.exponential(0.008) + 0.002
    ring = modal(rng, [rng.uniform(350, 500), rng.uniform(900, 1300), rng.uniform(1800, 2600)], [0.07, 0.045, 0.03],
                 [0.8, 0.5, 0.3], dur, shimmer=False)
    return y + ring + thump(rng, 100, 50, dur, 0.15) + bubbles(rng, dur, 3, 300, 800, 0.08) * 0.15


@reg("impact", "armor_clank", 4)
def armor_clank(rng, i):
    """Iron plate hit: lower, duller and rattlier than a sword clang."""
    f0 = rng.uniform(280, 520)
    fr, d, a = steel_partials(rng, f0, rng.uniform(0.12, 0.25), n_extra=24, plate=True)
    y = modal(rng, fr, d, a, 0.6, detune=0.003)
    t = tt(0.6)
    y += bandpass(noise(rng, 0.6), 800, 5000, 1) * np.exp(-t / 0.03) * 0.5
    return y + thump(rng, 130, 70, 0.6, 0.06) * 0.6


@reg("impact", "mail_jingle", 4)
def mail_jingle(rng, i):
    dur = 0.7
    y = silence(dur)
    for _ in range(rng.integers(90, 170)):
        at = rng.exponential(0.12)
        if at > dur - 0.05:
            continue
        f = rng.uniform(2200, 9000)
        g = modal(rng, [f, f * rng.uniform(1.4, 2.2)], [rng.uniform(0.01, 0.04)] * 2, [1.0, 0.4], 0.08, shimmer=False)
        place(y, g, at, rng.uniform(0.2, 1.0) * np.exp(-at / 0.2))
    return y + thump(rng, 160, 90, dur, 0.04) * 0.25


@reg("impact", "leather_slap", 4)
def leather_slap(rng, i):
    t = tt(0.35)
    n = bandpass(noise(rng, 0.35), 400, 2500, 2) * np.exp(-t / 0.02)
    creak = bandpass(noise(rng, 0.35), 150, 700, 1) * env_ad(t, 0.01, 0.07) * 1.2
    return n + creak + thump(rng, 110, 60, 0.35, 0.07) * 0.9


@reg("impact", "helm_knock", 3)
def helm_knock(rng, i):
    """Helmet knocked off: a loud iron clang, then bouncing, rolling tumble."""
    dur = 1.9
    y = silence(dur)
    f0 = rng.uniform(380, 640)
    fr, d, a = steel_partials(rng, f0, 0.6, plate=True)
    first = modal(rng, fr, d, a, 1.4, detune=0.003)
    c = click(rng, 0.005, 2000, 10000, 0.0015)
    first[:len(c)] += c
    place(y, first, 0, 1.0)
    at, amp, gap = 0.0, 1.0, 0.2
    while gap > 0.03 and at < dur - 0.4:
        at += gap
        amp *= 0.62
        gap *= 0.7
        ff, dd, aa = steel_partials(rng, f0 * rng.uniform(0.9, 1.15), 0.3, n_extra=8, plate=True)
        place(y, modal(rng, ff, dd, aa, 0.5) + thump(rng, 120, 70, 0.5, 0.05) * 0.4, at, amp * 0.6)
    roll = grains(rng, 0.8, 120, 800, 4000, decay_t=0.3)
    place(y, roll * np.linspace(1, 0, len(roll)), at, 0.4)
    return y


@reg("impact", "drop_sand", 4)
def drop_sand(rng, i):
    dur = 0.55
    t = tt(dur)
    y = thump(rng, 90, 45, dur, 0.12)
    y += lowpass(noise(rng, dur), 500) * env_ad(t, 0.002, 0.05) * 3
    y += lowpass(grains(rng, dur, 140, 400, 3500, decay_t=0.1, glen=(0.002, 0.008)), 3800) * 0.7
    y += modal(rng, [rng.uniform(250, 400), rng.uniform(900, 1300)], [0.06, 0.03], [0.3, 0.2], dur, shimmer=False)
    return y


@reg("impact", "drop_sand_metal", 4)
def drop_sand_metal(rng, i):
    y = drop_sand(rng, i)
    fr, d, a = steel_partials(rng, rng.uniform(900, 1800), 0.3, n_extra=6)
    y += modal(rng, fr, d, a, 0.55) * 0.35
    return y


# ---- gore
@reg("gore", "sever", 3)
def sever(rng, i):
    dur = 1.1
    t = tt(dur)
    y = silence(dur)
    place(y, flesh_cut(rng, i), 0.0, 0.8)
    place(y, bone_crack(rng, i), 0.05, 1.1)
    place(y, thump(rng, 70, 38, 0.7, 0.3), 0.04, 1.3)
    tear = bandpass(noise(rng, dur), 500, 3000, 1) * env_ad(t, 0.02, 0.18) * 0.4
    return y + bubbles(rng, dur, 18, 180, 900, dens_decay=0.25) * 0.6 + tear


@reg("gore", "behead", 3)
def behead(rng, i):
    dur = 1.5
    y = silence(dur)
    place(y, sever(rng, i), 0, 1.0)
    place(y, bandpass(noise(rng, 0.2), 150, 1800, 2) * np.exp(-tt(0.2) / 0.03), 0.0, 1.5)
    place(y, thump(rng, 60, 32, 1.0, 0.45), 0.02, 1.2)
    g = bandpass(noise(rng, 0.9), 1500, 6000, 1) * env_ad(tt(0.9), 0.1, 0.25) * 0.5
    g += bubbles(rng, 0.9, 25, 200, 700, 0.3) * 0.5
    place(y, g, 0.25, 1.0)
    return y


@reg("gore", "gut", 3)
def gut(rng, i):
    dur = 1.4
    t = tt(dur)
    rip = stft_filter(noise(rng, dur), lambda tm, f: lorentz(f[None, :], (1400 - 700 * np.clip(tm / 0.5, 0, 1))[:, None], 1500))
    rip = rip * env_ad(t, 0.01, 0.25) * 1.2
    slosh = lowpass(noise(rng, dur), 220, 2) * (0.5 + 0.5 * np.sin(2 * np.pi * 5 * t + 1)) * env_ad(t, 0.15, 0.5) * 5
    wet = bubbles(rng, dur, 40, 150, 800, dens_decay=0.35) * 0.9
    return rip + slosh + wet + thump(rng, 80, 45, dur, 0.2) * 0.9


@reg("gore", "run_through", 3)
def run_through(rng, i):
    dur = 1.2
    t = tt(dur)
    y = fit(flesh_pierce(rng, i), dur)
    slide = bandpass(noise(rng, dur), 300, 2200, 1) * env_ad(t, 0.05, 0.25) * 0.5
    crunch = grains(rng, dur, 60, 800, 3500, decay_t=0.2) * 0.5
    wet = bubbles(rng, dur, 25, 150, 700, dens_decay=0.3) * 0.7
    return y + slide + crunch + wet + thump(rng, 70, 40, dur, 0.3) * 0.8


@reg("gore", "spurt_hiss", 3)
def spurt_hiss(rng, i):
    dur = 0.9
    t = tt(dur)
    pulse = np.exp(-((t - 0.12) / 0.07) ** 2) + 0.55 * np.exp(-((t - 0.52) / 0.09) ** 2)
    hiss = bandpass(noise(rng, dur), 2200, 7500, 2) * pulse
    wet = bubbles(rng, dur, 20, 400, 1800, 0.25) * 0.4 * pulse
    return hiss + wet + lowpass(noise(rng, dur), 300) * pulse * 2


@reg("gore", "blood_spatter_sand", 5)
def blood_spatter_sand(rng, i):
    dur = 0.6
    y = silence(dur)
    for _ in range(rng.integers(6, 14)):
        at = rng.exponential(0.15)
        if at > dur - 0.05:
            continue
        g = bandpass(noise(rng, 0.03), rng.uniform(700, 1500), rng.uniform(2500, 4000), 1)
        g = g * np.exp(-tt(0.03) / rng.uniform(0.003, 0.008))
        place(y, g, at, rng.uniform(0.2, 1.0))
    return y + lowpass(grains(rng, dur, 40, 600, 3500, decay_t=0.1, glen=(0.002, 0.008)), 4000) * 0.6 + bubbles(rng, dur, 4, 300, 900, 0.1) * 0.3


# ---- move
def _whoosh(rng, dur, f_a, f_b, bw, peak_at, tonal=0.0):
    t = tt(dur)

    def resp(tm, f):
        u = np.clip(tm / dur, 0, 1)
        fc = (f_a * (f_b / f_a) ** u)[:, None]
        return lorentz(f[None, :], fc, bw * fc)
    y = stft_filter(noise(rng, dur), resp)
    env = np.exp(-((t - dur * peak_at) / (dur * 0.28)) ** 2)
    y = y * env
    if tonal:
        fc = f_a * (f_b / f_a) ** (t / dur)
        y = y + tonal * np.sin(2 * np.pi * np.cumsum(fc * 1.7) / SR) * env * np.std(y) * 2
    return y


@reg("move", "whoosh_slow", 5, 0.7)
def whoosh_slow(rng, i):
    return _whoosh(rng, rng.uniform(0.55, 0.75), 250, rng.uniform(550, 800), 1.3, 0.5)


@reg("move", "whoosh_mid", 5, 0.85)
def whoosh_mid(rng, i):
    return _whoosh(rng, rng.uniform(0.32, 0.42), 450, rng.uniform(1300, 1800), 1.1, 0.45)


@reg("move", "whoosh_fast", 5, 1.0)
def whoosh_fast(rng, i):
    return _whoosh(rng, rng.uniform(0.2, 0.28), 800, rng.uniform(3200, 4800), 0.8, 0.5, tonal=0.25)


@reg("move", "footstep_sand", 6, 0.5)
def footstep_sand(rng, i):
    dur = 0.4
    t = tt(dur)
    y = thump(rng, 90, 52, dur, 0.09) * 1.3
    y += lowpass(noise(rng, dur), 380, 2) * env_ad(t, 0.004, 0.05) * 1.8
    y += lowpass(grains(rng, dur, rng.integers(60, 130), 400, 3200, decay_t=0.06, glen=(0.002, 0.008)), 3500) * 1.0
    return y + bandpass(noise(rng, dur), 500, 2200, 1) * env_ad(t, 0.012, 0.05) * 0.4


@reg("move", "body_fall_sand", 4, 1.0)
def body_fall_sand(rng, i):
    dur = 1.3
    t = tt(dur)
    y = thump(rng, 70, 34, dur, 0.4) * 1.5
    y += lowpass(noise(rng, dur), 420, 2) * env_ad(t, 0.01, 0.14) * 6
    y += lowpass(grains(rng, dur, 350, 400, 3500, decay_t=0.25, glen=(0.002, 0.008)), 3800) * 0.7
    return y + bandpass(noise(rng, dur), 400, 2000, 1) * env_ad(t, 0.02, 0.15) * 0.4


@reg("move", "sand_impact", 5, 0.6)
def sand_impact(rng, i):
    dur = 0.5
    t = tt(dur)
    y = thump(rng, 85, 48, dur, 0.1) * 1.2
    y += lowpass(noise(rng, dur), 400, 2) * env_ad(t, 0.004, 0.05) * 1.3
    y += lowpass(grains(rng, dur, 110, 400, 3200, decay_t=0.09, glen=(0.002, 0.008)), 3600) * 1.0
    return y + bandpass(noise(rng, dur), 500, 2400, 1) * env_ad(t, 0.01, 0.06) * 0.3


@reg("move", "armor_rattle", 4, 0.5)
def armor_rattle(rng, i):
    dur = 0.35
    y = silence(dur)
    for _ in range(rng.integers(35, 60)):
        at = rng.exponential(0.07)
        if at > dur - 0.05:
            continue
        f = rng.uniform(1800, 8000)
        g = modal(rng, [f, f * 1.5], [rng.uniform(0.01, 0.03)] * 2, [1.0, 0.4], 0.06, shimmer=False)
        place(y, g, at, rng.uniform(0.2, 1.0))
    return y


# ---- voice
@reg("voice", "grunt", 5, 0.8)
def grunt(rng, i):
    dur = rng.uniform(0.22, 0.38)
    t = tt(dur)
    env = np.minimum(1, t / 0.03) * np.exp(-t / (dur * 0.5)) * np.minimum(1, (dur - t) / 0.04)
    y = vox(rng, dur, rng.uniform(105, 135), rng.uniform(78, 95), "uh", "o", env=env, breath=0.12, rough=0.15, vib=(0, 0))
    return y + bandpass(noise(rng, dur), 500, 3000, 1) * env * 0.04


@reg("voice", "pain_light", 4, 0.9)
def pain_light(rng, i):
    dur = rng.uniform(0.35, 0.5)
    t = tt(dur)
    env = np.minimum(1, t / 0.025) * np.exp(-t / (dur * 0.7)) * np.minimum(1, (dur - t) / 0.08)
    return vox(rng, dur, rng.uniform(150, 190), rng.uniform(210, 260), "ae", "a", env=env, breath=0.08, rough=0.1,
               vib=(6.0, 0.02), shape=0.5, drive=1.4)


@reg("voice", "pain_heavy", 4, 1.0)
def pain_heavy(rng, i):
    dur = rng.uniform(0.8, 1.2)
    t = tt(dur)
    env = np.minimum(1, t / 0.03) * np.minimum(1, (dur - t) / 0.2) * (0.7 + 0.3 * np.sin(np.pi * t / dur))
    y = vox(rng, dur, rng.uniform(210, 250), rng.uniform(330, 420), "a", "ae", env=env, breath=0.1, rough=0.4,
            vib=(6.5, 0.03), shape=0.4, drive=2.2)
    return y + bandpass(noise(rng, dur), 2000, 7000, 1) * env * 0.05


@reg("voice", "death_gurgle", 3, 0.8)
def death_gurgle(rng, i):
    dur = rng.uniform(1.6, 2.1)
    t = tt(dur)
    env = np.minimum(1, t / 0.08) * np.exp(-t / (dur * 0.55)) * np.minimum(1, (dur - t) / 0.3)
    y = vox(rng, dur, 95, 55, "o", "u", env=np.ones_like(t), breath=0.25, rough=0.5, vib=(0, 0), shape=0.7)
    rate = 14 + 5 * smooth_noise(rng, dur, 3)
    bubbly = 0.45 + 0.55 * np.clip(np.sin(2 * np.pi * np.cumsum(rate) / SR), -1, 1) ** 2
    y = y * bubbly * env
    y += bubbles(rng, dur, 30, 150, 600, 0.6) * 0.5 * env
    return y + bandpass(noise(rng, dur), 600, 3000, 1) * env * 0.08


# ---- crowd
def _loop_ambience(rng, dur, voices, f0r, vowels, level_voice, clap_n):
    over = 1.5
    total = dur + over
    t = tt(total)
    mur = unit(murmur(rng, total)) * 0.5
    swell = 0.7 + 0.3 * np.clip(smooth_noise(rng, total, 0.35), -1, 1)
    vo = unit(crowd_voices(rng, total, voices, f0r, vowels, onset=(0, total * 0.9), length=(0.4, 2.2),
                           glide=(-0.12, 0.12), vib_depth=0.01)) * level_voice
    y = (mur + vo) * swell
    if clap_n:
        y = y + claps(rng, total, clap_n, 0.05 + (0.5 + 0.5 * np.clip(smooth_noise(rng, total, 0.5), -1, 1)) ** 2) * 0.25
    n, k = int(dur * SR), int(over * SR)
    w = np.linspace(0, np.pi / 2, k)  # equal-power crossfade of the tail onto the head -> seamless loop
    y2 = y[:n].copy()
    y2[:k] = y[:k] * np.sin(w) + y[n:n + k] * np.cos(w)
    return y2


@reg("crowd", "amb_low", 1, 0.35)
def amb_low(rng, i):
    return _loop_ambience(rng, 14.0, 90, (95, 210), ["a", "o", "e", "uh", "aw"], 0.5, 0)


@reg("crowd", "amb_high", 1, 0.6)
def amb_high(rng, i):
    return _loop_ambience(rng, 14.0, 240, (110, 330), ["a", "o", "e", "uh", "aw", "ae"], 1.0, 130)


@reg("crowd", "gasp", 3, 0.8)
def gasp(rng, i):
    dur = 1.1
    t = tt(dur)
    inh = stft_filter(noise(rng, dur), lambda tm, f: lorentz(f[None, :], (1200 + 1600 * np.clip(tm / 0.5, 0, 1))[:, None], 2600))
    inh = unit(inh * np.exp(-((t - 0.38) / 0.22) ** 2)) * 0.25
    v = unit(crowd_voices(rng, dur, 70, (160, 320), ["o", "aw", "ae"], onset=(0.1, 0.35), length=(0.3, 0.6), glide=(0.0, 0.25)))
    return inh + v * np.exp(-((t - 0.55) / 0.25) ** 2) * 0.5


def _reaction(rng, dur, n, f0r, vowels, rise, fall, clap_n, gl=(-0.05, 0.1), onset=0.35, mur=0.3):
    t = tt(dur)
    env = np.minimum(1, (t / rise) ** 1.3) * np.minimum(1, np.maximum(0, (dur - t) / fall))
    vo = unit(crowd_voices(rng, dur, n, f0r, vowels, onset=(0, onset), length=(dur * 0.35, dur * 0.9), glide=gl))
    m = unit(murmur(rng, dur, 250, 4500))
    y = (vo * 0.8 + m * mur) * env
    if clap_n:
        y = y + claps(rng, dur, clap_n, env + 0.01) * 0.35
    return y


@reg("crowd", "cheer", 3, 0.8)
def cheer(rng, i):
    return _reaction(rng, 2.4, 160, (170, 360), ["a", "ae", "e", "aw"], 0.3, 1.0, 180, gl=(-0.1, 0.15), onset=0.4, mur=0.35)


@reg("crowd", "roar", 3, 1.0)
def roar(rng, i):
    return _reaction(rng, 3.4, 300, (95, 240), ["a", "aw", "o", "uh", "ae"], 0.5, 1.6, 150, gl=(-0.1, 0.12), onset=0.5, mur=0.5)


@reg("crowd", "boo", 2, 0.8)
def boo(rng, i):
    return _reaction(rng, 2.6, 160, (110, 200), ["u", "o", "uh"], 0.35, 1.0, 0, gl=(-0.3, -0.05), onset=0.4, mur=0.3)


@reg("crowd", "chant", 2, 0.9)
def chant(rng, i):
    """Rhythmic non-verbal chant: stressed 'HOH-ah' syllable pairs on a stomped beat, about 8 s."""
    beat = 0.5 + 0.03 * i
    beats = 16
    dur = beats * beat + 0.8
    y = silence(dur)
    for b in range(beats):
        at = b * beat + rng.uniform(0, 0.01)
        strong = (b % 2 == 0)
        ln = beat * (0.75 if strong else 0.55)
        v = unit(crowd_voices(rng, ln + 0.1, 70, (115, 230) if strong else (130, 260), ["o"] if strong else ["a", "uh"],
                              onset=(0, 0.06), length=(ln * 0.8, ln), glide=(-0.1, 0.05) if strong else (-0.2, 0.0)))
        tl = tt(ln + 0.1)
        place(y, v * np.minimum(1, tl / 0.05) * np.exp(-tl / (ln * 0.8)) * (1.0 if strong else 0.7), at)
        place(y, thump(rng, 75, 42, 0.3, 0.12), at, (1.0 if strong else 0.55) * 0.8)
    y += unit(murmur(rng, dur, 250, 4000)) * 0.25
    return y + claps(rng, dur, 220, np.ones(len(y))) * 0.12


@reg("crowd", "finisher_roar", 2, 1.0)
def finisher_roar(rng, i):
    dur = 5.0
    t = tt(dur)
    env = np.minimum(1, (t / 0.45) ** 1.2) * np.minimum(1, np.maximum(0, (dur - t) / 2.0))
    low = unit(crowd_voices(rng, dur, 340, (90, 210), ["a", "aw", "o", "uh"], onset=(0, 0.35), length=(dur * 0.5, dur * 0.95), glide=(-0.1, 0.1)))
    high = unit(crowd_voices(rng, dur, 220, (190, 420), ["a", "ae", "e"], onset=(0.05, 0.6), length=(dur * 0.3, dur * 0.8), glide=(0.0, 0.2)))
    m = unit(murmur(rng, dur, 300, 5000))
    return (low * 0.8 + high * 0.55 + m * 0.5) * env + claps(rng, dur, 420, env + 0.02) * 0.35


# ---------------------------------------------------------------- output and checks
def finish(x, level, loop=False):
    x = highpass(np.asarray(x, float), 25, 2)
    x = x - np.mean(x)
    if not loop:
        x = fade(x, 0.0008, 0.01)
    return x / (np.max(np.abs(x)) + 1e-12) * PEAK * level


def write_wav(path, x):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def seed_for(cat, name, i):
    return zlib.crc32(f"{cat}/{name}/{i}".encode()) & 0xFFFFFFFF


def read_wav(path):
    with wave.open(path, "rb") as w:
        assert w.getframerate() == SR and w.getnchannels() == 1 and w.getsampwidth() == 2, "format"
        return np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(float) / 32768


def check_wav(path, expect_min=0.12, expect_max=20.0):
    d = read_wav(path)
    probs = []
    pk = float(np.max(np.abs(d)))
    rms = float(np.sqrt(np.mean(d ** 2)))
    dur = len(d) / SR
    if pk >= 0.999:
        probs.append("clipping")
    if pk < 0.05:
        probs.append("too quiet")
    if abs(np.mean(d)) > 0.003:
        probs.append("dc %.4f" % abs(np.mean(d)))
    if rms < 0.004:
        probs.append("rms low")
    if not (expect_min <= dur <= expect_max):
        probs.append("length %.2f" % dur)
    if (abs(d[0]) > 0.02 or abs(d[-1]) > 0.02) and not os.path.basename(path).startswith("amb_"):
        probs.append("edge click")
    if not np.all(np.isfinite(d)):
        probs.append("nan")
    return probs, pk, rms, dur


def main():
    prefixes = sys.argv[1:]
    manifest = {}
    problems = count = total = 0
    for (cat, name), (variants, fn, level) in sorted(SOUNDS.items()):
        manifest.setdefault(cat, {})[name] = variants
        if prefixes and not any(f"{cat}/{name}".startswith(p) for p in prefixes):
            continue
        for i in range(variants):
            x = finish(fn(np.random.default_rng(seed_for(cat, name, i)), i), level, name.startswith("amb_"))
            path = os.path.join(ROOT, cat, f"{name}_{i + 1}.wav")
            write_wav(path, x)
            count += 1
            total += os.path.getsize(path)
            probs = check_wav(path)[0]
            if probs:
                problems += 1
                print(f"FAIL {cat}/{name}_{i + 1}: {', '.join(probs)}")
    with open(os.path.join(ROOT, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    print(f"SFX files={count} bytes={total} problems={problems}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
