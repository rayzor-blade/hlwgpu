// Runtime-specific roots for xgpu's generated, runtime-neutral worker service.

import { start } from "./gpu-agent.mjs";

// A device the browser takes back, as when the GPU process crashes or hangs, leaves the canvas as it was and draws
// nothing more. It is said on the console and passed to the page, which can show it.
const requestDevice = GPUAdapter.prototype.requestDevice;
GPUAdapter.prototype.requestDevice = async function (...args) {
  const device = await requestDevice.apply(this, args);
  device.lost.then((info) => {
    if (info.reason === "destroyed") return;
    console.error(`xgpu: the GPU device was lost (${info.reason}): ${info.message}`);
    self.postMessage({ kind: "device-lost", reason: info.reason, message: info.message });
  });
  return device;
};

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
