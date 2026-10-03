// A host for xgpu.wasm that is not Ash. It supplies what IMPORTS.md names and
// nothing else: a dylink loader, HashLink's allocation, rooting, string and
// exception ABI without a collector, Ash Future's hooks, and the browser
// hooks. It calls the generated primitives directly and checks what comes
// back. Prints PASS or FAIL <n> last.
//
// It runs in a worker: a synchronous xgpu call blocks on the mailbox with
// Atomics.wait, which a page's main thread may not do.

const print = (text) => postMessage({ kind: "line", text });
let failures = 0;
function check(ok, what) {
  print((ok ? "ok   " : "FAIL ") + what);
  if (!ok) failures++;
}

/** An exception a primitive threw through hl_throw, with its message. */
class HashLinkError extends Error {}

// -- the side module's own description ---------------------------------------

function reader(bytes) {
  let at = 0;
  return {
    get at() { return at; },
    set at(value) { at = value; },
    byte: () => bytes[at++],
    leb() {
      let result = 0, shift = 0, b;
      do {
        b = bytes[at++];
        result += (b & 0x7f) * 2 ** shift;
        shift += 7;
      } while (b & 0x80);
      return result;
    },
    name() {
      const n = this.leb();
      const text = new TextDecoder().decode(bytes.subarray(at, at + n));
      at += n;
      return text;
    },
  };
}

/** dylink.0's memory info: the data size and alignment, and the table size. */
function dylinkInfo(module) {
  const [section] = WebAssembly.Module.customSections(module, "dylink.0");
  if (!section) throw new Error("xgpu.wasm has no dylink.0 section: it is not a side module");
  const r = reader(new Uint8Array(section));
  while (r.at < section.byteLength) {
    const id = r.byte();
    const size = r.leb();
    const end = r.at + size;
    if (id === 1) {
      return { memorySize: r.leb(), memoryAlign: 2 ** r.leb(), tableSize: r.leb() };
    }
    r.at = end;
  }
  throw new Error("dylink.0 has no memory info");
}

/** The limits the module declares for its imported memory and table. */
function importLimits(bytes) {
  const r = reader(bytes);
  r.at = 8;
  const limits = {};
  const readLimits = () => {
    const flags = r.byte();
    const min = r.leb();
    const max = flags & 1 ? r.leb() : undefined;
    return { min, max, shared: (flags & 2) !== 0 };
  };
  while (r.at < bytes.length) {
    const id = r.byte();
    const size = r.leb();
    const end = r.at + size;
    if (id === 2) {
      for (let n = r.leb(); n > 0; n--) {
        r.name();
        const field = r.name();
        const kind = r.byte();
        if (kind === 0) r.leb();
        else if (kind === 1) { r.byte(); limits[field] = readLimits(); }
        else if (kind === 2) limits[field] = readLimits();
        else if (kind === 3) { r.byte(); r.byte(); }
        else throw new Error(`unknown import kind ${kind}`);
      }
      return limits;
    }
    r.at = end;
  }
  return limits;
}

// -- memory, without a collector ----------------------------------------------

const bytes = new Uint8Array(await (await fetch(new URL("./xgpu.wasm", import.meta.url))).arrayBuffer());
const module = await WebAssembly.compile(bytes);
const info = dylinkInfo(module);
const declared = importLimits(bytes);
if (!declared.memory?.shared) throw new Error("xgpu.wasm does not import shared memory");

const memory = new WebAssembly.Memory({
  initial: Math.max(declared.memory.min, 512),
  maximum: declared.memory.max,
  shared: true,
});
const u8 = () => new Uint8Array(memory.buffer);
const view = () => new DataView(memory.buffer);
const words = () => new Int32Array(memory.buffer);

// A bump allocator: each block has its size in the 16 bytes before it, and
// nothing is freed. Address 0 stays unused, so null is never a block.
let heap = 1024;
function alloc(size, align = 16) {
  const at = Math.ceil((heap + 16) / align) * align;
  heap = at + Math.max(size, 1);
  if (heap > memory.buffer.byteLength) {
    memory.grow(Math.ceil((heap - memory.buffer.byteLength) / 65536));
  }
  view().setUint32(at - 4, size, true);
  u8().fill(0, at, at + size);
  return at;
}
const sizeOf = (block) => view().getUint32(block - 4, true);

