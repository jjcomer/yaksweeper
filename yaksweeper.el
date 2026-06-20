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
  '((t :inherit highlight :weight bold :box (:line-width 1 :color "#FFD166")))
  "Face for the selected cell."
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
(defvar-local yaksweeper--state 'playing "Game state: playing, won, or lost.")
(defvar-local yaksweeper--first-click t "Is this the first click?")
(defvar-local yaksweeper--start-time nil "Time the game started.")
(defvar-local yaksweeper--mines-flagged 0 "Number of flagged mines.")
(defvar-local yaksweeper--selection-overlay nil "Overlay for the selected cell.")

(define-multisession-variable yaksweeper-stats nil
  "Statistics for Yaksweeper.
Format: list of plists, e.g. (:difficulty beginner :time 45.2
:won t :date \"...\").")

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
  "Format number N to fit 2 characters width if Unicode emojis are 2 chars."
  (let* ((str (number-to-string n))
         (padded (if (= (length str) 1) (concat " " str) str)))
    (propertize padded 'face (yaksweeper--get-face-for-number n))))

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
  "Move the selection overlay to the cell at point."
  (when (derived-mode-p 'yaksweeper-mode)
    (unless (overlayp yaksweeper--selection-overlay)
      (setq yaksweeper--selection-overlay (make-overlay (point-min) (point-min)))
      (overlay-put yaksweeper--selection-overlay 'face 'yaksweeper-selected-face)
      (overlay-put yaksweeper--selection-overlay 'priority 10))
    (let ((bounds (yaksweeper--cell-bounds-at-point)))
      (if bounds
          (move-overlay yaksweeper--selection-overlay (car bounds) (cdr bounds))
        (delete-overlay yaksweeper--selection-overlay)))))

(defun yaksweeper--render (&optional focus)
  "Render the board to the buffer.
FOCUS is an optional (X . Y) cell to keep selected after rendering."
  (let ((inhibit-read-only t)
        (focus (or focus (yaksweeper--get-coords-at-point) (cons 0 0)))
        (time-elapsed (if yaksweeper--start-time
                          (- (float-time) yaksweeper--start-time)
                        0.0)))
    (erase-buffer)
    ;; Header
    (insert (propertize (format "Yaksweeper [%s] | Mines: %d/%d | Time: %d\n"
                                (capitalize (symbol-name yaksweeper--difficulty))
                                yaksweeper--mines-flagged yaksweeper--mines
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
  (setq cursor-type nil)
  (hl-line-mode -1)
  (add-hook 'post-command-hook #'yaksweeper--update-selection nil t))

;;; Game Launchers

(defun yaksweeper--init-game (width height mines difficulty)
  "Initialize the game buffer with WIDTH, HEIGHT, MINES, and DIFFICULTY."
  (yaksweeper--validate-game width height mines)
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
  (yaksweeper--render (cons 0 0)))

;;;###autoload
(defun yaksweeper-restart ()
  "Restart current game."
  (interactive)
  (yaksweeper--init-game yaksweeper--width yaksweeper--height yaksweeper--mines yaksweeper--difficulty))

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

;;; Stats

(defun yaksweeper--record-stats (won)
  "Record game stats, marking the game as won if WON is non-nil."
  (let ((time (- (float-time) yaksweeper--start-time)))
    (setf (multisession-value yaksweeper-stats)
          (cons (list :difficulty yaksweeper--difficulty
                      :time time
                      :won won
                      :date (format-time-string "%Y-%m-%d %H:%M:%S"))
                (multisession-value yaksweeper-stats)))))

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

;;;###autoload
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
