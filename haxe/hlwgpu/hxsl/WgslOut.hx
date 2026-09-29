package hlwgpu.hxsl;

import hlwgpu.hxsl.Ast;
import hlwgpu.hxsl.Extension;

using hlwgpu.hxsl.Ast;

/** Where a program finds what the WGSL declares. **/
typedef WgslLayout = {
	/**
		Each uniform block: its bind group, binding and size in bytes, and
		each member's byte offset, by its path with `_` for `.`.
	**/
	var blocks:Array<{name:String, group:Int, binding:Int, size:Int, members:Array<{name:String, offset:Int}>}>;
	/** Each texture's group and binding; its sampler is the next binding. **/
	var textures:Array<{name:String, group:Int, binding:Int}>;
	/** Each buffer's or storage texture's group and binding. **/
	var buffers:Array<{name:String, group:Int, binding:Int}>;
	/** Each vertex input's location, in declaration order. **/
	var inputs:Array<{name:String, location:Int}>;
	/** Each fragment output's color target, in `output`'s declaration order. **/
	var targets:Array<{name:String, location:Int}>;
	/** Each `@const`'s pipeline-constant key, the name of its WGSL override. **/
	var overrides:Array<{name:String, key:String}>;
}

/**
	Prints linked HXSL stages as one WGSL module: `vertex` and `fragment`
	entry points, or `main` for a compute shader.

	Params and globals sit in uniform blocks, `params` unless an extension
	chooses another, each a struct laid out by WGSL's uniform rules. In each
	bind group the blocks take the first bindings, then textures (each with
	its sampler after it), then buffers and storage textures, in declaration
	order. Every variable a stage keeps, locals included, is a private
	module variable, as Heaps' GLSL output keeps its locals global: a block
	used as a value then becomes a function that reads them.
**/
class WgslOut implements WgslContext {
	/** WGSL's keywords and reserved words, its predeclared types and functions, and this printer's own names. **/
	static var WORDS = "
		alias break case const const_assert continue continuing default diagnostic discard else enable false fn for if let loop
		override requires return struct switch true var while
		NULL Self abstract active alignas alignof as asm asm_fragment async attribute auto await become binding_array cast catch
		class co_await co_return co_yield coherent column_major common compile compile_fragment concept const_cast consteval
		constexpr constinit crate debugger decltype delete demote demote_to_helper do dynamic_cast enum explicit export extends
		extern external fallthrough filter final finally friend from fxgroup get goto groupshared highp impl implements import
		inline instanceof interface layout lowp macro macro_rules match mediump meta mod module move mut mutable namespace new nil
		noexcept noinline nointerpolation noperspective null nullptr of operator package packoffset partition pass patch
		pixelfragment precise precision premerge priv protected pub public readonly ref regardless register reinterpret_cast
		require resource restrict self set shared sizeof smooth snorm static static_assert static_cast std subroutine super
		target template this thread_local throw trait try type typedef typeid typename typeof union unless unorm unsafe unsized
		use using varying virtual volatile wgsl where with writeonly yield
		bool f16 f32 i32 u32 vec2 vec3 vec4 mat2x2 mat2x3 mat2x4 mat3x2 mat3x3 mat3x4 mat4x2 mat4x3 mat4x4 array atomic ptr sampler
		sampler_comparison texture_1d texture_2d texture_2d_array texture_3d texture_cube texture_cube_array
		texture_storage_1d texture_storage_2d texture_storage_2d_array texture_storage_3d
		sin cos tan asin acos atan atan2 pow exp log exp2 log2 sqrt inverseSqrt abs sign floor ceil fract min max clamp mix step
		smoothstep length distance dot cross normalize reflect radians degrees saturate select all any round transpose bitcast
		textureSample textureSampleLevel textureLoad textureStore textureDimensions textureNumLayers dpdx dpdy fwidth
		unpack4x8snorm unpack4x8unorm firstTrailingBit firstLeadingBit countOneBits workgroupBarrier
		vin vout fin fout input vertex fragment main
	";
	static var RESERVED = [for (w in new EReg("\\s+", "g").split(WORDS)) if (w != "") w => true];

	var names = new Map<Int, String>();
	var taken = new Map<String, Bool>();
	var decls:Array<String> = [];
	var functions:Array<String> = [];
	var privates:Array<String> = [];
	var privateIds = new Map<Int, Bool>();
	var valueCount = 0;

	var order:Map<String, Int>;
	/** The paths declared `@const`; evaluation drops the qualifier from what it copies. **/
	var consts = new Map<String, Bool>();
	var stageKind:FunctionKind;
	var compute:Bool;
	/** In an entry point's body, where `return` returns the stage's output. **/
	var inEntry:Bool;
	var workgroup = [1, 1, 1];

	var exts:Array<Extension>;
	var externs = new Map<String, ExternFunction>();
	/** Each `output` field's role, by the field's name. **/
	var roles:Map<String, OutputRole>;
	var enables:Array<String> = [];
	/** The built-ins each stage reads, by attribute: the private variable, parameter type and conversion. **/
	var stageInputs = new Map<String, {name:String, parameterType:String, convert:String->String, stages:Map<String, Bool>}>();

	var params:Array<TVar> = [];
	/** A value param's access, `params.tint`, by id. **/
	var paramFields = new Map<Int, String>();
	var textures = new Map<Int, {texture:String, sampler:String, type:Type}>();
	var bindings = new Map<Int, String>();
	var overrides = new Map<Int, String>();
	var inputs:Array<TVar> = [];
	var varyings:Array<TVar> = [];
	var targets:Array<TVar> = [];
	var fields = new Map<Int, String>();
	var positionField:String;

