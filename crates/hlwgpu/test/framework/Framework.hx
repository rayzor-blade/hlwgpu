#if macro
/**
	A stand-in for a framework built on hlwgpu: its shaders implement
	`FrameworkShader`, and its extension gives them an `exposure` global in
	its own bind group and a `luma` function. This directory is the
	framework's haxelib, and its extraParams.hxml registers the extension.
**/
class Framework extends hlwgpu.hxsl.Extension {
	public static function register() {
		hlwgpu.hxsl.Extensions.register(new Framework(), "FrameworkShader");
	}

	override function functions():Array<hlwgpu.hxsl.Extension.ExternFunction> {
		return [{
			name: "luma",
			variants: [{args: [{name: "c", type: TVec(3, VFloat)}], ret: TFloat}],
			print: call -> {
				call.out.helper("fn framework_luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.299, 0.587, 0.114)); }");
				'framework_luma(${call.args[0]})';
			}
		}];
	}

	override function prelude():Null<haxe.macro.Expr> {
		return macro {
			@global var exposure : Float;
		};
	}

	override function block(v:hlwgpu.hxsl.Ast.TVar, path:String):Null<String> {
		return v.kind == Global ? "frame" : null;
	}

	override function group(name:String):Null<Int> {
		return name == "frame" ? 1 : null;
	}
}
#end
