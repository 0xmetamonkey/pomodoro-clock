#!/usr/bin/env python3
"""Render seamless tanpura drone loops for the Pomodoro & Clock app.

The model is a jawari model, not a generic plucked-string one. What makes a real
tanpura recognisable is the *jawari* bridge: a thick, slightly curved piece of
wood that the string keeps re-touching as it vibrates. That does three things a
naive additive synth misses, and they are the whole sound:

  1. The upper partials are strong and sustain *longer than the fundamental*, so
     a tanpura sounds like a buzzing wash with a pitch, not a plucked note.
  2. Each partial is amplitude-modulated by that contact, at a rate that rises
     with partial number — the "zzz" shimmer, a couple of Hz on the low
     partials up to ~13 Hz on the bright ones.
  3. The gourd (tumba) and the tabli soundboard add broad body formants, and the
     fingernail gives a short bright click at every pluck.

Plus the two things specific to the Hindustani instrument this copies:
  * four strings in the cycle mandra Sa - Pa - Sa - Sa, the last two a unison
    "jodi" pair deliberately detuned by a few cents, which is where the slow
    beating across the whole drone comes from;
  * the copper-wound low string is darker, thicker and slower than the steel
    ones, and the thin upper string is the brightest of the four.

Seamlessness is by construction, not by crossfade. Every frequency used —
carriers, buzz modulation rates, shimmer rates — is quantised to an integer
multiple of 1/CYCLE_SECONDS, and every decay is the *periodic summation* of the
single-pluck decay (closed form for exponentials, explicit wrap for localised
bumps). So one rendered cycle is exactly one period of the steady-state drone,
the plugin's native loop lands mid-rotation of the previous pluck's tail, and
there is nothing to hear at the seam. It also means a sustain can be longer than
the cycle without the tail being chopped off.

Usage:
    python scripts/make_tanpura.py          # all six pitches
    python scripts/make_tanpura.py c g      # just these two, while tuning
"""

import sys
import wave
from pathlib import Path

import numpy as np

SAMPLE_RATE = 44100
PLUCK_GAP = 2.0                    # seconds between consecutive string plucks
CYCLE_SECONDS = PLUCK_GAP * 4      # one full pass of the four strings = 8.0 s
N = int(round(CYCLE_SECONDS * SAMPLE_RATE))
PERIOD_HZ = 1.0 / CYCLE_SECONDS    # every frequency snaps to a multiple of this

PEAK_CEILING = 0.92                # headroom for the tanh knee, full-scale units
# Loudness is measured on the *body* of the drone, not overall RMS. Targeting
# overall RMS is what made the previous render a spectral change nobody could
# hear: the pluck transients dominate that number, so hitting -20 dBFS overall
# left the sustained part at -27 dBFS, 7.6 dB quieter than the older model it
# replaced, with a 24 dB peak-to-body ratio. The ear tracks the wash, so the wash
# is what gets a level target: -17 dBFS body, a clear 2.3 dB above the old
# model's -19.3, with the knee pulling the peaks back without saturating them.
TARGET_BODY_DBFS = -17.0


def body_rms(x):
    """RMS over everything but the loudest 10% of samples.

    Excluding the top decile removes the attack transients without needing to
    know where in the cycle the plucks fall, so the same measure works on any
    render and on a recording.
    """
    threshold = np.percentile(np.abs(x), 90)
    quiet = x[np.abs(x) <= threshold]
    return np.sqrt(np.mean(quiet**2))


# Sa in Hz per selectable pitch; the app labels these with the same names.
PITCHES = {
    "c": 130.81,
    "d": 146.83,
    "e": 164.81,
    "f": 174.61,
    "g": 196.00,
    "a": 220.00,
}

