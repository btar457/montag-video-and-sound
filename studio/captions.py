"""Arabic captions and text cards as an ASS subtitle file (burned in by
ffmpeg/libass, which shapes Arabic correctly)."""

from collections.abc import Iterator

from . import config

# libass lays out every line as a left-to-right paragraph; wrapping Arabic in
# a right-to-left embedding fixes mixed lines such as "حمّل من Google Play"
# and puts end punctuation on the left where it belongs.
RLE, PDF = "‫", "‬"


def rtl(text: str) -> str:
    return f"{RLE}{text}{PDF}"


def ts(t: float) -> str:
    """Seconds → ASS time (h:mm:ss.cc)."""
    cs = int(round(max(t, 0) * 100))
    return f"{cs // 360000}:{cs // 6000 % 60:02d}:{cs // 100 % 60:02d}.{cs % 100:02d}"


def chunks(text: str, start: float, end: float, max_words: int = config.CAPTION_MAX_WORDS) -> Iterator[tuple[float, float, str]]:
    """Split a spoken line into short caption pieces timed by text length.

    A single trailing word is merged into the previous piece so no caption
    shows one lonely word.
    """
    words = text.split()
    if not words:
        return
    groups = [words[k : k + max_words] for k in range(0, len(words), max_words)]
    if len(groups) > 1 and len(groups[-1]) == 1:
        last = groups.pop()
        groups[-1] += last
    total = sum(len(" ".join(g)) for g in groups)
    t = start
    for g in groups:
        piece = " ".join(g)
        d = (end - start) * len(piece) / total
        yield t, t + d, piece
        t += d


def _style(name, font, size, primary, outline, back, border_style, outline_w, shadow, align, margin_v):
    return (
        f"Style: {name},{font},{size},{primary},&H00FFFFFF,{outline},{back},1,0,0,0,100,100,0,0,"
        f"{border_style},{outline_w},{shadow},{align},80,80,{margin_v},1"
    )


def header(width: int = config.WIDTH, height: int = config.HEIGHT) -> list[str]:
    scale = height / 1920  # styles are designed for 1080x1920
    s = lambda v: max(int(v * scale), 1)  # noqa: E731
    g = config.GOLD
    return [
        "[Script Info]",
        "ScriptType: v4.00+",
        f"PlayResX: {width}",
        f"PlayResY: {height}",
        "WrapStyle: 0",
        "ScaledBorderAndShadow: yes",
        "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, "
        "Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, "
        "Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
        _style("Cap", config.FONT_BODY, s(80), "&H00FFFFFF", "&H00101010", "&H96000000", 1, s(6), s(3), 2, s(430)),
        _style("Card", config.FONT_TITLE, s(96), g, "&H00101010", "&H64000000", 1, s(5), s(4), 5, 0),
        _style("Logo", config.FONT_TITLE, s(190), g, "&H00101010", "&H64000000", 1, s(7), s(5), 5, 0),
        _style("Tag", config.FONT_BODY, s(64), "&H00FFFFFF", "&H00101010", "&H64000000", 1, s(5), s(3), 5, 0),
        _style("Cta", config.FONT_BODY, s(62), "&H00FFFFFF", g, g, 3, s(22), 0, 5, 0),
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]


def build_ass(
    timeline: list[dict],
    cards,
    end_card,
    total: float,
    width: int = config.WIDTH,
    height: int = config.HEIGHT,
) -> str:
    """Captions for every line (except the last section when an end card
    shows those words), centre cards, and the end card."""
    last_section = timeline[-1]["section"] if timeline else None
    lines = header(width, height)
    for row in timeline:
        if end_card and row["section"] == last_section:
            continue
        for a, b, piece in chunks(row["text"], row["start"], row["end"]):
            lines.append(f"Dialogue: 0,{ts(a)},{ts(b)},Cap,,0,0,0,,{rtl(piece)}")
    for c in cards:
        lines.append(f"Dialogue: 1,{ts(c.start)},{ts(c.end)},Card,,0,0,0,,{{\\fad(250,200)}}{rtl(c.text)}")
    if end_card and timeline:
        closing = [r for r in timeline if r["section"] == last_section]
        logo_in = closing[0]["start"]
        cta_in = closing[-1]["start"] if len(closing) > 1 else logo_in + 1.0
        x = width // 2
        y = lambda v: int(v * height / 1920)  # noqa: E731
        lines += [
            f"Dialogue: 1,{ts(logo_in)},{ts(total)},Logo,,0,0,0,,{{\\pos({x},{y(700)})\\fad(400,0)}}{rtl(end_card.title)}",
            f"Dialogue: 1,{ts(logo_in + 0.6)},{ts(total)},Tag,,0,0,0,,{{\\pos({x},{y(900)})\\fad(400,0)}}{rtl(end_card.tagline)}",
            f"Dialogue: 1,{ts(cta_in)},{ts(total)},Cta,,0,0,0,,{{\\pos({x},{y(1180)})\\fad(300,0)}}{rtl(end_card.cta)}",
        ]
        if end_card.sub:
            lines.append(
                f"Dialogue: 1,{ts(cta_in + 0.8)},{ts(total)},Tag,,0,0,0,,"
                f"{{\\pos({x},{y(1340)})\\fs{int(46 * height / 1920)}\\fad(300,0)}}{rtl(end_card.sub)}"
            )
    return "\n".join(lines) + "\n"
