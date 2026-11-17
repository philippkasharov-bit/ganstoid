"""AU1: every sound in the game, made from maths (noise, tones, filters).

No samples are downloaded, so the sounds are ours to ship. Same seed, same
files. Writes 16-bit mono WAVs into the folder given:

    python3 -I tools/audio/synth.py assets/audio

Loops (amb_*, engine, siren, radio_*) are cut so their end runs into their
start; AudioBank in the game turns looping on for them.
"""
import sys
import wave
from pathlib import Path

import numpy as np

SR = 22050
rng = np.random.default_rng(1993)


# --- building blocks -------------------------------------------------------

def t_of(sec):
    return np.arange(int(sec * SR)) / SR


def noise(sec):
    return rng.uniform(-1.0, 1.0, int(sec * SR))


def brown(sec):
    x = np.cumsum(noise(sec))
    x -= np.convolve(x, np.ones(2000) / 2000, mode="same")   # keep it from wandering off
    return x / (np.abs(x).max() + 1e-9)


def onepole_lp(x, hz):
    a = np.exp(-2 * np.pi * hz / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def lp(x, hz, order=2):
    """Low-pass via FFT (fast, zero phase): fine for one-shots and loops."""
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    f *= 1.0 / (1.0 + (fr / hz) ** (2 * order))
    return np.fft.irfft(f, len(x))


def hp(x, hz, order=2):
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    f *= 1.0 - 1.0 / (1.0 + (fr / max(hz, 1e-3)) ** (2 * order))
    return np.fft.irfft(f, len(x))


def bp(x, lo, hi):
    return lp(hp(x, lo), hi)


def env(sec, attack=0.002, decay=0.2, curve=4.0):
    t = t_of(sec)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-4) * curve / 4.0)
    return a * d


def pad(x, sec):
    n = int(sec * SR)
    return np.pad(x, (0, max(0, n - len(x))))[:n]


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def at(x, sec, total):
    out = np.zeros(int(total * SR))
    i = int(sec * SR)
    j = min(len(out), i + len(x))
    out[i:j] += x[: j - i]
    return out


def sweep(f0, f1, sec, shape="sine"):
    t = t_of(sec)
    f = f0 * (f1 / f0) ** (t / sec)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) if shape == "sine" else 2 * ((ph / (2 * np.pi)) % 1.0) - 1


def tone(hz, sec, shape="sine"):
    t = t_of(sec)
    ph = 2 * np.pi * hz * t
    if shape == "sine":
        return np.sin(ph)
    if shape == "tri":
        return 2 * np.abs(2 * ((hz * t) % 1.0) - 1) - 1
    if shape == "square":
        return np.sign(np.sin(ph))
    return 2 * ((hz * t) % 1.0) - 1   # saw


def reverb(x, room=0.25, wet=0.25):
    """A cheap room: a few feedback combs, enough to put a sound in a street."""
    out = x.copy()
    tail = np.zeros(len(x) + int(SR * room * 3))
    tail[: len(x)] = x
    for ms, g in ((29.7, 0.75), (37.1, 0.72), (41.1, 0.7), (43.7, 0.68)):
        d = int(SR * ms / 1000 * (0.5 + room * 2))
        y = tail.copy()
        for i in range(d, len(y), d):
            y[i:i + d] += g * y[i - d:i][: len(y[i:i + d])]
        out = mix(out, y[: len(tail)] * wet / 4)
    return out


def seamless(x, fade=0.5):
    """Fold the tail over the head so the loop has no click."""
    n = int(fade * SR)
    head, body, tail = x[:n], x[n:-n] if n else x, x[-n:]
    w = np.linspace(0, 1, n)
    return np.concatenate([head * w + tail * (1 - w), body])


def norm(x, peak=0.9):
    m = np.abs(x).max()
    return x * (peak / m) if m > 0 else x


# --- one-shots --------------------------------------------------------------

def step(i):
    sec = 0.16
    thump = lp(noise(sec), 300) * env(sec, 0.001, 0.03) * 3
    scuff = bp(noise(sec), 1500 + 300 * i, 5000) * env(sec, 0.004, 0.05) * 0.6
    grit = hp(noise(sec), 5000) * env(sec, 0.01, 0.025) * 0.2 * (i % 2)
    return norm(mix(thump, scuff, grit), 0.7)


