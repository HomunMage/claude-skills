;;; init.el --- VSCode-like layout, portable -*- lexical-binding: t; -*-
;;; Commentary:
;;  Minimal single-file Emacs config. Copy to ~/.emacs.d/init.el on any
;;  machine with Emacs 29+ and internet; first launch auto-installs treemacs.
;;  Layout: treemacs (left) + editor (top-right) + bash ansi-term (bottom-right).
;;; Code:

;; ---- Package sources (Tsinghua mirror; swap to melpa.org if preferred)
(require 'package)
(setq package-archives
      '(("gnu"    . "https://mirrors.tuna.tsinghua.edu.cn/elpa/gnu/")
        ("nongnu" . "https://mirrors.tuna.tsinghua.edu.cn/elpa/nongnu/")
        ("melpa"  . "https://mirrors.tuna.tsinghua.edu.cn/elpa/melpa/")))
(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))

(unless (package-installed-p 'use-package)
  (package-install 'use-package))
(require 'use-package)
(setq use-package-always-ensure t)

;; ---- Base UI
(menu-bar-mode 1)
(when (fboundp 'tool-bar-mode)   (tool-bar-mode   -1))
(when (fboundp 'scroll-bar-mode) (scroll-bar-mode -1))
(global-display-line-numbers-mode 1)
(column-number-mode 1)
(setq inhibit-startup-screen t
      make-backup-files nil
      auto-save-default nil
      ring-bell-function 'ignore)
(load-theme 'wombat t)

;; VSCode-style clipboard: C-c/C-x/C-v, typing replaces selection
(cua-mode 1)
(delete-selection-mode 1)
(global-set-key (kbd "C-s") #'save-buffer)
(global-set-key (kbd "C-z") #'undo)

;; ---- File tree (treemacs)
(use-package treemacs
  :defer nil
  :init
  (setq treemacs-width 32
        treemacs-is-never-other-window t
        treemacs-follow-after-init t
        treemacs-no-png-images t)     ; icons as text -> works in TTY
  :bind
  (("C-x t t" . treemacs)
   ("C-x t d" . my/open-folder)
   ("<f8>"    . treemacs)))

(defun my/open-folder (dir)
  "Prompt for DIR and show it in treemacs as the sole project."
  (interactive "DOpen folder: ")
  (let* ((full (expand-file-name dir))
         (name (file-name-nondirectory (directory-file-name full))))
    (when (fboundp 'treemacs-do-remove-project-from-workspace)
      (dolist (p (ignore-errors
                   (treemacs-workspace->projects (treemacs-current-workspace))))
        (ignore-errors (treemacs-do-remove-project-from-workspace p))))
    (ignore-errors (treemacs-do-add-project-to-workspace full name))
    (treemacs)))

;; Custom top-level "Project" menu (sits on menu bar next to File/Edit/...)
(easy-menu-define my/project-menu global-map "Project"
  '("Project"
    ["Open Folder..."   my/open-folder t]
    ["Toggle File Tree" treemacs t]
    "---"
    ["VSCode Layout"    my/vscode-layout t]
    ["Toggle Terminal"  my/toggle-terminal t]))

;; ---- Bottom terminal (ansi-term running real /bin/bash)
(defconst my/term-buffer-name "*bash*")

(defun my/--ensure-bash-term ()
  "Ensure a live ansi-term running /bin/bash, switch to it in current window."
  (let ((buf (get-buffer my/term-buffer-name)))
    (if (buffer-live-p buf)
        (switch-to-buffer buf)
      (ansi-term "/bin/bash" "bash"))))

(defun my/toggle-terminal ()
  "Toggle a bash ansi-term window at the bottom of the frame."
  (interactive)
  (let ((win (get-buffer-window my/term-buffer-name)))
    (if win
        (delete-window win)
      (let ((bottom (split-window (frame-root-window)
                                  (floor (* 0.72 (window-total-height
                                                  (frame-root-window))))
                                  'below)))
        (select-window bottom)
        (my/--ensure-bash-term)))))

;; ---- VSCode-like 3-pane layout: treemacs | editor / *bash*
(defun my/--first-non-side-window ()
  "Return the first window in the current frame that is not a side window."
  (seq-find (lambda (w) (not (window-parameter w 'window-side)))
            (window-list nil 'no-minibuf)))

(defun my/vscode-layout ()
  "Arrange: treemacs left, editor top-right, *bash* bottom-right."
  (interactive)
  (let ((main (my/--first-non-side-window)))
    (unless main (error "No non-side window available"))
    (select-window main)
    (delete-other-windows main)
    (unless (and (fboundp 'treemacs-current-visibility)
                 (eq (treemacs-current-visibility) 'visible))
      (save-selected-window (treemacs)))
    (let ((bottom (split-window main
                                (floor (* 0.72 (window-total-height main)))
                                'below)))
      (select-window bottom)
      (my/--ensure-bash-term)
      (select-window main))))

(global-set-key (kbd "<f9>") #'my/vscode-layout)

;; Startup layout: idle timer avoids racing with the minibuffer in TTY.
(add-hook 'emacs-startup-hook
          (lambda ()
            (run-with-idle-timer
             0.5 nil
             (lambda ()
               (unless (active-minibuffer-window)
                 (my/vscode-layout))))))

(provide 'init)
;;; init.el ends here
