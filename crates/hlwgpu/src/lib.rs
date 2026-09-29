//! WebGPU for HashLink.
//!
//! Natively this crate is `wgpu.hdll`: it holds the implementation and
//! the VM calls straight into it, so it loads in upstream HashLink too. Built
//! for wasm it is `xgpu.wasm`: an Ash-compatible side module whose primitives
//! send WebGPU commands to a runtime-owned browser agent. `IMPORTS.md` is the
//! host contract.
//!
//! Every side but the implementation comes from `wgpu.api`; see `build.rs`.

// wgpu's types nest deeply enough that proving `Slab<wgpu::Instance>: Send`
// overflows the default limit of 128.
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
#[thread_local]
static mut errno: i32 = 0;

#[cfg(not(target_family = "wasm"))]
mod bindings;
// Public: the host crate implementing the wasm imports reuses this.
#[cfg(not(target_family = "wasm"))]
pub mod handles;

#[cfg(feature = "native")]
mod imp;

/// The complete xgpu surface for Ash programs. The original `wgpu` package
/// remains available while applications migrate; both share wgpu but keep
/// independent handle tables so their ABI contracts cannot be confused.
mod xgpu;
