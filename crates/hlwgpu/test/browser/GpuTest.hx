import gpu.BufferUsage;
import gpu.ColorWrite;
import gpu.ErrorFilter;
import gpu.Feature;
import gpu.GpuBindings;
import gpu.GpuBuffer;
import gpu.GpuBufferDescriptor;
import gpu.CompilationMessageType;
import gpu.DeviceLostReason;
import gpu.FilterMode;
import gpu.GpuColor;
import gpu.GpuComputePipelineDescriptor;
import gpu.GpuProgrammableStage;
import gpu.GpuQuerySetDescriptor;
import gpu.GpuRenderBundleEncoderDescriptor;
import gpu.GpuSamplerDescriptor;
import gpu.QueryType;
import gpu.TextureDimension;
import gpu.GpuDevice;
import gpu.GpuError;
import gpu.GpuExtent3D;
import gpu.GpuInstance;
import gpu.GpuInstanceDescriptor;
import gpu.GpuQueue;
import gpu.GpuRenderPassColorAttachment;
import gpu.GpuRenderPassDescriptor;
import gpu.GpuTexture;
import gpu.GpuTextureDescriptor;
import gpu.GpuTextureViewDescriptor;
import gpu.Limit;
import gpu.LoadOp;
import gpu.MapMode;
import gpu.Power;
import gpu.StoreOp;
import gpu.TextureFormat;
import gpu.TextureUsage;
import haxe.Int64;
import haxe.io.Bytes;

/**
	xgpu's browser backend, checked against what the GPU hands back: a
	compute pass's integers, a render target's pixels, and the errors and
	rejections a program can observe. Prints `PASS` or `FAIL <n>` last.
**/
class GpuTest {
	static var failures = 0;

	static function check(ok:Bool, what:String) {
		Sys.println((ok ? "ok   " : "FAIL ") + what);
		if (!ok) failures++;
	}

	/** The buffer's first `len` bytes, mapped for reading and copied out. **/
	static function readBack(device:GpuDevice, buffer:GpuBuffer, len:Int):Bytes {
		device.mapBufferWith(buffer, MapMode.READ, 0, len).await();
		var out = Bytes.alloc(len);
		var copied = buffer.copyOut(0, out, len);
		buffer.unmap();
		return copied ? out : null;
	}

	static function main() {
		var instance = GpuInstance.createWith(new GpuInstanceDescriptor());
		check(instance.valid(), "an instance made with native options");
		var adapter = instance.requestAdapter(Power.HighPerformance).await();
		check(adapter.valid(), "an adapter: " + adapter.name());
		var device = adapter.requestDevice().await();
		check(device.valid(), "a device");
		var queue = device.queue();

		features(adapter, device);
		limits(device);
		check(queue.timestampPeriod() == 1.0, "timestamps count nanoseconds");
		compute(device, queue);
		render(device, queue);
		errors(device);
		caught(device, queue);
		sampled(device, queue);
		copyIn(device, queue);
		pipelines(device);

		var leftover = device.takeError();
		check(leftover == null, "nothing else went wrong: " + leftover);
		var lost = device.lost();
		device.destroy();
		var info = lost.await();
		check(info.valid() && info.reason() == DeviceLostReason.Destroyed, "a destroyed device is lost: " + info.message());
		info.destroy();
		adapter.destroy();
		instance.destroy();
		Sys.println(failures == 0 ? "PASS" : 'FAIL $failures');
	}

	static function features(adapter:gpu.GpuAdapter, device:GpuDevice) {
		var names = [];
		for (f in 0...24) {
			var feature:Feature = f;
			var onAdapter = adapter.supports(feature);
			if (onAdapter) names.push(f);
			if (device.supports(feature) && !onAdapter) {
				check(false, 'device feature $f is not on its adapter');
			}
		}
		Sys.println("adapter features (by index): " + names.join(","));
		check(device.supports(Feature.CoreFeaturesAndLimits) == adapter.supports(Feature.CoreFeaturesAndLimits),
			"core-features-and-limits agrees between adapter and device");
	}

