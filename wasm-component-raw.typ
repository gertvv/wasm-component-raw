#html.elem("h1")[
  Gert van Valkenhoef
]

= WASM Component Model in Raw WASM

_May 2025_

By default, interfacing with #link("https://en.wikipedia.org/wiki/WebAssembly")[WebAssembly] (WASM) modules is not exactly plug-and-play, as it is essentially a matter of exchanging bytes via shared memory. That's (sort of) OK in the browser as #link("https://webassembly.org/getting-started/developers-guide/")[compiler tooling] exists for many languages that generates both the WASM module and JavaScript bindings for it. But if you want to embed a WASM module in a server side process, or if you want to plug two WASM modules built in different languages together, things get complicated, as you'll need to bridge the gap between their different binary interfaces yourself.

This is the problem the #link("https://component-model.bytecodealliance.org/")[WebAssembly Component Model] aims to solve. It defines an interface definition language, #link("https://component-model.bytecodealliance.org/design/wit.html")[WIT], and a #link("https://component-model.bytecodealliance.org/advanced/canonical-abi.html")[Canonical ABI] - application binary interface, so that standardized binary interfaces can be defined in a language-neutral way, allowing bindings to many languages, and interoperability between components written in different languages.

That's all great when it works, but we're in the "preview 2" stage of the component model and the tools are still maturing, or may not even exist yet. So what if I want to implement tool support for the component model, or what if I want to write a component in "raw" WASM? Let's find out!

All code for the examples below is available open source on GitHub: #link("https://github.com/gertvv/wasm-component-raw")[wasm-component-raw] and #link("https://github.com/gertvv/wasm-cabi-realloc")[wasm-cabi-realloc].

== WIT & Canonical ABI basics

A normal (pre-component model) WASM module is generally referred to as "core WASM". A WASM component is essentially a wrapper around a core WebAssembly module that includes its high-level language-neutral interface definition as well as some other metadata. All you need to interface with a component is included with the component itself. If we have a WASM component in hand, we can easily see this using e.g. `wasm-tools`:

```
$ wasm-tools component wit comp.wasm
package root:component;

world root {
  export length: func(s: string) -> u32;
}
```

Each component implements a WIT `world`, which can have a number of imports and exports defined in terms of high level types. For example the above defines a component that exports a single function to calculate a string's length. Let's have a look at the component's structure (parts left out for focus & clarity):

```
$ wasm-tools print --skeleton comp.wasm
(component
  (core module (;0;)
    (type (;0;) (func (param i32 i32 i32 i32) (result i32)))
    (type (;1;) (func (param i32 i32) (result i32)))
    (memory $mem (;0;) 1)
    (export "memory" (memory $mem))
    (export "length" (func 1))
    (export "cabi_realloc" (func $realloc))
    (func (;1;) (type 1) (param $ptr i32) (param $size i32) (result i32) ...)
    ...
  )
  ...
  (type (;0;) (func (param "s" string) (result u32)))
  (alias core export 2 "length" (core func (;2;)))
  (alias core export 2 "cabi_realloc" (core func (;3;)))
  (func (;0;) (type 0) (canon lift (core func 2) (memory 0) (realloc 3) string-encoding=utf8))
  (export (;1;) "length" (func 0))
  ...
)

```

So the component wraps a `core module (;0;)` that exports a `length` function that takes two integers as parameters and returns an integer. Further it defines a high-level function `type (;0;)` that takes a string and returns an unsigned integer, it exports a `length` function of that type, and it defines it in terms of the core function via an operation called `canon lift`.

