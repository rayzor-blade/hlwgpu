# Status and remaining work

## Available now

- The generated `gpu` package exposes the portable WebGPU surface and xgpu's
  native extensions through one HashLink API.
- Native releases use wgpu on Metal, D3D12, Vulkan, and Android OpenGL ES.
- Promise-returning operations use `ash.Future<T>`.
- Buffers, textures, pipelines, passes, query sets, render bundles, surfaces,
  error scopes, pipeline caches, mesh shaders, and ray-tracing descriptors are
  represented by the generated API.
- HXSL render and compute shaders compile to WGSL at Haxe compile time.
- Releases contain desktop hdlls, mobile static archives, committed Haxe
  externs, and an Ash-compatible browser side-module bundle.

Feature coverage of the shared API is tracked in
[xgpu](https://github.com/rayzor-blade/xgpu). hlwgpu should not maintain a
second operation or enum count.

## Highest-value remaining work

### Browser execution tests

The threaded `xgpu.wasm` side module builds, links, and exports the generated
API. It still needs a CI browser test that loads the bundle through Ash,
requests a real browser adapter, runs a compute pass, renders to a canvas, and
checks an asynchronous failure path.

### Host conformance

`hlwgpu.js` lets another runtime locate and load the side module, and
`IMPORTS.md` specifies the ABI. A small conformance harness should verify a
non-Ash loader against the same mailbox and Future behavior.

### Remove the legacy implementation

The old `wgpu.api`, `src/imp.rs`, native bindings, local handle table, and
`hl_native_gen` remain for compatibility during the xgpu migration. Once no
consumer needs their symbols, remove them so `xgpu.hdll` contains one object
model and one generated binding pipeline.

### Package the Future dependency

Ash already provides the Future ABI. The release story for a program launched
by upstream HashLink should make the matching `ash.Future` Haxe package and
runtime symbols explicit and easy to install.

### Runtime smoke tests

Release jobs prove that every target compiles. Add small execution tests on
available Metal, D3D12, Vulkan/lavapipe, and browser WebGPU runners so adapter
selection, resource lifetime, and async completion are exercised as well.

## Release maintenance

- Keep hlwgpu pinned to one xgpu revision for `xgpu-core`, `xgpu-backend`, and
  `xgpu-bindgen`.
- Regenerate and commit `haxe/gpu` whenever that pin changes.
- Keep the haxelib version and a versioned release tag aligned.
- Treat `crates/hlwgpu/spec/webgpu.idl` as legacy input only; xgpu's vendored
  IDL is canonical.
