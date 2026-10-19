"""Procedural, original audio: racing effects + driving minor-key loops. Fixed seeds -> identical rebuilds.
Smooth by construction: sine voices, soft attacks (>= 8 ms), one-pole low-pass, convolution reverb with a
decaying filtered-noise impulse (no comb filters -> no metallic/periodic buzz). WAV 16-bit mono 44.1 kHz. Music loops are an integer number of bars; reverb + release tails wrap onto the head."""
import wave
import numpy as np
from scipy.signal import lfilter, fftconvolve
from meshkit import ROOT

SR = 44100  # = Godot's mix rate: no resampling at play time
OUT = ROOT / "assets/audio"


def db(x):
    return 10 ** (x / 20)


def env(n, a=0.02, d=0.1, s=0.6, r=0.2):
    t = np.arange(n) / SR
    dur = n / SR
    att = 0.5 - 0.5 * np.cos(np.pi * np.clip(t / max(a, 1e-4), 0, 1))  # raised-cosine attack: no click
    dec = np.where(t < a + d, 1 - (1 - s) * np.clip((t - a) / max(d, 1e-4), 0, 1), s)
    rel = np.clip((dur - t) / max(r, 1e-4), 0, 1) ** 2  # curved release
    return att * dec * rel


def tone(f, dur, kind="sine", **kw):
    n = int(dur * SR)
    ph = 2 * np.pi * np.cumsum(np.broadcast_to(f, (n,)) if np.ndim(f) else np.full(n, f)) / SR
    w = np.sin(ph) if kind == "sine" else 2 / np.pi * np.arcsin(np.sin(ph))
    return w * env(n, **kw)


def lowpass(x, hz):
    a = np.exp(-2 * np.pi * hz / SR)
    return lfilter([1 - a], [1, -a], x)


_IR = None


def reverb(x, mix=0.2, tail=1.2):
    """Soft room via convolution with a smooth, darkened, exponentially decaying noise burst.
    No feedback delays, so tails have no periodic 'hum'. Returns x with tail appended."""
    global _IR
    if _IR is None:
        n = int(1.4 * SR)
        t = np.arange(n) / SR
        ir = np.random.default_rng(1234).normal(size=n) * np.exp(-t / 0.32)
        ir = lowpass(lowpass(ir, 2500), 2500)
        ir[: int(0.012 * SR)] = 0  # 12 ms pre-delay
        _IR = ir / np.sqrt((ir ** 2).sum())
    x = np.concatenate([x, np.zeros(int(tail * SR))])
    wet = fftconvolve(x, _IR)[: len(x)]
    wet *= np.abs(x).max() / (np.abs(wet).max() + 1e-9)
    return x * (1 - mix) + wet * mix


def soft_noise(dur, hz=900, seed=0):
    x = lowpass(lowpass(np.random.default_rng(seed).normal(size=int(dur * SR)), hz), hz)
    return x / (np.abs(x).max() + 1e-9)


def fade_tail(x, ms=20):
    n = int(ms * SR / 1000)
    x[-n:] *= np.linspace(1, 0, n) ** 2
    return x


def save(name, x, peak_db):
    x = x / (np.abs(x).max() + 1e-9) * db(peak_db)
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    return x


def note(midi):
    return 440 * 2 ** ((midi - 69) / 12)


PENTA = [0, 2, 4, 7, 9]
MINOR_PENTA = [0, 3, 5, 7, 10]


def harm(f, dur, partials, **kw):
    """Brassy/buzzy voice from a few sine partials (smooth: no aliasing square waves)."""
    return sum(g * tone(np.asarray(f) * h, dur, **kw) for h, g in partials)


