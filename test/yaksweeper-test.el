;;; yaksweeper-test.el --- Tests for Yaksweeper -*- lexical-binding: t -*-

;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Regression tests for yaksweeper.el.

;;; Code:

(require 'ert)

(setq multisession-directory
      (expand-file-name "yaksweeper-test-multisession/" temporary-file-directory))

(require 'yaksweeper)

(defun yaksweeper-test--setup-game (width height mines)
  "Set up a test game with WIDTH, HEIGHT, and MINES in the current buffer."
  (yaksweeper-mode)
  (setq yaksweeper--width width
        yaksweeper--height height
        yaksweeper--mines mines
        yaksweeper--difficulty 'custom
        yaksweeper--preset nil
        yaksweeper--board (make-vector (* width height) nil)
        yaksweeper--state 'playing
        yaksweeper--first-click t
        yaksweeper--start-time nil
        yaksweeper--mines-flagged 0)
  (dotimes (i (length yaksweeper--board))
    (aset yaksweeper--board i (make-yaksweeper-cell))))

(ert-deftest yaksweeper-first-click-is-safe ()
  "The first reveal should not place a mine on the clicked cell or neighbors."
  (with-temp-buffer
    (yaksweeper-test--setup-game 5 5 5)
    (yaksweeper--do-reveal 2 2)
    (should-not yaksweeper--first-click)
    (should (yaksweeper-cell-revealed (yaksweeper--get-cell 2 2)))
    (should-not (yaksweeper-cell-has-mine (yaksweeper--get-cell 2 2)))
    (dolist (coord (yaksweeper--neighbors 2 2))
      (should-not (yaksweeper-cell-has-mine
                   (yaksweeper--get-cell (car coord) (cdr coord)))))))

(ert-deftest yaksweeper-loss-keeps-exploded-cell-marker ()
  "A lost game should render the clicked mine with the exploded marker."
  (with-temp-buffer
    (setf (multisession-value yaksweeper-stats) nil)
    (yaksweeper-test--setup-game 1 2 1)
    (setq yaksweeper--first-click nil
          yaksweeper--start-time (float-time))
    (setf (yaksweeper-cell-has-mine (yaksweeper--get-cell 0 0)) t)
    (let ((inhibit-message t)
          (message-log-max nil))
      (yaksweeper--do-reveal 0 0))
    (should (eq (yaksweeper-cell-revealed (yaksweeper--get-cell 0 0))
                'exploded))
    (should (string-match-p (regexp-quote yaksweeper-char-exploded)
                            (buffer-string)))))

(ert-deftest yaksweeper-stats-buffer-can-refresh ()
  "Stats display should work repeatedly even after special-mode makes it read-only."
  (let ((buf (get-buffer "*Yaksweeper Stats*")))
    (when buf
      (kill-buffer buf)))
  (unwind-protect
      (progn
        (setf (multisession-value yaksweeper-stats) nil)
        (yaksweeper-show-stats)
        (yaksweeper-show-stats)
        (with-current-buffer "*Yaksweeper Stats*"
          (should (derived-mode-p 'special-mode))
          (should (string-match-p "No games played yet" (buffer-string)))))
    (let ((buf (get-buffer "*Yaksweeper Stats*")))
      (when buf
        (kill-buffer buf)))))

(ert-deftest yaksweeper-validation-rejects-oversized-games ()
  "Custom game validation should reject sizes that can hang Emacs."
  (let ((yaksweeper-max-width 10)
        (yaksweeper-max-height 10)
        (yaksweeper-max-cells 100))
    (should-error (yaksweeper--validate-game 11 10 1) :type 'user-error)
    (should-error (yaksweeper--validate-game 10 11 1) :type 'user-error))
  (let ((yaksweeper-max-width 100)
        (yaksweeper-max-height 100)
        (yaksweeper-max-cells 25))
    (should-error (yaksweeper--validate-game 6 6 1) :type 'user-error))
  (should (null (yaksweeper--validate-game 30 16 99))))

(ert-deftest yaksweeper-save-preset-replaces-existing-name ()
  "Saving a preset with an existing name should replace it."
  (setf (multisession-value yaksweeper-presets) nil)
  (yaksweeper--save-preset " Tiny " 6 6 6)
  (yaksweeper--save-preset "Tiny" 7 7 7)
  (let ((presets (multisession-value yaksweeper-presets)))
    (should (= (length presets) 1))
    (should (equal (plist-get (car presets) :name) "Tiny"))
    (should (= (plist-get (car presets) :width) 7))
    (should (= (plist-get (car presets) :height) 7))
    (should (= (plist-get (car presets) :mines) 7))))

(provide 'yaksweeper-test)
;;; yaksweeper-test.el ends here
