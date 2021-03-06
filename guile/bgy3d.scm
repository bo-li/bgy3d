;;;
;;; Copyright (c) 2013, 2014 Alexei Matveev
;;; Copyright (c) 2013 Bo Li
;;;
;;; Scheme  interface  to  BGY3d  code.   Not to  pollute  the  global
;;; namespace  we put bgy3d-*  functions into  this module.
;;;
(define-module (guile bgy3d)
  #:use-module (guile compat)           ; define-syntax-rule for 1.8
  #:use-module (guile molecule)         ; site representation
  #:use-module (guile punch-file)       ; write-punch-file
  #:use-module (guile utils)            ; memoize
  #:use-module (srfi srfi-1)            ; list manipulation
  #:use-module (srfi srfi-2)            ; and-let*
  #:use-module (srfi srfi-11)           ; let-values
  #:use-module (ice-9 match)            ; match-lambda
  #:use-module (ice-9 pretty-print)     ; pretty-print
  #:use-module (ice-9 getopt-long)      ; getopt-long, option-ref
  #:use-module (ice-9 threads)
  #:use-module (system foreign)         ; %null-pointer
  ;; #:use-module (rnrs bytevectors)       ; make-bytevector, etc.
  ;; #:use-module (rnrs io ports)          ; make-custom-binary-output-port, etc.
  #:use-module (guile bgy3d internal)   ; see bgy3d-guile.c
  #:re-export                           ; from (guile bgy3d internal)
  (state-make
   state-destroy
   vec-make
   vec-make-complex
   vec-destroy
   vec-save
   vec-set-random
   vec-dot
   vec-fft
   vec-ifft
   vec-fft-interp
   vec-map1
   vec-map2
   vec-moments
   vec-shift!
   vec-scale!
   ;; See eos.f90:
   eos-alj
   eos-alj-res
   eos-plj
   eos-ulj
   ;; See bgy3d-solutes.c:
   lj0
   lj1
   ljcap0
   ljcap1
   cl0
   cl1
   cs0
   cs1
   cscap0
   cscap1
   ccap0
   ccap1
   ;; See bgy3d-guile.c and ./lebed:
   genpts
   f64dst
   f64+
   f64*
   f64scale
   least-squares
   comm-size
   comm-rank
   comm-set-parallel!
   ;; comm-bcast!
   bgy3d-restart-destroy
   bgy3d-pot-destroy
   ;; from (system foreign):
   %null-pointer
   )
  #:export
  (bgy3d-main
   parse-command-line
   rism-solvent
   rism-solute
   rism-self-energy
   hnc3d-run-solvent
   hnc3d-run-solute
   bgy3d-run-solvent
   bgy3d-run-solute
   destroy
   make-pes
   env-ref
   env-set
   mesh/lin
   mesh/log
   linspace
   *settings*
   *server*
   vec-print
   vec-norm
   eos-mulj
   solvent/solvent
   solute/solvent
   pretty-print/serial
   ;; Syntax
   begin/serial
   ))

(cond-expand
 ((not guile-2))
 (else
  (use-modules (rnrs bytevectors))
  (use-modules (rnrs io ports))))

;;;
;;; The list of the procedures defined in bgy3d-guile.c includes
;;;
;;;   rism-solvent/c
;;;   rism-solute/c
;;;   rism-self-energy/c
;;;   hnc3d-run-solvent/c
;;;   hnc3d-run-solute/c
;;;   bgy3d-run-solvent/c
;;;   bgy3d-run-solute/c
;;;   bgy3d-pot-interp
;;;   bgy3d-pot-destroy
;;;   bgy3d-restart-destroy
;;;   vec-make
;;;   vec-make-complex
;;;   vec-destroy
;;;   vec-save
;;;   vec-load
;;;   vec-length
;;;   vec-ref
;;;   vec-set-random
;;;   vec-dot
;;;   vec-fft
;;;   vec-ifft
;;;   vec-fft-interp
;;;   vec-map1
;;;   vec-map2
;;;   vec-moments
;;;   vec-shift!
;;;   vec-scale!
;;;   comm-rank
;;;   comm-size
;;;   state-make
;;;   state-destroy
;;;   least-squares (depends on MINPACK)
;;;
;;; and  possibly  more, depending  on  the  compilation options.  The
;;; definitions are  put into (guile bgy3d  internal) module, imported
;;; here  and  re-exported  selectively  (see use-modules  form).   An
;;; earlier  version actively  invoked the  procedure to  define those
;;; symbols. However, this caused annoying warnings with Guile 2 which
;;; complains about "possibly undefined symbols" at compile time.
;;;

;;;
;;; μ = A + P/ρ - T
;;;
(define (eos-mulj T rho)
  (let ((A (eos-alj T rho))
        (P (eos-plj T rho)))
    (+ A (/ P rho) (- T))))

