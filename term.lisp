(defpackage :lem.term
  (:use :cl)
  (:export :get-color-pair
           :term-set-foreground
           :term-set-background
           :background-mode
           :term-init
           :term-finalize
           :term-set-tty
           ;;win32 patch
           :get-mouse-mode
           :enable-mouse
           :disable-mouse))
(in-package :lem.term)

#+nil
(cffi:defcvar ("COLOR_PAIRS" *COLOR-PAIRS* :library charms/ll::libcurses) :int)

;; mouse mode
;;   =0: not use mouse
;;   =1: use mouse
#+nil
(defvar *mouse-mode* #+win32 1 #-win32 0)

;; for mouse
#+nil
(defun get-mouse-mode ()
  *mouse-mode*)
#+nil
(defun enable-mouse ()
  (setf ncurses-clone::*mouse-enabled-p* t)
  #+nil
  (progn
    (setf *mouse-mode* 1)
    ;;FIXME- mouse?
    (charms/ll:mousemask (logior charms/ll:all_mouse_events
				 charms/ll:report_mouse_position))))
#+nil
(defun disable-mouse ()
  (setf ncurses-clone::*mouse-enabled-p* nil)
  #+nil
  (progn
    (setf *mouse-mode* 0)
    ;;FIXME - mouse?
    (charms/ll:mousemask 0)))


(defvar *colors*)

(defun color-red (color) (first color))
(defun color-green (color) (second color))
(defun color-blue (color) (third color))
(defun color-number (color) (fourth color))

(defun init-colors (n)
  (let ((counter 0))
    (flet ((add-color (r g b)
	     #+nil
             (when (<= 8 counter)
               (charms/ll:init-color counter
                                     (round (* r 1000/255))
                                     (round (* g 1000/255))
                                     (round (* b 1000/255))))
             (setf (aref *colors* counter) (list r g b counter))
             (incf counter)))
      (setf *colors* (make-array n))
      (dotimes (i n)
	(apply #'add-color
	       (mapcar (lambda (x)
			 (floor (* x 255)))
		       (multiple-value-list (color-fun i))))))))

(defun rgb-to-hsv (r g b)
  (let ((max (max r g b))
        (min (min r g b)))
    (let ((h (cond ((= min max) 0)
                   ((= r max)
                    (* 60 (/ (- g b) (- max min))))
                   ((= g max)
                    (+ 120 (* 60 (/ (- b r) (- max min)))))
                   ((= b max)
                    (+ 240 (* 60 (/ (- r g) (- max min))))))))
      (when (minusp h) (incf h 360))
      (let ((s (if (= min max) 0 (* 100 (/ (- max min) max))))
            (v (* 100 (/ max 255))))
        (values (round (float h))
                (round (float s))
                (round (float v)))))))

(defun rgb-to-hsv-distance (r1 g1 b1 r2 g2 b2)
  (multiple-value-bind (h1 s1 v1) (rgb-to-hsv r1 g1 b1)
    (multiple-value-bind (h2 s2 v2) (rgb-to-hsv r2 g2 b2)
      (let ((h (abs (- h1 h2)))
            (s (abs (- s1 s2)))
            (v (abs (- v1 v2))))
        (+ (* h h) (* s s) (* v v))))))

(defun get-color-rgb (r g b)
  (let ((min most-positive-fixnum)
        (best-color))
    (loop :for color :across *colors*
          :do (let ((dist (rgb-to-hsv-distance
                           r g b
                           (color-red color) (color-green color) (color-blue color))))
                (when (< dist min)
                  (setf min dist)
                  (setf best-color color))))
    (color-number best-color)))

(defun get-color-1 (string)
  (alexandria:when-let ((color (lem:parse-color string)))
    (get-color-rgb (color-red color)
                   (color-green color)
                   (color-blue color))))

(defun get-color (string)
  (let ((color (get-color-1 string)))
    (if color
        (values color t)
        (values 0 nil))))


(defvar *pair-counter* 0)
(defvar *color-pair-table* (make-hash-table :test 'equal))

(defun reset-color-pair ()
  (clrhash *color-pair-table*)
  (setf *pair-counter* 0))

(defun init-pair (pair-color)
  (incf *pair-counter*)
  ;;(charms/ll:init-pair *pair-counter* (car pair-color) (cdr pair-color))
  (ncurses-clone::ncurses-init-pair *pair-counter* (car pair-color) (cdr pair-color))
  (setf (gethash pair-color *color-pair-table*)
	*pair-counter* ;;FIXME wat
	;;(ncurses-clone::ncurses-color-pair *pair-counter*)
        ;;(charms/ll:color-pair *pair-counter*)
	)
  ;;FIXME:: return color-pair?
  *pair-counter*)
#+nil
"After it has been initialized, COLOR_PAIR(n), a macro defined in <curses.h>, can be used as a new video attribute. "
;;;https://linux.die.net/man/3/color_pair
(defparameter *color-pairs* 256) ;;;FIXME::wtf does this mean? I added this and am guessing.

(defun get-color-pair (fg-color-name bg-color-name)
  (let* ((fg-color (if (null fg-color-name) -1 (get-color fg-color-name)))
         (bg-color (if (null bg-color-name) -1 (get-color bg-color-name)))
         (pair-color (cons fg-color bg-color)))
    (cond ((gethash pair-color *color-pair-table*))
          ((< *pair-counter* *color-pairs*)
           (init-pair pair-color))
          (t 0))))

#+(or)
(defun get-color-content (n)
  (cffi:with-foreign-pointer (r (cffi:foreign-type-size '(:pointer :short)))
    (cffi:with-foreign-pointer (g (cffi:foreign-type-size '(:pointer :short)))
      (cffi:with-foreign-pointer (b (cffi:foreign-type-size '(:pointer :short)))
        (charms/ll:color-content n r g b)
        (list (cffi:mem-ref r :short)
              (cffi:mem-ref g :short)
              (cffi:mem-ref b :short))))))

(defun get-default-colors ()
  (ncurses-clone::ncurses-pair-content 0)
  #+nil
  (cffi:with-foreign-pointer (f (cffi:foreign-type-size '(:pointer :short)))
    (cffi:with-foreign-pointer (b (cffi:foreign-type-size '(:pointer :short)))
      (charms/ll:pair-content 0 f b)
      (values (cffi:mem-ref f :short)
              (cffi:mem-ref b :short)))))

(defun set-default-color (foreground background)
  ;;;;-1 for values mean defaults.
  (let ((fg-color (if foreground (get-color foreground) -1))
        (bg-color (if background (get-color background) -1)))
    (ncurses-clone::ncurses-assume-default-color fg-color bg-color)
    #+nil
    (charms/ll:assume-default-colors fg-color
                                     bg-color)))

(defun term-set-foreground (name)
  (multiple-value-bind (fg found) (get-color name)
    (cond (found
	   (;;charms/ll:assume-default-colors
	    ncurses-clone::ncurses-assume-default-color
	    fg ncurses-clone::*bg-default*)
	   t)
	  (t
	   (error "Undefined color: ~A" name)))))

(defun term-set-background (name)
  (multiple-value-bind (bg found) (get-color name)
    (cond (found
	   (;;charms/ll:assume-default-colors
	    ncurses-clone::ncurses-assume-default-color
	    ncurses-clone::*fg-default* bg)
	   t)
	  (t
	   (error "Undefined color: ~A" name)))))

(defun background-mode ()
  (let ((b (nth-value 1 (get-default-colors))))
    (cond ((= b -1) :light
	   )
          (t
           (let ((color (aref *colors* b)))
             (lem:rgb-to-background-mode (color-red color)
                                         (color-green color)
                                         (color-blue color)))))))

;;;

;;(cffi:defcfun "fopen" :pointer (path :string) (mode :string))
;;(cffi:defcfun "fclose" :int (fp :pointer))
;;(cffi:defcfun "fileno" :int (fd :pointer))

#+nil
(cffi:defcstruct winsize
  (ws-row :unsigned-short)
  (ws-col :unsigned-short)
  (ws-xpixel :unsigned-short)
  (ws-ypixel :unsigned-short))

#+nil
(cffi:defcfun ioctl :int
  (fd :int)
  (cmd :int)
  &rest)

;;(defvar *tty-name* nil)
;;(defvar *term-io* nil)

#+nil
(defun resize-term ()
  (when *term-io*
    (cffi:with-foreign-object (ws '(:struct winsize))
      (when (= 0 (ioctl (fileno *term-io*) 21523 :pointer ws))
        (cffi:with-foreign-slots ((ws-row ws-col) ws (:struct winsize))
          (charms/ll:resizeterm ws-row ws-col))))))
#+nil
(defun term-init-tty (tty-name)
  (let* ((io (fopen tty-name "r+")))
    (setf *term-io* io)
    (cffi:with-foreign-string (term "xterm")
      (charms/ll:newterm term io io))))


(defun term-init ()
  #+(or (and ccl unix) (and lispworks unix))
  (lem-setlocale/cffi:setlocale lem-setlocale/cffi:+lc-all+ "")
  #+nil
  (if *tty-name*
      (term-init-tty *tty-name*)
      (charms/ll:initscr))
  #+nil
  (when (zerop (charms/ll:has-colors))
    (charms/ll:endwin)
    (write-line "Please execute TERM=xterm-256color and try again.")
    (return-from term-init nil))
  ;;(charms/ll:start-color)
  ;; enable default color code (-1)
  ;;#+win32(charms/ll:use-default-colors)
  (init-colors 256
	       )
  ;;;FIXME: find out what all these options do
  ;;(set-default-color nil nil)
  ;;(charms/ll:noecho)
  ;;(charms/ll:cbreak)
  ;;(charms/ll:raw)
  ;;(charms/ll:nonl)
  ;;(charms/ll:refresh)
  ;;(charms/ll:keypad charms/ll:*stdscr* 1)
  ;;(setf charms/ll::*escdelay* 0)
  ;; (charms/ll:curs-set 0)
  ;; for mouse
  #+nil
  (when (= *mouse-mode* 1)
    (enable-mouse))
  t)

#+nil
(defun term-init ()
  #+(or (and ccl unix) (and lispworks unix))
  (lem-setlocale/cffi:setlocale lem-setlocale/cffi:+lc-all+ "")
  (if *tty-name*
      (term-init-tty *tty-name*)
      (charms/ll:initscr))
  (when (zerop (charms/ll:has-colors))
    (charms/ll:endwin)
    (write-line "Please execute TERM=xterm-256color and try again.")
    (return-from term-init nil))
  (charms/ll:start-color)
  ;; enable default color code (-1)
  ;;#+win32(charms/ll:use-default-colors)
  (init-colors charms/ll:*colors*)
  (set-default-color nil nil)
  "Normally, the tty driver buffers typed characters until a newline or carriage return is typed. The cbreak routine disables line buffering and erase/kill character-processing (interrupt and flow control characters are unaffected), making characters typed by the user immediately available to the program. The nocbreak routine returns the terminal to normal (cooked) mode.

Initially the terminal may or may not be in cbreak mode, as the mode is inherited; therefore, a program should call cbreak or nocbreak explicitly. Most interactive programs using curses set the cbreak mode. Note that cbreak overrides raw. [See curs_getch(3X) for a discussion of how these routines interact with echo and noecho.]

The echo and noecho routines control whether characters typed by the user are echoed by getch as they are typed. Echoing by the tty driver is always disabled, but initially getch is in echo mode, so characters typed are echoed. Authors of most interactive programs prefer to do their own echoing in a controlled area of the screen, or not to echo at all, so they disable echoing by calling noecho. [See curs_getch(3X) for a discussion of how these routines interact with cbreak and nocbreak.] https://linux.die.net/man/3/raw"
  (charms/ll:noecho)
  (charms/ll:cbreak)
  (charms/ll:raw)
  "The raw and noraw routines place the terminal into or out of raw mode. Raw mode is similar to cbreak mode, in that characters typed are immediately passed through to the user program. The differences are that in raw mode, the interrupt, quit, suspend, and flow control characters are all passed through uninterpreted, instead of generating a signal. The behavior of the BREAK key depends on other bits in the tty driver that are not set by curses. https://linux.die.net/man/3/raw"
  (charms/ll:nonl)
  "The nl and nonl routines control whether the underlying display device translates the return key into newline on input, and whether it translates newline into return and line-feed on output (in either case, the call addch('\n') does the equivalent of return and line feed on the virtual screen). Initially, these translations do occur. If you disable them using nonl, curses will be able to make better use of the line-feed capability, resulting in faster cursor motion. Also, curses will then be able to detect the return key. https://linux.die.net/man/3/clearok"
  (charms/ll:refresh)
  (charms/ll:keypad charms/ll:*stdscr* 1)
  (setf charms/ll::*escdelay* 0)
  ;; (charms/ll:curs-set 0)
  ;; for mouse
  (when (= *mouse-mode* 1)
    (enable-mouse))
  t)

#+nil
(defun term-set-tty (tty-name)
  (setf *tty-name* tty-name))

#+nil
(defun term-finalize ()
  (when *term-io*
    (fclose *term-io*)
    (setf *term-io* nil))
  (charms/ll:endwin)
  (charms/ll:delscreen charms/ll:*stdscr*))

(defun c6? (x)
  (let ((acc nil))
    (loop
       (push (mod x 6) acc)
       (setf x (floor x 6))
       (when (zerop x)
	 (return)))
    acc))


(defparameter *ansi-color-names-vector* nil)
(defun color-fun (color)
  (labels ((bcolor (r g b)
	     (values (/ (utility::floatify r) 255.0)
		     (/ (utility::floatify g) 255.0)
		     (/ (utility::floatify b) 255.0)))
	   (c (r g b)
	     (bcolor r g b))
	   (c6 (x)
	     (destructuring-bind (r g b) (last (append (list 0 0 0)
						       (c6? x))
					       3)
	       (bcolor (* 51 r)
		       (* 51 g)
		       (* 51 b))))
	   (g (x)
	     (let* ((magic (load-time-value (/ 255.0 23.0)))
		    (val (* x magic)))
	       (c val val val))))
    
    (let ((color-data (nth color *ansi-color-names-vector*)))
      (when color-data
	(return-from color-fun (apply #'c color-data))))
    ;;FIXME::the case statement below goes through redundant numbers?
    (case color
      (0 (c 0 0 0))
      (1 (c 205 0 0))
      (2 (c 0 205 0))
      (3 (c 205 205 0))
      (4 (c 0 0 238))
      (5 (c 205 0 205))
      (6 (c 0 205 205))
      (7 (c 229 229 229))
      (8 (c 127 127 127))
      (9 (c 255 0 0))
      (10 (c 0 255 0))
      (11 (c 255 255 0))
      (12 (c 92 92 255))
      (13 (c 255 0 255))
      (14 (c 0 255 255))
      (15 (c 255 255 255))
      (t (if (< color (+ 16 (* 6 6 6)))
	     (c6 (- color 16))
	     (g (- color (+ 16 (* 6 6 6)))))))))

#+nil
(defun detect-distance ()
  (map 'list
       (lambda (x y)
	 (mapcar '- x y))
       (mapcar (lambda (x) (mapcar (lambda (x) (* x 255))
				   (multiple-value-list (color-fun x))))
	       (alexandria:iota 256))
       *colors*))