def punch():
    sec = 0.25
    body = lp(noise(sec), 400) * env(sec, 0.001, 0.06) * 2
    low = tone(70, sec) * env(sec, 0.001, 0.08)
    snap = hp(noise(sec), 2000) * env(sec, 0.0005, 0.012) * 0.6
    return norm(mix(body, low, snap), 0.85)


def swing():
    sec = 0.3
    w = bp(noise(sec), 400, 2500) * np.sin(np.pi * t_of(sec) / sec) ** 2
    return norm(w, 0.45)


def slash():
    sec = 0.3
    w = swing()
    edge = hp(noise(sec), 4000) * env(sec, 0.12, 0.05) * 0.5
    return norm(mix(w, at(edge, 0.08, sec)), 0.6)


def bat_hit():
    sec = 0.4
    knock = (tone(180, sec) + 0.6 * tone(420, sec) + 0.3 * tone(910, sec)) * env(sec, 0.0005, 0.06)
    return norm(mix(knock * 0.6, punch()), 0.9)


def pistol(far=False):
    sec = 1.6
    crack = noise(sec) * env(sec, 0.0003, 0.015) * 1.5
    boom = lp(noise(sec), 900) * env(sec, 0.001, 0.12) * 2.0
    low = tone(55, sec) * env(sec, 0.001, 0.15)
    x = mix(crack, boom, low)
    if far:
        x = lp(x, 600) * 0.6
        x = reverb(x, room=0.8, wet=0.9)
    else:
        x = reverb(x, room=0.35, wet=0.45)
    return norm(pad(x, sec), 0.95 if not far else 0.6)


def dry_fire():
    sec = 0.12
    c = hp(noise(sec), 2500) * env(sec, 0.0003, 0.006)
    c2 = at(hp(noise(0.05), 3000) * env(0.05, 0.0003, 0.004), 0.04, sec)
    return norm(mix(c, c2 * 0.7), 0.5)


def equip():
    sec = 0.25
    a = hp(noise(sec), 1800) * env(sec, 0.002, 0.03)
    b = at((tone(1300, 0.1) * env(0.1, 0.0005, 0.02)), 0.09, sec)
    return norm(mix(a * 0.6, b * 0.5), 0.45)


def door_open():
    sec = 0.9
    latch = at(hp(noise(0.08), 1500) * env(0.08, 0.0005, 0.01), 0.0, sec) * 0.8
    t = t_of(0.6)
    f = 380 + 120 * np.sin(2 * np.pi * 1.3 * t)
    creak = np.sin(2 * np.pi * np.cumsum(f) / SR) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 28 * t)))
    creak = bp(creak, 300, 2500) * np.sin(np.pi * t / 0.6) * 0.25
    return norm(mix(latch, at(creak, 0.12, sec)), 0.5)


def door_close():
    sec = 0.5
    thud = lp(noise(sec), 250) * env(sec, 0.001, 0.07) * 2.5
    latch = at(hp(noise(0.06), 2000) * env(0.06, 0.0005, 0.008), 0.03, sec) * 0.6
    return norm(reverb(mix(thud, latch), 0.2, 0.3)[: int(sec * SR)], 0.6)


def door_kick():
    sec = 0.8
    bang = lp(noise(sec), 700) * env(sec, 0.0005, 0.09) * 2.5
    wood = (tone(140, sec) + tone(330, sec) * 0.5) * env(sec, 0.0005, 0.12) * 0.6
    splinter = at(hp(noise(0.3), 2500) * env(0.3, 0.002, 0.08) * 0.5, 0.02, sec)
    return norm(reverb(mix(bang, wood, splinter), 0.3, 0.35)[: int(sec * SR)], 0.9)


def lockpick():
    sec = 1.0
    out = np.zeros(int(sec * SR))
    for k in range(7):
        c = hp(noise(0.03), 3500) * env(0.03, 0.0003, 0.004)
        out = mix(out, at(c * rng.uniform(0.3, 0.8), 0.05 + k * 0.13 + rng.uniform(-0.02, 0.02), sec))
    return norm(out, 0.4)


def rattle():
    sec = 0.5
    out = np.zeros(int(sec * SR))
    for k in range(4):
        out = mix(out, at(bp(noise(0.06), 800, 4000) * env(0.06, 0.001, 0.015), k * 0.09, sec))
    return norm(out, 0.45)


