;; -*- Gerbil -*-
;;;; Basic utilities

(export #t)


;;;; Basic syntax for control flow

;; One-character λ
(defalias λ lambda)

;; Function that matches its argument against given clauses
(defrules lambda-match () ((_ clauses ...) (match <> clauses ...)))
(defalias λ-match lambda-match)

;; The anti-indentation macro: nest each form onto the end of the previous form.
;; This way, you can (nest (form1 ...) (form2 ...) ... (formN ...)) and
;; instead of it causing your code to be indented N to 2*N spaces or such
;; as with the expansion (form1 ... (form2 ... ( ... (formN ...))))
;; it will be indented uniformly just 2 spaces.
;; You can thus get lots of nested binding forms, conditional executions, catching, etc.,
;; in a way that preserves the vertical flow of a same notional block,
;; just as you would do in an imperative language with lots of assignments,
;; except in a well-scoped functional way.
;; This style also compares favorably with maintaining a mother-of-all binding form
;; that thereafter has to be extended for each and every new way to bind identifiers
;; that may be invented in the future, while the user who have to remember the mapping
;; between nested style and the mother-of-all style.
;; Here, the two are the same by construction.
(defsyntax (nest stx)
  (syntax-case stx ()
    ((_ outer ... inner)
     (foldr (lambda (outer-form inner-form)
              (with-syntax (((o ...) outer-form)
                            (i inner-form))
                #'(o ... i)))
            #'inner
            #'(outer ...))))) ; NB: On Racket, #'(outer ...) must be wrapped in a syntax->list

(defrules when-match ()
  ((_ expr pattern body ...) (match expr (pattern body ...) (else (void)))))

;; From CL's ALEXANDRIA library
(defrules if-let ()
  ((_ () then else) then)
  ((_ ((ids exprs) ...) then else)
   (let ((ids exprs) ...)
     (if (and ids ...)
       then
       else)))
  ((_ (id expr) then else)
   (let ((id expr)) (if id then else))))

(defrules when-let ()
  ((_ bindings body ...) (if-let bindings (begin body ...) (void))))

;; Force left-to-right evaluation of the arguments of a function call
;; NB: the function itself might be evaluated after.
(defsyntax (left-to-right stx)
  (syntax-case stx ()
    ((_ fun arg ...)
     (with-syntax (((tmp ...) (gentemps #'(arg ...))))
       #'(let* ((tmp arg) ...)
           (fun tmp ...))))))

;;;; Basic higher-order function combinators

;; rcompose: compose functions by flowing values left-to-right (same as !>),
;; as opposed to the conventional (and arguably backward) mathematical ∘ operator.
;; Other suggested names: esopmoc (poetic, obvious a posteriori but not a priori),
;; sequentially (rhymes with constantly, not with compose), seq (too short and clashy)
;; chaining, chain (not obvious enough, clashy),
;; compose*, compose-right, reverse-compose, rev-compose, rcomp (ugly, not obvious enough).
;; NB: doing the right thing with multiple-values
;; : (X_n <- X_0) <- (X_1 <- X_0) (X_2 <- X_1) ... (X_n <- X_(n-1))
(def rcompose
  (case-lambda
    (() values)
    ((f) f)
    ((f1 f2) (λ args (call-with-values (λ () (apply f1 args)) f2)))
    ((f1 f2 f3 . fs) (rcompose f1 (apply rcompose f2 f3 fs)))))

;; compose: compose functions in usual mathematical right to left order ∘ (opposite !>).
;; NB: doing the right thing with multiple-values
;; : (X_n <- X_0) <- (X_n <- X_(n-1)) ...  (X_2 <- X_1) (X_1 <- X_0)
(def compose
  (case-lambda
    (() values)
    ((f) f)
    ((f1 f2) (rcompose f2 f1))
    ((f1 f2 f3 . fs) (apply rcompose (reverse [f1 f2 f3 . fs])))))

;; pipeline operator: feed x into a series of multi-valued functions
;; : (X_n <- X_0) <- X_0 (X_1 <- X_0) (X_2 <- X_1) ... (X_n <- X_(n-1))
(def !> ;; see x |> f in ML
  (case-lambda
    ((x) x)
    ((x f) (f x))
    ((x f1 f2 . fs) ((apply rcompose f1 f2 fs) x))))

(def !!> ;; Multiple value variant
  (case-lambda
    ((x) (apply values x))
    ((x f) (apply f x))
    ((x f1 f2 . fs) (apply (apply rcompose f1 f2 fs) x))))

;; TODO: Should we define this unicode alias?
;; (defalias ‎▷ !>)

(def (iterated-function n fun)
  (cond
   ((equal? n 0) values)
   ((equal? n 1) fun)
   (else (rcompose fun (iterated-function (- n 1) fun)))))

;; A bit like CL:FUNCALL, as a trivial higher-order function.
(def funcall ;; same as (lambda (fun . args) (apply fun args)), but optimizing a bit
  (case-lambda
    ((f) (f))
    ((f x) (f x))
    ((f x y) (f x y))
    ((f x y z . t) (apply f x y z t))))

;; A bit like CL:CONSTANTLY, except it accepts multiple values.
(def (constantly . x) (lambda _ (apply values x)))

;; Like ALEXANDRIA:CURRY in CL
;; (Z <- YY) <- (Z <- XX YY) XX
(def curry
  (case-lambda
    ((f x) (case-lambda ((y) (f x y)) ;; optimization for a common case
                        (ys (apply f x ys))))
    ((f . xs) (lambda ys (apply f append xs ys))))) ;; main case

;; Like ALEXANDRIA:CURRY in CL
;; (Z <- YY) <- (Z <- YY XX) XX
(def rcurry ;; TODO: find a better name for this function specializer
  ;; same as (λ (f . args) (λ first-args (apply f (append first-args args)))), but optimized a bit.
  ;; NB: you could use (cut f <> ... args ...) if you don't need a first-class function.
  (case-lambda
    ((f x) (case-lambda ((y) (f y x)) ;; optimization for a common case
                        (ys (apply f (append ys [x])))))
    ((f . xs)
     (case-lambda ((y) (apply f y xs))
                  (ys (apply f (append ys xs))))))) ;; main case


;; Fold from monoid reduce and map
;; : (B <- (M A) (B <- A B) B) <- (B <- (M B) B (B <- B B)) ((M B) <- (M A) (B <- A))
(def (fold<-reduce-map reduce map)
  (λ (data nil cons) ((reduce (map data (curry curry cons)) identity compose) nil)))


;;;; Multiple values
(defrules first-value ()
  ((_ form) (with ((values x . _) form) x)))

(defrules nth-value ()
  ((_ n form) (with ((values . x) form) (list-ref x n))))

(defrules values->vector ()
  ((_ form) (list->vector (values->list form))))

(defrules values->cons ()
  ((_ form) (let-values (((a b) form)) (cons a b))))


;;;; Stupid error non-handling
(defrules ignore-errors ()
  ((_ form ...) (with-catch (λ (_) #f) (λ () form ...))))

;;;; Basic error cases

;; Use undefined where the language requires you to cover a case that is actually
;; not defined and cannot possibly be observed by end-users.
;; A typical use is for unimplemented methods of abstract classes.
;; NB: IF THIS IS EVER VISIBLE TO END-USERS during normal operation of an application,
;; this is an implementation error and YOU LOSE.
;; Any <- Any ...
(def (undefined . args) (error "undefined function or method" args))


;; Use NIY when you need a TEMPORARY filler for code that MUST be implemented
;; BEFORE release, probably even before your branch is merged into production
;; code. IF THIS CODE APPEARS IN PRODUCTION, YOU LOSE.
;; Any <- Any ...
(def (NIY . args) (error "Not Implemented Yet" args))


;;;; Basic types

;; Trivial constructor to wrap some value. The conventional option type for our code will be
;; in pseudo-code: (deftype (option value-type) (sum-type (some value-type) '#f))
;; i.e. (some foo) represents the present of value foo, and #f represents the absence of value.
;; In Haskell you'd have option bool := Just True | Just False | None
;; In Gerbil, we'll have (option bool) := (some #t) | (some #f) | #f
(defstruct some (value))


;;;; Functions to manipulate 2D arrays represented as a single vectorx
;;(def (make-2d-array N-columns N-rows (initial-element #f))
;;  (make-vector (* N-columns N-rows) initial-element))
;;(def (2d-array-ref array N-columns row column)
;;  (vector-ref array (+ (* row N-columns) column)))
;;(def (2d-array-set! array N-columns row column value)
;;  (vector-set! array (+ (* row N-columns) column) value))


;; This function implements the common features of the search functions of Common Lisp,
;; to make them available to corresponding Scheme functions: e.g. CL:FIND vs Scheme find.
;; : (Bool <- X) <- V test: (Bool <- V V) key: (V <- X)
(def (looking-for value test: (test equal?) key: (key identity))
  (λ (x) (test value (key x))))

;; This function implements the common features of the search functions of Common Lisp,
;; to make them available to corresponding Scheme functions.
;; : (Bool <- X X) <- test: (Bool <- V V) key: (V <- X)
(def (comparing-key test: (test equal?) key: (key identity))
  (λ (x y) (test (key x) (key y))))


;;;; Object utilities

;;;; long-hand for (λ (x args ...) {method-id x args ...})
;;(def (method-fun method-id)
;;  (λ (object . args) (apply call-method object method-id args)))


;;;; Basic defining forms

;; Define a nullary function that caches its resulting value
(defrules defonce ()
  ((_ (id) body) (def id (let ((id (delay body))) (λ () (force id))))))


;;; Generic (read-only) accessor for builtin data structures...
(def ref
  (case-lambda
    ;; unary case: just return the damn object
    ((object) object)
    ;; two or more keys: use the first key, then recurse
    ((object key1 key2 . more-keys)
     (apply ref (ref object key1) key2 more-keys))
    ;; interesting case: one key
    ((object key)
     (match object
       ((? list?) (list-ref object key))
       ((? vector?) (vector-ref object key))
       ((? u8vector?) (u8vector-ref object key))
       ((? string?) (string-ref object key))
       ((? hash-table?) (hash-ref object key))
       ;; NB: I don't how to access a structure field by name :-(
       ((? object?) (slot-ref object key))
       ((? procedure?) (object key)))))) ; or should we apply instead?

(def (ensure-function x)
  (match x
   ((? procedure?) x)
   ((? hash-table?) (cut hash-ref x <>))
   ((? integer?) (cut ref <> x))
   ([f . args] (apply rcurry (ensure-function f) args))
   ([] identity)
   ((? (λ (x) (or (boolean? x) (eof-object? x)))) (λ _ x))
   ((? object?) (λ (name) (slot-ref x name)))))


;; Beware: scheme has no equivalent to Common Lisp's define-setf-expander,
;; so if you use set! with side-effectful expressions in the below macros,
;; the effects can happen more than once!

;; shift a list of places to the left: each place is assigned the value previously at the next place
(defrules shift! ()
  ((_) (void))
  ((_ place1) (void))
  ((_ place1 place2 places ...) (begin (set! place1 place2) (shift! place2 places ...))))

;; extract last form in a list, continue with the form sandwiched between a before and an after
(defrules sandwich-last-form ()
  ((_ (before ...) (after ...))
   (void))
  ((_ (before ...) (after ...) form)
   (before ... form after ...))
  ((_ (before ...) (after ...) form1 form2 forms ...)
   (sandwich-last-form (before ...) (after ...) form2 forms ...)))

;; rotate a list of places to the left: like shift! but additionally the last place is also assigned
;; the value previously at the first place
(defrules rotate! ()
  ((_)
   (void))
  ((_ place1)
   (void))
  ((_ place1 place2 places ...)
   (let ((tmp place1))
     (shift! place1 place2 places ... tmp))))

;; Bool <- Number Number
(def (number-comparer x y)
  (if (= x y) 0 (if (< x y) -1 1)))
