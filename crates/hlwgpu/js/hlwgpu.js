// Runtime-neutral entry point for the browser bundle.
// xgpu.wasm is a position-independent side module, so a host runtime supplies
// its own dylink loader and the ABI imports documented in IMPORTS.md.

export const xgpuWasm = new URL("./xgpu.wasm", import.meta.url);

/** Load xgpu.wasm with a runtime's side-module loader. */
export function loadXgpu(loadSideModule, options = {}) {
  if (typeof loadSideModule !== "function") {
    throw new TypeError("loadXgpu requires a WebAssembly side-module loader");
  }
  return loadSideModule(xgpuWasm, options);
}

// Ash uses this page shim to transfer the canvas to xgpu's worker. Other
// runtimes may use the generated agent exports with their own harness.
export { start as startAshAgent } from "./gpu.mjs";
export * as gpuAgent from "./gpu-agent.mjs";
