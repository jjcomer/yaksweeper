;;; yaksweeper.el --- Modern Emacs Minesweeper -*- lexical-binding: t -*-

;; Copyright (C) 2026 Josh Comer
;; SPDX-License-Identifier: MIT
;; Author: Yaksweeper Contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (transient "0.3.7"))
;; Keywords: games
;; URL: https://github.com/jjcomer/yaksweeper

;;; Commentary:
;; A modern Minesweeper implementation for Emacs using Unicode visuals
;; and transient menus.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
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
  "Character used for marked cells."
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

(defcustom yaksweeper-char-wrong-flag "❌"
  "Character used for incorrectly flagged cells after a loss."
  :type 'string
  :group 'yaksweeper)

(defcustom yaksweeper-cell-width 4
  "Minimum display columns reserved for each board cell."
  :type 'integer
  :group 'yaksweeper)

(defface yaksweeper-number-1-face '((t :foreground "#1E90FF" :weight bold)) "Face for 1." :group 'yaksweeper)
(defface yaksweeper-number-2-face '((t :foreground "#32CD32" :weight bold)) "Face for 2." :group 'yaksweeper)
(defface yaksweeper-number-3-face '((t :foreground "#FF4500" :weight bold)) "Face for 3." :group 'yaksweeper)
(defface yaksweeper-number-4-face '((t :foreground "#4B0082" :weight bold)) "Face for 4." :group 'yaksweeper)
(defface yaksweeper-number-5-face '((t :foreground "#800000" :weight bold)) "Face for 5." :group 'yaksweeper)
(defface yaksweeper-number-6-face '((t :foreground "#00CED1" :weight bold)) "Face for 6." :group 'yaksweeper)
(defface yaksweeper-number-7-face '((t :foreground "#000000" :weight bold)) "Face for 7." :group 'yaksweeper)
(defface yaksweeper-number-8-face '((t :foreground "#696969" :weight bold)) "Face for 8." :group 'yaksweeper)
(defface yaksweeper-revealed-face '((t :background "#333333")) "Face for revealed empty background." :group 'yaksweeper)
(defface yaksweeper-selected-face
  '((t :background "#FFD166" :foreground "#000000"))
  "Legacy face for selected cells.
Selection is shown with the cursor to keep emoji glyph rendering stable."
  :group 'yaksweeper)
(defface yaksweeper-warning-face
  '((t :inherit warning :weight bold))
  "Face for warning text, such as too many flags."
  :group 'yaksweeper)

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
(defvar-local yaksweeper--preset nil "Current custom preset name, or nil.")
(defvar-local yaksweeper--state 'playing "Game state: playing, won, or lost.")
(defvar-local yaksweeper--first-click t "Is this the first click?")
(defvar-local yaksweeper--start-time nil "Time the game started.")
(defvar-local yaksweeper--mines-flagged 0 "Number of flagged mines.")
(defvar-local yaksweeper--selection-overlay nil "Overlay for the selected cell.")

(define-multisession-variable yaksweeper-stats nil
  "Statistics for Yaksweeper.
Format: list of plists, e.g. (:difficulty beginner :time 45.2
:won t :date \"...\" :width 9 :height 9 :mines 10 :preset nil).")

(define-multisession-variable yaksweeper-presets nil
  "Saved Yaksweeper custom game presets.
Format: list of plists, e.g. (:name \"Tiny\" :width 6 :height 6 :mines 6).")

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

(defun yaksweeper--validate-game (width height mines)
  "Signal an error unless WIDTH, HEIGHT, and MINES can make a game."
  (unless (and (integerp width) (> width 0))
    (user-error "Width must be a positive integer"))
  (unless (and (integerp height) (> height 0))
    (user-error "Height must be a positive integer"))
  (unless (and (integerp mines) (>= mines 0))
    (user-error "Mines must be a non-negative integer"))
  (unless (< mines (* width height))
    (user-error "Mines must leave at least one safe cell")))

(defun yaksweeper--normalize-preset-name (name)
  "Return a trimmed preset NAME, or nil when NAME is blank."
  (when (stringp name)
    (let ((trimmed (string-trim name)))
      (unless (string-empty-p trimmed)
        trimmed))))

(defun yaksweeper--difficulty-symbol (difficulty)
  "Return DIFFICULTY as a lowercase symbol when possible."
  (cond
   ((symbolp difficulty) difficulty)
   ((stringp difficulty) (intern-soft (downcase difficulty)))))

(defun yaksweeper--board-label (difficulty width height mines &optional preset)
  "Return a display label for DIFFICULTY, WIDTH, HEIGHT, MINES, and PRESET."
  (pcase (yaksweeper--difficulty-symbol difficulty)
    ('beginner "Beginner")
    ('intermediate "Intermediate")
    ('expert "Expert")
    (_ (cond
        ((yaksweeper--normalize-preset-name preset)
         (format "Custom: %s" (yaksweeper--normalize-preset-name preset)))
        ((and (integerp width) (integerp height) (integerp mines))
         (format "Custom %dx%d/%d" width height mines))
        ((symbolp difficulty)
         (capitalize (symbol-name difficulty)))
        ((stringp difficulty)
         (capitalize difficulty))
        (t "Custom")))))

(defun yaksweeper--current-board-label ()
  "Return the display label for the current game."
  (yaksweeper--board-label yaksweeper--difficulty
                           yaksweeper--width
                           yaksweeper--height
                           yaksweeper--mines
                           yaksweeper--preset))

(defun yaksweeper--safe-cells-remaining ()
  "Return the number of unrevealed non-mine cells remaining."
  (if yaksweeper--first-click
      (- (* yaksweeper--width yaksweeper--height) yaksweeper--mines)
    (let ((remaining 0))
      (dotimes (i (length yaksweeper--board))
        (let ((cell (aref yaksweeper--board i)))
          (when (and (not (yaksweeper-cell-has-mine cell))
                     (not (yaksweeper-cell-revealed cell)))
            (cl-incf remaining))))
      remaining)))

(defun yaksweeper--place-mines (safe-x safe-y)
  "Place mines randomly without mining the first click at SAFE-X, SAFE-Y.
When the board has enough space, also keep SAFE-X, SAFE-Y's neighbors clear so
the first revealed cell is a zero."
  (let* ((first-click (cons safe-x safe-y))
         (zero-safe-coords (cons first-click (yaksweeper--neighbors safe-x safe-y)))
         (zero-safe-slots (- (* yaksweeper--width yaksweeper--height)
                             (length zero-safe-coords)))
         (safe-coords (if (<= yaksweeper--mines zero-safe-slots)
                          zero-safe-coords
                        (list first-click)))
         (candidates nil))
    (dotimes (y yaksweeper--height)
      (dotimes (x yaksweeper--width)
        (let ((coord (cons x y)))
          (unless (member coord safe-coords)
            (push coord candidates)))))
    (unless (<= yaksweeper--mines (length candidates))
      (user-error "Not enough cells to place %d mines safely" yaksweeper--mines))
    (dotimes (_ yaksweeper--mines)
      (let* ((index (random (length candidates)))
             (coord (nth index candidates))
             (cell (yaksweeper--get-cell (car coord) (cdr coord))))
        (setf (yaksweeper-cell-has-mine cell) t)
        (setq candidates
              (append (cl-subseq candidates 0 index)
                      (nthcdr (1+ index) candidates)))))
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
    (let ((cell (yaksweeper--get-cell x y)))
      (when (and cell (not (yaksweeper-cell-flagged cell)))
        (when yaksweeper--first-click
          (setq yaksweeper--first-click nil
                yaksweeper--start-time (float-time))
          (yaksweeper--place-mines x y))
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
    (yaksweeper--render (cons x y))))

(defun yaksweeper--do-flag (x y)
  "Toggle flag at X, Y."
  (when (eq yaksweeper--state 'playing)
    (let ((cell (yaksweeper--get-cell x y)))
      (when (and cell (not (yaksweeper-cell-revealed cell)))
        (setf (yaksweeper-cell-flagged cell) (not (yaksweeper-cell-flagged cell)))
        (if (yaksweeper-cell-flagged cell)
            (cl-incf yaksweeper--mines-flagged)
          (cl-decf yaksweeper--mines-flagged))))
    (yaksweeper--render (cons x y))))

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
    (yaksweeper--render (cons x y))))

;;; Display

(defun yaksweeper--get-face-for-number (n)
  "Return face for number N."
  (intern (format "yaksweeper-number-%d-face" n)))

(defun yaksweeper--format-number (n)
  "Format number N."
  (propertize (number-to-string n)
              'face (yaksweeper--get-face-for-number n)))

(defun yaksweeper--effective-cell-width ()
  "Return the display columns reserved for one rendered cell."
  (let* ((glyphs (list yaksweeper-char-hidden
                       yaksweeper-char-empty
                       yaksweeper-char-flag
                       yaksweeper-char-mine
                       yaksweeper-char-exploded
                       yaksweeper-char-wrong-flag
                       "8"))
         (widest (apply #'max (mapcar #'string-width glyphs))))
    (max yaksweeper-cell-width (+ widest 2))))

(defun yaksweeper--cell-properties (x y)
  "Return text properties for the rendered cell at X and Y."
  (list 'yaksweeper-x x
        'yaksweeper-y y
        'help-echo (format "(%d, %d)" x y)))

(defun yaksweeper--insert-cell (str x y cell-width)
  "Insert cell STR at X and Y, aligning the next cell by CELL-WIDTH."
  (let ((properties (yaksweeper--cell-properties x y)))
    (insert (apply #'propertize str properties))
    (insert (apply #'propertize
                   " "
                   'display `(space :align-to ,(* (1+ x) cell-width))
                   properties))))

(defun yaksweeper--goto-cell (x y)
  "Move point to the rendered cell at X, Y."
  (let ((pos (point-min))
        found)
    (while (and (not found) (< pos (point-max)))
      (if (and (equal (get-text-property pos 'yaksweeper-x) x)
               (equal (get-text-property pos 'yaksweeper-y) y))
          (setq found pos)
        (setq pos (next-single-property-change
                   pos 'yaksweeper-x nil (point-max)))))
    (when found
      (goto-char found)
      t)))

(defun yaksweeper--cell-bounds-at-point (&optional pos)
  "Return the text bounds of the cell at POS, or nil."
  (let* ((p (or pos (point)))
         (coords (yaksweeper--get-coords-at-point p)))
    (when coords
      (let ((start p)
            (end p))
        (while (and (> start (point-min))
                    (equal coords (yaksweeper--get-coords-at-point (1- start))))
          (cl-decf start))
        (while (and (< end (point-max))
                    (equal coords (yaksweeper--get-coords-at-point end)))
          (cl-incf end))
        (cons start end)))))

(defun yaksweeper--update-selection ()
  "Remove stale selection overlays.
Point and the cursor show the selected cell.  Avoid applying faces to board
glyphs here because that can change emoji rendering metrics in Emacs."
  (when (derived-mode-p 'yaksweeper-mode)
    (when (overlayp yaksweeper--selection-overlay)
      (delete-overlay yaksweeper--selection-overlay)
      (setq yaksweeper--selection-overlay nil))))

(defun yaksweeper--render (&optional focus)
  "Render the board to the buffer.
FOCUS is an optional (X . Y) cell to keep selected after rendering."
  (let ((inhibit-read-only t)
        (focus (or focus (yaksweeper--get-coords-at-point) (cons 0 0)))
        (time-elapsed (if yaksweeper--start-time
                          (- (float-time) yaksweeper--start-time)
                        0.0))
        (cell-width (yaksweeper--effective-cell-width))
        (mine-counter (format "Mines: %d/%d"
                              yaksweeper--mines-flagged
                              yaksweeper--mines)))
    (erase-buffer)
    ;; Header
    (insert (propertize (format "Yaksweeper [%s] | " (yaksweeper--current-board-label))
                        'face 'bold))
    (insert (propertize mine-counter
                        'face (if (> yaksweeper--mines-flagged yaksweeper--mines)
                                  'yaksweeper-warning-face
                                'bold)))
    (insert (propertize (format " | Remaining: %d | Time: %d\n"
                                (yaksweeper--safe-cells-remaining)
                                (floor time-elapsed))
                        'face 'bold))
    (insert (propertize
             "Controls: arrows/hjkl move | RET/SPC/x reveal | f/m flag | c chord | r restart | q quit\n\n"
             'face 'shadow))
    ;; Board
    (dotimes (y yaksweeper--height)
      (dotimes (x yaksweeper--width)
        (let* ((cell (yaksweeper--get-cell x y))
               (str (cond
                     ((eq (yaksweeper-cell-revealed cell) 'exploded) yaksweeper-char-exploded)
                     ((and (eq yaksweeper--state 'lost)
                           (yaksweeper-cell-flagged cell)
                           (not (yaksweeper-cell-has-mine cell)))
                      yaksweeper-char-wrong-flag)
                     ((not (yaksweeper-cell-revealed cell))
                      (if (yaksweeper-cell-flagged cell) yaksweeper-char-flag yaksweeper-char-hidden))
                     ((yaksweeper-cell-has-mine cell) yaksweeper-char-mine)
                     ((= (yaksweeper-cell-neighbor-mines cell) 0) yaksweeper-char-empty)
                     (t (yaksweeper--format-number (yaksweeper-cell-neighbor-mines cell))))))
          (yaksweeper--insert-cell str x y cell-width)))
      (insert "\n"))

    (when (eq yaksweeper--state 'won)
      (insert (propertize "\n\n*** YOU WIN! ***\n" 'face '(bold :foreground "green"))))
    (when (eq yaksweeper--state 'lost)
      (insert (propertize "\n\n*** GAME OVER ***\n" 'face '(bold :foreground "red"))))
    (or (yaksweeper--goto-cell (car focus) (cdr focus))
        (yaksweeper--goto-cell 0 0))
    (yaksweeper--update-selection)))

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

(defun yaksweeper--move (dx dy)
  "Move the selected cell by DX and DY."
  (let* ((coords (or (yaksweeper--get-coords-at-point) (cons 0 0)))
         (x (max 0 (min (1- yaksweeper--width) (+ (car coords) dx))))
         (y (max 0 (min (1- yaksweeper--height) (+ (cdr coords) dy)))))
    (when (yaksweeper--goto-cell x y)
      (yaksweeper--update-selection))))

(defun yaksweeper-move-left ()
  "Move the selected cell left."
  (interactive)
  (yaksweeper--move -1 0))

(defun yaksweeper-move-right ()
  "Move the selected cell right."
  (interactive)
  (yaksweeper--move 1 0))

(defun yaksweeper-move-up ()
  "Move the selected cell up."
  (interactive)
  (yaksweeper--move 0 -1))

(defun yaksweeper-move-down ()
  "Move the selected cell down."
  (interactive)
  (yaksweeper--move 0 1))

(defun yaksweeper-click (event)
  "Handle mouse EVENT as a reveal click."
  (interactive "e")
  (mouse-set-point event)
  (yaksweeper-reveal-at-point))

(defun yaksweeper-flag-click (event)
  "Handle mouse EVENT as a flag click."
  (interactive "e")
  (mouse-set-point event)
  (yaksweeper-flag-at-point))

(defun yaksweeper-chord-click (event)
  "Handle mouse EVENT as a chord click."
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
    (define-key map (kbd "<left>") #'yaksweeper-move-left)
    (define-key map (kbd "<right>") #'yaksweeper-move-right)
    (define-key map (kbd "<up>") #'yaksweeper-move-up)
    (define-key map (kbd "<down>") #'yaksweeper-move-down)
    (define-key map (kbd "h") #'yaksweeper-move-left)
    (define-key map (kbd "l") #'yaksweeper-move-right)
    (define-key map (kbd "k") #'yaksweeper-move-up)
    (define-key map (kbd "j") #'yaksweeper-move-down)
    (define-key map [mouse-1] #'yaksweeper-click)
    (define-key map [mouse-3] #'yaksweeper-flag-click)
    (define-key map [mouse-2] #'yaksweeper-chord-click)
    (define-key map [double-mouse-1] #'yaksweeper-chord-click)
    map)
  "Keymap for Yaksweeper.")

(define-derived-mode yaksweeper-mode special-mode "Yaksweeper"
  "Major mode for playing Yaksweeper."
  (setq truncate-lines t)
  (setq cursor-type 'box)
  (hl-line-mode -1)
  (add-hook 'post-command-hook #'yaksweeper--update-selection nil t))

;;; Game Launchers

(defun yaksweeper--find-preset (name)
  "Return the saved preset named NAME, or nil."
  (let ((normalized-name (yaksweeper--normalize-preset-name name)))
    (when normalized-name
      (cl-find-if (lambda (preset)
                    (equal normalized-name (plist-get preset :name)))
                  (multisession-value yaksweeper-presets)))))

(defun yaksweeper--save-preset (name width height mines)
  "Save custom game preset NAME with WIDTH, HEIGHT, and MINES."
  (let* ((normalized-name (yaksweeper--normalize-preset-name name))
         (preset (list :name normalized-name
                       :width width
                       :height height
                       :mines mines)))
    (unless normalized-name
      (user-error "Preset name cannot be blank"))
    (yaksweeper--validate-game width height mines)
    (setf (multisession-value yaksweeper-presets)
          (cons preset
                (cl-remove-if (lambda (existing)
                                (equal normalized-name (plist-get existing :name)))
                              (multisession-value yaksweeper-presets))))
    preset))

(defun yaksweeper--init-game (width height mines difficulty &optional preset)
  "Initialize the game buffer with WIDTH, HEIGHT, MINES, DIFFICULTY, and PRESET."
  (yaksweeper--validate-game width height mines)
  (switch-to-buffer (get-buffer-create "*Yaksweeper*"))
  (yaksweeper-mode)
  (setq yaksweeper--width width
        yaksweeper--height height
        yaksweeper--mines mines
        yaksweeper--difficulty difficulty
        yaksweeper--preset (yaksweeper--normalize-preset-name preset)
        yaksweeper--board (make-vector (* width height) nil)
        yaksweeper--state 'playing
        yaksweeper--first-click t
        yaksweeper--start-time nil
        yaksweeper--mines-flagged 0)
  (dotimes (i (length yaksweeper--board))
    (aset yaksweeper--board i (make-yaksweeper-cell)))
  (yaksweeper--render (cons 0 0)))

;;;###autoload
(defun yaksweeper-restart ()
  "Restart current game."
  (interactive)
  (yaksweeper--init-game yaksweeper--width
                         yaksweeper--height
                         yaksweeper--mines
                         yaksweeper--difficulty
                         yaksweeper--preset))

;;;###autoload
(defun yaksweeper-beginner ()
  "Start a beginner game."
  (interactive)
  (yaksweeper--init-game 9 9 10 'beginner))

;;;###autoload
(defun yaksweeper-intermediate ()
  "Start an intermediate game."
  (interactive)
  (yaksweeper--init-game 16 16 40 'intermediate))

;;;###autoload
(defun yaksweeper-expert ()
  "Start an expert game."
  (interactive)
  (yaksweeper--init-game 30 16 99 'expert))

;;;###autoload
(defun yaksweeper-custom (width height mines &optional preset-name)
  "Start a custom game with WIDTH, HEIGHT, and MINES.
When PRESET-NAME is non-empty, save these settings as a reusable preset."
  (interactive
   (let* ((width (read-number "Width: " 9))
          (height (read-number "Height: " 9))
          (mines (read-number "Mines: " 10))
          (preset-name (yaksweeper--normalize-preset-name
                        (read-string "Save preset name (empty to skip): "))))
     (list width height mines preset-name)))
  (let ((preset (yaksweeper--normalize-preset-name preset-name)))
    (when preset
      (yaksweeper--save-preset preset width height mines))
    (yaksweeper--init-game width height mines 'custom preset)))

;;;###autoload
(defun yaksweeper-start-preset (name)
  "Start a custom game from the saved preset named NAME."
  (interactive
   (let* ((presets (multisession-value yaksweeper-presets))
          (names (delq nil (mapcar (lambda (preset) (plist-get preset :name))
                                   presets))))
     (unless names
       (user-error "No saved Yaksweeper presets"))
     (list (completing-read "Preset: " names nil t))))
  (let ((preset (yaksweeper--find-preset name)))
    (unless preset
      (user-error "No saved Yaksweeper preset named %s" name))
    (yaksweeper--init-game (plist-get preset :width)
                           (plist-get preset :height)
                           (plist-get preset :mines)
                           'custom
                           (plist-get preset :name))))

;;; Stats

(defun yaksweeper--stat-board-label (stat)
  "Return the board label for STAT."
  (yaksweeper--board-label (plist-get stat :difficulty)
                           (plist-get stat :width)
                           (plist-get stat :height)
                           (plist-get stat :mines)
                           (plist-get stat :preset)))

(defun yaksweeper--format-duration (seconds)
  "Format SECONDS for stats output."
  (if (numberp seconds)
      (format "%.1fs" seconds)
    "n/a"))

(defun yaksweeper--format-win-rate (wins games)
  "Format WINS divided by GAMES as a percentage."
  (if (and (numberp games) (> games 0))
      (format "%.1f%%" (* 100.0 (/ (float wins) games)))
    "n/a"))

(defun yaksweeper--stats-by-board (stats)
  "Return (LABELS . TABLE) aggregating STATS by board label."
  (let ((labels nil)
        (table (make-hash-table :test 'equal)))
    (dolist (stat stats)
      (let* ((label (yaksweeper--stat-board-label stat))
             (entry (gethash label table)))
        (unless entry
          (setq entry (list :games 0 :wins 0 :win-times nil))
          (push label labels))
        (setq entry (plist-put entry :games (1+ (plist-get entry :games))))
        (when (plist-get stat :won)
          (setq entry (plist-put entry :wins (1+ (plist-get entry :wins))))
          (when (numberp (plist-get stat :time))
            (setq entry (plist-put entry :win-times
                                   (cons (plist-get stat :time)
                                         (plist-get entry :win-times))))))
        (puthash label entry table)))
    (cons (nreverse labels) table)))

(defun yaksweeper--average (numbers)
  "Return the average of NUMBERS, or nil when NUMBERS is empty."
  (when numbers
    (/ (apply #'+ numbers) (float (length numbers)))))

(defun yaksweeper--stat-newer-p (a b)
  "Return non-nil when stat A should sort newer than stat B."
  (let ((date-a (plist-get a :date))
        (date-b (plist-get b :date)))
    (cond
     ((and (stringp date-a) (stringp date-b))
      (string> date-a date-b))
     ((stringp date-a) t)
     (t nil))))

(defun yaksweeper--insert-stats-dashboard (stats)
  "Insert a dashboard summarizing STATS into the current buffer."
  (let* ((games (length stats))
         (wins (cl-count-if (lambda (stat) (plist-get stat :won)) stats))
         (losses (- games wins))
         (by-board (yaksweeper--stats-by-board stats))
         (labels (car by-board))
         (table (cdr by-board))
         (recent (cl-stable-sort (copy-sequence stats) #'yaksweeper--stat-newer-p)))
    (insert "Overall\n-------\n")
    (insert (format "Games: %d | Wins: %d | Losses: %d | Win rate: %s\n\n"
                    games wins losses (yaksweeper--format-win-rate wins games)))

    (insert "By Board\n--------\n")
    (insert (format "%-24s %5s %9s %10s %10s\n"
                    "Board" "Games" "Win Rate" "Best Win" "Avg Win"))
    (insert (make-string 64 ?-))
    (insert "\n")
    (dolist (label labels)
      (let* ((entry (gethash label table))
             (board-games (plist-get entry :games))
             (board-wins (plist-get entry :wins))
             (win-times (plist-get entry :win-times))
             (best (when win-times (apply #'min win-times)))
             (average (yaksweeper--average win-times)))
        (insert (format "%-24s %5d %9s %10s %10s\n"
                        label
                        board-games
                        (yaksweeper--format-win-rate board-wins board-games)
                        (yaksweeper--format-duration best)
                        (yaksweeper--format-duration average)))))

    (insert "\nRecent Games\n------------\n")
    (dolist (stat recent)
      (insert (format "[%s] %s - %s (%s)\n"
                      (or (plist-get stat :date) "unknown date")
                      (yaksweeper--stat-board-label stat)
                      (if (plist-get stat :won) "WON" "LOST")
                      (yaksweeper--format-duration (plist-get stat :time)))))))

(defun yaksweeper--record-stats (won)
  "Record game stats, marking the game as won if WON is non-nil."
  (let* ((now (float-time))
         (time (- now (or yaksweeper--start-time now)))
         (record (list :difficulty yaksweeper--difficulty
                       :time time
                       :won won
                       :date (format-time-string "%Y-%m-%d %H:%M:%S")
                       :width yaksweeper--width
                       :height yaksweeper--height
                       :mines yaksweeper--mines)))
    (when yaksweeper--preset
      (setq record (plist-put record :preset yaksweeper--preset)))
    (setf (multisession-value yaksweeper-stats)
          (cons record (multisession-value yaksweeper-stats)))))

;;;###autoload
(defun yaksweeper-show-stats ()
  "Show Yaksweeper statistics."
  (interactive)
  (let ((buf (get-buffer-create "*Yaksweeper Stats*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert "Yaksweeper Statistics\n=====================\n\n")
      (if (not (multisession-value yaksweeper-stats))
          (insert "No games played yet.\n")
        (yaksweeper--insert-stats-dashboard (multisession-value yaksweeper-stats)))
      (special-mode)
      (goto-char (point-min)))
    (display-buffer buf)))

;;; Menus

;;;###autoload
(transient-define-prefix yaksweeper ()
  "Play Yaksweeper."
  ["Start Game"
   ("b" "Beginner (9x9, 10 mines)" yaksweeper-beginner)
   ("i" "Intermediate (16x16, 40 mines)" yaksweeper-intermediate)
   ("e" "Expert (30x16, 99 mines)" yaksweeper-expert)
   ("c" "Custom Game" yaksweeper-custom)
   ("p" "Saved Preset" yaksweeper-start-preset)]
  ["Other"
   ("s" "Show Stats" yaksweeper-show-stats)])

(provide 'yaksweeper)
;;; yaksweeper.el ends here
