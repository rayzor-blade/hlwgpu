package hlwgpu.hxsl;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

class Build {
	/** The source of the shader class `path`, for `@:import` and `@:extends`. **/
	static function source(path:String):Ast.Expr {
		switch (Context.follow(Context.getType(path))) {
			case TInst(c, _):
				for (m in c.get().meta.get())
					if (m.name == ":src")
						return new MacroParser().parseExpr(m.params[0]);
			default:
		}
		throw '$path is not an HXSL shader';
	}

	public static function shader():Array<Field> {
		var fields = Context.getBuildFields();
		var src = Lambda.find(fields, f -> f.name == "SRC");
		// A framework's shader interface or base class has no source of its own.
		if (src == null || Context.getLocalClass().get().isInterface)
			return fields;
		var expr = switch (src.kind) {
			case FVar(_, e) if (e != null): e;
			default: Context.error("SRC is the shader's source", src.pos);
		}
		var local = Context.getLocalClass().get();
		local.meta.add(":src", [expr], expr.pos);
		fields.remove(src);
		var exts = Extensions.of(local);
		var preludes = [for (x in exts) x.prelude()].filter(p -> p != null);
		var full = preludes.length == 0 ? expr : {expr: EBlock(preludes.concat([expr])), pos: expr.pos};
		try {
			var compiled = Compiler.compile(local.name, full, source, (msg, pos) -> Context.warning(msg, pos), exts);
			// Only helpers: a module other shaders import, with nothing to print.
			if (compiled == null)
				return fields;
			var wgsl = compiled.wgsl;
			var pos = expr.pos;
			function constant(name:String, value:Expr, doc:String)
				fields.push({
					name: name,
					doc: doc,
					// Final rather than inline: other languages read the field at run time.
					access: [APublic, AStatic, AFinal],
					kind: FVar(null, value),
					pos: pos
				});
			constant("WGSL", macro $v{wgsl}, "The shader as WGSL, for `device.createShader`.");
			var l = compiled.layout;
			for (b in l.blocks) {
				var B = b.name.toUpperCase();
				constant('${B}_SIZE', macro $v{b.size}, 'Bytes of the `${b.name}` uniform buffer.');
				constant('${B}_GROUP', macro $v{b.group}, 'Bind group of the `${b.name}` uniform buffer.');
				constant('${B}_BINDING', macro $v{b.binding}, 'Binding of the `${b.name}` uniform buffer.');
				for (m in b.members)
					constant('${B}_${m.name}', macro $v{m.offset}, 'Byte offset of `${m.name}` in the `${b.name}` uniform buffer.');
			}
			for (t in l.textures) {
				constant('TEXTURE_${t.name}', macro $v{t.binding}, 'Binding of `${t.name}`; its sampler is the next binding.');
				constant('TEXTURE_${t.name}_GROUP', macro $v{t.group}, 'Bind group of `${t.name}` and its sampler.');
			}
			for (b in l.buffers) {
				constant('BUFFER_${b.name}', macro $v{b.binding}, 'Binding of `${b.name}`.');
				constant('BUFFER_${b.name}_GROUP', macro $v{b.group}, 'Bind group of `${b.name}`.');
			}
			for (i in l.inputs)
				constant('INPUT_${i.name}', macro $v{i.location}, 'Vertex attribute location of `${i.name}`.');
			for (t in l.targets)
				constant('TARGET_${t.name}', macro $v{t.location}, 'Color target of `${t.name}`.');
			for (o in l.overrides)
				constant('CONST_${o.name}', macro $v{o.key}, 'Pipeline constant key of `@const ${o.name}`.');
		} catch (e:Ast.Error) {
			Context.error(e.msg, e.pos);
		}
		return fields;
	}
}
#end
