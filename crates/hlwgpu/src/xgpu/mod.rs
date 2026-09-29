//! Ash/HashLink adapter for xgpu's generated API.

#![allow(dead_code, non_snake_case, improper_ctypes_definitions, clippy::all)]

mod runtime;

mod handles {
    pub use xgpu_core::{kind_of, Slab};
}

mod types {
    pub use xgpu_core::Kind;
}

mod backend {
    include!(concat!(env!("OUT_DIR"), "/xgpu_backend/backend.rs"));
}

use runtime::{host, Buffer, BufferMut, Enum, ErrorKind, Future, NativeEnum, Rooted, Text};

include!(concat!(env!("OUT_DIR"), "/xgpu_hashlink.rs"));
