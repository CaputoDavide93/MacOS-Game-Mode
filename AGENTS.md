# Agent instructions

This repository follows Davide Caputo's house standards. The full spec is
[`reference/STYLE.md` in repo-standards](https://github.com/CaputoDavide93/repo-standards/blob/main/reference/STYLE.md)
(private). When this summary and the spec disagree, the spec wins.

## Rules that apply to every change

- **Documentation never lies.** Every command, flag, feature, count and badge must be true of the code. Verify before writing; delete what you can't verify. No hand-typed counts that can drift.
- **Commits:** conventional (`fix:`, `feat:`, `docs:`, `refactor:`, `ci:`, `chore:`), authored by the repo owner. **Never** add `Co-Authored-By`, `Claude-Session`, "Generated with …" or any other AI attribution — not in commits, PR bodies, issues or comments.
- **Never** force-push the default branch, commit secrets, or change runtime identifiers (env var names, container/image names, bundle IDs, entity IDs, public URLs) as a side effect.
- Run the repo's own checks (tests, lint, build, `python3 tools/gen_diagram.py --check`) before and after; anything green before stays green.
- **Apps** also follow [`reference/APPS.md`](https://github.com/CaputoDavide93/repo-standards/blob/main/reference/APPS.md): private by design, copy in ARB/strings files (never hard-coded), theme tokens only, light and dark, 2× text, the security baseline, failing-first regression tests, and nothing in docs or store listings the code doesn't back. The free version is never limited. Every app has a public privacy policy and contact page (its own `<app>-site` repo on GitHub Pages, from `assets/app/site/`), linked from Settings, and an in-app Philosophy page (APPS.md §15). The only contact address is caputodav@gmail.com. Apps for children under about 5 also follow [`reference/KIDS.md`](https://github.com/CaputoDavide93/repo-standards/blob/main/reference/KIDS.md): check every feature against it and the app's `docs/research.md`; nothing leaves the device; nothing plays by itself for babies; no "approved" or developmental claims.
- **Real iPhones through another Mac** (a newer iOS than your Xcode, or the phone is plugged in elsewhere): follow [`reference/IOS-REMOTE-BUILD.md`](https://github.com/CaputoDavide93/repo-standards/blob/main/reference/IOS-REMOTE-BUILD.md). SSH with a key only, never a password; committed code only; ask the owner for the steps only they can do.
- **Real Android phones through another Mac:** follow [`reference/ANDROID-REMOTE-INSTALL.md`](https://github.com/CaputoDavide93/repo-standards/blob/main/reference/ANDROID-REMOTE-INSTALL.md). Build from a clean commit, check the permissions with `aapt2 dump badging`, install with `install-on-android.sh`; never uninstall someone's copy without asking.

## README

- Centered header: one emoji H1 (the same emoji as the GitHub description), a **bold** one-line tagline, flat shields.io badges (tech → platform → license → live CI; no `style=`), then `---`.
- Emoji `##` headings in the canonical order, `---` between sections, features as an emoji-lead table, a repo tree in a ` ```text ` block that matches `git ls-files`.
- `## 🗺️ Architecture` opens with the house-kit diagram: `tools/gen_diagram.py` writes `docs/assets/architecture-{light,dark}.svg`, embedded with `<picture>` (dark `<source>` + light `<img width="100%">` + a one-sentence alt). No Mermaid for architecture, no ASCII boxes.
- Screenshots live in `docs/assets/screenshots/<screen>-{light,dark}.png`; public repos use demo data only.
- The README ends with `---` and then exactly:
  `<p align="center"><sub>Made with ❤️ by <a href="https://github.com/CaputoDavide93">Davide Caputo</a></sub></p>`
  (translated only when the README body is in another language). No star request, no extra lines.

## Layout and naming

- Directories `lowercase-kebab`; docs `docs/lowercase-kebab.md`; shell scripts `kebab-case.sh`; Python `snake_case`; TS/JS modules `kebab-case`, React components `PascalCase.tsx`. Toolchain rules win (Xcode targets, HA `custom_components/<domain>`, Python import names, Kotlin packages, ESPHome/HA `.yaml`).
- Root holds only README, LICENSE, SECURITY, CONTRIBUTING, CHANGELOG, AGENTS, CLAUDE (`.md`) plus config files. Code in `src/` (or the toolchain's dir), tests in `tests/`, `scripts/` for things that touch live systems, `tools/` for repo generators, `config/` for samples, docs in `docs/` with `docs/README.md` once there are more than five, superseded material in `docs/archive/YYYY/`.
- One `.env.example` with every variable the code reads (obviously fake placeholders). Examples are `<name>.example.<ext>`.

<!-- ── repo-specific notes below this line ─────────────────────────────── -->

- **Public repository.** No home-network details, names, addresses or measurements from any real household; screenshots use the demo data from `AppModel.loadDemo()`.
- Logic belongs in `Packages/GameReadyCore` (pure Swift, no I/O) with tests; the app only measures and displays.
- Every host the app contacts is in `Endpoints.allHosts`; `EndpointGuardTests` fails on any other.
- Strings: edit `tools/strings.py`, then `python3 tools/gen_strings.py`. Never edit `Localizable.xcstrings` by hand.
- Gate before every push: `scripts/check.sh` (tests, strings, diagram, build).
