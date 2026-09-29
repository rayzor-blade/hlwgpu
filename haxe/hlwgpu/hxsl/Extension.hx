package hlwgpu.hxsl;

import hlwgpu.hxsl.Ast;

/** What an `output` field is. **/
enum OutputRole {
	/** The vertex stage's clip-space position. **/
	Position;
	/** The next color target. **/
	Target;
	/** The fragment's depth, `@builtin(frag_depth)`. **/
	Depth;
	/** Nothing the pipeline reads. **/
	Unused;
}

/** A call to a function a framework adds, with its arguments already printed. **/
typedef ExternCall = {
	var args:Array<String>;
	var types:Array<Type>;
	var ret:Type;
	var out:WgslContext;
}

/** A function a framework adds to HXSL: overloads checked as the built-in ones are, and how a call prints. **/
typedef ExternFunction = {
	var name:String;
	var variants:Array<FunType>;
	var print:ExternCall->String;
}

/** What an extension reaches of the printer while it prints. **/
interface WgslContext {
	/** The stage being printed: Vertex, Fragment or Main. **/
	function stage():FunctionKind;
	/** Declares a WGSL function once, before the code that calls it. **/
	function helper(code:String):Void;
	/** Adds `enable name;` to the module. **/
	function enable(name:String):Void;
	/**
		A stage built-in the entry point receives, `@builtin(attribute)`, as a
		private variable of `type` the code reads; `convert` turns the
		parameter into it.
	**/
	function input(attribute:String, parameterType:String, type:String, ?convert:String->String):String;
	/** A typed HXSL expression as WGSL. **/
	function expr(e:TExpr):String;
}

/**
	What a framework adds to HXSL for its shaders. Subclass it, override what
	the framework needs, and register it from the framework's init macro with
	`Extensions.register`, so a program adds the framework's library and
	nothing else.
**/
class Extension {
	public function new() {}

	/** Functions HXSL code can call beyond HXSL's own. **/
	public function functions():Array<ExternFunction> {
		return [];
	}

	/** HXSL each shader starts with: the framework's globals, inputs, `@:import`s. **/
	public function prelude():Null<haxe.macro.Expr> {
		return null;
	}

	/** A pass over each checked shader, before it is inlined and linked. **/
	public function transform(shader:ShaderData):ShaderData {
		return shader;
	}

	/** WGSL for one of HXSL's built-ins the printer has none of, or null. **/
	public function builtin(g:TGlobal, args:Array<TExpr>, out:WgslContext):Null<String> {
		return null;
	}

	/** The uniform block a param or global at `path` goes in; null leaves it in `params`. **/
	public function block(v:TVar, path:String):Null<String> {
		return null;
	}

	/** The bind group of a uniform block, texture or buffer, by name; null leaves it in group 0. **/
	public function group(name:String):Null<Int> {
		return null;
	}

	/** What the `output` field `name` is; null leaves `position` the position and the rest targets. **/
	public function output(name:String):Null<OutputRole> {
		return null;
	}
}