	public var layout(default, null):WgslLayout;

	/** The linker's path for each variable it made, by id. **/
	var paths:Map<Int, String>;

	/**
		`declared` is the shader as written, whose order fixes locations and
		offsets; `paths` holds the linked variables' paths.
	**/
	public function new(declared:Array<TVar>, paths:Map<Int, String>, exts:Array<Extension>, roles:Map<String, OutputRole>) {
		this.exts = exts;
		this.roles = roles;
		for (x in exts)
			for (f in x.functions())
				externs.set(f.name, f);
		this.paths = new Map();
		order = new Map();
		var index = 0;
		function walk(v:TVar) {
			order.set(fullPath(v), index++);
			if (v.isConst())
				consts.set(fullPath(v), true);
			switch (v.type) {
				case TStruct(vl):
					for (c in vl)
						walk(c);
				default:
			}
		}
		for (v in declared)
			walk(v);
		this.paths = paths;
		layout = {
			blocks: [],
			textures: [],
			buffers: [],
			inputs: [],
			targets: [],
			overrides: []
		};
	}

	static function error(msg:String, p:Position):Dynamic {
		throw new Error(msg, p);
		return null;
	}

	/** A module-scope name, unique and not WGSL's. **/
	function fresh(base:String):String {
		return unique(base, taken);
	}

	/** A name unique among `used`; struct members have their own. **/
	static function unique(base:String, used:Map<String, Bool>):String {
		var n = ~/[^A-Za-z0-9_]/g.replace(base, "_");
		if (StringTools.startsWith(n, "__"))
			n = "v" + n;
		if (n == "_" || RESERVED.exists(n))
			n = n + "_";
		if (used.exists(n)) {
			var k = 2;
			while (used.exists(n + "_" + k))
				k++;
			n = n + "_" + k;
		}
		used.set(n, true);
		return n;
	}

	/** `v`'s path from its outermost struct, `input.position`. **/
	function fullPath(v:TVar):String {
		var linked = paths.get(v.id);
		if (linked != null)
			return linked;
		var n = v.getName();
		var p = v.parent;
		while (p != null) {
			n = p.getName() + "." + n;
			p = p.parent;
		}
		return n;
	}

	function rank(v:TVar):Int {
		var r = order.get(fullPath(v));
		return r == null ? 0x7FFFFFFF : r;
	}

	// -- types -----------------------------------------------------------------------

	function vecType(t:VecType):String {
		return switch (t) {
			case VFloat: "f32";
			case VInt: "i32";
			case VBool: "bool";
		}
	}

	function type(t:Type, p:Position):String {
		return switch (t) {
			case TInt: "i32";
			case TFloat: "f32";
			case TBool: "bool";
			case TVec(n, k): 'vec$n<${vecType(k)}>';
			case TMat2: "mat2x2<f32>";
			case TMat3: "mat3x3<f32>";
			case TMat4: "mat4x4<f32>";
			case TMat3x4: "mat3x4<f32>";
			case TArray(e, SConst(0)): 'array<${type(e, p)}>';
			case TArray(e, SConst(n)): 'array<${type(e, p)}, $n>';
			case TArray(_, SVar(v)): error('an array sized by ${v.name} has no fixed size in WGSL', p);
			default: error('${t.toString()} has no WGSL type here', p);
		}
	}

	function textureType(t:Type, p:Position):String {
		return switch (t) {
			case TSampler(T1D, false): "texture_1d<f32>";
			case TSampler(T2D, false): "texture_2d<f32>";
			case TSampler(T2D, true): "texture_2d_array<f32>";
			case TSampler(T3D, false): "texture_3d<f32>";
			case TSampler(TCube, false): "texture_cube<f32>";
			case TSampler(TCube, true): "texture_cube_array<f32>";
			case TRWTexture(dim, arr, chans):
				var format = switch (chans) {
					case 1: "r32float";
					case 2: "rg32float";
					default: "rgba32float";
				}
				var d = switch (dim) {
					case T1D: "1d";
					case T2D: arr ? "2d_array" : "2d";
					case T3D: "3d";
					case TCube: error("a storage texture cannot be a cube", p);
				}
				'texture_storage_$d<$format, write>';
			default: error('${t.toString()} is not a texture', p);
		}
	}

	/** WGSL's alignment and size in the uniform address space. **/
	function uniformLayout(t:Type, name:String, p:Position):{align:Int, size:Int} {
		return switch (t) {
			case TInt, TFloat, TBool: {align: 4, size: 4};
			case TVec(2, _): {align: 8, size: 8};
			case TVec(3, _): {align: 16, size: 12};
			case TVec(4, _): {align: 16, size: 16};
			case TMat2: {align: 8, size: 16};
			case TMat3, TMat3x4: {align: 16, size: 48};
			case TMat4: {align: 16, size: 64};
			case TArray(e, SConst(n)) if (n > 0):
				var el = uniformLayout(e, name, p);
				var stride = roundUp(el.size, el.align);
				if (stride % 16 != 0)
					error('$name: an array in params needs elements of 16 bytes, as WGSL requires; ${e.toString()} is $stride', p);
				{align: 16, size: stride * n};
			default: error('$name: ${t.toString()} cannot be a param', p);
		}
	}

	static inline function roundUp(n:Int, to:Int):Int {
		return Std.int((n + to - 1) / to) * to;
	}

	// -- declarations ------------------------------------------------------------------

	function leaves(v:TVar, f:TVar->Void) {
		switch (v.type) {
			case TStruct(vl):
				for (c in vl)
					leaves(c, f);
			default:
				f(v);
		}
	}

	function path(v:TVar):String {
		return StringTools.replace(fullPath(v), ".", "_");
	}