Also, there's a few things to do with memory allocation. Why? You can only communicate with a core module by passing integers (or floats) as arguments or by exchanging bytes via linear memory. So the host system and the core module must agree on which chunks of linear memory are safe to use for this purpose. That's why the core module must export a `cabi_realloc` function, which is able to allocate or free chunks of linear memory, as well as resize existing allocations. This function is used whenever structures of variable size (lists for example) are passed into or out of the core module. If your toolchain uses linear memory anyway (and it usually would) then you'd just export the relevant allocator. If not, you'll have to suck it up and build or borrow one (#link("https://github.com/WebAssembly/component-model/issues/305")[for now...]).

This also happens for our `length(s: string) -> u32` function. Since the string could be of any length, the host calls `cabi_realloc` to allocate the required linear memory and the core function gets the offset and size of this byte buffer. This is called "lowering" - the high-level type is converted to a low-level set of integers and/or bytes. The core function looks like `length(ptr: i32, size: i32) -> i32`. The core function is "lifted" to a component model function according to the definition:

```
  (func (;0;) (type 0) (canon lift (core func 2) (memory 0) (realloc 3) string-encoding=utf8))
```

This definition refers to the core function to lift, the linear memory to use, the realloc implementation, and a string encoding. In this case it is `utf8` (the default), but `utf16` or `latin1+utf16` are also supported because important runtimes (Java, .NET, JavaScript) use them. That also means conversions between these encodings may be necessary, but if my understanding is correct, that's up to the host and not the core module's concern.

If we don't have a component at the ready but do have a WIT file we wish to implement a module for, `wasm-tools` has us covered too:

```
$ wasm-tools component embed --dummy example.wit -t
(module
  ...
  (export "cm32p2||length" (func 0))
  (export "cm32p2||length_post" (func 1))
  (export "cm32p2_memory" (memory 0))
  (export "cm32p2_realloc" (func 2))
  (export "cm32p2_initialize" (func 3))
  (func (;0;) (type 0) (param i32 i32) (result i32) ...)
  (func (;1;) (type 1) (param i32))
  (func (;2;) (type 2) (param i32 i32 i32 i32) (result i32) ...)
  (func (;3;) (type 3))
  (@custom "component-type" ...)
)
```

This tells us the signature of the `length` function, now called `cm32p2||length` according to the component model (preview 2) standard naming scheme. The signature can ofcourse be inferred from the specification but this is a useful starting point.

So now that we know how the string is passed to the core function, we can start writing some code in WebAssembly text format (WAT). To start, let's cheat by just returning the size of the byte buffer, which will be correct as long as we only pass ASCII strings:

```
(module $length_core
  (import "cabi" "cabi_realloc" (func $realloc (param i32 i32 i32 i32) (result i32)))
  (memory $mem (export "memory") 1)
  (func (export "length") (param $ptr i32) (param $size i32) (result i32)
    (local.get $size)
  )
  (export "cabi_realloc" (func $realloc))
)
```

We're importing the realloc function from... somewhere. I've built a #link("https://github.com/gertvv/wasm-cabi-realloc")[minimal `cabi_realloc` in pure WASM] which can be injected using the `--adapt` argument to `wasm-tools`. We build our component in three steps: (1) build the core module; (2) embed the WIT description; (3) convert it into a full component:

```
$ wasm-as simple.wat
$ wasm-tools component embed example.wit simple.wasm -o simple_embed.wasm
$ wasm-tools component new simple_embed.wasm --adapt cabi.wasm -o simple_component.wasm 
```

In true UNIX fashion: no news is good news. So now we've got a component that we can test-drive. This step turned out to be harder than I had anticipated. Initially I was using #link("https://github.com/rylev/wepl")[WEPL] for this but it seems to be abandoned and doesn't support the latest `wasmtime` features (such as `wasm-gc`). Luckily, `wasmtime` supports a `--invoke` syntax for components that's so bleeding edge it's coming in the #link("https://github.com/bytecodealliance/wasmtime/issues/10764")[*next* major version] (update: released in v33 on 2025-05-20). It uses a general text representation of the component model's high-level value types called #link("https://github.com/bytecodealliance/wasm-tools/tree/main/crates/wasm-wave")[WAVE] that's incredibly useful. Here we go:

```
$ wasmtime run --invoke 'length("abc")' simple_component.wasm
3
$ wasmtime run --invoke 'length("abcdef")' simple_component.wasm
6
$ wasmtime run --invoke 'length("áèø")' simple_component.wasm
6
```

So our component works as expected: it returns the correct length for ASCII-only strings but doesn't count non-ASCII characters correctly. In #link("https://en.wikipedia.org/wiki/UTF-8")[UTF-8], specific bit-patterns indicate whether a 1, 2, 3, or 4-byte sequence encodes the character. Technically, some bit patterns are invalid or can mess with the length of the sequence, but we ignore that for demonstration purposes. Don't follow my lead in production! So to get the correct length, we'll have to dig into the linear memory, like this:

```
  (func (export "length") (param $ptr i32) (param $size i32) (result i32)
    (local $len i32)
    (local $byte i32)
    ;; naive string length ignoring possible encoding errors
    (local.set $size (i32.add (local.get $ptr) (local.get $size)))
    (block
      (loop
        (i32.ge_u (local.get $ptr) (local.get $size))
        (br_if 1)
        (local.set $byte (i32.load8_u (local.get $ptr)))
        ;; check for 4-byte code point
        ...
        ;; check for 3-byte code point
        ...
        ;; check for 2-byte code point
        (block
          (i32.ne
            (i32.shr_u (local.get $byte) (i32.const 5))
            (i32.const 6))
          (br_if 0)
          (local.set $len (i32.add (local.get $len) (i32.const 1)))
          (local.set $ptr (i32.add (local.get $ptr) (i32.const 2)))
          (br 1))
        ;; check for 1-byte code point
        (block
          (i32.ne
            (i32.shr_u (local.get $byte) (i32.const 7))
            (i32.const 0))
          (br_if 0)
          (local.set $len (i32.add (local.get $len) (i32.const 1)))
          (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
          (br 1))
        ;; otherwise skip
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        (br 0)))
    (local.get $len))
```

We create locals to contain the current byte and the running total string length, loop until we reach the end, and then return the length. We read bytes from linear memory using `i32.load8_u` (load 8 bits into an i32, treating it as unsigned). Some bitwise operations tell us how many bytes the current character is encoded as. Now we get the correct result:

```
$ wasmtime run --invoke 'length("áèø")' better_component.wasm
3
```

== Flattening, lifting, lowering, loading, and storing

Within WIT definitions, structural types can be defined. To illustrate the key ones with a nonsensical example:

```wit
package local:root;

world example {
  enum encoding {
    latin1,
    utf8,
  }

  record raw-string {
    bytes: list<u8>,
    encoding: encoding,
  }

  variant text-data {
    raw(raw-string),
    str(string),
  }

  export length: func(s: text-data) -> u32;
}
```

Lists are essentially arrays and are represented by a pointer and a length, just like strings. Variants are implemented as tagged unions, i.e. as an integer tag followed by an (optional) payload; enums are a special case of this. Records consist of a number of named fields that can be of different types.

Where possible, the Canonical ABI will "flatten" argument types to a series of core type arguments to avoid dynamic allocations (typically `i32` is used, but `i64`, `f32`, and `f64` are also in play). The WIT above is implemented via a core function that takes four `i32` arguments. This breaks down as follows:

#table(columns: 3,
  table.header(
    [Byte], [Raw variant], [String variant],
  ),
  [0], [Tag (0 = raw)], [Tag (1 = str)],
  [1], [Offset of bytes], [Offset of string],
  [2], [Length of bytes], [Lenght of string],
  [3], [Encoding (0 = latin1, 1 = utf8)], [N/A],
)

