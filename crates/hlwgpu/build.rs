use std::{env::temp_dir, path::PathBuf};

fn gpu_decl(content: &str) -> Option<PathBuf> {
    // make file unique to avoid collisions with other tests
    let file_name = format!(
        "gpu.api.{}.rs",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_micros()
    );
    let path = temp_dir().join(file_name);
    std::fs::write(&path, content).ok()?;
    Some(path)
}


fn main() {
    let out = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap());
    xgpu_backend::install_scoped(&out, "crate::xgpu").expect("installing the shared xgpu backend");
    let api = xgpu_bindgen::gpu_api();
    let model = xgpu_bindgen::generate_hashlink(gpu_decl(&api), xgpu_bindgen::WEBGPU_IDL)
        .expect("generating the xgpu HashLink adapter");
    std::fs::write(out.join("xgpu_hashlink.rs"), model).expect("writing the xgpu adapter");

    let browser_idl = xgpu_bindgen::browser_idl();
    let wire = xgpu_bindgen::wire::wire(&browser_idl).expect("generating the xgpu browser wire");
    std::fs::write(out.join("xgpu_wire.rs"), wire.rust).expect("writing the xgpu browser wire");
    let scoped = |source: &str| {
        source
            .lines()
            .map(|line| {
                line.strip_prefix("//!")
                    .map_or(line.to_owned(), |doc| format!("//{doc}"))
            })
            .collect::<Vec<_>>()
            .join("\n")
            .replace("crate ::", "crate :: xgpu ::")
            .replace("crate::", "crate::xgpu::")
    };
    let web = scoped(xgpu_backend::WEB);
    std::fs::write(out.join("xgpu_web.rs"), web).expect("writing the xgpu web implementation");
    let web_backend =
        xgpu_bindgen::hashlink_web_backend("gpu", gpu_decl(&api), &browser_idl, xgpu_backend::WEB)
            .expect("generating the xgpu web backend");
    let web_backend = web_backend
        .lines()
        .map(|line| {
            line.strip_prefix("//!")
                .map_or(line.to_owned(), |doc| format!("//{doc}"))
        })
        .collect::<Vec<_>>()
        .join("\n")
        .replace("crate ::", "crate :: xgpu ::")
        .replace("crate::", "crate::xgpu::");
    std::fs::write(out.join("xgpu_web_backend.rs"), web_backend)
        .expect("writing the xgpu web backend");

    println!("cargo:rerun-if-env-changed=HLWGPU_WASM_JS_OUT");
    if let Some(js_out) = std::env::var_os("HLWGPU_WASM_JS_OUT") {
        let js_out = std::path::PathBuf::from(js_out);
        std::fs::create_dir_all(&js_out).expect("creating the wasm JavaScript output");
        std::fs::write(js_out.join("gpu-agent.mjs"), wire.js)
            .expect("writing the xgpu browser agent");
    }

    let manifest = std::path::PathBuf::from(std::env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let haxe = manifest.join("../..").join("haxe");
    for file in xgpu_bindgen::_haxe(xgpu_bindgen::haxe::Runtime::HashLink)
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