const STACK_SIZE = 1 << 20;
const stack = alloc(STACK_SIZE);
const memoryBase = alloc(info.memorySize, Math.max(info.memoryAlign, 16));

// HashLink's type objects. Nothing here looks inside one; only their
// addresses travel.
const HLT_ABSTRACT = alloc(64);
const HLT_BYTES = alloc(64);
const HLT_I32 = alloc(64);
const programData = { hlt_abstract: HLT_ABSTRACT };

const decoder = new TextDecoder();
const text = (at, len) => decoder.decode(u8().slice(at, at + len));
function cString(at) {
  const m = u8();
  let end = at;
  while (m[end]) end++;
  return text(at, end - at);
}
function utf16(at) {
  const v = view();
  let s = "";
  for (let p = at; ; p += 2) {
    const unit = v.getUint16(p, true);
    if (unit === 0) return s;
    s += String.fromCharCode(unit);
  }
}
/** A HashLink value made by hl_alloc_strbytes: a dynamic holding UTF-16. */
const message = (value) => (value ? utf16(view().getUint32(value + 8, true)) : "null");

/** A haxe.io.Bytes as HashLink lays it out: type, length, data. */
function hlBytes(data) {
  const at = alloc(data.length);
  u8().set(data, at);
  const object = alloc(12);
  const v = view();
  v.setUint32(object, HLT_BYTES, true);
  v.setInt32(object + 4, data.length, true);
  v.setUint32(object + 8, at, true);
  return object;
}
const bytesOf = (object) => {
  const v = view();
  const at = v.getUint32(object + 8, true);
  return u8().slice(at, at + v.getInt32(object + 4, true));
};

// -- Ash Future, and the browser hooks ----------------------------------------

const futures = new Map();
function settle(future, state, value) {
  const record = futures.get(future);
  if (!record || record.state !== "pending") return 0;
  record.state = state;
  record.value = value;
  return 1;
}

const watches = [];
// The word an agent bumps after each reply, to wake whoever sleeps on it.
const WAKE = alloc(4);

// -- loading ------------------------------------------------------------------

const table = new WebAssembly.Table({
  element: "anyfunc",
  initial: 1 + info.tableSize,
  maximum: declared.__indirect_function_table?.max,
});
const tableBase = 1;
const stackPointer = new WebAssembly.Global({ value: "i32", mutable: true }, stack + STACK_SIZE);

let streams = { 1: "", 2: "" };
function emit(fd, chunk) {
  streams[fd] = (streams[fd] ?? "") + chunk;
  const lines = streams[fd].split("\n");
  streams[fd] = lines.pop();
  for (const line of lines) print(`[${fd === 2 ? "stderr" : "stdout"}] ${line}`);
}