def glass():
    sec = 1.2
    shatter = hp(noise(sec), 2500) * env(sec, 0.0005, 0.25)
    tinkles = np.zeros(int(sec * SR))
    for _ in range(18):
        f = rng.uniform(2500, 7000)
        tinkles = mix(tinkles, at(tone(f, 0.15) * env(0.15, 0.0005, 0.03) * rng.uniform(0.1, 0.3),
                                  rng.uniform(0.02, 0.9), sec))
    return norm(mix(shatter, tinkles), 0.7)


def car_door():
    sec = 0.6
    thud = lp(noise(sec), 300) * env(sec, 0.001, 0.05) * 2
    metal = (tone(260, sec) + tone(610, sec) * 0.4) * env(sec, 0.001, 0.07) * 0.3
    latch = at(hp(noise(0.05), 2000) * env(0.05, 0.0005, 0.006), 0.02, sec) * 0.5
    return norm(mix(thud, metal, latch), 0.6)


def horn():
    sec = 0.7
    h = (tone(400, sec, "saw") + tone(500, sec, "saw")) * 0.5
    h = bp(h, 300, 3000) * np.clip(t_of(sec) / 0.02, 0, 1) * np.clip((sec - t_of(sec)) / 0.05, 0, 1)
    return norm(h, 0.55)


def crash():
    sec = 1.5
    hitx = lp(noise(sec), 1500) * env(sec, 0.0005, 0.2) * 2
    metal = sum(tone(f, sec) * rng.uniform(0.2, 0.5) for f in (190, 433, 760, 1180)) * env(sec, 0.001, 0.4)
    return norm(reverb(mix(hitx, metal * 0.4, glass() * 0.4), 0.3, 0.3)[: int(sec * SR)], 0.95)


def car_pass():
    sec = 2.2
    t = t_of(sec)
    loud = np.exp(-((t - 1.0) / 0.45) ** 2)
    n = noise(sec)
    x = (lp(n, 300) * (1 - loud) + lp(n, 1800) * loud) * loud
    eng = sweep(120, 80, sec, "saw") * loud * 0.3
    return norm(mix(x, lp(eng, 600)), 0.5)


def distant_horn():
    return norm(reverb(lp(horn(), 900), 0.8, 0.8), 0.25)


def dog():
    sec = 1.4
    out = np.zeros(int(sec * SR))
    for k in range(2):
        b = sweep(520, 300, 0.16, "saw")
        b = bp(b, 300, 2200) * env(0.16, 0.005, 0.07)
        b = mix(b, bp(noise(0.16), 500, 2000) * env(0.16, 0.005, 0.05) * 0.4)
        out = mix(out, at(b, 0.1 + k * 0.32, sec))
    return norm(reverb(lp(out, 2500), 0.7, 0.6)[: int(sec * SR)], 0.3)


def bird():
    sec = 0.8
    out = np.zeros(int(sec * SR))
    for k in range(3):
        c = sweep(3200, 4600, 0.07) * env(0.07, 0.005, 0.03)
        out = mix(out, at(c, 0.05 + k * 0.16, sec))
    return norm(out, 0.18)


def siren_far():
    sec = 4.0
    t = t_of(sec)
    f = 950 + 350 * np.sin(2 * np.pi * 0.35 * t)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR)
    s *= np.sin(np.pi * t / sec)
    return norm(reverb(lp(s, 1500), 0.9, 0.8)[: int(sec * SR)], 0.2)


# --- interface ------------------------------------------------------------

def blip(freqs, each=0.07, decay=0.06, shape="sine", gap=0.0):
    sec = len(freqs) * (each + gap) + decay * 3
    out = np.zeros(int(sec * SR))
    for k, f in enumerate(freqs):
        n = tone(f, each + decay * 2, shape) * env(each + decay * 2, 0.002, decay)
        out = mix(out, at(n, k * (each + gap), sec))
    return out


def ui_click():
    sec = 0.05
    return norm(bp(noise(sec), 1500, 6000) * env(sec, 0.0003, 0.005) + tone(2200, sec) * env(sec, 0.0003, 0.01) * 0.3, 0.3)


def ui_open():
    return norm(mix(blip([660, 990], 0.04, 0.04, "tri")), 0.25)


def ui_close():
    return norm(blip([880, 587], 0.04, 0.04, "tri"), 0.2)


