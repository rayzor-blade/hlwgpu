fn main() {
    hl_native_gen::generate_backend("wgpu.api").expect("generating the wgpu bindings");

    let out = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap());
    xgpu_backend::install_scoped(&out, "crate::xgpu").expect("installing the shared xgpu backend");
    let api = xgpu_bindgen::gpu_api();
    let model = xgpu_bindgen::generate_hashlink(&api, xgpu_bindgen::WEBGPU_IDL)
        .expect("generating the xgpu HashLink adapter");
    std::fs::write(out.join("xgpu_hashlink.rs"), model).expect("writing the xgpu adapter");
    let manifest = std::path::PathBuf::from(std::env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let haxe = manifest.join("../..").join("haxe");
    for file in xgpu_bindgen::haxe(xgpu_bindgen::haxe::Runtime::HashLink)
        .expect("generating the xgpu Haxe API")
    {
        let path = haxe.join(file.path);
        if std::fs::read_to_string(&path).ok().as_deref() != Some(file.source.as_str()) {
            std::fs::create_dir_all(path.parent().unwrap()).expect("creating the Haxe package");
            std::fs::write(path, file.source).expect("writing the xgpu Haxe API");
        }
    }

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
