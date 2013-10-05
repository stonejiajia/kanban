;;; kanban.el --- Parse org-todo headlines to use org-tables as Kanban tables
;;
;; Copyright (C) 2012-2013  Arne Babenhauserheide <arne_bab@web.de>

;; Version: 0.1.2

;; Author: Arne Babenhauserheide <arne_bab@web.de>
;; Keywords: outlines, convenience

;; This file is NOT part of Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of
;; the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be
;; useful, but WITHOUT ANY WARRANTY; without even the implied
;; warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
;; PURPOSE.  See the GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public
;; License along with this program; if not, write to the Free
;; Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
;; MA 02111-1307 USA
;;
;;; Commentary:

;; If you have not installed this from a package such as those on
;; Marmalade or MELPA, then save kanban.el to a directory in your
;; load-path and add
;;
;; (require 'kanban)
;;
;; to your Emacs start-up files.
;;
;; Usage:
;;
;; * Zero state Kanban: Directly displaying org-mode todo states as kanban board
;;
;; Use the functions kanban-headers and kanban-zero in TBLFM lines to
;; get your org-mode todo states as kanban table. Update with C-c C-c
;; on the TBLFM line.
;;
;; Example:
;;
;; |   |   |   |
;; |---+---+---|
;; |   |   |   |
;; |   |   |   |
;; #+TBLFM: @1$1='(kanban-headers)::@2$1..@>$>='(kanban-zero @# $# "TAG" '(list-of-files))
;; "TAG" and the list of files are optional
;;
;; * Stateful Kanban: Use org-mode to retrieve tasks, but track their state in the Kanban board
;;
;; |   |   |   |
;; |---+---+---|
;; |   |   |   |
;; |   |   |   |
;; #+TBLFM: @1$1='(kanban-headers)::@2$1..@>$1='(kanban-todo @# @2$2..@>$> "TAG" '(list-of-files))
;; "TAG" and the list of files are optional
;;
;; TODO: The links don’t yet work for tagged entries. Fix that. There
;; has to be some org-mode function to retrieve the plain header.
;;
;; TODO: kanban-todo sometimes inserts no tasks at all if there are multiple tasks in non-standard states.
;;
;;; Code:

;; Get the defined todo-states from the current org-mode document.
;;;###autoload
(defun kanban-headers (&optional startcolumn)
  "Fill the headers of your table with your org-mode TODO
states. If the table is too narrow, the only the first n TODO
states will be shown, with n as the number of columns in your
table.

Only not already present TODO states will be filled into empty
fields starting from the current column. All columns left of
the current one are left untouched.

Optionally ignore fields in columns left of STARTCOLUMN"
  (let* ((ofc (org-table-get nil nil)) ; remember old field content
     (col (org-table-current-column)) ; and current column
     (startcolumn (or startcolumn col))
     (kwl org-todo-keywords-1)
     kw)
  (while (setq kw (pop kwl)) ; iterate over all TODO states
    (let ((matchcol 0) ; insert kw in this empty column
      (n startcolumn)
      field)
    (while (and matchcol (<= n org-table-current-ncol))
      (if (equal kw (setq field (org-table-get nil n)))
        (setq matchcol nil) ; kw already in column n
      (if (and (= 0 matchcol) (equal "" field))
        (setq matchcol n))) ; remember first empty column
      (setq n (+ 1 n)))
    (when (and matchcol (> matchcol 0))
      (if (= matchcol col) (setq ofc kw))
      (save-excursion
      (org-table-get-field matchcol kw)))))
  ofc))

(defun kanban--todo-links-function ()
  "Retrieve the current header as org-mode link."
  (let ((file (buffer-file-name))
        (line (filter-buffer-substring
               (point) (line-end-position)))
        (keyword (nth (- row 1) org-todo-keywords-1)))
    (if file
        (setq file (concat file "::")))
    ; clean up the string
    (let* (; first remove the initial headline marker FIXME: currently gets later "* ", too
           (cleanline (nth 1 (split-string line "* ")))
           ; and kill off links in the link part
           (link (replace-regexp-in-string "\\[" "%5B"
                                           (replace-regexp-in-string "\\]" "%5D" cleanline)))
           ; then kill off trailing space and tags in the name part
           (notrailing (replace-regexp-in-string "\\( +$\\| +:\\w.*: *$\\)" "" cleanline))
           ; and links
           (nolinks (replace-regexp-in-string
                     "\\[" "{" (replace-regexp-in-string
                                "\\]" "}" (replace-regexp-in-string
                                           "\\[\\[\\(.*\\)\\]\\[\\(.*\\)\\]\\]" "{\\2}" notrailing))))
           ; finally shorten the string to a maximum length of 30 chars
           (clean (substring nolinks
                             (+ (length keyword) 1)
                             (min 30 (length nolinks)))))
      (concat "[[" file link "][" clean "]]" ))))

;; Get TODO of current column from field in row 1
(defun kanban--get-todo-of-current-col ()
  "Get TODO of current column from field in row 1 or nil if
row 1 does not contain a valid TODO"
  (let ((todo (org-table-get 1 nil)))
    (if (member todo org-todo-keywords-1) todo)))

;; Fill the kanban table with tasks with corresponding TODO states from org files
;;;###autoload
(defun kanban-zero (row column &optional match scope)
  "Zero-state Kanban board: This Kanban board just displays all
org-mode headers which have a TODO state in their respective TODO
state. Useful for getting a simple overview of your tasks.

Gets the ROW and COLUMN via TBLFM ($# and @#) and can get a string as MATCH to select only entries with a matching tag, as well as a list of org-mode files as the SCOPE to search for tasks."
  (let*
      ((todo (kanban--get-todo-of-current-col))
       (elem (and todo (nth (- row 2)
                            (delete nil (org-map-entries
                               'kanban--todo-links-function
                               ; select the TODO state via the matcher: just match the TODO.
                               (if match
                                   (concat match "+TODO=\"" todo "\"")
                                 (concat "+TODO=\"" todo "\""))
                               ; read all agenda files
                               (if scope
                                   scope
                                 'agenda)))))))
    (if (equal elem nil)
        ""
      elem)))

; Fill the first column with TODO items, except if they exist in other cels
;;;###autoload
(defun kanban-todo (row cels &optional match scope)
  "Kanban TODO item grabber. Fills the first column of the kanban
table with org-mode TODO entries, if they are not in another cell
of the table. This allows you to set the state manually and just
use org-mode to supply new TODO entries.

Gets the ROW and all other CELS via TBLFM ($# and @2$2..@>$>) and can get a string as MATCH to select only entries with a matching tag, as well as a list of org-mode files as the SCOPE to search for tasks."
 (let ((elem (nth (- row 2) (delete nil
                                   (org-map-entries
                                    (lambda
                                      ()
                                      (let
                                          ((file (buffer-file-name))
                                           (line (filter-buffer-substring (point) (line-end-position)))
                                           (keyword (nth 0 org-todo-keywords-1)))
                                        (if file
                                            (setq file (concat file "::")))
                                        (let* ((cleanline (nth 1 (split-string line "* ")))
                                               (shortline (substring cleanline
                                                                     (+ (length keyword) 1)
                                                                     (min 40 (length cleanline))))
                                               (clean (if (member " " (split-string
                                                                       (substring shortline
                                                                                  (min 25 (length shortline)))
                                                                       ""))
                                                          (mapconcat 'identity
                                                                     (reverse (rest (reverse
                                                                                     (split-string shortline " "))))
                                                                     " ") shortline)))
                                          (concat "[[" file cleanline "][" clean "]]" ))))
                                    (if match
                                        (concat match "+TODO=\"" (nth 0 org-todo-keywords-1) "\"")
                                      (concat "+TODO=\"" (nth 0 org-todo-keywords-1) "\""))
                                    (if scope
                                        scope
                                      'agenda))))))
   (if
       (or (member elem (list cels)) (equal elem nil))
       " " ; the element exists in another table or is nil: Keep the cel empty
     elem))) ; otherwise use the element.



;; An example for auto-updating kanban tables from duply.han
;; I use the double-dash to mark this as "private" function
(defun kanban--update-function (&optional kanbanbufferregexp)
  (when (not (stringp kanbanbufferregexp))
      (setq kanbanbufferregexp "k[a-z]+kk.org"))
  (when (and (stringp buffer-file-name)
             (string-match kanbanbufferregexp buffer-file-name)) ;; match files such as kXXkk.org, kYYkk.org etc.
    (save-excursion
      (beginning-of-buffer)
      (while (search-forward "='(kanban-" nil t)
        (org-ctrl-c-ctrl-c)))))

; The following lines activate the auto-updating.

; (run-at-time "3 min" 180 '(lambda () (kanban--update-function)))
;; refreshes kanban table every 3 min after emacs startup.
; (add-hook 'find-file-hook 'kanban--update-function)

(provide 'kanban)
;;; kanban.el ends here