# The four strings, in plucking order. Hindustani tanpura: the low copper-wound
# mandra Sa, then Pa, then the two middle Sa as a slightly detuned unison pair.
#   brightness     1/k rolloff; lower is more top end
#   inharmonicity  bridge/string stiffness, pushes partials sharp
#   tau_floor      decay time of the fundamental, seconds
#   tau_ceiling    decay time the buzz cluster settles at, seconds
#   attack_tau     how long the pluck takes to bloom
#   buzz/noise/click/pan  relative level of each layer, and where it sits
#
# tau_floor is deliberately *longer than the 2 s between plucks*. That is the
# single property that separates a drone from an arpeggio: on a real tanpura the
# next string is already ringing before the previous one has gone, and the level
# only dips a couple of dB in between. Shortening these times is the fastest way
# to make this sound like plucked notes again.
STRINGS = (
    {
        "name": "mandra Sa",
        "ratio": 0.5, "cents": 0.0,
        "harmonics": 46, "brightness": 1.12, "inharmonicity": 0.00095,
        "tau_floor": 2.9, "tau_ceiling": 6.5, "attack_tau": 0.034,
        "buzz": 1.25, "noise": 0.70, "click": 0.18, "pan": -0.18,
    },
    {
        "name": "Pa",
        "ratio": 1.5, "cents": -3.0,
        "harmonics": 40, "brightness": 1.24, "inharmonicity": 0.00060,
        "tau_floor": 2.4, "tau_ceiling": 5.6, "attack_tau": 0.022,
        "buzz": 1.45, "noise": 0.95, "click": 0.32, "pan": 0.08,
    },
    {
        "name": "Sa",
        "ratio": 1.0, "cents": 0.0,
        "harmonics": 42, "brightness": 1.20, "inharmonicity": 0.00065,
        "tau_floor": 2.7, "tau_ceiling": 6.0, "attack_tau": 0.026,
        "buzz": 1.40, "noise": 0.90, "click": 0.30, "pan": 0.14,
    },
    {
        "name": "Sa jodi",
        "ratio": 1.0, "cents": 6.5,
        "harmonics": 48, "brightness": 1.05, "inharmonicity": 0.00050,
        "tau_floor": 2.6, "tau_ceiling": 5.8, "attack_tau": 0.018,
        "buzz": 1.60, "noise": 1.05, "click": 0.36, "pan": -0.06,
    },
)

# Broad body resonances as log-frequency gaussian boosts: tumba gourd, tabli
# soundboard, jawari buzz band, and a little air above it.
FORMANT_PEAKS = (
    (105.0, 0.55, 0.95),
    (330.0, 0.50, 0.75),
    (1900.0, 0.72, 1.70),
    (5200.0, 0.90, 0.55),
)
# The gourd and soundboard stop following the string above a few kilohertz, and
# a real tanpura is never bright up there — it is the harshest part of a naive
# additive stack. A gentle one-pole-ish rolloff keeps the buzz band intact and
# takes the fizz off the top.
RADIATION_CORNER = 3600.0
RADIATION_SLOPE = 2.2


def snap(freq):
    """Quantise a frequency (scalar or array) so its period divides the cycle."""
    return np.round(np.asarray(freq) / PERIOD_HZ) * PERIOD_HZ


def periodic_decay(t, tau):
    """Steady-state decay: this pluck's tail summed over every past cycle.

    For a pure exponential that sum has a closed form, which is why a sustain
    longer than the cycle is fine here — the head of the loop already contains
    the tail of the pluck before it.
    """
    r = np.exp(-CYCLE_SECONDS / tau)
    return np.exp(-t / tau) / (1.0 - r if r > 0.0 else 1.0)


def periodic_bloom(t, tau, attack_tau):
    """(1 - e^-t/attack) * e^-t/tau, periodised.

    Expanding the product into a difference of two exponentials lets each half
    use the closed form above, so the bloom stays exact across the seam.
    """
    tau_e = 1.0 / (1.0 / attack_tau + 1.0 / tau)
    return periodic_decay(t, tau) - periodic_decay(t, tau_e)


def wrapped_bump(t, center, sigma):
    """A localised gaussian swell plus its neighbours from the cycles either
    side, so it too is exactly periodic."""
    out = np.zeros_like(t)
    for shift in (-CYCLE_SECONDS, 0.0, CYCLE_SECONDS):
        out += np.exp(-((t - center + shift) ** 2) / (2 * sigma * sigma))
    return out


def radiation_rolloff(freqs):
    return 1.0 / (1.0 + (np.asarray(freqs) / RADIATION_CORNER) ** RADIATION_SLOPE)


def formant_gain(freqs):
    log_f = np.log2(freqs)
    gain = radiation_rolloff(freqs)
    for center, width, boost in FORMANT_PEAKS:
        gain = gain * (1.0 + boost * np.exp(
            -((log_f - np.log2(center)) ** 2) / (2 * width * width)
        ))
    return gain