	function collect(stages:Array<ShaderData>) {
		var seen = new Map<Int, Bool>();
		var vertexVars:Array<TVar> = [];
		var fragmentVars:Array<TVar> = [];
		for (s in stages) {
			var isFragment = s.funs[0].kind == Fragment;
			for (top in s.vars)
				leaves(top, v -> {
					switch (v.kind) {
						case Var:
							if (!seen.exists(v.id)) {
								seen.set(v.id, true);
								varyings.push(v);
							}
						case Output:
							if (isFragment) targets.push(v) else if (!compute) positionField = null;
							if (!isFragment) fields.set(v.id, "position");
						case Input:
							if (!seen.exists(v.id)) {
								seen.set(v.id, true);
								inputs.push(v);
							}
						case Param, Global:
							if (seen.exists(v.id))
								return;
							seen.set(v.id, true);
							if (v.isConst() || consts.exists(fullPath(v))) {
								var n = fresh(path(v));
								overrides.set(v.id, n);
								decls.push('override $n: ${type(v.type, null)};');
								layout.overrides.push({name: path(v), key: n});
							} else if (v.type.match(TSampler(_))) {
								textures.set(v.id, null);
								params.push(v);
							} else if (v.type.match(TBuffer(_) | TRWTexture(_) | TArray(TRWTexture(_), _))) {
								bindings.set(v.id, null);
								params.push(v);
							} else if (v.type.match(TArray(TSampler(_), _))) {
								error('${v.name}: arrays of textures need binding arrays, which this HXSL does not print yet', null);
							} else {
								params.push(v);
							}
						case Local:
							addPrivate(v);
						case Function:
					}
				});
		}
	}

	function addPrivate(v:TVar) {
		if (privateIds.exists(v.id))
			return;
		privateIds.set(v.id, true);
		var n = fresh(v.name);
		names.set(v.id, n);
		privates.push('var<private> $n: ${type(v.type, null)};');
	}

	function extensionGroup(name:String):Int {
		for (x in exts) {
			var g = x.group(name);
			if (g != null)
				return g;
		}
		return 0;
	}

	function declare() {
		params.sort((a, b) -> rank(a) - rank(b));
		// Bindings count up within each group: blocks, textures, then buffers.
		var next = new Map<Int, Int>();
		function bind(name:String):{group:Int, binding:Int} {
			var group = extensionGroup(name);
			var binding = next.exists(group) ? next.get(group) : 0;
			next.set(group, binding + 1);
			return {group: group, binding: binding};
		}

		var blockOrder:Array<String> = [];
		var members = new Map<String, Array<TVar>>();
		for (v in params) {
			if (textures.exists(v.id) || bindings.exists(v.id))
				continue;
			var block = "params";
			for (x in exts) {
				var b = x.block(v, fullPath(v));
				if (b != null) {
					block = b;
					break;
				}
			}
			if (!members.exists(block)) {
				members.set(block, []);
				blockOrder.push(block);
			}
			members.get(block).push(v);
		}
		for (block in blockOrder) {
			var variable = fresh(block);
			var structName = fresh(block.charAt(0).toUpperCase() + block.substr(1) + "Block");
			var offset = 0;
			var align = 16;
			var body = [];
			var used = new Map();
			var offsets = [];
			for (v in members.get(block)) {
				var n = unique(path(v), used);
				paramFields.set(v.id, '$variable.$n');
				var l = uniformLayout(v.type, fullPath(v), null);
				offset = roundUp(offset, l.align);
				offsets.push({name: path(v), offset: offset});
				// A uniform holds no bool; it is a u32, read as `!= 0u`.
				body.push('\t$n: ${v.type == TBool ? "u32" : type(v.type, null)},');
				offset += l.size;
				if (l.align > align)
					align = l.align;
			}
			var at = bind(block);
			var size = roundUp(offset, align);
			layout.blocks.push({name: block, group: at.group, binding: at.binding, size: size, members: offsets});
			decls.push('struct $structName {\n${body.join("\n")}\n};');
			decls.push('@group(${at.group}) @binding(${at.binding}) var<uniform> $variable: $structName;');
		}
		for (v in params) {
			if (textures.exists(v.id)) {
				var t = fresh(path(v));
				var s = fresh(t + "_sampler");
				textures.set(v.id, {texture: t, sampler: s, type: v.type});
				var at = bind(path(v));
				layout.textures.push({name: path(v), group: at.group, binding: at.binding});
				decls.push('@group(${at.group}) @binding(${at.binding}) var $t: ${textureType(v.type, null)};');
				next.set(at.group, at.binding + 2);
				decls.push('@group(${at.group}) @binding(${at.binding + 1}) var $s: sampler;');
			}
		}
		for (v in params) {
			if (bindings.exists(v.id)) {
				var n = fresh(path(v));
				bindings.set(v.id, n);
				var at = bind(path(v));
				layout.buffers.push({name: path(v), group: at.group, binding: at.binding});
				var decl = switch (v.type) {
					case TBuffer(t, size, kind):
						var el = type(t, null);
						var array = switch (size) {
							case SConst(n) if (n > 0): 'array<$el, $n>';
							default: 'array<$el>';
						}
						switch (kind) {
							case Uniform, Partial: 'var<uniform> $n: $array';
							case Storage, StoragePartial: 'var<storage, read> $n: $array';
							case RW, RWPartial: 'var<storage, read_write> $n: $array';
						}
					case TRWTexture(_):
						'var $n: ${textureType(v.type, null)}';
					default: error('${v.name}: arrays of storage textures need binding arrays', null);
				}
				decls.push('@group(${at.group}) @binding(${at.binding}) $decl;');
			}
		}

		if (compute)
			return;
		inputs.sort((a, b) -> rank(a) - rank(b));
		targets.sort((a, b) -> rank(a) - rank(b));
		var location = 0;
		if (inputs.length > 0) {
			var body = [];
			var used = new Map();
			for (v in inputs) {
				// An input's name without the struct that holds it: `position`.
				var n = unique(v.getName(), used);
				fields.set(v.id, n);
				layout.inputs.push({name: v.getName(), location: location});
				body.push('\t@location(${location++}) $n: ${type(v.type, null)},');
			}
			decls.push('struct VertexInput {\n${body.join("\n")}\n};');
			privates.push("var<private> vin: VertexInput;");
		}
		var used = new Map();
		positionField = unique("position", used);
		var body = ['\t@builtin(position) $positionField: vec4<f32>,'];
		location = 0;
		for (v in varyings) {
			var n = unique(path(v), used);
			fields.set(v.id, n);
			var flat = v.hasQualifier(Flat) || !isFloat(v.type) ? "@interpolate(flat) " : "";
			body.push('\t@location(${location++}) $flat$n: ${type(v.type, null)},');
		}
		decls.push('struct Varyings {\n${body.join("\n")}\n};');
		privates.push("var<private> vout: Varyings;");
		privates.push("var<private> fin: Varyings;");
		if (targets.length > 0) {
			var body = [];
			var used = new Map();
			location = 0;
			for (v in targets) {
				// The linker renames an output that shares a param's name; its Name qualifier keeps the field's.
				var name = v.getName();
				var n = unique(name, used);
				fields.set(v.id, n);
				if (roles.get(name) == Depth) {
					if (v.type != TFloat)
						error('output.$name is the fragment depth, a Float', null);
					body.push('\t@builtin(frag_depth) $n: f32,');
					continue;
				}
				layout.targets.push({name: name, location: location});
				body.push('\t@location(${location++}) $n: ${type(v.type, null)},');
			}
			decls.push('struct FragmentOutput {\n${body.join("\n")}\n};');
			privates.push("var<private> fout: FragmentOutput;");
		}
	}

