# Why hlwgpu is built this way

This explains the decisions. For how to use the library, read the README and
`docs/using.md`.

## WebGPU is the API

**We expose WebGPU rather than inventing an API.**

Modern GPU programming means Vulkan, D3D12, Metal, or something that abstracts
all three. WebGPU is the only one of those with a browser implementation, and
HashLink is going to wasm.

`wgpu` is its Rust implementation. It already resolves to Vulkan, Metal and
D3D12 underneath. Firefox, Servo and Deno ship it.

So one Haxe program runs on a desktop and in a page, with one API and one set
of shaders.

## The implementation is native; wasm only forwards

**`wgpu.hdll` is the whole library. `wgpu.wasm` is empty.**

A `wasm32-wasip1` module has no GPU and no JavaScript. There is no version of
this library that reaches a device from inside one.

| where | what runs the GPU |
|---|---|
| native | `wgpu.hdll`, which holds the implementation |
| a page | `js/hlwgpu.js`, over `navigator.gpu` |
| another host | whatever implements `IMPORTS.md` |

On wasm the primitives call out and the host does the work. Everywhere else
the library does it itself.

## One declaration, every side generated

**`wgpu.api` is the only place a primitive is written down.**

A primitive otherwise appears five times: the Rust that implements it, the
Rust that forwards it, the JavaScript, the Haxe extern, and the host contract.
Keeping five copies in step by hand is how a wrong argument type gets into one
of them.

`build.rs` generates the other four. Enumerations come from the vendored
WebGPU IDL, so their values and order are the spec's.

Only `imp.rs` and the `js` line of each primitive are hand-written.

## Handles are integers

**Every GPU object crosses as an `i32`, not a pointer.**

A pointer cannot cross to a host. On wasm the object lives in the host's
address space, so an integer is the only thing that means the same on both
sides.

The integer packs a kind, a generation and a slot index. A destroyed handle
fails its generation check and raises. A buffer passed where a texture belongs
fails its kind check.

`abstract Buffer(Int)` gives Haxe the type safety back and compiles to a bare
`Int`, so this costs nothing.

## Nothing is freed for you

**Everything with a `destroy()` needs one.**

ash runs no finalizers. Upstream HashLink does, so a library that relied on
them would behave differently on the two VMs.

`wgpu.Scope` destroys everything registered with it. Debug builds can dump
what is still alive.

Explicit destruction is the model, not a gap to fill in later.

## No GC pointer lives in Rust

**Rust stores integer tickets. Haxe stores the closures.**

The collector does not scan the malloc heap. A pointer whose only holder is a
Rust `Vec` is unrooted, and the next collection takes it.

Asynchronous work is where a callback would be stashed. Instead Haxe keeps it
where the collector can see it, and passes an `i32`.

The library holds no GC pointer, so there is nothing to root.

## No primitive blocks

**Work that takes time returns a `Request`.**

In a page nothing can block. A promise settles only when the task returns.
Suspending inside a primitive would also need the engine's help, which pins
the browsers we support.

So a primitive starts the work and returns. `Request.await()` loops in Haxe,
yielding between checks.

```haxe
var data = buffer.read(device, 0, 1024);
```

That line blocks the calling Haxe thread on both targets, and no primitive
blocked to do it.

## Descriptors are built by typed calls

**A run of calls, never a packed blob.**

A blob is untyped at both ends. A layout mistake is a silent misread rather
than a compile error, and it needs a decoder in Rust and another in
JavaScript that must agree.

```haxe
device.pipeline()
    .shader(shader, "vs", "fs")
    .vertexBuffer().attributes(Float32x2, Float32x4)
    .target(Rgba8Unorm).blend(One, One)
    .build();
```

Each call is one primitive taking scalars. The builder's type changes as it
fills in, so `attribute` needs an open vertex buffer and `build` needs a
target. `test/constraints.sh` proves the compiler refuses the rest.

The crossings cost nothing, because pipelines are built at load and not per
frame.

Data still crosses as bytes: buffer contents, pixels, an array of handles.
Structure does not.

## WGSL only

**The library takes WGSL and nothing else.**

WGSL is the only shading language a browser accepts. Natively `wgpu` would
also take SPIR-V and GLSL.

Exposing those would give the native build a capability the browser build
lacks.

No primitive may work on one target and not another. That rule is why
`surface_unconfigure` was removed after it turned out to have no native
counterpart.

## Surfaces are supplied, not created

**hlwgpu does not open windows.**

Owning a window natively means owning an event loop. In a page the canvas
belongs to the embedder.

`wgpu.WindowSource` is a structural Haxe type. Anything reporting a platform
code and four handle fields satisfies it. `crates/hlwindow` happens to, and
neither crate names the other.

A surface comes from outside, which keeps this library about drawing.

## Testing

**Every test asserts exact bytes.**

Integer compute is bit-reproducible. Colours of 0 or 1 per channel survive the
unorm conversion unchanged. So there is no tolerance to tune and no golden
image to eyeball.

CI runs them under ash and under upstream HashLink on lavapipe. Identical
pixels from Metal and a software rasteriser is the evidence that they are
vendor-independent.

A test that could pass without the feature is worth nothing. The depth test
draws the far thing last. The stencil test paints only where a mark is.

## What building this found in ash

**A library is a good way to find the parts of a VM nobody has needed.**

The interpreter called natives through a hand-written table of signatures. A
combination nobody had used was a clean error, but still a wall. It grew three
arms in one afternoon once colours and viewports started crossing.

It is generated now, in ash's `ash_native_call`.

`wgpu.hdll` also asked for `hlp_alloc_bytes`, which is ash's spelling. Upstream
HashLink exports `hl_alloc_bytes`. Every test used ash, so the claim that it
loads in any HashLink was untested exactly where it was wrong.

CI builds upstream HashLink now, and the library asks for one symbol.

## A miss must not look like an answer

**A lookup that fails should say so, not return something plausible.**

`surface_preferred_format` returned 0 for a format it could not name. 0 is
`Rgba8Unorm`, a real format.

The first surface it met wanted `Bgra8UnormSrgb`. It answered "Rgba8Unorm"
with confidence, and `configure` panicked two calls later with an error naming
neither the cause nor the caller. On screen it was a blank white window.

It returns -1 now, which is not a format. Any lookup added here should fail
loudly rather than plausibly.

## What is deliberately absent

- **SDL.** Not a dependency, not a surface source, not a fallback.
- **Hand-written JavaScript**, beyond a prelude that knows no primitives.
- **Any dependency on ash.** The native library loads in stock HashLink. The
  browser half works in a page that has never heard of us.
- **A renderer, scene graph or material system.** This is the layer under
  those.
- **GL or WebGL.** The point of WebGPU is not writing that translation.

## Still open

- **The browser half has never run.** It is generated and it links, with the
  right imports and exports. Nothing has executed it in a page.
- **Queries, render bundles, explicit layouts and async pipeline creation.**
  Instrumentation and optimisation. None blocks a renderer.
- **The declaration parser should use nom or pest.** It splits strings by
  hand. That is fine for `prim` and `js` lines and will not stay fine.
- **`haxelib.json` has a version nothing sets.** The release workflow does not
  read it, so a tag and the manifest can disagree.
