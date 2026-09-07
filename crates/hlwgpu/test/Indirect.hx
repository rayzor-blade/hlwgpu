/**
	A draw whose counts come from a buffer, and a blend factor that comes from
	the pass rather than the pipeline.

	Both are things a renderer sets between draws without rebuilding anything:
	the counts so that work the GPU produced can be drawn without reading it
	back, the constant so one pipeline can fade different things by different
	amounts.
**/
class Indirect {
	static inline var SIZE = 64;
	static inline var ROW = SIZE * 4;

	static var SHADER = "
@vertex
fn vs(@location(0) pos : vec2<f32>) -> @builtin(position) vec4<f32> {
	return vec4<f32>(pos, 0.0, 1.0);
}

@fragment
fn fs() -> @location(0) vec4<f32> {
	return vec4<f32>(1.0, 0.0, 0.0, 1.0);
}
";

	static function pixel(image : haxe.io.Bytes, x : Int, y : Int) : String {
		var at = y * ROW + x * 4;
		return image.get(at) + "," + image.get(at + 1) + "," + image.get(at + 2) + "," + image.get(at + 3);
	}

	static function main() {
		var instance = wgpu.Instance.create();
		var adapter = instance.adapter();
		var device = adapter.device();
		if (!device.ok) {
			Sys.println("no device");
			Sys.exit(1);
		}
		var queue = device.queue;

		var target = device.texture(SIZE, SIZE, Rgba8Unorm, RenderAttachment | CopySrc);
		var view = target.view();
		var readback = device.buffer(SIZE * ROW, MapRead | CopyDst);

		var corners = [-1.0, -1.0, 1.0, -1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, 1.0];
		var data = haxe.io.Bytes.alloc(corners.length * 4);
		for (i in 0...corners.length) {
			data.setFloat(i * 4, corners[i]);
		}
		var vertices = device.buffer(data.length, Vertex | CopyDst);
		queue.write(vertices, 0, data);

		// Six vertices, one instance, starting at the beginning of each.
		var commands = haxe.io.Bytes.alloc(16);
		commands.setInt32(0, 6);
		commands.setInt32(4, 1);
		commands.setInt32(8, 0);
		commands.setInt32(12, 0);
		var indirect = device.buffer(16, Indirect | CopyDst);
		queue.write(indirect, 0, commands);

		var shader = device.shader(SHADER);
		var pipeline = device.pipeline()
			.shader(shader, "vs", "fs")
			.vertexBuffer().attributes(Float32x2)
			.target(Rgba8Unorm).blend(Constant, OneMinusConstant)
			.build();

		function paint(constant : Float, indirectly : Bool) : haxe.io.Bytes {
			var encoder = device.encoder();
			encoder.beginRender(view, 0.0, 0.0, 1.0);
			encoder.pushDebugGroup(indirectly ? "indirect draw" : "direct draw");
			encoder.setPipeline(pipeline);
			encoder.setBlendConstant(constant, constant, constant);
			encoder.setVertexBuffer(0, vertices);
			if (indirectly) {
				encoder.drawIndirect(indirect);
			} else {
				encoder.draw(6);
			}
			encoder.popDebugGroup();
			encoder.endRender();
			encoder.copyTextureToBuffer(target, readback, SIZE, SIZE, ROW);
			encoder.submit(queue);
			var image = readback.read(device, 0, SIZE * ROW);
			// Nothing panics any more, so a mistake is only visible if
			// something asks. This is what the queue is for.
			var complaint = device.takeError();
			while (complaint != null) {
				Sys.println("  device says: " + complaint);
				complaint = device.takeError();
			}
			return image;
		}

		var failed = 0;
		function check(what : String, got : String, want : String) {
			if (got != want) {
				Sys.println('  $what: wanted $want, got $got');
				failed++;
			}
		}

		var mid = SIZE >> 1;
		// A constant of one takes all of the source, of zero none of it.
		check("a constant of 1 keeps the drawn colour", pixel(paint(1.0, false), mid, mid), "255,0,0,255");
		check("a constant of 0 leaves the clear", pixel(paint(0.0, false), mid, mid), "0,0,255,255");
		// The same draw again, with its counts read from a buffer.
		check("drawn from a buffer", pixel(paint(1.0, true), mid, mid), "255,0,0,255");

		Sys.println(failed == 0 ? "indirect: counts from a buffer and a blend constant, exactly"
			: 'indirect: $failed wrong');

		pipeline.destroy();
		shader.destroy();
		indirect.destroy();
		vertices.destroy();
		readback.destroy();
		view.destroy();
		target.destroy();
		device.destroy();
		adapter.destroy();
		instance.destroy();
		Sys.exit(failed == 0 ? 0 : 1);
	}
}
