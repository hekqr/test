#!/usr/bin/env python3
"""Generates every sound effect in assets/sfx/ from scratch (synthesised noise, tones and filters:
no recordings, no third-party audio). Run again to rebuild them: python3 tools/make_sfx.py
Needs numpy and scipy."""
import os
import wave

import numpy as np
from scipy import signal

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
rng = np.random.default_rng(1234)


# ---------------------------------------------------------------- helpers

def t_of(dur):
    return np.arange(int(dur * SR)) / SR


def noise(dur):
    return rng.uniform(-1.0, 1.0, int(dur * SR))


def lp(x, f, order=2):
    b, a = signal.butter(order, min(f / (SR / 2), 0.99), "low")
    return signal.lfilter(b, a, x)


def hp(x, f, order=2):
    b, a = signal.butter(order, min(f / (SR / 2), 0.99), "high")
    return signal.lfilter(b, a, x)


def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], "band")
    return signal.lfilter(b, a, x)


def decay(dur, tau, attack=0.002):
    t = t_of(dur)
    env = np.exp(-t / tau)
    if attack > 0:
        env *= np.clip(t / attack, 0, 1)
    return env


def sine_glide(dur, f0, f1, curve=1.0):
    t = t_of(dur)
    k = (t / dur) ** curve
    f = f0 + (f1 - f0) * k
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def saw(freqs):
    """Band-limited-ish sawtooth from a per-sample frequency array."""
    ph = np.cumsum(freqs) / SR
    return 2.0 * (ph - np.floor(ph + 0.5))


def pad(x, dur):
    n = int(dur * SR)
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def mix(dur, *parts):
    """parts: (signal, start seconds, gain)"""
    out = np.zeros(int(dur * SR))
    for x, start, g in parts:
        i = int(start * SR)
        n = min(len(x), len(out) - i)
        if n > 0:
            out[i:i + n] += x[:n] * g
    return out


def fade(x, fin=0.003, fout=0.02):
    n = len(x)
    a = min(int(fin * SR), n)
    b = min(int(fout * SR), n)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def save(name, x, peak=0.9, loop=False):
    x = np.asarray(x, dtype=np.float64)
    if not loop:
        x = fade(x)
    m = np.max(np.abs(x)) or 1.0
    x = x / m * peak
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def seamless(x, overlap=0.5):
    """Crossfades the end into the start so the sound loops without a click."""
    n = int(overlap * SR)
    head = x[:n].copy()
    tail = x[-n:].copy()
    ramp = np.linspace(0, 1, n)
    body = x[n:-n] if len(x) > 2 * n else x[n:]
    blended = tail * (1 - ramp) + head * ramp
    return np.concatenate([body, blended])


def smooth_random(dur, rate, lo, hi):
    """A slowly wandering value (for gusts, pitch drift)."""
    pts = int(dur * rate) + 3
    v = rng.uniform(lo, hi, pts)
    xs = np.linspace(0, dur, pts)
    return np.interp(t_of(dur), xs, v)


def echo(x, delay, gain, cut=1500):
    d = int(delay * SR)
    out = np.concatenate([x, np.zeros(d)])
    out[d:] += lp(x, cut) * gain
    return out


# ---------------------------------------------------------------- guns

def gun(name, dur, crack_hp, crack_tau, body_lp, body_tau, thump_f, thump_tau, tail_lp, tail_tau, tail_gain, echo_d=0.0):
    crack = hp(noise(dur), crack_hp) * decay(dur, crack_tau, 0.0005)
    body = lp(noise(dur), body_lp) * decay(dur, body_tau, 0.001)
    thump = sine_glide(dur, thump_f * 1.8, thump_f, 0.3) * decay(dur, thump_tau, 0.001)
    tail = lp(noise(dur), tail_lp) * decay(dur, tail_tau, 0.01)
    x = crack * 0.7 + body * 1.0 + thump * 0.9 + tail * tail_gain
    if echo_d > 0:
        x = echo(x, echo_d, 0.28, 900)
    save(name, x, 0.95)


