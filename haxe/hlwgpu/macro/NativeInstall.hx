package hlwgpu.macro;

#if macro
import haxe.Json;
import haxe.io.Path;
import haxe.macro.Compiler;
import haxe.macro.Context;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

/** Copy the bundled host xgpu.hdll beside HashLink bytecode. */
class NativeInstall {
	public static function stage():Void {
		if (!Context.defined("hl") || Context.defined("hlc") || Context.defined("hlwgpu_no_hdll")) return;
		Context.onAfterGenerate(() -> {
			var platform = hostPlatform();
			// The haxelib root holds haxe/hlwgpu/macro/NativeInstall.hx.
			var module = Context.resolvePath("hlwgpu/macro/NativeInstall.hx");
			var root = Path.directory(Path.directory(Path.directory(Path.directory(module))));
			var manifest:Dynamic = Json.parse(File.getContent(Path.join([root, "native/hdlls.json"])));
			var entry:Dynamic = Reflect.field(manifest, platform);
			// The Windows build that carries Vulkan beside D3D12; Linux already uses Vulkan.
			if (Context.defined("hlwgpu_vulkan") && Reflect.hasField(manifest, platform + "-vulkan"))
				entry = Reflect.field(manifest, platform + "-vulkan");
			if (entry == null) {
				Context.fatalError('hlwgpu has no xgpu.hdll for $platform', Context.currentPos());
				return;
			}
			var source = Path.join([root, entry.packagePath]);
			if (!FileSystem.exists(source)) {
				Context.fatalError('hlwgpu is missing $source; install the release Haxelib ZIP, or define hlwgpu_no_hdll and supply xgpu.hdll yourself',
					Context.currentPos());
				return;
			}
			var destination = Path.join([Path.directory(Compiler.getOutput()), "xgpu.hdll"]);
			if (Path.normalize(source) != Path.normalize(destination)) File.copy(source, destination);
		});
	}

	static function hostPlatform():String {
		var os = switch (Sys.systemName()) {
			case "Linux": "linux";
			case "Mac": "macos";
			case "Windows": "windows";
			case other: other.toLowerCase();
		};
		var arch:String;
		if (os == "windows") {
			arch = Sys.getEnv("PROCESSOR_ARCHITEW6432");
			if (arch == null) arch = Sys.getEnv("PROCESSOR_ARCHITECTURE");
		} else {
			var process = new Process("uname", ["-m"]);
			arch = StringTools.trim(process.stdout.readAll().toString());
			var status = process.exitCode();
			process.close();
			if (status != 0) throw "hlwgpu could not detect the CPU architecture";
		}
		arch = switch (arch == null ? "" : arch.toLowerCase()) {
			case "amd64", "x86_64": "x86_64";
			case "arm64", "aarch64": "aarch64";
			case other: other;
		};
		return '$os-$arch';
	}
}
#end
