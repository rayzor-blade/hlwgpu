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

## How it is tested

`crates/hlwgpu/test/browser/GpuTest.hx` checks what the GPU hands back:
compute and rendering by exact readback, copies, queries, and the errors and
rejections a program observes through `ash.Future`. The `gpu` workflow runs it

- on stock HashLink with `ash_future.hdll` (`scripts/native_test.sh`), on
  Linux with lavapipe for Vulkan and on Windows with WARP for D3D12;
- on Ash for Metal, since stock HashLink's JIT does not run on arm64 macOS;
- in headless Chrome through Ash's page on SwiftShader
  (`scripts/browser_test.sh`).

A runner that exposes no adapter reports SKIP rather than failing.

`crates/hlwgpu/test/host` holds `xgpu.wasm` to `IMPORTS.md` with a host that
shares no code with Ash (`scripts/host_test.sh`): its own dylink loader,
HashLink carriers, Future hooks and agent worker.

Programs on upstream HashLink take `ash.Future` from Ash's `ash-future`
haxelib, whose release ZIP carries `ash_future.hdll`; see
[using hlwgpu](using.md).

## Release maintenance

`scripts/release_check.py` fails CI and a release when `xgpu-core`,
`xgpu-backend` and `xgpu-bindgen` are not pinned to one xgpu revision, or when
hlwgpu tracks WebGPU IDL of its own; xgpu's vendored IDL is the API's input.
CI fails when a build changes the committed `haxe/gpu`, so a new pin has to be
regenerated and committed. A versioned release takes its Haxelib version from
its tag, and its notes name the pinned xgpu and the IDL snapshot it carries.
