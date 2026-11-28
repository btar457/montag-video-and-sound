from studio.check import MIN_COVERAGE, MIN_LETTERS_PER_SECOND, compare, letters, normalize

SCRIPT = "إنت حرفي؟ تسوي أعمال يدوية؟ تعبك يستاهل ينشاف!"


def test_normalize_ignores_diacritics_hamza_and_iraqi_letters():
    assert normalize("الحِرْفة") == normalize("الحرفه")
    assert normalize("إنت") == normalize("انت")
    assert normalize("تلگه") == normalize("تلكه")
    assert normalize("ينشاف!") == "ينشاف"


def test_clean_take_passes():
    heard = ["انت", "حرفي", "تسوي", "اعمال", "يدوية", "تعبك", "يستاهل", "ينشاف"]
    r = compare(SCRIPT, heard)
    assert r.ok
    assert r.coverage == 1.0
    assert r.missing == []


def test_spoken_english_instructions_fail():
    # What actually happened: the TTS read its style direction aloud.
    heard = [
        "as",
        "a",
        "young",
        "woman",
        "from",
        "Baghdad",
        "انت",
        "حرفي",
        "تسوي",
        "اعمال",
        "يدوية",
        "تعبك",
        "يستاهل",
        "ينشاف",
    ]
    r = compare(SCRIPT, heard)
    assert not r.ok
    assert "Baghdad" in r.unexpected_latin


def test_whisper_spelling_noise_still_counts_as_heard():
    # Real: "كل قطعة مسوّاية بالإيد بيها روح" was heard as below.
    r = compare(
        "تدري؟ كل قطعة مسوّاية بالإيد بيها روح… وبيها قصة.",
        ["هل", "تدري؟", "كل", "قطعم", "سواية", "بالإيد", "بها", "روح", "وبها", "قصة"],
    )
    assert r.coverage >= 0.8
    assert r.ok


def test_a_brand_name_in_english_is_not_instructions():
    # Real: "گوگل بلي" in the script was heard as "Google Play".
    r = compare("نزّله هسه من گوگل بلي", ["نزله", "هسه", "من", "Google", "Play"])
    assert r.unexpected_latin == ["Google", "Play"]
    assert r.ok


def test_latin_words_in_the_script_are_allowed():
    r = compare("نزّله من Google Play", ["نزله", "من", "Google", "Play"])
    assert r.ok
    assert r.unexpected_latin == []


def test_skipped_line_lowers_coverage():
    # What actually happened: "تعبك يستاهل ينشاف!" was skipped once.
    long_script = SCRIPT + " لوحة تحكم سهلة وسلسة تضيف منتجك بدقيقة وتتابع طلباتك"
    r = compare(long_script, ["انت", "حرفي", "تسوي"])
    assert not r.ok
    assert "ينشاف!" in r.missing


def test_empty_script_is_trivially_covered():
    assert compare("", []).coverage == 1.0


# Real measurements from the Al-Hirfa ad (letters, seconds of speech).
SECTION_5 = "«الحرفة»… من إيد الحرفي العراقي لبيتك. نزّله هسه من گوگل بلي، وادعم ابن بلدك."
SECTION_5_WORDS = ["الحرفة", "من", "ايد", "الحرفي", "العراقي", "لبيتك", "نزله", "هسه", "من", "كوكل", "بلي", "وادعم", "ابن", "بلدك"]


def test_letters_counts_word_characters_only():
    assert letters("هلا، بيكم!") == 7
    assert letters(SECTION_5) == 57


def test_clean_take_speed_passes():
    r = compare(SECTION_5, SECTION_5_WORDS, speech_seconds=5.9)  # 9.7 letters/s
    assert r.rate > MIN_LETTERS_PER_SECOND
    assert r.ok


def test_take_with_spoken_instructions_is_too_slow():
    # Same words were heard, but 16 s of speech: instructions were read too
    # (in mangled Arabic, so no English words gave it away).
    r = compare(SECTION_5, SECTION_5_WORDS, speech_seconds=16.0)  # 3.6 letters/s
    assert r.too_slow
    assert not r.ok


def test_worst_measured_bad_take_is_caught():
    r = compare("x" * 174, [], speech_seconds=23.8)  # section 4 raw: 7.3 letters/s
    assert r.too_slow


def test_rate_is_optional():
    r = compare(SCRIPT, ["انت", "حرفي", "تسوي", "اعمال", "يدوية", "تعبك", "يستاهل", "ينشاف"])
    assert r.rate is None and r.ok


# Real: the first take of section 2 skipped its last line. This is what was
# heard (transcribed from that take).
SECTION_2 = (
    "إنت حرفي؟ تسوي أعمال يدوية؟\n"
    "تنقش على النحاس والحجر؟ تصوغ ذهب وفضة، أو تشتغل على الأحجار الكريمة؟\n"
    "تخيط، تطرّز، تسوي فخار وخوص…\n"
    "تعبك يستاهل ينشاف!"
)
SECTION_2_SKIPPED_TAKE = (
    "انت حرفي؟ تسوي أعمال يدوية؟ تنقش ع النحاس والحجر؟ تصوغ ذهب وفضة؟ أو تشتغل ع الأحجار الكريمة؟ تخيط؟ تطرز؟ تسوي فخار وخوص؟"
).split()
SECTION_2_FULL_TAKE = SECTION_2_SKIPPED_TAKE + ["تعبك", "يستاهل", "ينشاف"]


def test_real_skipped_last_line_is_caught():
    r = compare(SECTION_2, SECTION_2_SKIPPED_TAKE)
    assert r.coverage >= MIN_COVERAGE  # the whole-section check alone would let it through
    assert r.skipped_lines == [3]
    assert not r.ok


def test_real_full_take_passes_line_by_line():
    r = compare(SECTION_2, SECTION_2_FULL_TAKE)
    assert r.skipped_lines == []
    assert r.ok


def test_speech_seconds_ignores_inner_and_trailing_silence(tmp_path):
    from studio.check import speech_seconds
    from studio.media import ff

    wav = tmp_path / "t.wav"
    # 1 s tone, 1 s silence, 1 s tone, 1 s trailing silence → 2 s of speech.
    ff(
        "-f",
        "lavfi",
        "-i",
        "sine=f=300:r=24000:d=1",
        "-f",
        "lavfi",
        "-i",
        "anullsrc=r=24000:cl=mono:d=1",
        "-filter_complex",
        "[0][1][0][1]concat=n=4:v=0:a=1",
        str(wav),
    )
    assert abs(speech_seconds(wav) - 2.0) < 0.15


def test_rate_threshold_boundaries():
    slowest_clean = compare("x" * 90, [], speech_seconds=10.0)  # 9.0 letters/s (real minimum)
    fastest_bad = compare("x" * 73, [], speech_seconds=10.0)  # 7.3 letters/s (real maximum)
    assert not slowest_clean.too_slow
    assert fastest_bad.too_slow
