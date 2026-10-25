# One entry point for the checks CI runs. `make check` before every push.
APP := build/dd/Build/Products/Release/Game Ready.app

.PHONY: check test strings diagram build screenshots social-preview

check: ## Everything CI checks (core tests, strings, diagram, shell lint, Release build)
	scripts/check.sh

test: ## The core test suite
	cd Packages/GameReadyCore && swift test

strings: ## Regenerate the string catalogue from tools/strings/*.json
	python3 tools/gen_strings.py

diagram: ## Redraw docs/assets/architecture-*.svg
	python3 tools/gen_diagram.py

build: ## Release build and dist/Game-Ready.zip
	scripts/build.sh

screenshots: build ## Retake docs/assets/screenshots/ from the app's demo data, metadata stripped
	"$(APP)/Contents/MacOS/Game Ready" --screenshots docs/assets/screenshots
	python3 tools/strip_png.py docs/assets/screenshots/*.png

social-preview: ## Redraw docs/assets/social-preview.png (needs Google Chrome)
	tools/social-preview.sh
