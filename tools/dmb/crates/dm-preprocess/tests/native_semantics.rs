use dm_preprocess::{preprocess_project, SourceProvider};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

struct Memory(BTreeMap<PathBuf, String>);

impl SourceProvider for Memory {
    fn read(&self, path: &Path) -> Result<String, String> {
        self.0
            .get(path)
            .cloned()
            .ok_or_else(|| format!("missing {}", path.display()))
    }
}

// The fixture was compiled with BYOND 516.1687. Its native DMB contains
// `VALUE`, `preproc_ALIAS`, `preprocess_semantics.dm`, `conditional_yes`,
// `nested_yes`, and `defined_yes`.
#[test]
fn native_nested_macros_conditionals_and_locations() {
    let files = Memory(BTreeMap::from([
        (
            PathBuf::from("preprocess_semantics.dme"),
            include_str!("../../../fixtures/native_compiler/preprocess_semantics.dme").into(),
        ),
        (
            PathBuf::from("preprocess_semantics.dm"),
            include_str!("../../../fixtures/native_compiler/preprocess_semantics.dm").into(),
        ),
    ]));
    let output = preprocess_project(
        Path::new("preprocess_semantics.dme"),
        &files,
        &BTreeMap::new(),
    );
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert!(output.text.contains("var/preproc_ALIAS = 7"));
    assert!(output.text.contains("list(\"VALUE\", \"VALUE\", preproc_ALIAS, \"preprocess_semantics.dm\", 28, \"preprocess_semantics.dm\", 28, \"conditional_yes\", \"nested_yes\", \"defined_yes\")"));
}

#[test]
fn crlf_continuation_preserves_physical_line_number() {
    let files = Memory(BTreeMap::from([
        (PathBuf::from("game.dme"), "#include \"leaf.dm\"\r\n".into()),
        (
            PathBuf::from("leaf.dm"),
            "#define VALUE \\\r\n  __LINE__\r\n/obj/probe\r\n    line = VALUE\r\n".into(),
        ),
    ]));
    let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert!(output.text.contains("line = 4"), "{:?}", output.text);
}
