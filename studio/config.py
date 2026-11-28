"""Studio defaults. Change here, not in project files, to change house style."""

# Approved narrator voice (Gemini prebuilt voice).
DEFAULT_VOICE = "Leda"

# Tried in order; each free-tier model allows ~10 requests per day, so the
# next one is used when one is exhausted.
TTS_MODELS = (
    "gemini-3.8-flash-tts",
    "gemini-3.8-flash-lite-tts",
    "gemini-3.1-flash-tts-preview",
)

GEMINI_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
# The environment's network proxy injects the real key into this header.
# Never put a real key here or anywhere in the repo.
GEMINI_KEY_PLACEHOLDER = "injected-by-proxy"

# Output frame.
WIDTH, HEIGHT, FPS = 1080, 1920, 30

# Voiceover assembly.
SECTION_GAP = 0.55  # seconds of silence between script sections
LOUDNESS = "I=-16:TP=-1.5:LRA=9"  # social-media loudness target

# Captions.
FONT_BODY = "Noto Sans Arabic"
FONT_TITLE = "Noto Kufi Arabic"
GOLD = "&H0037AFD4"  # ASS colour (BGR) for #D4AF37
CAPTION_MAX_WORDS = 4
