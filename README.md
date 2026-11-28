# استوديو المونتاج

نص مكتوب ← صوت راوية عراقي (Leda) ← فحص سمعي آلي ← ترجمة وبطاقات ← فيديو 9:16 جاهز للنشر.

```bash
pip install faster-whisper librosa pytest ruff   # + ffmpeg مع libass و fonts-noto-core
python -m studio voice  projects/alhirfa-ad
python -m studio render projects/alhirfa-ad
python -m pytest -q
```

التفاصيل في `docs/architecture.md`، وخطوات صناعة إعلان في `.claude/skills/make-ad/SKILL.md`.
