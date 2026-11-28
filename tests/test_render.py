"""End-to-end render of a tiny project (real ffmpeg, no network)."""

import json
import subprocess
from pathlib import Path

import pytest

from studio.media import duration, ff
from studio.project import Project
from studio.render import check_timing, render


def streams(path):
    out = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "stream=codec_type,width,height",
            "-of",
            "json",
            str(path),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(out.stdout)["streams"]


def test_renders_clips_cards_and_end_card(tmp_path):
    media = tmp_path / "media"
    build = tmp_path / "build"
    media.mkdir()
    build.mkdir()
    # Two small portrait clips like the generator's (384x736 scaled down).
    for name, color in (("a.mp4", "red"), ("b.mp4", "blue")):
        ff("-f", "lavfi", "-i", f"color=c={color}:s=96x184:r=12", "-t", "2", str(media / name))
    ff("-f", "lavfi", "-i", "sine=f=440:r=48000", "-t", "4", str(build / "voiceover.wav"))
    (build / "timeline.json").write_text(
        json.dumps(
            [
                {"section": 1, "start": 0.0, "end": 2.0, "text": "كل قطعة بيها روح"},
                {"section": 2, "start": 2.4, "end": 4.0, "text": "نزّله من Google Play"},
            ],
            ensure_ascii=False,
        )
    )
    project = Project.from_dict(
        tmp_path,
        {
            "title": "t",
            "sections": [{"id": 1, "lines": [{"say": "a"}]}, {"id": 2, "lines": [{"say": "b"}]}],
            "segments": [
                {"kind": "clip", "src": "a.mp4", "start": 0, "end": 2.6},
                {"kind": "blur", "src": "b.mp4", "start": 2.6, "end": 3.4},
                {"kind": "end", "src": "b.mp4", "start": 3.4, "end": -1},
            ],
            "cards": [{"start": 2.6, "end": 3.4, "text": "مجاني"}],
            "end_card": {"title": "الحرفة", "tagline": "شعار", "cta": "حمّل", "hold": 1.0},
        },
    )
    out = render(project, width=108, height=192, fps=12, log=lambda *_: None)

    assert out.exists()
    assert abs(duration(out) - 5.0) < 0.15  # last word at 4.0 + 1.0 hold
    kinds = {s["codec_type"]: s for s in streams(out)}
    assert kinds["video"]["width"] == 108 and kinds["video"]["height"] == 192
    assert "audio" in kinds
    assert (build / "captions.ass").read_text(encoding="utf-8").count("Dialogue:") >= 4


def make_project(tmp_path, segments, end_card=True):
    data = {"title": "t", "sections": [{"id": 1, "lines": [{"say": "a"}]}], "segments": segments}
    if end_card:
        data["end_card"] = {"title": "T", "tagline": "g", "cta": "c"}
    return Project.from_dict(tmp_path, data)


def test_timing_check_rejects_segments_that_no_longer_fit(tmp_path):
    # Voice regenerated shorter: the end card would start after the end.
    p = make_project(
        tmp_path, [{"kind": "clip", "src": "a.mp4", "start": 0, "end": 8}, {"kind": "end", "src": "a.mp4", "start": 8, "end": -1}]
    )
    with pytest.raises(ValueError, match="update project.json"):
        check_timing(p, total=6.0)
    check_timing(p, total=10.0)


def test_timing_check_without_end_card_needs_exact_end(tmp_path):
    p = make_project(tmp_path, [{"kind": "clip", "src": "a.mp4", "start": 0, "end": 5}], end_card=False)
    with pytest.raises(ValueError, match="update project.json"):
        check_timing(p, total=7.0)
    check_timing(p, total=5.0)


def test_wide_clips_fill_the_portrait_frame(tmp_path):
    media, build = tmp_path / "media", tmp_path / "build"
    media.mkdir()
    build.mkdir()
    ff("-f", "lavfi", "-i", "color=c=green:s=192x108:r=12", "-t", "2", str(media / "wide.mp4"))  # 16:9
    ff("-f", "lavfi", "-i", "sine=f=440:r=48000", "-t", "2", str(build / "voiceover.wav"))
    (build / "timeline.json").write_text(json.dumps([{"section": 1, "start": 0, "end": 2.0, "text": "هلا"}]))
    p = make_project(tmp_path, [{"kind": "clip", "src": "wide.mp4", "start": 0, "end": 2.0}], end_card=False)
    out = render(p, width=108, height=192, fps=12, log=lambda *_: None)
    video = next(s for s in streams(out) if s["codec_type"] == "video")
    assert (video["width"], video["height"]) == (108, 192)


