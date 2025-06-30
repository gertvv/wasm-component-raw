WASM Component Model in Raw WASM
===

This repository contains the source code for [a post](https://gertvv.nl/posts/wasm-component-raw.html) explaining how the WASM Component Moel's (preview 2) Canonical ABI works using examples implemented in raw WebAssembly Text.

Addendum
---

When I originally wrote the post, I wanted to demonstrate composition of components, but the [tools weren't quite ready](https://github.com/bytecodealliance/wac/issues/158). Now that they are, I've added an example based on `jco`'s [string-reverse-upper](https://github.com/bytecodealliance/jco/tree/main/examples/components/string-reverse-upper) example.

The WIT worlds are defined in `wit/reverse.wit`. The "inner" component to reverse a string is implemented in pure WASM in `reverse.wat` (it works for ASCII only). The "outer" component calls the "inner" component to reverse a string and then converts it to uppercase, as implemented in `revup.js`. The two are composed using [WAC](https://github.com/bytecodealliance/wac) and run as follows:

```
$ wac plug --output build/revup.comp.wasm \
    --plug build/reverse.comp.wasm build/revup.part.wasm
$ wasmtime run -W function-references,gc,component-model \
    --invoke 'reverse-and-uppercase("!dlroW ,olleH")' \
    build/revup.comp.wasm
"HELLO, WORLD!" 
```

For further detail see the `reverse` and `reverse-upper` targets in the `justfile`.
