#!/usr/bin/env python3
"""Measure the rendered tanpura loops instead of listening to them.

Nobody can hear a WAV file from a build log, and "does this sound like a
tanpura" has to be answered before the assets ship. These checks are the parts
of that answer that can be computed:

  seamless     the step across the loop point is no bigger than a step anywhere
               else in the file, and the spectrum sits in exact bins (a cut tail
               smears energy between bins)
  buzz         the 1.2-4 kHz band carries real energy next to the fundamental —
               the jawari, and the reason a plain additive synth sounds thin
  shimmer      how much of that band is amplitude-modulated at 2-16 Hz, which is
               the actual signature of a string grazing a curved bridge
  gaps_db      how far the level falls between plucks: a tanpura's four tails
               overlap, so it dips but never empties. Too short a sustain shows
               up here as an arpeggio rather than a drone
  loudness     peak, RMS and crest factor, so the drone sits at a sane level

The detuned jodi pair is deliberately *not* gated. Its beat rate is ~0.5 Hz and
the pluck cycle is 0.125 Hz, so the fourth harmonic of the pluck rhythm lands on
the same bin — no envelope measure tells those apart, and a metric that passes
for the wrong reason is worse than no metric.

Usage: python scripts/check_tanpura.py [c g]     (default: all six)
Exits non-zero if any loop fails a check, so it can gate a release build.
"""

import sys
import wave
from pathlib import Path

import numpy as np

SAMPLE_RATE = 44100
PLUCK_GAP = 2.0
CYCLE_SECONDS = PLUCK_GAP * 4
N = int(round(CYCLE_SECONDS * SAMPLE_RATE))
PERIOD_HZ = 1.0 / CYCLE_SECONDS
PLUCK_TIMES = tuple(i * PLUCK_GAP for i in range(4))

# Sa per pitch, matching PITCHES in make_tanpura.py and DronePitch in Dart.
PITCHES = {"c": 130.81, "d": 146.83, "e": 164.81, "f": 174.61, "g": 196.00, "a": 220.00}

FLOOR = {
    "seam_ratio": 3.0,       # loop-point step vs the loudest step inside
    "off_bin_energy": 0.06,  # spectral leakage, i.e. an unperiodic tail
    "buzz_db": -14.0,        # 1.2-4 kHz vs the fundamental band
    "shimmer": 0.30,         # 2-16 Hz modulation share of the buzz band
    "gaps_db": -7.0,         # trough between plucks, vs the crests
    "body_dbfs": -19.0,      # level of the sustained wash, not the peaks
    "peak_body": 18.0,       # how far the attacks tower over that wash
    "rms_dbfs": -26.0,
}

# Two of these are defects that must stay small; the rest are qualities that
# must be present.
LOWER_IS_BETTER = {"seam_ratio", "off_bin_energy", "peak_body"}


def body_rms(x):
    """RMS over everything but the loudest 10% of samples: the wash itself.

    Measured the same way as in the renderer, so the two scripts agree about
    what "loud" means. Overall RMS is the wrong number for a drone — it is
    dominated by four attack transients per cycle, which is exactly how the
    previous render passed a loudness check while sounding quieter than what it
    replaced.
    """
    threshold = np.percentile(np.abs(x), 90)
    quiet = x[np.abs(x) <= threshold]
    return np.sqrt(np.mean(quiet**2))


def load(path):
    with wave.open(str(path), "rb") as f:
        frames = np.frombuffer(f.readframes(f.getnframes()), dtype=np.int16)
        channels, rate = f.getnchannels(), f.getframerate()
    data = frames.reshape(-1, channels).astype(np.float64) / 32767.0
    return data, channels, rate


def band(x, lo, hi):
    """Zero-phase band selection over exactly one period, so it stays periodic."""
    spectrum = np.fft.rfft(x)
    bins = np.fft.rfftfreq(len(x), 1.0 / SAMPLE_RATE)
    mask = (bins >= lo) & (bins <= hi)
    return np.fft.irfft(spectrum * mask, len(x))


def modulation_share(x, lo, hi, mod_lo, mod_hi):
    """Of the slow envelope movement in a band, how much is at jawari rates.

    The denominator is deliberately limited to 0.3-30 Hz: the pluck cycle itself
    is 0.125 Hz and its harmonics, and counting the sharp attack transients as
    "modulation" would drown the number that actually describes the buzz.
    """
    envelope = np.abs(band(x, lo, hi))
    spectrum = np.abs(np.fft.rfft(envelope - envelope.mean())) ** 2
    bins = np.fft.rfftfreq(len(envelope), 1.0 / SAMPLE_RATE)
    total = np.sum(spectrum[(bins >= 0.3) & (bins <= 30.0)])
    inside = np.sum(spectrum[(bins >= mod_lo) & (bins <= mod_hi)])
    return inside / total if total else 0.0


def _wrapped_window(arr, centre, half):
    """arr[centre-half : centre+half], wrapping at both ends."""
    return arr[(np.arange(centre - half, centre + half)) % len(arr)]