def ui_cash():
    sec = 0.7
    coins = np.zeros(int(sec * SR))
    for k, f in enumerate((2637, 3136, 3951)):
        c = (tone(f, 0.4) + 0.4 * tone(f * 2.76, 0.4)) * env(0.4, 0.0005, 0.12)
        coins = mix(coins, at(c, k * 0.06, sec))
    drawer = lp(noise(sec), 500) * env(sec, 0.002, 0.04) * 0.5
    return norm(mix(coins * 0.5, drawer), 0.4)


def ui_good():
    return norm(blip([523, 659, 784], 0.06, 0.08, "tri"), 0.3)


def ui_bad():
    return norm(blip([392, 330], 0.09, 0.08, "square") * 0.5, 0.25)


def ui_stamp():
    sec = 0.8
    thump = lp(noise(sec), 160) * env(sec, 0.0008, 0.09) * 3 + tone(48, sec) * env(sec, 0.001, 0.2)
    chord = sum(tone(f, sec, "tri") for f in (220, 277, 330)) * env(sec, 0.005, 0.3) * 0.25
    return norm(reverb(mix(thump, chord), 0.4, 0.3)[: int(sec * SR)], 0.8)


def ui_rank():
    notes = [262, 330, 392, 523, 659, 784]
    a = blip(notes, 0.07, 0.12, "tri")
    held = sum(tone(f, 1.0, "saw") for f in (523, 659, 784)) * env(1.0, 0.01, 0.4) * 0.15
    return norm(reverb(mix(a, at(lp(held, 3000), 0.42, 1.6)), 0.5, 0.35), 0.6)


def pager():
    sec = 0.6
    out = np.zeros(int(sec * SR))
    for k in range(2):
        out = mix(out, at(tone(3100, 0.09, "square") * 0.3 * env(0.09, 0.001, 0.2), k * 0.14, sec))
    return norm(lp(out, 5000), 0.25)


def phone_buzz():
    sec = 0.9
    t = t_of(sec)
    buzz = lp(tone(170, sec, "square"), 900) * ((t % 0.4) < 0.25)
    return norm(buzz * np.clip(t / 0.01, 0, 1) * np.clip((sec - t) / 0.03, 0, 1), 0.3)


def ui_alert():
    return norm(blip([880, 660, 880, 660], 0.08, 0.05, "square") * 0.5, 0.3)


def heartbeat():
    sec = 0.9
    a = lp(noise(0.12), 90) * env(0.12, 0.002, 0.03) * 3 + tone(45, 0.12) * env(0.12, 0.002, 0.04)
    return norm(mix(at(a, 0.0, sec), at(a * 0.7, 0.22, sec)), 0.6)


# --- loops ------------------------------------------------------------------

def amb_day():
    sec = 14.5
    t = t_of(sec)
    rumble = lp(brown(sec), 180) * (0.7 + 0.3 * np.sin(2 * np.pi * t / 7.0))
    hiss = bp(noise(sec), 400, 2500) * 0.05 * (0.6 + 0.4 * np.sin(2 * np.pi * t / 4.7 + 1))
    hum = (tone(59, sec) + 0.4 * tone(118, sec)) * 0.03
    return norm(seamless(mix(rumble, hiss, hum)), 0.5)


def amb_night():
    sec = 14.5
    t = t_of(sec)
    rumble = lp(brown(sec), 120) * 0.5
    crickets = np.zeros(len(t))
    for f, rate, ph in ((4400, 2.1, 0.0), (4750, 2.6, 0.7), (4100, 1.7, 1.9)):
        gate = ((t * rate + ph) % 1.0) < 0.12
        chirp = tone(f, sec) * (np.sin(2 * np.pi * 48 * t) > 0) * gate
        crickets += lp(chirp.astype(float), 6000) * 0.06
    hum = tone(59, sec) * 0.04
    return norm(seamless(mix(rumble, crickets, hum)), 0.4)


def amb_crowd():
    """Many people talking at once: band-passed noise shaped like syllables."""
    sec = 10.5
    t = t_of(sec)
    out = np.zeros(len(t))
    for k in range(14):
        rate = rng.uniform(3.0, 6.0)
        syll = np.clip(np.sin(2 * np.pi * rate * t + rng.uniform(0, 6)) * 1.4, 0, 1) ** 2
        talk = (np.sin(2 * np.pi * rng.uniform(0.05, 0.2) * t + rng.uniform(0, 6)) > -0.3)
        f0 = rng.uniform(250, 900)
        v = bp(noise(sec), f0, f0 * 2.4) * syll * talk
        out += v * rng.uniform(0.4, 1.0)
    return norm(seamless(lp(out, 2600)), 0.4)


