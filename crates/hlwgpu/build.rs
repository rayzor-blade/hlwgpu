fn main() {
    hl_native_gen::generate("wgpu.api").expect("generating the wgpu bindings");

    // `hlp_alloc_bytes` and its siblings belong to the VM and are resolved
    // when it loads this library. Unix tolerates that in a shared object; the
    // Apple linker calls it "Undefined symbols for architecture" unless told.
    println!("cargo:rerun-if-changed=build.rs");
    match std::env::var("CARGO_CFG_TARGET_VENDOR").as_deref() {
        // Every Apple target, not just macOS: iOS builds the same way, and
        // the linker there objects to an undefined symbol just as loudly.
        Ok("apple") => {
            println!("cargo:rustc-cdylib-link-arg=-Wl,-undefined,dynamic_lookup");
        }
        // MSVC will not leave a symbol undefined in a DLL, so on Windows the
        // library has to be linked against the VM's import library. Point
        // HL_LIB_DIR at the directory holding libhl.lib.
        _ if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") => {
            println!("cargo:rerun-if-env-changed=HL_LIB_DIR");
            if let Ok(dir) = std::env::var("HL_LIB_DIR") {
                println!("cargo:rustc-link-search=native={dir}");
                println!("cargo:rustc-link-lib=dylib=libhl");
            }
        }
        // Every other Unix leaves an undefined symbol in a shared object
        // alone, which is what an hdll wants.
        _ => {}
    }
}
