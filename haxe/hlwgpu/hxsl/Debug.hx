package hlwgpu.hxsl;

class Debug {

	public static var VAR_IDS = #if shader_debug_var_ids true #else false #end;
	public static var TRACE = #if shader_debug_dump true #else false #end;

	// The compiler runs inside a build macro, where these cannot be macros.
	public static inline function trace(str:Dynamic) {}

	public static function varName( v : Ast.TVar, swizBits = 15 ) {
		var name = v.name;
		if( swizBits != 15 ) name += swizStr(swizBits);
		return VAR_IDS ? name+"@"+v.id : name;
	}

	static function swizStr( bits : Int ) {
		var str = ".";
		if( bits & 1 != 0 ) str += "x";
		if( bits & 2 != 0 ) str += "y";
		if( bits & 4 != 0 ) str += "z";
		if( bits & 8 != 0 ) str += "w";
		return str;
	}

	public static inline function traceDepth(str:Dynamic) {}

}