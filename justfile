area: build-dir
  wasm-as \
    --enable-gc --enable-reference-types \
    --output build/area.core.wasm area.wat
  wasm-tools component embed wit/ \
    --world calculator \
    --output build/area.embed.wasm \
    build/area.core.wasm
  wasm-tools component new \
    --adapt ../wasm-cabi-realloc/cabi.wasm \
    --output build/area.comp.wasm \
    build/area.embed.wasm
  wasmtime run \
    -W function-references,gc \
    --invoke 'area-each([circle({radius: 1.0}), rectangle({width: 1.0, height: 1.0})])' \
    build/area.comp.wasm

scale: build-dir
  wasm-as \
    --enable-gc --enable-reference-types \
    --output build/scale.core.wasm scale.wat
  wasm-tools component embed wit/ \
    --world scaler \
    --output build/scale.embed.wasm \
    build/scale.core.wasm
  wasm-tools component new \
    --adapt ../wasm-cabi-realloc/cabi.wasm \
    --output build/scale.comp.wasm \
    build/scale.embed.wasm
  wasmtime run \
    -W function-references,gc,component-model \
    --invoke 'scale([circle({radius: 1.0}), rectangle({width: 1.0, height: 1.0})], 1.5)' \
    build/scale.comp.wasm

hello: build-dir
  wasm-as --output build/hello.core.wasm hello.wat
  wasm-tools component embed wit/ \
    --world hello \
    --output build/hello.embed.wasm \
    build/hello.core.wasm
  wasm-tools component new \
    --adapt ../wasm-cabi-realloc/cabi.wasm \
    --output build/hello.comp.wasm \
    build/hello.embed.wasm
  wasmtime --invoke 'hello()' build/hello.comp.wasm

reverse: build-dir
  wasm-as \
    --enable-gc --enable-reference-types \
    --output build/reverse.core.wasm reverse.wat
  wasm-tools component embed wit/ \
    --world rev \
    --output build/reverse.embed.wasm \
    build/reverse.core.wasm
  wasm-tools component new \
    --adapt ../wasm-cabi-realloc/cabi.wasm \
    --output build/reverse.comp.wasm \
    build/reverse.embed.wasm
  wasmtime run \
    -W function-references,gc,component-model \
    --invoke 'reverse-string("!dlroW ,olleH")' \
    build/reverse.comp.wasm

reverse-upper: build-dir reverse
  jco componentize revup.js \
    --wit wit/ --world-name revup \
    --out build/revup.part.wasm \
    --disable all
  wac plug \
    --plug build/reverse.comp.wasm \
    build/revup.part.wasm \
    -o build/revup.comp.wasm
  wasmtime run \
    -W function-references,gc,component-model \
    --invoke 'reverse-and-uppercase("!dlroW ,olleH")' \
    build/revup.comp.wasm

build-dir:
  mkdir -p ./build/

article:
  typst compile --format html --features html wasm-component-raw.typ
  cp wasm-component-raw.html ../gertvv.nl/posts/wasm-component-raw.html
