//! A `.dm` file the `.dme` includes that did not exist when the model store was written is part of the model the next time it is read.
//! `analyze gen` meets this on a fresh tree: pass 1 parses a model while the generated files are missing, pass 2 runs after they were
//! written. The store lists only the files the preprocessor registered, so a file that was never registered has no key to differ.

use std::path::PathBuf;

use dq_analyze::run::{Engine, Options};

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf()
}

fn has_type(root: &std::path::Path, path: &str) -> bool {
    let opts = Options { root: root.to_path_buf(), lints: vec!["sem/keys".to_string()], scopes_from: Some(repo_root()), ..Default::default() };
    let engine = Engine::new(dq_analyze::run::registry(), opts).expect("engine");
    let sem = dq_analyze::sem::sem_for(&engine.tree).expect("model");
    let found = sem.ty(path).is_some();
    // The store writes its base on a side thread.
    dq_analyze::sem::model_store::finish();
    found
}

#[test]
fn an_included_file_that_appears_after_the_model_was_stored_is_in_the_next_model() {
    let base = std::env::temp_dir().join(format!("dq-model-appears-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&base);
    let root = base.join("tree");
    std::fs::create_dir_all(root.join("code")).unwrap();
    std::fs::create_dir_all(root.join("tools/ci")).unwrap();
    std::fs::copy(repo_root().join("tools/ci/lint_scopes.toml"), root.join("tools/ci/lint_scopes.toml")).unwrap();
    std::fs::write(root.join("code/a.dm"), "/obj/early\n\tvar/x = 1\n").unwrap();
    std::fs::write(root.join("deepquarry.dme"), "#include \"code/a.dm\"\n#include \"code/late.dm\"\n").unwrap();
    std::env::set_var("DQ_ANALYZE_CACHE", base.join("cache"));
    std::env::set_var("DQ_ANALYZE_SHARED_CACHE", "off");

    assert!(has_type(&root, "/obj/early"));
    assert!(!has_type(&root, "/obj/late"), "the file does not exist yet");
    std::fs::write(root.join("code/late.dm"), "/obj/late\n\tvar/y = 2\n").unwrap();
    assert!(has_type(&root, "/obj/late"), "the stored model was reused without the file that appeared");
    // And it is stable once stored.
    assert!(has_type(&root, "/obj/late"));
    let _ = std::fs::remove_dir_all(&base);
}
