"""Montage studio: turn a written script into a finished vertical video.

Pipeline: script (project.json) → voiceover (Gemini TTS, voice Leda) →
automatic check (speech-to-text) → captions + cards → ffmpeg render.
"""