	static function isFloat(t:Type):Bool {
		return switch (t) {
			case TFloat, TVec(_, VFloat): true;
			default: false;
		}
	}

	// -- variables -----------------------------------------------------------------------

	function access(v:TVar, p:Position):String {
		switch (v.kind) {
			case Param, Global:
				var o = overrides.get(v.id);
				if (o != null)
					return o;
				var f = paramFields.get(v.id);
				if (f != null)
					return v.type == TBool ? '($f != 0u)' : f;
				var b = bindings.get(v.id);
				if (b != null)
					return b;
				return error('${v.name} is not a value here', p);
			case Input:
				return 'vin.${fields.get(v.id)}';
			case Var:
				return (stageKind == Fragment ? "fin." : "vout.") + fields.get(v.id);
			case Output:
				return stageKind == Fragment ? 'fout.${fields.get(v.id)}' : 'vout.$positionField';
			case Local:
				addPrivate(v);
				return names.get(v.id);
			case Function:
				return error('${v.name} is a function', p);
		}
	}

	public function stage():FunctionKind {
		return compute ? Main : stageKind;
	}

	public function helper(code:String):Void {
		if (functions.indexOf(code) < 0)
			functions.unshift(code);
	}

	public function enable(name:String):Void {
		if (enables.indexOf(name) < 0)
			enables.push(name);
	}

	public function input(attribute:String, parameterType:String, type:String, ?convert:String->String):String {
		var known = stageInputs.get(attribute);
		if (known == null) {
			known = {
				name: fresh(attribute),
				parameterType: parameterType,
				convert: convert == null ? v -> v : convert,
				stages: new Map()
			};
			stageInputs.set(attribute, known);
			privates.push('var<private> ${known.name}: $type;');
		}
		known.stages.set(Std.string(stage()), true);
		return known.name;
	}

	// -- expressions -----------------------------------------------------------------------

	function float(f:Float):String {
		var s = Std.string(f);
		if (s.indexOf(".") < 0 && s.indexOf("e") < 0 && s.indexOf("E") < 0)
			s += ".0";
		return s;
	}

	/** `e` converted to `to`'s component type when it is an integer where a float is wanted, or the reverse. **/
	function convert(e:TExpr, to:VecType):String {
		var s = expr(e);
		return switch ([e.t, to]) {
			case [TInt, VFloat]: 'f32($s)';
			case [TFloat, VInt]: 'i32($s)';
			case [TVec(n, VInt), VFloat]: 'vec$n<f32>($s)';
			case [TVec(n, VFloat), VInt]: 'vec$n<i32>($s)';
			default: s;
		}
	}

	/** A scalar argument spread to `t` when `t` is a vector, as GLSL's overloads allow. **/
	function spread(e:TExpr, t:Type):String {
		return switch ([e.t, t]) {
			case [TFloat | TInt, TVec(n, k)]: 'vec$n<${vecType(k)}>(${expr(e)})';
			default: expr(e);
		}
	}

	function named(name:String, code:String):String {
		helper(code);
		return name;
	}

	function textureOf(e:TExpr):{texture:String, sampler:String, type:Type} {
		return switch (e.e) {
			case TVar(v) if (textures.exists(v.id)): textures.get(v.id);
			default: error("a texture here is one declared as a param", e.p);
		}
	}

	function coordinates(t:Type, uv:TExpr):Array<String> {
		var s = expr(uv);
		return switch (t) {
			case TSampler(T2D, true): ['($s).xy', 'i32(($s).z)'];
			case TSampler(TCube, true): ['($s).xyz', 'i32(($s).w)'];
			default: [s];
		}
	}