A maximum of 16 "flat" arguments is used. If more are needed, a single `i32` pointer to dynamically allocated memory is passed instead. Only types of fixed size are flattened. A number of tricks are used to flatten variants with cases of different sizes, or where the payloads use different underlying types. Refer to the #link("https://github.com/WebAssembly/component-model/blob/main/design/mvp/Explainer.md#canonical-definitions")[Canonical ABI explainer] if you need to know.

The upshot of all this is that we may need to:

 1. _Lift_ types from flat arguments to our "native" representation when our exported functions are called
 2. _Lower_ our "native" representation to flat arguments when we call imported functions
 3. _Load_ bytes from linear memory and map to our "native" representation
 4. _Store_ bytes to linear memory that we derive from our "native" representation

It also means that if you only deal with things of a fixed size, you may not need `cabi_realloc` after all, if that fixed size is sufficiently small.

== Working with variants and records

To see the above in action, consider this component to scale a list of shapes (circles an/or rectangles):

```wit
package local:shapes;

interface scale {
    record circle {
        radius: f32,
    }

    record rectangle {
        width: f32,
        height: f32,
    }

    variant shape {
        circle(circle),
        rectangle(rectangle),
    }

    scale: func(shape: list<shape>, factor: f32) -> list<shape>;
}

world scaler {
    export scale;
}
```

Rather than work with the "lowered" representation directly, let's use the [WASM GC](https://github.com/WebAssembly/gc) types as an internal representation:

```wat
  (rec
    (type $shape (sub (struct)))
    (type $circle (sub $shape (struct (field f32))))
    (type $rectangle (sub $shape (struct (field f32 f32)))))
  (type $shapes (array (mut (ref $shape))))
```

