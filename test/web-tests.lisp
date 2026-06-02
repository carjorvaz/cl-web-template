;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:app.tests)

(in-suite :app)

(defun response-status (response) (first response))
(defun response-headers (response) (second response))
(defun response-body (response) (first (third response)))
(defun header-value (response key)
  (loop for rest on (response-headers response) by #'cddr
        when (string-equal (string key) (string (first rest))) return (second rest)))

(defun get-env (path)
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
  (funcall app (get-env path)))

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
    (is (= 200 (response-status response)))
    (is (search "Common Lisp Web App" (response-body response)))
    (is (search "/health" (response-body response)))
    (is (search "/version" (response-body response)))
    (is (string= "text/html; charset=utf-8" (header-value response :content-type)))
    (assert-default-security-headers response)))

(test operational-routes-are-plain-text
  (let ((health (app.web::health-handler nil))
        (version (app.web::version-handler nil)))
    (is (= 200 (response-status health)))
    (is (string= (format nil "ok~%") (response-body health)))
    (is (string= "text/plain; charset=utf-8" (header-value health :content-type)))
    (assert-default-security-headers health)
    (is (= 200 (response-status version)))
    (is (plusp (length (response-body version))))
    (is (string= "text/plain; charset=utf-8" (header-value version :content-type)))
    (assert-default-security-headers version)))

(test static-css-asset-is-cacheable-and-keeps-security-headers
  (let ((response (app.web::asset-response "static/style.css" "text/css; charset=utf-8")))
    (is (= 200 (response-status response)))
    (is (plusp (length (response-body response))))
    (is (string= "text/css; charset=utf-8" (header-value response :content-type)))
    (is (string= "public, max-age=3600" (header-value response :cache-control)))
    (assert-default-security-headers response)))

(test app-boundary-routes-keep-default-security-headers
  (let* ((app (app.web::make-app))
         (home (app-response app "/"))
         (health (app-response app "/health"))
         (missing (app-response app "/missing")))
    (is (= 200 (response-status home)))
    (is (search "Common Lisp Web App" (response-body home)))
    (assert-default-security-headers home)
    (is (= 200 (response-status health)))
    (is (string= (format nil "ok~%") (response-body health)))
    (assert-default-security-headers health)
    (is (= 404 (response-status missing)))
    (assert-default-security-headers missing)))
