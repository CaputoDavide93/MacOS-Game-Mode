#!/usr/bin/env python3
"""Build App/Resources/Localizable.xcstrings from tools/strings/<lang>.json.

  python3 tools/gen_strings.py          # write the catalogue
  python3 tools/gen_strings.py --check  # fail if stale, a code has no string, or a
                                        # translation is missing a key or a placeholder

en.json is the source. Every other language must have exactly the same keys and the same
placeholders (%@, %lld) in each string. Translations other than English are marked
"needs_review" until a native speaker has checked them.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
STRINGS = ROOT / "tools/strings"
LANGS = ["en", "it", "es", "fr", "de", "pt-BR", "ja", "zh-Hans", "ko", "hi"]
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:@|lld|ld|d|s|f)")


def load() -> dict[str, dict[str, str]]:
    out = {}
    for lang in LANGS:
        path = STRINGS / f"{lang}.json"
        if path.exists():
            out[lang] = json.loads(path.read_text(encoding="utf-8"))
    return out


TABLES = load()
S = TABLES["en"]

OUT = ROOT / "App/Resources/Localizable.xcstrings"
CORE = ROOT / "Packages/GameReadyCore/Sources/GameReadyCore"
APP = ROOT / "App/Sources"


def enum_cases(path: pathlib.Path, name: str) -> list[str]:
    text = path.read_text()
    # Stop at the closing brace with the enum's own indentation (enums can be nested).
    m = re.search(r"^([ \t]*)(?:public |private |fileprivate |internal )?enum %s\b[^{]*\{" % name, text, re.M)
    indent = m.group(1)
    end = re.search(r"\n%s\}" % re.escape(indent), text[m.end():])
    body = text[m.end():m.end() + end.start()]
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


def problems() -> list[str]:
    out = []
    for lang, table in TABLES.items():
        if lang == "en":
            continue
        missing, extra = S.keys() - table.keys(), table.keys() - S.keys()
        if missing: out.append(f"{lang}: missing {sorted(missing)}")
        if extra: out.append(f"{lang}: unknown keys {sorted(extra)}")
        for key in S.keys() & table.keys():
            if sorted(PLACEHOLDER.findall(S[key])) != sorted(PLACEHOLDER.findall(table[key])):
                out.append(f"{lang}: placeholders differ in {key}")
            if not table[key].strip():
                out.append(f"{lang}: empty {key}")
    return out


def build() -> str:
    strings = {}
    for key in sorted(S):
        locs = {}
        for lang, table in TABLES.items():
            if key in table:
                state = "translated" if lang == "en" else "needs_review"
                locs[lang] = {"stringUnit": {"state": state, "value": table[key]}}
        strings[key] = {"extractionState": "manual", "localizations": locs}
    return json.dumps({"sourceLanguage": "en", "strings": strings, "version": "1.0"},
                      indent=2, ensure_ascii=False, sort_keys=True) + "\n"


def main() -> int:
    missing = sorted(required_keys() - S.keys())
    if missing:
        print("missing strings:", ", ".join(missing))
        return 1
    bad = problems()
    if bad:
        print("translation problems:\n  " + "\n  ".join(bad))
        return 1
    text = build()
    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text() != text:
            print("Localizable.xcstrings is stale: run python3 tools/gen_strings.py")
            return 1
        print(f"strings ok ({len(S)} keys x {len(TABLES)} languages)")
        return 0
    OUT.write_text(text)
    print(f"wrote {OUT.relative_to(ROOT)} ({len(S)} keys)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
