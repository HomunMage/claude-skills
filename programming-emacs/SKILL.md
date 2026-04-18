---
name: programming-emacs
description: Customize Emacs into a VSCode-like layout (treemacs sidebar + editor + bash terminal) in a single portable init.el. Use when the user wants an IDE-style layout, file tree, integrated terminal, or an Emacs config that copies cleanly to another machine.
version: 0.1.0
---

# Emacs like VSCode — portable single-file config

## When to use

- "Make emacs look like VSCode / an IDE / have a sidebar"
- "Add file tree / integrated terminal to emacs"
- "Portable emacs config I can copy to another PC"

## Golden rules (learned from failure — do not repeat)

1. **Check `$DISPLAY` before recommending GUI features.** Empty → user is TTY-only. Icon/font-heavy configs (centaur-tabs, doom-modeline with nerd-font, PNG treemacs icons) render as mojibake. Set `treemacs-no-png-images t` for TTY.
2. **melpa.org HTTPS is unreachable from many networks** (CN, filtered, corporate). Symptom: emacs hangs forever on `Contacting host: melpa.org:443`. ELPA/GNU is fine, only melpa.org's HTTPS is flaky. See [mirrors.md](mirrors.md).
3. **Never `rm -rf ~/.emacs.d/elpa` while emacs is running.** Downloads silently fail to persist → cascade of `Cannot open load file` errors for every `use-package`. Kill emacs first.
4. **Prefer single-file `init.el` over starter kits** (visual-emacs, Doom, Spacemacs) when the ask is "portable" or "simple". A 150-line `init.el` with `use-package :ensure t` installs itself in one launch on another machine. Starter kits drag in dozens of packages the user didn't ask for.
5. **`ansi-term` with `/bin/bash`, NOT `eshell`.** When the user says "terminal like VSCode" they want their real shell (`.bashrc`, aliases like `ll`, nvm, etc.). Eshell is an elisp shell — surprising and incomplete. Recipe: `(ansi-term "/bin/bash" "bash")` → buffer `*bash*`. Teach the user: char mode by default (keys → shell); `C-c C-j` switches to line mode (emacs keys, copy text); `C-c C-k` back.
6. **Startup layout via idle timer, not direct call.** In TTY the minibuffer may be busy when `emacs-startup-hook` fires, and direct `(my/vscode-layout)` silently no-ops. Wrap with `(run-with-idle-timer 0.5 nil ...)` and check `(unless (active-minibuffer-window) ...)`. Bind F9 for manual re-apply.
7. **`cua-mode` for VSCode-native `C-c/C-x/C-v`.** Plus `delete-selection-mode` so typing replaces selection.

## Layout primitive

Three panes: treemacs (left side-window) + editor (top-right) + `*bash*` (bottom-right).

```elisp
(defun my/--first-non-side-window ()
  (seq-find (lambda (w) (not (window-parameter w 'window-side)))
            (window-list nil 'no-minibuf)))

(defun my/vscode-layout ()
  (interactive)
  (let ((main (my/--first-non-side-window)))
    (select-window main) (delete-other-windows main)
    (unless (eq (treemacs-current-visibility) 'visible)
      (save-selected-window (treemacs)))
    (let ((bottom (split-window main
                                (floor (* 0.72 (window-total-height main)))
                                'below)))
      (select-window bottom) (ansi-term "/bin/bash" "bash")
      (select-window main))))
```

Key points:
- Operate on a *non-side* window — treemacs is a side window and splitting it corrupts the layout.
- `frame-root-window` / `split-window … 'below` for the bottom terminal. Do NOT split the side window.
- Re-check `treemacs-current-visibility` before calling `(treemacs)` again — avoids double-open.

See [init.el](init.el) for the full working reference.

## Key binding map (VSCode ↔ this config)

| VSCode                     | This config           | Mechanism                               |
|----------------------------|-----------------------|-----------------------------------------|
| `Ctrl+B` sidebar toggle    | `F8` / `C-x t t`      | treemacs                                |
| `Ctrl+\`` terminal         | Project menu → Toggle Term | ansi-term in bottom split          |
| `Ctrl+C/X/V` clipboard     | native                | cua-mode                                |
| `Ctrl+S` save              | `C-s`                 | rebinding (note: shadows isearch)       |
| `Ctrl+Shift+E` explorer    | `C-x t d`             | prompt for folder, set as treemacs root |
| Command palette            | `M-x`                 | native                                  |

## Top-level "Project" menu

`easy-menu-define` adds an entry to the menu bar (left of Help). `menu-bar-mode 1` must be on. In TTY, F10 opens the menu bar.

```elisp
(easy-menu-define my/project-menu global-map "Project"
  '("Project"
    ["Open Folder..."   my/open-folder t]
    ["Toggle File Tree" treemacs t]
    "---"
    ["VSCode Layout"    my/vscode-layout t]
    ["Toggle Terminal"  my/toggle-terminal t]))
```

## Portability contract

- Single `init.el`, ~130 lines.
- Only MELPA package required: `treemacs`. Everything else is built-in (`ansi-term`, `easy-menu-define`, `cua-mode`, `display-line-numbers-mode`, `menu-bar-mode`).
- On import: copy file, launch emacs once, wait for `(package-refresh-contents)` + `(package-install 'treemacs)`.
- Pin archives to Tsinghua mirror by default (works behind most firewalls); user swaps back to melpa.org if preferred.

## Recovery playbook

| Symptom | Fix |
|---------|-----|
| Stuck on `Contacting host: melpa.org:443` | Swap to Tsinghua mirror (see mirrors.md), kill emacs, `rm -rf ~/.emacs.d/elpa`, restart |
| `Cannot open load file` cascade, no elpa dir on disk | Kill emacs, `mkdir -p ~/.emacs.d/elpa`, restart. Something (rm, permissions) wiped it mid-install |
| Layout doesn't auto-apply on startup | Press F9. Check `*Messages*` for errors |
| Treemacs icons look like `?` or mojibake | `(setq treemacs-no-png-images t)` + run in TTY; OR install a nerd-font + use GUI emacs |
| ansi-term keys all go to shell, can't navigate | `C-c C-j` → line mode; `C-c C-k` → char mode |
