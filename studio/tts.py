"""Gemini text-to-speech.

Lesson learned: the newer TTS models read *any* direction placed in the
request text aloud ("Say warmly…" was spoken in English). So we send the
words to speak and nothing else; tone comes from punctuation. The automatic
check in `check.py` still verifies every take.
"""

import base64
import json
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

from . import config


class QuotaExhausted(RuntimeError):
    """Every TTS model hit its daily free-tier limit."""


def _request(model: str, text: str, voice: str) -> bytes:
    body = {
        "contents": [{"parts": [{"text": text}]}],
        "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": voice}}},
        },
    }
    req = urllib.request.Request(
        config.GEMINI_ENDPOINT.format(model=model),
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "x-goog-api-key": config.GEMINI_KEY_PLACEHOLDER},
    )
    data = json.load(urllib.request.urlopen(req, timeout=300))
    try:
        part = data["candidates"][0]["content"]["parts"][0]["inlineData"]["data"]
    except (KeyError, IndexError) as e:
        reason = (data.get("candidates") or [{}])[0].get("finishReason") or data.get("promptFeedback")
        raise RuntimeError(f"{model} returned no audio (reason: {reason})") from e
    return base64.b64decode(part)  # 24 kHz mono s16le PCM


def is_daily_quota(err: urllib.error.HTTPError) -> bool:
    try:
        body = json.loads(err.read())
    except (ValueError, OSError):
        return False
    return "PerDay" in json.dumps(body)


def synthesize(text: str, out: Path, voice: str = config.DEFAULT_VOICE, models: tuple[str, ...] = config.TTS_MODELS) -> str:
    """Speak `text` into `out` (wav). Returns the model used.

    Falls through to the next model on a daily quota; waits and retries on a
    short-term rate limit.
    """
    tmp = out.with_name(out.stem + ".part.wav")
    for model in models:
        for attempt in range(4):
            try:
                pcm = _request(model, text, voice)
            except urllib.error.HTTPError as e:
                if e.code == 429 and is_daily_quota(e):
                    break  # next model
                if e.code in (429, 500, 503) and attempt < 3:
                    time.sleep(15 * (attempt + 1))
                    continue
                raise
            subprocess.run(
                [
                    "ffmpeg",
                    "-y",
                    "-v",
                    "error",
                    "-f",
                    "s16le",
                    "-ar",
                    "24000",
                    "-ac",
                    "1",
                    "-i",
                    "-",
                    str(tmp),
                ],
                input=pcm,
                check=True,
            )
            tmp.replace(out)  # never leave a half-written take behind
            return model
    raise QuotaExhausted("All TTS models are out of daily quota; try again tomorrow.")