	function sample(args:Array<TExpr>, lod:Null<String>, p:Position):String {
		var tex = textureOf(args[0]);
		var coords = coordinates(tex.type, args[1]);
		// Implicit derivatives exist only in fragment code.
		if (lod == null && stageKind == Fragment)
			return 'textureSample(${tex.texture}, ${tex.sampler}, ${coords.join(", ")})';
		return 'textureSampleLevel(${tex.texture}, ${tex.sampler}, ${coords.join(", ")}, ${lod == null ? "0.0" : lod})';
	}

	function call(g:TGlobal, args:Array<TExpr>, rt:Type, p:Position):String {
		inline function a(i)
			return expr(args[i]);
		inline function all(name:String)
			return '$name(${[for (e in args) expr(e)].join(", ")})';
		inline function spreadAll(name:String)
			return '$name(${[for (e in args) spread(e, rt)].join(", ")})';
		return switch (g) {
			case Radians: all("radians");
			case Degrees: all("degrees");
			case Sin: all("sin");
			case Cos: all("cos");
			case Tan: all("tan");
			case Asin: all("asin");
			case Acos: all("acos");
			case Atan: args.length == 2 ? all("atan2") : all("atan");
			case Pow: spreadAll("pow");
			case Exp: all("exp");
			case Log: all("log");
			case Exp2: all("exp2");
			case Log2: all("log2");
			case Sqrt: all("sqrt");
			case Inversesqrt: all("inverseSqrt");
			case Abs: all("abs");
			case Sign: all("sign");
			case Floor: all("floor");
			case Ceil: all("ceil");
			case Fract: all("fract");
			case Mod:
				if (rt == TInt || rt.match(TVec(_, VInt)))
					'(${spread(args[0], rt)} % ${spread(args[1], rt)})';
				else
					'${named("hxsl_mod", modHelper(rt))}(${spread(args[0], rt)}, ${spread(args[1], rt)})';
			case Min: spreadAll("min");
			case Max: spreadAll("max");
			case Clamp: spreadAll("clamp");
			case Mix:
				// WGSL takes a scalar blend factor with vectors itself.
				'mix(${spread(args[0], rt)}, ${spread(args[1], rt)}, ${a(2)})';
			case InvLerp:
				'${named("hxsl_invLerp", "fn hxsl_invLerp(v: f32, a: f32, b: f32) -> f32 { return saturate((v - a) / (b - a)); }")}(${a(0)}, ${a(1)}, ${a(2)})';
			case Step: 'step(${spread(args[0], rt)}, ${spread(args[1], rt)})';
			case Smoothstep: 'smoothstep(${spread(args[0], rt)}, ${spread(args[1], rt)}, ${spread(args[2], rt)})';
			case Length: all("length");
			case Distance: all("distance");
			case Dot: all("dot");
			case Cross: all("cross");
			case Normalize: all("normalize");
			case LReflect: all("reflect");
			case Texture: sample(args, null, p);
			case TextureLod: sample(args, a(2), p);
			case Texel, TexelLod:
				var tex = textureOf(args[0]);
				'textureLoad(${tex.texture}, ${convert(args[1], VInt)}, ${args.length > 2 ? convert(args[2], VInt) : "0"})';
			case TextureSize:
				var tex = textureOf(args[0]);
				var lod = args.length > 1 ? ', ${convert(args[1], VInt)}' : "";
				switch (tex.type) {
					case TSampler(T2D | TCube, true):
						'vec3<f32>(vec2<f32>(textureDimensions(${tex.texture}$lod)), f32(textureNumLayers(${tex.texture})))';
					case TSampler(T3D, _): 'vec3<f32>(textureDimensions(${tex.texture}$lod))';
					case TSampler(T1D, _): 'f32(textureDimensions(${tex.texture}$lod))';
					default: 'vec2<f32>(textureDimensions(${tex.texture}$lod))';
				}
			case ToInt: rt.match(TVec(_)) ? '${type(rt, p)}(${a(0)})' : 'i32(${a(0)})';
			case ToFloat: rt.match(TVec(_)) ? '${type(rt, p)}(${a(0)})' : 'f32(${a(0)})';
			case ToBool: rt.match(TVec(_)) ? '${type(rt, p)}(${a(0)})' : 'bool(${a(0)})';
			case Vec2, Vec3, Vec4: '${type(rt, p)}(${[for (e in args) convert(e, VFloat)].join(", ")})';
			case IVec2, IVec3, IVec4: '${type(rt, p)}(${[for (e in args) convert(e, VInt)].join(", ")})';
			case BVec2, BVec3, BVec4: all(type(rt, p));
			case Mat2: all("mat2x2<f32>");
			case Mat3:
				switch (args.map(e -> e.t)) {
					case [TMat4 | TMat3x4]:
						var m = a(0);
						'mat3x3<f32>(($m)[0].xyz, ($m)[1].xyz, ($m)[2].xyz)';
					default: all("mat3x3<f32>");
				}
			case Mat4: all("mat4x4<f32>");
			case Mat3x4:
				switch (args.map(e -> e.t)) {
					case [TMat4]:
						var m = a(0);
						'mat3x4<f32>(($m)[0], ($m)[1], ($m)[2])';
					default: all("mat3x4<f32>");
				}
			case Saturate: all("saturate");
			case Pack:
				'${named("hxsl_pack", "fn hxsl_pack(v: f32) -> vec4<f32> { let c = fract(v * vec4<f32>(1.0, 255.0, 65025.0, 16581375.0)); return c - c.yzww * vec4<f32>(1.0 / 255.0, 1.0 / 255.0, 1.0 / 255.0, 0.0); }")}(${a(0)})';
			case Unpack:
				'${named("hxsl_unpack", "fn hxsl_unpack(c: vec4<f32>) -> f32 { return dot(c, vec4<f32>(1.0, 1.0 / 255.0, 1.0 / 65025.0, 1.0 / 16581375.0)); }")}(${a(0)})';
			case PackNormal:
				'${named("hxsl_packNormal", "fn hxsl_packNormal(v: vec3<f32>) -> vec4<f32> { return vec4<f32>((v + vec3<f32>(1.0)) * vec3<f32>(0.5), 1.0); }")}(${a(0)})';
			case UnpackNormal:
				'${named("hxsl_unpackNormal", "fn hxsl_unpackNormal(v: vec4<f32>) -> vec3<f32> { let xy = (v.xy - vec2<f32>(0.5)) * vec2<f32>(2.0); return vec3<f32>(xy, sqrt(1.0 - saturate(dot(xy, xy)))); }")}(${a(0)})';
			case ScreenToUv:
				'(${a(0)} * vec2<f32>(0.5, -0.5) + vec2<f32>(0.5, 0.5))';
			case UvToScreen:
				'(${a(0)} * vec2<f32>(2.0, -2.0) + vec2<f32>(-1.0, 1.0))';
			case DFdx: all("dpdx");
			case DFdy: all("dpdy");
			case Fwidth: all("fwidth");
			case FloatBitsToInt, FloatBitsToUint: 'bitcast<${type(rt, p)}>(${a(0)})';
			case IntBitsToFloat, UintBitsToFloat: 'bitcast<${type(rt, p)}>(${a(0)})';
			case RoundEven: all("round");
			case Transpose: all("transpose");
			case UnpackSnorm4x8: 'unpack4x8snorm(u32(${a(0)}))';
			case UnpackUnorm4x8: 'unpack4x8unorm(u32(${a(0)}))';
			case FindLSB: all("firstTrailingBit");
			case FindMSB: all("firstLeadingBit");
			case BitCount: all("countOneBits");
			case GroupMemoryBarrier: "workgroupBarrier()";
			case ImageStore:
				var target = switch (args[0].e) {
					case TVar(v) if (bindings.exists(v.id)): bindings.get(v.id);
					default: error("imageStore writes a storage texture declared as a param", p);
				}
				var value = switch (args[2].t) {
					case TFloat: 'vec4<f32>(${a(2)}, 0.0, 0.0, 0.0)';
					case TVec(2, _): 'vec4<f32>(${a(2)}, 0.0, 0.0)';
					case TVec(3, _): 'vec4<f32>(${a(2)}, 0.0)';
					default: a(2);
				}
				'textureStore($target, ${convert(args[1], VInt)}, $value)';
			default:
				extended(g, args, p);
		}
	}