def sfx():
    out = {}

    def fx(name, x, peak, rv=0.0, lp=3000):
        x = lowpass(x, lp)
        if rv:
            x = reverb(x, rv, 0.6)
        out[name] = save(name, fade_tail(x), peak)

    # car horn: two notes a major third apart, a little brassy
    horn = sum(harm(note(m), 0.42, ((1, 1), (2, 0.5), (3, 0.3), (4, 0.15)), a=0.015, d=0.05, s=0.85, r=0.08) for m in (66, 70))
    fx("sfx_honk", horn, -14, rv=0.08, lp=2600)
    # nitro: rising filtered-noise whoosh over a low rumble
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    wh = soft_noise(0.9, 2500, 3) * env(n, 0.05, 0.3, 0.6, 0.4)
    rumble = tone(55 + 40 * t, 0.9, a=0.03, r=0.4)
    fx("sfx_nitro", wh + 0.7 * rumble, -14, lp=3200)
    # near-miss: quick swish, pitch falls (doppler)
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    sw = soft_noise(0.45, 1800, 4) * np.exp(-((t - 0.15) / 0.08) ** 2) + 0.3 * tone(700 * np.exp(-t * 3), 0.45, a=0.01, r=0.2)
    fx("sfx_whoosh", sw, -16, lp=2800)
    # bump: soft thud
    n = int(0.3 * SR)
    fx("sfx_bump", tone(np.linspace(110, 50, n), 0.3, a=0.006, d=0.08, s=0.3, r=0.15) + 0.3 * soft_noise(0.3, 500, 5) * env(n, 0.005, 0.05, 0.1, 0.1), -14, lp=900)
    # wall scrape: grainy, short
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    fx("sfx_scrape", soft_noise(0.35, 2200, 6) * (0.6 + 0.4 * np.sin(2 * np.pi * 37 * t)) * env(n, 0.02, 0.1, 0.6, 0.15), -20, lp=2400)
    # countdown: three low beeps then a high GO
    fx("sfx_beep_low", tone(note(72), 0.25, a=0.008, d=0.05, s=0.7, r=0.08), -16, lp=3000)
    fx("sfx_beep_high", tone(note(84), 0.6, a=0.008, d=0.1, s=0.6, r=0.3) + 0.3 * tone(note(91), 0.6, a=0.008, r=0.3), -14, rv=0.15, lp=3500)
    # lap: quick rising arpeggio
    lp_ = sum(np.pad(tone(note(72 + p), 0.4, a=0.008, d=0.1, s=0.3, r=0.25), (int(k * 0.06 * SR), int(0.3 * SR) - int(k * 0.06 * SR)))
              for k, p in enumerate([0, 7, 12, 19]))
    fx("sfx_lap", lp_, -14, rv=0.25, lp=3500)
    # finish fanfare: brassy chord stabs, last one held
    stab = lambda root, dur: sum(harm(note(root + i), dur, ((1, 1), (2, 0.45), (3, 0.25), (4, 0.1)), a=0.02, d=0.1, s=0.7, r=min(0.25, dur / 2)) for i in (0, 4, 7))
    fan = np.concatenate([stab(67, 0.18), np.zeros(int(0.05 * SR)), stab(67, 0.18), np.zeros(int(0.05 * SR)), stab(72, 1.4)])
    fx("sfx_fanfare", fan, -12, rv=0.3, lp=3000)
    # firework: soft pop + crackle tail
    n = int(1.0 * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(7)
    crack = np.zeros(n)
    for _ in range(40):
        i = int(rng.uniform(0.15, 0.9) * SR)
        crack[i:i + 60] += rng.uniform(0.2, 0.6) * np.hanning(60)
    pop = tone(np.linspace(200, 60, n), 1.0, a=0.003, d=0.05, s=0.05, r=0.3) + soft_noise(1.0, 1200, 8) * np.exp(-t * 14)
    fx("sfx_pop", pop + crack * np.exp(-t * 2), -18, rv=0.3, lp=2600)
    # railway crossing bell: two-partial ding
    ding = harm(note(81), 0.5, ((1, 1), (2.76, 0.4), (5.4, 0.15)), a=0.002, d=0.15, s=0.0, r=0.3)
    fx("sfx_bell", np.concatenate([ding, ding]), -20, rv=0.2, lp=4000)
    fx("sfx_blip", tone(note(76), 0.09, a=0.008, d=0.03, s=0.3, r=0.05), -20, lp=3000)
    fx("sfx_boop", tone(np.linspace(260, 200, int(0.24 * SR)), 0.24, a=0.02, d=0.08, s=0.5, r=0.12), -18, lp=1500)
    # engine: 2 s seamless loop at idle-ish pitch (60 Hz firing); the game sweeps pitch_scale with "gears".
    # every partial and the firing-pulse AM complete whole cycles in 2 s; air noise crossfaded at the seam.
    L = 2 * SR
    t = np.arange(L) / SR
    f0 = 60.0
    eng = sum(g * np.sin(2 * np.pi * f0 * h * t + h) for h, g in ((0.5, 0.5), (1, 1.0), (2, 0.55), (3, 0.3), (4, 0.18), (6, 0.08)))
    eng *= 0.8 + 0.2 * np.sin(2 * np.pi * 15 * t)
    X = SR // 4
    w = soft_noise(2.3, 900, 9)
    air = w[:L].copy()
    air[:X] = w[:X] * np.linspace(0, 1, X) + w[L:L + X] * np.linspace(1, 0, X)
    out["loop_engine"] = save("loop_engine", eng + 0.25 * air, -12)
    return out


def drum_kick():
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    return tone(50 + 90 * np.exp(-t * 30), 0.25, a=0.002, d=0.08, s=0.2, r=0.12)


def drum_hat(seed):
    n = int(0.06 * SR)
    x = np.random.default_rng(seed).normal(size=n)
    x = x - lowpass(x, 6000)  # high-passed noise, soft
    return x * env(n, 0.002, 0.02, 0.2, 0.03) * 0.5


def music(name, root, bpm, prog, seed, bars=8, mode=MINOR_PENTA, drive=True):
    """Driving loop: kick + soft hats, eighth-note bass, arpeggio lead, pad. Integer bars; tails wrapped onto the head."""
    rng = np.random.default_rng(seed)
    beat = 60 / bpm
    L = int(bars * 4 * beat * SR)
    buf = np.zeros(L + 3 * SR)

    def add(x, t0):
        i = int(t0 * SR)
        buf[i:i + len(x)] += x[: len(buf) - i]

    kick = drum_kick()
    for b in range(bars):
        deg = prog[b % len(prog)]
        r = root + deg
        t_bar = b * 4 * beat
        for k in (0, 3, 7):  # minor pad, detuned pair
            for det in (0.997, 1.003):
                add(0.05 * tone(note(r + k) * det, 4 * beat, a=0.6, d=0.5, s=0.85, r=1.0), t_bar)
        for e in range(8):  # eighth-note bass: root/octave pulse
            m = r - 24 + (12 if e % 4 == 3 else 0)
            add(0.32 * harm(note(m), beat * 0.45, ((1, 1), (2, 0.35), (3, 0.12)), a=0.006, d=0.08, s=0.6, r=0.06), t_bar + e * beat / 2)
        if drive:
            for q in range(4):
                add(0.5 * kick, t_bar + q * beat)
                add(0.18 * drum_hat(seed * 100 + b * 8 + q), t_bar + (q + 0.5) * beat)
        for e in range(16 if drive else 8):  # lead arpeggio, some rests
            if rng.random() < 0.3:
                continue
            step = beat / 4 if drive else beat / 2
            m = root + 12 + deg + mode[(e + b + int(rng.integers(0, 3))) % len(mode)]
            add(0.12 * harm(note(m), step * 1.6, ((1, 1), (2, 0.25)), a=0.006, d=0.08, s=0.3, r=0.1), t_bar + e * step)
    wet = reverb(lowpass(buf, 3200), 0.2, 0)
    wet[: len(wet) - L] += wet[L:]
    return save(name, wet[:L], -12)


MUSIC = {
    "music_title": (57, 100, [0, 8, 3, 10], 1, False),
    "music_harbor": (57, 124, [0, 0, 8, 10], 2, True),
    "music_canyon": (52, 128, [0, 3, 10, 8], 3, True),
    "music_downtown": (54, 126, [0, 8, 5, 7], 4, True),
    "music_frost": (59, 120, [0, 5, 8, 3], 5, True),
}


def check(x) -> dict:
    """peak dBFS, RMS dBFS, seam jump (last->first sample)."""
    pk = 20 * np.log10(np.abs(x).max() + 1e-9)
    rms = 20 * np.log10(np.sqrt((x ** 2).mean()) + 1e-9)
    return {"peak": round(float(pk), 1), "rms": round(float(rms), 1), "seam": round(float(abs(x[-1] - x[0])), 4)}


def build() -> dict:
    out = sfx()
    for k, (root, bpm, prog, seed, drive) in MUSIC.items():
        out[k] = music(k, root, bpm, prog, seed, drive=drive)
    rep = {k: check(v) for k, v in out.items()}
    for k, r in rep.items():
        assert r["peak"] <= -6.0, f"{k} too loud"
        if k.startswith(("music", "loop")):
            assert r["seam"] < 0.02, f"{k} loop seam pops"
    return rep


if __name__ == "__main__":
    for k, v in build().items():
        print(k, v)
