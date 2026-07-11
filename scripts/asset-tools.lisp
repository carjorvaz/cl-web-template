;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(require :asdf)

(defun script-directory ()
  (make-pathname :name nil :type nil :defaults *load-truename*))

(defparameter *project-root*
  (truename (merge-pathnames "../" (script-directory))))

(pushnew *project-root* asdf:*central-registry* :test #'equal)
(asdf:load-system :app/assets)

(defpackage #:app.asset-tools
  (:use #:cl)
  (:export #:build-assets #:generated-stylesheet #:stylesheet-target-path))

(in-package #:app.asset-tools)

(defparameter *project-root* (asdf:system-source-directory :app))
(defparameter +stylesheet-header+
  "/* Generated from assets/style.lass. Run scripts/build-assets.lisp after edits. */")

(defun project-path (relative-path)
  (merge-pathnames relative-path *project-root*))

(defun stylesheet-source-path ()
  (project-path "assets/style.lass"))

(defun stylesheet-target-path ()
  (project-path "static/style.css"))


(defun read-generated-lass-css ()
  (uiop:with-temporary-file (:pathname temporary-path
                             :prefix "app-style-"
                             :type "css")
    (lass:generate (stylesheet-source-path) :out temporary-path :pretty t)
    (uiop:read-file-string temporary-path)))

(defun ensure-trailing-newline (content)
  (if (and (plusp (length content))
           (char= #\Newline (char content (1- (length content)))))
      content
      (format nil "~A~%" content)))

(defun generated-stylesheet ()
  (format nil "~A~%~%~A" +stylesheet-header+
          (ensure-trailing-newline (read-generated-lass-css))))

(defun build-assets ()
  (let ((content (generated-stylesheet)))
    (let ((target-path (stylesheet-target-path)))
      (ensure-directories-exist target-path)
      (uiop:with-temporary-file
          (:pathname temporary-path
           :directory (uiop:pathname-directory-pathname target-path)
           :prefix ".style-"
           :type "css")
        (with-open-file (stream temporary-path
                                :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :error)
          (write-string content stream))
        (uiop:rename-file-overwriting-target temporary-path target-path))))
  (format t "~&Generated ~A from ~A.~%"
          (enough-namestring (stylesheet-target-path) *project-root*)
          (enough-namestring (stylesheet-source-path) *project-root*)))
