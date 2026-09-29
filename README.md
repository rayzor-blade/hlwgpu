<img src="./hlwgpu.png" width="250" alt="HashLink WebGPU" align="right" />

# hlwgpu

[![ci](https://github.com/rayzor-blade/hlwgpu/actions/workflows/ci.yml/badge.svg)](https://github.com/rayzor-blade/hlwgpu/actions/workflows/ci.yml)
[![release](https://github.com/rayzor-blade/hlwgpu/actions/workflows/release.yml/badge.svg)](https://github.com/rayzor-blade/hlwgpu/actions/workflows/release.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

WebGPU for Haxe applications running on Ash and HashLink. hlwgpu packages the
shared [xgpu](https://github.com/rayzor-blade/xgpu) API as generated Haxe
externs and a native `xgpu.hdll` backed by Rust and wgpu.

## Use it

Download the release for your platform, add the unpacked directory as a
Haxelib, and keep `xgpu.hdll` beside the HashLink program. The release already
contains the generated Haxe files; application developers do not need Rust or
a binding generator.

```haxe
import gpu.GpuInstance;
import gpu.Power;

var instance = new GpuInstance();
var adapter = instance.requestAdapter(Power.HighPerformance).await();
var device = adapter.requestDevice().await();
```

Asynchronous GPU operations return `ash.Future<T>`. Handles expose `destroy()`
when their native resource can be released explicitly.

The public Haxelib class path has two namespaces:

- `gpu` is the generated xgpu API.
- `hlwgpu.hxsl` compiles typed HXSL shaders to WGSL.

Use the official [WebGPU specification](https://www.w3.org/TR/webgpu/) as the
API reference for the portable `gpu` surface. hlwgpu also exposes xgpu's
native extensions where the selected backend supports them.

hlwgpu follows the WebGPU IDL snapshot pinned by xgpu. A release therefore
identifies that API snapshot as well as the adapter binaries; hlwgpu does not
maintain a separate GPU API version.

## Typed shaders

Implement `hlwgpu.hxsl.Shader` and put the shader expression in `SRC`. The
macro checks it during Haxe compilation and emits WGSL plus its buffer and
binding layout.

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

`TriangleShader.WGSL` contains the generated shader. The macro also emits byte
offsets, bind groups, bindings, vertex locations, render targets, and pipeline
constant keys as static fields.

## Platforms

| Platform | Backend |
|---|---|
| macOS and iOS | Metal |
| Windows | D3D12, with a Vulkan release variant |
| Linux | Vulkan |
| Android | Vulkan, falling back to OpenGL ES |
| Browser Wasm | Browser WebGPU through Ash's side-module and agent harness |

Native release archives contain `xgpu.hdll` and the generated Haxe sources.
The Wasm archive contains `xgpu.wasm`, the runtime-neutral `hlwgpu.js` entry,
and the Ash browser agent modules. `hlwgpu.js` exposes the side-module URL and
accepts any runtime's dylink loader. Ash owns its browser page, loader, shared
memory, and isolation headers around the supplied agent files.

A fresh archive is published under the moving `nightly` release each day.
Versioned releases follow the WebGPU IDL snapshot pinned by xgpu.

## Contributing

xgpu owns the API model, WebIDL input, generator, and reusable backend. hlwgpu
owns the HashLink ABI adapter, release packaging, and HXSL-to-WGSL support.
Generated files under `haxe/gpu` carry a generated-file header and are checked
in so releases and source checkouts expose the same API.

`crates/hlwindow` is an internal native test helper. It is not part of the
public Haxelib or release class path.
