// GENERATED from `spec/webgpu.idl` via `wgpu.api`. Edit neither.

package wgpu;

/** `StencilOperation` from the WebGPU IDL: its values, in its order. **/
enum abstract StencilOperation(Int) from Int to Int {
	var Keep = 0;
	var Zero = 1;
	var Replace = 2;
	var Invert = 3;
	var IncrementClamp = 4;
	var DecrementClamp = 5;
	var IncrementWrap = 6;
	var DecrementWrap = 7;
}
