import io
import json
import urllib.error

import pytest

from studio import tts
from studio.media import duration


def http_429(daily: bool) -> urllib.error.HTTPError:
    quota = "GenerateRequestsPerDayPerProjectPerModel-FreeTier" if daily else "PerMinute"
    body = json.dumps({"error": {"details": [{"violations": [{"quotaId": quota}]}]}}).encode()
    return urllib.error.HTTPError("u", 429, "Too Many Requests", {}, io.BytesIO(body))


ONE_SECOND_PCM = b"\x00\x00" * 24000


def test_falls_through_to_next_model_on_daily_quota(tmp_path, monkeypatch):
    calls = []

    def fake(model, text, voice):
        calls.append(model)
        if model == "m1":
            raise http_429(daily=True)
        return ONE_SECOND_PCM

    monkeypatch.setattr(tts, "_request", fake)
    out = tmp_path / "a.wav"
    used = tts.synthesize("هلا", out, models=("m1", "m2"))
    assert used == "m2"
    assert calls == ["m1", "m2"]
    assert abs(duration(out) - 1.0) < 0.05


def test_raises_when_every_model_is_exhausted(tmp_path, monkeypatch):
    monkeypatch.setattr(tts, "_request", lambda *a: (_ for _ in ()).throw(http_429(daily=True)))
    with pytest.raises(tts.QuotaExhausted):
        tts.synthesize("هلا", tmp_path / "a.wav", models=("m1", "m2"))


def test_short_rate_limit_is_retried_on_same_model(tmp_path, monkeypatch):
    attempts = {"n": 0}

    def fake(model, text, voice):
        attempts["n"] += 1
        if attempts["n"] == 1:
            raise http_429(daily=False)
        return ONE_SECOND_PCM

    monkeypatch.setattr(tts, "_request", fake)
    monkeypatch.setattr(tts.time, "sleep", lambda s: None)
    assert tts.synthesize("هلا", tmp_path / "a.wav", models=("m1",)) == "m1"
    assert attempts["n"] == 2


def test_only_the_words_are_sent(monkeypatch):
    # Lesson learned: no style direction in the text, or it gets spoken.
    sent = {}

    class Resp(io.BytesIO):
        pass

    def fake_urlopen(req, timeout):
        sent.update(json.loads(req.data))
        payload = {"candidates": [{"content": {"parts": [{"inlineData": {"data": ""}}]}}]}
        return Resp(json.dumps(payload).encode())

    monkeypatch.setattr(tts.urllib.request, "urlopen", fake_urlopen)
    tts._request("m", "تدري؟ كل قطعة بيها روح.", "Leda")
    assert sent["contents"][0]["parts"][0]["text"] == "تدري؟ كل قطعة بيها روح."
    assert "systemInstruction" not in sent


def test_no_audio_in_response_is_a_clear_error(monkeypatch):
    def fake_urlopen(req, timeout):
        payload = {"candidates": [{"finishReason": "SAFETY"}]}
        return io.BytesIO(json.dumps(payload).encode())

    monkeypatch.setattr(tts.urllib.request, "urlopen", fake_urlopen)
    with pytest.raises(RuntimeError, match="SAFETY"):
        tts._request("m", "نص", "Leda")


def test_failed_conversion_leaves_no_take_behind(tmp_path, monkeypatch):
    monkeypatch.setattr(tts, "_request", lambda *a: ONE_SECOND_PCM)

    def broken_run(*a, **k):
        (tmp_path / "a.part.wav").write_bytes(b"half")
        raise tts.subprocess.CalledProcessError(1, "ffmpeg")

    monkeypatch.setattr(tts.subprocess, "run", broken_run)
    with pytest.raises(tts.subprocess.CalledProcessError):
        tts.synthesize("هلا", tmp_path / "a.wav", models=("m1",))
    assert not (tmp_path / "a.wav").exists()