	/** A built-in an extension prints, or an error naming it. **/
	function extended(g:TGlobal, args:Array<TExpr>, p:Position):String {
		for (x in exts) {
			var wgsl = x.builtin(g, args, this);
			if (wgsl != null)
				return wgsl;
		}
		return error('${g.toString()} has no WGSL here; an extension can give it one', p);
	}

	function modHelper(t:Type):String {
		var wt = type(t, null);
		return 'fn hxsl_mod(x: $wt, y: $wt) -> $wt { return x - y * floor(x / y); }';
	}

	function globalValue(g:TGlobal, p:Position):String {
		return switch (g) {
			case FragCoord:
				if (stageKind != Fragment) error("fragCoord is fragment data", p);
				'fin.$positionField';
			case FrontFacing: input("front_facing", "bool", "bool");
			case VertexID: input("vertex_index", "u32", "i32", v -> 'i32($v)');
			case InstanceID: input("instance_index", "u32", "i32", v -> 'i32($v)');
			case ComputeVar_GlobalInvocation: input("global_invocation_id", "vec3<u32>", "vec3<i32>", v -> 'vec3<i32>($v)');
			case ComputeVar_LocalInvocation: input("local_invocation_id", "vec3<u32>", "vec3<i32>", v -> 'vec3<i32>($v)');
			case ComputeVar_WorkGroup: input("workgroup_id", "vec3<u32>", "vec3<i32>", v -> 'vec3<i32>($v)');
			case ComputeVar_LocalInvocationIndex: input("local_invocation_index", "u32", "i32", v -> 'i32($v)');
			default: extended(g, [], p);
		}
	}

	static function opStr(op:Binop):String {
		return switch (op) {
			case OpAdd: "+";
			case OpMult: "*";
			case OpDiv: "/";
			case OpSub: "-";
			case OpMod: "%";
			case OpAnd: "&";
			case OpOr: "|";
			case OpXor: "^";
			case OpBoolAnd: "&&";
			case OpBoolOr: "||";
			case OpEq: "==";
			case OpNotEq: "!=";
			case OpGt: ">";
			case OpGte: ">=";
			case OpLt: "<";
			case OpLte: "<=";
			case OpShl: "<<";
			case OpShr: ">>";
			default: throw "assert";
		}
	}

