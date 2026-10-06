//! WebGPU for HashLink.
//!
//! Natively this crate builds `xgpu.hdll`, which runs xgpu's wgpu backend.
//! For wasm it builds `xgpu.wasm`, an Ash-compatible side module whose
//! primitives send WebGPU commands to a runtime-owned browser agent.
//! `IMPORTS.md` is the host contract.

// The generated xgpu backend's wgpu types nest deeply enough to exceed the
// default recursion limit of 128.
#![recursion_limit = "256"]
#![allow(unsafe_op_in_unsafe_fn)]
#![cfg_attr(
    all(target_arch = "wasm32", target_feature = "atomics"),
    feature(stdarch_wasm_atomic_wait, thread_local)
)]

#[cfg(target_family = "wasm")]
#[global_allocator]
static ALLOCATOR: hl_abi::ProgramAllocator = hl_abi::ProgramAllocator;

// Rust's threaded WASI std addresses errno as TLS. A dylink side module
// cannot import a TLS datum, and this adapter performs no errno-reporting
// libc calls, so it owns the otherwise-unused slot.
#[cfg(target_family = "wasm")]
#[unsafe(no_mangle)]
#[cfg_attr(target_feature = "atomics", thread_local)]
static mut errno: i32 = 0;

/// Tells Ash's card-marking collector that this library stores a pointer to a
/// GC object into a GC object only through the runtime's functions, which mark
/// the card. Records keep bytes in hl_add_root slots in native memory, and
/// futures settle through hlp_future_resolve and hlp_future_reject.
#[unsafe(no_mangle)]
pub static ash_hdll_barrier_aware: u8 = 1;

/// The xgpu surface for Ash and HashLink programs.
mod xgpu;