def make_guns():
    gun("gun_pistol", 0.5, 2500, 0.012, 3200, 0.045, 140, 0.06, 900, 0.14, 0.35)
    gun("gun_shotgun", 0.85, 1800, 0.02, 2200, 0.08, 85, 0.11, 700, 0.26, 0.55, 0.16)
    gun("gun_rifle", 0.55, 3000, 0.01, 4200, 0.04, 120, 0.05, 1100, 0.16, 0.35)
    gun("gun_hunting", 1.1, 2600, 0.016, 3000, 0.07, 95, 0.1, 800, 0.3, 0.5, 0.22)
    # dry click: the hammer falls on nothing
    c = bp(noise(0.004), 2500, 6000)
    save("gun_empty", mix(0.08, (c, 0.0, 1.0), (c, 0.012, 0.6)), 0.6)
    # reload: magazine out, in, slide
    clk = bp(noise(0.006), 1800, 5000) * decay(0.006, 0.002)
    slide = bp(noise(0.06), 1500, 6000) * np.hanning(int(0.06 * SR))
    save("reload", mix(0.6, (clk, 0.0, 0.8), (clk * 1.3, 0.22, 1.0), (slide, 0.38, 0.6), (clk, 0.46, 1.0)), 0.6)


# ---------------------------------------------------------------- melee / hits

def make_melee():
    dur = 0.28
    n = noise(dur)
    # whoosh: band of noise sweeping up then down
    out = np.zeros_like(n)
    seg = 64
    for i in range(0, len(n), seg):
        k = i / len(n)
        c = 350 + 1500 * np.sin(np.pi * k)
        out[i:i + seg] = bp(n[max(i - 256, 0):i + seg], c * 0.6, c * 1.4)[-len(n[i:i + seg]):]
    out *= np.sin(np.pi * np.clip(t_of(dur) / dur, 0, 1)) ** 2
    save("swing", out, 0.5)
    # hits
    for i, (f, g) in enumerate([(95, 1.0), (75, 0.9), (110, 1.0)]):
        d = 0.22
        th = sine_glide(d, f * 1.5, f, 0.4) * decay(d, 0.05)
        sm = lp(noise(d), 900) * decay(d, 0.03)
        cr = hp(noise(d), 2000) * decay(d, 0.006)
        save("hit_%d" % (i + 1), th * 1.0 + sm * 0.9 + cr * 0.3 * g, 0.8)
    # bullet into flesh / thing
    d = 0.15
    save("hit_bullet", lp(noise(d), 1400) * decay(d, 0.025) + sine_glide(d, 180, 90) * decay(d, 0.03) * 0.6, 0.7)


# ---------------------------------------------------------------- voices (zombies, you)

def voice(dur, f0, f1, formants, rough=0.35, breath=0.25, jitter=8.0, vib=(4.5, 3.0), env=None):
    t = t_of(dur)
    k = t / dur
    f = f0 + (f1 - f0) * k + smooth_random(dur, 12, -jitter, jitter) + vib[1] * np.sin(2 * np.pi * vib[0] * t)
    src = saw(f) + rough * lp(noise(dur), 2500) * (0.5 + 0.5 * np.sin(2 * np.pi * f * t / f.mean() * 1.0))
    out = np.zeros_like(src)
    for fc, bw, g in formants:
        out += bp(src, fc - bw / 2, fc + bw / 2) * g
    out += bp(noise(dur), 300, 3000) * breath
    if env is None:
        env = np.clip(k / 0.15, 0, 1) * np.clip((1 - k) / 0.35, 0, 1)
    return out * env


