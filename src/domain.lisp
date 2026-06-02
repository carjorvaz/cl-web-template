;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:app.domain)

(defun app-title ()
  "Return the title rendered as the primary page heading."
  "Common Lisp Web App")

(defun app-summary ()
  "Return the short product summary rendered on the home page."
  "A tiny server-rendered scaffold with tests, docs, assets, and browser smoke.")

(defun status-lines ()
  "Return stable status copy for the scaffold home page."
  (list "Domain logic is independent from HTTP."
        "HTML is rendered on the server."
        "Validation scripts are part of the app contract."))
