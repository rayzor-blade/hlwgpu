package hlwgpu.hxsl;

#if macro
import haxe.macro.Type.ClassType;

/** The extensions registered for this compilation, each for all shaders or for one family. **/
class Extensions {
	static var registered:Array<{extension:Extension, family:Null<String>}> = [];

	/**
		Adds `extension` to every shader, or with `family` to the shaders
		that implement or extend that interface or class. Call it from an
		init macro, before any shader is typed.
	**/
	public static function register(extension:Extension, ?family:String) {
		registered.push({extension: extension, family: family});
	}

	/** The extensions for the shader class `c`, in the order they were registered. **/
	public static function of(c:ClassType):Array<Extension> {
		var families = new Map<String, Bool>();
		function walk(c:ClassType) {
			families.set(c.pack.concat([c.name]).join("."), true);
			for (i in c.interfaces)
				walk(i.t.get());
			if (c.superClass != null)
				walk(c.superClass.t.get());
		}
		walk(c);
		return [for (r in registered) if (r.family == null || families.exists(r.family)) r.extension];
	}
}
#end