def make_voices():
    zf = [(450, 260, 1.0), (850, 300, 0.7), (2300, 600, 0.25)]
    for i, (f0, f1, d) in enumerate([(92, 78, 1.3), (105, 88, 1.0), (84, 96, 1.6), (98, 70, 1.2)]):
        save("zombie_groan_%d" % (i + 1), voice(d, f0, f1, zf, rough=0.45, breath=0.3, jitter=10.0), 0.7)
    # noticed you: a rising, harsher moan
    save("zombie_alert_1", voice(0.9, 105, 165, [(600, 300, 1.0), (1100, 400, 0.8), (2600, 800, 0.35)], rough=0.7, breath=0.4, jitter=14.0), 0.85)
    save("zombie_alert_2", voice(0.75, 120, 150, [(550, 300, 1.0), (1000, 400, 0.8), (2500, 800, 0.35)], rough=0.8, breath=0.45, jitter=16.0), 0.85)
    # attacking: a short snarl
    k = t_of(0.35) / 0.35
    save("zombie_attack", voice(0.35, 150, 120, [(700, 400, 1.0), (1300, 500, 0.7)], rough=1.0, breath=0.6, jitter=20.0,
                                env=np.clip(k / 0.08, 0, 1) * np.clip((1 - k) / 0.4, 0, 1)), 0.8)
    # death: falling moan and a thud
    d = 1.1
    die = voice(d, 110, 55, zf, rough=0.6, breath=0.35, jitter=10.0)
    thud = sine_glide(0.3, 90, 50) * decay(0.3, 0.07) + lp(noise(0.3), 500) * decay(0.3, 0.05)
    save("zombie_die", mix(1.3, (die, 0.0, 1.0), (thud, 0.95, 1.4)), 0.8)
    # you: short grunts
    pf = [(650, 300, 1.0), (1150, 350, 0.6), (2600, 700, 0.2)]
    for i, (f0, f1) in enumerate([(165, 130), (180, 140), (150, 125)]):
        k = t_of(0.28) / 0.28
        save("hurt_%d" % (i + 1), voice(0.28, f0, f1, pf, rough=0.5, breath=0.5, jitter=6.0, vib=(0, 0),
                                        env=np.clip(k / 0.05, 0, 1) * np.clip((1 - k) / 0.5, 0, 1)), 0.7)
    save("player_die", voice(1.2, 170, 90, pf, rough=0.6, breath=0.5, jitter=8.0), 0.75)
    # bandit shouts are left out: grunts only
    # wolf howl: rising then falling, slightly breathy
    d = 2.4
    t = t_of(d)
    k = t / d
    f = 380 + 330 * np.sin(np.pi * np.clip(k * 1.15, 0, 1)) ** 0.7 + 6 * np.sin(2 * np.pi * 5.5 * t)
    ph = np.cumsum(f) / SR
    howl = np.sin(2 * np.pi * ph) + 0.3 * np.sin(4 * np.pi * ph) + 0.1 * np.sin(6 * np.pi * ph)
    howl += bp(noise(d), 500, 2500) * 0.08
    howl *= np.clip(k / 0.1, 0, 1) * np.clip((1 - k) / 0.3, 0, 1)
    save("wolf_howl", echo(howl, 0.3, 0.25, 1200), 0.6)
    k = t_of(0.4) / 0.4
    save("wolf_snarl", voice(0.4, 210, 170, [(900, 500, 1.0), (1800, 600, 0.6)], rough=1.0, breath=0.8, jitter=25.0,
                             env=np.clip(k / 0.05, 0, 1) * np.clip((1 - k) / 0.5, 0, 1)), 0.7)


# ---------------------------------------------------------------- footsteps, doors, handling things

