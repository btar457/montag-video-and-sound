"""A video project: `projects/<name>/project.json` plus a git-ignored
`media/` (input clips) and `build/` (generated files)."""

import json
from dataclasses import dataclass, field
from pathlib import Path

from . import config

KINDS = ("clip", "blur", "end")


@dataclass(frozen=True)
class Line:
    say: str  # what the voice reads (may carry diacritics for pronunciation)
    show: str  # what the caption shows (the writer's original wording)


@dataclass(frozen=True)
class Section:
    id: int
    lines: list[Line]


@dataclass(frozen=True)
class Segment:
    kind: str  # clip | blur | end
    src: str  # file in media/
    start: float
    end: float  # -1 means "until the end of the video"


@dataclass(frozen=True)
class Card:
    start: float
    end: float
    text: str  # use \N for a line break


@dataclass(frozen=True)
class EndCard:
    title: str
    tagline: str
    cta: str
    sub: str = ""
    hold: float = 2.6  # seconds the end card stays after the last word


@dataclass
class Project:
    root: Path
    title: str
    voice: str
    sections: list[Section]
    segments: list[Segment] = field(default_factory=list)
    cards: list[Card] = field(default_factory=list)
    end_card: EndCard | None = None

    @property
    def media_dir(self) -> Path:
        return self.root / "media"

    @property
    def build_dir(self) -> Path:
        return self.root / "build"

    @classmethod
    def load(cls, root: Path) -> "Project":
        data = json.loads((root / "project.json").read_text(encoding="utf-8"))
        return cls.from_dict(root, data)

    @classmethod
    def from_dict(cls, root: Path, data: dict) -> "Project":
        sections = [
            Section(
                id=int(s["id"]),
                lines=[Line(say=ln["say"], show=ln.get("show", ln["say"])) for ln in s["lines"]],
            )
            for s in data["sections"]
        ]
        segments = [
            Segment(kind=g["kind"], src=g["src"], start=float(g["start"]), end=float(g["end"])) for g in data.get("segments", [])
        ]
        cards = [Card(float(c["start"]), float(c["end"]), c["text"]) for c in data.get("cards", [])]
        end = data.get("end_card")
        project = cls(
            root=root,
            title=data["title"],
            voice=data.get("voice", config.DEFAULT_VOICE),
            sections=sections,
            segments=segments,
            cards=cards,
            end_card=EndCard(**end) if end else None,
        )
        project.validate()
        return project

    def validate(self) -> None:
        if not self.sections:
            raise ValueError("project has no sections")
        ids = [s.id for s in self.sections]
        if len(set(ids)) != len(ids):
            raise ValueError("section ids must be unique")
        for s in self.sections:
            if not s.lines or any(not ln.say.strip() for ln in s.lines):
                raise ValueError(f"section {s.id} has an empty line")
        prev_end = 0.0
        for g in self.segments:
            if g.kind not in KINDS:
                raise ValueError(f"unknown segment kind {g.kind!r}")
            if abs(g.start - prev_end) > 0.01:
                raise ValueError(f"segments must be contiguous: gap/overlap at {g.start}")
            if g.end != -1 and g.end <= g.start:
                raise ValueError(f"segment at {g.start} ends before it starts")
            if "/" in g.src or "\\" in g.src or g.src.startswith("."):
                raise ValueError(f"segment src must be a plain file name in media/: {g.src!r}")
            prev_end = g.end
        if self.segments and self.segments[-1].end != -1 and self.end_card:
            raise ValueError("with an end card, the last segment must end at -1")
        for c in self.cards:
            if c.end <= c.start:
                raise ValueError(f"card {c.text!r} ends before it starts")
