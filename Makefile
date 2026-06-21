EMACS ?= emacs

.PHONY: check compile checkdoc test clean

check: compile checkdoc test

compile:
	$(EMACS) -Q --batch -L . --eval "(progn (setq byte-compile-error-on-warn t byte-compile-dest-file-function (lambda (_) (expand-file-name \"yaksweeper.elc\" temporary-file-directory))) (byte-compile-file \"yaksweeper.el\"))"

checkdoc:
	$(EMACS) -Q --batch -L . --eval "(progn (require 'checkdoc) (with-current-buffer (find-file-noselect \"yaksweeper.el\") (checkdoc-current-buffer t)))"

test:
	$(EMACS) -Q --batch -L . -l test/yaksweeper-test.el -f ert-run-tests-batch-and-exit

clean:
	rm -f yaksweeper.elc
