# org-remark-posframe — modernization design

Date: 2026-06-21
Status: approved

## Problem

`org-marginalia-posframe.el` previews the marginal note for the highlight at
point in a child frame (posframe). It is currently **broken**: it
`(require 'org-marginalia)`, but upstream renamed the package to
**`org-remark`** (now v1.3.0), and `org-marginalia` is installed nowhere on
this machine. The rename is not a string substitution — the internals changed:

- Highlights are now **overlays** carrying the `org-remark-id` property (was a
  text property `org-marginalia-id`). `get-char-property` still reads it.
- The notes file is resolved by the generic `org-remark-notes-get-file-name`
  (per-source `FILE-notes.org`, or a shared `marginalia.org`), replacing the
  single variable `org-marginalia-notes-file-path`.
- `org-remark-next` / `org-remark-prev` exist and return t/nil.

The old content extraction did `switch-to-buffer` / `previous-buffer` (the
cause of the historical scroll bug). The C-g dismissal was an anonymous,
load-time, **global** advice on `keyboard-quit` that deleted *all* posframes.

## Goals

1. Port to live `org-remark` (>= 1.0) and Emacs 32 (master).
2. MELPA-grade: `package-lint`, `checkdoc`, and `batch-byte-compile` clean.
3. The preview posframe must **not cover the highlighted text** — show it
   *below* point (`posframe-poshandler-point-bottom-left-corner`), customizable.
4. Publish to `github.com/unship/org-remark-posframe`.

## Non-goals

- In-posframe editing of notes (listed under "Ideas" in the old README).
- nov.el / EWW source support (org-remark's generic API gives it for free, but
  it is not separately tested here).

## Decisions

- **Rename** `org-marginalia-posframe.el` → `org-remark-posframe.el` via
  `git mv` (preserve history). All package symbols → `org-remark-posframe-…`.
- **Attribution**: Author `Ran Wang` (original); Maintainer
  `liyanan <liyananfamily@gmail.com>`; URL `https://github.com/unship/org-remark-posframe`.
- **Position default**: `posframe-poshandler-point-bottom-left-corner`.
- **Scope**: MELPA-ready.

## Public interface

| Symbol | Type | Replaces | Purpose |
|---|---|---|---|
| `org-remark-posframe-show` | command | `org-marginalia-show-posframe` | Preview note for highlight at point |
| `org-remark-posframe-next` | command | `org-marginalia-next-preview` | `org-remark-next` + preview |
| `org-remark-posframe-prev` | command | `org-marginalia-prev-preview` | `org-remark-prev` + preview |
| `org-remark-posframe-hide` | command | (new) | Hide the preview posframe |
| `org-remark-posframe-mode` | global minor mode | the `keyboard-quit` advice | Opt-in: dismiss posframe on `C-g` |

All commands carry `;;;###autoload`.

### Customization (`defgroup org-remark-posframe`)

- `org-remark-posframe-poshandler` — fn, default
  `#'posframe-poshandler-point-bottom-left-corner` (below the highlight).
- `org-remark-posframe-internal-border-width` — int, default `2`.
- `org-remark-posframe-background-color` — string, default `"#93937070DBDB"`.
- `org-remark-posframe-todo-color` — string, default `"#ff4500"`.
- `org-remark-posframe-done-color` — string, default `"#7cfc00"`.

## Internals

- `org-remark-posframe-buffer` — defconst, `" *org-remark-posframe*"` (hidden).
- `org-remark-posframe--note-contents (id)` → `(CONTENTS . COLOR)` or nil.
  - Resolve `(org-remark-notes-get-file-name)` **in the source buffer**.
  - `find-file-noselect` + `with-current-buffer` + `org-with-wide-buffer` +
    `save-excursion` — the visible buffer never changes (fixes the scroll bug).
  - `(org-find-property org-remark-prop-id id)`; back to heading; collect the
    raw heading line plus the body from `org-end-of-meta-data` (skips the
    PROPERTIES drawer + planning) to `org-end-of-subtree`.
  - Color via `org-entry-is-done-p` / `org-entry-is-todo-p` (robust against
    custom TODO keywords; the old `string-match` against "TODO"/"DONE" was not).
- `org-remark-posframe--hide-on-quit` — named advice fn used by the minor mode.

### Display (`org-remark-posframe-show`)

1. `id = (get-char-property point 'org-remark-id)`; message + return if nil.
2. `note = (org-remark-posframe--note-contents id)`; message + return if nil.
3. Render CONTENTS into the hidden buffer, `org-mode`, hide org links if
   `org-link-descriptive` is nil (modern name; old `org-descriptive-links` is
   obsolete).
4. `(when (posframe-workable-p) (posframe-show … :poshandler
   org-remark-posframe-poshandler :internal-border-width … :background-color
   COLOR))`.

Navigation wrappers call `org-remark-next`/`prev`, and on a non-nil return
call `org-remark-posframe-show` at the new point. The old `sit-for 0.1` delay
and the `after-exec-point` free variable are removed (point moves synchronously).

### Dismissal

`org-remark-posframe-mode` (global, **off by default**, no load-time effect)
adds/removes named `:before` advice on `keyboard-quit` (and, if present,
`keyboard-quit-context+`) that calls `posframe-hide` on our buffer only.

## Header / dependencies

```elisp
;;; org-remark-posframe.el --- Preview org-remark notes in a posframe -*- lexical-binding: t; -*-
;; Author: Ran Wang
;; Maintainer: liyanan <liyananfamily@gmail.com>
;; URL: https://github.com/unship/org-remark-posframe
;; Version: 0.2.0
;; Package-Requires: ((emacs "27.1") (org "9.4") (posframe "1.0.0") (org-remark "1.0.0"))
;; Keywords: convenience, outlines, hypermedia
```

## Verification (evidence before "done")

1. `emacs -Q -batch -L . -L <posframe> -L <org-remark> -f batch-byte-compile
   org-remark-posframe.el` → 0 warnings/errors.
2. `checkdoc-file` → no issues.
3. `package-lint-batch-and-exit` → clean (dep-availability checks need archive
   metadata; note if unavailable).
4. **Functional** (batch, real org-remark): build a temp source file + notes
   file, create a highlight, assert `org-remark-posframe--note-contents`
   returns the expected text and color.
5. **GUI smoke test** via `emacsclient` to the running `server`: load the
   package, make a highlight, `org-remark-posframe-show`, confirm the posframe
   appears *below* the highlight (posframe needs a graphical frame;
   `posframe-workable-p` is nil in batch).

## README.org

Rewrite for the new name: `nobiot/org-remark` links, `org-remark-notes-file-name`
setup, new command/keybinding names on `org-remark-mode-map`, the below-highlight
behavior, the customization options, and `org-remark-posframe-mode` for C-g
dismissal. Keep the demo gif.

## Publish

Once green: `gh repo create unship/org-remark-posframe --public`, repoint
`origin`, commit, `git push -u origin main`.
