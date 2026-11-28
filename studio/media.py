"""Thin ffmpeg/ffprobe helpers."""

import re
import subprocess
from pathlib import Path


def ff(*args: str, cwd: Path | None = None) -> None:
    """Run ffmpeg quietly; raise on failure."""
    subprocess.run(["ffmpeg", "-y", "-v", "error", *args], check=True, cwd=cwd)


def duration(path: Path) -> float:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
        capture_output=True,
        text=True,
        check=True,
    )
    return float(out.stdout)


def silences(path: Path, noise_db: int = -40, min_len: float = 0.15) -> list[tuple[float, float]]:
    """(start, end) of every silence in an audio file."""
    log = subprocess.run(
        [
            "ffmpeg",
            "-v",
            "info",
            "-i",
            str(path),
            "-af",
            f"silencedetect=n={noise_db}dB:d={min_len}",
            "-f",
            "null",
            "-",
        ],
        capture_output=True,
        text=True,
    ).stderr
    starts = [float(x) for x in re.findall(r"silence_start: (-?[\d.]+)", log)]
    ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", log)]
    return list(zip(starts, ends))