	function binop(op:Binop, e1:TExpr, e2:TExpr, rt:Type, p:Position):String {
		return switch ([op, e1.t, e2.t]) {
			case [OpMult, TVec(3, VFloat), TMat3x4]:
				'(vec4<f32>(${expr(e1)}, 1.0) * ${expr(e2)})';
			case [OpMod, _, _] if (rt != TInt && !rt.match(TVec(_, VInt))):
				'${named("hxsl_mod", modHelper(rt))}(${spread(e1, rt)}, ${spread(e2, rt)})';
			case [OpShl | OpShr, _, _]:
				'(${expr(e1)} ${opStr(op)} u32(${expr(e2)}))';
			case [OpUShr, _, _]:
				'i32(u32(${expr(e1)}) >> u32(${expr(e2)}))';
			case [OpEq | OpNotEq | OpLt | OpGt | OpLte | OpGte, TVec(n, _), _] | [OpEq | OpNotEq | OpLt | OpGt | OpLte | OpGte, _, TVec(n, _)]:
				var compare = '(${expr(e1)} ${opStr(op)} ${expr(e2)})';
				switch (rt) {
					case TBool: op == OpNotEq ? 'any$compare' : 'all$compare';
					case TVec(_, VFloat): 'select(vec$n<f32>(0.0), vec$n<f32>(1.0), $compare)';
					default: compare;
				}
			case [OpAssign | OpAssignOp(_), _, _]:
				error("an assignment is not a value in WGSL", p);
			case [OpInterval, _, _]:
				error("a range is only a for loop's", p);
			default:
				// WGSL takes a scalar on either side of a vector operator.
				'(${expr(e1)} ${opStr(op)} ${expr(e2)})';
		}
	}

	public function expr(e:TExpr):String {
		return switch (e.e) {
			case TConst(CInt(v)): Std.string(v);
			case TConst(CFloat(f)): float(f);
			case TConst(CBool(b)): b ? "true" : "false";
			case TConst(_): error("only numbers and booleans are WGSL constants", e.p);
			case TVar(v): access(v, e.p);
			case TGlobal(g): globalValue(g, e.p);
			case TParenthesis(inner): '(${expr(inner)})';
			case TBlock(_): value(e);
			case TBinop(op, e1, e2): binop(op, e1, e2, e.t, e.p);
			case TUnop(OpNot, e1): '!(${expr(e1)})';
			case TUnop(OpNeg, e1): '-(${expr(e1)})';
			case TUnop(OpNegBits, e1): '~(${expr(e1)})';
			case TUnop(_, _): error("++ and -- are statements in WGSL", e.p);
			case TCall({e: TGlobal(g)}, args): call(g, args, e.t, e.p);
			case TCall({e: TVar(v)}, args) if (v.kind == Function && externs.exists(v.name)):
				externs.get(v.name).print({
					args: [for (a in args) expr(a)],
					types: [for (a in args) a.t],
					ret: e.t,
					out: this
				});
			case TCall(_, _): error("only HXSL's own and extensions' functions remain after inlining", e.p);
			case TSwiz(inner, regs):
				switch (inner.t) {
					case TFloat | TInt | TBool if (regs.length > 1):
						'vec${regs.length}<${vecType(switch (inner.t) { case TInt: VInt; case TBool: VBool; default: VFloat; })}>(${expr(inner)})';
					case TFloat | TInt | TBool:
						expr(inner);
					default:
						'${expr(inner)}.${[for (r in regs) switch (r) { case X: "x"; case Y: "y"; case Z: "z"; case W: "w"; }].join("")}';
				}
			case TIf(cond, eif, eelse) if (eelse != null):
				'select(${expr(eelse)}, ${expr(eif)}, ${expr(cond)})';
			case TArray(a, index): '${expr(a)}[${expr(index)}]';
			case TArrayDecl(el):
				var t = switch (e.t) {
					case TArray(t, _): type(t, e.p);
					default: error("an array literal has an array type", e.p);
				}
				'array<$t, ${el.length}>(${[for (x in el) expr(x)].join(", ")})';
			case TMeta(_, _, inner): expr(inner);
			case TField(inner, name): '${expr(inner)}.$name';
			case TSyntax("code" | "wgsl", code, args): syntax(code, args);
			default: error("this is not a value in WGSL", e.p);
		}
	}

	function syntax(code:String, args:Array<SyntaxArg>):String {
		var out = new StringBuf();
		var pos = 0;
		var arg = ~/{(\d+)}/g;
		while (arg.matchSub(code, pos)) {
			var at = arg.matchedPos();
			out.add(code.substring(pos, at.pos));
			var index = Std.parseInt(arg.matched(1));
			if (index < args.length)
				out.add(expr(args[index].e));
			pos = at.pos + at.len;
		}
		out.add(code.substr(pos));
		return out.toString();
	}

	/** A block used as a value, as a function of no arguments that returns its last expression. **/
	function value(e:TExpr):String {
		var el = switch (e.e) {
			case TBlock(el): el;
			default: throw "assert";
		}
		var name = fresh('hxsl_value${valueCount++}');
		var wasEntry = inEntry;
		inEntry = false;
		var out = new StringBuf();
		out.add('fn $name() -> ${type(e.t, e.p)} {\n');
		for (i in 0...el.length - 1)
			out.add(statement(el[i], "\t"));
		out.add('\treturn ${expr(el[el.length - 1])};\n}');
		inEntry = wasEntry;
		functions.push(out.toString());
		return '$name()';
	}

	// -- statements ----------------------------------------------------------------------

	function body(e:TExpr, tabs:String):String {
		return switch (e.e) {
			case TBlock(el):
				var out = new StringBuf();
				out.add("{\n");
				for (s in el)
					out.add(statement(s, tabs + "\t"));
				out.add(tabs + "}");
				out.toString();
			default:
				'{\n${statement(e, tabs + "\t")}$tabs}';
		}
	}

	function stageReturn():String {
		return compute ? "return" : stageKind == Fragment ? (targets.length > 0 ? "return fout" : "return") : "return vout";
	}

