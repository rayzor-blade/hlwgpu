package wgpu;

/** A compiled WGSL module. **/
abstract Shader(Int) from Int to Int {
	public var ok(get, never) : Bool;

	inline function get_ok() : Bool {
		return this != 0;
	}

	/**
		What the shader compiler said, or null if it said nothing.

		`Device.takeError` reports that a shader was wrong; this says where.
	**/
	public function messages() : String {
		var text = _Native.shader_messages(this);
		return text == null ? null : @:privateAccess String.fromUCS2(text);
	}

	public inline function destroy() : Void {
		_Native.shader_destroy(this);
		this = 0;
	}
}
