(module
  (import "cabi" "cabi_realloc" (func $realloc (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (export "cabi_realloc" (func $realloc))
  (type $str_utf8 (array (mut i8)))

  (func $cabi-reverse (export "cm32p2|local:root/reverse|reverse-string")
    (param $ptr i32)
    (param $len i32)
    (result i32)
	(call $copy-string-to-memory
	  (call $reverse
	    (call $copy-string-from-memory (local.get $ptr) (local.get $len)))))

  ;; CABI post: free the memory used to store the result string
  (func
    (export "cm32p2|local:root/reverse|reverse-string_post")
    (param $ptr i32)
    (local $len i32)
    (local.set $len (i32.load offset=4 (local.get $ptr)))
    (call
      $realloc
      (local.get $ptr)
      (i32.add (local.get $len) (i32.const 8))
      (i32.const 0)
      (i32.const 0))
    (drop))
 
  (func $reverse
    (param $str (ref $str_utf8))
	(result (ref $str_utf8))
	(local $out (ref $str_utf8))
    (local $len i32)
	(local $idx i32)
	(local.set $len (array.len (local.get $str)))
	(local.set $out (array.new_default $str_utf8 (local.get $len)))
	(block
	  (loop
	    (i32.ge_s (local.get $idx) (local.get $len))
		(br_if 1)
		(array.set $str_utf8
		  (local.get $out)
		  (local.get $idx)
		  (array.get $str_utf8
		    (local.get $str)
			(i32.sub
			  (local.get $len)
			  (i32.add (local.get $idx) (i32.const 1)))))
		(local.set $idx (i32.add (local.get $idx) (i32.const 1)))
		(br 0)))
	(local.get $out))

  (func $copy-string-from-memory
    (param $ptr i32)
	(param $len i32)
	(result (ref $str_utf8))
	(local $str (ref $str_utf8))
	(local $idx i32)
	(local.set $str (array.new_default $str_utf8 (local.get $len)))
	(block
	  (loop
	    (i32.ge_s (local.get $idx) (local.get $len))
		(br_if 1)
		(array.set $str_utf8
		  (local.get $str)
		  (local.get $idx)
		  (i32.load8_u (i32.add (local.get $ptr) (local.get $idx))))
		(local.set $idx (i32.add (local.get $idx) (i32.const 1)))
		(br 0)))
    (local.get $str))

  (func $copy-string-to-memory
    (param $str (ref $str_utf8))
	(result i32)
	(local $ptr i32)
	(local $len i32)
	(local $idx i32)
	(local.set $len (array.len (local.get $str)))
	(local.set $ptr
	  (call $realloc
	    (i32.const 0) ;; src ptr
		(i32.const 0) ;; src len
		(i32.const 1) ;; dst align
		(i32.add (local.get $len) (i32.const 8)))) ;; dst size
	(i32.store (local.get $ptr) (i32.add (local.get $ptr) (i32.const 8)))
	(i32.store (i32.add (local.get $ptr) (i32.const 4)) (local.get $len))
	(local.set $ptr (i32.add (local.get $ptr) (i32.const 8)))
	(block
	  (loop
	    (i32.ge_s (local.get $idx) (local.get $len))
		(br_if 1)
		(i32.store8
		  (i32.add (local.get $ptr) (local.get $idx))
		  (array.get $str_utf8 (local.get $str) (local.get $idx)))
		(local.set $idx (i32.add (local.get $idx) (i32.const 1)))
		(br 0)))
	(i32.sub (local.get $ptr) (i32.const 8))))
