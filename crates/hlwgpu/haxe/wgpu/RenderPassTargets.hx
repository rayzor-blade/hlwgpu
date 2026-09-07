package wgpu;

/** A render pass with somewhere to draw, so it can be opened. **/
abstract RenderPassTargets(Int) from Int to Int {
	public inline function colour(target : TextureView, r : Float, g : Float, b : Float, a = 1.0) : RenderPassTargets {
		_Native.pass_colour(this, target, r, g, b, a);
		return this;
	}

	/**
		Somewhere to keep depth, and stencil if the format has one.

		Leave `stencilClear` alone for a depth-only format. A format that has
		a stencil must be given one, or the pass is refused.
	**/
	public inline function depth(target : TextureView, clear = 1.0, stencilClear = -1) : RenderPassTargets {
		_Native.pass_depth(this, target, clear, stencilClear);
		return this;
	}

	public inline function begin() : Void {
		_Native.pass_begin(this);
	}
}
