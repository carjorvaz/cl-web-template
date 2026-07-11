;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(require :asdf)

(defun script-directory ()
  (make-pathname :name nil :type nil :defaults *load-truename*))

(defparameter *project-root*
  (truename (merge-pathnames "../" (script-directory))))

(defparameter *errors* nil)

(defun fail (control &rest arguments)
  (push (apply #'format nil control arguments) *errors*))

(defun root-path (relative-path)
  (merge-pathnames relative-path *project-root*))

(defun read-project-file (relative-path)
  (uiop:read-file-string (root-path relative-path)))

(defun string-starts-with-p (prefix string)
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun markdown-lines-outside-fences (content)
  (let ((lines nil)
        (fence-character nil)
        (fence-length 0))
    (dolist (raw-line (uiop:split-string content :separator '(#\Newline)))
      (let* ((line (string-right-trim '(#\Return) raw-line))
             (leading-spaces
               (loop for character across line
                     while (char= character #\Space)
                     count character))
             (marker-start (and (<= leading-spaces 3) leading-spaces))
             (marker-character
               (and marker-start
                    (< marker-start (length line))
                    (find (char line marker-start) "`~" :test #'char=)
                    (char line marker-start)))
             (marker-length
               (and marker-character
                    (loop for index from marker-start below (length line)
                          while (char= (char line index) marker-character)
                          count marker-character))))
        (cond
          ((and fence-character
                marker-character
                (char= marker-character fence-character)
                (>= marker-length fence-length)
                (every (lambda (character)
                         (find character '(#\Space #\Tab)))
                       (subseq line (+ marker-start marker-length))))
           (setf fence-character nil
                 fence-length 0))
          (fence-character)
          ((and marker-character (>= marker-length 3))
           (setf fence-character marker-character
                 fence-length marker-length))
          (t
           (push line lines)))))
    (nreverse lines)))

(defun markdown-heading-line-p (marker line)
  (let* ((leading-spaces
           (loop for character across line
                 while (char= character #\Space)
                 count character))
         (heading
           (and (<= leading-spaces 3)
                (string-right-trim '(#\Space #\Tab)
                                   (subseq line leading-spaces)))))
    (and heading
         (or (string= marker heading)
             (and (string-starts-with-p marker heading)
                  (> (length heading) (length marker))
                  (find (char heading (length marker)) '(#\Space #\Tab))
                  (let ((closing-hashes
                          (string-left-trim
                            '(#\Space #\Tab)
                            (subseq heading (length marker)))))
                    (and (> (length closing-hashes) 0)
                         (every (lambda (character)
                                  (char= character #\#))
                                closing-hashes))))))))

(defun markdown-marker-line-p (marker line)
  (let ((trimmed-line (string-right-trim '(#\Space #\Tab) line)))
    (if (string= marker "Last reviewed:")
        (and (string-starts-with-p marker trimmed-line)
             (> (length trimmed-line) (length marker))
             (find (char trimmed-line (length marker)) '(#\Space #\Tab))
             (some (lambda (character)
                     (not (find character '(#\Space #\Tab))))
                   (subseq trimmed-line (length marker))))
        (markdown-heading-line-p marker line))))

(defparameter *required-docs*
  '(("docs/README.md" ("Last reviewed:" "## Map" "## Maintenance Rules"))
    ("docs/ARCHITECTURE.md" ("Last reviewed:" "## Components" "## Boundaries" "## Mechanical Guards"))
    ("docs/HARNESS.md" ("Last reviewed:" "## Agent-First Harness" "## Local History" "## Common Lisp Taste" "## Feedback Loops"))
    ("docs/PRODUCT.md" ("Last reviewed:" "## App Contract" "## User Experience"))
    ("docs/RELIABILITY.md" ("Last reviewed:" "## Runtime" "## Feedback Loops"))
    ("docs/QUALITY.md" ("Last reviewed:" "## Current Grade" "## Verification Matrix" "## Known Gaps"))
    ("docs/PLANS.md" ("Last reviewed:" "## When To Create A Plan" "## Plan Location"))
    ("docs/TEMPLATE.md" ("Last reviewed:" "## Purpose" "## Repository Shape" "## Verification Harness"))
    ("docs/technical-debt.md" ("Last reviewed:" "## Known Debt" "## Gardening Rule"))))

(defun validate-file-markers (relative-path markers)
  (let ((pathname (root-path relative-path)))
    (if (not (probe-file pathname))
        (fail "~A is required but missing." relative-path)
        (let ((lines (markdown-lines-outside-fences
                       (read-project-file relative-path))))
          (dolist (marker markers)
            (unless (find-if (lambda (line)
                               (markdown-marker-line-p marker line))
                             lines)
              (fail "~A must contain marker ~S." relative-path marker)))))))

(defun validate-required-docs ()
  (dolist (entry *required-docs*)
    (destructuring-bind (relative-path markers) entry
      (validate-file-markers relative-path markers))))

(defun validate-agent-map ()
  (validate-file-markers "AGENTS.md"
                         '("## Start Here" "## Source Of Truth" "## Feedback Loop")))

(defun lisp-files-under (relative-directories)
  (let ((visited-directories (make-hash-table :test #'equal))
        (visited-files (make-hash-table :test #'equal))
        (files nil))
    (labels ((visit (directory)
               (let* ((canonical-directory (truename directory))
                      (directory-key (namestring canonical-directory)))
                 (unless (gethash directory-key visited-directories)
                   (setf (gethash directory-key visited-directories) t)
                   (dolist (pathname
                            (sort (copy-list
                                   (uiop:directory-files canonical-directory))
                                  #'string<
                                  :key #'namestring))
                     (when (string-equal "lisp" (pathname-type pathname))
                       (let* ((canonical-file (truename pathname))
                              (file-key (namestring canonical-file)))
                         (unless (gethash file-key visited-files)
                           (setf (gethash file-key visited-files) t)
                           (push canonical-file files)))))
                   (dolist (subdirectory
                            (sort (copy-list
                                   (uiop:subdirectories canonical-directory))
                                  #'string<
                                  :key #'namestring))
                     (visit subdirectory))))))
      (dolist (relative-directory relative-directories)
        (visit (root-path relative-directory))))
    (sort files #'string< :key #'namestring)))

(defun first-line (content)
  (string-right-trim '(#\Return)
                     (subseq content 0 (or (position #\Newline content)
                                           (length content)))))

(defun validate-lisp-spdx-headers ()
  (dolist (pathname (lisp-files-under '("src/" "test/" "scripts/")))
    (unless (string= ";;;; SPDX-License-Identifier: AGPL-3.0-or-later"
                     (first-line (uiop:read-file-string pathname)))
      (fail "~A must start with the AGPL SPDX header."
            (enough-namestring pathname *project-root*)))))

(defun main ()
  (validate-agent-map)
  (validate-required-docs)
  (validate-lisp-spdx-headers)
  (if *errors*
      (progn
        (format t "~&Repository harness validation failed:~%")
        (dolist (error (reverse *errors*))
          (format t "- ~A~%" error))
        (uiop:quit 1))
      (progn
        (format t "~&Repository harness validation passed.~%")
        (uiop:quit 0))))

(main)
