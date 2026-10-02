#!/usr/bin/env python3
"""Build App/Resources/Localizable.xcstrings from tools/strings.py.

  python3 tools/gen_strings.py          # write the catalogue
  python3 tools/gen_strings.py --check  # fail if stale, or if a code has no string
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from strings import S  # noqa: E402

OUT = ROOT / "App/Resources/Localizable.xcstrings"
CORE = ROOT / "Packages/GameReadyCore/Sources/GameReadyCore"
APP = ROOT / "App/Sources"


def enum_cases(path: pathlib.Path, name: str) -> list[str]:
    text = path.read_text()
    body = re.search(r"enum %s\b[^{]*\{(.*?)\n\}" % name, text, re.S).group(1)
    cases = []
    for line in body.splitlines():
        line = line.split("//")[0].strip()
        # Declarations only: "case a, b" or "case a = 1". Skips `switch` arms ("case .a:").
        if line.startswith("case ") and re.fullmatch(r"case [a-z][A-Za-z0-9]*( *= *[^,]+)?(, *[a-z][A-Za-z0-9]*( *= *[^,]+)?)*,?", line):
            cases += [c.strip().split("=")[0].strip() for c in line[5:].split(",") if c.strip()]
        elif cases and line.endswith(",") is False and re.fullmatch(r"[a-z][A-Za-z0-9]*(, *[a-z][A-Za-z0-9]*)*", line):
            cases += [c.strip() for c in line.split(",")]   # continuation line
    return cases


def required_keys() -> set[str]:
    keys = set()
    keys |= {f"check.{c}" for c in enum_cases(CORE / "Checks.swift", "CheckID")}
    keys |= {f"finding.{c}" for c in enum_cases(CORE / "Checks.swift", "Finding")}
    for v in enum_cases(CORE / "Verdict.swift", "VerdictLevel"):
        keys |= {f"verdict.{v}.title", f"verdict.{v}.subtitle"}
    keys |= {f"grade.{c}" for c in enum_cases(CORE / "Grade.swift", "Grade")}
    keys |= {f"event.{c}" for c in enum_cases(CORE / "LiveWatch.swift", "LiveEventKind")}
    keys |= {f"layer.{c}" for c in enum_cases(CORE / "LiveWatch.swift", "Layer")}
    keys |= {f"step.{c}" for c in enum_cases(APP / "Model/AppModel.swift", "Step")}
    for i in enum_cases(APP / "Model/Checklist.swift", "Item"):
        keys |= {f"checklist.{i}.title", f"checklist.{i}.help"}
    # Literal L("…") calls anywhere in the app.
    for f in APP.rglob("*.swift"):
        keys |= set(re.findall(r'\bL\("([a-z][A-Za-z0-9_.]+)"\)', f.read_text()))
    return keys


def build() -> str:
    strings = {}
    for key in sorted(S):
        en, it = S[key]
        strings[key] = {
            "extractionState": "manual",
            "localizations": {
                "en": {"stringUnit": {"state": "translated", "value": en}},
                "it": {"stringUnit": {"state": "needs_review", "value": it}},
            },
        }
    return json.dumps({"sourceLanguage": "en", "strings": strings, "version": "1.0"},
                      indent=2, ensure_ascii=False, sort_keys=True) + "\n"


def main() -> int:
    missing = sorted(required_keys() - S.keys())
    if missing:
        print("missing strings:", ", ".join(missing))
        return 1
    text = build()
    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text() != text:
            print("Localizable.xcstrings is stale: run python3 tools/gen_strings.py")
            return 1
        print(f"strings ok ({len(S)} keys)")
        return 0
    OUT.write_text(text)
    print(f"wrote {OUT.relative_to(ROOT)} ({len(S)} keys)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
