// Serves a directory with the cross-origin isolation SharedArrayBuffer needs.
//
//     node serve.mjs <directory> <port>
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";

const [root, port] = process.argv.slice(2);
const types = { ".html": "text/html", ".mjs": "text/javascript", ".js": "text/javascript", ".wasm": "application/wasm" };

createServer(async (request, response) => {
  const path = normalize(decodeURIComponent(new URL(request.url, "http://host").pathname));
  try {
    const body = await readFile(join(root, path === "/" ? "index.html" : path));
    response.writeHead(200, {
      "Content-Type": types[extname(path)] ?? "application/octet-stream",
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
    });
    response.end(body);
  } catch {
    response.writeHead(404).end();
  }
}).listen(Number(port), "127.0.0.1");