	function statement(e:TExpr, tabs:String):String {
		inline function line(s:String)
			return '$tabs$s;\n';
		return switch (e.e) {
			case TBlock(_): tabs + body(e, tabs) + "\n";
			case TVarDecl(v, init):
				addPrivate(v);
				init == null ? "" : line('${names.get(v.id)} = ${expr(init)}');
			case TIf(cond, eif, eelse):
				var out = '${tabs}if (${expr(cond)}) ${body(eif, tabs)}';
				if (eelse != null)
					out += ' else ${body(eelse, tabs)}';
				out + "\n";
			case TFor(v, {e: TBinop(OpInterval, from, to)}, loop):
				addPrivate(v);
				var n = names.get(v.id);
				'${tabs}for ($n = ${expr(from)}; $n < ${expr(to)}; $n++) ${body(loop, tabs)}\n';
			case TFor(_, _, _): error("a for loop runs over a range, `a...b`", e.p);
			case TWhile(cond, loop, true): '${tabs}while (${expr(cond)}) ${body(loop, tabs)}\n';
			case TWhile(cond, loop, false):
				var inner = body(loop, tabs + "\t");
				'${tabs}loop {\n$tabs\t$inner\n$tabs\tcontinuing {\n$tabs\t\tbreak if !(${expr(cond)});\n$tabs\t}\n$tabs}\n';
			case TSwitch(subject, cases, def):
				var out = new StringBuf();
				out.add('${tabs}switch (${expr(subject)}) {\n');
				for (c in cases)
					out.add('$tabs\tcase ${[for (v in c.values) expr(v)].join(", ")}: ${body(c.expr, tabs + "\t")}\n');
				out.add('$tabs\tdefault: ${def == null ? "{}" : body(def, tabs + "\t")}\n');
				out.add('$tabs}\n');
				out.toString();
			case TDiscard: line("discard");
			case TReturn(null): line(inEntry ? stageReturn() : "return");
			case TReturn(v): line('return ${expr(v)}');
			case TBreak: line("break");
			case TContinue: line("continue");
			case TCall({e: TGlobal(SetLayout)}, _): "";
			case TCall({e: TGlobal(GroupMemoryBarrier | ImageStore)}, _): line(expr(e));
			case TUnop(OpIncrement, target): line('${expr(target)}++');
			case TUnop(OpDecrement, target): line('${expr(target)}--');
			case TBinop(OpAssign, target, v): line('${expr(target)} = ${spread(v, target.t)}');
			case TBinop(OpAssignOp(op), target, v):
				switch ([op, target.t, v.t]) {
					case [OpMult, TVec(3, VFloat), TMat3x4], [OpMod, _, _], [OpShl | OpShr | OpUShr, _, _]:
						line('${expr(target)} = ${binop(op, target, v, target.t, e.p)}');
					default:
						line('${expr(target)} ${opStr(op)}= ${spread(v, target.t)}');
				}
			case TMeta(_, _, inner): statement(inner, tabs);
			case TSyntax("code" | "wgsl", code, args): line(syntax(code, args));
			case TSyntax(_, _, _): "";
			case TConst(_) | TVar(_) | TGlobal(_): "";
			default: line('_ = ${expr(e)}');
		}
	}

	function collectLayout(e:TExpr) {
		switch (e.e) {
			case TCall({e: TGlobal(SetLayout)}, args):
				for (i in 0...args.length)
					switch (args[i].e) {
						case TConst(CInt(v)): workgroup[i] = v;
						default: error("setLayout takes constant sizes", args[i].p);
					}
			default:
				e.iter(collectLayout);
		}
	}

	// -- the module ----------------------------------------------------------------------

	function entry(s:ShaderData):String {
		var f = s.funs[0];
		stageKind = compute ? Main : f.kind;
		inEntry = true;
		var statements = switch (f.expr.e) {
			case TBlock(el): [for (x in el) statement(x, "\t")].join("");
			default: statement(f.expr, "\t");
		}
		inEntry = false;
		var args = [];
		var copies = [];
		var here = Std.string(stage());
		for (attribute => b in stageInputs)
			if (b.stages.exists(here)) {
				args.push('@builtin($attribute) in_$attribute: ${b.parameterType}');
				copies.push('\t${b.name} = ${b.convert('in_$attribute')};\n');
			}
		var head:String;
		if (compute) {
			head = '@compute @workgroup_size(${workgroup.join(", ")})\nfn main(${args.join(", ")}) {\n';
		} else if (stageKind == Vertex) {
			if (inputs.length > 0) {
				args.unshift("attributes: VertexInput");
				copies.unshift("\tvin = attributes;\n");
			}
			head = '@vertex\nfn vertex(${args.join(", ")}) -> Varyings {\n';
		} else {
			args.unshift("varyings: Varyings");
			copies.unshift("\tfin = varyings;\n");
			head = '@fragment\nfn fragment(${args.join(", ")})${targets.length > 0 ? " -> FragmentOutput" : ""} {\n';
		}
		var tail = compute ? "" : '\t${stageReturn()};\n';
		return head + copies.join("") + statements + tail + "}";
	}

	public function run(stages:Array<ShaderData>, isCompute:Bool):String {
		compute = isCompute;
		for (s in stages)
			collectLayout(s.funs[0].expr);
		collect(stages);
		declare();
		var entries = [for (s in stages) entry(s)];
		var out = [
			[for (e in enables) 'enable $e;'].join("\n"),
			// HXSL samples textures in any control flow, as GLSL and HLSL allow.
			"diagnostic(off, derivative_uniformity);",
			decls.join("\n"),
			privates.join("\n"),
			functions.join("\n\n"),
			entries.join("\n\n")
		];
		return [for (part in out) if (part != "") part].join("\n\n") + "\n";
	}
}
