class HxslShader implements hlwgpu.hxsl.Shader {
	static var SRC = {
		@input var input : { position : Vec2 };
		var output : { position : Vec4, color : Vec4 };
		@param var tint : Vec4;

		function vertex() {
			output.position = vec4(input.position, 0, 1);
		}

		function fragment() {
			output.color = tint;
		}
	};
}

class Hxsl {
	static function main() {
		if (HxslShader.WGSL.indexOf("@vertex") < 0)
			throw "HXSL did not emit a vertex entry point";
		if (HxslShader.WGSL.indexOf("@fragment") < 0)
			throw "HXSL did not emit a fragment entry point";
		if (HxslShader.PARAMS_SIZE <= 0)
			throw "HXSL did not emit its uniform layout";
	}
}
