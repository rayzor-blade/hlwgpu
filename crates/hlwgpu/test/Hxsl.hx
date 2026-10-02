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

/** A framework's shader: its `exposure` global and `luma` come from the framework's extension. **/
class Exposed implements FrameworkShader {
	static var SRC = {
		var output : { position : Vec4, color : Vec4 };
		@param var tint : Vec4;

		function vertex() {
			output.position = vec4(0, 0, 0, 1);
		}

		function fragment() {
			output.color = vec4(vec3(luma(tint.rgb) * exposure), 1);
		}
	};
}

/**
	Compiled with the `hxsl-framework` haxelib in `framework/`, whose
	extraParams.hxml registers its extension. With `HXSL_WGSL_DIR` set, every
	shader's WGSL is written there for a validator.
**/
class Hxsl {
	static function check(ok:Bool, message:String) {
		if (!ok)
			throw message;
	}

	static function main() {
		check(HxslShader.WGSL.indexOf("@vertex") >= 0, "HXSL did not emit a vertex entry point");
		check(HxslShader.WGSL.indexOf("@fragment") >= 0, "HXSL did not emit a fragment entry point");
		check(HxslShader.PARAMS_SIZE > 0, "HXSL did not emit its uniform layout");

		// The extension's global is its own block, in its own group.
		check(Exposed.FRAME_GROUP == 1, 'the frame block is in group ${Exposed.FRAME_GROUP}, not 1');
		check(Exposed.FRAME_exposure == 0, 'exposure is at ${Exposed.FRAME_exposure} in the frame block, not 0');
		check(Exposed.FRAME_SIZE >= 4, 'the frame block is ${Exposed.FRAME_SIZE} bytes');
		check(Exposed.PARAMS_GROUP == 0, 'the shader\'s own params moved to group ${Exposed.PARAMS_GROUP}');
		check(Exposed.WGSL.indexOf('@group(1) @binding(${Exposed.FRAME_BINDING})') >= 0, "the frame block is not bound at group 1");
		// The extern function prints its helper once and calls it.
		check(Exposed.WGSL.split("fn framework_luma(").length == 2, "luma's helper is not printed exactly once");
		check(Exposed.WGSL.indexOf("framework_luma(") != Exposed.WGSL.lastIndexOf("framework_luma("), "luma is never called");

		// A shader outside the family is untouched.
		check(HxslShader.WGSL.indexOf("framework_luma") < 0, "luma reached a shader outside the family");
		check(HxslShader.WGSL.indexOf("exposure") < 0, "exposure reached a shader outside the family");
		check(Reflect.field(HxslShader, "FRAME_GROUP") == null, "the frame block reached a shader outside the family");

		var dir = Sys.getEnv("HXSL_WGSL_DIR");
		if (dir != null) {
			sys.FileSystem.createDirectory(dir);
			sys.io.File.saveContent('$dir/HxslShader.wgsl', HxslShader.WGSL);
			sys.io.File.saveContent('$dir/Exposed.wgsl', Exposed.WGSL);
		}
	}
}
