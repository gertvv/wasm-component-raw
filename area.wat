(module
  ;; wasm-as --enable-gc --enable-reference-types area.wat

  (import "cabi" "cabi_realloc" (func $realloc (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (export "cabi_realloc" (func $realloc))

  (type $circle (struct (field f32)))
  (type $rectangle (struct (field f32 f32)))
  (type $triangle (struct (field f32 f32)))
  (rec
    (type
      $shape
      (sub (struct (field $tag i32))))
    (type
      $shapes
      (array (mut (ref $shape))))
    (type
      $f32s
      (array (mut f32)))
    (type
      $shape-circle
      (sub $shape (struct (field $tag i32) (field $item (ref $circle)))))
    (type
      $shape-rectangle
      (sub $shape (struct (field $tag i32) (field $item (ref $rectangle)))))
    (type
      $shape-triangle
      (sub $shape (struct (field $tag i32) (field $item (ref $triangle))))))

  ;; the "wasm-gc" version of "area"
  (func
    $area (export "area")
    (param $s (ref $shape)) (result f32)
    (block
      (block
        (block
          (struct.get $shape $tag (local.get $s))
          (br_table 0 1 2))
        ;; case: circle
        (return
          (call
            $area-circle
            (struct.get
              $shape-circle $item
              (ref.cast (ref $shape-circle) (local.get $s))))))
      ;; case: rectangle 
      (return
        (call
          $area-rectangle
          (struct.get
            $shape-rectangle $item
            (ref.cast (ref $shape-rectangle) (local.get $s))))))
    ;; case: triangle 
    (return
      (call
        $area-triangle
        (struct.get
          $shape-triangle $item
          (ref.cast (ref $shape-triangle) (local.get $s))))))

  (func
    $area-circle
    (param $s (ref $circle)) (result f32)
    (f32.mul
      (f32.const 3.14)
      (struct.get $circle 0 (local.get $s))))

  (func
    $area-rectangle
    (param $s (ref $rectangle)) (result f32)
    (f32.mul
      (struct.get $rectangle 0 (local.get $s))
      (struct.get $rectangle 1 (local.get $s))))

  (func
    $area-triangle
    (param $s (ref $triangle)) (result f32)
    (f32.mul
      (f32.const 0.5)
      (f32.mul
        (struct.get $triangle 0 (local.get $s))
        (struct.get $triangle 1 (local.get $s)))))

  ;; the "wasm-gc" version of "area-sum"
  (func
    $area-sum (export "area-sum")
    (param $shapes (ref $shapes))
    (result f32)
    (local $i i32)
    (local $s f32)
    (loop (result f32)
      (local.get $s)
      (i32.ge_u (local.get $i) (array.len (local.get $shapes)))
      (br_if 1)
      (call $area (array.get $shapes (local.get $shapes) (local.get $i)))
      f32.add
      local.set $s
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br 0)))

  ;; the "wasm-gc" version of "area-each"
  (func
    $area-each (export "area-each")
    (param $shapes (ref $shapes))
    (result (ref $f32s))
    (local $len i32)
    (local $i i32)
    (local $areas (ref $f32s))
    (local.set $len (array.len (local.get $shapes)))
    (local.set
      $areas
      (array.new
        $f32s
        (f32.const 0.0)
        (local.get $len)))
    (block
      (loop
        (i32.ge_u (local.get $i) (local.get $len))
        (br_if 1)
        (array.set
          $f32s (local.get $areas) (local.get $i)
          (call $area (array.get $shapes (local.get $shapes) (local.get $i))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br 0)))
    (local.get $areas))

  ;; component model version of area
  ;; the entire variant/record is flattened into parameters
  (func
    $cm_area (export "cm32p2|local:root/area|area")
    (param $tag i32) (param $f0 f32) (param $f1 f32) (result f32)
    (block
      (block
        (block
          (local.get $tag)
          (br_table 0 1 2))
        ;; case: circle
        (return
          (call
            $area
            (struct.new
              $shape-circle
              (local.get $tag)
              (struct.new $circle (local.get $f0))))))
      ;; case: rectangle 
      (return
        (call
          $area
          (struct.new
            $shape-rectangle
            (local.get $tag)
            (struct.new $rectangle (local.get $f0) (local.get $f1))))))
    ;; case: triangle 
    (return
      (call
        $area
        (struct.new
          $shape-triangle
          (local.get $tag)
          (struct.new $triangle (local.get $f0) (local.get $f1))))))

  ;; component model version of area-sum
  ;; the list is getting flattened to a pointer and a length
  ;; the list's elements must be loaded from linear memory
  (func
    $cm-area-sum (export "cm32p2|local:root/area|area-sum")
    (param $ptr i32) (param $len i32)
    (result f32)
    (call $area-sum (call $load-shapes (local.get $ptr) (local.get $len))))

  ;; component model version of area-each
  ;; the list is getting flattened to a pointer and a length
  ;; the return value is stored in linear memory and a pointer returned
  (func
    $cm-area-each (export "cm32p2|local:root/area|area-each")
    (param $ptr i32) (param $len i32)
    (result i32)
    (local $arr (ref $f32s))
    (local $i i32)
    (local $offset i32)

    ;; run the core logic
    (local.set
      $arr
      (call $area-each (call $load-shapes (local.get $ptr) (local.get $len))))

    ;; allocate memory for a pointer, a length, and the actual array
    (local.set
      $ptr
      (call
        $realloc
        (i32.const 0) (i32.const 0) (i32.const 0)
        (i32.add
          (i32.mul (i32.const 4) (local.get $len))
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
        (f32.store
          (local.get $offset)
          (array.get $f32s (local.get $arr) (local.get $i)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (local.set $offset (i32.add (local.get $offset) (i32.const 4)))
        (br 0)))

    ;; return the pointer
    (local.get $ptr))

  ;; the post function can free the memory that was allocated for the result
  ;; (I think!)
  (func
    $cm-area-each_post (export "cm32p2|local:root/area|area-each_post")
    (param $ptr i32)
    (local $len i32)
    (local.set $len (i32.load offset=4 (local.get $ptr)))
    (call
      $realloc
      (local.get $ptr)
      (i32.add (i32.mul (local.get $len) (i32.const 4)) (i32.const 8))
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
        (struct.new
          $shape-circle
          (i32.const 0)
          (struct.new $circle (f32.const 0)))
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
    (local $tag i32)
    ;; get the variant tag
    (local.set $tag (i32.load offset=0 (local.get $ptr)))
    (block
      (block
        (block
          (local.get $tag)
          (br_table 0 1 2))
        ;; circle case
        (return
          (struct.new
            $shape-circle
            (i32.const 0)
            (struct.new $circle (f32.load offset=4 (local.get $ptr))))))
      ;; rectangle case
      (return
        (struct.new
          $shape-rectangle
          (i32.const 1)
          (struct.new $rectangle (f32.load offset=4 (local.get $ptr)) (f32.load offset=8 (local.get $ptr))))))
    ;; triangle case
    (return
      (struct.new
        $shape-triangle
        (i32.const 2) 
        (struct.new $triangle (f32.load offset=4 (local.get $ptr)) (f32.load offset=8 (local.get $ptr))))))

;; module end
)
