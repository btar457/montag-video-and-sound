"""Command line:

python -m studio voice  projects/<name>   # generate + check voiceover
python -m studio render projects/<name>   # assemble the final video
python -m studio check  <audio> "<text>"  # listening check of any take
"""

import argparse
import sys
from pathlib import Path

from .project import Project


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="studio")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("voice", "render"):
        sp = sub.add_parser(name)
        sp.add_argument("project", type=Path)
    ck = sub.add_parser("check")
    ck.add_argument("audio", type=Path)
    ck.add_argument("text")
    args = p.parse_args(argv)

    if args.cmd == "voice":
        from .voiceover import build

        build(Project.load(args.project))
    elif args.cmd == "render":
        from .render import render

        render(Project.load(args.project))
    else:
        from .check import check_audio

        r = check_audio(args.audio, args.text)
        rate = f"{r.rate:.1f} letters/s" + (" (too slow: extra speech?)" if r.too_slow else "") if r.rate else "n/a"
        print(f"coverage {r.coverage:.0%}; speed {rate}; unexpected English: {r.unexpected_latin or 'none'}")
        if r.skipped_lines:
            print("lines not heard:", [i + 1 for i in r.skipped_lines])
        print("heard:", " ".join(r.heard))
        return 0 if r.ok else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
