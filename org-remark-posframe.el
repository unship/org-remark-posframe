;;; org-remark-posframe.el --- Preview org-remark notes in a posframe -*- lexical-binding: t; -*-

;; Copyright (C) 2020-2026 Ran Wang

;; Author: Ran Wang
;; Maintainer: liyanan <liyananfamily@gmail.com>
;; URL: https://github.com/unship/org-remark-posframe
;; Version: 0.3.0
;; Package-Requires: ((emacs "27.1") (org "9.4") (posframe "1.0.0") (org-remark "1.0.0"))
;; Keywords: convenience, outlines, hypermedia

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Preview the Org-remark (https://github.com/nobiot/org-remark) marginal
;; note for the highlight at point in a child frame (posframe).
;;
;; By default the posframe is placed just below point, so the highlighted
;; text stays visible while you read its note.  The position is controlled
;; by `org-remark-posframe-poshandler' and can be set to any posframe
;; position handler.
;;
;; Commands:
;;
;;   `org-remark-posframe-show'  Preview the note for the highlight at point.
;;   `org-remark-posframe-next'  Move to the next highlight and preview it.
;;   `org-remark-posframe-prev'  Move to the previous highlight and preview it.
;;   `org-remark-posframe-hide'  Hide the preview posframe.
;;
;; Enable the buffer-local minor mode `org-remark-posframe-auto-mode' to
;; preview notes automatically: the posframe appears when point rests on a
;; highlight and disappears when point leaves it.
;;
;; Enable the global minor mode `org-remark-posframe-mode' to dismiss the
;; preview with `C-g' (`keyboard-quit').
;;
;; Example configuration:
;;
;;   (with-eval-after-load 'org-remark
;;     (org-remark-posframe-mode)
;;     (add-hook 'org-remark-mode-hook #'org-remark-posframe-auto-mode)
;;     (define-key org-remark-mode-map (kbd "C-M-}") #'org-remark-posframe-next)
;;     (define-key org-remark-mode-map (kbd "C-M-{") #'org-remark-posframe-prev))

;;; Code:

(require 'org)
(require 'posframe)
(require 'org-remark)

(defgroup org-remark-posframe nil
  "Preview Org-remark marginal notes in a posframe."
  :group 'org-remark
  :prefix "org-remark-posframe-"
  :link '(url-link :tag "GitHub" "https://github.com/unship/org-remark-posframe"))

(defcustom org-remark-posframe-poshandler
  #'posframe-poshandler-point-bottom-left-corner
  "Position handler used to place the preview posframe.
The default places the posframe at the bottom-left corner of point,
i.e. just below the highlight, so the highlighted text remains
visible.  See `posframe-show' for the available handlers."
  :type 'function)

(defcustom org-remark-posframe-internal-border-width 2
  "Width in pixels of the preview posframe's internal border."
  :type 'integer)

(defcustom org-remark-posframe-background-color "#93937070DBDB"
  "Background color of the preview posframe for a plain note."
  :type 'color)

(defcustom org-remark-posframe-todo-color "#ff4500"
  "Background color of the preview posframe when the note is a TODO."
  :type 'color)

(defcustom org-remark-posframe-done-color "#7cfc00"
  "Background color of the preview posframe when the note is done."
  :type 'color)

(defcustom org-remark-posframe-auto-delay 0.2
  "Idle seconds before `org-remark-posframe-auto-mode' shows the posframe.
When point rests on a highlight for this long, its note is previewed.
A value of 0 previews as soon as Emacs is idle (effectively immediate)."
  :type 'number)

(defconst org-remark-posframe-buffer " *org-remark-posframe*"
  "Name of the buffer used to render the preview posframe contents.")

(defvar org-remark-posframe--auto-timer nil
  "Idle timer scheduled by `org-remark-posframe-auto-mode'.")

(defvar org-remark-posframe--auto-shown-id nil
  "Id of the highlight currently previewed by `org-remark-posframe-auto-mode'.")

(defun org-remark-posframe--note-contents (id)
  "Return the marginal note identified by ID as (CONTENTS . COLOR).
CONTENTS is a string with the note's heading and body, with the
PROPERTIES drawer and planning lines removed.  COLOR is chosen from
the entry's TODO state and one of `org-remark-posframe-todo-color',
`org-remark-posframe-done-color' or `org-remark-posframe-background-color'.
Return nil when no entry with `org-remark-prop-id' equal to ID is found.

Call this from the source buffer so that `org-remark-notes-get-file-name'
resolves to the correct marginal notes file."
  (let ((notes-file (org-remark-notes-get-file-name)))
    (when (and notes-file (file-exists-p notes-file))
      (with-current-buffer (find-file-noselect notes-file)
        (org-with-wide-buffer
         (let ((pos (org-find-property org-remark-prop-id id)))
           (when pos
             (goto-char pos)
             (org-back-to-heading t)
             (let* ((color (cond ((org-entry-is-done-p)
                                  org-remark-posframe-done-color)
                                 ((org-entry-is-todo-p)
                                  org-remark-posframe-todo-color)
                                 (t org-remark-posframe-background-color)))
                    (heading (buffer-substring-no-properties
                              (line-beginning-position)
                              (line-end-position)))
                    (body-beg (save-excursion (org-end-of-meta-data t) (point)))
                    (body-end (save-excursion (org-end-of-subtree t t) (point)))
                    (body (if (< body-beg body-end)
                              (string-trim
                               (buffer-substring-no-properties body-beg body-end))
                            "")))
               (cons (if (string-empty-p body)
                         heading
                       (concat heading "\n" body))
                     color)))))))))

;;;###autoload
(defun org-remark-posframe-show (point)
  "Preview the Org-remark note for the highlight at POINT in a posframe.
The posframe is positioned by `org-remark-posframe-poshandler', which
by default places it below POINT so the highlighted text stays visible."
  (interactive "d")
  (let ((id (get-char-property point 'org-remark-id)))
    (if (null id)
        (message "org-remark-posframe: no highlight at point")
      (let ((note (org-remark-posframe--note-contents id)))
        (if (null note)
            (message "org-remark-posframe: no note found for the highlight")
          (with-current-buffer (get-buffer-create org-remark-posframe-buffer)
            (erase-buffer)
            (insert (car note))
            (delay-mode-hooks (org-mode))
            (unless org-link-descriptive
              (add-to-invisibility-spec '(org-link))))
          (when (posframe-workable-p)
            (posframe-show
             org-remark-posframe-buffer
             :poshandler org-remark-posframe-poshandler
             :internal-border-width org-remark-posframe-internal-border-width
             :background-color (cdr note))))))))

(defun org-remark-posframe--move-and-show (move-fn)
  "Move with MOVE-FN to a highlight, then preview its note in a posframe.
MOVE-FN is `org-remark-next' or `org-remark-prev'.  Bind
`overriding-terminal-local-map' so those commands skip their repeat
transient map, whose setup signals an error when they are called from
Lisp rather than from a key sequence; the repeat map would move without
previewing in any case."
  (when (let ((overriding-terminal-local-map (make-sparse-keymap)))
          (funcall move-fn))
    (org-remark-posframe-show (point))))

;;;###autoload
(defun org-remark-posframe-next ()
  "Move to the next Org-remark highlight and preview its note in a posframe."
  (interactive)
  (org-remark-posframe--move-and-show #'org-remark-next))

;;;###autoload
(defun org-remark-posframe-prev ()
  "Move to the previous Org-remark highlight and preview its note in a posframe."
  (interactive)
  (org-remark-posframe--move-and-show #'org-remark-prev))

;;;###autoload
(defun org-remark-posframe-hide ()
  "Hide the Org-remark preview posframe, if it is shown."
  (interactive)
  (when (get-buffer org-remark-posframe-buffer)
    (posframe-hide org-remark-posframe-buffer)))

(defun org-remark-posframe--hide-on-quit (&rest _args)
  "Hide the preview posframe.
Used as advice on `keyboard-quit' by `org-remark-posframe-mode'."
  (org-remark-posframe-hide))

;;;###autoload
(define-minor-mode org-remark-posframe-mode
  "Global minor mode to dismiss the Org-remark preview posframe.
When enabled, `\\[keyboard-quit]' hides the preview posframe shown by
`org-remark-posframe-show' and its navigation commands."
  :global t
  :group 'org-remark-posframe
  (if org-remark-posframe-mode
      (progn
        (advice-add 'keyboard-quit :before #'org-remark-posframe--hide-on-quit)
        (when (fboundp 'keyboard-quit-context+)
          (advice-add 'keyboard-quit-context+ :before
                      #'org-remark-posframe--hide-on-quit)))
    (advice-remove 'keyboard-quit #'org-remark-posframe--hide-on-quit)
    (when (fboundp 'keyboard-quit-context+)
      (advice-remove 'keyboard-quit-context+ #'org-remark-posframe--hide-on-quit))))

(defun org-remark-posframe--auto-cancel-timer ()
  "Cancel the pending `org-remark-posframe-auto-mode' idle timer, if any."
  (when org-remark-posframe--auto-timer
    (cancel-timer org-remark-posframe--auto-timer)
    (setq org-remark-posframe--auto-timer nil)))

(defun org-remark-posframe--auto-show (buffer)
  "Preview the highlight at point in BUFFER if it is still current.
Called by the idle timer scheduled in `org-remark-posframe--auto-update'."
  (when (and (buffer-live-p buffer)
             (eq buffer (window-buffer (selected-window))))
    (with-current-buffer buffer
      (let ((id (get-char-property (point) 'org-remark-id)))
        (when id
          (setq org-remark-posframe--auto-shown-id id)
          (org-remark-posframe-show (point)))))))

(defun org-remark-posframe--auto-update ()
  "Show or hide the preview posframe based on point.
Added to `post-command-hook' by `org-remark-posframe-auto-mode'."
  (org-remark-posframe--auto-cancel-timer)
  (let ((id (get-char-property (point) 'org-remark-id)))
    (cond
     ;; Off any highlight: hide what auto-mode is showing.
     ((null id)
      (when org-remark-posframe--auto-shown-id
        (setq org-remark-posframe--auto-shown-id nil)
        (org-remark-posframe-hide)))
     ;; Still on the highlight already previewed: nothing to do.
     ((equal id org-remark-posframe--auto-shown-id) nil)
     ;; On a new highlight: drop the old preview, then show after the delay.
     ;; Always go through an idle timer (even for delay 0) so the posframe is
     ;; positioned after redisplay -- showing it synchronously in
     ;; `post-command-hook' would read a stale glyph position for point.
     (t
      (when org-remark-posframe--auto-shown-id
        (setq org-remark-posframe--auto-shown-id nil)
        (org-remark-posframe-hide))
      (setq org-remark-posframe--auto-timer
            (run-with-idle-timer org-remark-posframe-auto-delay nil
                                 #'org-remark-posframe--auto-show
                                 (current-buffer)))))))

;;;###autoload
(define-minor-mode org-remark-posframe-auto-mode
  "Buffer-local minor mode to auto-preview Org-remark notes in a posframe.
When point rests on a highlight for `org-remark-posframe-auto-delay'
seconds, its marginal note appears in a posframe; the posframe is hidden
when point moves off the highlight.  Add it to `org-remark-mode-hook' to
enable it in every Org-remark buffer."
  :lighter " ormk-pf"
  :group 'org-remark-posframe
  (if org-remark-posframe-auto-mode
      (add-hook 'post-command-hook #'org-remark-posframe--auto-update nil :local)
    (remove-hook 'post-command-hook #'org-remark-posframe--auto-update :local)
    (org-remark-posframe--auto-cancel-timer)
    (setq org-remark-posframe--auto-shown-id nil)
    (org-remark-posframe-hide)))

(provide 'org-remark-posframe)

;;; org-remark-posframe.el ends here
