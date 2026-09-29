# Browser side-module host contract

`xgpu.wasm` is a position-independent WebAssembly side module. The runtime
loads it into the program's shared memory and table; it is not a standalone
module for `WebAssembly.instantiate`.

The dylink loader supplies `memory`, `__indirect_function_table`,
`__stack_pointer`, `__memory_base`, `__table_base`, and the relocation globals
under `GOT.func` and `GOT.mem`.

The runtime also supplies HashLink's allocation, rooting, type, string, and
exception ABI; Ash Future's `hlp_future_create`, `hlp_future_resolve`, and
`hlp_future_reject`; the ordinary WASI libc imports used by Rust; and these
browser hooks:

- `ash_host_agent(name, name_len, address)` starts the named browser agent for
  the mailbox at `address`. The GPU adapter asks for the `gpu` agent.
- `ash_host_watch(word, handler, context)` attaches the mailbox completion word
  to the runtime's fiber scheduler and calls `handler(context)` when it changes.

The release bundle provides:

- `hlwgpu.js`, a runtime-neutral entry exposing the `xgpu.wasm` URL and a
  `loadXgpu(loader, options)` helper;
- `gpu-agent.mjs`, xgpu's generated WebGPU mailbox service;
- `gpu.mjs` and `gpu-worker.mjs`, Ash's page and Worker harness.

A non-Ash runtime implements the same side-module and host ABI contracts and
may drive `gpu-agent.mjs` through its own page and Worker lifecycle. The host
must use shared WebAssembly memory and serve the page with the isolation
headers required by `SharedArrayBuffer`.
