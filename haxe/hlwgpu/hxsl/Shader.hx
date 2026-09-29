package hlwgpu.hxsl;

/**
	A shader written in HXSL. A class that implements this declares its
	source in `static var SRC = { ... }`; the build macro checks it when
	the program compiles and replaces it with `static final WGSL`, the
	source the gpu plugin compiles.
**/
#if !macro
@:autoBuild(hlwgpu.hxsl.Build.shader())
#end
interface Shader {}