def engine():
    sec = 1.0
    t = t_of(sec)
    f = 32.0   # a whole number of cycles in the loop
    x = (tone(f, sec, "saw") * 0.6 + tone(2 * f, sec, "square") * 0.25 + tone(3 * f, sec) * 0.2)
    x *= 0.75 + 0.25 * np.sin(2 * np.pi * 8 * t)
    x = lp(x, 700) + lp(noise(sec), 400) * 0.15
    return norm(x, 0.55)


def siren():
    sec = 4.0
    t = t_of(sec)
    f = 950 + 380 * np.sin(2 * np.pi * 0.5 * t - np.pi / 2)   # two full wails
    s = np.sin(2 * np.pi * np.cumsum(f) / SR)
    s = s + 0.3 * np.sin(4 * np.pi * np.cumsum(f) / SR)
    return norm(lp(s, 3500), 0.5)


# --- the car radio: two loops, ours -----------------------------------------

BPM = 90
BEAT = 60.0 / BPM


def kick():
    sec = 0.5
    return sweep(120, 45, sec) * env(sec, 0.001, 0.25) + lp(noise(sec), 2000) * env(sec, 0.0005, 0.005) * 0.3


def snare():
    sec = 0.4
    return hp(noise(sec), 1200) * env(sec, 0.001, 0.12) * 0.7 + tone(190, sec) * env(sec, 0.001, 0.06) * 0.5


def hat(open_=False):
    sec = 0.3 if open_ else 0.08
    return hp(noise(sec), 7000) * env(sec, 0.0005, 0.12 if open_ else 0.02) * 0.35


