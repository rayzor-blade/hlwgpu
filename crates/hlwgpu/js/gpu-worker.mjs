// Runtime-specific roots for xgpu's generated, runtime-neutral worker service.

import { start } from "./gpu-agent.mjs";

start(async ({ canvas }) => {
  if (!navigator.gpu) throw new Error("this browser exposes no WebGPU");
  const context = canvas.getContext("webgpu");
  if (!context) throw new Error("the Ash canvas has no WebGPU context");
  return new Map([
    [1, navigator.gpu],
    [2, context],
    [3, canvas],
  ]);
});
