#!/usr/bin/env bash
# The local gate: run before every push. Exits non-zero on the first failure.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== core tests";      (cd Packages/GameReadyCore && swift test 2>&1 | tail -1)
echo "== strings";         python3 tools/gen_strings.py --check
echo "== diagram";         python3 tools/gen_diagram.py --check
echo "== shell";           bash -n scripts/*.sh && { command -v shellcheck >/dev/null && shellcheck -S warning scripts/*.sh || true; }
echo "== build";           scripts/build.sh >/dev/null && echo "build ok"
echo "CHECK: PASS"
