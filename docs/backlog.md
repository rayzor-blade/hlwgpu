# What is done and what is next

`docs/design.md` is why the library is built the way it is. This is where it
has got to.

## Done

Native first throughout. A desktop library that works is worth more than two
halves that do not.

| | |
|---|---|
| **The seam** | `wgpu.api`, the generator, and an adapter reporting its name, backend and limits |
| **Compute** | buffer upload, a WGSL kernel, dispatch, and a polled readback checked value by value |
| **Offscreen render** | vertex buffers, a render pipeline, a pass into a texture, pixels checked exactly |
| **Textured drawing** | samplers, texture upload, index buffers, and bind groups holding buffers, views and samplers together |
| **Presentation** | a surface on a native window, drawn and presented every frame |
| **Capability** | blending, depth, stencil, viewport, scissor, instancing, multiple colour targets, indirect draws, the missing copies, and errors that report instead of killing the process |

Fourteen tests, all asserting exact bytes, run in CI under ash and under
upstream HashLink on lavapipe.

**50 of 66 WebGPU operations.** `crates/hlwgpu/spec/webgpu.idl` is the
checklist; `crates/hlwgpu/spec/README.md` has the current count.

## Next

**The browser half has never run.** It is generated, it links, and it has the
right imports and exports. Nothing has executed it in a page. That needs a
host to supply the imports and a browser to check it in.

Milestones 1 to 4 should then run unchanged against `navigator.gpu`. If any of
it needs a Haxe-side `#if`, something in the design went wrong.

## Backlog

**Operations, in the order they are likely to be missed.**

- Query sets, timestamps and occlusion. Profiling.
- Explicit bind group and pipeline layouts. Sharing a bind group between
  pipelines.
- Render bundles. Recording a run of draws once and replaying it.
- Async pipeline creation. Avoiding a hitch that can already be measured.

None of these blocks a renderer.

**Six operations cannot be done natively at all.** `importExternalTexture`,
`copyExternalImageToTexture`, `getConfiguration` and `unconfigure` are browser
concepts with no wgpu counterpart. Two `constructor` entries are error types
rather than methods. Adding them would break the rule that no primitive works
on one target only.

**Lifetime helpers.** Nothing tracks what a program forgot to destroy. A
scope object that destroys what was registered with it, and a debug-build
count of live handles per kind, would both help. `Slab::live` already counts
them; no primitive exposes it.

**Housekeeping.**

- The declaration parser splits strings by hand. That is fine for `prim` and
  `js` lines and will not stay fine once descriptors grow. Use nom or pest.
- `haxelib.json` has a version nothing sets. The release workflow does not
  read it, so a tag and the manifest can disagree.
- The wasm side module is 799 KB and almost all of it is std, for a module
  that holds no implementation. Making `hl_abi` `no_std` would cut most of it.

## Not planned

hxsl translation, a Heaps driver, SPIR-V ingestion, and ray queries. Each is
its own piece of work and none of it belongs in this library.