const env = {
  memory,
  __indirect_function_table: table,
  __stack_pointer: stackPointer,
  __memory_base: new WebAssembly.Global({ value: "i32", mutable: false }, memoryBase),
  __table_base: new WebAssembly.Global({ value: "i32", mutable: false }, tableBase),

  // libc, as the program would export it.
  malloc: (size) => alloc(size),
  free: () => {},
  realloc(block, size) {
    const moved = alloc(size);
    if (block) u8().copyWithin(moved, block, block + Math.min(sizeOf(block), size));
    return moved;
  },
  memcmp(a, b, n) {
    const m = u8();
    for (let i = 0; i < n; i++) if (m[a + i] !== m[b + i]) return m[a + i] - m[b + i];
    return 0;
  },
  strlen(at) {
    const m = u8();
    let end = at;
    while (m[end]) end++;
    return end - at;
  },
  getenv: () => 0,
  getcwd: () => 0,
  strerror_r(code, out, len) {
    if (len > 0) u8()[out] = 0;
    return 0;
  },
  write(fd, at, len) {
    emit(fd, text(at, len));
    return len;
  },
  writev(fd, iov, count) {
    let total = 0;
    for (let i = 0; i < count; i++) {
      const at = view().getUint32(iov + 8 * i, true);
      const len = view().getUint32(iov + 8 * i + 4, true);
      emit(fd, text(at, len));
      total += len;
    }
    return total;
  },
  abort() {
    throw new Error("xgpu.wasm aborted");
  },

  // HashLink's ABI. With no collector, rooting is a no-op.
  hl_gc_alloc_gen: (type, size) => alloc(size),
  hl_add_root: () => {},
  hl_remove_root: () => {},
  hl_alloc_bytes: (size) => alloc(size),
  hl_alloc_strbytes(format) {
    // No format directives: a message is used as written.
    const s = utf16(format);
    const units = alloc((s.length + 1) * 2);
    for (let i = 0; i < s.length; i++) view().setUint16(units + 2 * i, s.charCodeAt(i), true);
    const value = alloc(16);
    view().setUint32(value, HLT_BYTES, true);
    view().setUint32(value + 8, units, true);
    return value;
  },
  hlp_type_i32: () => HLT_I32,
  hlp_alloc_dynamic(type) {
    const value = alloc(16);
    view().setUint32(value, type, true);
    return value;
  },
  hl_throw(value) {
    throw new HashLinkError(message(value));
  },

  // Ash Future's.
  hlp_future_create() {
    const future = alloc(16);
    futures.set(future, { state: "pending" });
    return future;
  },
  hlp_future_resolve: (future, value) => settle(future, "resolved", value),
  hlp_future_reject: (future, value) => settle(future, "rejected", value),

  // The browser hooks.
  ash_host_agent(name, len, address) {
    postMessage({ kind: "agent", name: text(name, len), memory, address });
    return 1;
  },
  ash_host_watch(word, handler, context) {
    if (!word) return 0;
    watches.push({ word, seen: Atomics.load(words(), word >> 2), handler, context });
    return WAKE;
  },
};

// GOT entries start at zero and are filled once the module's exports exist.
const got = { "GOT.mem": {}, "GOT.func": {} };
for (const { module: from, name } of WebAssembly.Module.imports(module)) {
  if (from in got) got[from][name] = new WebAssembly.Global({ value: "i32", mutable: true }, 0);
}

// Instantiating runs __wasm_init_memory, which copies the data segments to
// memoryBase.
const instance = new WebAssembly.Instance(module, { env, ...got });
const exports = instance.exports;

const slots = new Map();
function tableIndex(fn) {
  if (!slots.has(fn)) {
    const index = table.grow(1);
    table.set(index, fn);
    slots.set(fn, index);
  }
  return slots.get(fn);
}
for (const [name, global] of Object.entries(got["GOT.mem"])) {
  const exported = exports[name];
  if (exported instanceof WebAssembly.Global) {
    // A side module's data symbol is relative to where its data was put.
    global.value = memoryBase + exported.value;
  } else if (name in programData) {
    global.value = programData[name];
  } else {
    throw new Error(`no data symbol ${name}`);
  }
}
for (const [name, global] of Object.entries(got["GOT.func"])) {
  if (typeof exports[name] !== "function") throw new Error(`no function ${name} to put in the table`);
  global.value = tableIndex(exports[name]);
}
exports.__wasm_apply_data_relocs?.();
exports.__wasm_call_ctors?.();

/**
 * A primitive's export, called as the program would. A throw unwinds the
 * module's frames without restoring its stack pointer, so the host does.
 */
function call(name, ...args) {
  const saved = stackPointer.value;
  try {
    return exports[name](...args);
  } catch (error) {
    stackPointer.value = saved;
    throw error;
  }
}

/** Runs the watch handlers whose word moved, as Ash's scheduler does when parked. */
function pollWatches() {
  for (const watch of watches) {
    const now = Atomics.load(words(), watch.word >> 2);
    if (now === watch.seen) continue;
    watch.seen = now;
    const saved = stackPointer.value;
    try {
      table.get(watch.handler)(watch.context);
    } finally {
      stackPointer.value = saved;
    }
  }
}

