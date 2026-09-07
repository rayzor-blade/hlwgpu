# Using hlwgpu

Three things behave differently from what you may expect, and each of them is
quiet about it: coordinates are WebGPU's rather than OpenGL's, nothing is freed
for you, and no call in this library blocks.

## Coordinates

WebGPU's coordinates are not OpenGL's. These are the two differences that catch
people out:

- Clip space has +y pointing up, but the first row of a texture is the top row.
  So geometry at +y comes back near the start of a readback buffer, and texture
  coordinates start at the top left corner.
- Depth runs from 0 to 1, not from -1 to 1. A vertex at z = -0.5 is behind the
  near plane, so it is clipped away rather than drawn in front of everything.

`crates/hlwgpu/test/Conventions.hx` checks both, because a symmetric test
cannot.

## House keeping

Call `destroy()` on anything that has it. Buffers, textures and pipelines are
not freed when they go out of scope, so anything you do not destroy holds its
GPU memory until the process exits. Destroying something twice is safe.

## Waiting

Nothing in this library blocks. Anything that takes time gives you a `Request`
instead: check `ready` whenever you like, or call `await()` to wait for the
result. `await()` yields between checks rather than spinning, so your other
threads keep running while the GPU works.
