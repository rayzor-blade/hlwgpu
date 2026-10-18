// The Ash page imports this module after xgpu.wasm asks for the "gpu" agent.
// It owns the DOM canvas; the worker owns WebGPU and serves xgpu's mailbox.

let worker;

// `report(title, detail)`, when the page gives it, is how a failure of the GPU reaches the page's user.
export function start({ memory, address, canvas, report }) {
  if (worker) throw new Error("the GPU agent is already running");
  if (!canvas) throw new Error("the Ash page supplied no canvas");
  if (!(memory.buffer instanceof SharedArrayBuffer)) {
    throw new Error("xgpu requires shared WebAssembly memory");
  }

  const offscreen = canvas.transferControlToOffscreen();
  canvas.hidden = false;
  worker = new Worker(new URL("./gpu-worker.mjs", import.meta.url), {
    type: "module",
  });
  worker.onmessage = ({ data }) => {
    if (data.kind === "device-lost") report?.("The graphics device was lost", `${data.message || data.reason} Reload the page to draw again.`);
  };
  worker.postMessage({ memory, address, canvas: offscreen }, [offscreen]);
}
