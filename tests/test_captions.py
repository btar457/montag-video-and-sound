from studio.captions import PDF, RLE, build_ass, chunks, rtl, ts
from studio.project import Card, EndCard


def test_ts_format():
    assert ts(0) == "0:00:00.00"
    assert ts(61.856) == "0:01:01.86"
    assert ts(-1) == "0:00:00.00"


def test_chunks_cover_the_line_in_order():
    parts = list(chunks("واحد اثنين ثلاثة أربعة خمسة ستة سبعة ثمانية", 10.0, 14.0))
    assert [p[2] for p in parts] == ["واحد اثنين ثلاثة أربعة", "خمسة ستة سبعة ثمانية"]
    assert parts[0][0] == 10.0
    assert abs(parts[-1][1] - 14.0) < 1e-9
    assert all(a[1] == b[0] for a, b in zip(parts, parts[1:]))


def test_no_single_word_orphan_with_two_groups():
    # Regression: 5 words → [4, 1]; merging the orphan used to crash.
    parts = list(chunks("تعبك يستاهل ينشاف هواية والله", 0, 2))
    assert len(parts) == 1
    assert parts[0][2] == "تعبك يستاهل ينشاف هواية والله"


def test_empty_line_yields_nothing():
    assert list(chunks("   ", 0, 1)) == []


def test_rtl_wraps_text():
    assert rtl("حمّل الآن من Google Play") == f"{RLE}حمّل الآن من Google Play{PDF}"


TIMELINE = [
    {"section": 1, "start": 0.0, "end": 2.0, "text": "تدري؟ كل قطعة بيها روح."},
    {"section": 2, "start": 2.5, "end": 4.0, "text": "«الحرفة»… من إيد الحرفي لبيتك."},
    {"section": 2, "start": 4.0, "end": 6.0, "text": "نزّله هسه من Google Play."},
]


def test_ass_has_rtl_captions_cards_and_end_card():
    ass = build_ass(
        TIMELINE,
        [Card(1.0, 2.0, "التحميل مجاني")],
        EndCard("الحرفة", "شعار", "حمّل الآن من Google Play", "وادعم"),
        total=8.6,
    )
    events = [ln for ln in ass.splitlines() if ln.startswith("Dialogue:")]
    caps = [e for e in events if ",Cap," in e]
    # Last section is shown by the end card, not as captions.
    assert caps and all("Google" not in e for e in caps)
    assert all(RLE in e and PDF in e for e in events)
    assert any(",Card," in e and "التحميل مجاني" in e for e in events)
    cta = next(e for e in events if ",Cta," in e)
    assert "0:00:04.00" in cta and "0:00:08.60" in cta
    assert "Fontname" in ass and "PlayResX: 1080" in ass


def test_without_end_card_every_line_is_captioned():
    ass = build_ass(TIMELINE, [], None, total=6.0)
    caps = [ln for ln in ass.splitlines() if ",Cap," in ln]
    assert any("Google" in c for c in caps)
    assert not any(",Logo," in ln for ln in ass.splitlines())


def test_styles_scale_with_resolution():
    small = build_ass(TIMELINE, [], None, total=6.0, width=216, height=384)
    assert "PlayResY: 384" in small
    cap_style = next(ln for ln in small.splitlines() if ln.startswith("Style: Cap"))
    assert ",16," in cap_style  # 80 * 384/1920