def shaped_noise(rng, t, band_lo, band_hi, tau, attack_tau, tilt):
    """White noise passed through a gaussian band, then given the same
    bloom-and-decay as the string it belongs to.

    Filtering in the frequency domain across the whole cycle is circular
    convolution, which keeps the result exactly periodic — the same reason the
    loop survives. The decay is periodised too, so the noise bed drops between
    plucks instead of hissing at one level.
    """
    spectrum = np.fft.rfft(rng.standard_normal(N))
    bins = np.fft.rfftfreq(N, 1.0 / SAMPLE_RATE)
    log_f = np.log2(np.maximum(bins, 1.0))
    centre = np.log2(np.sqrt(band_lo * band_hi))
    width = np.log2(band_hi / band_lo) / 2.2
    mask = np.exp(-((log_f - centre) ** 2) / (2 * width * width))
    mask *= (bins / band_lo) ** tilt
    mask *= radiation_rolloff(bins)
    mask[bins < band_lo * 0.5] = 0.0
    band = np.fft.irfft(spectrum * mask, N)
    band /= np.max(np.abs(band)) + 1e-12
    return band * periodic_bloom(t, tau, attack_tau)


def render_string(spec, f0, rng):
    """One plucked string, positioned at t = 0, spanning a whole cycle."""
    t = np.arange(N) / SAMPLE_RATE
    out = np.zeros(N)

    # The jawari's curved bridge makes the string stiff as well as long: the
    # partials sit above the harmonic series, further up the higher they go.
    ks, freqs = [], []
    for k in range(1, spec["harmonics"] + 1):
        f = f0 * k * np.sqrt(1.0 + spec["inharmonicity"] * k * k)
        if f > 0.46 * SAMPLE_RATE:
            break
        ks.append(k)
        freqs.append(snap(f))
    ks = np.asarray(ks, dtype=float)
    freqs = np.asarray(freqs)

    amps = formant_gain(freqs) / ks ** spec["brightness"]
    amps = amps * rng.uniform(0.86, 1.0, size=len(ks))

    # Sustain, buzz rate and buzz depth are all functions of where a partial
    # sits in hertz, not of its index. Indexing them instead would make the same
    # instrument brighter and more tremulous at A than at C: the buzz band would
    # be sampling the middle of the stack at one pitch and the bottom at
    # another. The reference frequencies below are calibrated so that the C
    # render keeps the shape these parameters were tuned on.
    body = 1.0 - np.exp(-freqs / 1100.0)
    taus = spec["tau_floor"] + (spec["tau_ceiling"] - spec["tau_floor"]) * body

    # Jawari modulation: rate and depth both rise with frequency. This is the
    # single most important block in the file — without it the thing sounds like
    # an organ, with it it sounds like a tanpura. Depth is deliberately deep in
    # the buzz band: the previous pass measured only 0.20 -> 0.23 against the
    # naive model, i.e. the layer I described as "the whole sound" was barely
    # stronger than the incidental wobble of random partial phases. Capped below
    # 0.85 so no partial fully inverts, which would add fizz rather than buzz.
    mod_rates = snap(rng.uniform(0.8, 2.2, size=len(ks)) + freqs / 320.0)
    mod_depth = np.minimum(
        0.85,
        (0.18 + 0.62 * np.clip(freqs / 4700.0, 0.0, 1.0) ** 0.62) * spec["buzz"],
    )

    swell = 1.0 + 0.20 * wrapped_bump(t, 0.10, 0.055)
    phases = rng.uniform(0, 2 * np.pi, size=len(ks))
    wobble_rates = snap(rng.uniform(0.38, 1.3, size=len(ks)))

    for i in range(len(ks)):
        env = periodic_bloom(t, taus[i], spec["attack_tau"])
        buzz = 1.0 + mod_depth[i] * np.sin(2 * np.pi * mod_rates[i] * t + phases[i])
        # A shallow frequency wobble: the string-and-bridge system breathing.
        phase = 2 * np.pi * freqs[i] * t + (
            0.00075 * freqs[i] / wobble_rates[i]
        ) * np.sin(2 * np.pi * wobble_rates[i] * t + phases[i])
        out += amps[i] * env * swell * buzz * np.sin(phase)

    # The buzz's noise component: the string rattling against the jawari, which
    # decays with the string rather than sitting under everything.
    noise = shaped_noise(rng, t, 900.0, 5200.0, 1.15, spec["attack_tau"], 0.35)
    roll = snap(rng.uniform(2.6, 5.2))
    noise *= 1.0 + 0.45 * np.sin(2 * np.pi * roll * t + rng.uniform(0, 2 * np.pi))
    out += noise * 0.075 * spec["noise"]

    # Fingernail attack: a couple of milliseconds of bright transient.
    out += shaped_noise(rng, t, 1500.0, 9000.0, 0.006, 0.0004, 0.0) * 0.09 * spec["click"]
    return out


