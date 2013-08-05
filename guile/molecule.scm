;;;
;;; Representation of molecular solvents and solutes and site-specific
;;; force field parameters.
;;;
(define-module (guile molecule)
  #:use-module (srfi srfi-1)            ; list manipulation
  #:use-module (srfi srfi-2)            ; and-let*
  #:use-module (ice-9 match)            ; match-lambda
  #:export
  (make-molecule
   molecule-name
   molecule-sites
   find-molecule
   molecule-print/xyz
   make-site
   site-name
   site-position
   site-sigma
   site-epsilon
   site-charge
   site-x
   site-y
   site-z
   tabulate-ff))

;;;
;;; ITC Calorie here. See also bgy3d.h:
;;;
(define (kj->kcal num)
  (/ num 4.1868))
(define (kcal->kj num)
  (* num 4.1868))

;;;
;;; Database  contains  entries in  non-native  units  such as  kJ/mol
;;; represented by an s-expression  like (kJ 0.3640).  Convert them to
;;; working units kcal & angstrom:
;;;
(define (eval-units ast)
  (if (not (pair? ast))
      ast
      (match ast
        (('A num)
         num)                           ; for completeness, default
        (('kcal num)
         num)                           ; for completeness, default
        (('kJ num)
         (kj->kcal num))                ; (kJ 0.3640) -> 0.08694
        (ast
         (map eval-units ast)))))

;;;
;;; Find a solute/solvent in a database or die:
;;;
(define (find-molecule name)
  (or
   (and-let* ((solutes (slurp (find-file "guile/solutes.scm")))
              (molecule (or (assoc name solutes)
                            (error "Not in the list:"
                                   name
                                   (map first solutes)))))
     (eval-units molecule))))



;;;
;;; Find  a file in  the search  patch, or  die.  Note  that find-file
;;; assumes  the %load-path contains  the repo  directory in  order to
;;; find "guile/solutes.scm".
;;;
(define (find-file file)
  (or (search-path %load-path file)
      (error "Not found:" file)))

;;;
;;; Slurps the whole file into a list:
;;;
(define (slurp file)
  (with-input-from-file file
    (lambda ()
      (let loop ((acc (list)))
        (let ((sexp (read)))
          (if (eof-object? sexp)
              (reverse acc)
              (loop (cons sexp acc))))))))

;; (write (slurp "guile/solutes.scm"))
;; (newline)


;;;
;;; Solute parameters are  currently represented by a name  and a list
;;; of sites:
;;;
;;; ("water"
;;;  (("O" (-0.2929 0.0 0.0) 3.1506 0.1521 -0.834)
;;;   ("OH" (0.2929 0.757 0.0) 0.4 0.046 0.417)
;;;   ("OH" (0.2929 -0.757 0.0) 0.4 0.046 0.417)))
;;;
(define (make-molecule name sites)
  (list name sites))

(define (molecule-name solute) (first solute))
(define (molecule-sites solute) (second solute))

;;;
;;; Return  the   force  field   parameter  table  in   each  molecule
;;; description.  FIXME: should check whether there is a "table" there
;;;
(define (molecule-ff-tab solute) (third solute))

;;;
;;; This will return the ff index ("CT3" 77 77)
;;;
(define (ff-tab-find-site site ff-tab)
  (let ((site-name (site-name site))) ; site-name redefined in this scope!
    (or (assoc site-name ff-tab)
        (error "Not in the table:" site-name))))

;;;
;;; This will  return a  list from wholefile  matching the  given atom
;;; type (78 13 CT "Alkane -CH2-" 6 12.011 4)
;;;
(define (find-ff atm-idx whole-file)
  (or (assoc atm-idx whole-file)
      (error "Not in the file:" atm-idx)))

;;;
;;; For  a  single  site,   find  its  relevant  ff  information  from
;;; whole-file and bind them together
;;;
(define (append-ff-site site ff-tab whole-file)
  (let* ((ff-idx (ff-tab-find-site site ff-tab))
	 (atm-idx (second ff-idx))
	 (ff-info (find-ff atm-idx whole-file)))
    ;; Bind sites with ff information
    (append site ff-info)))

;;;
;;; Example to load the ff database as a list, which could be obtained
;;; by tinker-test module
;;;
(define *tinker-ff-parameter-file*
  "guile/oplsaa.scm")

(define (load-ff-file)
  (second (slurp (find-file *tinker-ff-parameter-file*))))

(define (make-site name position sigma epsilon charge)
  (list name position sigma epsilon charge))

(define (site-name site) (first site))
(define (site-position site) (second site))
(define (site-sigma site) (third site))
(define (site-epsilon site) (fourth site))
(define (site-charge site) (fifth site))

(define (site-x site) (first (site-position site)))
(define (site-y site) (second (site-position site)))
(define (site-z site) (third (site-position site)))

(define (molecule-print/xyz solute)
  (let ((name   (molecule-name solute))
        (sites  (molecule-sites solute)))
    (format #t "~a\n" (length sites))
    (format #t "# ~a\n" name)
    (for-each (lambda (site)
                (format #t "~a ~a ~a ~a\n"
                        (site-name site)
                        (site-x site)
                        (site-y site)
                        (site-z site)))
              sites)))

;; (for-each molecule-print/xyz (slurp (find-file "guile/solutes.scm")))
;; (exit 0)

;;;
;;; This will be called from  outside, append each site in solute with
;;; force field information
;;;
(define (tabulate-ff solute)
  (let ((sites (molecule-sites solute))
        (ff-tab (molecule-ff-tab solute))
        (whole-file (load-ff-file)))
        (let ((newsites
		(map (lambda (site)
		       (append-ff-site site ff-tab whole-file)) sites)))
    (make-molecule (molecule-name solute) newsites ))))
