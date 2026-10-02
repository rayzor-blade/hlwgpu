// Loads a test page in Chrome over CDP, waits for the program's verdict, and
// prints what it wrote and what any of the page's workers logged. Exits 0
// on PASS.
//
//     node drive.mjs <page url> <debugging port> [seconds]
const [url, port, seconds = "90"] = process.argv.slice(2);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let target;
for (let i = 0; i < 150 && !target; i++) {
  try {
    const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
    target = list.find((t) => t.type === "page");
  } catch {}
  if (!target) await sleep(200);
}
if (!target) throw new Error("no page target");

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
let id = 0;
const pending = new Map();
const send = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
  const n = ++id;
  pending.set(n, { resolve, reject });
  ws.send(JSON.stringify({ id: n, method, params, sessionId }));
});
ws.onmessage = ({ data }) => {
  const msg = JSON.parse(data);
  if (msg.id && pending.has(msg.id)) {
    const { resolve, reject } = pending.get(msg.id);
    pending.delete(msg.id);
    if (msg.error) reject(new Error(JSON.stringify(msg.error)));
    else resolve(msg.result);
    return;
  }
  const where = msg.sessionId ? "worker" : "page";
  if (msg.method === "Target.attachedToTarget") {
    const sessionId = msg.params.sessionId;
    send("Runtime.enable", {}, sessionId).catch(() => {});
    send("Target.setAutoAttach", { autoAttach: true, waitForDebuggerOnStart: false, flatten: true }, sessionId).catch(() => {});
    send("Runtime.runIfWaitingForDebugger", {}, sessionId).catch(() => {});
  } else if (msg.method === "Runtime.consoleAPICalled") {
    const text = msg.params.args.map((a) => a.value ?? a.description).join(" ");
    console.log(`[${where} console.${msg.params.type}]`, text);
  } else if (msg.method === "Runtime.exceptionThrown") {
    const d = msg.params.exceptionDetails;
    console.log(`[${where} exception]`, d.exception?.description ?? d.text);
  }
};
const evaluate = async (expression) =>
  (await send("Runtime.evaluate", { expression, returnByValue: true })).result.value;
const out = () => evaluate("document.getElementById('out')?.textContent ?? ''");

await send("Runtime.enable");
await send("Page.enable");
await send("Target.setAutoAttach", { autoAttach: true, waitForDebuggerOnStart: false, flatten: true });
await send("Page.navigate", { url });

const end = Date.now() + Number(seconds) * 1000;
let text = "";
while (Date.now() < end) {
  text = await out();
  if (/^(PASS|FAIL \d+)$/m.test(text) || /trapped|exited|uncaught/.test(text)) break;
  await sleep(200);
}
console.log("---- program output ----");
console.log(text);
ws.close();
process.exit(/^PASS$/m.test(text) ? 0 : 1);