def test_still_and_trimmed_clip_segments(tmp_path):
    media, build = tmp_path / "media", tmp_path / "build"
    media.mkdir()
    build.mkdir()
    # 4 s clip whose colour changes at 2 s: red then blue.
    ff(
        "-f",
        "lavfi",
        "-i",
        "color=c=red:s=96x184:r=12:d=2",
        "-f",
        "lavfi",
        "-i",
        "color=c=blue:s=96x184:r=12:d=2",
        "-filter_complex",
        "[0][1]concat=n=2:v=1",
        str(media / "c.mp4"),
    )
    ff("-f", "lavfi", "-i", "sine=f=440:r=48000", "-t", "3", str(build / "voiceover.wav"))
    (build / "timeline.json").write_text(json.dumps([{"section": 1, "start": 0, "end": 3.0, "text": "هلا"}]))
    p = Project.from_dict(
        tmp_path,
        {
            "title": "t",
            "sections": [{"id": 1, "lines": [{"say": "a"}]}],
            "segments": [
                {"kind": "still", "src": "c.mp4", "at": 3.0, "start": 0, "end": 1.5},  # a blue frame
                {"kind": "clip", "src": "c.mp4", "from": 0.0, "to": 1.0, "start": 1.5, "end": 3.0},  # red part only
            ],
        },
    )
    out = render(p, width=108, height=192, fps=12, log=lambda *_: None)
    assert abs(duration(out) - 3.0) < 0.15

    def mean_rgb(t):
        raw = subprocess.run(
            [
                "ffmpeg",
                "-v",
                "error",
                "-ss",
                str(t),
                "-i",
                str(out),
                "-frames:v",
                "1",
                "-vf",
                "scale=1:1",
                "-f",
                "rawvideo",
                "-pix_fmt",
                "rgb24",
                "-",
            ],
            capture_output=True,
            check=True,
        ).stdout
        return tuple(raw[:3])

    r, g, b = mean_rgb(0.7)
    assert b > 150 and r < 80, "still should hold the frame at 3.0 s (blue)"
    r, g, b = mean_rgb(2.3)
    assert r > 150 and b < 80, "trimmed clip should only use 0–1 s (red)"


def test_render_works_with_a_relative_project_path(tmp_path, monkeypatch):
    # Real bug: the final step ran inside build/ while paths were relative
    # to the repo root, as with `python -m studio render projects/<name>`.
    root = tmp_path / "projects" / "p"
    (root / "media").mkdir(parents=True)
    (root / "build").mkdir()
    ff("-f", "lavfi", "-i", "color=c=red:s=96x184:r=12", "-t", "1", str(root / "media" / "a.mp4"))
    ff("-f", "lavfi", "-i", "sine=f=440:r=48000", "-t", "1", str(root / "build" / "voiceover.wav"))
    (root / "build" / "timeline.json").write_text(json.dumps([{"section": 1, "start": 0, "end": 1.0, "text": "هلا"}]))
    monkeypatch.chdir(tmp_path)
    p = make_project(Path("projects/p"), [{"kind": "clip", "src": "a.mp4", "start": 0, "end": 1.0}], end_card=False)
    out = render(p, width=108, height=192, fps=12, log=lambda *_: None)
    assert (tmp_path / out).exists()


def count_frames(path):
    out = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-count_frames",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=nb_read_frames",
            "-of",
            "csv=p=0",
            str(path),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return int(out.stdout)


def test_frame_counts_add_up_with_fractional_lengths(tmp_path):
    # Real bug: lengths like 4.9 s (146.99999 frames) rounded down lost a
    # frame per still, so the picture ran ahead of voice and captions.
    from studio.render import frame_count

    assert frame_count(12.0, 16.9, 30) == 147
    assert frame_count(6.44, 9.2, 30) == 83
    bounds = [0.0, 1.45, 2.93, 4.4]
    assert sum(frame_count(a, b, 12) for a, b in zip(bounds, bounds[1:])) == round(4.4 * 12)

    media, build = tmp_path / "media", tmp_path / "build"
    media.mkdir()
    build.mkdir()
    ff("-f", "lavfi", "-i", "color=c=red:s=96x184:r=12", "-t", "2", str(media / "c.mp4"))
    ff("-f", "lavfi", "-i", "sine=f=440:r=48000", "-t", "4.4", str(build / "voiceover.wav"))
    (build / "timeline.json").write_text(json.dumps([{"section": 1, "start": 0, "end": 4.4, "text": "هلا"}]))
    p = make_project(
        tmp_path,
        [
            {"kind": "still", "src": "c.mp4", "at": 1.0, "start": 0, "end": 1.45},
            {"kind": "clip", "src": "c.mp4", "from": 0.2, "to": 1.4, "start": 1.45, "end": 2.93},
            {"kind": "still", "src": "c.mp4", "at": 0.5, "start": 2.93, "end": 4.4},
        ],
        end_card=False,
    )
    out = render(p, width=108, height=192, fps=12, log=lambda *_: None)
    segs = sorted((build / "segments").glob("seg_*.mp4"))
    assert [count_frames(s) for s in segs] == [17, 18, 18]
    assert count_frames(out) == round(4.4 * 12)


@pytest.mark.parametrize(
    "seg, message",
    [
        ({"kind": "still", "src": "c.mp4", "at": 5.0, "start": 0, "end": 1.0}, "past the end"),
        ({"kind": "clip", "src": "c.mp4", "from": 3.0, "to": 4.0, "start": 0, "end": 1.0}, "past the end"),
    ],
)
def test_times_beyond_the_clip_are_errors(tmp_path, seg, message):
    media, build = tmp_path / "media", tmp_path / "build"
    media.mkdir()
    build.mkdir()
    ff("-f", "lavfi", "-i", "color=c=red:s=96x184:r=12", "-t", "2", str(media / "c.mp4"))
    ff("-f", "lavfi", "-i", "sine=f=440:r=48000", "-t", "1", str(build / "voiceover.wav"))
    (build / "timeline.json").write_text(json.dumps([{"section": 1, "start": 0, "end": 1.0, "text": "هلا"}]))
    # A stale frame from an "earlier edit" must not be reused silently.
    (build / "segments").mkdir()
    (build / "segments" / "still_00.png").write_bytes(b"old")
    p = make_project(tmp_path, [seg], end_card=False)
    with pytest.raises(ValueError, match=message):
        render(p, width=108, height=192, fps=12, log=lambda *_: None)
