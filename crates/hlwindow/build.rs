//! xwindow's HashLink adapter: the generated model and primitives, the
//! backend for the target, the page's modules for a browser, and the Haxe
//! surface in `haxe/`.

use std::path::PathBuf;

use xwindow_bindgen::Runtime;

fn main() {
    let out = PathBuf::from(std::env::var_os("OUT_DIR").unwrap());
    xwindow_backend::install(&out).expect("installing the xwindow backend");
    let model = xwindow_bindgen::generate(Runtime::HashLink).expect("generating the window model");
    std::fs::write(out.join("window.rs"), model).expect("writing the window model");

    let wire = xwindow_bindgen::browser_wire().expect("generating the window wire");
    std::fs::write(out.join("window_wire.rs"), wire.rust).expect("writing the window wire");
    std::fs::write(out.join("page").join(xwindow_backend::WIRE_MODULE), &wire.js)
        .expect("writing the page's wire module");
    if std::env::var("CARGO_CFG_TARGET_FAMILY").as_deref() == Ok("wasm") {
        let backend = xwindow_bindgen::web_backend(Runtime::HashLink, xwindow_backend::WEB)
            .expect("generating the web backend");
        std::fs::write(out.join("window_web_backend.rs"), backend)
            .expect("writing the web backend");
    }

    let manifest = PathBuf::from(std::env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let haxe = manifest.join("haxe");
    for file in xwindow_bindgen::haxe(xwindow_bindgen::haxe::Runtime::HashLink)
        .expect("generating the window Haxe API")
    {
        let path = haxe.join(file.path);
        if std::fs::read_to_string(&path).ok().as_deref() != Some(file.source.as_str()) {
            std::fs::create_dir_all(path.parent().unwrap()).expect("creating the Haxe package");
            std::fs::write(path, file.source).expect("writing the window Haxe API");
        }
    }

    // The VM's own symbols are resolved when it loads the library, as for
    // hlwgpu: Apple's linker needs telling, and Windows links the VM's
    // import library from HL_LIB_DIR.
    println!("cargo:rerun-if-changed=build.rs");
    match std::env::var("CARGO_CFG_TARGET_VENDOR").as_deref() {
        Ok("apple") => println!("cargo:rustc-cdylib-link-arg=-Wl,-undefined,dynamic_lookup"),
        _ if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") => {
            println!("cargo:rerun-if-env-changed=HL_LIB_DIR");
            if let Ok(dir) = std::env::var("HL_LIB_DIR") {
                println!("cargo:rustc-link-search=native={dir}");
                println!("cargo:rustc-link-lib=dylib=libhl");
            }
        }
        _ => {}
    }
}
