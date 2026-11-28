"""Build a project's voiceover: one TTS take per section, checked, cleaned
and joined, plus a per-line timeline for captions.

A take that fails the listening check is never "repaired" by guessing where
to cut: automatic cutting proved unreliable on real takes, so the build stops
and the take is regenerated (delete its raw file) or fixed by hand.
"""

import json
from pathlib import Path

from . import config
from .check import check_audio
from .media import duration, ff, silences
from .project import Project
from .tts import synthesize

CLEAN_FILTER = (
    "highpass=f=70,"
    "afftdn=nr=12:nf=-42:tn=1,"
    "silenceremove=start_periods=1:start_threshold=-40dB:start_silence=0.03,"
    "areverse,silenceremove=start_periods=1:start_threshold=-40dB:start_silence=0.06,areverse,"
    "afade=t=in:d=0.03"
)


def split_lines(lines: list[str], total: float, pause_mids: list[float], min_len: float = 0.3) -> list[float]:
    """Boundaries [0, ..., total] between lines of one section.

    Estimate each boundary by text length, then snap to the nearest unused
    pause within 1.5 s. Boundaries always increase, each line keeps at least
    `min_len` seconds, and a pause is used once at most.
    """
    chars = sum(len(x) for x in lines) or 1
    bounds, acc, free = [0.0], 0, sorted(pause_mids)
    for k, line in enumerate(lines[:-1]):
        acc += len(line)
        est = total * acc / chars
        lo = bounds[-1] + min_len
        hi = total - min_len * (len(lines) - 1 - k)
        options = [p for p in free if lo <= p <= hi and abs(p - est) < 1.5]
        if options:
            b = min(options, key=lambda p: abs(p - est))
            free.remove(b)
        else:
            b = min(max(est, lo), hi)
        bounds.append(b)
    bounds.append(total)
    return bounds


def build(project: Project, log=print) -> Path:
    work = project.build_dir / "voice"
    work.mkdir(parents=True, exist_ok=True)
    timeline, parts, t = [], [], 0.0
    gap = work / "gap.wav"
    ff("-f", "lavfi", "-i", "anullsrc=r=48000:cl=mono", "-t", str(config.SECTION_GAP), str(gap))

    for section in project.sections:
        say = "\n".join(line.say for line in section.lines)
        raw = work / f"s{section.id}_raw.wav"
        if not raw.exists():
            model = synthesize(say, raw, voice=project.voice)
            log(f"section {section.id}: generated with {model}")

        clean = work / f"s{section.id}.wav"
        ff("-i", str(raw), "-af", CLEAN_FILTER, "-ar", "48000", str(clean))
        d = duration(clean)
        final = work / f"s{section.id}_final.wav"
        ff("-i", str(clean), "-af", f"afade=t=out:st={max(d - 0.12, 0):.3f}:d=0.12", str(final))

        report = check_audio(final, say)
        log(
            f"section {section.id}: coverage {report.coverage:.0%}, "
            f"{report.rate if report.rate is not None else 0:.1f} letters/s"
            + (f", unexpected English: {report.unexpected_latin}" if report.unexpected_latin else "")
        )
        if report.skipped_lines:
            log(f"section {section.id}: lines not heard: {[i + 1 for i in report.skipped_lines]}")
        if not report.ok:
            raise RuntimeError(f"Section {section.id} failed the listening check; delete {raw.name} to regenerate.")

        if parts:
            parts.append(gap)
            t += config.SECTION_GAP
        mids = [(a + b) / 2 for a, b in silences(final, noise_db=-45, min_len=0.2)]
        bounds = split_lines([ln.say for ln in section.lines], d, mids)
        for k, line in enumerate(section.lines):
            timeline.append(
                {
                    "section": section.id,
                    "start": round(t + bounds[k], 2),
                    "end": round(t + bounds[k + 1], 2),
                    "text": line.show,
                }
            )
        parts.append(final)
        t += d

    (work / "list.txt").write_text("".join(f"file '{p.name}'\n" for p in parts))
    out = project.build_dir / "voiceover.wav"
    ff(
        "-f",
        "concat",
        "-safe",
        "0",
        "-i",
        str(work / "list.txt"),
        "-af",
        f"loudnorm={config.LOUDNESS}",
        "-ar",
        "48000",
        str(out),
    )
    (project.build_dir / "timeline.json").write_text(json.dumps(timeline, ensure_ascii=False, indent=1), encoding="utf-8")
    log(f"voiceover: {duration(out):.2f}s")
    return out
