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

social-preview: ## Redraw docs/assets/social-preview.png in the shared layout (needs Google Chrome and Pillow)
	python3 tools/brand/brand_kit.py social --name "Game Ready" --tagline "Check your Mac, Wi-Fi and internet before cloud gaming, and find what causes the lag" \
		--chip "macOS 15+" --chip "Apple silicon" --chip "Free, MIT" --chip "Private by design" \
		--icon docs/assets/brand/icon.png --hue 170 --out docs/assets/social-preview.png
