;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(require :asdf)

(defun script-directory ()
  (make-pathname :name nil :type nil :defaults *load-truename*))

(defparameter *project-root*
  (truename (merge-pathnames "../" (script-directory))))

(defparameter *errors* nil)

(defparameter *forbidden-package-roots*
  '("APP.WEB" "CLACK" "LACK" "NINGLE" "SPINNERET" "LASS"))

(defun fail (control &rest arguments)
  (push (apply #'format nil control arguments) *errors*))

(defun root-path (relative-path)
  (merge-pathnames relative-path *project-root*))

(defun designator-name (designator)
  (string-upcase
   (etypecase designator
     (string designator)
     (symbol (symbol-name designator))
     (package (package-name designator)))))

(defun forbidden-package-name-p (designator)
  (let ((name (designator-name designator)))
    (some (lambda (root)
            (or (string= name root)
                (and (> (length name) (length root))
                     (string= name root :end1 (length root))
                     (member (char name (length root)) '(#\. #\/) :test #'char=))))
          *forbidden-package-roots*)))

(defun app-package-name-p (designator)
  (let ((name (designator-name designator)))
    (or (string= name "APP")
        (and (> (length name) 4)
             (string= name "APP." :end1 4)))))

(defun form-operator-p (form name)
  (and (consp form)
       (symbolp (car form))
       (string= (symbol-name (car form)) name)))

(defun read-forms (pathname)
  (with-open-file (stream pathname :direction :input)
    (let ((*read-eval* nil)
          (eof (gensym "EOF")))
      (loop for form = (read stream nil eof)
            until (eq form eof)
            collect form))))

(defun component-source-files (component)
  (if (typep component 'asdf:cl-source-file)
      (list component)
      (mapcan #'component-source-files
              (asdf:component-children component))))

(defun component-named-p (component name)
  (string-equal (asdf:component-name component) name))

(defun defpackage-form-p (form)
  (form-operator-p form "DEFPACKAGE"))

(defun ensure-declared-packages (forms)
  ;; Reading a qualified symbol requires its package to exist.  Construct only
  ;; the packages and exports declared by the project's DEFPACKAGE forms; do
  ;; not evaluate arbitrary source while validating it.
  (dolist (form forms)
    (when (defpackage-form-p form)
      (let* ((name (designator-name (second form)))
             (package (or (find-package name)
                          (make-package name :use nil))))
        (dolist (clause (cddr form))
          (when (and (consp clause)
                     (symbolp (car clause))
                     (string= (symbol-name (car clause)) "EXPORT"))
            (dolist (export (cdr clause))
              (export (intern (designator-name export) package) package))))))))

(defun forbidden-package-dependency-in-defpackage (form)
  (labels ((forbidden (thing)
             (and (or (symbolp thing) (stringp thing))
                  (forbidden-package-name-p thing))))
    (loop for clause in (cddr form)
          thereis
          (and (consp clause)
               (let ((kind (designator-name (car clause))))
                 (cond
                   ((member kind '("USE" "USE-REEXPORT") :test #'string=)
                    (find-if #'forbidden (cdr clause)))
                   ((member kind '("IMPORT-FROM" "SHADOWING-IMPORT-FROM"
                                   "REEXPORT-FROM")
                            :test #'string=)
                    (and (second clause) (forbidden (second clause))))
                   ((string= kind "LOCAL-NICKNAMES")
                    (some (lambda (nickname)
                            (and (consp nickname)
                                 (second nickname)
                                 (forbidden (second nickname))))
                          (cdr clause)))))))))

(defun lower-layer-defpackage-p (form)
  (and (defpackage-form-p form)
       (app-package-name-p (second form))
       (not (string= (designator-name (second form)) "APP.WEB"))))

(defun symbol-forbidden-package-p (symbol)
  (let ((package (symbol-package symbol)))
    (and package (forbidden-package-name-p package))))

(defun constant-value (form)
  (if (form-operator-p form "QUOTE")
      (second form)
      form))

(defun package-lookup-dependency (form)
  (when (and (consp form) (symbolp (car form)))
    (let ((operator (symbol-name (car form))))
      (labels ((forbidden-value-p (value)
                 (cond
                   ((or (symbolp value) (stringp value))
                    (forbidden-package-name-p value))
                   ((consp value)
                    (some #'forbidden-value-p value))))
               (forbidden-argument-p (argument)
                 (forbidden-value-p (constant-value argument))))
        (cond
          ((member operator '("DELETE-PACKAGE" "FIND-PACKAGE" "FIND-SYSTEM"
                              "IN-PACKAGE" "LOAD-SYSTEM" "PACKAGE-USE-LIST"
                              "QUICKLOAD" "RENAME-PACKAGE" "REQUIRE"
                              "SYMBOL-CALL" "USE-PACKAGE")
                   :test #'string=)
           (and (second form) (forbidden-argument-p (second form))))
          ((member operator '("INTERN" "FIND-SYMBOL") :test #'string=)
           (and (third form) (forbidden-argument-p (third form)))))))))

(defun asset-reference-string-p (string)
  (let ((value (string-downcase string)))
    (and (notany (lambda (character)
                   (member character '(#\Space #\Tab #\Newline #\Return)))
                 value)
         (or (uiop:string-prefix-p "static/" value)
             (uiop:string-prefix-p "/static/" value)
             (uiop:string-prefix-p "assets/" value)
             (uiop:string-prefix-p "/assets/" value)
             (some (lambda (suffix)
                     (uiop:string-suffix-p suffix value))
                   '(".css" ".js" ".mjs" ".svg" ".png" ".woff" ".woff2"))
             (string= value "htmx")
             (search "htmx." value :test #'char=)))))
(defun pathname-asset-reference-p (pathname)
  (asset-reference-string-p (namestring pathname)))

(defun form-boundary-violation (form)
  (labels ((documentation-position-p (form position)
             (let ((operator (and (symbolp (car form))
                                  (symbol-name (car form)))))
               (or (and (member operator '("DEFUN" "DEFMACRO") :test #'string=)
                        (= position 3))
                   (and (member operator '("DEFVAR" "DEFPARAMETER"
                                           "DEFCONSTANT")
                                :test #'string=)
                        (= position 3))
                   (and operator (string= operator "DOCUMENTATION")))))
           (walk (value &optional parent position)
             (cond
               ((symbolp value)
                (or (symbol-forbidden-package-p value)
                    (asset-reference-string-p (symbol-name value))))
               ((pathnamep value) (pathname-asset-reference-p value))
               ((stringp value)
                (and parent
                     (not (documentation-position-p parent position))
                     (asset-reference-string-p value)))
               ((consp value)
                (or (package-lookup-dependency value)
                    (loop for item in value
                          for item-position from 0
                          thereis (walk item value item-position)))))))
    (walk form)))

(defun report-read-error (component condition)
  (let ((package (and (typep condition 'package-error)
                      (package-error-package condition))))
    (if (and package (forbidden-package-name-p package))
        (fail "~A has a forbidden dependency on package ~A."
              (asdf:component-relative-pathname component)
              (designator-name package))
        (fail "~A could not be read safely: ~A"
              (asdf:component-relative-pathname component)
              condition))))

(defun read-component-forms (component)
  (handler-case
      (read-forms (asdf:component-pathname component))
    (error (condition)
      (report-read-error component condition)
      nil)))

(defun validate-lower-layer (component forms)
  (when (some (lambda (form)
                (or (and (lower-layer-defpackage-p form)
                         (forbidden-package-dependency-in-defpackage form))
                    (and (not (defpackage-form-p form))
                         (form-boundary-violation form))))
              forms)
    (fail "~A has a web, adapter, or browser/static asset dependency."
          (asdf:component-relative-pathname component))))

(defun validate-component-order (components)
  (let ((package-positions nil)
        (web-positions nil)
        (lower-positions nil))
    (loop for component in components
          for position from 0
          do (cond
               ((component-named-p component "package")
                (push position package-positions))
               ((component-named-p component "web")
                (push position web-positions))
               (t (push position lower-positions))))
    (cond
      ((null package-positions)
       (fail "The app system must contain a package source component."))
      ((null lower-positions)
       (fail "The app system must contain at least one lower-layer source component."))
      ((null web-positions)
       (fail "The app system must contain a web source component."))
      ((not (and (< (apply #'max package-positions)
                    (apply #'min lower-positions))
                 (< (apply #'max lower-positions)
                    (apply #'min web-positions))))
       (fail "The app component graph must load package, all lower-layer sources, then web.")))))

(defun validate-architecture ()
  (handler-case
      (let ((definition (truename (root-path "app.asd"))))
        (let ((*read-eval* nil))
          (asdf:load-asd definition))
        (let* ((system (asdf:find-system "app"))
               (components (component-source-files system))
               (package-components
                 (remove-if-not (lambda (component)
                                  (component-named-p component "package"))
                                components))
               (web-components
                 (remove-if-not (lambda (component)
                                  (component-named-p component "web"))
                                components))
               (lower-components
                 (remove-if (lambda (component)
                              (or (component-named-p component "package")
                                  (component-named-p component "web")))
                            components))
               (package-forms
                 (mapcan #'read-component-forms package-components)))
          (unless (equal definition
                         (truename (asdf:system-source-file system)))
            (error "ASDF resolved app from a different definition."))
          (validate-component-order components)
          (ensure-declared-packages package-forms)
          (dolist (component package-components)
            (validate-lower-layer component
                                  (read-component-forms component)))
          (dolist (component lower-components)
            (let ((forms (read-component-forms component)))
              (ensure-declared-packages forms)
              (validate-lower-layer component forms)))))
    (error (condition)
      (fail "Could not inspect the app component graph: ~A" condition))))

(defun main ()
  (validate-architecture)
  (if *errors*
      (progn
        (format t "~&Architecture validation failed:~%")
        (dolist (error (reverse *errors*))
          (format t "- ~A~%" error))
        (uiop:quit 1))
      (progn
        (format t "~&Architecture validation passed.~%")
        (uiop:quit 0))))

(main)
