//! HashLink carriers for xgpu's generated model: hl_xidl's, with errors
//! that say they are the GPU's.

pub use hl_xidl::*;

pub mod host {
    // The browser backend's; a native build has no use for them.
    #[allow(unused_imports)]
    pub use hl_xidl::host::{agent, watch};

    use hl_xidl::ErrorKind;

    pub fn raise(kind: ErrorKind, message: &str) {
        let prefix = match kind {
            ErrorKind::Type => "GPU type error: ",
            ErrorKind::Runtime => "GPU error: ",
        };
        hl_xidl::host::raise(kind, &format!("{prefix}{message}"));
    }
}
