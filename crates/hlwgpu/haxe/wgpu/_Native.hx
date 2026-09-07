// GENERATED from `wgpu.api`. Edit the declaration, not this file.

package wgpu;

/**
	The primitives, one to one. A program is not meant to call these:
	the classes beside them are the API. `wgpu.hdll` implements them
	natively; on wasm a host does.
**/
@:keep
class _Native {
	// The entry point. Natively this is a wgpu Instance; in a page it is
	// `navigator.gpu` itself, which is why a page with WebGPU disabled returns 0
	// here rather than failing later with something less obvious.
	@:hlNative("wgpu", "wgpu_instance_create")
	public static function instance_create() : Int {
		return 0;
	}

	@:hlNative("wgpu", "wgpu_instance_destroy")
	public static function instance_destroy(inst : Int) : Void {
		return;
	}

	// Returns a request id, not an adapter. `requestAdapter` is a promise in a
	// page and nothing may block on it, so async work is started here and
	// collected through `request_ready` / `request_result`. Natively it resolves
	// before this returns; the id exists anyway, so both look the same.
	// 
	// `power` is 0 for low-power and 1 for high-performance.
	@:hlNative("wgpu", "wgpu_adapter_request")
	public static function adapter_request(inst : Int, power : Int) : Int {
		return 0;
	}

	@:hlNative("wgpu", "wgpu_request_ready")
	public static function request_ready(request : Int) : Bool {
		return false;
	}

	// Only meaningful once `request_ready` is true. Reading early raises rather
	// than answering zero, so a caller that polls wrongly finds out here.
	@:hlNative("wgpu", "wgpu_request_result")
	public static function request_result(request : Int) : Int {
		return 0;
	}

	// UTF-16 and NUL-terminated, which is what `String.fromUCS2` expects.
	@:hlNative("wgpu", "wgpu_adapter_name")
	public static function adapter_name(adapter : Int) : hl.Bytes {
		return null;
	}

	// 0 unknown, 1 vulkan, 2 metal, 3 dx12, 4 gl, 5 webgpu.
	@:hlNative("wgpu", "wgpu_adapter_backend")
	public static function adapter_backend(adapter : Int) : Int {
		return 0;
	}

	// One limit by index, so that adding a limit does not add a primitive. The
	// indices are declared once, in Haxe, as `wgpu.Limit`.
	@:hlNative("wgpu", "wgpu_adapter_limit")
	public static function adapter_limit(adapter : Int, which : Int) : Int {
		return 0;
	}

	@:hlNative("wgpu", "wgpu_adapter_destroy")
	public static function adapter_destroy(adapter : Int) : Void {
		return;
	}

	// The queue comes back with the device, so `device_queue` needs no request of
	// its own.
	@:hlNative("wgpu", "wgpu_device_request")
	public static function device_request(adapter : Int) : Int {
		return 0;
	}

	// The oldest error this device has reported and not yet been asked about, or
	// null. A validation mistake is a message here rather than a dead process:
	// a bad shader, a format the surface does not have, a buffer used for
	// something it was not created for.
	@:hlNative("wgpu", "wgpu_device_take_error")
	public static function device_take_error(device : Int) : hl.Bytes {
		return null;
	}

	@:hlNative("wgpu", "wgpu_device_queue")
	public static function device_queue(device : Int) : Int {
		return 0;
	}

