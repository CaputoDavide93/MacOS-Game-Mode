# Design

A Mac app first: system surfaces, standard controls, one brand colour. Two views of one
window (Basic, Advanced) plus a menu-bar extra. Every colour pair passes WCAG AA (≥ 4.5:1).
This replaces the earlier warm custom palette (D19 in decisions.md).

## Colour tokens

Surfaces and text are the system's (`windowBackgroundColor`, `controlBackgroundColor`,
`labelColor`, `secondaryLabelColor`, `separatorColor`), so light, dark and accessibility
settings behave like any Mac app. The brand and status colours are fixed:

| Token | Light | Dark | Contrast |
|---|---|---|---|
| `ready` (brand, good) | `#0B7A3E` | `#19F27A` | 5.4:1 on white · 11.1:1 on dark window |
| `onReady` (text on ready) | `#FFFFFF` | `#0F1826` | 5.4 · 11.9 |
| `warn` | `#B25000` | `#FF9F0A` | 5.2 · 8.1 |
| `bad` | `#C4291C` | `#FF6961` | 5.7 · 5.9 |

Basic's Fix & Play uses the user's own accent colour (blue by default). Colour is never the
only signal: every status also has a symbol and words.

## Shape and type

- Grouped rows radius 10 with a separator-colour hairline, like System Settings. Filled
  buttons are capsules. Shadows only on the status orb and the ring (glow in dark mode).
- System font; Basic's title 34 pt heavy; readouts and values monospaced.
- SF Symbols. No emoji.

## Views

- **Basic** (460 pt wide min): status orb → title → one sentence → what Fix & Play will do
  (or what was done, as chips) → one filled button → one quiet footer line.
- **Advanced** (820 pt wide min): sidebar (Overview, Checklist, History, Settings, live
  readouts) and content: readiness ring + verdict + monospaced readouts → Check again,
  Game Mode switch, Play → results grouped as Network and Line and Mac.
- **Basic | Advanced** switch in the title bar.

## Layout (before 2026-10-02, kept for history)

- Main window 440 × 680 by default, resizable down to 380 × 560. 20 pt side padding.
- Top: a segmented control for **Check · Checklist · History**. Settings live in the app's
  Settings window (⌘,), as on every Mac app.
- **Check:** verdict card (icon, headline, one-line reason) → **Check now** (the main
  action, full width, 52 pt) → Game Mode toggle row → **Play** (secondary) → results list.
- **Results rows:** status icon, check name, plain sentence, value on the right;
  disclosure reveals the raw numbers.
- **Menu-bar extra:** a dot (good/warn/bad) with the last ping; the popover shows router
  and game-server ping, Game Mode switch, the last 5 events, and "Open Game Ready".

## Motion and feedback

- Subtle only: 200 ms fades and value changes. With Reduce Motion on, none.
- Every action over 300 ms shows progress: the check lists each step as it runs,
  with a determinate bar.
- The main button ignores a second click while a check runs.

## Accessibility

- 44 pt minimum targets; every control has an accessibility label; verdict and results
  read as "Hop to router: good. Steady, 4.7 milliseconds."
- Keyboard: ⌘R runs a check, ⌘G toggles Game Mode, ⌘P plays.
- Dynamic type is limited on macOS; layouts are tested at the largest text size the
  Accessibility settings offer.
