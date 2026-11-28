"""End-to-end render of a tiny project (real ffmpeg, no network)."""

import json
import subprocess

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
