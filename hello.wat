(module
  (import
    "cm32p2|wasi:cli/stdout@0.2"
    "get-stdout"
    (func $get-stdout (result i32)))
  (import
    "cm32p2|wasi:io/streams@0.2"
    "[method]output-stream.blocking-write-and-flush"
    (func $print (param i32 i32 i32 i32)))
  (memory 1)
  (export "cm32p2_memory" (memory 0))
  (func $hello (export "cm32p2||hello")
    (call $print
      (call $get-stdout)
      (i32.const 16)   ;; offset to print
      (i32.const 13)   ;; length to print
      (i32.const 32))) ;; offset for result<_, stream-error>
  (data (i32.const 16) "Hello, WASI!\n"))