def pluck_gaps_db(x):
    """Level of the trough halfway between plucks, against the pluck crests.

    Smoothing is a circular convolution so the RMS envelope of this exactly
    periodic signal stays periodic, including across the seam. The crest window
    is nudged past the attack because the jawari bloom peaks a few tens of
    milliseconds *after* the strike.
    """
    half = int(0.10 * SAMPLE_RATE)
    power = np.ones(2 * half) / (2 * half)
    env = np.sqrt(np.abs(np.fft.irfft(
        np.fft.rfft(x**2) * np.fft.rfft(power, len(x)), len(x))))
    peaks, troughs = [], []
    for t in PLUCK_TIMES:
        peaks.append(_wrapped_window(env, int((t + 0.05) * SAMPLE_RATE), half).max())
        troughs.append(
            _wrapped_window(env, int((t + PLUCK_GAP / 2.0) * SAMPLE_RATE), half).min()
        )
    return 20 * np.log10(np.mean(troughs) / np.mean(peaks) + 1e-12)


def analyse(x, sa):
    out = {}
    out["peak"] = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
    out["rms"] = 20 * np.log10(np.sqrt(np.mean(x**2)) + 1e-12)
    out["rms_dbfs"] = out["rms"]
    out["crest"] = out["peak"] - out["rms"]
    out["body_dbfs"] = 20 * np.log10(body_rms(x) + 1e-12)
    out["peak_body"] = out["peak"] - out["body_dbfs"]

    # Seam: compare the one step that wraps around with the steps inside.
    inside = np.abs(np.diff(x))
    seam = abs(x[0] - x[-1])
    out["seam_ratio"] = seam / (np.percentile(inside, 99.99) + 1e-12)

    # Leakage: a signal that is exactly periodic over this window puts its
    # energy in whole bins; a chopped tail smears it into neighbours.
    spectrum = np.abs(np.fft.rfft(x)) ** 2
    ranked = np.sort(spectrum)[::-1]
    keep = max(1, len(ranked) // 20)
    out["off_bin_energy"] = 1.0 - np.sum(ranked[:keep]) / np.sum(spectrum)

    fundamental = np.sqrt(np.sum(band(x, sa * 0.9, sa * 1.1) ** 2))
    buzz = np.sqrt(np.sum(band(x, 1200.0, 4000.0) ** 2))
    out["buzz_db"] = 20 * np.log10(buzz / (fundamental + 1e-12))
    # The shimmer band is narrower than the buzz band on purpose. Across
    # 1.2-4 kHz the number of partials varies a lot with the pitch, and every
    # pair contributes a difference frequency to the envelope, so a wide band
    # measures how *many* partials are there rather than how much they wobble:
    # the same instrument then reads ~0.17 at C and ~0.21 at A for the wrong
    # reason. 1.5-3 kHz is the jawari's core, and holds one partial population
    # whatever the sa.
    out["shimmer"] = modulation_share(x, 1500.0, 3000.0, 2.0, 16.0)
    out["gaps_db"] = pluck_gaps_db(x)

    bins = np.fft.rfftfreq(len(x), 1.0 / SAMPLE_RATE)
    power = np.abs(np.fft.rfft(x)) ** 2
    out["centroid"] = np.sum(bins * power) / np.sum(power)
    return out


def main() -> int:
    wanted = sys.argv[1:] or list(PITCHES)
    audio_dir = Path(__file__).resolve().parent.parent / "assets" / "audio"
    failures = []

    for name in wanted:
        path = audio_dir / f"tanpura_{name}.wav"
        if not path.exists():
            failures.append(f"{path.name}: missing")
            continue

        data, channels, rate = load(path)
        if rate != SAMPLE_RATE:
            failures.append(f"{path.name}: {rate} Hz, expected {SAMPLE_RATE}")
        if len(data) != N:
            failures.append(f"{path.name}: {len(data)} samples, expected {N}")

        # Gate every metric per channel, then report their mean. There is
        # deliberately no "mix" analysis: the two channels are phase-decorrelated
        # on purpose, so averaging them comb-cancels the low partials and measures
        # the allpass curve instead of the instrument. A loop that is fine in the
        # sum and broken in one ear is exactly what this catches.
        per_channel = [analyse(data[:, i], PITCHES[name]) for i in range(channels)]
        for label, m in zip("LR"[:channels], per_channel):
            for key, limit in FLOOR.items():
                worse = (
                    m[key] > limit
                    if key in LOWER_IS_BETTER
                    else m[key] < limit
                )
                if worse:
                    # 4 significant figures: a value that rounds to exactly the
                    # limit is the case most worth reading precisely.
                    failures.append(
                        f"{path.name} [{label}] {key}={m[key]:.4g} "
                        f"(limit {limit:g})"
                    )

        mean = {
            key: float(np.mean([m[key] for m in per_channel]))
            for key in per_channel[0]
        }
        print(
            f"{path.name}  {channels}ch  {len(data)/rate:.2f}s  "
            f"{path.stat().st_size/1024:.0f} KB  "
            f"body {mean['body_dbfs']:6.1f}  peak {mean['peak']:6.1f}  "
            f"p-b {mean['peak_body']:5.1f}  centroid {mean['centroid']:6.0f} Hz  "
            f"buzz {mean['buzz_db']:6.1f} dB  shimmer {mean['shimmer']:.2f}  "
            f"gaps {mean['gaps_db']:5.1f} dB  seam {mean['seam_ratio']:.2f}  "
            f"leak {mean['off_bin_energy']:.3f}"
        )

    if failures:
        print("\nFAILED:")
        for line in failures:
            print("  " + line)
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
