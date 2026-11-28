"""Assemble the final video: segments from the user's clips, voiceover,
captions, cards and end card."""

import json
from pathlib import Path

from . import config
from .captions import build_ass
from .media import duration, ff
from .project import Project, Segment


def _upscale(w: int, h: int) -> str:
    # Clips from generators are often small (e.g. 384x736): scale to width,
    # centre-crop to the frame, light sharpening.
    # Fill the frame whatever the clip's shape, then centre-crop.
    return (
        f"scale={w}:{h}:force_original_aspect_ratio=increase:flags=lanczos,crop={w}:{h},"
        f"unsharp=5:5:0.5:5:5:0,format=yuv420p,setsar=1"
    )


def segment_filter(kind: str, factor: float, w: int, h: int, fps: int, frames: int = 0) -> str:
    """ffmpeg -vf for one segment. `factor` stretches the clip to its slot
    (1.3 = 30% slower), smoothed with motion interpolation."""
    up = _upscale(w, h)
    if kind == "clip":
        return f"setpts={factor:.4f}*PTS,minterpolate=fps={fps}:mi_mode=mci:mc_mode=aobmc:vsbmc=1,{up}"
    if kind == "blur":
        return f"setpts={factor:.4f}*PTS,fps={fps},{up},gblur=sigma=28,eq=brightness=-0.18:saturation=0.8"
    if kind == "end":
        return (
            f"{up},zoompan=z='min(1+0.0009*on,1.12)':d={frames}:"
            f"x='iw/2-(iw/zoom/2)':y='ih/3-(ih/zoom/3)':s={w}x{h}:fps={fps},"
            f"eq=brightness=-0.12,format=yuv420p"
        )
    raise ValueError(kind)


def check_timing(project: Project, total: float) -> None:
    """Segment times are fixed in project.json; if the voiceover was
    regenerated with a different length they may no longer fit."""
    if not project.segments:
        raise ValueError("project has no segments to render")
    last = project.segments[-1]
    if any(s.end == -1 for s in project.segments[:-1]):
        raise ValueError("only the last segment may end at -1")
    if last.end == -1 and last.start >= total - 0.5:
        raise ValueError(f"last segment starts at {last.start}s but the video is {total}s: update project.json")
    if last.end != -1 and abs(last.end - total) > 0.05:
        raise ValueError(f"segments end at {last.end}s but the video is {total}s: update project.json")


def _render_segment(project: Project, i: int, seg: Segment, end: float, w: int, h: int, fps: int, out_dir: Path) -> Path:
    out = out_dir / f"seg_{i:02d}.mp4"
    length = end - seg.start
    src = project.media_dir / seg.src
    if not src.is_file():
        raise FileNotFoundError(f"missing clip media/{seg.src}")
    enc = ["-r", str(fps), "-c:v", "libx264", "-preset", "medium", "-crf", "18", str(out)]
    if seg.kind == "end":
        still = out_dir / f"end_{i:02d}.png"
        ff("-sseof", "-0.1", "-i", str(src), "-an", "-frames:v", "1", "-update", "1", str(still))
        vf = segment_filter("end", 1, w, h, fps, frames=int(length * fps))
        ff("-loop", "1", "-i", str(still), "-vf", vf, "-t", f"{length:.3f}", *enc)
    else:
        vf = segment_filter(seg.kind, length / duration(src), w, h, fps)
        ff("-i", str(src), "-an", "-vf", vf, "-t", f"{length:.3f}", *enc)
    return out


def render(project: Project, width: int = config.WIDTH, height: int = config.HEIGHT, fps: int = config.FPS, log=print) -> Path:
    voice = project.build_dir / "voiceover.wav"
    timeline_file = project.build_dir / "timeline.json"
    if not voice.exists() or not timeline_file.exists():
        raise FileNotFoundError("run `python -m studio voice` first")
    timeline = json.loads(timeline_file.read_text(encoding="utf-8"))
    hold = project.end_card.hold if project.end_card else 0.0
    total = round(timeline[-1]["end"] + hold, 2)
    check_timing(project, total)

    seg_dir = project.build_dir / "segments"
    seg_dir.mkdir(parents=True, exist_ok=True)
    parts = []
    for i, seg in enumerate(project.segments):
        end = total if seg.end == -1 else seg.end
        parts.append(_render_segment(project, i, seg, end, width, height, fps, seg_dir))
        log(f"segment {i}: {seg.kind} {seg.src} {seg.start:.2f}–{end:.2f}")
    (seg_dir / "list.txt").write_text("".join(f"file '{p.name}'\n" for p in parts))
    video = seg_dir / "video_only.mp4"
    ff("-f", "concat", "-safe", "0", "-i", str(seg_dir / "list.txt"), "-c", "copy", str(video))

    ass = project.build_dir / "captions.ass"
    ass.write_text(build_ass(timeline, project.cards, project.end_card, total, width, height), encoding="utf-8")
    out = project.build_dir / f"{project.root.name}.mp4"
    ff(
        "-i",
        str(video),
        "-i",
        str(voice),
        "-vf",
        f"ass={ass.name}",  # relative: run in build/, so paths need no filter escaping
        "-map",
        "0:v",
        "-map",
        "1:a",
        "-c:v",
        "libx264",
        "-preset",
        "slow",
        "-crf",
        "19",
        "-pix_fmt",
        "yuv420p",
        "-c:a",
        "aac",
        "-b:a",
        "192k",
        "-af",
        f"apad=whole_dur={total}",
        "-t",
        f"{total}",
        "-movflags",
        "+faststart",
        str(out),
        cwd=project.build_dir,
    )
    log(f"wrote {out} ({total:.2f}s)")
    return out