;;;
;;; This  form can  be  used for  code  to be  evaluated  only on  one
;;; (master)  worker. In  particular no  collective procedures  can be
;;; used from this context. Do not assume the forms are evaluated:
;;;
(define-syntax-rule (begin/serial e ...)
  (begin
    (if (zero? (comm-rank))
        (begin e ...))
    (if #f #f)))

(define (pretty-print/serial . args)
  (begin/serial
   (apply pretty-print args)
   (force-output)))

;;;
;;; On root rank  return an output port, on all  other ranks return an
;;; input  port. Writing  to this  port  (from the  writer side)  will
;;; broadcast the data to all reader ranks.
;;;
;;; Beware of buffering issues: a simple (write data port) does almost
;;; no buffering each written number is transfered in a transaction of
;;; just a  few bytes.  On the  other hand a  (put-bytevector port bv)
;;; will  pass the  bytevector through  irrespective of  how  big that
;;; is. Obviousely, many small broadcasts are slow.
;;;
;;; Note that reading lists like (1.23) does not need look-ahead --- a
;;; closing paren is  unambigous. When reading things like  #f or 1.23
;;; the reader  needs to know  the stream is  over.  In this  case the
;;; reader  posts  another  request  for  data which  then  should  be
;;; satisfied by  writer sending zero  bytes. It is important  to keep
;;; the number of calls to bcast! the same over all workers, otherwise
;;; they deadlock.
;;;
(define (make-bcast-port root)
  (let* ((eof? #f)                      ; set! to #t later
         (rank (comm-rank))
         (bcast! (lambda (bv i n)
                   (let ((n (comm-bcast! root bv i n)))
                     (if (zero? n) (set! eof? #t))
                     n))) ; must return the number of bytes read/written
         (close (lambda ()
                  (if (not eof?)
                      (bcast! (make-bytevector 0) 0 0)))))
    (let ((port (if (equal? rank root)
                    (make-custom-binary-output-port "o" bcast! #f #f close)
                    (make-custom-binary-input-port "i" bcast! #f #f close))))
      ;; (setvbuf  port _IOFBF BUFFER-SIZE) will not  work on custom
      ;; binary ports as of 2.0.5
      port)))

;;;
;;; Should  we build our  own with-output-to-bytevector  instead? Data
;;; serialized like this is READ in comm-bcast on the reader side.
;;;
(define (serialize data)
  (let-values (((port get-bytes) (open-bytevector-output-port)))
    (write data port)
    (let ((bytes (get-bytes)))
      (close-port port)
      bytes)))

(define (deserialize bytes)
  (let ((port (open-bytevector-input-port bytes)))
    (let ((data (read port)))
      (close-port port)
      data)))

;;;
;;; One could do this with data read from external sources to increase
;;; consistency:
;;;
(define (normalize data)
  (deserialize (serialize data)))

;;; Returns data  as broadcast from the  root rank. The  input data on
;;; reader ranks  is ignored (but  reguired as argument).   FIXME: any
;;; better interface?
;;;
(define (comm-bcast root data)
  (let ((rank (comm-rank))
        (port (make-bcast-port root)))
    (let ((data' (if (equal? rank root)
                     ;; Writer side. Note that a plain old (write data
                     ;; port)  would also  work, albeit slower  --- as
                     ;; every MPI broadcast will be just a few bytes.
                     (let ((bytes (serialize data)))
                       (put-bytevector port bytes)
                       ;; FIXME: Scheme tries (but fails) to guarantee
                       ;; that a write/read is a no-op for simple data
                       ;; structures. In this way bcast will return
                       ;; the same on all workers or fail:
                       (let ((data' (deserialize bytes)))
                         ;; (unless (equal? data data')
                         ;;   (error "conversion error, diff=" (diff data data')))
                         data'))
                     ;; Reader side:
                     (read port))))
      (close-port port)
      data')))

;;;
;;; Here rank-0 reads the fifo and broadcasts the data to everyone:
;;;
(define (read-fifo fifo)
  (let ((rank (comm-rank)))
    (comm-bcast 0 (when (zero? rank)
                    (normalize (with-input-from-file fifo read))))))

;;;
;;; Rank-0   writes  to  fifo,   on  other   workesrs  the   input  is
;;; ignored. Return value is unspecfied:
;;;
(define (write-fifo fifo data)
  (let ((rank (comm-rank)))
    (when (zero? rank)
      (with-output-to-file fifo (lambda () (write data)))))
  (if #f #f))

;;;
;;; This is  called on  all workers. But  only rank-0 should  read the
;;; FIFO.  The reader will block for measurable time (minutes).  Other
;;; workers should not  be too eagerly waiting for  the result because
;;; of agressive polling used  by MPI_Bcast().  Otherwise everyone but
;;; rank-0 burns 100% CPU.
;;;
(define (read-fifo-v2 fifo)
  (let ((flag #f)
        (data #f)
        (mutex (make-mutex)))
    ;; This thread (created on  rank-0) blocks on reading a FIFO, when
    ;; done sets two globals secured by the mutex:
    (let ((helper (if (zero? (comm-rank))
                      (make-thread
                       (lambda ()
                         (let ((value (normalize (with-input-from-file fifo read))))
                           (with-mutex mutex
                                       (set! data value)
                                       (set! flag #t)))))
                      #f)))
      ;; Every worker checks the value of the flag on rank-0. If the
      ;; data has not yet arrived, then sleep for some time and
      ;; repeat. Access to flag needs to be secured by a mutex on
      ;; rank-0. FIXME: other workers dont need a mutex, actually.
      (let loop ()
        (unless (comm-bcast 0 (with-mutex mutex flag))
                (usleep 100000)         ; FIXME: literal 0.1 sec
                (loop)))
      (when helper (join-thread helper))
      (comm-bcast 0 data))))

;;;
;;; Settings are handled as an  association list. The human input as a
;;; sequence of 2-lists.  This is the  input as it would appear in the
;;; file.  These defaults are targeting water at normal conditions.
;;;
;;; The  defaults, updated  from the  command  line, will  be used  to
;;; prepare   the   reall   association   list  with   settings.   See
;;; parse-command-line below.
;;;
(define *defaults*
  '((solvent #f)                      ; uninitialized string, actually
    (solute #f)                       ; uninitialized string
    (L 10.0)                          ; [-L, L] gives the box size
    (N 64)                            ; grid dimension
    (rho 0.033427745)                 ; solvent density (1 g/cm^3)
    (beta 1.6889)                     ; inverse temperature
    (norm-tol 1.0e-7)                 ; convergence threshold
    (max-iter 1500)                   ; max number of iterations
    (damp-start 1.0)                  ; scaling factor?
    (lambda 0.02)                     ; not the scheme lambda
    (bond-length-thresh 1.0)   ; scale for covalent bond autodetection
    (closure HNC)                     ; HNC, KH or PY
    (hnc #f)                          ; FIXME: exclusive
    (bgy #f)                          ; FIXME: exclusive
    (rism #f)                         ; FIXME: exclusive
    (derivatives #f)                  ; #t or #f
    ))

;;;
;;; This  dynamically  scoped  global   will  be  used  to  communcate
;;; variables too cumbersome to be passed as arguments. Do not abuse.
;;;
(define *settings* (make-fluid))

;;;
;;; Some    functions,   notably   rism-solute,    rism-solvent,   and
;;; hnc3d-run-solute return a  dictionary of results in the  form of a
;;; nested  association   list.   The  two   established  entries  are
;;; free-energy and, occasionally, free-energy-gradient.
;;;
(define (rism-self-energy molecule species settings)
  (with-fluids ((*settings* settings))
    (rism-self-energy/c molecule species)))

(define (rism-solvent solvent settings)
  (with-fluids ((*settings* settings))
    (rism-solvent/c solvent)))

;;
;; One optional  argument, chi, for solvent  susceptibility is allowed
;; here:
;;
(define (rism-solute solute solvent settings . rest)
  (with-fluids ((*settings* settings))
    (apply rism-solute/c solute solvent rest)))

(define (bgy3d-run-solvent solvent settings)
  (with-fluids ((*settings* settings))
    (bgy3d-run-solvent/c solvent)))

(define (bgy3d-run-solute solute solvent settings . rest)
  (with-fluids ((*settings* settings))
    (apply bgy3d-run-solute/c solute solvent rest)))

(define (hnc3d-run-solvent solvent settings)
  (with-fluids ((*settings* settings))
    ;; FIXME:  make it return dicts  like the others, I  think it just
    ;; returns the settings as is:
    (let* ((dct (hnc3d-run-solvent/c solvent))
           (dct (acons 'free-energy 'FIXME! dct)))
      dct)))

(define (hnc3d-run-solute solute solvent settings . rest)
  (with-fluids ((*settings* settings))
    (apply hnc3d-run-solute/c solute solvent rest)))

;;;
;;; This compacts  association list  with entries coming  later having
;;; precedence. FIXME: thus any prior acons may be ignored.
;;;
(define (overwrite alist)
  (let loop ((merged '())
             (alist alist))
    (if (null? alist)
        merged
        (let ((head (car alist))
              (tail (cdr alist)))
          (loop (assoc-set! merged (car head) (cdr head))
                tail)))))
;;;
;;; You  may choose  to use  env-ref, env-set  to  manipulate settings
;;; consistently.
;;;
(define (env-ref settings key)
  (assoc-ref settings key))

;;;
;;; Almost as  acons/alist-cons but  deletes the previous  setting, if
;;; present.  Note that alist-delete  does not modify the original but
;;; the result may share the  tail with the input.  FIXME: memoization
;;; in  (guile  utils)  is  based  on  association  lists  and  equal?
;;; comparisons, so that the branch is actually redundant.
;;;
(define (env-set key val settings)
  (if (equal? val (env-ref settings key))
      settings
      (let ((settings' (alist-delete key settings)))
        (alist-cons key val settings'))))


;;;
;;; The  input comes  from reading  (in  the Scheme  sense) the  human
;;; editable file.   To keep it simple  for a human we  do not require
;;; him/her  to properly  specify pairs  by Scheme  syntax as  in (key
;;; .  value).  Instead  a  key/value shall  be  a 2-list  as in  (key
;;; value), e.g.:
;;;
;;;   ((solute "butanoic acid")
;;;    (closure KH))
;;;
;;; This function is supposed to process the input and return a proper
;;; association list of (key . value) pairs:
;;;
(define (input->settings input)
  (overwrite (map (lambda (x) (cons (first x) (second x)))
                  input)))


;;;
;;; Only uses the length of g1 list to generate file names:
;;;
(define (g1-file-names g1)
  (map (lambda (i) (format #f "g~A.bin" i))
       (iota (length g1))))

;;;
;;; Solute parameters are  currently represented by a name  and a list
;;; of sites. See (guile molecule) for accessors/constructors:
;;;
;;; ("water"
;;;  (("O" (-0.2929 0.0 0.0) 3.1506 0.1521 -0.834)
;;;   ("OH" (0.2929 0.757 0.0) 0.4 0.046 0.417)
;;;   ("OH" (0.2929 -0.757 0.0) 0.4 0.046 0.417)))
;;;

;;;
;;; Update site force field parameters by replacing them with the data
;;; from a  table identified  by string table-name.   The name  of the
;;; site serves as a key to lookup table entries.  The table is stored
;;; in  guile/solutes.scm as  a fake  solute with  all  possible sites
;;; listed once.
;;;
(define (update-sites table-name sites)
  (let* ((table                     ; fake solute with site-parameters
          (molecule-sites (find-molecule table-name)))
         (update-one
          (lambda (site)
            (let* ((name (site-name site))
                   (table-site (assoc name table)))
              (make-site name                      ; original
                         (site-position site)      ; original
                         (site-sigma table-site)   ; from table
                         (site-epsilon table-site) ; from table
                         (site-charge site))))))   ; original
    (map update-one sites)))


;;;
;;; L2-norm   of  a   vec.  The   funciton  vec-dot   is   defined  in
;;; bgy3d-guile.c:
;;;
(define (vec-norm v)
  (sqrt (vec-dot v v)))

;;;
;;; Will work inefficiently with  distributed vectors.  The problem is
;;; vec-ref  is collective.  The  Petsc primitive  VecGetValues() only
;;; works for local section.
;;;
(define (vec-fold kons knil vec)
  "A (left) fold of a (Petsc) vector.  E.g. (vec-fold + 0.0 vec)
computes the sum of all vector elements."
  (let ((len (vec-length vec))
        (vec (lambda (i) (vec-ref vec i))))
    (let loop ((knil knil)
               (i 0))
      (if (< i len)
          (loop (kons (vec i) knil)
                (+ 1 i))
          knil))))

(define (vec-for-each f vec)
  (vec-fold
   (lambda (x seed) (f x))              ; seed not used
   (if #f #f)                           ; seed is #<unspecified>
   vec))

;;;
;;; Returns an "iterator" --- here  a function that takes a callback f
;;; and invokes that callback for each vector element:
;;;
(define (make-vec-iter vec)
  (lambda (f) (vec-for-each f vec)))

;;;
;;; FIXME: Guile has problems with denormal numbers, replace small ones
;;; by zeros. Otherwise Guile will show #.# when printing it:
;;;
(define (vec-print v)
  (define (normalize x)
    (if (> (abs x) 2.0e-308)
        x
        0.0))
  (vec-for-each
   (lambda (x) (format #t "~a\n" (normalize x)))
   v))

;;;
;;; For   each  position  x   in  the   list  xs   evaluate  potential
;;; v(x). Potential is a BGY3D interator object, not a function:
;;;
(define (potential-map v xs)
  (map (lambda (x) (bgy3d-pot-interp v x)) xs)) ; so far this accepts only one position

;;;
;;; These hooks,  solvent/solvent and solute/solvent,  are called from
;;; the "runqm" script used for QM solutes:
;;;
(define (solvent/solvent input)
  (let* ((settings      (input->settings (append *defaults* input)))
         (solvent-name  (env-ref settings 'solvent)) ; string or #f
         (solvent       (find-molecule solvent-name))  ; fails for #f
         (closure       (env-ref settings 'closure)) ; symbol or #f
         (run-solvent   (if closure
                            hnc3d-run-solvent
                            bgy3d-run-solvent))
         (solvent-info-file (if closure
                                "x00-fft.bin"
                                "g00.bin"))
         (always-run-solvent #t))
    ;;
    ;; At the moment the function bound to run-solvent echoes settings
    ;; as is, the output is written to disk instead. FIXME: a hack to
    ;; save some time re-running pure solvent calculations.  Set
    ;; always-run-solvent to #f. Then the calulation will only run if
    ;; the file solvent-info-file does not exist. It may still
    ;; correspond to a different solvent or settings.
    ;;
    (if (or always-run-solvent
            (not (file-exists? solvent-info-file)))
        (run-solvent solvent settings)))) ; writes solvent info to disk

;;;
;;; Input  comes   from  the  text  file   (see  ../test-qm/*.scm  and
;;; ../test-qm/runqm) but  sites, funptr and restart come  from the QM
;;; code.  The force  field parameters of sites are  to be replaced by
;;; something meaningful as the QM code knows little about that.
;;;
(define (solute/solvent input sites funptr restart)
  (let* ((settings      (input->settings (append *defaults* input)))
         (solvent-name  (env-ref settings 'solvent)) ; string or #f
         (solute-name   (env-ref settings 'solute))  ; string or #f
         (solvent       (find-molecule solvent-name))
         (solute        (make-molecule solute-name
                                       (update-sites solute-name
                                                     sites)))
         (closure       (env-ref settings 'closure)) ; symbol or #f
         (run-solute    (if closure
                            hnc3d-run-solute
                            bgy3d-run-solute)))
    ;;
    ;; Extend settings by an  entry with the funciton pointer that can
    ;; be used to compute additional solute charge density:
    ;;
    (set! settings (env-set 'qm-density ; key
                            funptr      ; value
                            settings))  ; alist
    ;; Print on master only:
    (pretty-print/serial (list 'SETTINGS: settings))
    (pretty-print/serial (list 'SOLVENT: solvent))
    (pretty-print/serial (list 'SOLUTE: solute))
    (pretty-print/serial (list 'RESTART: restart))
    ;;
    ;; The function  bound to run-solute allocates and  returns a list
    ;; of  Petsc Vecs, a  descriptor for electrostatic  potential, and
    ;; some  restart info  to be passed  back on the  next invokations
    ;; (returned as multiple values). It is the callers responsibility
    ;; to destroy  all of them ---  do not assume any of  them will be
    ;; garbage-collected. As of now it expects the solvent description
    ;; such as g??.bin or x??-fft.bin to exist as files:
    ;;
    (let ((alist (run-solute solute solvent settings #f restart)))
      ;;
      ;; Save g1-files to disk:
      ;;
      (let ((g1 (assoc-ref alist 'GUV)))
        (map vec-save (g1-file-names g1) g1)
        ;;
        ;; Dont forget to destroy them after use:
        ;;
        (map vec-destroy g1))
      ;;
      ;; Return (a) the (iterator over) potential (the caller must
      ;; bgy3d-pot-destroy it) and (b) the restart info that, when
      ;; passed to this function next time, could help saving a few
      ;; BGY iterations:
      ;;
      (cons (assoc-ref alist 'POTENTIAL)
            (assoc-ref alist 'RESTART)))))

;;;
;;; Specifications  of command  line flags  for use  with getopt-long.
;;; Most  of these  happen to  be  real- or  integer numbers.   Though
;;; according to getopt-long the predicate is required to return #f or
;;; something trueish we request the predicate to return a typed value
;;; converted from string for future use.
;;;
;;; FIXME: ./runbgy.scm invokes old-main at the moment, so that it has
;;; to accept  the options of  the new-main. This leads  to unhelpfull
;;; error messages sometimes:
;;;
(define option-spec
  (quasiquote
   ((bgy                (value #f))
    (hnc                (value #f))
    (rism               (value #f))
    (verbosity          (value #t)      (predicate ,string->number)) ; dont use -v
    (rho                (value #t)      (predicate ,string->number))
    (beta               (value #t)      (predicate ,string->number))
    (L                  (value #t)      (predicate ,string->number))
    (N                  (value #t)      (predicate ,string->number))
    (rmax               (value #t)      (predicate ,string->number))
    (nrad               (value #t)      (predicate ,string->number))
    (norm-tol           (value #t)      (predicate ,string->number))
    (max-iter           (value #t)      (predicate ,string->number))
    (damp-start         (value #t)      (predicate ,string->number))
    (lambda             (value #t)      (predicate ,string->number))
    (solvent
     (value #t)
     (predicate ,(lambda (name)
                   (and (find-molecule name) name)))) ; a string
    (solute
     (value #t)
     (predicate ,(lambda (name)
                   (and (find-molecule name) name)))) ; a string
    (solute-geometry
     (value #t)
     (predicate ,(lambda (path)
                   (with-input-from-file path read-xyz))))
    (closure
     (value #t)
     (predicate ,(lambda (x)
                   (let ((y (string->symbol x)))
                     (and (member y '(HNC PY KH PSE0 PSE1 PSE2 PSE3 PSE4 PSE5 PSE6 PSE7))
                          y)))))
    (dielectric         (value #t)      (predicate ,string->number))
    (comb-rule          (value #t)      (predicate ,string->number))
    (solvent-3d         (value #f)) ; take χ from file computed by 3D RISM
    (no-renorm          (value #f)) ; dont do lon-range renormalization
    (from-radial-g2     (value #f))
    (save-guess         (value #f))
    (save-binary        (value #f))
    (load-guess         (value #f))
    (derivatives        (value #f))
    (response           (value #f))
    (snes-solver
     (value #t)
     (predicate ,(lambda (x)
                   (and (member x '("jager" "newton" "picard" "trial"))
                        x))))
    (verbose            (single-char #\v)
                        (value #f)) ; use --verbosity num instead
    (rbc                (value #f)) ; add repulsive bridge correction
    (no-cage            (value #f)) ; turns off metallic cage boundary
    (no-hacks           (value #f)))))  ; turns off ugly hacks


;;;
;;; Returns an association list where the values from the command line
;;; (provided as strings)  are converted to the proper  type using the
;;; predicates from option-spec above.
;;;
(define (options->settings options)
  ;; Here we are "abusing" predicates from the specification of
  ;; acceptable command line flags to convert strings to typed
  ;; values. Note that specifications of the options use 2-lists and
  ;; not (car . cdr) pairs for keys and values.
  (define (make-pair op)
    (let* ((key (car op))      ; symbol or ()
           (val (cdr op))      ; string, #t or (), getopt-long is ugly
           (spec (assoc-ref option-spec key))
           (pred (assoc-ref spec 'predicate)) ; #f or 1-list
           (pred (and pred (car pred))))      ; see option-spec syntax
      (if pred
          (cons key (pred val))
          op)))
  ;; List of kv-pairs, including positional arguments with () as a
  ;; key:
  (map make-pair options))


;;;
;;; Try  to  keep the  command  line parsing  at  a  single place  for
;;; re-use. This converts the known options to numbers. Note that only
;;; those    options   are    accepted   that    are    specified   in
;;; option-spec. FIXME: Petsc  options use a single dash  and thus are
;;; incompatible  with  getopt-long. You  can  still  specify them  in
;;; ~/.petscrc, though.
;;;
(define (parse-command-line argv)
  (let* ((options (getopt-long argv option-spec))
         (defaults (input->settings *defaults*))
         (user-defined (options->settings options)))
    ;; User-defined settings derived from command line include
    ;; positional args. User-defined take precedence:
    (overwrite (append defaults user-defined))))


;;;
;;; For testing, primarily, evaluate  potential at positions of solute
;;; sites and the corresponding total energy:
;;;
(define (maybe-print-potentials solute potential)
  (let* ((sites         (molecule-sites solute))
         (positions     (map site-position sites))
         (potentials    (potential-map potential positions))
         (charges       (map site-charge sites))
         (energy        (apply + (map * charges potentials))))
    ;;
    ;; Only print on master:
    ;;
    (pretty-print/serial (cons 'core-potentials potentials))
    (pretty-print/serial (cons 'core-energy energy))))

;;;
;;; Some solvers  return distributions and other results  that need to
;;; be explicitly destroyed. If there were a way to reliably trigger a
;;; collective operation on all MPI ranks by a garbage collector ...
;;;
(define (destroy alist)
  (and-let* ((guv (assoc-ref alist 'GUV)))
    (map vec-destroy guv))
  (and-let* ((potential (assoc-ref alist 'POTENTIAL)))
    (bgy3d-pot-destroy potential))
  (and-let* ((restart (assoc-ref alist 'RESTART)))
    (bgy3d-restart-destroy restart)))


;;;
;;; Linear mesh.  Note that the last point  is max - dr  < max. FIXME:
;;; division by zero for n = 0.
;;;
(define (mesh/lin min max n)
  (let ((dr (/ (- max min) n)))
    (map (lambda (i) (+ min (* dr i)))
         (iota n))))

;;;
;;; Logarithmic mesh.  Similar gotchas  as with mesh/lin. Moreover one
;;; needs min > 0:
;;;
(define (mesh/log min max n)
  (map exp (mesh/lin (log min) (log max) n)))

;;;
;;; (linspace  a b n)  behaves as  in NumPy  for n  > 1:  a and  b are
;;; included in  the mesh. This  is usefull for "centered"  meshes say
;;; between -1 and +1.
;;;
(define (linspace min max n)
  (let ((dr (/ (- max min) (- n 1))))
    (map (lambda (i) (+ min (* dr i)))
         (iota n))))

;;;
;;; Should work for any number of columns:
;;;
(define (print-columns . columns)
  (apply for-each
         (lambda row
           (display (string-join (map number->string row) " "))
           (newline))
         columns))

;;;
;;; This dynvar will hold  a univariate function of molecular geometry
;;; that returns the energy and  the corresponding gradient for use in
;;; foreign code.  See bgy3d_molmech() in bgy3d-guile.c for its use.
;;;
(define *server* (make-fluid))

;;;
;;; Construct a PES as a  function of solute (or solvent) geometry and
;;; return that together with the initial geometry as multiple values.
;;; The solvent  susceptibility χ is precomuted lazily  and forced the
;;; first time the PES is used (if at all).
;;;
;;; The species are  defined here using the reference  geometry of the
;;; solute as  returned by  find-molecule.  The definition  of species
;;; will  NOT change with  the geometry  even if  bonds are  broken or
;;; formed!
;;;
;;; FIXME: this procedure is ugly as hell, in part because it tries to
;;; handle pure solvent and solute/solvent simultaneously.
;;;
(define (make-pes solute solvent settings)
  (let ((three-dee (env-ref settings 'hnc))
        (chi (delay (let ((dct (rism-solvent solvent settings))) ; solvent run here!
                      (assoc-ref dct 'susceptibility))))) ; extract susceptibility
    (let* ((m (or solute solvent))      ; molecule to be "moved"
           (x0 (molecule-positions m))  ; unperturbed geometry
           (restart %null-pointer)
           (rism (lambda (x s)          ; (x, settings) -> alist
                   (let ((m' (move-molecule m x)))
                     (if three-dee
                         (if solute
                             (let ((dct (hnc3d-run-solute m' solvent s (force chi) restart)))
                               ;; FIXME: lots of memory leaks here,
                               ;; need a way to dispose of PES
                               ;; functions:
                               (set! restart (assoc-ref dct 'RESTART))
                               (let ((dct (alist-delete 'RESTART dct)))
                                 (destroy dct) ; deallocate Vecs ...
                                 dct))
                             (hnc3d-run-solvent m' s)) ; FIXME: returns fake
                         (if solute
                             (rism-solute m' solvent s (force chi))
                             (rism-solvent m' s))))))
           ;; FIXME: Leaking much?  A geometry optimization may easily
           ;; require a few hundred evaluations:
           (rism (memoize rism))
           ;; Define solute species once, using the reference
           ;; geometry.  Otherwise self-energy may become
           ;; discontinous. FIXME: the idea is that we can guess
           ;; topology of any solute by our limited means is just
           ;; broken. Nothing of importance should depend on "species"
           ;; defined in this automatic way. In particular covalent
           ;; radii of unknown sites (see ./guile/atoms.scm) will be
           ;; zero.
           (scale (env-ref settings 'bond-length-thresh))
           (species (and solute
                         (sites->species (molecule-sites solute) scale)))
           (settings (if species
                         (env-set 'solute-species species settings)
                         settings))
           ;; PES (f x) -> energy:
           (f (lambda (x)
                (assoc-ref (rism x settings) 'free-energy)))
           ;; Make sure to request evaluation of gradients for (g x)
           ;; but not for (f x). Using two different settings impedes
           ;; memoization:
           (settings (env-set 'derivatives #t settings))
           ;; PES tuple (fg x) -> energy, gradients:
           (fg (lambda (x)
                 (let ((dict (rism x settings)))
                   (values (assoc-ref dict 'free-energy)
                           (assoc-ref dict 'free-energy-gradient))))))
      ;;
      ;; Return initial geometry, PES function f, and its Taylor
      ;; expansion fg as multiple values:
      ;;
      (values x0 f fg))))

;;;
;;; "Gas-phase" PES. Hm,  you cannot search for a  minimum on this PES
;;; without  introducing intra-molecular  interactions or  making each
;;; species rigid.
;;;
(define (make-pes/gp solute settings)
  (let* ((scale (env-ref settings 'bond-length-thresh))
         (species (sites->species (molecule-sites solute) scale)) ; list of ints
         (x0 (molecule-positions solute))
         (fg (lambda (x)              ; x -> (values energy gradients)
               (let ((solute' (move-molecule solute x)))
                 (rism-self-energy solute' species settings))))
         (f (lambda (x)                 ; x -> energy
              (let-values (((e g) (fg x)))
                e))))
    (values x0 f fg)))


;;;
;;; Derive the solute description  from the settings.  If the geometry
;;; option  is set  to some  molecule description,  take  its geometry
;;; instead:
;;;
(define (find-solute settings)
  (let ((name (env-ref settings 'solute))
        (geometry (env-ref settings 'solute-geometry)))
    (and name
         (let ((solute (find-molecule name)))
           (or (and geometry
                    (move-molecule solute
                                   (molecule-positions geometry)))
               solute)))))
;;;
;;; Act   according   to   the   subcommand  (the   first   positional
;;; argument). With  cmd == "solutes" interprete each  argument as the
;;; name of the solute. Note that  you may need to first run a solvent
;;; calculation with cmd == "solvent".
;;;
;;; FIXME: report usage meaningfully when called incorrectly
;;;
(define (new-main argv)
  (let* ((settings (parse-command-line argv)) ; argv[0] is ignored
         (args (env-ref settings '()))        ; positional arguments
         (args (if (null? args) '("old-main") args)) ; hack
         (cmd (car args))               ; first the command ...
         (args (cdr args)))             ; ... then the real args
    (let ((solvent (and-let* ((name (env-ref settings 'solvent)))
                     (find-molecule name))) ; Maybe solvent
          (solute (find-solute settings))   ; Maybe solute
          (save-binary (env-ref settings 'save-binary)))
      ;;
      (match cmd
        ("old-main"
         ;;
         ;; This branch emulates historical interface --- no
         ;; subcommands just flags. The new functionality is in the
         ;; flux.  Note that at variance with the legacy code the
         ;; function find-molecule uses on-disk database in
         ;; ./solutes.scm and not the compiled in set from
         ;; bgy3d-solutes.c and bgy3d-solvents.h:
         ;;
         (pretty-print/serial (list 'solvent: solvent))
         (pretty-print/serial (list 'solute: solute))
         (let-values
             (((method run-solvent run-solute) ; three method-dependent values:
               (cond
                ((env-ref settings 'hnc)  (values 'hnc hnc3d-run-solvent hnc3d-run-solute))
                ((env-ref settings 'bgy)  (values 'bgy bgy3d-run-solvent bgy3d-run-solute))
                ((env-ref settings 'rism) (values 'rism rism-solvent rism-solute))
                (else (error "no luck, use subcommands")))))
           (case method
             ;;
             ;; 3d HNC/BGY.  The functions bound to run-solvent and
             ;; run-solute share the interface. The code that calls
             ;; them is the same.
             ;;
             ((hnc bgy)
              (if solute                ; either #f or real solute
                  ;;
                  ;; Solute with solvent. Dont forget to destroy the
                  ;; objects returned:
                  ;;
                  (let ((alist (run-solute solute solvent settings)))
                    ;;
                    ;; Evaluate and print potential at positions of
                    ;; solute sites and the corresponding total
                    ;; energy:
                    ;;
                    (let ((potential (assoc-ref alist 'POTENTIAL)))
                      (maybe-print-potentials solute potential))
                    ;;
                    ;; Output excess chemical potential to tty:
                    ;;
                    (let ((free-energy (assoc-ref alist 'free-energy))
                          (closure (env-ref settings 'closure)))
                      (pretty-print/serial (list closure free-energy)))
                    ;;
                    ;; Write g?.bin files:
                    ;;
                    (let ((g1 (assoc-ref alist 'GUV)))
                      (map vec-save (g1-file-names g1) g1))
                    ;;
                    ;; Destroy all Vecs, potential, restart info, etc ...
                    ;;
                    (destroy alist))
                  ;;
                  ;; Pure solvent:
                  ;;
                  (run-solvent solvent settings)))
             ;;
             ;; 1d-RISM:
             ;;
             ((rism)
              (if solute                ; either #f or real solute
                  ;;
                  ;; Solute with solvent:
                  ;;
                  (let ((res (run-solute solute solvent settings)))
                    (pretty-print/serial res))
                  ;;
                  ;; Pure solvent:
                  ;;
                  (let ((res (run-solvent solvent settings)))
                    (pretty-print/serial res))))
             ;;
             ;; FIXME: print usage help here ...
             ;;
             (else
              (display "I dont understand you, my master.\n")))))
        ;;
        ((or "energy" "gradient" "gradients" "taylor")
         (let-values (((x f fg) (if solvent
                                    (make-pes solute solvent settings)
                                    (make-pes/gp solute settings))))
           (match cmd
             ("energy"
              (let ((e (f x)))
                (pretty-print/serial e)))
             ((or "gradient" "gradients")
              (let-values (((e g) (fg x)))
                (pretty-print/serial g)))
             ("taylor"
              (let-values (((e g) (fg x)))
                (pretty-print/serial (cons e g)))))))
        ;;
        ;; Start a server that communicates with a client via two
        ;; named pipes for input/output. This fragile construct is
        ;; used for free energy surface exploration, such as
        ;; minimization, where many calculations that differ only by
        ;; geometry are performed.
        ;;
        ("server"
         (let ((finp (first args))  ; coordinates or #f read from here
               (fout (second args))) ; resulting energy is written here
           ;;
           ;; Make a function of 3d geometry. The initial geometry is
           ;; not used:
           ;;
           (let-values (((x0 f fg) (if solvent
                                       (make-pes solute solvent settings)
                                       (make-pes/gp solute settings))))
             (let loop ()
               ;;
               ;; Read the input pipe. This will block utill the
               ;; client writes the geometry from the other side. Note
               ;; that only the first s-expression is read:
               ;;
               (let ((x (read-fifo-v2 finp)))
                 ;;
                 ;; Convention is when the input is #f, then
                 ;; terminate. Otherwise evaluate PES at this point
                 ;; and write the resulting energy and gradients to
                 ;; our side of the output pipe as a single
                 ;; s-expression. This will block utill the client
                 ;; reads the results from his end:
                 ;;
                 (when x
                   (let-values (((e g) (fg x))) ; get energy, gradient
                     (write-fifo fout (cons e g))) ; or (list e g)?
                   (loop)))))))
        ("solvent"
         ;;
         ;; Only then run pure solvent, if --solvent was present in the
         ;; command line:
         ;;
         (error "FIXME: is this branch used? Sep. 2014")
         (bgy3d-run-solvent solvent settings))
        ;;
        ((or "solute" "solutes")
         ;;
         ;; Check if we can find the solutes by names early, typos are
         ;; common. FIXME: If this never fires, maybe delete the case?
         ;;
         (error "FIXME: I think bgy3d-run-solute returns an alist by now")
         (let ((solutes (map find-molecule args)))
           (map (lambda (solute)
                  (let-values (((g1 ve restart)
                                (bgy3d-run-solute solute solvent settings)))
                    ;;
                    ;; Save distributions if requested from command
                    ;; line. FIXME: the file names do not relate to
                    ;; solute, so that when processing more than one
                    ;; solute in a row files will get overwritten:
                    ;;
                    (if save-binary
                        (map vec-save (g1-file-names g1) g1))
                    ;;
                    ;; Dont forget to destroy them:
                    ;;
                    (bgy3d-pot-destroy ve) ; not yet used
                    (bgy3d-restart-destroy restart)
                    (map vec-destroy g1)))
                solutes)))
        ("update-param"
         ;;
         ;; input must be in the fixed order: "solvent"/"solute" +
         ;; "site" + "sigma"/"epsilon"/"charge" + value.
         ;; FIXME: need improvement to update more than one type of
         ;; parameters simultaneously
         ;;
         (let ((molecule (first args))
               (sname (second args))
               (param (third args))
               (value (fourth args)))
           (match molecule
                  ("solvent"
                   (let* ((solvent-new
                            (update-param solvent sname param
                                          (string->number value))))
                     ;; these print sentences are for debug only, will be
                     ;; abandoned in future
                     (pretty-print solvent-new)
                     ;; (pretty-print solvent)
                     (pretty-print settings)
                     (pretty-print solute)
                     (let ((res (rism-solute solute solvent-new settings)))
                       (pretty-print/serial res))))
                  ("solute"
                   (let* ((solute-new
                            (update-param solute sname param
                                          (string->number value))))
                     (pretty-print solvent)
                     (pretty-print solute-new)
                     ;; (pretty-print solute)
                     (let ((res (rism-solute solute-new solvent settings)))
                       (pretty-print/serial res)))))))
        ("punch"
         ;;
         ;; Use g1 vectors to produce a *.pun file for visualization:
         ;;
         (if (not solute)
             (error "Specify --solute \"name\" for punch file!"))
         (let ((g1 (map vec-load args)))
            (write-punch-file solute
                              (map vec-length g1)
                              (map make-vec-iter g1)
                              settings)
            (map vec-destroy g1)))
        ;;
        ("moments"
         ;;
         ;; Print a few first moments (with respect to the grid
         ;; center) of each distribution supplied in the command line.
         ;;
         ;; mpirun guile/runbgy.scm moments --N 96 --L 10 test/*.bin
         ;;
         (let ((domain (state-make settings)))
           (for-each (lambda (path)
                       (let* ((h (vec-load path))
                              (h (vec-shift! h -1.0))
                              (h (vec-scale! h -1.0))
                              (moments (vec-moments domain h)))
                         (begin/serial
                           (format #t ";;; Moments from ~A\n" path)
                           ;; FIXME: this staff is used for regression
                           ;; testing only, so print only a few
                           ;; digits:
                           (pretty-print (numbers->strings 4 moments)))
                         (vec-destroy h)))
                     args)
           (state-destroy domain)))
        ;;
        ("rdf"
         ;;
         ;; Print Gnuplot-ready RDF table. E.g. by executing this:
         ;;
         ;;   mpirun guile/runbgy.scm rdf --N 96 --L 10 "(1 1 -1)" *.bin
         ;;   mpirun guile/runbgy.scm rdf --N 96 --L 10 --solute="XY" "X" *.bin
         ;;
         ;; Coordinates may be negative, thus it is cumbersome to
         ;; specify real numbers in command line and handle short
         ;; flags as well. Specify site names. FIXME: site names are
         ;; not unique, maybe use indices instead?
         ;;
         (let* ((center-spec (with-input-from-string (first args) read))
                (center (if (list? center-spec)
                            center-spec
                            (let ((site-name (symbol->string center-spec)))
                              (site-position (or (assoc site-name
                                                        (molecule-sites solute))
                                                 (error "No such site!"
                                                        'site: site-name
                                                        'solute: solute))))))
                (args (cdr args))
                (angular-order 110)     ; FIXME: literals here ...
                (rmin 0.75)             ; cannot be zero for log-mesh
                (rmax (env-ref settings 'L)) ; a choice ...
                (npts (env-ref settings 'N)) ; another choice ...
                (mesh (mesh/log rmin rmax npts))
                (domain (state-make settings))
                (rdfs (map (lambda (path)
                             (let* ((g (vec-load path))
                                    (rdf (rism-rdf domain g center mesh angular-order)))
                               (vec-destroy g)
                               rdf))
                           args)))
           (state-destroy domain)
           (begin/serial
            (format #t "# center = ~A inferred from input ~A\n" center center-spec)
            (apply print-columns mesh rdfs))))
        ;;
        ("dump"
         ;;
         ;; Dump each Vec from a *.bin file to tty:
         ;;
         (for-each
          (lambda (path)
            (let ((v (vec-load path)))
              (vec-print v)
              (vec-destroy v)))
          args))
        ;;
        ("print-molecule"
         (for-each
             (lambda (name)
               (print-molecule/xyz (find-entry name))) ; find-molecule needs FF to be present
           args))
        ;;
        ("print-species"
         (let ((scale (env-ref settings 'bond-length-thresh)))
          (for-each
           (lambda (name)
             (let ((mol (find-molecule name)))
               (pretty-print/serial
                (map cons
                     (map site-name (molecule-sites mol))
                     (sites->species (molecule-sites mol) scale)))))
           args)))
        ;;
        ("self-energy"
         (for-each
          (lambda (name)
            (let ((settings (env-set 'solute name settings)))
              (let-values (((x0 f fg) (make-pes/gp (find-solute settings) settings)))
                (let ((e (f x0)))
                  (pretty-print/serial e)))))
          args))
        ("self-energy-gradients"
         (for-each
          (lambda (name)
            (let-values (((x0 f fg) (make-pes/gp (find-molecule name) settings)))
              (let-values (((e g) (fg x0)))
                (pretty-print/serial g))))
          args))
        ;;
        ("scan-self-energy"
         (let ((name (first args))
               (xyz1 (second args))
               (xyz2 (third args)))
           (let ((mol (find-molecule name))
                 (x0 (molecule-positions (with-input-from-file xyz1 read-xyz)))
                 (x1 (molecule-positions (with-input-from-file xyz2 read-xyz))))
             (pretty-print/serial (scan-self-energy mol x0 x1)))))
        ("read-xyz"
         (for-each
          (lambda (path)
            (let ((mol (with-input-from-file path read-xyz)))
              (pretty-print/serial mol)))
          args))
        ;;
        ("find-molecule"
         (for-each
             (lambda (name)
               (let* ((mol (find-molecule name))
                      (charge-sum (molecule-charge mol))
                      (dipole-vec (molecule-dipole mol))
                      (dipole-mag (sqrt (apply + (map * dipole-vec dipole-vec)))))
                 ;;
                 ;; Abuse debugging helper to print commented expressions:
                 ;;
                 (pk 'CHARGE-SUM: charge-sum)
                 (pk 'DIPOLE-VEC: dipole-vec)
                 (pk 'DIPOLE-MAG: dipole-mag 'eA '= (eA->debye dipole-mag) 'D)
                 ;;
                 ;; Actual data:
                 ;;
                 (pretty-print mol)))
           args))))))


;;;
;;; We are  trying to  emulate behaviour of  old executable  unless we
;;; find a better interface. The  old behaviour is triggered only when
;;; there are  no positonal  arguments or with  the "old-main"  as the
;;; first positional argument.
;;;
(define (bgy3d-main argv)
  (new-main argv))
