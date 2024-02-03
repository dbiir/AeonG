;;;; This file contains common code for generating C++ code.

(in-package #:lcp)

(defun call-with-cpp-block-output (out fun &key semicolonp name)
  "Surround the invocation of FUN by emitting '{' and '}' to OUT.  If
SEMICOLONP is set, the closing '}' is suffixed with ';'.  NAME is used to
prepend the starting block with a name, for example \"class MyClass\"."
  (if name
    (format out "~A {~%" name)
    (write-line "{" out))
  (funcall fun)
  (if semicolonp (write-line "};" out) (write-line "}" out)))

(defmacro with-cpp-block-output ((out &rest rest &key semicolonp name) &body body)
  "Surround BODY with emitting '{' and '}' to OUT.  For additional arguments,
see `CALL-WITH-CPP-BLOCK-OUTPUT' documentation."
  (declare (ignorable semicolonp name))
  `(call-with-cpp-block-output ,out (lambda () ,@body) ,@rest))

(defun call-with-namespaced-output (out fun)
  "Invoke FUN with a function for opening C++ namespaces.  The function takes
care to write namespaces to OUT without redundantly opening already open
namespaces."
  (check-type out stream)
  (check-type fun function)
  (let (open-namespaces)
    (funcall fun (lambda (namespaces)
                   ;; No namespaces is global namespace
                   (unless namespaces
                     (dolist (to-close open-namespaces)
                       (declare (ignore to-close))
                       (format out "~%}")))
                   ;; Check if we need to open or close namespaces
                   (loop :for namespace :in namespaces
                         :with unmatched := open-namespaces :do
                           (if (string= namespace (car unmatched))
                               (setf unmatched (cdr unmatched))
                               (progn
                                 (dolist (to-close unmatched)
                                   (declare (ignore to-close))
                                   (format out "~%}"))
                                 (format out "namespace ~A {~2%" namespace))))
                   (setf open-namespaces namespaces)))
    ;; Close remaining namespaces
    (dolist (to-close open-namespaces)
      (declare (ignore to-close))
      (format out "~%}"))))

(defmacro with-namespaced-output ((out open-namespace-fun) &body body)
  "Use `CALL-WITH-NAMESPACED-OUTPUT' more conveniently by executing BODY in a
context which binds OPEN-NAMESPACE-FUN function for opening namespaces."
  (let ((open-namespace (gensym)))
    `(call-with-namespaced-output
      ,out
      (lambda (,open-namespace)
        (flet ((,open-namespace-fun (namespaces)
                 (funcall ,open-namespace namespaces)))
          ,@body)))))

(defun cpp-documentation (documentation)
  "Convert DOCUMENTATION to Doxygen style string."
  (check-type documentation string)
  (format nil "/// ~A"
          (cl-ppcre:regex-replace-all
           (string #\Newline) documentation (format nil "~%/// "))))

(defvar *cpp-gensym-counter* 0 "Used to generate unique variable names")

(defun cpp-gensym (&optional (prefix "var"))
  "Generate a unique C++ name.

The name is constructed by concatenating the string PREFIX with the current
value of *CPP-GENSYM-COUNTER*. Afterwards, the value of *CPP-GENSYM-COUNTER* is
incremented by 1.

Despite the suggestive name \"gensym\", this function cannot guarantee that the
name is globally unique (because C++ has no concept equivalent to uninterned
symbols). The name is only unique across all of the names generated by the
function."
  (prog1 (format nil "~A~A" prefix *cpp-gensym-counter*)
    (incf *cpp-gensym-counter*)))

(defmacro with-cpp-gensyms (vars &body body)
  "Evaluate and return the result of the implicit progn BODY with the variables
specified within VARS bound to strings representing unique C++ names.

Each element of VARS is either a symbol SYMBOL or a pair (SYMBOL NAME). Bare
symbols are equivalent to the pair (SYMBOL SYMBOL-NAME) where SYMBOL-NAME is the
result of (cpp-name-for-variable SYMBOL).

Each pair (SYMBOL NAME) specifies a single unique C++ name. SYMBOL should be a
symbol naming the variable to which the generated C++ name will bound. NAME
should be a prefix that will be used to construct the name using CPP-GENSYM.

Example:

  (with-cpp-gensyms ((loop-counter \"i\"))
    (format nil \"for (auto ~A = 0; ~A < v.size(); ++~A) {
                    // do something
                  }\"
            loop-counter loop-counter loop-counter))

  ;;; >>
  ;;; for (auto i0 = 0; i0 < v.size(); ++i0) {
  ;;;     // do something
  ;;; }

Example:

  Assume *CPP-GENSYM-COUNTER* is 0.

  (defun gen1 ()
    (with-cpp-gensyms ((hello \"hello\"))
      (format t \"int ~a;~%\" hello)))

  (defun gen2 ()
    (with-cpp-gensyms ((hello \"hello\"))
      (gen1)
      (format t \"int ~a;~%\" hello)))

  (gen2)

  ;;; >>
  ;;; int hello1;
  ;;; int hello0;"
  `(let* (,@(mapcar
              (lambda (var)
                (destructuring-bind (sym &optional name)
                    (alexandria:ensure-list var)
                  (let ((name (or name (cpp-name-for-variable sym))))
                    `(,sym (cpp-gensym ,name)))))
              vars))
     ,@body))

(defun cpp-member-reader-name (cpp-member)
  (check-type cpp-member cpp-member)
  (string-right-trim '(#\_) (cpp-member-name cpp-member)))
