# Design

Calm, warm and plain. One window, one main action per screen, plus a menu-bar extra.
The tokens follow the house app standard. Status colours were added for this app and
checked for contrast (WCAG AA ≥ 4.5:1) on both surfaces.

## Colour tokens

| Token | Light | Dark | Contrast on surface (L / D) |
|---|---|---|---|
| `surface` | `#F7F4EE` warm off-white | `#0F1826` deep navy | — |
| `card` | `#FFFDF9` | `#1A2638` | — |
| `text` | `#1B2A41` | `#EDEFF3` | 13.2 / 15.5 |
| `textVariant` | `#55606E` | `#B7C1CE` | 5.8 / 9.8 |
| `primary` | `#2F6F69` muted teal | `#8CC7BF` light teal | 5.3 / 9.4 |
| `onPrimary` | `#FFFFFF` | `#0F1826` | 5.8 / 9.4 on primary |
| `good` | `#2E7D4F` | `#7DD3A0` | 4.6 / 9.9 |
| `warn` | `#8A5A00` | `#F2C14E` | 5.4 / 10.6 |
| `bad` | `#B3261E` | `#F2938C` | 6.0 / 7.9 |
| `outline` | `#1B2A41` at 12% | `#EDEFF3` at 14% | hairline only |

Colour is never the only signal: every status has an icon and a word
(`checkmark.circle` Ready, `exclamationmark.triangle` Warning, `xmark.octagon` Not ready,
`questionmark.circle` Couldn't measure).

## Shape and type

- Cards radius 18, buttons 14, chips 10. No shadows; a 1 pt hairline border.
- System font. Titles weight 600; verdict headline `.title` weight 600.
- Rounded SF Symbols. No emoji.

## Layout

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