def make_world():
    for i in range(3):
        d = 0.14
        crunch = bp(noise(d), 250, 1600) * decay(d, 0.03, 0.004)
        # little grass / twig crackles
        for _ in range(5):
            p = rng.uniform(0, 0.06)
            crunch += mix(d, (bp(noise(0.004), 1200, 3000), p, rng.uniform(0.1, 0.25)))
        save("step_grass_%d" % (i + 1), crunch, 0.5)
        thud = lp(noise(d), 450) * decay(d, 0.025, 0.002) + sine_glide(d, 120, 80) * decay(d, 0.02) * 0.5
        heel = hp(noise(d), 1800) * decay(d, 0.006)
        save("step_hard_%d" % (i + 1), thud + heel * 0.35, 0.5)
        snow = bp(noise(d), 400, 2500) * decay(d, 0.05, 0.02)
        snow *= 0.5 + 0.5 * (rng.uniform(0, 1, len(snow)) > 0.6)
        save("step_snow_%d" % (i + 1), lp(snow, 2200), 0.45)
    # doors: a creak (wavering tone) and a latch click / a thump when shut
    d = 0.7
    t = t_of(d)
    f = 520 + 160 * np.sin(2 * np.pi * 1.4 * t) + smooth_random(d, 25, -60, 60)
    creak = saw(f) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 38 * t)))  # stick-slip
    creak = bp(creak, 500, 2500) * np.clip(t / 0.05, 0, 1) * np.clip((d - t) / 0.2, 0, 1)
    latch = bp(noise(0.01), 2000, 6000) * decay(0.01, 0.003)
    save("door_open", mix(0.8, (latch, 0.0, 1.0), (creak, 0.04, 0.5)), 0.55)
    thump = sine_glide(0.3, 110, 70) * decay(0.3, 0.06) + lp(noise(0.3), 600) * decay(0.3, 0.04)
    save("door_close", mix(0.4, (thump, 0.0, 1.0), (latch, 0.05, 0.8)), 0.6)
    # searching: rustling through things
    d = 0.7
    r = bp(noise(d), 600, 5000)
    gate = smooth_random(d, 20, 0, 1) ** 2
    save("rustle", r * gate * np.clip(t_of(d) / 0.05, 0, 1), 0.45)
    # picking something up
    d = 0.12
    save("pickup", sine_glide(d, 700, 380, 0.5) * decay(d, 0.04) * 0.6 + bp(noise(d), 1000, 4000) * decay(d, 0.02) * 0.5, 0.45)
    # chop wood: a hard "tock" and splinters
    d = 0.35
    tock = bp(noise(d), 250, 1600) * decay(d, 0.03, 0.001) + sine_glide(d, 220, 160) * decay(d, 0.04) * 0.6
    splint = hp(noise(d), 3000) * decay(d, 0.015) * 0.3
    save("chop", tock + splint, 0.7)
    # hammering (building)
    knock = sine_glide(0.12, 900, 700) * decay(0.12, 0.02) + bp(noise(0.12), 1500, 5000) * decay(0.12, 0.008) * 0.6
    save("hammer", mix(0.55, (knock, 0.0, 1.0), (knock, 0.18, 0.9), (knock, 0.36, 1.0)), 0.6)
    # eating / drinking
    d = 0.5
    bites = np.zeros(int(d * SR))
    for p in (0.0, 0.16, 0.32):
        bites += mix(d, (bp(noise(0.08), 800, 4000) * decay(0.08, 0.02), p, 1.0))
    save("eat", bites, 0.45)
    d = 0.6
    gulps = np.zeros(int(d * SR))
    for p in (0.0, 0.22, 0.42):
        gulps += mix(d, (sine_glide(0.12, 300, 520, 0.5) * np.hanning(int(0.12 * SR)), p, 1.0))
    save("drink", lp(gulps, 1500), 0.45)
    # bandaging: cloth tearing
    d = 0.5
    tear = bp(noise(d), 1500, 7000) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 60 * t_of(d))))
    save("bandage", tear * np.clip(t_of(d) / 0.02, 0, 1) * np.clip((d - t_of(d)) / 0.15, 0, 1), 0.4)
    # a match strikes and the fire catches
    d = 0.9
    strike = bp(noise(0.15), 2000, 8000) * np.hanning(int(0.15 * SR))
    whoomp = lp(noise(0.7), 700) * np.clip(t_of(0.7) / 0.15, 0, 1) * decay(0.7, 0.25)
    save("ignite", mix(d, (strike, 0.0, 0.8), (whoomp, 0.15, 1.0)), 0.55)
    # stick lands with a clatter
    clat = np.zeros(int(0.4 * SR))
    for p, g in ((0.0, 1.0), (0.09, 0.6), (0.17, 0.35)):
        clat += mix(0.4, (bp(noise(0.05), 600, 3500) * decay(0.05, 0.012) + sine_glide(0.05, 500, 400) * decay(0.05, 0.015) * 0.5, p, g))
    save("clatter", clat, 0.6)
    # ui
    save("ui_click", bp(noise(0.03), 1500, 5000) * decay(0.03, 0.006) + sine_glide(0.03, 1200, 900) * decay(0.03, 0.008) * 0.5, 0.35)
    save("ui_open", mix(0.18, (bp(noise(0.15), 400, 3000) * np.hanning(int(0.15 * SR)), 0.0, 1.0)), 0.3)


