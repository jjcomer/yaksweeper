;;; yaksweeper.el --- Modern Emacs Minesweeper -*- lexical-binding: t -*-

;; Copyright (C) 2026 Free Software Foundation, Inc.
;; Author: Yaksweeper Contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (transient "0.3.7"))
;; Keywords: games
;; URL: https://github.com/josh/yaksweeper

;;; Commentary:
;; A modern Minesweeper implementation for Emacs using Unicode visuals
;; and transient menus.

;;; Code:

(require 'cl-lib)
(require 'transient)
(require 'multisession)

;;; Customization

(defgroup yaksweeper nil
  "Modern Minesweeper for Emacs."
  :group 'games)

(defcustom yaksweeper-char-hidden "⬜"
  "Character used for hidden cells."
  :type 'string
  :group 'yaksweeper)

(defcustom yaksweeper-char-empty "⬛"
  "Character used for revealed empty cells."
  :type 'string
  :group 'yaksweeper)

(defcustom yaksweeper-char-flag "🚩"
  "Character used for flagged cells."
  :type 'string
  :group 'yaksweeper)

(defcustom yaksweeper-char-mine "💣"
  "Character used for mines."
  :type 'string
  :group 'yaksweeper)

(defcustom yaksweeper-char-exploded "💥"
  "Character used for exploded mines."
  :type 'string
  :group 'yaksweeper)

(defface yaksweeper-number-1-face '((t :foreground "#1E90FF" :weight bold)) "Face for 1" :group 'yaksweeper)
(defface yaksweeper-number-2-face '((t :foreground "#32CD32" :weight bold)) "Face for 2" :group 'yaksweeper)
(defface yaksweeper-number-3-face '((t :foreground "#FF4500" :weight bold)) "Face for 3" :group 'yaksweeper)
(defface yaksweeper-number-4-face '((t :foreground "#4B0082" :weight bold)) "Face for 4" :group 'yaksweeper)
(defface yaksweeper-number-5-face '((t :foreground "#800000" :weight bold)) "Face for 5" :group 'yaksweeper)
(defface yaksweeper-number-6-face '((t :foreground "#00CED1" :weight bold)) "Face for 6" :group 'yaksweeper)
(defface yaksweeper-number-7-face '((t :foreground "#000000" :weight bold)) "Face for 7" :group 'yaksweeper)
(defface yaksweeper-number-8-face '((t :foreground "#696969" :weight bold)) "Face for 8" :group 'yaksweeper)
(defface yaksweeper-revealed-face '((t :background "#333333")) "Face for revealed empty background." :group 'yaksweeper)

;;; State

(cl-defstruct yaksweeper-cell
  (has-mine nil)
  (revealed nil)
  (flagged nil)
  (neighbor-mines 0))

(defvar-local yaksweeper--board nil "The game board (vector of cells).")
(defvar-local yaksweeper--width 0 "Board width.")
(defvar-local yaksweeper--height 0 "Board height.")
(defvar-local yaksweeper--mines 0 "Total mines.")
(defvar-local yaksweeper--difficulty 'beginner "Current difficulty level.")
(defvar-local yaksweeper--state 'playing "Game state: 'playing, 'won, 'lost.")
(defvar-local yaksweeper--first-click t "Is this the first click?")
(defvar-local yaksweeper--start-time nil "Time the game started.")
(defvar-local yaksweeper--mines-flagged 0 "Number of flagged mines.")

(define-multisession-variable yaksweeper-stats nil
  "Statistics for Yaksweeper.
Format: list of plists, e.g. (:difficulty beginner :time 45.2 :won t :date \"...\")")

;;; Logic

(defun yaksweeper--index (x y)
  "Convert X and Y coordinates to an array index."
  (+ x (* y yaksweeper--width)))

(defun yaksweeper--coords (index)
  "Convert INDEX back to (X . Y) coordinates."
  (cons (% index yaksweeper--width)
        (/ index yaksweeper--width)))

(defun yaksweeper--valid-p (x y)
  "Return t if X and Y are within the board."
  (and (>= x 0) (< x yaksweeper--width)
       (>= y 0) (< y yaksweeper--height)))

(defun yaksweeper--get-cell (x y)
  "Get the cell at X and Y."
  (when (yaksweeper--valid-p x y)
    (aref yaksweeper--board (yaksweeper--index x y))))

(defun yaksweeper--neighbors (x y)
  "Return a list of valid neighbor coordinates for X and Y."
  (let ((neighbors nil))
    (dolist (dx '(-1 0 1))
      (dolist (dy '(-1 0 1))
        (unless (and (= dx 0) (= dy 0))
          (let ((nx (+ x dx))
                (ny (+ y dy)))
            (when (yaksweeper--valid-p nx ny)
              (push (cons nx ny) neighbors))))))
    neighbors))

(defun yaksweeper--place-mines (safe-x safe-y)
  "Place mines randomly, ensuring the first click at SAFE-X, SAFE-Y is a 0."
  (let ((safe-coords (cons (cons safe-x safe-y) (yaksweeper--neighbors safe-x safe-y)))
        (placed 0))
    (while (< placed yaksweeper--mines)
      (let* ((rx (random yaksweeper--width))
             (ry (random yaksweeper--height))
             (cell (yaksweeper--get-cell rx ry)))
        (unless (or (yaksweeper-cell-has-mine cell)
                    (member (cons rx ry) safe-coords))
          (setf (yaksweeper-cell-has-mine cell) t)
          (cl-incf placed))))
    ;; Calculate neighbors
    (dotimes (y yaksweeper--height)
      (dotimes (x yaksweeper--width)
        (let ((cell (yaksweeper--get-cell x y)))
          (unless (yaksweeper-cell-has-mine cell)
            (let ((mines 0))
              (dolist (n (yaksweeper--neighbors x y))
                (when (yaksweeper-cell-has-mine (yaksweeper--get-cell (car n) (cdr n)))
                  (cl-incf mines)))
              (setf (yaksweeper-cell-neighbor-mines cell) mines))))))))

(defun yaksweeper--check-win ()
  "Check if the game is won."
  (let ((won t))
    (dotimes (i (length yaksweeper--board))
      (let ((cell (aref yaksweeper--board i)))
        (when (and (not (yaksweeper-cell-has-mine cell))
                   (not (yaksweeper-cell-revealed cell)))
          (setq won nil))))
    (when won
      (setq yaksweeper--state 'won)
      (yaksweeper--record-stats t)
      (message "You won!"))))

(defun yaksweeper--reveal-all ()
  "Reveal the board at the end of the game."
  (dotimes (i (length yaksweeper--board))
    (let ((cell (aref yaksweeper--board i)))
      (when (yaksweeper-cell-has-mine cell)
        (setf (yaksweeper-cell-revealed cell) t)))))

(defun yaksweeper--reveal-cell (x y)
  "Reveal cell at X, Y. Return nil if it was a mine, t otherwise."
  (let ((cell (yaksweeper--get-cell x y)))
    (cond
     ((or (not cell) (yaksweeper-cell-revealed cell) (yaksweeper-cell-flagged cell)) t)
     ((yaksweeper-cell-has-mine cell) nil)
     (t
      (setf (yaksweeper-cell-revealed cell) t)
      (when (= (yaksweeper-cell-neighbor-mines cell) 0)
        (dolist (n (yaksweeper--neighbors x y))
          (yaksweeper--reveal-cell (car n) (cdr n))))
      t))))

(defun yaksweeper--do-reveal (x y)
  "Interactive logic to reveal X, Y."
  (when (eq yaksweeper--state 'playing)
    (when yaksweeper--first-click
      (setq yaksweeper--first-click nil
            yaksweeper--start-time (float-time))
      (yaksweeper--place-mines x y))
    
    (let ((cell (yaksweeper--get-cell x y)))
      (when (and cell (not (yaksweeper-cell-flagged cell)))
        (if (yaksweeper-cell-has-mine cell)
            (progn
              ;; Game over
              (setq yaksweeper--state 'lost)
              (setf (yaksweeper-cell-revealed cell) 'exploded)
              (yaksweeper--reveal-all)
              (yaksweeper--record-stats nil)
              (message "Boom! You hit a mine."))
          (yaksweeper--reveal-cell x y)
          (yaksweeper--check-win))))
    (yaksweeper--render)))

(defun yaksweeper--do-flag (x y)
  "Toggle flag at X, Y."
  (when (eq yaksweeper--state 'playing)
    (let ((cell (yaksweeper--get-cell x y)))
      (when (and cell (not (yaksweeper-cell-revealed cell)))
        (setf (yaksweeper-cell-flagged cell) (not (yaksweeper-cell-flagged cell)))
        (if (yaksweeper-cell-flagged cell)
            (cl-incf yaksweeper--mines-flagged)
          (cl-decf yaksweeper--mines-flagged))))
    (yaksweeper--render)))

(defun yaksweeper--do-chord (x y)
  "Chord at X, Y (reveal neighbors if flags match)."
  (when (eq yaksweeper--state 'playing)
    (let ((cell (yaksweeper--get-cell x y)))
      (when (and cell (yaksweeper-cell-revealed cell) (> (yaksweeper-cell-neighbor-mines cell) 0))
        (let ((flags 0))
          (dolist (n (yaksweeper--neighbors x y))
            (when (yaksweeper-cell-flagged (yaksweeper--get-cell (car n) (cdr n)))
              (cl-incf flags)))
          (when (= flags (yaksweeper-cell-neighbor-mines cell))
            ;; Reveal all non-flagged neighbors
            (dolist (n (yaksweeper--neighbors x y))
              (yaksweeper--do-reveal (car n) (cdr n)))))))
    (yaksweeper--render)))

;;; Display

(defun yaksweeper--get-face-for-number (n)
  "Return face for number N."
  (intern (format "yaksweeper-number-%d-face" n)))

(defun yaksweeper--format-number (n)
  "Format number N to fit 2 characters width if Unicode emojis are 2 chars."
  (let* ((str (number-to-string n))
         (padded (if (= (length str) 1) (concat " " str) str)))
    (propertize padded 'face (yaksweeper--get-face-for-number n))))

(defun yaksweeper--render ()
  "Render the board to the buffer."
  (let ((inhibit-read-only t)
        (time-elapsed (if yaksweeper--start-time
                          (- (float-time) yaksweeper--start-time)
                        0.0)))
    (erase-buffer)
    ;; Header
    (insert (propertize (format "Yaksweeper [%s] | Mines: %d/%d | Time: %d\n\n"
                                (capitalize (symbol-name yaksweeper--difficulty))
                                yaksweeper--mines-flagged yaksweeper--mines
                                (floor time-elapsed))
                        'face 'bold))
    ;; Board
    (dotimes (y yaksweeper--height)
      (dotimes (x yaksweeper--width)
        (let* ((cell (yaksweeper--get-cell x y))
               (str (cond
                     ((eq (yaksweeper-cell-revealed cell) 'exploded) yaksweeper-char-exploded)
                     ((not (yaksweeper-cell-revealed cell))
                      (if (yaksweeper-cell-flagged cell) yaksweeper-char-flag yaksweeper-char-hidden))
                     ((yaksweeper-cell-has-mine cell) yaksweeper-char-mine)
                     ((= (yaksweeper-cell-neighbor-mines cell) 0) yaksweeper-char-empty)
                     (t (yaksweeper--format-number (yaksweeper-cell-neighbor-mines cell))))))
          (insert (propertize str
                              'yaksweeper-x x
                              'yaksweeper-y y
                              'mouse-face 'highlight
                              'help-echo (format "(%d, %d)" x y)))))
      (insert "\n"))
    
    (when (eq yaksweeper--state 'won)
      (insert (propertize "\n\n*** YOU WIN! ***\n" 'face '(bold :foreground "green"))))
    (when (eq yaksweeper--state 'lost)
      (insert (propertize "\n\n*** GAME OVER ***\n" 'face '(bold :foreground "red"))))
    (goto-char (point-min))))

;;; Interaction

(defun yaksweeper--get-coords-at-point (&optional pos)
  "Get the coordinates at POS (or point)."
  (let* ((p (or pos (point)))
         (x (get-text-property p 'yaksweeper-x))
         (y (get-text-property p 'yaksweeper-y)))
    (if (and x y)
        (cons x y)
      nil)))

(defun yaksweeper-reveal-at-point ()
  "Reveal cell at point."
  (interactive)
  (let ((coords (yaksweeper--get-coords-at-point)))
    (when coords
      (yaksweeper--do-reveal (car coords) (cdr coords)))))

(defun yaksweeper-flag-at-point ()
  "Flag cell at point."
  (interactive)
  (let ((coords (yaksweeper--get-coords-at-point)))
    (when coords
      (yaksweeper--do-flag (car coords) (cdr coords)))))

(defun yaksweeper-chord-at-point ()
  "Chord cell at point."
  (interactive)
  (let ((coords (yaksweeper--get-coords-at-point)))
    (when coords
      (yaksweeper--do-chord (car coords) (cdr coords)))))

(defun yaksweeper-click (event)
  "Handle mouse click."
  (interactive "e")
  (mouse-set-point event)
  (yaksweeper-reveal-at-point))

(defun yaksweeper-flag-click (event)
  "Handle mouse right click."
  (interactive "e")
  (mouse-set-point event)
  (yaksweeper-flag-at-point))

(defun yaksweeper-chord-click (event)
  "Handle mouse middle click or double click."
  (interactive "e")
  (mouse-set-point event)
  (yaksweeper-chord-at-point))

;;; Major Mode

(defvar yaksweeper-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'yaksweeper-reveal-at-point)
    (define-key map (kbd "SPC") #'yaksweeper-reveal-at-point)
    (define-key map (kbd "x") #'yaksweeper-reveal-at-point)
    (define-key map (kbd "f") #'yaksweeper-flag-at-point)
    (define-key map (kbd "m") #'yaksweeper-flag-at-point)
    (define-key map (kbd "c") #'yaksweeper-chord-at-point)
    (define-key map (kbd "r") #'yaksweeper-restart)
    (define-key map [mouse-1] #'yaksweeper-click)
    (define-key map [mouse-3] #'yaksweeper-flag-click)
    (define-key map [mouse-2] #'yaksweeper-chord-click)
    (define-key map [double-mouse-1] #'yaksweeper-chord-click)
    map)
  "Keymap for Yaksweeper.")

(define-derived-mode yaksweeper-mode special-mode "Yaksweeper"
  "Major mode for playing Yaksweeper."
  (setq truncate-lines t)
  (setq cursor-type nil)
  (hl-line-mode -1))

;;; Game Launchers

(defun yaksweeper--init-game (width height mines difficulty)
  "Initialize the game buffer."
  (switch-to-buffer (get-buffer-create "*Yaksweeper*"))
  (yaksweeper-mode)
  (setq yaksweeper--width width
        yaksweeper--height height
        yaksweeper--mines mines
        yaksweeper--difficulty difficulty
        yaksweeper--board (make-vector (* width height) nil)
        yaksweeper--state 'playing
        yaksweeper--first-click t
        yaksweeper--start-time nil
        yaksweeper--mines-flagged 0)
  (dotimes (i (length yaksweeper--board))
    (aset yaksweeper--board i (make-yaksweeper-cell)))
  (yaksweeper--render))

(defun yaksweeper-restart ()
  "Restart current game."
  (interactive)
  (yaksweeper--init-game yaksweeper--width yaksweeper--height yaksweeper--mines yaksweeper--difficulty))

(defun yaksweeper-beginner ()
  "Start a beginner game."
  (interactive)
  (yaksweeper--init-game 9 9 10 'beginner))

(defun yaksweeper-intermediate ()
  "Start an intermediate game."
  (interactive)
  (yaksweeper--init-game 16 16 40 'intermediate))

(defun yaksweeper-expert ()
  "Start an expert game."
  (interactive)
  (yaksweeper--init-game 30 16 99 'expert))

;;; Stats

(defun yaksweeper--record-stats (won)
  "Record game stats."
  (let ((time (- (float-time) yaksweeper--start-time)))
    (setq yaksweeper-stats
          (cons (list :difficulty yaksweeper--difficulty
                      :time time
                      :won won
                      :date (format-time-string "%Y-%m-%d %H:%M:%S"))
                (multisession-value yaksweeper-stats)))))

(defun yaksweeper-show-stats ()
  "Show Yaksweeper statistics."
  (interactive)
  (let ((buf (get-buffer-create "*Yaksweeper Stats*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert "Yaksweeper Statistics\n=====================\n\n")
      (if (not (multisession-value yaksweeper-stats))
          (insert "No games played yet.\n")
        (dolist (stat (multisession-value yaksweeper-stats))
          (insert (format "[%s] %s - %s (%.1fs)\n"
                          (plist-get stat :date)
                          (capitalize (symbol-name (plist-get stat :difficulty)))
                          (if (plist-get stat :won) "WON" "LOST")
                          (plist-get stat :time)))))
      (special-mode)
      (goto-char (point-min)))
    (display-buffer buf)))

;;; Menus

(transient-define-prefix yaksweeper ()
  "Play Yaksweeper."
  ["Start Game"
   ("b" "Beginner (9x9, 10 mines)" yaksweeper-beginner)
   ("i" "Intermediate (16x16, 40 mines)" yaksweeper-intermediate)
   ("e" "Expert (30x16, 99 mines)" yaksweeper-expert)]
  ["Other"
   ("s" "Show Stats" yaksweeper-show-stats)])

(provide 'yaksweeper)
;;; yaksweeper.el ends here
