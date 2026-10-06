# Butterfly

A macOS menu bar app that filters the double-typed keystrokes caused by failing butterfly keyboards.

## How it works

Butterfly watches key presses and looks at repeats of the same key:

- **Hard bounce** — a repeat faster than the hard threshold (default 40 ms) is always blocked.
- **Soft bounce** — a repeat faster than the soft threshold (default 100 ms) is blocked only if the doubled letter can't be part of a real word, checked against `/usr/share/dict/words`. So "thhe" is fixed while "bookkeeper" is left alone.

Holding a key down (key repeat) is never filtered. Both thresholds can be changed in Settings.

## Build

Requires macOS 11+ and the Swift toolchain (Xcode or Command Line Tools).

```sh
./build-app.sh
open Butterfly.app
```

On first launch, grant Accessibility permission in System Settings → Privacy & Security → Accessibility. Filtering starts automatically once permission is granted.
