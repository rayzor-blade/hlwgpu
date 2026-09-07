/**
	A mask written in one pass and read in the next.

	The second draw covers the whole target and would fill it, except that it
	is only allowed where the first draw left a mark. Anything else on screen
	would mean the stencil was ignored, which is the only way this can pass by
	accident.
**/
class Stencil {
	static inline var SIZE = 64;
	static inline var ROW = SIZE * 4;

	static var SHADER = "
@vertex
fn vs(@location(0) pos : vec2<f32>) -> @builtin(position) vec4<f32> {
	return vec4<f32>(pos, 0.0, 1.0);
}

@fragment
fn mark() -> @location(0) vec4<f32> {
	return vec4<f32>(0.0, 0.0, 0.0, 1.0);
}

@fragment
fn paint() -> @location(0) vec4<f32> {
	return vec4<f32>(1.0, 0.0, 0.0, 1.0);
}
";

	static function pixel(image : haxe.io.Bytes, x : Int, y : Int) : String {
		var at = y * ROW + x * 4;
		return image.get(at) + "," + image.get(at + 1) + "," + image.get(at + 2) + "," + image.get(at + 3);
	}

	static function quad(x0 : Float, x1 : Float) : haxe.io.Bytes {
		var corners = [[x0, -1.0], [x1, -1.0], [x1, 1.0], [x0, -1.0], [x1, 1.0], [x0, 1.0]];
		var out = haxe.io.Bytes.alloc(corners.length * 8);
		var at = 0;
		for (c in corners) {
			out.setFloat(at, c[0]);
			out.setFloat(at + 4, c[1]);
			at += 8;
		}
		return out;
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
		var stencilBuffer = device.texture(SIZE, SIZE, Depth24PlusStencil8, RenderAttachment);
		var stencilView = stencilBuffer.view();
		var readback = device.buffer(SIZE * ROW, MapRead | CopyDst);

		var left = device.buffer(48, Vertex | CopyDst);
		queue.write(left, 0, quad(-1.0, 0.0));
		var whole = device.buffer(48, Vertex | CopyDst);
		queue.write(whole, 0, quad(-1.0, 1.0));

		var shader = device.shader(SHADER);

		// Writes 1 into the stencil wherever it draws, and no colour.
		var marker = device.pipeline().shader(shader, "vs", "mark")
			.vertexBuffer().attributes(Float32x2)
			.target(Rgba8Unorm, 0)
			.depth(Depth24PlusStencil8, false, Always)
			.stencil(Always, Keep, Keep, Replace)
			.build();

		// Draws only where the stencil already says 1.
		var painter = device.pipeline().shader(shader, "vs", "paint")
			.vertexBuffer().attributes(Float32x2)
			.target(Rgba8Unorm)
			.depth(Depth24PlusStencil8, false, Always)
			.stencil(Equal, Keep, Keep, Keep)
			.build();

		var encoder = device.encoder();
		encoder.beginRenderStencil(view, stencilView, 0.0, 0.0, 0.0);
		encoder.setStencilReference(1);
		encoder.setPipeline(marker);
		encoder.setVertexBuffer(0, left);
		encoder.draw(6);
		encoder.setPipeline(painter);
		encoder.setVertexBuffer(0, whole);
		encoder.draw(6);
		encoder.endRender();
		encoder.copyTextureToBuffer(target, readback, SIZE, SIZE, ROW);
		encoder.submit(queue);

		var out = readback.read(device, 0, SIZE * ROW);
		var complaint = device.takeError();
		while (complaint != null) {
			Sys.println("  device says: " + complaint);
			complaint = device.takeError();
		}
		if (out == null) {
			Sys.println("readback failed");
			Sys.exit(1);
		}

		var mid = SIZE >> 1;
		var failed = 0;
		for (check in [{ what: "inside the mark", x: 16, want: "255,0,0,255" },
			{ what: "outside it", x: 48, want: "0,0,0,255" }]) {
			var got = pixel(out, check.x, mid);
			if (got != check.want) {
				Sys.println('  ${check.what}: wanted ${check.want}, got $got');
				failed++;
			}
		}
		Sys.println(failed == 0 ? "stencil: the second draw landed only where the first marked"
			: 'stencil: $failed of 2 wrong');

		painter.destroy();
		marker.destroy();
		shader.destroy();
		whole.destroy();
		left.destroy();
		readback.destroy();
		stencilView.destroy();
		stencilBuffer.destroy();
		view.destroy();
		target.destroy();
		device.destroy();
		adapter.destroy();
		instance.destroy();
		Sys.exit(failed == 0 ? 0 : 1);
	}
}
