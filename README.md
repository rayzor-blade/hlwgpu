<img src="./hlwgpu.png" width="250" alt="HashLink WebGPU" align="right" />

# hlwgpu

[![ci](https://github.com/rayzor-blade/hlwgpu/actions/workflows/ci.yml/badge.svg)](https://github.com/rayzor-blade/hlwgpu/actions/workflows/ci.yml)
[![release](https://github.com/rayzor-blade/hlwgpu/actions/workflows/release.yml/badge.svg)](https://github.com/rayzor-blade/hlwgpu/actions/workflows/release.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

WebGPU for HashLink: buffers, textures, WGSL shaders, render and compute
pipelines.

Each platform gets the backend it actually uses, through
[wgpu](https://wgpu.rs), the implementation Firefox, Servo and Deno use:

| | |
|---|---|
| macOS, iOS | Metal |
| Windows | D3D12, and a separate build that can also use Vulkan |
| Linux | Vulkan |
| Android | Vulkan, falling back to OpenGL ES |
| a browser | WebGPU |

You do not pick between them; `Adapter.backend` tells you which one you got.
Where a build has more than one, `WGPU_BACKEND` chooses.

GPU triangle example:

```haxe
var device = wgpu.Instance.create().adapter().device();
var queue = device.queue;

var target = device.texture(256, 256, Rgba8Unorm, RenderAttachment | CopySrc);
var view = target.view();

var corners = haxe.io.Bytes.alloc(24);
for (i => value in [-0.8, -0.8, 0.8, -0.8, 0.0, 0.8]) {
	corners.setFloat(i * 4, value);
}
var vertices = device.buffer(corners.length, Vertex | CopyDst);
queue.write(vertices, 0, corners);

var shader = device.shader("
@vertex
fn vs(@location(0) pos : vec2<f32>) -> @builtin(position) vec4<f32> {
	return vec4<f32>(pos, 0.0, 1.0);
}

@fragment
fn fs() -> @location(0) vec4<f32> {
	return vec4<f32>(0.95, 0.45, 0.1, 1.0);
}
");

var pipeline = device.pipeline()
	.shader(shader, "vs", "fs")
	.vertexBuffer().attributes(Float32x2)
	.target(Rgba8Unorm)
	.build();

var encoder = device.encoder();
encoder.beginRender(view, 0.06, 0.07, 0.09);
encoder.setPipeline(pipeline);
encoder.setVertexBuffer(0, vertices);
encoder.draw(3);
encoder.endRender();
encoder.submit(queue);
```

Read the result back with `Buffer.read` after a `copyTextureToBuffer`, or draw
into a window instead by taking the view from a `Surface` each frame.

Builders are validated as you write them. An attribute with no vertex buffer
open, or a build with nowhere to draw, will not compile.

## Three things to know

Coordinates are WebGPU's and not OpenGL's, nothing is freed for you, and no
call in this library blocks. See [docs/using.md](docs/using.md).

## Native target and Browser via wasm

On desktop, hlwgpu is one native library, `wgpu.hdll`. HashLink loads it and
calls straight into it, and there is nothing else to install.

For the browser we recommend [ash](https://ash.rayzor.tech), which builds a
WebAssembly binary from the same HashLink bytecode you already have, and hosts
it in a page.

hlwgpu's wasm tooling is designed around ash's, but it is not tied to it. A
WebAssembly module cannot reach a GPU or call JavaScript on its own, so
`wgpu.wasm` contains no GPU code at all and forwards every call out to whatever
is hosting it. In a page that is `crates/hlwgpu/js/hlwgpu.js`, which does the real work
against `navigator.gpu`: include it with a script tag and pass what it exports
to the module as imports. Nothing needs compiling.

`crates/hlwgpu/IMPORTS.md` lists every function a host has to provide, so you
can write your own instead.

## What is in here

| | |
|---|---|
| `crates/hlwgpu` | the library: `wgpu.hdll` natively, `wgpu.wasm` and `hlwgpu.js` for a page |
| `crates/hlwindow` | a small [winit](https://github.com/rust-windowing/winit) companion, so there is a window to draw into. Neither crate depends on the other |
| `crates/hl_native_gen` | writes every side of a HashLink native library from one declaration |

## Read the docs
- Convention - [docs/using.md](docs/using.md)
- Design - [docs/design.md](docs/design.md)
- WebGPU IDL - `crates/hlwgpu/spec/webgpu.idl` 

## Getting a window to draw into

hlwgpu does not create windows. Implement `wgpu.WindowSource` on whatever
provides yours, then pass it to `Surface.fromWindow`.

```haxe
typedef WindowSource = {
    function surfacePlatform() : Int;
    function surfaceHandle(which : Int) : haxe.Int64;
}
```

`surfacePlatform` says which kind of native handle you are reporting, and
`surfaceHandle` returns its fields: 0 and 1 for the window, 2 and 3 for the
display.
