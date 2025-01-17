;;; org-toggl.el --- A simple Org-mode interface to Toggl  -*- lexical-binding: t; -*-

;; Copyright (C) 2016  Marcin Borkowski

;; Author: Marcin Borkowski <mbork@mbork.pl>
;; Keywords: calendar
;; Package-Requires: ((request "0.2.0"))

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; A simple Org-mode interface to Toggl, a time-tracking service.
;; Hooks into the Org-mode's clocking mechanism.

;;; Code:

(require 'json)
(require 'request)

(defcustom toggl-auth-token ""
  "Authentication token for Toggl."
  :type 'string
  :group 'toggl)

(defcustom toggl-workspace-id ""
  "Toggl workspace id to work with"
  :type 'integer
  :group 'toggl)

(defcustom toggl-default-timeout 20
  "Default timeout for HTTP requests."
  :type 'integer
  :group 'toggl)

(defvar toggl-api-url "https://api.track.toggl.com/api/v9/workspaces/"
  "The URL for making API calls.")

(defun toggl-create-api-url (string)
  "Prepend Toogl API URL to STRING."
  (concat toggl-api-url toggl-workspace-id string))

(defun toggl-prepare-auth-header ()
  "Return a cons to be put into headers for authentication."
  (cons "Authorization"
	(format "Basic %s" (base64-encode-string (concat toggl-auth-token ":api_token")))))

(defun toggl-request-get (request &optional sync success-fun error-fun timeout)
  "Send a GET REQUEST to toggl.com, with TIMEOUT.
Add the auth token)."
  (request (toggl-create-api-url request)
	   :parser #'json-read
	   :headers (list (toggl-prepare-auth-header))
	   :success success-fun
	   :error error-fun
	   :sync sync
	   :timeout (or timeout toggl-default-timeout)))

(defun toggl-request-post (request data &optional sync success-fun error-fun timeout)
  "Send a POST REQUEST to toggl.com, with TIMEOUT.
Add the auth token)."
  (request (toggl-create-api-url request)
	   :type "POST"
	   :data data
	   :parser #'json-read
	   :headers (list (toggl-prepare-auth-header)
			  '("Content-Type" . "application/json"))
	   :success success-fun
	   :error error-fun
	   :sync sync
	   :timeout (or timeout toggl-default-timeout)))

(defun toggl-request-patch (request data &optional sync success-fun error-fun timeout)
  "Send PATCH REQUEST to toggl.com, with TIMEOUT.
Add the auth token)."
  (request (toggl-create-api-url request)
	   :type "PATCH"
	   :data data
	   :parser #'json-read
	   :headers (list (toggl-prepare-auth-header)
			  '("Content-Type" . "application/json"))
	   :success success-fun
	   :error error-fun
	   :sync sync
	   :timeout (or timeout toggl-default-timeout)))

(defun toggl-request-delete (request &optional sync success-fun error-fun timeout)
  "Send a DELETE REQUEST to toggl.com, with TIMEOUT.
Add the auth token)."
  (request (toggl-create-api-url request)
	   :type "DELETE"
	   :parser 'buffer-string
	   :headers (list (toggl-prepare-auth-header))
	   :success success-fun
	   :error error-fun
	   :sync sync
	   :timeout (or timeout toggl-default-timeout)))

(defvar toggl-projects nil
  "A list of available projects.
Each project is a cons cell with car equal to its name and cdr to
its id.")

(defvar toggl-current-time-entry nil
  "Data of the current Toggl time entry.")

(defun toggl-get-projects ()
  "Fill in `toggl-projects' (asynchronously)."
  (interactive)
  (toggl-request-get
   "/projects"
   nil
   (cl-function
    (lambda (&key data &allow-other-keys)
      (setq toggl-projects
            (mapcar (lambda (project)
                      (cons (substring-no-properties (alist-get 'name project)) (alist-get 'id project)))
                    data
                    )
            )
      (message "Toggl projects successfully downloaded.")))
   (cl-function
    (lambda (&key error-thrown &allow-other-keys)
      (message "Fetching projects failed because %s" error-thrown)))))

(defvar toggl-default-project nil
  "Id of the default Toggl project.")

(defun toggl-select-default-project (project)
  "Make PROJECT the default.
It is assumed that no two projects have the same name."
  (interactive (list (completing-read "Default project: " toggl-projects nil t)))
  (setq toggl-default-project (toggl-get-pid project)))

(defun toggl-select-project (project)
  "Select project id by selecting interactively with a list of names"
  (interactive (list (completing-read "Select the project where the time entry will be regitered: "
                                      toggl-projects nil t)
                     )
               )
  (setq project project)
  )



(defun toggl-get-project-id-by-name (project)
  "Select project id by selecting interactively with a list of names"
  (interactive (list (completing-read "Select the project where the time entry will be regitered: " toggl-projects nil t)))
  (toggl-get-pid project))


(defun format-time-zone-offset (offset)
  "Formats the time zone OFFSET as HH:MM."
  (let ((time (format-time-string "%z")))
    (concat
     (substring time 0 3)
     ":"
     (substring time 3)))
  )

(defun get-current-date-time ()
  (concat (format-time-string "%Y-%m-%dT%H:%M:%S" (current-time))
          (format-time-zone-offset (format-time-string "%z" (current-time)))
          )
)

(defun toggl-start-time-entry (&optional description tags pid show-message)
  "Start Toggl time entry.
   if description is not set then it will ask it
   if pid is not set  then it will ask it from the list of projects
   tags is passed as a list in order to convert it to json array
   "
  (interactive)
  (setq description (or description (read-from-minibuffer "Please enter a description for the task: ")))

  (toggl-request-post
   "/time_entries"
   (json-encode `(("description" . ,description)
                  ("project_id" . ,pid)
		              ("created_with" . "mbork's Emacs toggl client")
                  ("start" . ,(get-current-date-time))
                  ("wid" . ,(string-to-number toggl-workspace-id))
                  ("tags" . ,tags)
                  ("duration" . -1)
                  ))
   nil
   (cl-function
    (lambda (&key data &allow-other-keys)
      (setq toggl-current-time-entry data)
      (when show-message (message "Toggl time entry started."))
      )
    )
   (cl-function
    (lambda (&key error-thrown &allow-other-keys)
      (when show-message (message "Starting time entry failed because %s" error-thrown)))
    )
   )

  )

(defun toggl-stop-time-entry (&optional show-message)
  "Stop running Toggl time entry."
  (interactive "p")
  (when toggl-current-time-entry
    (toggl-request-patch
     (format "/time_entries/%s/stop"
	     (alist-get 'id toggl-current-time-entry))
     nil
     nil
     (cl-function
      (lambda (&key data &allow-other-keys)
	(when show-message (message "Toggl time entry stopped."))))
     (cl-function
      (lambda (&key error-thrown &allow-other-keys)
	(when show-message (message "Stopping time entry failed because %s" error-thrown)))))
    (setq toggl-current-time-entry nil)))

(defun toggl-delete-time-entry (&optional tid show-message)
  "Delete a Toggl time entry.
By default, delete the current one."
  (interactive "ip")
  (when toggl-current-time-entry
    (toggl-request-delete
     (format "/time_entries/%s" (alist-get 'id toggl-current-time-entry))
     nil
     (cl-function
      (lambda (&key response &allow-other-keys)
        (when (= (request-response-status-code response) 200)
          (setq toggl-current-time-entry nil))
		      (when show-message (message "Toggl time entry deleted.")))
      )
     (cl-function
      (lambda (&key error-thrown &allow-other-keys)
	(when show-message (message "Deleting time entry failed because %s" error-thrown)))))))

(defun toggl-get-pid (project)
  "Get PID given PROJECT's name."
  (cdr (assoc project toggl-projects)))

(defcustom org-toggl-inherit-toggl-properties nil
  "Make org-toggl use property inheritance."
  :type 'boolean
  :group 'toggl)

;(defun org-toggl-clock ()
;  "Start a Toggl time entry based on current heading."
;  (interactive)
;  (let* ((heading (substring-no-properties (org-get-heading t t t t)))
;	 (project (org-entry-get (point) "toggl-project" org-toggl-inherit-toggl-properties))
;	 (pid (toggl-get-pid project)))
;    (when pid (toggl-start-time-entry heading pid t))))

(defun org-toggl-clock-in ()
  "Start a Toggl time entry based on current heading."
  (interactive)
  (when (not (org-entry-get nil "TOGGL_PROJECT"))
    (org-set-property "TOGGL_PROJECT" (call-interactively 'toggl-select-project))
    )

  (toggl-start-time-entry
   (org-get-heading t t t t)
   (org-get-tags nil t)
   (toggl-get-project-id-by-name (org-entry-get nil "TOGGL_PROJECT"))
   t
   )
  )

(defun org-toggl-clock-out ()
  "Stop the running Toggle time entry."
  (toggl-stop-time-entry t))

(defun org-toggl-clock-cancel ()
  "Delete the running Toggle time entry."
  (toggl-delete-time-entry nil t))


(define-minor-mode org-toggl-integration-mode
  "Toggle a (global) minor mode for Org/Toggl integration.
When on, clocking in and out starts and stops Toggl time entries
automatically."
  :init-value nil
  :global t
  :lighter " T-O"
  (if org-toggl-integration-mode
      (progn
	(add-hook 'org-clock-in-hook #'org-toggl-clock-in)
	(add-hook 'org-clock-out-hook #'org-toggl-clock-out)
	(add-hook 'org-clock-cancel-hook #'org-toggl-clock-cancel))
    (remove-hook 'org-clock-in-hook #'org-toggl-clock-in)
    (remove-hook 'org-clock-out-hook #'org-toggl-clock-out)
    (remove-hook 'org-clock-cancel-hook #'org-toggl-clock-cancel)))

(provide 'org-toggl)
;;; org-toggl.el ends here
