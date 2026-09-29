# Legacy WebGPU IDL snapshot

This copy of `webgpu.idl` was fetched from the official WebGPU specification
on 2026-09-07. It remains only because the legacy `wgpu.api` generator reads a
small enum subset while that implementation is being retired.

It is not hlwgpu's public API checklist and its old operation, dictionary, and
enum coverage counts are no longer meaningful. The canonical WebGPU IDL,
generated API, coverage work, and native extension catalog live in
[xgpu](https://github.com/rayzor-blade/xgpu).

Use the official [WebGPU specification](https://www.w3.org/TR/webgpu/) as the
portable API reference. Do not add new public bindings here; update xgpu and
then refresh hlwgpu's generated `haxe/gpu` package by advancing the pinned
xgpu revision.