def note_hz(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def drums(bars, pattern):
    sec = bars * 4 * BEAT
    out = np.zeros(int(sec * SR))
    k, s, h = kick(), snare(), hat()
    for b in range(bars):
        for step_, (kk, ss) in enumerate(pattern):
            pos = (b * 16 + step_) * BEAT / 4
            if kk:
                out = mix(out, at(k, pos, sec))
            if ss:
                out = mix(out, at(s, pos, sec))
            if step_ % 2 == 0:
                swing_ = BEAT / 4 * 0.12 if step_ % 4 == 2 else 0
                out = mix(out, at(h * (1.0 if step_ % 4 == 0 else 0.6), pos + swing_, sec))
    return out[: int(sec * SR)]


BOOM_BAP = [(1, 0), (0, 0), (0, 0), (0, 0), (0, 1), (0, 0), (0, 0), (1, 0),
            (0, 0), (0, 0), (1, 0), (0, 0), (0, 1), (0, 0), (0, 0), (0, 0)]


def keys(chord, sec):
    """A dusty electric piano chord."""
    out = np.zeros(int(sec * SR))
    for n in chord:
        f = note_hz(n)
        v = (tone(f, sec) + 0.25 * tone(2 * f, sec) + 0.08 * tone(3 * f, sec)) * env(sec, 0.01, sec * 0.7)
        out += v * (1 + 0.15 * np.sin(2 * np.pi * 5 * t_of(sec)))
    return out / len(chord)


def radio_1():
    """Boom-bap, A minor: a dusty piano and a round bass."""
    bars = 8
    sec = bars * 4 * BEAT
    out = drums(bars, BOOM_BAP) * 0.9
    prog = [[57, 60, 64, 67], [53, 57, 60, 64], [55, 59, 62, 65], [52, 56, 59, 62]]   # Am7 Fmaj7 G7 E7
    bass = [45, 41, 43, 40]
    for b in range(bars):
        c = prog[b % 4]
        out = mix(out, at(keys(c, BEAT * 1.5) * 0.35, b * 4 * BEAT, sec))
        out = mix(out, at(keys(c, BEAT * 1.0) * 0.25, b * 4 * BEAT + BEAT * 2.5, sec))
        bf = note_hz(bass[b % 4])
        for pos, ln in ((0, 1.5), (1.75, 0.5), (2.5, 1.2)):
            bn = lp(tone(bf, BEAT * ln, "tri"), 400) * env(BEAT * ln, 0.005, BEAT * ln * 0.8)
            out = mix(out, at(bn * 0.6, b * 4 * BEAT + pos * BEAT, sec))
    crackle = (rng.uniform(0, 1, len(out)) > 0.9993) * rng.uniform(-1, 1, len(out)) * 0.3
    out = mix(lp(out, 6000), crackle, bp(noise(sec), 1000, 8000) * 0.01)
    return norm(out[: int(sec * SR)], 0.8)


def radio_2():
    """West-coast funk, G minor: a whining lead that slides, a deep synth bass."""
    bars = 8
    sec = bars * 4 * BEAT
    pat = [(1, 0), (0, 0), (0, 0), (1, 0), (0, 1), (0, 0), (1, 0), (0, 0),
           (0, 0), (0, 0), (1, 0), (0, 0), (0, 1), (0, 0), (0, 0), (1, 0)]
    out = drums(bars, pat) * 0.85
    bass = [43, 43, 46, 41, 43, 43, 48, 46]
    for b in range(bars):
        bf = note_hz(bass[b])
        for pos in (0, 0.75, 1.5, 2.5, 3.0):
            ln = 0.6
            bn = lp(tone(bf, BEAT * ln, "saw"), 350) * env(BEAT * ln, 0.003, BEAT * 0.4)
            out = mix(out, at(bn * 0.55, b * 4 * BEAT + pos * BEAT, sec))
        if b % 2 == 0:
            ch = keys([55, 58, 62, 65], BEAT * 2) if b % 4 == 0 else keys([53, 57, 60, 63], BEAT * 2)
            out = mix(out, at(ch * 0.25, b * 4 * BEAT, sec))
    # the lead: a sine that glides between notes, with vibrato
    melody = [(0, 79, 2), (2, 77, 1), (3, 74, 1), (4, 77, 3), (7.5, 79, 0.5),
              (8, 82, 2), (10, 79, 2), (12, 77, 1.5), (13.5, 74, 2.0)]
    t = t_of(sec)
    f = np.zeros(len(t))
    gate = np.zeros(len(t))
    for beat, n, ln in melody * 1:
        for rep in (0, 16):
            i0 = int((beat + rep) * BEAT * SR)
            i1 = min(len(t), int((beat + rep + ln) * BEAT * SR))
            f[i0:i1] = note_hz(n)
            gate[i0:i1] = 1
    for i in range(1, len(f)):
        if f[i] == 0:
            f[i] = f[i - 1]
    f = onepole_lp(f, 12)   # the slide
    f *= 1 + 0.012 * np.sin(2 * np.pi * 5.5 * t)
    lead = np.sin(2 * np.pi * np.cumsum(f) / SR) * onepole_lp(gate, 30)
    out = mix(out, lead * 0.22)
    return norm(lp(out[: int(sec * SR)], 7000), 0.8)


SOUNDS = {
    "step_1": lambda: step(0), "step_2": lambda: step(1), "step_3": lambda: step(2), "step_4": lambda: step(3),
    "punch": punch, "swing": swing, "slash": slash, "bat_hit": bat_hit,
    "shot": pistol, "shot_far": lambda: pistol(True), "dry_fire": dry_fire, "equip": equip,
    "door_open": door_open, "door_close": door_close, "door_kick": door_kick,
    "lockpick": lockpick, "rattle": rattle, "glass": glass,
    "car_door": car_door, "horn": horn, "crash": crash, "car_pass": car_pass,
    "distant_horn": distant_horn, "dog": dog, "bird": bird, "siren_far": siren_far,
    "ui_click": ui_click, "ui_open": ui_open, "ui_close": ui_close, "ui_cash": ui_cash,
    "ui_good": ui_good, "ui_bad": ui_bad, "ui_stamp": ui_stamp, "ui_rank": ui_rank,
    "pager": pager, "phone_buzz": phone_buzz, "ui_alert": ui_alert, "heartbeat": heartbeat,
    "amb_day": amb_day, "amb_night": amb_night, "amb_crowd": amb_crowd,
    "engine": engine, "siren": siren, "radio_1": radio_1, "radio_2": radio_2,
}


def write(path, x):
    x = np.clip(x, -1, 1)
    data = (x * 32767).astype("<i2").tobytes()
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/audio")
    out.mkdir(parents=True, exist_ok=True)
    only = set(sys.argv[2:])
    for name, make in SOUNDS.items():
        if only and name not in only:
            continue
        x = make()
        write(out / f"{name}.wav", x)
        print(f"{name:14s} {len(x) / SR:5.2f} s")


if __name__ == "__main__":
    main()