	// Lets finished work report itself. A page does this from the event loop, so
	// there is nothing to do there.
	@:hlNative("wgpu", "wgpu_device_poll")
	public static function device_poll(device : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_device_destroy")
	public static function device_destroy(device : Int) : Void {
		return;
	}

	// `usage` is WebGPU's GPUBufferUsage bitmask, which wgpu numbers identically:
	// 1 MAP_READ, 2 MAP_WRITE, 4 COPY_SRC, 8 COPY_DST, 128 STORAGE.
	@:hlNative("wgpu", "wgpu_buffer_create")
	public static function buffer_create(device : Int, size : Int, usage : Int) : Int {
		return 0;
	}

	@:hlNative("wgpu", "wgpu_queue_write_buffer")
	public static function queue_write_buffer(queue : Int, buffer : Int, offset : Int, data : hl.Bytes, len : Int) : Void {
		return;
	}

	// Starts a read mapping. Poll it with `request_ready`, then `buffer_copy_out`.
	@:hlNative("wgpu", "wgpu_buffer_map_begin")
	public static function buffer_map_begin(device : Int, buffer : Int, offset : Int, size : Int) : Int {
		return 0;
	}

	// Copies from a mapped buffer into `out`. False if it was not mapped.
	@:hlNative("wgpu", "wgpu_buffer_copy_out")
	public static function buffer_copy_out(buffer : Int, offset : Int, out : hl.Bytes, len : Int) : Bool {
		return false;
	}

	@:hlNative("wgpu", "wgpu_buffer_unmap")
	public static function buffer_unmap(buffer : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_buffer_destroy")
	public static function buffer_destroy(buffer : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_shader_create")
	public static function shader_create(device : Int, wgsl : hl.Bytes) : Int {
		return 0;
	}

	@:hlNative("wgpu", "wgpu_shader_destroy")
	public static function shader_destroy(shader : Int) : Void {
		return;
	}

	// Layout is inferred from the shader, so a bind group only needs its buffers.
	@:hlNative("wgpu", "wgpu_compute_pipeline_create")
	public static function compute_pipeline_create(device : Int, shader : Int, entry : hl.Bytes) : Int {
		return 0;
	}

	@:hlNative("wgpu", "wgpu_pipeline_destroy")
	public static function pipeline_destroy(pipeline : Int) : Void {
		return;
	}

	// `bound` is `count` handles, one per binding, in binding order. Each may be a
	// buffer, a texture view or a sampler: a handle carries its own kind, so what
	// it binds as does not have to be said twice.
	// 
	// The pipeline may be a compute or a render one.
	@:hlNative("wgpu", "wgpu_bind_group_create")
	public static function bind_group_create(device : Int, pipeline : Int, group : Int, bound : hl.Bytes, count : Int) : Int {
		return 0;
	}

	@:hlNative("wgpu", "wgpu_bind_group_destroy")
	public static function bind_group_destroy(bindgroup : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_encoder_create")
	public static function encoder_create(device : Int) : Int {
		return 0;
	}

	// A whole compute pass: one pipeline, one bind group, one dispatch. Passes
	// with several dispatches get their own primitives when something needs them.
	@:hlNative("wgpu", "wgpu_encoder_compute")
	public static function encoder_compute(encoder : Int, pipeline : Int, bindgroup : Int, x : Int, y : Int, z : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_encoder_copy_buffer")
	public static function encoder_copy_buffer(encoder : Int, src : Int, src_offset : Int, dst : Int, dst_offset : Int, size : Int) : Void {
		return;
	}

	// Finishes the encoder and submits it. The encoder is spent afterwards.
	@:hlNative("wgpu", "wgpu_encoder_submit")
	public static function encoder_submit(encoder : Int, queue : Int) : Void {
		return;
	}

	// Finishes when everything submitted so far has run. Takes the device because
	// natively the callback fires only when one is polled, and polling is what
	// `request_ready` does while waiting.
	@:hlNative("wgpu", "wgpu_queue_work_done")
	public static function queue_work_done(device : Int, queue : Int) : Int {
		return 0;
	}

	// `format` is `wgpu.TextureFormat`; `usage` is GPUTextureUsage's bits:
	// 1 COPY_SRC, 2 COPY_DST, 4 TEXTURE_BINDING, 8 STORAGE_BINDING,
	// 16 RENDER_ATTACHMENT.
	@:hlNative("wgpu", "wgpu_texture_create")
	public static function texture_create(device : Int, width : Int, height : Int, format : Int, usage : Int) : Int {
		return 0;
	}

	@:hlNative("wgpu", "wgpu_texture_view")
	public static function texture_view(texture : Int) : Int {
		return 0;
	}

	@:hlNative("wgpu", "wgpu_texture_destroy")
	public static function texture_destroy(texture : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_view_destroy")
	public static function view_destroy(view : Int) : Void {
		return;
	}

	// A render pipeline is built by a run of calls rather than one descriptor:
	// every argument stays a typed scalar the compiler checks, and there is no
	// packed layout for the two sides to disagree about. The crossings cost
	// nothing, because a pipeline is built at load and not per frame.
	@:hlNative("wgpu", "wgpu_pipeline_begin")
	public static function pipeline_begin(device : Int) : Int {
		return 0;
	}

	@:hlNative("wgpu", "wgpu_pipeline_shader")
	public static function pipeline_shader(builder : Int, shader : Int, vs : hl.Bytes, fs : hl.Bytes) : Void {
		return;
	}

	// Opens a vertex buffer layout; the attributes that follow belong to it.
	// A stride of 0 means "as wide as the attributes turn out to be", worked out
	// when the pipeline is built.
	@:hlNative("wgpu", "wgpu_pipeline_vertex_buffer")
	public static function pipeline_vertex_buffer(builder : Int, stride : Int, step : Int) : Void {
		return;
	}

	// Appends an attribute packed against the one before it, at the next free
	// shader location. What a vertex layout almost always is, and one fewer pair
	// of numbers to get wrong.
	@:hlNative("wgpu", "wgpu_pipeline_attribute_packed")
	public static function pipeline_attribute_packed(builder : Int, format : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_pipeline_attribute")
	public static function pipeline_attribute(builder : Int, format : Int, offset : Int, location : Int) : Void {
		return;
	}

	// Opens a colour target; a blend that follows belongs to it.
	@:hlNative("wgpu", "wgpu_pipeline_target")
	public static function pipeline_target(builder : Int, format : Int, write_mask : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_pipeline_blend")
	public static function pipeline_blend(builder : Int, src : Int, dst : Int, op : Int, src_alpha : Int, dst_alpha : Int, op_alpha : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_pipeline_depth")
	public static function pipeline_depth(builder : Int, format : Int, write : Bool, compare : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_pipeline_primitive")
	public static function pipeline_primitive(builder : Int, topology : Int, cull : Int, front : Int) : Void {
		return;
	}

	// Builds the pipeline and spends the builder.
	@:hlNative("wgpu", "wgpu_render_pipeline_build")
	public static function render_pipeline_build(builder : Int) : Int {
		return 0;
	}

	@:hlNative("wgpu", "wgpu_render_pipeline_destroy")
	public static function render_pipeline_destroy(pipeline : Int) : Void {
		return;
	}

	// A pass is described before it is opened, because it can have more than one
	// colour target and may or may not have depth. `pass_reset` starts describing,
	// `pass_begin` opens what was described.
	@:hlNative("wgpu", "wgpu_pass_reset")
	public static function pass_reset(encoder : Int) : Void {
		return;
	}

	// Adds a colour target and what to clear it to. Their order is the order the
	// fragment shader's `@location`s are numbered in.
	@:hlNative("wgpu", "wgpu_pass_colour")
	public static function pass_colour(encoder : Int, view : Int, r : Float, g : Float, b : Float, a : Float) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_pass_depth")
	public static function pass_depth(encoder : Int, view : Int, clear : Float) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_pass_begin")
	public static function pass_begin(encoder : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_render_set_pipeline")
	public static function render_set_pipeline(encoder : Int, pipeline : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_render_set_vertex_buffer")
	public static function render_set_vertex_buffer(encoder : Int, slot : Int, buffer : Int) : Void {
		return;
	}

	// Where in the target the clip space -1..1 lands, and what depth range it
	// maps onto.
	@:hlNative("wgpu", "wgpu_render_set_viewport")
	public static function render_set_viewport(encoder : Int, x : Float, y : Float, width : Float, height : Float, min_depth : Float, max_depth : Float) : Void {
		return;
	}

	// Throws away anything drawn outside this rectangle. Unlike a viewport it
	// does not squeeze what is drawn, it cuts it.
	@:hlNative("wgpu", "wgpu_render_set_scissor_rect")
	public static function render_set_scissor_rect(encoder : Int, x : Int, y : Int, width : Int, height : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_render_draw")
	public static function render_draw(encoder : Int, vertices : Int, instances : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_encoder_render_end")
	public static function encoder_render_end(encoder : Int) : Void {
		return;
	}

	// The other direction. `bytes_per_row` is a multiple of 256 here too.
	@:hlNative("wgpu", "wgpu_encoder_copy_buffer_to_texture")
	public static function encoder_copy_buffer_to_texture(encoder : Int, buffer : Int, bytes_per_row : Int, texture : Int, width : Int, height : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_encoder_copy_texture_to_texture")
	public static function encoder_copy_texture_to_texture(encoder : Int, src : Int, dst : Int, width : Int, height : Int) : Void {
		return;
	}

	// Zeroes a range of a buffer without uploading zeroes to it.
	@:hlNative("wgpu", "wgpu_encoder_clear_buffer")
	public static function encoder_clear_buffer(encoder : Int, buffer : Int, offset : Int, size : Int) : Void {
		return;
	}

	// `bytes_per_row` must be a multiple of 256, which is WebGPU's rule and not
	// ours: a width of 64 RGBA pixels is exactly one row.
	@:hlNative("wgpu", "wgpu_encoder_copy_texture_to_buffer")
	public static function encoder_copy_texture_to_buffer(encoder : Int, texture : Int, buffer : Int, width : Int, height : Int, bytes_per_row : Int) : Void {
		return;
	}

	// `filter` is 0 nearest, 1 linear. `address` is 0 clamp-to-edge, 1 repeat.
	@:hlNative("wgpu", "wgpu_sampler_create")
	public static function sampler_create(device : Int, filter : Int, address : Int) : Int {
		return 0;
	}

	@:hlNative("wgpu", "wgpu_sampler_destroy")
	public static function sampler_destroy(sampler : Int) : Void {
		return;
	}

	// Unlike a copy out of a texture, this has no row alignment to honour.
	@:hlNative("wgpu", "wgpu_queue_write_texture")
	public static function queue_write_texture(queue : Int, texture : Int, data : hl.Bytes, width : Int, height : Int, bytes_per_row : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_render_set_bind_group")
	public static function render_set_bind_group(encoder : Int, group : Int, bindgroup : Int) : Void {
		return;
	}

	// `format` is 0 for uint16 and 1 for uint32.
	@:hlNative("wgpu", "wgpu_render_set_index_buffer")
	public static function render_set_index_buffer(encoder : Int, buffer : Int, format : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_render_draw_indexed")
	public static function render_draw_indexed(encoder : Int, indices : Int, instances : Int) : Void {
		return;
	}

	// A surface on a native window, from the raw handle fields `hlwindow` reports.
	// Integers because the two libraries are separate: a Rust type cannot cross
	// between them, the pointer inside it can.
	// 
	// A page has no such thing -- its surface comes from a canvas it already owns.
	@:hlNative("wgpu", "wgpu_surface_create")
	public static function surface_create(instance : Int, platform : Int, wa : haxe.Int64, wb : haxe.Int64, da : haxe.Int64, db : haxe.Int64) : Int {
		return 0;
	}

	// What this surface would rather be configured as, as a `wgpu.TextureFormat`.
	@:hlNative("wgpu", "wgpu_surface_preferred_format")
	public static function surface_preferred_format(surface : Int, adapter : Int) : Int {
		return 0;
	}

	@:hlNative("wgpu", "wgpu_surface_configure")
	public static function surface_configure(device : Int, surface : Int, width : Int, height : Int, format : Int) : Void {
		return;
	}

	// The view to draw this frame into, or 0 if the surface needs configuring
	// again -- which is what a resize looks like from here.
	@:hlNative("wgpu", "wgpu_surface_acquire")
	public static function surface_acquire(surface : Int) : Int {
		return 0;
	}

	// Hands the frame over, after the work drawing it has been submitted. A page
	// presents at the end of its task, so this only releases the view there.
	@:hlNative("wgpu", "wgpu_surface_present")
	public static function surface_present(queue : Int, surface : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_surface_destroy")
	public static function surface_destroy(surface : Int) : Void {
		return;
	}

	// The colour a `Constant` or `OneMinusConstant` blend factor refers to.
	@:hlNative("wgpu", "wgpu_render_set_blend_constant")
	public static function render_set_blend_constant(encoder : Int, r : Float, g : Float, b : Float, a : Float) : Void {
		return;
	}

	// Takes the vertex count, instance count and first indices from a buffer
	// rather than from here, so work the GPU produced can be drawn without
	// reading it back first. Four `u32` at `offset`.
	@:hlNative("wgpu", "wgpu_render_draw_indirect")
	public static function render_draw_indirect(encoder : Int, buffer : Int, offset : Int) : Void {
		return;
	}

	// The same for indexed drawing. Five `u32` at `offset`.
	@:hlNative("wgpu", "wgpu_render_draw_indexed_indirect")
	public static function render_draw_indexed_indirect(encoder : Int, buffer : Int, offset : Int) : Void {
		return;
	}

	// What a frame capture shows instead of a list of anonymous draws. Nothing
	// reads these at run time.
	@:hlNative("wgpu", "wgpu_encoder_push_debug_group")
	public static function encoder_push_debug_group(encoder : Int, label : hl.Bytes) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_encoder_pop_debug_group")
	public static function encoder_pop_debug_group(encoder : Int) : Void {
		return;
	}

	@:hlNative("wgpu", "wgpu_encoder_insert_debug_marker")
	public static function encoder_insert_debug_marker(encoder : Int, label : hl.Bytes) : Void {
		return;
	}

}
