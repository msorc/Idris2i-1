#!chezscheme

(define (blodwen-os)
  (case (machine-type)
    [(i3le ti3le a6le ta6le tarm64le) "unix"]  ; GNU/Linux
    [(i3ob ti3ob a6ob ta6ob tarm64ob) "unix"]  ; OpenBSD
    [(i3fb ti3fb a6fb ta6fb tarm64fb) "unix"]  ; FreeBSD
    [(i3nb ti3nb a6nb ta6nb tarm64nb) "unix"]  ; NetBSD
    [(i3osx ti3osx a6osx ta6osx tarm64osx tppc32osx tppc64osx) "darwin"]
    [(i3nt ti3nt a6nt ta6nt tarm64nt) "windows"]
    [else "unknown"]))

(define blodwen-lazy
  (lambda (f)
    (let ([evaluated #f] [res void])
      (lambda ()
        (if (not evaluated)
            (begin (set! evaluated #t)
                   (set! res (f))
                   (set! f void))
            (void))
        res))))

(define (blodwen-delay-lazy f)
  (weak-cons #!bwp f))

(define (blodwen-force-lazy e)
  (let ((exval (car e)))
    (if (bwp-object? exval)
      (let ((val ((cdr e))))
        (begin (set-car! e val) val))
      exval)))

;; A fixnum (60 bits and a sign) is within the range of the integers of
;; 61 bits or more as it is, which is the common case: this skips the
;; computation of the masks, which allocates numbers of 64 bits and more.
(define (blodwen-toSignedInt x bits)
  (if (and (fixnum? x) (fx>= bits 60))
      x
      (if (logbit? bits x)
          (logor x (ash -1 bits))
          (logand x (sub1 (ash 1 bits))))))

(define (blodwen-toUnsignedInt x bits)
  (if (and (fixnum? x) (fx>= x 0) (fx>= bits 60))
      x
      (logand x (sub1 (ash 1 bits)))))

(define (blodwen-euclidDiv a b)
  (let ((q (quotient a b))
        (r (remainder a b)))
    (if (< r 0)
      (if (> b 0) (- q 1) (+ q 1))
      q)))

(define (blodwen-euclidMod a b)
  (let ((r (remainder a b)))
    (if (< r 0)
      (if (> b 0) (+ r b) (- r b))
      r)))

; flonum constants

(define (blodwen-calcFlonumUnitRoundoff)
  (let loop [(uro 1.0)]
    (if (fl= 1.0 (fl+ 1.0 uro))
      uro
      (loop (fl/ uro 2.0)))))

(define (blodwen-calcFlonumEpsilon)
  (fl* (blodwen-calcFlonumUnitRoundoff) 2.0))

(define (blodwen-flonumNaN)
  +nan.0)

(define (blodwen-flonumInf)
  +inf.0)

; Bits

(define bu+ (lambda (x y bits) (blodwen-toUnsignedInt (+ x y) bits)))
(define bu- (lambda (x y bits) (blodwen-toUnsignedInt (- x y) bits)))
(define bu* (lambda (x y bits) (blodwen-toUnsignedInt (* x y) bits)))
(define bu/ (lambda (x y bits) (blodwen-toUnsignedInt (quotient x y) bits)))

(define bs+ (lambda (x y bits) (blodwen-toSignedInt (+ x y) bits)))
(define bs- (lambda (x y bits) (blodwen-toSignedInt (- x y) bits)))
(define bs* (lambda (x y bits) (blodwen-toSignedInt (* x y) bits)))
(define bs/ (lambda (x y bits) (blodwen-toSignedInt (blodwen-euclidDiv x y) bits)))

(define (integer->bits8 x) (logand x (sub1 (ash 1 8))))
(define (integer->bits16 x) (logand x (sub1 (ash 1 16))))
(define (integer->bits32 x) (logand x (sub1 (ash 1 32))))
(define (integer->bits64 x)
  (if (and (fixnum? x) (fx>= x 0))
      x
      (logand x (sub1 (ash 1 64)))))

(define (bits16->bits8 x) (logand x (sub1 (ash 1 8))))
(define (bits32->bits8 x) (logand x (sub1 (ash 1 8))))
(define (bits64->bits8 x) (logand x (sub1 (ash 1 8))))
(define (bits32->bits16 x) (logand x (sub1 (ash 1 16))))
(define (bits64->bits16 x) (logand x (sub1 (ash 1 16))))
(define (bits64->bits32 x) (logand x (sub1 (ash 1 32))))

; (`bits` is the width of the type, minus 1 for the signed types)  A shift
; by the width of the type or more is computed without making the huge
; number that `ash` would make (and run out of memory for a huge count).
(define (blodwen-bits-shl-signed x y bits)
  (if (> y bits) 0 (blodwen-toSignedInt (ash x y) bits)))

; (a shift by a negative count goes the other way, and wraps around)
(define (blodwen-bits-shr-signed x y bits)
  (if (< y 0) (blodwen-bits-shl-signed x (- y) bits) (ash x (- y))))

(define (blodwen-bits-shl x y bits)
  (if (>= y bits) 0 (logand (ash x y) (sub1 (ash 1 bits)))))

(define blodwen-shl (lambda (x y) (ash x y)))
(define blodwen-shr (lambda (x y) (ash x (- y))))
(define blodwen-and (lambda (x y) (logand x y)))
(define blodwen-or (lambda (x y) (logor x y)))
(define blodwen-xor (lambda (x y) (logxor x y)))

(define cast-num
  (lambda (x)
    (if (number? x) x 0)))
(define destroy-prefix
  (lambda (x)
    (cond
      ((equal? x "") "")
      ((equal? (string-ref x 0) #\#) "")
      (else x))))

(define exact-floor
  (lambda (x)
    (inexact->exact (floor x))))

(define exact-truncate
  (lambda (x)
    (inexact->exact (truncate x))))

(define exact-truncate-boundedInt
  (lambda (x y)
    (blodwen-toSignedInt (exact-truncate x) y)))

(define exact-truncate-boundedUInt
  (lambda (x y)
    (blodwen-toUnsignedInt (exact-truncate x) y)))

(define cast-char-boundedInt
  (lambda (x y)
    (blodwen-toSignedInt (char->integer x) y)))

(define cast-char-boundedUInt
  (lambda (x y)
    (blodwen-toUnsignedInt (char->integer x) y)))

(define cast-string-int
  (lambda (x)
    (exact-truncate (cast-num (string->number (destroy-prefix x))))))

(define cast-string-boundedInt
  (lambda (x y)
    (blodwen-toSignedInt (cast-string-int x) y)))

(define cast-string-boundedUInt
  (lambda (x y)
    (blodwen-toUnsignedInt (cast-string-int x) y)))

(define cast-int-char
  (lambda (x)
    (if (or
          (and (>= x 0) (<= x #xd7ff))
          (and (>= x #xe000) (<= x #x10ffff)))
        (integer->char x)
        (integer->char 0))))

(define cast-string-double
  (lambda (x)
    (exact->inexact (cast-num (string->number (destroy-prefix x))))))


(define (string-concat xs) (apply string-append xs))
(define (string-unpack s) (string->list s))
(define (string-pack xs) (list->string xs))

(define string-cons (lambda (x y) (string-append (string x) y)))
(define string-reverse (lambda (x)
  (list->string (reverse (string->list x)))))
(define (string-substr off len s)
    (let* ((l (string-length s))
          (b (max 0 off))
          (x (max 0 len))
          (end (min l (+ b x))))
          (if (> b l)
              ""
              (substring s b end))))

(define (blodwen-string-iterator-new s)
  0)

(define (blodwen-string-iterator-to-string _ s ofs f)
  (f (substring s ofs (string-length s))))

(define (blodwen-string-iterator-next s ofs)
  (if (>= ofs (string-length s))
      '() ; EOF
      (cons (string-ref s ofs) (+ ofs 1))))

(define either-left
  (lambda (x)
    (vector 0 x)))

(define either-right
  (lambda (x)
    (vector 1 x)))

(define blodwen-error-quit
  (lambda (msg)
    (display msg)
    (newline)
    (call/cc (lambda (k) (blodwen-backtrace k)))
    (if (= (get-thread-id) 0)
        (exit 1)
        ;; (`exit` only ends a thread other than the main one, and the
        ;; program went on, or waited for it for ever)
        (begin
          (flush-output-port (current-output-port))
          (flush-output-port (current-error-port))
          ((foreign-procedure "exit" (int) void) 1)))))

(define (blodwen-get-line p)
    (if (port? p)
        (let ((str (get-line p)))
            (if (eof-object? str)
                ""
                str))
        void))

(define (blodwen-get-char p)
    (if (port? p)
        (let ((chr (get-char p)))
            (if (eof-object? chr)
                #\nul
                chr))
        void))

;; The UTF-8 bytes of a String, followed by a 0, for a foreign call; the
;; caller locks them during the call.  This is what the `string` argument
;; type of foreign-procedure passes, by the same conversion when it exists.
(define blodwen-string->c
  (guard (e [#t (lambda (s) (string->utf8 (string-append s "\x0;")))])
    (eval '($primitive $fp-string->utf8))))

;; Buffers

(define (blodwen-new-buffer size)
  (make-bytevector size 0))

(define (blodwen-buffer-size buf)
  (bytevector-length buf))

(define (blodwen-buffer-setbyte buf loc val)
  (bytevector-u8-set! buf loc val))

(define (blodwen-buffer-getbyte buf loc)
  (bytevector-u8-ref buf loc))

(define (blodwen-buffer-setbits16 buf loc val)
  (bytevector-u16-set! buf loc val (native-endianness)))

(define (blodwen-buffer-getbits16 buf loc)
  (bytevector-u16-ref buf loc (native-endianness)))

(define (blodwen-buffer-setbits32 buf loc val)
  (bytevector-u32-set! buf loc val (native-endianness)))

(define (blodwen-buffer-getbits32 buf loc)
  (bytevector-u32-ref buf loc (native-endianness)))

(define (blodwen-buffer-setbits64 buf loc val)
  (bytevector-u64-set! buf loc val (native-endianness)))

(define (blodwen-buffer-getbits64 buf loc)
  (bytevector-u64-ref buf loc (native-endianness)))

(define (blodwen-buffer-setint8 buf loc val)
  (bytevector-s8-set! buf loc val))

(define (blodwen-buffer-getint8 buf loc)
  (bytevector-s8-ref buf loc))

(define (blodwen-buffer-setint16 buf loc val)
  (bytevector-s16-set! buf loc val (native-endianness)))

(define (blodwen-buffer-getint16 buf loc)
  (bytevector-s16-ref buf loc (native-endianness)))

(define (blodwen-buffer-setint32 buf loc val)
  (bytevector-s32-set! buf loc val (native-endianness)))

(define (blodwen-buffer-getint32 buf loc)
  (bytevector-s32-ref buf loc (native-endianness)))

(define (blodwen-buffer-setint buf loc val)
  (bytevector-s64-set! buf loc val (native-endianness)))

(define (blodwen-buffer-getint buf loc)
  (bytevector-s64-ref buf loc (native-endianness)))

(define (blodwen-buffer-setint64 buf loc val)
  (bytevector-s64-set! buf loc val (native-endianness)))

(define (blodwen-buffer-getint64 buf loc)
  (bytevector-s64-ref buf loc (native-endianness)))

(define (blodwen-buffer-setdouble buf loc val)
  (bytevector-ieee-double-set! buf loc val (native-endianness)))

(define (blodwen-buffer-getdouble buf loc)
  (bytevector-ieee-double-ref buf loc (native-endianness)))

(define (blodwen-stringbytelen str)
  (bytevector-length (string->utf8 str)))

(define (blodwen-buffer-setstring buf loc val)
  (let* [(strvec (string->utf8 val))
         (len (bytevector-length strvec))]
    (bytevector-copy! strvec 0 buf loc len)))

(define (blodwen-buffer-getstring buf loc len)
  (let [(newvec (make-bytevector len))]
    (bytevector-copy! buf loc newvec 0 len)
    (utf8->string newvec)))

(define (blodwen-buffer-copydata buf start len dest loc)
  (bytevector-copy! buf start dest loc len))

;; Threads

(define-record thread-handle (semaphore))

(define (blodwen-thread proc)
  (let [(sema (blodwen-make-semaphore 0))]
    (fork-thread (lambda () (proc (vector 0)) (blodwen-semaphore-post sema)))
    (make-thread-handle sema)
    ))

(define (blodwen-thread-wait handle)
  (blodwen-semaphore-wait (thread-handle-semaphore handle)))

;; Thread mailboxes

(define blodwen-thread-data
  (make-thread-parameter #f))

(define (blodwen-get-thread-data ty)
  (blodwen-thread-data))

(define (blodwen-set-thread-data ty a)
  (blodwen-thread-data a))

;; Semaphore

(define-record semaphore (box mutex condition))

(define (blodwen-make-semaphore init)
  (make-semaphore (box init) (make-mutex) (make-condition)))

(define (blodwen-semaphore-post sema)
  (with-mutex (semaphore-mutex sema)
    (let [(sema-box (semaphore-box sema))]
      (set-box! sema-box (+ (unbox sema-box) 1))
      (condition-signal (semaphore-condition sema))
    )))

(define (blodwen-semaphore-wait sema)
  (with-mutex (semaphore-mutex sema)
    (let [(sema-box (semaphore-box sema))]
      (when (= (unbox sema-box) 0)
        (condition-wait (semaphore-condition sema) (semaphore-mutex sema)))
      (set-box! sema-box (- (unbox sema-box) 1))
      )))

;; Barrier

(define-record barrier (count-box num-threads mutex cond))

(define (blodwen-make-barrier num-threads)
  (make-barrier (box 0) num-threads (make-mutex) (make-condition)))

(define (blodwen-barrier-wait barrier)
  (let [(count-box (barrier-count-box barrier))
        (num-threads (barrier-num-threads barrier))
        (mutex (barrier-mutex barrier))
        (condition (barrier-cond barrier))]
    (with-mutex mutex
    (let* [(count-old (unbox count-box))
           (count-new (+ count-old 1))]
      (set-box! count-box count-new)
      (if (= count-new num-threads)
          (condition-broadcast condition)
          (condition-wait condition mutex))
      ))))

;; Channel
; With thanks to Alain Zscheile (@zseri) for help with understanding condition
; variables, and figuring out where the problems were and how to solve them.

(define-record channel (read-mut read-cv read-box val-cv val-box))

(define (blodwen-make-channel ty)
  (make-channel
    (make-mutex)
    (make-condition)
    (box #t)
    (make-condition)
    (box '())
    ))

; block on the read status using read-cv until the value has been read
(define (channel-put-while-helper chan)
  (let ([read-mut (channel-read-mut chan)]
        [read-box (channel-read-box chan)]
        [read-cv  (channel-read-cv  chan)]
        )
    (if (unbox read-box)
      (void)    ; val has been read, so everything is fine
      (begin    ; otherwise, block/spin with cv
        (condition-wait read-cv read-mut)
        (channel-put-while-helper chan)
        )
      )))

(define (blodwen-channel-put ty chan val)
  (with-mutex (channel-read-mut chan)
    (channel-put-while-helper chan)
    (let ([read-box (channel-read-box chan)]
          [val-box  (channel-val-box  chan)]
          )
      (set-box! val-box val)
      (set-box! read-box #f)
      ))
  (condition-signal (channel-val-cv chan))
  )

; block on the value until it has been set
(define (channel-get-while-helper chan)
  (let ([read-mut (channel-read-mut chan)]
        [read-box (channel-read-box chan)]
        [val-cv   (channel-val-cv   chan)]
        )
    (if (unbox read-box)
      (begin
        (condition-wait val-cv read-mut)
        (channel-get-while-helper chan)
        )
      (void)
      )))

(define (blodwen-channel-get ty chan)
  (mutex-acquire (channel-read-mut chan))
  (channel-get-while-helper chan)
  (let* ([val-box  (channel-val-box  chan)]
         [read-box (channel-read-box chan)]
         [read-cv  (channel-read-cv  chan)]
         [the-val  (unbox val-box)]
         )
    (set-box! val-box '())
    (set-box! read-box #t)
    (mutex-release (channel-read-mut chan))
    (condition-signal read-cv)
    the-val))

(define (blodwen-channel-get-non-blocking ty chan)
  (if (mutex-acquire (channel-read-mut chan) #f)
    (let* ([val-box  (channel-val-box  chan)]
           [read-box (channel-read-box chan)]
           [read-cv  (channel-read-cv  chan)]
           [the-val  (unbox val-box)]
          )
      (if (null? the-val)
          (begin
           (mutex-release (channel-read-mut chan))
           '())
          (begin
            (set-box! val-box '())
            (set-box! read-box #t)
            (mutex-release (channel-read-mut chan))
            (condition-signal read-cv)
            (box the-val))
      ))
  '()))

(define (blodwen-channel-get-with-timeout ty chan timeout)
  ;; timeout is in milliseconds, convert to nanoseconds
  (let* ([timeout-ns (* timeout 1000000)]
         [sleep-ns 10000] ; 10 us step
         [sleep-time (make-time 'time-duration (mod sleep-ns 1000000000)
                                                (div sleep-ns 1000000000))])
    (let loop ([elapsed 0])
      (if (mutex-acquire (channel-read-mut chan) #f)
          (let* ([val-box  (channel-val-box chan)]
                 [the-val  (unbox val-box)])
            (if (null? the-val)
                (if (>= elapsed timeout-ns)
                    (begin
                      (mutex-release (channel-read-mut chan))
                      '())
                    (begin
                      (mutex-release (channel-read-mut chan))
                      (sleep sleep-time)
                      (loop (+ elapsed sleep-ns))))
                (let* ([read-box (channel-read-box chan)]
                       [read-cv  (channel-read-cv chan)])
                  (set-box! val-box '())
                  (set-box! read-box #t)
                  (mutex-release (channel-read-mut chan))
                  (condition-signal read-cv)
                  (box the-val))))
          (begin
            (sleep sleep-time)
            (loop (+ elapsed sleep-ns)))))))

;; Mutex

(define (blodwen-make-mutex)
  (make-mutex))
(define (blodwen-mutex-acquire mutex)
  (mutex-acquire mutex))
(define (blodwen-mutex-release mutex)
  (mutex-release mutex))

;; Condition variable

(define (blodwen-make-condition)
  (make-condition))
(define (blodwen-condition-wait condition mutex)
  (condition-wait condition mutex))
(define (blodwen-condition-wait-timeout condition mutex timeout)
  (let* [(sec (div timeout 1000000))
         (micro (mod timeout 1000000))]
    (condition-wait condition mutex (make-time 'time-duration (* 1000 micro) sec))))
(define (blodwen-condition-signal condition)
  (condition-signal condition))
(define (blodwen-condition-broadcast condition)
  (condition-broadcast condition))

;; Future

(define-record future-internal (result ready mutex signal))
(define (blodwen-make-future ty work)
  (let ([future (make-future-internal #f #f (make-mutex) (make-condition))])
    (fork-thread (lambda ()
      (let ([result (work '())])
        (with-mutex (future-internal-mutex future)
          (set-future-internal-result! future result)
          (set-future-internal-ready! future #t)
          (condition-broadcast (future-internal-signal future))))))
    future))
(define (blodwen-await-future ty future)
  (let ([mutex (future-internal-mutex future)])
    (with-mutex mutex
      (if (not (future-internal-ready future))
          (condition-wait (future-internal-signal future) mutex))
      (future-internal-result future))))

(define (blodwen-sleep s) (sleep (make-time 'time-duration 0 s)))
(define (blodwen-usleep s)
  (let ((sec (div s 1000000))
        (micro (mod s 1000000)))
       (sleep (make-time 'time-duration (* 1000 micro) sec))))

(define (blodwen-clock-time-utc) (current-time 'time-utc))
(define (blodwen-clock-time-monotonic) (current-time 'time-monotonic))
(define (blodwen-clock-time-duration) (current-time 'time-duration))
(define (blodwen-clock-time-process) (current-time 'time-process))
(define (blodwen-clock-time-thread) (current-time 'time-thread))
(define (blodwen-clock-time-gccpu) (current-time 'time-collector-cpu))
(define (blodwen-clock-time-gcreal) (current-time 'time-collector-real))
(define (blodwen-is-time? clk) (if (time? clk) 1 0))
(define (blodwen-clock-second time) (time-second time))
(define (blodwen-clock-nanosecond time) (time-nanosecond time))

(define (blodwen-arg-count)
  (length (command-line)))

(define (blodwen-arg n)
  (if (< n (length (command-line))) (list-ref (command-line) n) ""))

(define (blodwen-hasenv var)
  (if (eq? (getenv var) #f) 0 1))

;; Randoms
(define random-seed-register 0)
(define (initialize-random-seed-once)
  (if (= (virtual-register random-seed-register) 0)
      (let ([seed (time-nanosecond (current-time))])
        (set-virtual-register! random-seed-register seed)
        (random-seed seed))))

(define (blodwen-random-seed seed)
  (set-virtual-register! random-seed-register seed)
  (random-seed seed))
(define blodwen-random
  (case-lambda
    ;; no argument, pick a real value from [0, 1.0)
    [() (begin
          (initialize-random-seed-once)
          (random 1.0))]
    ;; single argument k, pick an integral value from [0, k)
    [(k)
      (begin
        (initialize-random-seed-once)
        (if (> k 0)
              (random k)
              (assertion-violationf 'blodwen-random "invalid range argument ~a" k)))]))

;; For finalisers

(define blodwen-finaliser (make-guardian))
(define (blodwen-register-object obj proc)
  (let [(x (cons obj proc))]
       (blodwen-finaliser x)
       x))
(define blodwen-run-finalisers
  (lambda ()
    (let run ()
      (let ([x (blodwen-finaliser)])
        (when x
          (((cdr x) (car x)) 'erased)
          (run))))))

;; For creating and reading back scheme objects

; read a scheme string and evaluate it, returning 'Just result' on success
; TODO: catch exception!
(define (blodwen-eval-scheme str)
  (guard
     (x [#t '()]) ; Nothing on failure
     (box (eval (read (open-input-string str)))))
  ); box == Just

(define (blodwen-eval-okay obj)
  (if (null? obj)
      0
      1))

(define (blodwen-get-eval-result obj)
  (unbox obj))

(define (blodwen-debug-scheme obj)
  (display obj) (newline))

(define (blodwen-is-number obj)
  (if (number? obj) 1 0))

(define (blodwen-is-integer obj)
  (if (and (number? obj) (exact? obj)) 1 0))

(define (blodwen-is-float obj)
  (if (flonum? obj) 1 0))

(define (blodwen-is-char obj)
  (if (char? obj) 1 0))

(define (blodwen-is-string obj)
  (if (string? obj) 1 0))

(define (blodwen-is-procedure obj)
  (if (procedure? obj) 1 0))

(define (blodwen-is-symbol obj)
  (if (symbol? obj) 1 0))

(define (blodwen-is-vector obj)
  (if (vector? obj) 1 0))

(define (blodwen-is-nil obj)
  (if (null? obj) 1 0))

(define (blodwen-is-pair obj)
  (if (pair? obj) 1 0))

(define (blodwen-is-box obj)
  (if (box? obj) 1 0))

(define (blodwen-make-symbol str)
  (string->symbol str))

; The below rely on checking that the objects are the right type first.

(define (blodwen-vector-ref obj i)
  (vector-ref obj i))

(define (blodwen-vector-length obj)
  (vector-length obj))

(define (blodwen-vector-list obj)
  (vector->list obj))

(define (blodwen-unbox obj)
  (unbox obj))

(define (blodwen-apply obj arg)
  (obj arg))

(define (blodwen-force obj)
  (obj))

(define (blodwen-read-symbol sym)
  (symbol->string sym))

(define (blodwen-id x) x)

;; Backtraces of a fatal error (see docs/source/backends/chez.rst)
;;
;; When they are on (IDRIS2_CHEZ_BACKTRACE=1, or by default in a program
;; compiled with `--directive chez-backtrace`), a program that dies of
;; `idris_crash` or of a missing case in partial code (`blodwen-error-quit`),
;; or of an error that Chez raises and nobody handles (the base exception
;; handler), prints the Idris functions of the continuation of the error on
;; stderr, after the message of the error, the innermost first.
;;
;; The frames are those of the continuation, walked with the inspector: the
;; name of the code of a return point is the Scheme name of its function.
;; The calls in tail position leave no frame.  The directive gives the
;; program's table of the Idris names of its functions and where they are
;; defined to `blodwen-backtrace-names`, and keeps Chez from inlining them
;; (see Compiler.Scheme.Chez); without it, the Scheme names are turned back
;; into Idris names as well as they can be.
;;
;; Nothing of this runs before a fatal error, but for reading the variable
;; when the program starts.
;;
;; (boxes: the variables of the library of support-sep.ss cannot be assigned)

;; #t with the directive
(define blodwen-bt-default (box #f))
;; #(scheme-name idris-name location) for every function, from the directive
;; (whole programs only)
(define blodwen-bt-names (box #f))

;; An identity that Chez does not see through: a function bound to its
;; result is not inlined (with the directive).
(define blodwen-bt-keep
  (let ([keep (lambda (f) f)])
    (set! keep keep)
    keep))

(define (blodwen-bt-on?)
  (let ([e (getenv "IDRIS2_CHEZ_BACKTRACE")])
    (if (and e (not (string=? e "")))
        (not (string=? e "0"))
        (unbox blodwen-bt-default))))

;; Print the Idris functions of the continuation k on the port p.
(define (blodwen-bt-print k p)
  (blodwen-bt-printer (unbox blodwen-bt-names) k p))

;; Print the backtrace of the continuation k, if backtraces are on.
(define (blodwen-backtrace k)
  (when (blodwen-bt-on?)
    (flush-output-port (current-output-port))
    (let ([p (current-error-port)])
      (blodwen-bt-print k p)
      (flush-output-port p))))

;; Errors that Chez raises and that nobody handles: the message, as the
;; default handler prints it, then the backtrace, then what the default
;; handler does (the program, or the thread, ends).
(define (blodwen-bt-handler old)
  (lambda (c)
    (if (and (serious-condition? c) (blodwen-bt-on?))
        (let ([p (console-error-port)])
          (flush-output-port (console-output-port))
          (display-condition c p)
          (newline p)
          ;; (the handler runs in the continuation of the error; that of
          ;; the condition, if any, is empty after a signal)
          (blodwen-bt-print (call/cc (lambda (k) k)) p)
          (flush-output-port p)
          (reset))
        (old c))))

(define blodwen-bt-started (box #f))

(define (blodwen-bt-start)
  (when (and (not (unbox blodwen-bt-started)) (blodwen-bt-on?))
    (set-box! blodwen-bt-started #t)
    (base-exception-handler (blodwen-bt-handler (base-exception-handler)))))

;; Called by a program compiled with `--directive chez-backtrace`, with the
;; Scheme names of its functions, their Idris names and where they are (or
;; #f, in an incremental build).
(define (blodwen-backtrace-names names)
  (set-box! blodwen-bt-default #t)
  (set-box! blodwen-bt-names names)
  (blodwen-bt-start))

;; Print the Idris functions of the continuation k on the port p, with the
;; table of names (or #f).
(define blodwen-bt-printer
  (lambda (names k p)
     (letrec*
       (;; the innermost frames, and the outermost ones of a deep
        ;; continuation, which is not walked beyond 5 million frames
        [head-size 48]
        [tail-size 12]
        [limit 5000000]
        [table
         (and names
              (let ([t (make-hashtable string-hash string=?)])
                (vector-for-each
                  (lambda (e) (hashtable-set! t (vector-ref e 0) e))
                  names)
                t))]
        ;; The Idris name of a Scheme name made by
        ;; Compiler.Scheme.Common.schName, or #f if it is not one (a
        ;; function of the support code, or of Chez).  The names of the
        ;; namespaces begin with a capital letter, or `_` (`_PE`), and are
        ;; followed by `-`; a character other than a letter, a digit or `_`
        ;; is written `C-` and its code.
        [demangle
         (lambda (s)
           (letrec*
             ([n (string-length s)]
              ;; the end of the escape `C-NN` at i (before j), or #f
              [escape-end
               (lambda (i j)
                 (and (< (+ i 2) j)
                      (char=? (string-ref s i) #\C)
                      (char=? (string-ref s (+ i 1)) #\-)
                      (char-numeric? (string-ref s (+ i 2)))
                      (let loop ([e (+ i 2)])
                        (if (and (< e j) (char-numeric? (string-ref s e)))
                            (loop (+ e 1))
                            e))))]
              ;; the characters from i to j, with the escapes decoded
              [decode
               (lambda (i j)
                 (let loop ([i i] [acc '()])
                   (cond
                     [(>= i j) (list->string (reverse acc))]
                     [(escape-end i j)
                      => (lambda (e)
                           (loop e (cons (integer->char
                                           (string->number (substring s (+ i 2) e)))
                                         acc)))]
                     [else (loop (+ i 1) (cons (string-ref s i) acc))])))]
              ;; the position of the first `-` from i not in an escape
              [separator
               (lambda (i)
                 (cond
                   [(>= i n) #f]
                   [(escape-end i n) => separator]
                   [(char=? (string-ref s i) #\-) i]
                   [else (separator (+ i 1))]))]
              [prefix?
               (lambda (x i)
                 (let ([m (string-length x)])
                   (and (<= (+ i m) n) (string=? (substring s i (+ i m)) x))))]
              [digits?
               (lambda (i)
                 (and (< i n)
                      (let loop ([j i])
                        (or (= j n)
                            (and (char-numeric? (string-ref s j)) (loop (+ j 1)))))))]
              ;; a case or with block: the name of its function, `-`, a number
              [block
               (lambda (what i)
                 (let loop ([j (- n 1)])
                   (cond
                     [(<= j i) (string-append what (decode i n))]
                     [(char=? (string-ref s j) #\-)
                      (string-append what (decode i j))]
                     [else (loop (- j 1))])))]
              ;; a name without its namespace, from i
              [name
               (lambda (i)
                 (cond
                   [(prefix? "u--" i) (decode (+ i 3) n)]
                   [(prefix? "rf--" i) (decode (+ i 4) n)]
                   [(prefix? "pat--" i) (name (+ i 5))]
                   [(prefix? "fn--" i) (decode (+ i 4) n)]
                   [(prefix? "case--" i) (block "case block in " (+ i 6))]
                   [(prefix? "with--" i) (block "with block in " (+ i 6))]
                   [(prefix? "n--" i)
                    ;; Nested (x, y) m is `x:y:m`
                    (let* ([a (separator (+ i 3))]
                           [b (and a (separator (+ a 1)))])
                      (if b
                          (string-append (substring s (+ i 3) a) ":"
                                         (substring s (+ a 1) b) ":" (name (+ b 1)))
                          (decode i n)))]
                   [else
                    ;; `f-0` is the machine name {f:0}
                    (let ([d (separator i)])
                      (if (and d (digits? (+ d 1)))
                          (string-append "{" (decode i d) ":" (substring s (+ d 1) n) "}")
                          (decode i n)))]))])
             (and (> n 0)
                  (let ([c (string-ref s 0)])
                    (cond
                      [(or (char-upper-case? c) (char=? c #\_))
                       ;; the namespace, whose parts are separated by `-`
                       ;; (escaped)
                       (let ([d (separator 0)])
                         (and d
                              (string-append
                                (list->string
                                  (map (lambda (c) (if (char=? c #\-) #\. c))
                                       (string->list (decode 0 d))))
                                "." (name (+ d 1)))))]
                      [(or (prefix? "u--" 0) (prefix? "n--" 0)
                           (prefix? "case--" 0) (prefix? "with--" 0))
                       (name 0)]
                      [else #f])))))]
        ;; the line of the frame of the code named s, or #f
        [frame
         (lambda (s)
           (and (string? s)
                (if table
                    (let ([e (hashtable-ref table s #f)])
                      (and e
                           (if (vector-ref e 2)
                               (string-append (vector-ref e 1) " (" (vector-ref e 2) ")")
                               (vector-ref e 1))))
                    (demangle s))))]
        [tail (make-vector tail-size #f)]
        ;; consecutive frames of the same function make one line
        [line #f]
        [count 0]
        [end-line
         (lambda ()
           (when line
             (if (> count 1)
                 (fprintf p "  ~a, ~a frames~%" line count)
                 (fprintf p "  ~a~%" line))
             (set! line #f)))]
        [add-line
         (lambda (f)
           (if (and line (string=? f line))
               (set! count (+ count 1))
               (begin (end-line) (set! line f) (set! count 1))))])
       (let walk ([o (inspect/object k)] [walked 0] [n 0] [head '()])
         (if (and (eq? (o 'type) 'continuation) (< walked limit))
             (let ([f (frame ((o 'code) 'name))])
               (if f
                   (begin
                     (vector-set! tail (modulo n tail-size) f)
                     (walk (o 'link) (+ walked 1) (+ n 1)
                           (if (< n head-size) (cons f head) head)))
                   (walk (o 'link) (+ walked 1) n head)))
             (let ([id (get-thread-id)])
               (if (= id 0)
                   (fprintf p "Backtrace of the main thread, innermost call first:~%")
                   (fprintf p "Backtrace of thread ~a, innermost call first:~%" id))
               (for-each add-line (reverse head))
               (cond
                 [(= n 0)
                  (fprintf p "  (no frames of Idris functions)~%")]
                 [(eq? (o 'type) 'continuation)
                  (end-line)
                  (fprintf p "  ... and more than ~a more frames~%"
                           (- limit head-size))]
                 [(> n head-size)
                  (end-line)
                  (let ([first (max head-size (- n tail-size))])
                    (when (> first head-size)
                      (fprintf p "  ... ~a more frames ...~%" (- first head-size)))
                    (do ([i first (+ i 1)]) ((= i n))
                      (add-line (vector-ref tail (modulo i tail-size)))))])
               (end-line)))))))

(define blodwen-bt-startup (blodwen-bt-start))
