"""Automatic listening check for generated voice (speech-to-text).

Catches what went wrong in practice:
- spoken instructions: English words that are not in the script, or speech
  that is too slow for the amount of text (extra words were read);
- skipped lines: low word coverage.
Uses faster-whisper on the CPU.
"""

import re
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from pathlib import Path

_ARABIC_DIACRITICS = re.compile(r"[ً-ْـ]")  # tashkeel + tatweel
_NON_WORD = re.compile(r"[^\w\s]")


def normalize(word: str) -> str:
    """Loose Arabic normalisation so ASR spelling noise does not count."""
    w = _ARABIC_DIACRITICS.sub("", word)
    w = _NON_WORD.sub("", w)
    for a, b in (
        ("أ", "ا"),
        ("إ", "ا"),
        ("آ", "ا"),
        ("ة", "ه"),
        ("ى", "ي"),
        ("گ", "ك"),
        ("چ", "ج"),
        ("پ", "ب"),
        ("ڤ", "ف"),
    ):
        w = w.replace(a, b)
    return w.lower()


def similar(a: str, b: str) -> bool:
    """Loose match for Whisper's spelling of Iraqi Arabic (merged words,
    dropped or swapped letters): equal, one contains the other, or ≥ 75 %."""
    if not a or not b:
        return False
    if a == b or (min(len(a), len(b)) >= 3 and (a in b or b in a)):
        return True
    return SequenceMatcher(None, a, b).ratio() >= 0.75


# Spoken instructions are whole sentences; a brand name or two ("Google
# Play" for "گوگل بلي") is not. Flag English from this many words up.
MIN_UNEXPECTED_LATIN = 3


def latin_words(words: list[str]) -> list[str]:
    return [w for w in words if re.search(r"[A-Za-z]", w)]


# Share of script words heard (loose matching). Per line as well: a skipped
# short line barely moves the whole-section figure (24 words − 3 = 87 %).
MIN_COVERAGE = 0.6
MIN_LINE_COVERAGE = 0.5

# Letters of script per second of speech. Measured on this project's takes:
# clean takes 9.0–11.7, takes that also read their instructions 3.6–7.3.
# Below this, something besides the script was spoken.
MIN_LETTERS_PER_SECOND = 8.0


def letters(text: str) -> int:
    return len(re.findall(r"\w", text))


@dataclass
class Report:
    heard: list[str]
    unexpected_latin: list[str] = field(default_factory=list)
    coverage: float = 0.0  # share of script words that were heard
    missing: list[str] = field(default_factory=list)
    rate: float | None = None  # script letters per second of speech
    line_coverage: list[float] = field(default_factory=list)  # one per script line

    @property
    def skipped_lines(self) -> list[int]:
        """Lines (0-based) of which too little was heard: likely skipped."""
        return [i for i, c in enumerate(self.line_coverage) if c < MIN_LINE_COVERAGE]

    @property
    def too_slow(self) -> bool:
        return self.rate is not None and self.rate < MIN_LETTERS_PER_SECOND

    @property
    def ok(self) -> bool:
        return (
            len(self.unexpected_latin) < MIN_UNEXPECTED_LATIN
            and self.coverage >= MIN_COVERAGE
            and not self.skipped_lines
            and not self.too_slow
        )


def compare(script: str, heard: list[str], speech_seconds: float | None = None) -> Report:
    """Compare what should be said with what was heard.

    `script` may hold several lines (one per newline); each line is also
    scored on its own so a skipped line is caught. Whisper's Iraqi-Arabic
    spelling is imperfect, so matching is loose (`similar`).
    """
    script_words = [w for w in script.split() if normalize(w)]
    allowed_latin = {normalize(w) for w in latin_words(script_words)}
    heard_norm = [normalize(w) for w in heard]

    def is_heard(w: str) -> bool:
        return any(similar(normalize(w), h) for h in heard_norm)

    found = [is_heard(w) for w in script_words]
    line_coverage = []
    for line in script.splitlines():
        words = [w for w in line.split() if normalize(w)]
        if words:
            line_coverage.append(sum(is_heard(w) for w in words) / len(words))
    hits = [w for w, f in zip(script_words, found) if f]
    missing = [w for w, f in zip(script_words, found) if not f]
    extra_latin = [w for w in latin_words(heard) if normalize(w) not in allowed_latin]
    return Report(
        heard=heard,
        unexpected_latin=extra_latin,
        coverage=len(hits) / len(script_words) if script_words else 1.0,
        missing=missing,
        rate=letters(script) / speech_seconds if speech_seconds else None,
        line_coverage=line_coverage,
    )


def transcribe(path: Path) -> list[tuple[float, float, str]]:
    """(start, end, word) for every recognised word."""
    import librosa  # heavy imports kept local
    from faster_whisper import WhisperModel

    model = _model(WhisperModel)
    audio, _ = librosa.load(str(path), sr=16000, mono=True)
    segments, _ = model.transcribe(audio, word_timestamps=True, condition_on_previous_text=False)
    return [(w.start, w.end, w.word.strip()) for s in segments for w in s.words]


_MODEL = None


def _model(cls):
    global _MODEL
    if _MODEL is None:
        _MODEL = cls("small", device="cpu", compute_type="int8")
    return _MODEL


def speech_seconds(path: Path) -> float:
    """Duration minus silences: the time actually spent talking."""
    from .media import duration, silences

    total = duration(path)
    return total - sum(min(end, total) - start for start, end in silences(path, -40, 0.15))


def check_audio(path: Path, script: str) -> Report:
    return compare(script, [w for _, _, w in transcribe(path)], speech_seconds(path))
