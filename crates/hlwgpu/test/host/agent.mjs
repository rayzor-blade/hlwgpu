// xgpu's generated mailbox service with the one root a compute program needs.
import { start } from "./gpu-agent.mjs";

start(async () => {
  if (!navigator.gpu) throw new Error("this browser exposes no WebGPU");
  return new Map([[1, navigator.gpu]]);
});
