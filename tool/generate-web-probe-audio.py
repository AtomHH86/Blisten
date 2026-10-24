#!/usr/bin/env python3
"""Generate the local Web probe's 60-second, low-volume PCM WAVE file."""

import argparse
import array
import json
import math
from pathlib import Path
import sys
import wave


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="Explicit destination, e.g. build/web-probe/generated-probe.wav",
    )
    output = parser.parse_args().output.resolve()
    sample_rate = 22050
    seconds = 60
    frequency_hz = 220
    amplitude = 0.02
    frame_count = sample_rate * seconds
    fade_frames = sample_rate // 20
    samples = array.array("h", (
        round(
            32767 * amplitude
            * math.sin(2 * math.pi * frequency_hz * index / sample_rate)
            * min(1, index / fade_frames, (frame_count - 1 - index) / fade_frames)
        )
        for index in range(frame_count)
    ))
    if sys.byteorder != "little":
        samples.byteswap()
    output.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(output), "wb") as target:
        target.setnchannels(1)
        target.setsampwidth(2)
        target.setframerate(sample_rate)
        target.writeframes(samples.tobytes())
    print(json.dumps({
        "output": str(output),
        "duration_seconds": seconds,
        "sample_rate": sample_rate,
        "channels": 1,
        "frequency_hz": frequency_hz,
        "peak_amplitude": amplitude,
        "size_bytes": output.stat().st_size,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