/** Waits for `future` to settle, sleeping on the wake word between replies. */
async function settled(future, seconds = 30) {
  const end = Date.now() + seconds * 1000;
  for (;;) {
    pollWatches();
    const record = futures.get(future);
    if (!record) throw new Error(`${future} is not a future this host made`);
    if (record.state !== "pending") return record;
    if (Date.now() > end) throw new Error("a future never settled");
    const waited = Atomics.waitAsync(words(), WAKE >> 2, Atomics.load(words(), WAKE >> 2), 100);
    if (waited.async) await waited.value;
  }
}
const boxedInt = (value) => view().getInt32(value + 8, true);

// -- the checks ---------------------------------------------------------------

const MAP_READ = 1, COPY_SRC = 4, COPY_DST = 8, READ = 1, HIGH_PERFORMANCE = 1;

try {
  const signature = alloc(4);
  const index = exports.hlp_gpu_instance_new(signature);
  check(table.get(index) === exports.__hl_gpu_instance_new && cString(view().getUint32(signature, true)) === "P_i",
    "a DEFINE_PRIM resolver hands back its primitive and signature: " + cString(view().getUint32(signature, true)));

  const gpu = call("__hl_gpu_instance_new");
  check(gpu !== 0, "an instance, which starts the gpu agent");

  const adapterAsked = await settled(call("__hl_gpu_instance_request_adapter", gpu, HIGH_PERFORMANCE));
  check(adapterAsked.state === "resolved", "an adapter, asked for asynchronously");
  const adapter = boxedInt(adapterAsked.value);
  const deviceAsked = await settled(call("__hl_gpu_adapter_request_device", adapter));
  check(deviceAsked.state === "resolved", "a device, asked for asynchronously");
  const device = boxedInt(deviceAsked.value);
  const queue = call("__hl_gpu_device_queue", device);

  const descriptor = call("__hl_gpu_buffer_descriptor_new", 16n, MAP_READ | COPY_DST);
  const buffer = call("__hl_gpu_device_create_buffer", device, descriptor);
  check(buffer !== 0 && call("__hl_gpu_buffer_size", buffer) === 16n, "a buffer made from a descriptor record, 16 bytes");

  const written = Uint8Array.from({ length: 16 }, (_, i) => i * 3 + 1);
  call("__hl_gpu_queue_write_buffer", queue, buffer, 0n, hlBytes(written), 16);
  const mapped = await settled(call("__hl_gpu_device_map_buffer_with", device, buffer, READ, 0n, 16n));
  check(mapped.state === "resolved", "mapped for reading");
  const out = hlBytes(new Uint8Array(16));
  check(call("__hl_gpu_buffer_copy_out", buffer, 0n, out, 16) === 1, "copied out of the mapping");
  const read = bytesOf(out);
  check(read.every((b, i) => b === written[i]), "the bytes written are the bytes read back: " + read.join(","));
  call("__hl_gpu_buffer_unmap", buffer);

  let raised;
  try {
    call("__hl_gpu_buffer_copy_in", buffer, 0n, hlBytes(new Uint8Array(4)), -1);
  } catch (error) {
    raised = error;
  }
  check(raised instanceof HashLinkError, "a raised error reaches the caller through hl_throw: " + raised?.message);
  check(call("__hl_gpu_buffer_size", buffer) === 16n, "and the next call is answered");

  const unmappable = call("__hl_gpu_device_create_buffer", device,
    call("__hl_gpu_buffer_descriptor_new", 16n, COPY_DST | COPY_SRC));
  const refused = await settled(call("__hl_gpu_device_map_buffer_with", device, unmappable, READ, 0n, 16n));
  check(refused.state === "rejected", "a map the browser refuses rejects: " + message(refused.value));

  call("__hl_gpu_buffer_destroy", unmappable);
  call("__hl_gpu_buffer_destroy", buffer);
  call("__hl_gpu_device_destroy", device);
  call("__hl_gpu_adapter_destroy", adapter);
  call("__hl_gpu_instance_destroy", gpu);
  check(true, "buffers, the device, the adapter and the instance destroyed");
} catch (error) {
  check(false, `uncaught ${error?.stack ?? error}`);
}
print(failures === 0 ? "PASS" : `FAIL ${failures}`);
