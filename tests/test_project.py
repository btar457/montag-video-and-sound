import copy
from pathlib import Path

import pytest

from studio.project import Project

ROOT = Path(__file__).resolve().parents[1]

BASE = {
    "title": "t",
    "sections": [{"id": 1, "lines": [{"say": "الحِرْفة", "show": "«الحرفة»"}, {"say": "هلا"}]}],
    "segments": [
        {"kind": "clip", "src": "a.mp4", "start": 0, "end": 3},
        {"kind": "end", "src": "a.mp4", "start": 3, "end": -1},
    ],
    "cards": [{"start": 1, "end": 2, "text": "x"}],
    "end_card": {"title": "T", "tagline": "g", "cta": "c"},
}


def load(**changes):
    data = copy.deepcopy(BASE)
    data.update(changes)
    return Project.from_dict(Path("/tmp/p"), data)


def test_valid_project_and_defaults():
    p = load()
    assert p.voice == "Leda"
    assert p.sections[0].lines[0].show == "«الحرفة»"
    assert p.sections[0].lines[1].show == "هلا"  # show defaults to say
    assert p.end_card.hold == 2.6
    assert p.media_dir == Path("/tmp/p/media")


def test_the_saved_ad_project_is_valid():
    p = Project.load(ROOT / "projects" / "alhirfa-ad")
    assert len(p.sections) == 5
    assert p.segments[-1].end == -1


@pytest.mark.parametrize(
    "bad, message",
    [
        ({"sections": []}, "no sections"),
        ({"sections": [{"id": 1, "lines": [{"say": " "}]}]}, "empty line"),
        ({"sections": [{"id": 1, "lines": [{"say": "a"}]}, {"id": 1, "lines": [{"say": "b"}]}]}, "unique"),
        ({"segments": [{"kind": "zoom", "src": "a.mp4", "start": 0, "end": -1}]}, "unknown segment"),
        (
            {
                "segments": [
                    {"kind": "clip", "src": "a.mp4", "start": 0, "end": 2},
                    {"kind": "end", "src": "a.mp4", "start": 3, "end": -1},
                ]
            },
            "contiguous",
        ),
        ({"segments": [{"kind": "clip", "src": "../secret.mp4", "start": 0, "end": -1}]}, "plain file name"),
        ({"segments": [{"kind": "clip", "src": "a.mp4", "start": 0, "end": 5}]}, "must end at -1"),
        ({"cards": [{"start": 2, "end": 1, "text": "x"}]}, "ends before"),
    ],
)
def test_invalid_projects_are_rejected(bad, message):
    with pytest.raises(ValueError, match=message):
        load(**bad)


@pytest.mark.parametrize(
    "seg, message",
    [
        ({"kind": "clip", "src": "a.mp4", "start": 0, "end": -1, "from": 1}, "both 'from' and 'to'"),
        ({"kind": "clip", "src": "a.mp4", "start": 0, "end": -1, "from": 3, "to": 2}, "from < to"),
        ({"kind": "still", "src": "a.mp4", "start": 0, "end": -1, "at": -1}, "must not be negative"),
        ({"kind": "still", "src": "", "start": 0, "end": -1}, "plain file name"),
    ],
)
def test_invalid_trim_and_still_are_rejected(seg, message):
    with pytest.raises(ValueError, match=message):
        load(segments=[seg])


def test_still_and_trim_fields_are_read():
    p = load(
        segments=[
            {"kind": "still", "src": "a.mp4", "at": 5.2, "start": 0, "end": 2},
            {"kind": "clip", "src": "a.mp4", "from": 2.0, "to": 6.0, "start": 2, "end": -1},
        ]
    )
    assert p.segments[0].at == 5.2
    assert (p.segments[1].src_from, p.segments[1].src_to) == (2.0, 6.0)


@pytest.mark.parametrize(
    "seg, message",
    [
        ({"kind": "clip", "src": "a.mp4", "start": 0, "end": -1, "at": 2}, "only applies to still"),
        ({"kind": "still", "src": "a.mp4", "start": 0, "end": -1, "from": 1, "to": 2}, "only apply to clip and blur"),
    ],
)
def test_fields_for_another_kind_are_rejected(seg, message):
    with pytest.raises(ValueError, match=message):
        load(segments=[seg])
