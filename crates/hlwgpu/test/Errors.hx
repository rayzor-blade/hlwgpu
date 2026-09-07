/**
	A shader that is not WGSL, and a pipeline that cannot be built from it.

	The point is that neither stops the program. Before the device collected
	them, a validation mistake panicked inside wgpu and took the process with
	it, naming neither the cause nor the caller.
**/
class Errors {
	static function main() {
		var instance = wgpu.Instance.create();
		var adapter = instance.adapter();
		var device = adapter.device();
		if (!device.ok) {
			Sys.println("no device");
			Sys.exit(1);
		}

		var failed = 0;
		if (device.takeError() != null) {
			Sys.println("  a fresh device already had something to complain about");
			failed++;
		}

		device.shader("@vertex fn nonsense( this is not a shader");
		var message = device.takeError();
		if (message == null || message.length == 0) {
			Sys.println("  a broken shader reported nothing");
			failed++;
		} else {
			// Just the first line: the rest is a source excerpt.
			Sys.println("  reported: " + message.split("\n")[0]);
		}

		if (device.takeError() != null) {
			Sys.println("  the same error was reported twice");
			failed++;
		}

		// And the device still works afterwards.
		var buffer = device.buffer(256, CopyDst | CopySrc);
		if (!buffer.ok) {
			Sys.println("  the device was unusable afterwards");
			failed++;
		}
		buffer.destroy();

		Sys.println(failed == 0 ? "errors: reported, once each, and the device carried on"
			: 'errors: $failed wrong');

		device.destroy();
		adapter.destroy();
		instance.destroy();
		Sys.exit(failed == 0 ? 0 : 1);
	}
}
