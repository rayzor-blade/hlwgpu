# hlwgpu HXSL

Implement `hlwgpu.hxsl.Shader` and put the typed shader block in `SRC`.
The Haxe build macro checks and links it, then adds a `WGSL` string and layout
constants to the class. Pass `WGSL` to hlwgpu when creating the shader module.

```haxe
class TriangleShader implements hlwgpu.hxsl.Shader {
	static var SRC = {
		@input var input : { position : Vec2 };
		var output : { position : Vec4, color : Vec4 };

		function vertex() {
			output.position = vec4(input.position, 0, 1);
		}

		function fragment() {
			output.color = vec4(0.95, 0.45, 0.1, 1);
		}
	};
}
```

The compiler also supports compute shaders, imports, framework extensions,
uniform/storage layouts, texture bindings, vertex locations, render targets,
and pipeline constants.
