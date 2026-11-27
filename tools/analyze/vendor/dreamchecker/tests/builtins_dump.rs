//! The builtin types, vars and procs the native checker starts from (`src/native/builtins.txt`) are SpacemanDMM's own table
//! (dreammaker's `builtins.rs`, read through its builtin object tree): this test rebuilds the text from it and requires the checked-in
//! file to be exactly that. `DQ_DC_BUILTINS_BLESS=1` writes it.

extern crate dreamchecker as dc;

#[test]
fn builtins_text_is_dreammakers_table() {
    let text = dc::native::builtins::dump_dreammaker();
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src/native/builtins.txt");
    if std::env::var_os("DQ_DC_BUILTINS_BLESS").is_some() {
        std::fs::write(&path, &text).unwrap();
    }
    let stored = std::fs::read_to_string(&path).unwrap().replace("\r\n", "\n");
    assert!(stored == text, "src/native/builtins.txt is not dreammaker's builtin table (DQ_DC_BUILTINS_BLESS=1 rewrites it)");
}
