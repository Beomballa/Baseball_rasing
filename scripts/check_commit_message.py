#!/usr/bin/env python3
"""Validate the repository's date-based commit subject without rewriting it."""
from datetime import datetime
from pathlib import Path
import re
import sys


def valid_subject(subject: str) -> bool:
    match = re.fullmatch(r"(\d{4}\.\d{2}\.\d{2}) (\S(?:.*\S)?) 작업 수행", subject)
    if not match:
        return False
    try:
        datetime.strptime(match[1], "%Y.%m.%d")
    except ValueError:
        return False
    return True


def main() -> int:
    lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
    if not lines or not valid_subject(lines[0]):
        print("커밋 제목 형식: YYYY.MM.DD 구체적인 기능 작업 수행", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
