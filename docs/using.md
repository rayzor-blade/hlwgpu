# Using hlwgpu

## Install the native package

hlwgpu depends on `ash-future` for `ash.Future<T>`. Neither is on
lib.haxe.org, so install both from their GitHub releases: `ash-future-<version>.zip`
from [Ash](https://github.com/rayzor-blade/ash/releases), then
`hlwgpu-<version>.zip` from this project's. `--skip-dependencies` stops
Haxelib looking `ash-future` up on lib.haxe.org:

```sh
haxelib install ash-future-<version>.zip
haxelib install --skip-dependencies hlwgpu-<version>.zip
```

Compile with `-lib hlwgpu`, which brings in `ash-future`. The package carries `xgpu.hdll` for every desktop
platform, and its `extraParams.hxml` copies the host's beside the generated
HashLink program. `-D hlwgpu_vulkan` stages the Windows build that carries
Vulkan beside D3D12. `-D hlwgpu_no_hdll` stages nothing, for a program that
supplies its own `xgpu.hdll`; a source checkout has none, so `-lib hlwgpu` on
one needs that define.

The library is named `xgpu` at the HashLink boundary, which matches the
`@:hlNative("xgpu", ...)` declarations in the generated `gpu` package.

Ash provides the `ash.Future<T>` implementation used by asynchronous methods.
On stock HashLink, compile with `-D ash_future_stock` as well, so `ash-future`
stages its `ash_future.hdll`; `xgpu.hdll` needs that native ABI loaded first.

## Request a device

```haxe
var instance = new gpu.GpuInstance();
var adapter = instance.requestAdapter(gpu.Power.HighPerformance).await();
var device = adapter.requestDevice().await();
var queue = device.queue();
```

Use `requestAdapterWith()` and `requestDeviceWith()` when you need explicit
feature, limit, surface, or fallback-adapter selection.

## Asynchronous work

Methods whose WebGPU counterpart returns a Promise return `ash.Future<T>`.
Examples include adapter and device requests, buffer mapping, submitted-work
completion, async pipeline creation, device loss, and error-scope results.

`await()` parks the current Ash fiber until completion. `then(onValue,
onError)` schedules a continuation when blocking the current control flow is
undesirable. Rejections are raised by `await()` and delivered to `onError` by
`then()`.

## Resource lifetime

Call `destroy()` on GPU resources that expose it. Driver allocations can be
much larger than their Haxe handles, so waiting for language-heap pressure is
not a useful GPU-memory policy. Destroying a handle invalidates it and stale
uses are rejected by xgpu's generational handle table.

Descriptor and record objects are HashLink-managed values used while building
calls. They do not own the GPU resource returned by a call.

## Data transfer

Buffer payloads use Haxe bytes through the HashLink ABI. `copyIn()` and
`copyOut()` move data between mapped GPU memory and an existing Haxe byte
buffer; they do not require a second language-side wrapper for the GPU object.
Observe WebGPU's alignment rules for mapping and texture rows.

## Coordinates

hlwgpu follows WebGPU coordinates:

- clip-space depth is 0 to 1;
- clip-space positive Y points up;
- the first texture row is the top row.

Code written for OpenGL commonly needs its depth projection or texture Y
coordinate adjusted.

## Browser Wasm

Application code keeps the same `gpu` API, but the host runtime performs the
integration. It must load `xgpu.wasm` as a dylink side module, supply shared
memory and the HashLink/Ash ABIs, and start the generated WebGPU mailbox agent.

The release includes `hlwgpu.js` for locating and handing the side module to a
runtime loader, `gpu-agent.mjs` for the generated browser service, and
`gpu.mjs` plus `gpu-worker.mjs` for Ash. See
[`crates/hlwgpu/IMPORTS.md`](../crates/hlwgpu/IMPORTS.md) for the complete host
contract.
