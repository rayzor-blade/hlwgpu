package wgpu;

/** A pipeline with somewhere to draw, so it can be built. **/
abstract PipelineTargets(Int) from Int to Int {
	/** Blends the target opened last, alpha the same as colour. **/
	public inline function blend(src : BlendFactor, dst : BlendFactor, op : BlendOperation = Add) : PipelineTargets {
		_Native.pipeline_blend(this, src, dst, op, src, dst, op);
		return this;
	}

	/** Blends it with alpha treated differently from colour. **/
	public inline function blendSeparate(src : BlendFactor, dst : BlendFactor, op : BlendOperation, srcAlpha : BlendFactor,
			dstAlpha : BlendFactor, opAlpha : BlendOperation) : PipelineTargets {
		_Native.pipeline_blend(this, src, dst, op, srcAlpha, dstAlpha, opAlpha);
		return this;
	}

	public inline function target(format : TextureFormat, writeMask = 0xF) : PipelineTargets {
		_Native.pipeline_target(this, format, writeMask);
		return this;
	}

	public inline function depth(format : TextureFormat, write = true, compare : CompareFunction = Less) : PipelineTargets {
		_Native.pipeline_depth(this, format, write, compare);
		return this;
	}

	/** How the stencil test behaves, for both faces. **/
	public inline function stencil(compare : CompareFunction, fail : StencilOperation = Keep,
			depthFail : StencilOperation = Keep, pass : StencilOperation = Keep, readMask = 0xFF,
			writeMask = 0xFF) : PipelineTargets {
		_Native.pipeline_stencil(this, compare, fail, depthFail, pass, readMask, writeMask);
		return this;
	}

	public inline function primitive(topology : PrimitiveTopology = TriangleList, cull : CullMode = None,
			front : FrontFace = Ccw) : PipelineTargets {
		_Native.pipeline_primitive(this, topology, cull, front);
		return this;
	}

	public inline function build() : RenderPipeline {
		return _Native.render_pipeline_build(this);
	}
}
