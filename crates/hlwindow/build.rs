fn main() {
    hl_native_gen::generate("window.api").expect("generating the window bindings");

    println!("cargo:rerun-if-changed=build.rs");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        println!("cargo:rustc-cdylib-link-arg=-Wl,-undefined,dynamic_lookup");
    }
    // Nothing of the VM is called from here, so Windows needs no import
    // library: every symbol this defines, it defines.
}
