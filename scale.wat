(module
  ;; wasm-as --enable-gc --enable-reference-types scale.wat

  (import "cabi" "cabi_realloc" (func $realloc (param i32 i32 i32 i32) (result i32)))
  (memory (export "cm32p2_memory") 1)
  (export "cm32p2_realloc" (func $realloc))

  (rec
    (type $shape (sub (struct)))
    (type $circle (sub $shape (struct (field f32))))
    (type $rectangle (sub $shape (struct (field f32 f32)))))
  (type $shapes (array (mut (ref $shape))))

  ;; the wasm-gc version of "scale"
  (func
    $scale
    (param $shapes (ref $shapes)) (param $factor f32)
    (result (ref $shapes))
    (local $len i32)
    (local $i i32)
    (local $scaled (ref $shapes))
    (local.set $len (array.len (local.get $shapes)))
    (local.set
      $scaled
      (array.new
        $shapes
        (struct.new $circle (f32.const 0))
        (local.get $len)))
    (block
      (loop
        (i32.ge_u (local.get $i) (local.get $len))
        (br_if 1)
        (array.set
          $shapes (local.get $scaled) (local.get $i)
          (call
            $scale-one
            (array.get $shapes (local.get $shapes) (local.get $i))
            (local.get $factor)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br 0)))
    (local.get $scaled))

  (func
    $scale-one
    (param $shape (ref $shape))
    (param $factor f32)
    (result (ref $shape))
    (local $circ (ref $circle))
    (local $rect (ref $rectangle))
    (block (result (ref $shape))
      ;; circle case
      (local.set
        $circ
        (br_on_cast_fail 0 (ref $shape) (ref $circle) (local.get $shape)))
      (return
        (struct.new
          $circle
          (f32.mul (local.get $factor) (struct.get $circle 0 (local.get $circ))))))
    ;; rectangle case
    (local.set
      $rect
      (ref.cast (ref $rectangle)))
    (return
      (struct.new
        $rectangle
        (f32.mul (local.get $factor) (struct.get $rectangle 0 (local.get $rect)))
        (f32.mul (local.get $factor) (struct.get $rectangle 1 (local.get $rect))))))


  ;; component model wrapper for scale
  ;; the list is getting flattened to a pointer and a length
  ;; the return value is stored in linear memory and a pointer returned
  (func
    (export "cm32p2|local:shapes/scale|scale")
    (param $ptr i32) (param $len i32) (param $factor f32)
    (result i32)
    (local $arr (ref $shapes))
    (local.set
      $arr
      (call $load-shapes (local.get $ptr) (local.get $len)))
    (local.set
      $arr
      (call $scale (local.get $arr) (local.get $factor)))
    (call $store-shapes (local.get $arr)))

  (func
    $store-shapes
    (param $arr (ref $shapes))
    (result i32)
    (local $ptr i32)
    (local $offset i32)
    (local $len i32)
    (local $i i32)

    ;; allocate memory for a pointer, a length, and the actual array
    (local.set $len (array.len (local.get $arr)))
    (local.set
      $ptr
      (call
        $realloc
        (i32.const 0) (i32.const 0) (i32.const 4)
        (i32.add
          (i32.mul (i32.const 12) (local.get $len))
          (i32.const 8))))
    ;; trap if we can't allocate
    (block
      (i32.ne (i32.const 0) (local.get $ptr))
      (br_if 0)
      (unreachable))

    ;; store the pointer & length
    (local.set $offset (i32.add (local.get $ptr) (i32.const 8)))
    (i32.store offset=0 (local.get $ptr) (local.get $offset))
    (i32.store offset=4 (local.get $ptr) (local.get $len))

    ;; loop to store the actual elements
    (block
      (loop
        (i32.ge_u (local.get $i) (local.get $len))
        (br_if 1)
        (call
          $store-shape
          (local.get $offset)
          (array.get $shapes (local.get $arr) (local.get $i)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (local.set $offset (i32.add (local.get $offset) (i32.const 12)))
        (br 0)))

    ;; return the pointer
    (local.get $ptr))
    

  ;; the post function can free the memory that was allocated for the result
  (func
    (export "cm32p2|local:shapes/scale|scale_post")
    (param $ptr i32)
    (local $len i32)
    (local.set $len (i32.load offset=4 (local.get $ptr)))
    (call
      $realloc
      (local.get $ptr)
      (i32.add (i32.mul (local.get $len) (i32.const 12)) (i32.const 8))
      (i32.const 0)
      (i32.const 0))
    (drop))

  ;; load an array of shapes from linear memory
  (func
    $load-shapes
    (param $ptr i32) (param $len i32)
    (result (ref $shapes))
    (local $i i32)
    (local $arr (ref $shapes))
    ;; initialize the array to a default value
    (local.set
      $arr
      (array.new
        $shapes
        (struct.new $circle (f32.const 0))
        (local.get $len)))
    ;; loop to load the actual elements
    (block
      (loop
        (i32.ge_u (local.get $i) (local.get $len))
        (br_if 1)
        (array.set
          $shapes (local.get $arr) (local.get $i)
          (call
            $load-shape
            (i32.add
              (local.get $ptr)
              (i32.mul (local.get $i) (i32.const 12)))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br 0)))
    (local.get $arr))

  ;; load a shape from linear memory
  (func
    $load-shape
    (param $ptr i32)
    (result (ref $shape))
    ;; get the variant tag
    (block
      (block
        (i32.load offset=0 (local.get $ptr))
        (br_table 0 1))
      ;; circle case
      (return
        (struct.new
          $circle
          (f32.load offset=4 (local.get $ptr)))))
    ;; rectangle case
    (return
      (struct.new
        $rectangle
        (f32.load offset=4 (local.get $ptr))
        (f32.load offset=8 (local.get $ptr)))))

  ;; store a shape in linear memory
  (func
    $store-shape
    (param $ptr i32)
    (param $shape (ref $shape))
    (local $circ (ref $circle))
    (local $rect (ref $rectangle))
    (block (result (ref $shape))
      ;; circle case
      (local.set
        $circ
        (br_on_cast_fail 0 (ref $shape) (ref $circle) (local.get $shape)))
        (i32.store offset=0 (local.get $ptr) (i32.const 0))
        (f32.store
          offset=4 (local.get $ptr)
          (struct.get $circle 0 (local.get $circ)))
        (br 1))
    ;; rectangle case
    (local.set
      $rect
      (ref.cast (ref $rectangle)))
    (i32.store offset=0 (local.get $ptr) (i32.const 1))
    (f32.store
      offset=4 (local.get $ptr)
      (struct.get $rectangle 0 (local.get $rect)))
    (f32.store
      offset=8 (local.get $ptr)
      (struct.get $rectangle 1 (local.get $rect))))

;; module end
)
