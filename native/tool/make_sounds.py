"""Synthesizes Vastra's interface sounds into assets/sounds/.

Soft sine tones with slow attacks, gentle detuned chorus and long
exponential tails, peaking well below full scale, so feedback is felt more
than heard. Run from native/: python tool/make_sounds.py
"""

import math
import struct
import wave
from pathlib import Path

RATE = 44100
PEAK = 10 ** (-20 / 20)  # -20 dBFS
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds"


def tone(start_hz, end_hz, length, decay, delay=0.0, attack=0.008, gain=1.0):
    def sample(t):
        t -= delay
        if t < 0 or t > length:
            return 0.0
        progress = t / length
        hz = start_hz * (end_hz / start_hz) ** progress
        envelope = min(1.0, t / attack) * math.exp(-t / decay) * (1 - progress) ** 0.5
        phase = 2 * math.pi * hz * t
        # A slightly detuned twin and a quiet octave make the tone airy.
        voice = (
            math.sin(phase)
            + 0.45 * math.sin(phase * 1.003 + 0.6)
            + 0.12 * math.sin(phase * 2.0)
        )
        return gain * envelope * voice

    return sample


def render(name, voices, seconds):
    frames = [sum(v(i / RATE) for v in voices) for i in range(int(seconds * RATE))]
    scale = PEAK / max(abs(f) for f in frames)
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(f * scale * 32767)) for f in frames))


render("tap", [tone(880, 860, 0.09, 0.03)], 0.1)
render("toggle", [tone(784, 784, 0.07, 0.03), tone(1047, 1047, 0.12, 0.05, delay=0.05, gain=0.8)], 0.18)
render("open", [tone(523, 784, 0.22, 0.12, attack=0.04)], 0.24)
render("close", [tone(784, 523, 0.2, 0.1, attack=0.02, gain=0.8)], 0.22)
render(
    "success",
    [
        tone(1047, 1047, 0.7, 0.25),
        tone(1319, 1319, 0.65, 0.22, delay=0.07, gain=0.8),
        tone(1568, 1568, 0.6, 0.2, delay=0.14, gain=0.6),
    ],
    0.8,
)
render("error", [tone(440, 430, 0.18, 0.08), tone(370, 360, 0.26, 0.1, delay=0.12, gain=0.9)], 0.4)