def diffuse(x, rng):
    """Allpass smear: randomises phase, leaves the spectrum untouched.

    Two different curves for the two channels decorrelate the tails, which is
    what buys the "one instrument in a room" width without doubling the sound.
    """
    spectrum = np.fft.rfft(x)
    anchors = rng.standard_normal(24)
    curve = np.interp(
        np.linspace(0.0, len(anchors) - 1.0, len(spectrum)),
        np.arange(len(anchors)),
        anchors,
    )
    phases = np.exp(1j * curve * 1.1)
    phases[0] = 1.0  # leave DC alone
    return np.fft.irfft(spectrum * phases, len(x))


def render_cycle(sa, rng):
    dry_l = np.zeros(N)
    dry_r = np.zeros(N)

    for index, spec in enumerate(STRINGS):
        f0 = sa * spec["ratio"] * (2.0 ** (spec["cents"] / 1200.0))
        mono = render_string(spec, f0, rng)

        # Each string brings its own peak to the mix, then the blend weights
        # them: in a real tanpura the low Sa is the loudest and the jodi pair
        # sits just behind it.
        mono /= np.max(np.abs(mono)) + 1e-12
        weight = (0.62, 0.50, 0.56, 0.46)[index]
        angle = (np.pi / 4) * (1.0 + spec["pan"])
        dry_l += mono * weight * np.cos(angle)
        dry_r += mono * weight * np.sin(angle)

    # Three early reflections off the room, as circular shifts so the cycle
    # stays exactly periodic.
    left = dry_l.copy()
    right = dry_r.copy()
    for shift, gain in ((353, 0.26), (614, 0.19), (1010, 0.13)):
        left += np.roll(dry_l, shift) * gain
        right += np.roll(dry_r, -shift) * gain * 0.9

    return diffuse(left, rng), diffuse(np.roll(right, 26), rng)


def soft_limit(x, ceiling):
    """tanh knee, so the level can come up without the pluck transients clipping.

    Only the top few dB are touched; below half the ceiling it is within a
    couple of percent of linear. The mild even-harmonic distortion it adds at
    the peaks reads as warmth on a drone rather than as processing.
    """
    return np.tanh(x / ceiling) * ceiling


def to_int16(signal, rng):
    # TPDF dither measured in LSBs, not in full-scale units.
    lsb = 1.0 / 32767.0
    dithered = signal + (rng.uniform(-0.5, 0.5) + rng.uniform(-0.5, 0.5)) * lsb
    return np.int16(np.clip(dithered, -1.0, 1.0) * 32767)


def main() -> None:
    wanted = sys.argv[1:] or list(PITCHES)
    out_dir = Path(__file__).resolve().parent.parent / "assets" / "audio"
    out_dir.mkdir(parents=True, exist_ok=True)

    # Fixed seeds so re-running the script reproduces byte-identical assets;
    # Python's own hash() is salted per process and would not.
    seeds = {"c": 1001, "d": 2002, "e": 3003, "f": 4004, "g": 5005, "a": 6006}

    for name in wanted:
        sa = PITCHES[name]
        rng = np.random.default_rng(seeds[name])
        left, right = render_cycle(sa, rng)

        # Bring the sustained body up to target and let the knee deal with the
        # peaks. One gain for both channels, so the image never shifts with
        # level.
        measured = 0.5 * (body_rms(left) + body_rms(right))
        gain = 10 ** (TARGET_BODY_DBFS / 20.0) / (measured + 1e-12)
        left = soft_limit(left * gain, PEAK_CEILING)
        right = soft_limit(right * gain, PEAK_CEILING)

        frames = np.empty(2 * N, dtype=np.int16)
        frames[0::2] = to_int16(left, rng)
        frames[1::2] = to_int16(right, rng)

        path = out_dir / f"tanpura_{name}.wav"
        with wave.open(str(path), "wb") as f:
            f.setnchannels(2)
            f.setsampwidth(2)
            f.setframerate(SAMPLE_RATE)
            f.writeframes(frames.tobytes())

        samples = frames.astype(np.float64) / 32767.0
        rms = np.sqrt(np.mean(samples**2))
        body = body_rms(samples)
        peak = np.max(np.abs(samples))
        print(f"{path.name}: {sa:7.2f} Hz  {N / SAMPLE_RATE:.2f}s  "
              f"{path.stat().st_size / 1024:.0f} KB  "
              f"body {20 * np.log10(body):5.1f}  peak {20 * np.log10(peak):5.1f}  "
              f"rms {20 * np.log10(rms):5.1f}  "
              f"peak-body {20 * np.log10(peak / body):4.1f} dB")


if __name__ == "__main__":
    main()
