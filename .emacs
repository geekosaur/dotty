;(setq load-path (append '("~/.elisp/") load-path))
;(load "/opt/local/share/emacs/site-lisp/haskell-mode-2.4/haskell-site-file")
(add-hook 'haskell-mode-hook 'turn-on-haskell-doc-mode)
(add-hook 'haskell-mode-hook 'turn-on-haskell-indent)
(add-hook 'haskell-mode-hook 'font-lock-mode)
(add-hook 'haskell-mode-hook 'imenu-add-menubar-index)
;(autoload 'markdown-mode "markdown-mode"
;  "Major mode for editing Markdown files" t)
;(add-to-list 'auto-mode-alist '("\\.markdown\\'" . markdown-mode))
;(add-to-list 'auto-mode-alist '("\\.md\\'" . markdown-mode))
;(add-to-list 'auto-mode-alist '("\\.mdwn\\'" . markdown-mode))
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(colon-double-space t)
 '(column-number-mode t)
 '(comment-column 48)
 '(confirm-kill-emacs (quote yes-or-no-p))
 '(current-language-environment "UTF-8")
 '(desktop-save-mode t)
 '(fill-column 78)
 '(focus-follows-mouse nil)
 '(frame-background-mode (quote dark))
 '(global-linum-mode t)
 '(ibuffer-use-other-window t)
 '(icomplete-mode t)
 '(indicate-buffer-boundaries (quote right))
 '(indicate-empty-lines t)
 '(inhibit-startup-screen t)
 '(initial-scratch-message nil)
 '(iswitchb-mode t)
 '(partial-completion-mode t)
 '(save-place t nil (saveplace))
 '(scalable-fonts-allowed t)
 '(show-paren-mode t)
 '(size-indication-mode t)
 '(speedbar-frame-parameters (quote ((minibuffer) (width . 30) (border-width . 0) (menu-bar-lines . 0) (tool-bar-lines . 0) (unsplittable . t) (left-fringe . 0))))
 '(speedbar-frame-plist (quote (minibuffer nil width 30 border-width 0 internal-border-width 0 unsplittable t default-toolbar-visible-p nil has-modeline-p nil menubar-visible-p nil default-gutter-visible-p nil)))
 '(speedbar-hide-button-brackets-flag t)
 '(speedbar-show-unknown-files t)
 '(speedbar-track-mouse-flag t)
 '(text-mode-hook (quote (turn-on-auto-fill text-mode-hook-identify)))
 '(tool-bar-mode nil)
 '(tooltip-mode nil)
 '(uniquify-buffer-name-style (quote forward) nil (uniquify))
 '(visible-cursor t))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(default ((t (:stipple nil :background "black" :foreground "white" :inverse-video nil :box nil :strike-through nil :overline nil :underline nil :slant normal :weight normal :height 98 :width normal :family "DejaVu Sans Mono" :foundry "unknown"))))
 '(fixed-pitch ((t (:family "apple-monaco"))))
 '(variable-pitch ((t (:family "arial")))))

(put 'upcase-region 'disabled nil)
(setq cperl-hairy t)
; this is probably beyond evil
(require 'cperl-mode)
(fset 'perl-mode (symbol-function 'cperl-mode))

;; these are *nice*
;; (will be nicer when I get around to combining them properly)
(global-set-key [3 127] 'c-hungry-backspace)
(global-set-key [3 9] '(lambda (backp)
			   (interactive "P")
			   (delete-horizontal-space backp)
			   (indent-relative)))
(setq auto-mode-alist
      (append '(("[Mm][Aa][Nn][Ii][Ff][Ee][Ss][Tt]\\.mf\\'" . conf-mode))
	      auto-mode-alist))

(server-start)
