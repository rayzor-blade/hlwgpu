//! Ash/HashLink adapter for xgpu's generated API.

#![allow(dead_code, non_snake_case, improper_ctypes_definitions, clippy::all)]

mod runtime;

mod handles {
    pub use xgpu_core::{Slab, kind_of};
}

mod types {
    pub use xgpu_core::Kind;
}

#[cfg(not(target_family = "wasm"))]
mod backend {
    include!(concat!(env!("OUT_DIR"), "/xgpu_backend/backend.rs"));
}

#[cfg(target_family = "wasm")]
mod wire {
    include!(concat!(env!("OUT_DIR"), "/xgpu_wire.rs"));
}

#[cfg(target_family = "wasm")]
mod web {
    include!(concat!(env!("OUT_DIR"), "/xgpu_web.rs"));
}

#[cfg(target_family = "wasm")]
mod backend {
    use super::*;
    include!(concat!(env!("OUT_DIR"), "/xgpu_web_backend.rs"));
}

use runtime::{Buffer, BufferMut, Enum, ErrorKind, Future, NativeEnum, Rooted, Text, host};

include!(concat!(env!("OUT_DIR"), "/xgpu_hashlink.rs"));
