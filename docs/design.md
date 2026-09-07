# Design notes

Why hlwgpu is built the way it is. For usage, see the README and
`docs/using.md`. For status, see `docs/backlog.md`.

## Why WebGPU

hlwgpu exposes WebGPU rather than a custom API.

`wgpu` is the Rust implementation of WebGPU. It resolves to Vulkan, Metal and
D3D12 underneath, so one dependency covers every native platform.

## Native and wasm

The implementation lives in `wgpu.hdll`, and the wasm build has none of it.

A `wasm32-wasip1` module cannot reach a GPU or call JavaScript, so on wasm the
primitives call out to the host:

| target | what runs the GPU |
|---|---|
| native | `wgpu.hdll` |
| browser | `js/hlwgpu.js`, over `navigator.gpu` |
| other host | whatever implements `IMPORTS.md` |

## Generated bindings

`wgpu.api` is the DSL that declares the primitives.

The same primitive must exist in five files that agree on its name and
arguments. Nothing checks that agreement at build time, so a mismatch fails at
run time or not at all. This line:

```
prim buffer_create(device: i32, size: i32, usage: i32) -> i32
```

generates:

| file | contents |
|---|---|
| `haxe/wgpu/_Native.hx` | the extern a Haxe program calls |
| `src/native.rs` | `hlp_wgpu_buffer_create`, which a VM looks up |
| `src/wasm.rs` | the same export, calling out to a host |
| `js/hlwgpu.js` | the browser implementation |
| `IMPORTS.md` | the entry another host must provide |

`build.rs` generates all of the above. Enum values come from the vendored WebGPU IDL.
Only `imp.rs` and the `js` line of each declaration are hand-written.

## Handles

Every GPU object crosses the boundary as an `i32`.

A pointer would not work on wasm, where the object lives in the host's address
space. The integer packs a kind, a generation and a slot index:

- a destroyed handle fails its generation check and raises
- a buffer passed where a texture is expected fails its kind check

`abstract Buffer(Int)` restores type safety in Haxe and compiles to a bare
`Int`.

## Resource lifetime

Callers release GPU resources by calling `destroy()`, and nothing frees them
automatically.

A garbage collector measures pressure on the Haxe heap, where a texture is one
integer however much video memory it holds. A program can therefore exhaust the
GPU while its heap still looks nearly empty and no collection is due. WebGPU
itself makes `destroy()` explicit for the same reason, so this is not a
concession to how any particular VM collects.

`destroy()` is idempotent, and bumps the slot's generation so a stale handle
raises rather than reaching whatever occupies the slot next.

## GC pointers

Rust never stores a pointer into the Haxe heap, only an integer that
identifies what it needs.

The collector does not scan the malloc heap, so a GC pointer stored only in a
Rust `Vec` is unrooted and will be collected. Asynchronous callbacks are the
obvious place this would happen, so Haxe stores them and passes an `i32`
instead.

## Blocking

No primitive blocks or suspends.

A promise in a browser settles only after the current task returns, so a
blocking primitive would deadlock. Suspending inside one requires engine
support, which would restrict the browsers hlwgpu runs on.

Primitives start work and return a `Request`. `Request.await()` polls in Haxe
and yields between checks:

```haxe
var data = buffer.read(device, 0, 1024);
```

This blocks the calling Haxe thread, but no primitive blocked.

## Descriptors

Descriptors are built by a sequence of typed calls, not passed as a packed
buffer.

A packed buffer is untyped at both ends. A layout mistake would be a silent
misread rather than a compile error, and it would require a decoder in Rust
and another in JavaScript.

```haxe
device.pipeline()
    .shader(shader, "vs", "fs")
    .vertexBuffer().attributes(Float32x2, Float32x4)
    .target(Rgba8Unorm).blend(One, One)
    .build();
```

Each call is one primitive taking scalar arguments. The builder's type changes
as it is filled in, so `attribute` requires an open vertex buffer and `build`
requires a colour target. `test/constraints.sh` compiles invalid chains to
check they are rejected.

The extra boundary crossings do not matter: pipelines are built at load time.

Bulk data still crosses as bytes — buffer contents, pixels, arrays of handles.
Structured data does not.

## Shaders

hlwgpu accepts WGSL only.

WGSL is now a shading language modern browsers accept. `wgpu` also accepts SPIR-V
and GLSL natively, but exposing those would give the native build capabilities
the browser build lacks.

No primitive may work on one target and not another. `surface_unconfigure` was
removed for this reason: it has no wgpu equivalent.

## Surfaces

hlwgpu does not create windows.

Creating one natively means owning an event loop; in a browser the canvas
belongs to the page. Instead, `wgpu.WindowSource` is a structural Haxe type
that any window provider can satisfy by reporting a platform code and four
handle fields. `crates/hlwindow` does, and neither crate references the other.

## Testing

Tests assert exact byte values rather than comparing within a tolerance.

Integer compute is bit-reproducible across GPUs. Colour channels of 0 or 1
survive unorm conversion unchanged. CI runs the tests under ash and under
upstream HashLink on lavapipe, so identical results come from both Metal and a
software rasteriser.

Tests are written so they cannot pass without the feature under test. The
depth test draws the far object last; the stencil test draws over the whole
target and is masked to a region.

## Failed lookups

A lookup that cannot resolve returns a value that is not valid, not a default.

`surface_preferred_format` returned 0 for unrecognised formats. 0 is
`Rgba8Unorm`, a real format. A surface requiring `Bgra8UnormSrgb` therefore
got a valid-looking wrong answer, and `configure` failed two calls later with
an error identifying neither the cause nor the caller. The visible symptom was
a blank window.

It returns -1 now.

## Out of scope

- **SDL**, in any form.
- **Hand-written JavaScript**, apart from a prelude containing no
  primitive-specific code.
- **Any dependency on ash.** The native library must load in stock HashLink,
  and the browser half must work in a page that does not know about ash.
- **A renderer, scene graph or material system.**
- **GL or WebGL.**

## Status

See `docs/backlog.md`.
