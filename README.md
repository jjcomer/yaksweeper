<div align="center">
  <img src="assets/logo.jpg" alt="Yaksweeper Logo" width="500"/>
  <h1>Yaksweeper</h1>
  <p><em>A modern Minesweeper implementation for Emacs using Unicode visuals and transient menus.</em></p>
</div>

---

## 💣 Overview

**Yaksweeper** brings the classic Minesweeper experience straight to your favorite editor, Emacs! It features a beautiful Unicode-based grid, varying difficulty levels, statistical tracking, and an intuitive [Transient](https://magit.vc/manual/transient/) interface.

## ✨ Features

- **Transient Menus**: Launch and configure games easily with `M-x yaksweeper`.
- **Unicode Graphics**: Clean visual indicators using emojis (⬜, ⬛, 🚩, 💣, 💥).
- **Multiple Difficulties**: 
  - Beginner (9x9, 10 mines)
  - Intermediate (16x16, 40 mines)
  - Expert (30x16, 99 mines)
- **Statistics Tracking**: View your game history and times via the Transient menu.
- **Mouse & Keyboard Support**: Full support for standard keybindings and mouse chords.

## 📦 Requirements

- GNU Emacs **30.1** or newer
- **transient** 0.3.7 or newer

## 🚀 Usage

Start the game with:
```elisp
M-x yaksweeper
```

From the Transient menu, press `b`, `i`, or `e` to start a Beginner, Intermediate, or Expert game.

### Keybindings

When in `yaksweeper-mode`, use the following controls:

| Action | Keyboard | Mouse |
|--------|----------|-------|
| **Reveal Cell** | `RET`, `SPC`, or `x` | `mouse-1` (Left Click) |
| **Flag/Unflag** | `f` or `m` | `mouse-3` (Right Click) |
| **Chord** (Reveal neighbors) | `c` | `mouse-2` (Middle Click) or `double-mouse-1` |
| **Restart Game** | `r` | - |

> *Tip: Chording on a revealed number that has the correct amount of flagged neighbors will automatically reveal the rest of its neighbors.*

## 📈 Statistics

Yaksweeper tracks your wins, losses, and completion times across all difficulty levels using Emacs' `multisession` variables. 
You can view your stats from the main menu by pressing `s` (`yaksweeper-show-stats`).

## 🛠️ Customization

You can customize the appearance of Yaksweeper via the `yaksweeper` customization group:
```elisp
M-x customize-group RET yaksweeper RET
```
Available options include changing the characters used for mines, flags, hidden cells, and the colors (faces) of the numbers.
