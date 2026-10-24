fn main() {
    bosion::gather_to_env();
    // src/abi.rs is generated build output (not committed). Fail with the fix instead of "file not found for module".
    println!("cargo:rerun-if-changed=src/abi.rs");
    if !std::path::Path::new("src/abi.rs").exists() {
        panic!(
            "verdigris/ffi/src/abi.rs is missing: it is generated, not committed. Run \
             `bash tools/ci/gen_verdigris_bindings.sh` (or `tools/build/build.sh verdigris-bindings`) from the repo root, then build again."
        );
    }
}