This representation avoids the use of a tagged union to more clearly differentiate it from the Canonical ABI representation. Instead it uses WASM GC's support for subtyping. We won't go into detail of the implementation, but the core business logic using our interal representation has this signature:

```wat
  (func
    $scale
    (param $shapes (ref $shapes)) (param $factor f32)
    (result (ref $shapes))
    ...)
```

While the Canonical ABI version looks like this:

```wat
  (func
    $cm-scale  (export "cm32p2|local:shapes/scale|scale")
    (param $ptr i32) (param $len i32) (param $factor f32)
    (result i32)
    ...)
```

So we'll have to _lift_ the list of shapes by _loading_ its contents from linear memory, then we'll execute our business logic function, and finally we'll _lower_ the result list by storing its offset, length, and contents in linear memory. As the size of the result list isn't known statically, we'll have to allocate the memory for this. Which means we'll have to free it, at some point. This is the job of the post-return function:

```wat
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
```

We'll store the header (offset and length) and the contents of the list in a contiguous block of memory. Thus, our post function calculates the size of the allocation as 8 bytes for the header, plus 12 bytes for each shape and calls `realloc` to free this memory. The component model wrapper for our core function looks like this:

```wat
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
```

Each shape is stored in a 12-byte block. The tag is in principle stored in 1 byte but since the floats are aligned to 4 bytes, 4 bytes are used anyway. We _lift_ the shapes passed to us by loading them from linear memory:

```wat
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
```

The code to store a shape in linear memory is very similar. In each case, we loop through the list of shapes to copy it to/from our internal representation. There isn't anything too interesting going on so we'll skip the code listings. It works (if we enable the flags required for WASM GC support):

```bash
$ wasmtime run \
    -W function-references,gc \
    --invoke 'scale([circle({radius: 2.0}),
      rectangle({width: 3.0, height: 4.0})], 1.5)'  \
    scale_comp.wasm
[circle({radius: 3}), rectangle({width: 4.5, height: 6})]
```

== Hello, WASI!

WebAssembly System Interface (WASI) is a standard set of WIT worlds defined to enable system access for server-side or command-line applications. Let's say hello!

```wit
world hello {
  import wasi:cli/stdout@0.2.5;

  export hello: func();
}
```

The dummy WASM module generated for this is not even funny. But in #link("https://github.com/WebAssembly/wasi-cli/blob/main/wit/stdio.wit")[stdio.wit] we find there's a `get-stdout()` function in the `wasi:cli/stdout` interface. It returns an `output-stream` resource (defined in #link("https://github.com/WebAssembly/wasi-io/blob/main/wit/streams.wit")[streams.wit])- which is essentially an interface with an associated "self" instance - an opaque reference. It defines a convenience method that allows us to print up to 4096 bytes without any further ceremony. In short:

```wit
package wasi:io@0.2.5;
interface streams {
    resource output-stream {
        blocking-write-and-flush: func(
            contents: list<u8>
        ) -> result<_, stream-error>;
    }
}
```

In order to call `blocking-write-and-flush` (which we'll alias as `$print`), we need to _lower_ our internal string representation to the Canonical ABI - and we do this by passing a pointer and length as flat arguments.
Thus we can initialize our memory with a greeting and write it to `stdout` like so:

```wat
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
```

We import the two WASI functions we need, and export our linear memory and our `hello` function. In this case our component is responsible for allocating the memory both for the parameters and the result because the result has a predictable size. Thus, we're not required to provide a memory allocator. For simplicity's sake, we're using fixed 16-byte blocks at offsets 16 and 32 for the input string and the result. We're also ignoring the result, which we could check using `i32.load8_u` (0 = OK, 1 = error) if we wanted. To build and invoke the component:

```bash
$ wasm-as hello.wat
$ wasm-tools component embed wit/ --world hello hello.wasm -o hello_embed.wasm
$ wasm-tools component new hello_embed.wasm -o hello_comp.wasm
$ wasmtime --invoke 'hello()' hello_comp.wasm
Hello, WASI!
()
```

As you can see we say hello, and afterwards `wasmtime` outputs the return value (an empty tuple represents no return value). Perfect!

#html.elem("link", attrs: (rel: "stylesheet", href: "/css/gert.css?v2", type: "text/css"))
#html.elem("link", attrs: (rel: "stylesheet", href: "https://fonts.googleapis.com/css?family=Raleway", type: "text/css"))
