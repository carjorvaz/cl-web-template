;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:app.tests)

(in-suite :app)

(defun response-status (response) (first response))
(defun response-headers (response) (second response))
(defun response-body (response) (first (third response)))
(defun header-value (response key)
  (loop for rest on (response-headers response) by #'cddr
        when (string-equal (string key) (string (first rest))) return (second rest)))

(defun make-get-env (path)
  (list :request-method :get
        :path-info path
        :script-name ""
        :query-string ""
        :server-name "localhost"
        :server-port 4242
        :server-protocol :http/1.1
        :url-scheme "http"
        :request-uri path
        :remote-addr "127.0.0.1"
        :headers (make-hash-table :test #'equal)
        :raw-body (make-string-input-stream "")))

(defun app-response (app path)
  (funcall app (make-get-env path)))

(defun call-with-environment-variables (bindings thunk)
  (let ((saved-values
          (loop for binding in bindings
                for name = (car binding)
                collect (cons name (uiop:getenv name)))))
    (unwind-protect
         (progn
           (dolist (binding bindings)
             (setf (uiop:getenv (car binding)) (cdr binding)))
           (funcall thunk))
      (dolist (saved saved-values)
        (if (cdr saved)
            (setf (uiop:getenv (car saved)) (cdr saved))
            (progn
              (require :sb-posix)
              (uiop:symbol-call :sb-posix :unsetenv (car saved))))))))

(test scoped-environment-restores-host-values-after-error
  (let ((saved-app-version (uiop:getenv "APP_VERSION"))
        (saved-source-code-url (uiop:getenv "SOURCE_CODE_URL"))
        (caught-error nil))
    (unwind-protect
         (progn
           (handler-case
               (call-with-environment-variables
                '(("APP_VERSION" . "exception-version")
                  ("SOURCE_CODE_URL" . "https://example.invalid/exception-source"))
                (lambda () (error "Forced scoped-environment exit.")))
             (simple-error () (setf caught-error t)))
           (is (eq caught-error t))
           (is (equal saved-app-version (uiop:getenv "APP_VERSION")))
           (is (equal saved-source-code-url (uiop:getenv "SOURCE_CODE_URL"))))
      (dolist (saved `(("APP_VERSION" . ,saved-app-version)
                       ("SOURCE_CODE_URL" . ,saved-source-code-url)))
        (if (cdr saved)
            (setf (uiop:getenv (car saved)) (cdr saved))
            (progn
              (require :sb-posix)
              (uiop:symbol-call :sb-posix :unsetenv (car saved))))))))

(defparameter *expected-default-security-headers*
  '((:x-content-type-options . "nosniff")
    (:x-frame-options . "DENY")
    (:referrer-policy . "same-origin")
    (:permissions-policy . "camera=(), microphone=(), geolocation=()")
    (:content-security-policy . "default-src 'self'; base-uri 'none'; connect-src 'self'; form-action 'self'; frame-ancestors 'none'; img-src 'self'; object-src 'none'; script-src 'self'; style-src 'self'")))

(defun assert-default-security-headers (response)
  (dolist (entry *expected-default-security-headers*)
    (destructuring-bind (key . value) entry
      (let ((actual (header-value response key)))
        (is (string= value actual)
            "~A header should be ~S, got ~S."
            key value actual)))))

(test home-page-renders-contract
  (let ((response (app.web::home-handler nil)))
    (is (search "Common Lisp Web App" (response-body response)))
    (is (= 200 (response-status response)))
    (is (search "A tiny server-rendered scaffold with tests, docs, assets, and browser smoke."
                (response-body response)))
    (is (search "/health" (response-body response)))
    (is (search "/version" (response-body response)))
    (is (string= "text/html; charset=utf-8" (header-value response :content-type)))
    (assert-default-security-headers response)))

(test operational-routes-honor-scoped-configuration
  (call-with-environment-variables
   '(("APP_VERSION" . "contract-version")
     ("SOURCE_CODE_URL" . "https://example.invalid/source-contract"))
   (lambda ()
     (let* ((app (app.web::make-app))
            (home (app-response app "/"))
            (health (app-response app "/health"))
            (version (app-response app "/version")))
       (is (= 200 (response-status health)))
       (is (string= (format nil "ok~%") (response-body health)))
       (is (string= "text/plain; charset=utf-8" (header-value health :content-type)))
       (assert-default-security-headers health)
       (is (= 200 (response-status version)))
       (is (string= (format nil "contract-version~%") (response-body version)))
       (is (string= "text/plain; charset=utf-8" (header-value version :content-type)))
       (assert-default-security-headers version)
       (let* ((body (response-body home))
              (destination "href=\"https://example.invalid/source-contract\"")
              (source-label ">Source</a>")
              (href-position (search destination body))
              (anchor-position
                (and href-position
                     (search "<a" body :from-end t :end2 href-position))))
         (is (and anchor-position
                  (loop for position from (+ anchor-position 2) below href-position
                        always (member (char body position)
                                       '(#\Space #\Tab #\Newline #\Return)))
                  (let ((label-position (+ href-position (length destination))))
                    (and (<= (+ label-position (length source-label))
                             (length body))
                         (string= source-label body
                                  :start2 label-position
                                  :end2 (+ label-position
                                          (length source-label))))))))
       (assert-default-security-headers home)))))

(test public-static-routes-are-cacheable-and-keep-security-headers
  (let* ((app (app.web::make-app))
         (style (app-response app "/style.css"))
         (app-script (app-response app "/app.js"))
         (htmx (app-response app "/htmx.min.js")))
    (dolist (response (list style app-script htmx))
      (is (= 200 (response-status response)))
      (is (plusp (length (response-body response))))
      (is (string= "public, max-age=3600" (header-value response :cache-control)))
      (assert-default-security-headers response))
    (is (string= "text/css; charset=utf-8" (header-value style :content-type)))
    (is (search ".app{" (response-body style)))
    (is (string= "application/javascript; charset=utf-8"
                 (header-value app-script :content-type)))
    (is (search "document.documentElement.dataset.appReady = 'true';"
                (response-body app-script)))
    (is (string= "application/javascript; charset=utf-8"
                 (header-value htmx :content-type)))
    (is (search "var htmx=function()" (response-body htmx)))))

(test app-boundary-routes-preserve-contracts-and-default-security-headers
  (let* ((app (app.web::make-app))
         (home (app-response app "/"))
         (health (app-response app "/health"))
         (version (app-response app "/version"))
         (missing (app-response app "/missing")))
    (is (= 200 (response-status home)))
    (is (search "Common Lisp Web App" (response-body home)))
    (is (string= "text/html; charset=utf-8" (header-value home :content-type)))
    (assert-default-security-headers home)
    (is (= 200 (response-status health)))
    (is (string= (format nil "ok~%") (response-body health)))
    (is (string= "text/plain; charset=utf-8" (header-value health :content-type)))
    (assert-default-security-headers health)
    (is (= 200 (response-status version)))
    (is (plusp (length (response-body version))))
    (is (string= "text/plain; charset=utf-8" (header-value version :content-type)))
    (assert-default-security-headers version)
    (is (= 404 (response-status missing)))
    (assert-default-security-headers missing)))
