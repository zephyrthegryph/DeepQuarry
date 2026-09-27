use std::{env, fs, path::PathBuf};

fn main() {
    println!("cargo:rerun-if-env-changed=DQ_VERDIGRIS_INPUT_HASH");
    let hash = env::var("DQ_VERDIGRIS_INPUT_HASH").unwrap_or_else(|_| "unverified".into());
    let marker = format!("VERDIGRIS_SOURCE_HASH:{hash}");
    let output = format!(
        "#[used]\n#[unsafe(no_mangle)]\npub static VERDIGRIS_BUILD_FINGERPRINT: [u8; {}] = *b\"{}\";\n",
        marker.len(), marker
    );
    let path = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR")).join("fingerprint.rs");
    fs::write(path, output).expect("write Verdigris build fingerprint");
}