# ---------------------------------------------------------------- ambience (loops)

def make_ambience():
    # wind: low rushing noise with slow gusts
    d = 8.0
    w = lp(noise(d), 500, 2) * 0.8 + bp(noise(d), 500, 1400) * 0.25 * smooth_random(d, 0.8, 0, 1)
    w *= 0.45 + 0.55 * smooth_random(d, 0.5, 0, 1)
    save("amb_wind", seamless(w, 1.0), 0.6, loop=True)
    # rain: hiss plus drops
    d = 6.0
    r = hp(noise(d), 1200) * 0.35 + bp(noise(d), 400, 1200) * 0.15
    for _ in range(int(d * 40)):
        p = rng.uniform(0, d - 0.02)
        r += mix(d, (bp(noise(0.012), 2000, 7000) * decay(0.012, 0.003), p, rng.uniform(0.1, 0.5)))
    save("amb_rain", seamless(r, 0.8), 0.55, loop=True)
    # crickets at night: chirp pulses in little groups
    d = 6.0
    cr = np.zeros(int(d * SR))
    for voice_f, rate in ((4300, 2.1), (4700, 1.6), (3900, 2.7)):
        p = rng.uniform(0, 0.4)
        while p < d - 0.3:
            for k in range(3):
                pulse = np.sin(2 * np.pi * voice_f * t_of(0.025)) * np.hanning(int(0.025 * SR))
                cr += mix(d, (pulse, p + k * 0.045, rng.uniform(0.3, 0.6)))
            p += 1.0 / rate + rng.uniform(-0.1, 0.1)
    save("amb_crickets", seamless(cr, 0.3), 0.35, loop=True)
    # campfire: low roar and crackles
    d = 5.0
    f = lp(noise(d), 300) * 0.5 * (0.7 + 0.3 * smooth_random(d, 2, 0, 1))
    for _ in range(int(d * 14)):
        p = rng.uniform(0, d - 0.03)
        f += mix(d, (bp(noise(0.006), 1500, 7000) * decay(0.006, 0.002), p, rng.uniform(0.3, 1.0)))
    save("amb_fire", seamless(f, 0.5), 0.5, loop=True)
    # birds: single calls the ambience plays now and then in daylight
    for i in range(4):
        d = 0.6
        call = np.zeros(int(d * SR))
        base = rng.uniform(2500, 4200)
        notes = rng.integers(2, 5)
        for k in range(notes):
            nd = rng.uniform(0.05, 0.11)
            ch = sine_glide(nd, base * rng.uniform(0.9, 1.25), base * rng.uniform(0.7, 1.3), 0.6) * np.hanning(int(nd * SR))
            call += mix(d, (ch, k * 0.13, rng.uniform(0.6, 1.0)))
        save("bird_%d" % (i + 1), call, 0.35)


if __name__ == "__main__":
    make_guns()
    make_melee()
    make_voices()
    make_world()
    make_ambience()
    print("wrote", len([f for f in os.listdir(OUT) if f.endswith(".wav")]), "sounds to", os.path.abspath(OUT))
