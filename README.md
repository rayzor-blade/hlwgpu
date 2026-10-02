<img src="./hlwgpu.png" width="250" alt="HashLink WebGPU" align="right" />

# hlwgpu

[![ci](https://github.com/rayzor-blade/hlwgpu/actions/workflows/ci.yml/badge.svg)](https://github.com/rayzor-blade/hlwgpu/actions/workflows/ci.yml)
[![release](https://github.com/rayzor-blade/hlwgpu/actions/workflows/release.yml/badge.svg)](https://github.com/rayzor-blade/hlwgpu/actions/workflows/release.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

hlwgpu packages the shared [xgpu](https://github.com/rayzor-blade/xgpu)
API for Haxe programs on Ash and HashLink. Native programs call `xgpu.hdll`,
which uses Rust and wgpu. Browser programs load the supplied `xgpu.wasm` side
module and WebGPU agent through their runtime's Wasm harness.

## Install

Download the archive for your platform from
[GitHub Releases](https://github.com/rayzor-blade/hlwgpu/releases), unpack it,
and register that directory as the `hlwgpu` haxelib. Keep `xgpu.hdll` beside
your HashLink bytecode or executable.

```sh
haxelib dev hlwgpu /path/to/unpacked/hlwgpu
```

Add `-lib hlwgpu` to your Haxe build. The archive already contains the
generated API, so application developers do not need Rust, WebIDL tooling, or
xgpu's generator.

The generated API uses `ash.Future<T>` for asynchronous results. Ash provides
the matching runtime ABI. A different HashLink host can use the same hdll when
it provides the Ash Future ABI described by the
[ash-future package](https://github.com/rayzor-blade/ash/tree/main/haxelib/ash-future).

## First device

```haxe
import gpu.GpuInstance;
import gpu.Power;

var instance = new GpuInstance();
var adapter = instance.requestAdapter(Power.HighPerformance).await();
var device = adapter.requestDevice().await();
trace('${adapter.name()} through ${adapter.backend()}');
```

GPU work that completes later returns `ash.Future<T>`. `await()` parks an Ash
fiber; `then()` attaches a continuation. GPU resources expose `destroy()` so
applications can release driver memory at a predictable point.

The haxelib exposes two namespaces:

- `gpu` is xgpu's generated portable WebGPU API plus native extensions.
- `hlwgpu.hxsl` compiles typed HXSL shaders to WGSL during Haxe compilation.

Use the official [WebGPU specification](https://www.w3.org/TR/webgpu/) as the
reference for portable behavior. Native-only capabilities such as backend
selection, pipeline caches, mesh shaders, ray tracing, and passthrough shaders
are described by their generated classes and are available only where the
selected wgpu backend supports them.

## Typed shaders

Implement `hlwgpu.hxsl.Shader` and put the shader expression in `SRC`. The
macro checks it during Haxe compilation and emits WGSL plus its resource and
pipeline layout constants.

```haxe
class TriangleShader implements hlwgpu.hxsl.Shader {
	static var SRC = {
		@input var input:{position:Vec2};
		var output:{position:Vec4, color:Vec4};
		@param var tint:Vec4;

		function vertex() {
			output.position = vec4(input.position, 0, 1);
		}

		function fragment() {
			output.color = tint;
		}
	};
}

var shader = device.createShader(TriangleShader.WGSL);
```

`TriangleShader.WGSL` contains the generated shader. The macro also emits
uniform offsets, bind groups, bindings, vertex locations, render targets, and
pipeline constant keys as static fields.

## Releases

| Archive | Intended use |
|---|---|
| `hlwgpu-hdll-<platform>` | Desktop `xgpu.hdll`, generated Haxe API, and haxelib manifest |
| `hlwgpu-ios-*` / `hlwgpu-android-*` | Static native archive for a mobile runtime integration |
| `hlwgpu-wasm-ash` | `xgpu.wasm`, runtime-neutral loader entry, and Ash browser agent modules |
| `hlwgpu-haxe` | Generated Haxe API without a platform binary |

Native backends are Metal on Apple platforms, D3D12 on Windows, and Vulkan on
Linux. The dedicated Windows Vulkan archive enables Vulkan as another runtime
choice. Android builds include Vulkan and OpenGL ES. Browser Wasm uses the
browser's WebGPU implementation.

The moving `nightly` release is rebuilt on the daily schedule. Versioned
releases follow the WebGPU IDL snapshot pinned by xgpu.

The Wasm archive is an integration package rather than a standalone JS
library. `xgpu.wasm` is a position-independent side module that shares the
program's memory and table. See [the host contract](crates/hlwgpu/IMPORTS.md)
for the runtime imports and supplied JavaScript modules.

## More documentation

- [Using hlwgpu](docs/using.md)
- [Architecture](docs/design.md)
- [Current status and remaining work](docs/backlog.md)
- [HXSL to WGSL](haxe/hlwgpu/hxsl/README.md)

xgpu owns the API model, WebIDL input, generator, and reusable wgpu backend.
hlwgpu owns the HashLink ABI adapter, release packaging, and HXSL compiler.
[hlwindow](https://github.com/rayzor-blade/hlwindow) is
[xwindow](https://github.com/rayzor-blade/xwindow)'s adapter for HashLink and
Ash: the `window` package, loaded as `xwindow.hdll`, or as the side module
`xwindow.wasm` in a page.
