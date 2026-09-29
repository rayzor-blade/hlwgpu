# Using hlwgpu

## Install the native package

Download `hlwgpu-hdll-<platform>` from the project's GitHub Releases page,
unpack it, and register the directory with Haxelib:

```sh
haxelib dev hlwgpu /path/to/unpacked/hlwgpu
```

Compile with `-lib hlwgpu` and place `xgpu.hdll` beside the resulting HashLink
program. The library is named `xgpu` at the HashLink boundary, which matches
the `@:hlNative("xgpu", ...)` declarations in the generated `gpu` package.

Ash provides the `ash.Future<T>` implementation used by asynchronous methods.
Another HashLink host must provide the same Ash Future native ABI before it
loads `xgpu.hdll`.

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