	static function limits(device:GpuDevice) {
		var dimension = device.limit(Limit.MaxTextureDimension2D);
		check(dimension >= 8192, 'maxTextureDimension2D, an unsigned long: $dimension');
		var size = device.limit(Limit.MaxBufferSize);
		check(size >= Int64.ofInt(268435456), 'maxBufferSize, an unsigned long long: $size');
	}

	/** Sixteen integers through `x * 3 + 1`, read back exactly. **/
	static function compute(device:GpuDevice, queue:GpuQueue) {
		var count = 16;
		var data = Bytes.alloc(count * 4);
		for (i in 0...count) data.setInt32(i * 4, i * 1000 - 7);
		var storage = device.createBuffer(new GpuBufferDescriptor(data.length, BufferUsage.STORAGE | BufferUsage.COPY_SRC | BufferUsage.COPY_DST));
		queue.writeBuffer(storage, 0, data, data.length);
		var readback = device.createBuffer(new GpuBufferDescriptor(data.length, BufferUsage.MAP_READ | BufferUsage.COPY_DST));
		var shader = device.createShader('
			@group(0) @binding(0) var<storage, read_write> data: array<i32>;
			@compute @workgroup_size(16)
			fn main(@builtin(global_invocation_id) id: vec3<u32>) {
				data[id.x] = data[id.x] * 3 + 1;
			}
		');
		var pipeline = device.computePipeline(shader, "main");
		var bindings = new GpuBindings();
		bindings.buffer(storage);
		var group = device.bindGroup(pipeline, 0, bindings);
		var encoder = device.encoder();
		encoder.pushDebugGroup("compute");
		encoder.compute(pipeline, group, 1, 1, 1);
		encoder.insertDebugMarker("copy");
		encoder.copyBuffer(storage, 0, readback, 0, data.length);
		encoder.popDebugGroup();
		encoder.submit(queue);
		var out = readBack(device, readback, data.length);
		var exact = out != null;
		if (exact) for (i in 0...count) if (out.getInt32(i * 4) != (i * 1000 - 7) * 3 + 1) exact = false;
		check(exact, "a compute pass's integers, read back exactly");
		bindings.destroy();
		group.destroy();
		pipeline.destroy();
		shader.destroy();
		storage.destroy();
		readback.destroy();
	}

	static function texture2d(device:GpuDevice, width:Int, height:Int, usage:Int):GpuTexture {
		var size = new GpuExtent3D(width);
		size.height(height);
		return device.texture(new GpuTextureDescriptor(size, TextureFormat.Rgba8unorm, usage));
	}

	static function texels(colours:Array<Array<Int>>):Bytes {
		var bytes = Bytes.alloc(colours.length * 4);
		for (i in 0...colours.length) for (c in 0...4) bytes.set(i * 4 + c, colours[i][c]);
		return bytes;
	}

	/**
		An 8x8 target cleared yellow. A first pass draws a 2x2 texture over it,
		each texel a 4x4 quadrant, through a viewport that is the left half.
		A second pass, begun from a descriptor that loads the first's pixels,
		draws an all-green texture through a 2x2 scissor at the bottom right.
	**/
	static function render(device:GpuDevice, queue:GpuQueue) {
		var red = [255, 0, 0, 255], green = [0, 255, 0, 255], blue = [0, 0, 255, 255];
		var white = [255, 255, 255, 255], yellow = [255, 255, 0, 255];
		var source = texture2d(device, 2, 2, TextureUsage.TEXTURE_BINDING | TextureUsage.COPY_DST);
		check(source.valid(), "a texture");
		queue.writeTexture(source, texels([red, green, blue, white]), 2, 2, 8);
		var plain = texture2d(device, 2, 2, TextureUsage.TEXTURE_BINDING | TextureUsage.COPY_DST);
		queue.writeTexture(plain, texels([green, green, green, green]), 2, 2, 8);
		var target = texture2d(device, 8, 8, TextureUsage.RENDER_ATTACHMENT | TextureUsage.COPY_SRC);

		var shader = device.createShader('
			@group(0) @binding(0) var source: texture_2d<f32>;
			@vertex
			fn vs(@builtin(vertex_index) i: u32) -> @builtin(position) vec4<f32> {
				let corner = vec2<f32>(f32((i << 1u) & 2u), f32(i & 2u));
				return vec4<f32>(corner * 2.0 - 1.0, 0.0, 1.0);
			}
			@fragment
			fn fs(@builtin(position) at: vec4<f32>) -> @location(0) vec4<f32> {
				return textureLoad(source, vec2<i32>(at.xy) / 4, 0);
			}
		');
		var builder = device.pipeline();
		builder.shader(shader, "vs", "fs");
		builder.target(TextureFormat.Rgba8unorm, ColorWrite.ALL);
		var pipeline = builder.build();
		check(pipeline.valid(), "a render pipeline");
		var groups = [for (texture in [source, plain]) {
			var bindings = new GpuBindings();
			bindings.texture(texture.createView(new GpuTextureViewDescriptor()));
			device.bindGroup(pipeline, 0, bindings);
		}];
		var view = target.createView(new GpuTextureViewDescriptor());

		var encoder = device.encoder();
		encoder.passColour(view, 1, 1, 0, 1);
		encoder.passBegin();
		encoder.renderSetPipeline(pipeline);
		encoder.renderSetBindGroup(0, groups[0]);
		encoder.renderSetViewport(0, 0, 4, 8, 0, 1);
		encoder.renderDraw(3, 1);
		encoder.renderEnd();

		var attachment = new GpuRenderPassColorAttachment(LoadOp.Load, StoreOp.Store);
		attachment.viewTextureView(view);
		attachment.clearValue(new GpuColor(0, 0, 0, 1));
		var pass = new GpuRenderPassDescriptor();
		pass.addColorAttachments(attachment);
		encoder.beginRenderPass(pass);
		encoder.renderSetPipeline(pipeline);
		encoder.renderSetBindGroup(0, groups[1]);
		encoder.renderSetScissorRect(6, 6, 2, 2);
		encoder.renderSetBlendConstant(0, 0, 0, 0);
		encoder.renderSetStencilReference(0);
		encoder.renderDraw(3, 1);
		encoder.renderEnd();

		// Rows of a texture-to-buffer copy are 256-byte aligned.
		var row = 256;
		var readback = device.createBuffer(new GpuBufferDescriptor(row * 8, BufferUsage.MAP_READ | BufferUsage.COPY_DST));
		encoder.copyTextureToBuffer(target, readback, 8, 8, row);
		encoder.submit(queue);
		var pixels = readBack(device, readback, row * 8);
		check(pixels != null, "the render target, read back");
		if (pixels != null) {
			var wrong = [];
			for (y in 0...8) for (x in 0...8) {
				var expected = if (x >= 6 && y >= 6) green else if (x >= 4) yellow else if (y < 4) red else blue;
				for (c in 0...4) if (pixels.get(y * row + x * 4 + c) != expected[c]) {
					wrong.push('($x,$y)');
					break;
				}
			}
			check(wrong.length == 0, "each pixel as drawn: texture, viewport, loaded pass, scissor" + (wrong.length > 0 ? "; wrong at " + wrong.join(" ") : ""));
		}

		var copy = texture2d(device, 2, 2, TextureUsage.COPY_SRC | TextureUsage.COPY_DST);
		var bytes = device.createBuffer(new GpuBufferDescriptor(512, BufferUsage.MAP_READ | BufferUsage.COPY_DST));
		var encoder = device.encoder();
		encoder.copyTextureToTexture(target, copy, 2, 2);
		encoder.copyTextureToBuffer(copy, bytes, 2, 2, 256);
		encoder.clearBuffer(bytes, 256, 256);
		encoder.submit(queue);
		var copied = readBack(device, bytes, 512);
		check(copied != null && copied.get(0) == 255 && copied.get(1) == 0 && copied.get(256) == 0,
			"a texture copied to a texture and a buffer, and a range cleared");

		for (group in groups) group.destroy();
		pipeline.destroy();
		shader.destroy();
		for (t in [source, plain, target, copy]) t.destroy();
		readback.destroy();
		bytes.destroy();
	}

	/** A raise caught by the program leaves the backend answering. **/
	static function caught(device:GpuDevice, queue:GpuQueue) {
		var target = texture2d(device, 4, 4, TextureUsage.RENDER_ATTACHMENT);
		var encoder = device.encoder();
		encoder.passColour(target.createView(new GpuTextureViewDescriptor()), 0, 0, 0, 1);
		encoder.passBegin();
		var threw = try {
			encoder.passBegin();
			false;
		} catch (e:Dynamic) true;
		check(threw, "beginning a second pass raises");
		encoder.renderEnd();
		encoder.submit(queue);
		check(device.queue().valid() && device.limit(Limit.MaxBindGroups) >= 4, "and the backend answers after it is caught");
		target.destroy();
	}

	/**
		A 2x2 texture sampled over an 8x8 target, inside an occlusion query,
		then the same draw recorded in a bundle and executed into another.
	**/
	static function sampled(device:GpuDevice, queue:GpuQueue) {
		var red = [255, 0, 0, 255], green = [0, 255, 0, 255], blue = [0, 0, 255, 255];
		var white = [255, 255, 255, 255];
		var usage = TextureUsage.TEXTURE_BINDING | TextureUsage.COPY_DST;
		var source = texture2d(device, 2, 2, usage);
		queue.writeTexture(source, texels([red, green, blue, white]), 2, 2, 8);
		check(source.width() == 2 && source.height() == 2 && source.depthOrArrayLayers() == 1 && source.mipLevelCount() == 1
			&& source.sampleCount() == 1 && source.dimension() == TextureDimension.D2d && source.format() == TextureFormat.Rgba8unorm
			&& source.usage() == usage, "a texture's attributes");
		var described = new GpuSamplerDescriptor();
		described.magFilter(FilterMode.Nearest);
		described.minFilter(FilterMode.Nearest);
		var sampler = device.sampler(described);
		check(sampler.valid(), "a sampler");

		var shader = device.createShader('
			@group(0) @binding(0) var source: texture_2d<f32>;
			@group(0) @binding(1) var nearest: sampler;
			@vertex
			fn vs(@builtin(vertex_index) i: u32) -> @builtin(position) vec4<f32> {
				let corner = vec2<f32>(f32((i << 1u) & 2u), f32(i & 2u));
				return vec4<f32>(corner * 2.0 - 1.0, 0.0, 1.0);
			}
			@fragment
			fn fs(@builtin(position) at: vec4<f32>) -> @location(0) vec4<f32> {
				return textureSample(source, nearest, at.xy / 8.0);
			}
		');
		var builder = device.pipeline();
		builder.shader(shader, "vs", "fs");
		builder.target(TextureFormat.Rgba8unorm, ColorWrite.ALL);
		var pipeline = builder.build();
		var bindings = new GpuBindings();
		bindings.texture(source.createView(new GpuTextureViewDescriptor()));
		bindings.sampler(sampler);
		var group = device.bindGroup(pipeline, 0, bindings);

		var queries = device.createQuerySet(new GpuQuerySetDescriptor(QueryType.Occlusion, 2));
		check(queries.count() == 2 && queries.queryType() == QueryType.Occlusion, "an occlusion query set");
		var targets = [for (_ in 0...2) texture2d(device, 8, 8, TextureUsage.RENDER_ATTACHMENT | TextureUsage.COPY_SRC)];

		var encoder = device.encoder();
		var attachment = new GpuRenderPassColorAttachment(LoadOp.Clear, StoreOp.Store);
		attachment.viewTexture(targets[0]);
		attachment.clearValue(new GpuColor(0, 0, 0, 1));
		var pass = new GpuRenderPassDescriptor();
		pass.addColorAttachments(attachment);
		pass.occlusionQuerySet(queries);
		encoder.beginRenderPass(pass);
		encoder.renderSetPipeline(pipeline);
		encoder.renderSetBindGroup(0, group);
		encoder.renderBeginOcclusionQuery(0);
		encoder.renderDraw(3, 1);
		encoder.renderEndOcclusionQuery();
		encoder.renderBeginOcclusionQuery(1);
		encoder.renderEndOcclusionQuery();
		encoder.renderEnd();

		var bundler = device.createRenderBundleEncoder({
			var d = new GpuRenderBundleEncoderDescriptor();
			d.addColorFormats(TextureFormat.Rgba8unorm);
			d;
		});
		bundler.setPipeline(pipeline);
		bundler.setBindGroup(0, group);
		bundler.draw(3, 1, 0, 0);
		var bundle = bundler.finish();
		check(bundle.valid(), "a render bundle");
		encoder.passColour(targets[1].createView(new GpuTextureViewDescriptor()), 0, 0, 0, 1);
		encoder.passBegin();
		encoder.renderExecuteBundle(bundle);
		encoder.renderEnd();

		var resolved = device.createBuffer(new GpuBufferDescriptor(16, BufferUsage.QUERY_RESOLVE | BufferUsage.COPY_SRC));
		var counts = device.createBuffer(new GpuBufferDescriptor(16, BufferUsage.MAP_READ | BufferUsage.COPY_DST));
		encoder.resolveQuerySet(queries, 0, 2, resolved, 0);
		encoder.copyBuffer(resolved, 0, counts, 0, 16);
		var row = 256;
		var readbacks = [for (_ in 0...2) device.createBuffer(new GpuBufferDescriptor(row * 8, BufferUsage.MAP_READ | BufferUsage.COPY_DST))];
		for (i in 0...2) encoder.copyTextureToBuffer(targets[i], readbacks[i], 8, 8, row);
		encoder.submit(queue);

		for (i in 0...2) {
			var pixels = readBack(device, readbacks[i], row * 8);
			var wrong = 0;
			if (pixels == null) wrong = 64 else for (y in 0...8) for (x in 0...8) {
				var expected = if (y < 4) (x < 4 ? red : green) else (x < 4 ? blue : white);
				for (c in 0...4) if (pixels.get(y * row + x * 4 + c) != expected[c]) {
					wrong++;
					break;
				}
			}
			check(wrong == 0, (i == 0 ? "sampled through a sampler" : "drawn by a bundle") + ', $wrong pixel(s) wrong');
		}
		var samples = readBack(device, counts, 16);
		check(samples != null && samples.getInt64(0) > 0 && samples.getInt64(8) == 0,
			"occlusion counts: " + (samples == null ? "none" : samples.getInt64(0) + ", " + samples.getInt64(8)));

		queries.destroy();
		check(!queries.valid(), "a destroyed query set");
		bundle.destroy();
		sampler.destroy();
		group.destroy();
		pipeline.destroy();
		shader.destroy();
		for (t in targets.concat([source])) t.destroy();
		for (b in readbacks.concat([resolved, counts])) b.destroy();
	}

	/** Bytes into a buffer mapped at creation, and into one mapped for writing. **/
	static function copyIn(device:GpuDevice, queue:GpuQueue) {
		var data = Bytes.alloc(16);
		for (i in 0...16) data.set(i, 200 - i);
		var described = new GpuBufferDescriptor(16, BufferUsage.COPY_SRC);
		described.mappedAtCreation(true);
		var created = device.createBuffer(described);
		check(created.copyIn(0, data, 16), "into a buffer mapped at creation");
		created.unmap();
		var writable = device.createBuffer(new GpuBufferDescriptor(16, BufferUsage.MAP_WRITE | BufferUsage.COPY_SRC));
		check(!writable.copyIn(0, data, 16), "not into one that is not mapped");
		device.mapBufferWith(writable, MapMode.WRITE, 0, 16).await();
		check(writable.copyIn(8, data, 8), "into a range mapped for writing");
		writable.unmap();
		var readback = device.createBuffer(new GpuBufferDescriptor(32, BufferUsage.MAP_READ | BufferUsage.COPY_DST));
		var encoder = device.encoder();
		encoder.copyBuffer(created, 0, readback, 0, 16);
		encoder.copyBuffer(writable, 8, readback, 16, 8);
		encoder.submit(queue);
		var out = readBack(device, readback, 32);
		var same = out != null;
		if (same) for (i in 0...16) if (out.get(i) != 200 - i) same = false;
		if (same) for (i in 0...8) if (out.get(16 + i) != 200 - i) same = false;
		check(same, "and back out as written");
		device.takeError();
		for (b in [created, writable, readback]) b.destroy();
	}

	/** A pipeline made asynchronously, one that fails, and a shader's messages. **/
	static function pipelines(device:GpuDevice) {
		var shader = device.createShader('
			@compute @workgroup_size(1)
			fn main() {}
		');
		var stage = new GpuProgrammableStage(shader);
		stage.entryPoint("main");
		var made = device.createComputePipelineAsync(new GpuComputePipelineDescriptor(stage)).await();
		check(made.valid() && made.getBindGroupLayout(0).valid(), "a compute pipeline made asynchronously");
		made.destroy();
		var wrong = new GpuProgrammableStage(shader);
		wrong.entryPoint("absent");
		var failed = try {
			device.createComputePipelineAsync(new GpuComputePipelineDescriptor(wrong)).await();
			false;
		} catch (e:Dynamic) {
			Sys.println("     rejected with: " + e);
			true;
		}
		check(failed, "one with no such entry point rejects");
		shader.destroy();

		device.pushErrorScope(ErrorFilter.Validation);
		var broken = device.createShader("\n\nfn main( {");
		device.popErrorScope().await();
		var first = broken.messages();
		check(first != null && StringTools.startsWith(first, "line 3: "), "a broken shader's messages, as lines: " + first);
		for (round in 0...2) {
			var info = broken.getCompilationInfo().await();
			var count = info.messageCount();
			check(count >= 1 && info.messageType(0) == CompilationMessageType.Error && info.lineNum(0) == 3 && info.message(0).length > 0,
				'compilation info, asked for ${round == 0 ? "once" : "again"}: $count message(s), the first '
				+ (count > 0 ? info.messageType(0) + " at " + info.lineNum(0) + ":" + info.linePos(0) + ", " + info.message(0) : "missing"));
			info.destroy();
		}
		check(broken.messages() == first, "and as lines again");
		broken.destroy();
	}

	static function errors(device:GpuDevice) {
		// Mapping for both reading and writing is invalid.
		function invalidBuffer() {
			device.createBuffer(new GpuBufferDescriptor(16, BufferUsage.MAP_READ | BufferUsage.MAP_WRITE));
		}

		device.pushErrorScope(ErrorFilter.Validation);
		invalidBuffer();
		var error:GpuError = device.popErrorScope().await();
		check(error.valid(), "a validation error scope catches an invalid buffer");
		if (error.valid()) {
			check(error.filter() == ErrorFilter.Validation, "its filter is the scope's");
			var message = error.message();
			check(message != null && message.length > 0, "its message: " + message);
			error.destroy();
		}

		device.pushErrorScope(ErrorFilter.OutOfMemory);
		device.pushErrorScope(ErrorFilter.Validation);
		var nothing:GpuError = device.popErrorScope().await();
		check(!nothing.valid(), "a scope over nothing wrong pops null");
		invalidBuffer();
		var oom:GpuError = device.popErrorScope().await();
		check(!oom.valid(), "an out-of-memory scope lets a validation error through");
		var passed = device.takeError();
		check(passed != null, "which takeError reports: " + passed);
		check(device.takeError() == null, "once");

		var empty = try {
			device.popErrorScope().await();
			false;
		} catch (e:Dynamic) true;
		check(empty, "popping with no scope pushed rejects");

		// Not MAP_READ: the browser rejects the map.
		var unmappable = device.createBuffer(new GpuBufferDescriptor(16, BufferUsage.COPY_DST));
		var rejected = try {
			device.mapBufferWith(unmappable, MapMode.READ, 0, 16).await();
			false;
		} catch (e:Dynamic) {
			Sys.println("     rejected with: " + e);
			true;
		}
		check(rejected, "a map the browser refuses rejects its future");
		device.takeError();
		unmappable.destroy();
	}
}
